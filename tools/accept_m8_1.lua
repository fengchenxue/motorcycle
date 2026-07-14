--[[
NEON RUN — M8.1 增量落地 自动验收(Edit 仿真,固定 dt=1/60)
运行:MCP execute_luau(datamodel=Edit)或 Studio 命令栏粘贴。无需进 Play。
覆盖 design §E4 M8.1 验收清单:
  ① 最小点火:一次点按至少燃烧 0.4s(松键仍烧尾段)
  ② 0 能量按键=空箱反馈且速度不变(setSprintAllowed(false));emptyBox 每次按键只报一次
  ③ W+S 同按能量分毫不动(ADR-31⑤)
  ④ 燃尽帧数=273(回归:按住冲刺路径不被 min-ignition 改动)
  ⑤ 磁吸半径边界拾取(进 7 studs 捕获入账,7+ε 不)
  ⑥ 各入账路径正确:核 +25 / 闸门 +15 / 斩本体 +30 / 弹反 +25(坑 13:先压 energy 离上限)
  ⑦ AttackSystem 闸门集成:斩 Destructible → +15
  ⑧ 去接触擦墙回能:EnergyState 不再订阅 graze(擦碰纯惩罚)
坑 15:require 缓存跨调用存活 → 用 :Clone() 强制重编译新代码。
坑 7 :配置新字段先显式 SetAttribute(ConfigLive.get 优先读 attribute),绕开 require 缓存旧 flat。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local DT = 1 / 60

-- 显式补种 M8.1 新 Energy 属性(get 优先读 attribute,故即便 require 缓存旧 flat 也拿到新值)+ 清旧擦墙字段
local eInst = nr.Config.Energy
local SEED = { MinIgnitionBurnSec = 0.4, IgnitionCost = 0, CrystalMagnetRadius = 7, MoveRegenPerSec = 0, GateGain = 15 }
for k, v in pairs(SEED) do eInst:SetAttribute(k, v) end
for _, dead in ipairs({ "NearMissGain", "NearMissWindow" }) do eInst:SetAttribute(dead, nil) end

local EnergyState = require(nr.Modules.EnergyState:Clone())
local CrystalField = require(nr.Modules.CrystalField:Clone())
local AttackSystem = require(nr.Modules.AttackSystem:Clone())

-- ---- 断言框架 ----
local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log+1] = "  ✓ " .. name
	else fail += 1; log[#log+1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end

-- ---- Mock 控制器(EnergyState 只用 on/getTelemetry/setSprintAllowed/setForcedSprint)----
local function MockCtrl()
	local m = { _events = {}, sprintAllowed = true, forcedSprint = false,
		tel = { sprint = false, braking = false, speed = 100, grounded = true, wallContact = false } }
	function m:on(name, fn) self._events[name] = self._events[name] or {}; table.insert(self._events[name], fn) end
	function m:getTelemetry()
		return { sprint = self.tel.sprint, braking = self.tel.braking, speed = self.tel.speed,
			grounded = self.tel.grounded, wallContact = self.tel.wallContact,
			sprinting = (self.tel.sprint or self.forcedSprint) and self.sprintAllowed }
	end
	function m:setSprintAllowed(b) self.sprintAllowed = b ~= false end
	function m:setForcedSprint(b) self.forcedSprint = b == true end
	return m
end

-- ① 最小点火:满能量点按 1 帧后松开,应继续烧到 ~0.4s(0.4*22≈8.8),尾段 forcedSprint=true
do
	local c = MockCtrl(); local e = EnergyState.new(c)
	e.energy = 50
	local grazeSubs = c._events.graze and #c._events.graze or 0   -- ⑧ 顺带取样
	c.tel.sprint = true; e:step(DT)          -- 第 1 帧:按下点火
	c.tel.sprint = false                     -- 立刻松开
	local burned, forcedTail, frames = 0, false, 0
	local before = e.energy
	for _ = 1, 60 do
		e:step(DT); frames += 1
		if c.forcedSprint then forcedTail = true end
		if e.energy == before then break end  -- 已停止燃烧
		before = e.energy
	end
	burned = 50 - e.energy
	ok("① 最小点火:点按后续烧≈8.8(0.4s×22)", near(burned, 8.8, 0.5), burned)
	ok("① 尾段 forcedSprint 曾置真(维持冲刺速)", forcedTail, forcedTail)
	ok("⑧ EnergyState 不再订阅 graze(擦碰纯惩罚 ADR-23)", grazeSubs == 0, grazeSubs)
end

-- ② 空箱反馈 + 速度不变;emptyBox 每次按键只报一次
do
	local c = MockCtrl(); local e = EnergyState.new(c)
	e.energy = 0
	local empty = 0; e:on("emptyBox", function() empty += 1 end)
	c.tel.sprint = true
	for _ = 1, 10 do e:step(DT) end          -- 按住 10 帧
	ok("② 0 能量按键 emptyBox 只报一次", empty == 1, empty)
	ok("② 能量维持 0(不负)", e.energy == 0, e.energy)
	ok("② setSprintAllowed(false)=速度不变的地基", c.sprintAllowed == false, c.sprintAllowed)
	c.tel.sprint = false; e:step(DT)         -- 松开
	c.tel.sprint = true; e:step(DT)          -- 再按 → 再报一次
	ok("② 重新按键 emptyBox 再报", empty == 2, empty)
end

-- ③ W+S 同按能量分毫不动
do
	local c = MockCtrl(); local e = EnergyState.new(c)
	e.energy = 80
	c.tel.sprint = true; c.tel.braking = true
	for _ = 1, 120 do e:step(DT) end
	ok("③ W+S 同按 120 帧能量不变(=80)", e.energy == 80, e.energy)
end

-- ④ 燃尽帧数=273(按住冲刺,回归:min-ignition 不改按住路径)
do
	local c = MockCtrl(); local e = EnergyState.new(c)
	e.energy = 100
	c.tel.sprint = true; c.tel.speed = 135
	local flowSeen = false; e:on("flowStart", function() flowSeen = true end)
	local frames = 0
	while e.energy > 0 and frames < 400 do e:step(DT); frames += 1 end
	ok("④ 满槽燃尽帧数≈273(按住路径未变)", frames == 273, frames)
	ok("④ 满槽点燃即入心流", flowSeen, flowSeen)
	ok("④ 燃尽后心流熄灭", e.flow == false, e.flow)
end

-- ⑤ 磁吸半径边界拾取(7 内捕获,7+ε 不)
do
	local mk = function(pos)
		local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false
		p.Size = Vector3.new(2, 2, 2); p.Position = pos; p.Parent = workspace
		CS:AddTag(p, "EnergyCrystal"); return p
	end
	local bike = Vector3.new(0, 0, 0)
	local inCrys = mk(Vector3.new(7, 0, 0))       -- 恰 7:边界内(<=)
	local outCrys = mk(Vector3.new(7.5, 0, 0))    -- 7.5:边界外
	local hits = 0
	local field = CrystalField.new(function() hits += 1 end)
	field:step(bike, DT)
	ok("⑤ 距 7.0 捕获入账", hits == 1, hits)
	field:step(bike, DT)                          -- 再步:out 仍在外,in 已冷却
	ok("⑤ 距 7.5 不入账", hits == 1, hits)
	field:destroy(); inCrys:Destroy(); outCrys:Destroy()
end

-- ⑥ 入账路径数值:核 +25 / 闸门 +15 / 斩本体 +30 / 弹反 +25(每次从 20 起,避免撞上限)
do
	local c = MockCtrl(); local e = EnergyState.new(c)
	local function delta(fn) e.energy = 20; fn(e); return e.energy - 20 end
	ok("⑥ onCore +25", delta(function(x) x:onCore() end) == 25)
	ok("⑥ onGate +15", delta(function(x) x:onGate() end) == 15)
	ok("⑥ onSlash +30", delta(function(x) x:onSlash() end) == 30)
	ok("⑥ onParry +25", delta(function(x) x:onParry() end) == 25)
	-- 蓝区已满(CrystalCap=80):满则 capFull 且不加
	e.energy = 80; local capped = false; e:on("capFull", function() capped = true end)
	local d = e:addCrystal()
	ok("⑥ 水晶满 Cap 拒收(delta 0 + capFull)", d == 0 and capped, tostring(d) .. "/" .. tostring(capped))
end

-- ⑦ AttackSystem 闸门集成:Destructible 在盒内 → 斩得 +15
do
	local c = MockCtrl(); local e = EnergyState.new(c); e.energy = 20
	-- 需 ctrl.physPos/yaw 供盒判定;mock 补上
	c.physPos = Vector3.new(0, 0, 0); c.yaw = 0
	-- 先建件 + 打 Tag,再造 AttackSystem(靠初始 GetTagged 扫描注册,不依赖信号时序)
	local gate = Instance.new("Part"); gate.Anchored = true; gate.CanCollide = false
	gate.Size = Vector3.new(2, 2, 2); gate.Position = Vector3.new(0, 0, -5)  -- 车前 5 studs(盒前深 12 内)
	gate.Parent = workspace
	CS:AddTag(gate, "Destructible")
	local atk = AttackSystem.new(c, e, nil)   -- spline=nil:lint 跳过
	atk:step(DT)  -- 刷新遥测
	local res = atk:attack()
	ok("⑦ 斩闸门命中", res == "hit", res)
	ok("⑦ 闸门入账 +15(20→35)", e.energy == 35, e.energy)
	atk:destroy(); gate:Destroy()
end

-- ---- 汇总 ----
table.insert(log, 1, string.format("== M8.1 验收:%d 通过 / %d 失败 ==", pass, fail))
print(table.concat(log, "\n"))
return string.format("M8.1 accept: %d pass, %d fail", pass, fail)
