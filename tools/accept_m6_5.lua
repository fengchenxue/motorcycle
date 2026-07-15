--[[
NEON RUN — M6.5 贴墙段 + 松键宽限 自动验收(Edit 仿真,固定 dt=1/60)
运行:MCP execute_luau(datamodel=Edit)或 Studio 命令栏粘贴。无需进 Play。
覆盖 design §E4 M6.5 验收清单(第 6/8 条全部自动项):
  ① 进出 100 次逐位一致(轨迹逐帧串比对)
  ② 墙态全程能量零变动:巡航=常量;冲刺=与平地流水逐位一致("贴墙就是平地跑");gain 事件=0
  ③ 空中进入(滞空跳向墙被磁吸,全程未落地)
  ④ 高位退出跳距对 jumptable 弹道模型:d = v·(vy+√(vy²+2gh))/g
  ⑤ 地面路径零改动:直线 400 帧 drift=0/airborne=0/maxVy=0;转向锚点 69.3/55.0/55.0(分母锚 135);
     坡顶起飞(正式场景在才跑,基准 flights=2/airborne=117/maxFlight=85/endPos(1500,-17.5,-538.2))
  ⑥ 三种退出:段尾弹道交接 / 驶下下缘回地(不撞不重生) / 上缘弹出(=④);墙上减速一档不退墙
  ⑦ R 全重置:墙态中重开 → 退墙+能量心流归位
  ⑧ 松键宽限(ADR-39):松 6 帧重按心流在 / 松 10 帧断 / 能量流水与无宽限版逐位一致 /
     刹车立即断不走宽限 / 满槽按住燃尽 273 帧回归(按住路径未变)
  ⑨ 心流跨墙不断(进入/墙上/弹出滞空/落地全程 flow=true)
  ⑩ 相机 up 参数化:入墙滚向墙法线(roll≤90°)/出墙回正/snap 复位
坑 15:require 缓存跨调用存活 → :Clone() 强制重编译。坑 7:新配置键先显式 SetAttribute。
测试台 NeonRunWallRig 建在 (-1800,200,-600) 区(坑 4:y≥200;距 CombatRig 600 studs)。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local DT = 1 / 60

-- ---- 配置补种(坑 7:attribute 优先于 require 缓存的旧 flat)----
local eInst = nr.Config.Energy
local hInst = nr.Config.Handling
eInst:SetAttribute("ReleaseGraceSec", 0.12)
for _, dead in ipairs({ "WallRideGainPerSec", "WallRideMinSpeed" }) do eInst:SetAttribute(dead, nil) end
local WALLCFG = {
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25,
}
for k, v in pairs(WALLCFG) do hInst:SetAttribute(k, v) end

local BikeController = require(nr.Modules.BikeController:Clone())
local EnergyState = require(nr.Modules.EnergyState:Clone())
local WallRideField = require(nr.Modules.WallRideField:Clone())
local CameraRig = require(nr.Modules.CameraRig:Clone())

-- ---- 断言框架 ----
local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end

-- ---- WallRig 测试台(Edit 期建,幂等;几何常驻可复用)----
local FLOOR_TOP = 200
local rig = workspace:FindFirstChild("NeonRunWallRig")
if not rig then
	rig = Instance.new("Folder"); rig.Name = "NeonRunWallRig"; rig.Parent = workspace
	local floor = Instance.new("Part")
	floor.Name = "Floor"; floor.Anchored = true; floor.Size = Vector3.new(260, 2, 800)
	floor.Position = Vector3.new(-1800, FLOOR_TOP - 1, -600)
	floor.Color = Color3.fromRGB(60, 65, 80); floor.Parent = rig
	local wall = Instance.new("Part")
	wall.Name = "Wall"; wall.Anchored = true; wall.Size = Vector3.new(2, 30, 700) -- 厚2 高30 长700(约定:±X=贴面,Z=切向)
	wall.Position = Vector3.new(-1769, FLOOR_TOP + 15, -600)                      -- 贴面 x=-1770,墙顶 y=230,z∈[-950,-250]
	wall.Color = Color3.fromRGB(0, 180, 220); wall.Parent = rig
	CS:AddTag(wall, "WallRideSurface")
end

-- ---- 测试摩托(最小模型,不动 Workspace.Motorcycle)----
local bikeModel = Instance.new("Model"); bikeModel.Name = "M65TestBike"
local rootPart = Instance.new("Part")
rootPart.Name = "BikeRoot"; rootPart.Size = Vector3.new(2, 2.5, 7)
rootPart.Anchored = true; rootPart.CanCollide = false; rootPart.CanQuery = false
rootPart.Transparency = 0.5; rootPart.Parent = bikeModel
bikeModel.PrimaryPart = rootPart; bikeModel.Parent = workspace

local HOVER = hInst:GetAttribute("Ground_HoverHeight") or 1.6
local GRAV = hInst:GetAttribute("Physics_Gravity") or 260
local S_ENTRY = CFrame.lookAt(Vector3.new(-1790, FLOOR_TOP + HOVER, -300), Vector3.new(-1790, FLOOR_TOP + HOVER, -400))
local S_STRAIGHT = CFrame.lookAt(Vector3.new(-1820, FLOOR_TOP + HOVER, -250), Vector3.new(-1820, FLOOR_TOP + HOVER, -350))

local ctrl = BikeController.new(bikeModel)
ctrl:setWallField(WallRideField.new())
local energy = EnergyState.new(ctrl)
energy:on("flowStart", function() ctrl:setFlowBoost(true) end)
energy:on("flowEnd", function() ctrl:setFlowBoost(false) end)

-- 标准驾驶循环:opts = { steerFn(f, st), sprint, frames, onFrame(f, tel, et) };st 由调用方读写
local function drive(opts)
	local st = { enteredAt = nil, exitedAt = nil }
	for f = 1, opts.frames do
		ctrl:setSteer(opts.steerFn and opts.steerFn(f, st) or 0)
		ctrl:setSprint(opts.sprint == true)
		ctrl:step(DT)
		energy:step(DT)
		local tel = ctrl:getTelemetry()
		if tel.wallRiding and not st.enteredAt then st.enteredAt = f end
		if st.enteredAt and not st.exitedAt and not tel.wallRiding then
			st.exitedAt = f
			ctrl.steer = 0; ctrl.rawSteer = 0 -- 出墙即回正:隔离高度带按键的 ramp-out 残留(空中转向)对弹道测量的污染
		end
		if opts.onFrame then opts.onFrame(f, tel, st) end
	end
	return st
end
-- 入墙→墙上巡航 10 帧→持续爬升(右墙 D=升)→上缘弹出→落地 的标准剧本
local function climbScript(f, st)
	if not st.enteredAt then return (f <= 12) and -1 or 0 end -- 先弯向墙(D=右转朝 +X)
	if not st.exitedAt then return (f >= st.enteredAt + 10) and -1 or 0 end
	return 0
end
local function reset(cf)
	ctrl:teleport(cf)
	energy:reset()
end

-- ① 进出 100 次逐位一致(顺带:墙态巡航能量常量 / wallContact=false / ④跳距 / ⑥上缘弹出)
do
	local firstTrace, mismatch = nil, 0
	local exitInfo, landInfo, energyConstBad, wallContactBad = nil, nil, 0, 0
	for run = 1, 100 do
		reset(S_ENTRY)
		local tr = {}
		local st = drive({ frames = 200, sprint = false, steerFn = climbScript,
			onFrame = function(f, tel, st2)
				tr[f] = string.format("%.17g,%.17g,%.17g", ctrl.physPos.X, ctrl.physPos.Y, ctrl.physPos.Z)
				if run == 1 then
					if tel.wallRiding then
						if energy.energy ~= 50 then energyConstBad += 1 end     -- 巡航上墙:能量必须纹丝不动
						if tel.wallContact then wallContactBad += 1 end          -- 墙态≠擦墙
					end
					if st2.exitedAt == f then exitInfo = { pos = ctrl.physPos, vy = ctrl.vy, speed = ctrl.curSpeed } end
					if st2.exitedAt and not landInfo and tel.grounded then landInfo = { pos = ctrl.physPos, f = f } end
				end
			end })
		local s = table.concat(tr, ";")
		if run == 1 then
			firstTrace = s
			ok("① 首跑完成进出(entered=" .. tostring(st.enteredAt) .. ", exited=" .. tostring(st.exitedAt) .. ")",
				st.enteredAt ~= nil and st.exitedAt ~= nil, "未入墙/未出墙")
		elseif s ~= firstTrace then
			mismatch += 1
		end
	end
	ok("① 进出 100 次轨迹逐位一致", mismatch == 0, mismatch .. " 次不一致")
	ok("② 墙态巡航能量零变动(=50)", energyConstBad == 0, energyConstBad .. " 帧变动")
	ok("② 墙态 wallContact=false(磁吸≠擦墙)", wallContactBad == 0, wallContactBad .. " 帧为真")
	-- ④ 高位退出跳距对弹道模型(上缘弹出=⑥之一)
	if exitInfo and landInfo then
		local h = exitInfo.pos.Y - landInfo.pos.Y
		local d = math.abs(landInfo.pos.Z - exitInfo.pos.Z)
		local expect = exitInfo.speed * (exitInfo.vy + math.sqrt(exitInfo.vy ^ 2 + 2 * GRAV * h)) / GRAV
		ok(string.format("④ 上缘弹出跳距≈弹道模型(实 %.1f / 模 %.1f, h=%.1f, vy=%.1f)", d, expect, h, exitInfo.vy),
			near(d, expect, 4), d)
		ok("④ 上缘弹出带高度带速率(vy>0)", exitInfo.vy > 1, exitInfo.vy)
	else
		ok("④ 上缘弹出+落地被记录", false, "exit/land 未记录")
	end
end

-- ② 补:冲刺上墙能量流水与平地逐位一致("贴墙就是平地跑");墙上 gain 事件=0
do
	local gains = 0
	local gh = energy:on("gain", function() gains += 1 end)
	-- 平地冲刺 60 帧流水(从能量 40 起)
	reset(S_STRAIGHT)
	drive({ frames = 30, sprint = true })  -- 预热(速度爬到 135)
	energy.energy = 40
	local groundLedger = {}
	drive({ frames = 60, sprint = true, onFrame = function(f) groundLedger[f] = energy.energy end })
	-- 上墙冲刺 60 帧流水(入墙后从能量 40 起)
	reset(S_ENTRY)
	local wallLedger, wallGainBase = {}, nil
	drive({ frames = 260, sprint = true, steerFn = function(f, st) -- 入墙后保持墙上巡航(不爬升,长墙不出段)
		if not st.enteredAt then return (f <= 12) and -1 or 0 end
		return 0
	end, onFrame = function(f, tel, st)
		if st.enteredAt then
			local k = f - st.enteredAt
			if k == 5 then energy.energy = 40; wallGainBase = gains end -- 入墙稳定后重置起点
			if k >= 6 and k <= 65 then wallLedger[k - 5] = energy.energy end
		end
	end })
	local same = #wallLedger == 60
	for i = 1, math.min(#wallLedger, 60) do
		if wallLedger[i] ~= groundLedger[i] then same = false break end
	end
	ok("② 冲刺上墙 60 帧能量流水与平地逐位一致", same, "流水不一致或帧数不足(" .. #wallLedger .. ")")
	ok("② 墙态期间 gain 事件=0(无任何墙收入)", wallGainBase ~= nil and gains == wallGainBase,
		tostring(wallGainBase) .. "→" .. tostring(gains))
end

-- ③ 空中进入:滞空斜向墙,被磁吸前全程未落地
do
	reset(CFrame.lookAt(Vector3.new(-1778, 216, -420), Vector3.new(-1778, 216, -420) + Vector3.new(0.2, 0, -1).Unit))
	local touchedGround, entered = false, nil
	drive({ frames = 60, sprint = false, onFrame = function(f, tel, st)
		if not st.enteredAt and tel.grounded and f > 1 then touchedGround = true end
		entered = st.enteredAt
	end })
	ok("③ 空中进入:滞空被磁吸(entered=" .. tostring(entered) .. ")", entered ~= nil, "未入墙")
	ok("③ 入墙前未落地(纯空中路径)", not touchedGround, "中途落地")
end

-- ⑤ 地面路径零改动:直线 400 帧(带 wallField 探测空转,墙在 50 studs 外)
do
	reset(S_STRAIGHT)
	local drift, airborneFrames, maxVy = 0, 0, 0
	drive({ frames = 400, sprint = false, onFrame = function(f, tel)
		drift = math.max(drift, math.abs(ctrl.physPos.X - (-1820)))
		if not tel.grounded then airborneFrames += 1 end
		maxVy = math.max(maxVy, math.abs(tel.vy or 0))
	end })
	ok("⑤ 直线 400 帧 drift=0", drift == 0, drift)
	ok("⑤ 直线 400 帧 airborne=0", airborneFrames == 0, airborneFrames)
	ok("⑤ 直线 400 帧 maxVy=0", maxVy == 0, maxVy)
end

-- ⑤ 转向角速度锚点(分母锚 135;验证 _steerRamp/_speedStep 抽取后逐位不变)
do
	local function turnRateAt(sprint, flow)
		reset(S_STRAIGHT)
		ctrl:setFlowBoost(flow == true)
		drive({ frames = 40, sprint = sprint })            -- 速度稳态
		drive({ frames = 9, sprint = sprint, steerFn = function() return 1 end }) -- steer 渐入(0.12s=7.2 帧)
		local y0 = ctrl.yaw
		drive({ frames = 30, sprint = sprint, steerFn = function() return 1 end })
		ctrl:setFlowBoost(false)
		energy:reset() -- 防冲刺间能量耗尽干扰后续
		return math.deg(ctrl.yaw - y0) / (30 * DT)
	end
	local r100 = turnRateAt(false, false)
	local r135 = turnRateAt(true, false)
	local r146 = turnRateAt(true, true)
	ok(string.format("⑤ 100 速转向≈69.3°/s(实 %.1f)", r100), near(r100, 69.3, 0.6), r100)
	ok(string.format("⑤ 135 速转向≈55.0°/s(实 %.1f)", r135), near(r135, 55.0, 0.6), r135)
	ok(string.format("⑤ 146 心流转向≈55.0°/s 不再降(实 %.1f)", r146), near(r146, 55.0, 0.6), r146)
end

-- ⑤ 坡顶起飞回归(需正式场景沙丘;缺则 SKIP——回归以带 Studio 会话复跑为准)
do
	local sceneHit = workspace:Raycast(Vector3.new(1500, 210, 130), Vector3.new(0, -60, 0))
	if sceneHit then
		reset(CFrame.lookAt(Vector3.new(1500, 202.6, 130), Vector3.new(1500, 202.6, 30)))
		local flights, airborne, maxFlight, cur, prevG, landed = 0, 0, 0, 0, true, false
		for f = 1, 1200 do
			ctrl:setSteer(0); ctrl:setSprint(true)
			ctrl:step(DT)
			local g = ctrl.grounded
			if not g then airborne += 1; cur += 1; maxFlight = math.max(maxFlight, cur) end
			if g and not prevG then
				if cur > 3 then flights += 1 end
				cur = 0
				if flights >= 2 then landed = true break end
			end
			prevG = g
		end
		ok("⑤ 坡顶:flights=2 且落地", flights == 2 and landed, flights .. "/" .. tostring(landed))
		ok("⑤ 坡顶:airborne=117", airborne == 117, airborne)
		ok("⑤ 坡顶:maxFlight=85", maxFlight == 85, maxFlight)
		local e = ctrl.physPos
		ok(string.format("⑤ 坡顶:endPos≈(1500,-17.5,-538.2) 实(%.1f,%.1f,%.1f)", e.X, e.Y, e.Z),
			near(e.X, 1500, 0.5) and near(e.Y, -17.5, 0.5) and near(e.Z, -538.2, 0.5), tostring(e))
	else
		log[#log + 1] = "  ○ ⑤ 坡顶起飞:SKIP(本场景无沙丘;带正式场景会话复跑)"
	end
end

-- ⑥ 段尾弹道交接 + 墙上减速一档不退墙 + 下缘回地
do
	-- 段尾:入墙后平骑到 z<-950 出段,顺滑落地不撞不重生
	reset(S_ENTRY)
	local resets0 = ctrl.resetCount
	local exitZ, landedAfterEnd = nil, false
	local st = drive({ frames = 460, sprint = true, steerFn = function(f, st2)
		if not st2.enteredAt then return (f <= 12) and -1 or 0 end
		return 0
	end, onFrame = function(f, tel, st2)
		-- 墙上中段:吃弹减速一档(applySpeedMultiplier),断言不退墙
		if st2.enteredAt and f == st2.enteredAt + 60 then ctrl:applySpeedMultiplier(0.75) end
		if st2.exitedAt == f then exitZ = ctrl.physPos.Z end
		if st2.exitedAt and tel.grounded then landedAfterEnd = true end
	end })
	ok("⑥ 段尾弹道交接(出段 z≈-950,实 " .. tostring(exitZ and math.floor(exitZ) or "nil") .. ")",
		exitZ ~= nil and near(exitZ, -950, 4), exitZ)
	ok("⑥ 段尾交接后顺滑落地", landedAfterEnd, landedAfterEnd)
	ok("⑥ 全程无硬撞/重生(resetCount 不变)", ctrl.resetCount == resets0, ctrl.resetCount - resets0)
	ok("⑥ 墙上减速一档未退墙(exited 晚于减速帧)", st.enteredAt and st.exitedAt and st.exitedAt > st.enteredAt + 60,
		tostring(st.exitedAt))

	-- 下缘回地:入墙后压 A(右墙 A=降)驶下下缘,数帧内落地续骑
	reset(S_ENTRY)
	resets0 = ctrl.resetCount
	local exitF, landF, reentered = nil, nil, false
	drive({ frames = 160, sprint = false, steerFn = function(f, st2)
		if not st2.enteredAt then return (f <= 12) and -1 or 0 end
		if not st2.exitedAt then return (f >= st2.enteredAt + 10) and 1 or 0 end
		return 0
	end, onFrame = function(f, tel, st2)
		exitF = st2.exitedAt
		if st2.exitedAt and not landF and tel.grounded then landF = f end
		if landF and tel.wallRiding then reentered = true end
	end })
	ok("⑥ 下缘回地:落地帧距出墙 ≤6 帧", exitF and landF and (landF - exitF) <= 6,
		tostring(exitF) .. "→" .. tostring(landF))
	ok("⑥ 下缘回地无硬撞/重生", ctrl.resetCount == resets0, ctrl.resetCount - resets0)
	ok("⑥ 回地后平行骑行不回吸(EnterTowardMinSpeed 拦截)", not reentered, reentered)
end

-- ⑦ R 全重置:墙态中重开 → 退墙 + 能量/心流归位
do
	reset(S_ENTRY)
	energy.energy = 100
	drive({ frames = 90, sprint = true, steerFn = climbScript }) -- 心流点燃+入墙
	local tel = ctrl:getTelemetry()
	ok("⑦ 前置:处于墙态(flow=" .. tostring(energy.flow) .. ")", tel.wallRiding, "未入墙")
	reset(S_ENTRY)  -- 等价 doRestart:teleport + energy:reset
	tel = ctrl:getTelemetry()
	ok("⑦ R 后退墙(wall=nil)", ctrl.wall == nil and not tel.wallRiding, tostring(ctrl.wall))
	ok("⑦ R 后能量=StartEnergy(50)", energy.energy == 50, energy.energy)
	ok("⑦ R 后心流熄/宽限清零", energy.flow == false and energy.graceT == 0,
		tostring(energy.flow) .. "/" .. tostring(energy.graceT))
end

-- ⑧ 松键宽限(ADR-39,Mock 时序;与真实控制器解耦)
do
	local function MockCtrl()
		local m = { _events = {}, sprintAllowed = true, forcedSprint = false,
			tel = { sprint = false, braking = false, speed = 135, grounded = true, wallContact = false } }
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
	-- 满槽点燃 → 按住 30 帧 → 松 N 帧 → 重按:N=6 心流在,N=10 断
	local function releaseTest(n)
		local c = MockCtrl(); local e = EnergyState.new(c)
		e.energy = 100
		c.tel.sprint = true
		for _ = 1, 30 do e:step(DT) end
		c.tel.sprint = false
		for _ = 1, n do e:step(DT) end
		c.tel.sprint = true
		e:step(DT)
		return e
	end
	ok("⑧ 松 6 帧(0.1s)重按:心流在", releaseTest(6).flow == true, "flow=false")
	ok("⑧ 松 10 帧(0.167s)重按:心流断", releaseTest(10).flow == false, "flow=true")
	-- 能量流水与无宽限版逐位一致(除 flow 标志):同剧本跑 grace=0.12 与 0
	local function ledgerRun(grace)
		eInst:SetAttribute("ReleaseGraceSec", grace)
		local c = MockCtrl(); local e = EnergyState.new(c)
		e.energy = 100
		local led, flows = {}, {}
		local script = function(f) return f <= 30 or f > 36 end  -- 按 30 / 松 6 / 重按至 90
		for f = 1, 90 do
			c.tel.sprint = script(f)
			e:step(DT)
			led[f] = e.energy; flows[f] = e.flow
		end
		return led, flows
	end
	local ledG, flowG = ledgerRun(0.12)
	local led0, flow0 = ledgerRun(0)
	eInst:SetAttribute("ReleaseGraceSec", 0.12)
	local ledSame, flowDiff = true, false
	for f = 1, 90 do
		if ledG[f] ~= led0[f] then ledSame = false end
		if flowG[f] ~= flow0[f] then flowDiff = true end
	end
	ok("⑧ 能量流水与无宽限版逐位一致", ledSame, "流水有分歧")
	ok("⑧ flow 标志两版确有差异(宽限生效的证据)", flowDiff, "flow 序列完全相同=宽限未生效")
	-- 刹车立即断,不走宽限
	do
		local c = MockCtrl(); local e = EnergyState.new(c)
		e.energy = 100; c.tel.sprint = true
		for _ = 1, 30 do e:step(DT) end
		c.tel.braking = true
		e:step(DT)
		ok("⑧ 心流中按刹车:立即断(无宽限)", e.flow == false, "flow=true")
	end
	-- 按住路径回归:满槽按住燃尽 273 帧(宽限不改按住路径)
	do
		local c = MockCtrl(); local e = EnergyState.new(c)
		e.energy = 100; c.tel.sprint = true
		local frames = 0
		while e.energy > 0 and frames < 400 do e:step(DT); frames += 1 end
		ok("⑧ 满槽按住燃尽=273 帧(回归)", frames == 273, frames)
	end
end

-- ⑨ 心流跨墙不断:点燃→入墙→墙上→上缘弹出滞空→落地,全程 flow=true
do
	reset(S_ENTRY)
	energy.energy = 100
	local flowBroke, sawWall, sawAirAfterExit, sawLand = false, false, false, false
	drive({ frames = 200, sprint = true, steerFn = climbScript, onFrame = function(f, tel, st)
		if st.enteredAt and not energy.flow then flowBroke = true end
		if tel.wallRiding then sawWall = true end
		if st.exitedAt and not tel.grounded then sawAirAfterExit = true end
		if st.exitedAt and tel.grounded then sawLand = true end
	end })
	ok("⑨ 全程经历 墙上→弹出滞空→落地", sawWall and sawAirAfterExit and sawLand,
		tostring(sawWall) .. "/" .. tostring(sawAirAfterExit) .. "/" .. tostring(sawLand))
	ok("⑨ 心流跨墙不断(进/滞空/出零熄火)", not flowBroke, "中途熄火")
end

-- ⑩ 相机 up 参数化:入墙滚向墙法线 / 出墙回正 / snap 复位(Edit 无相机实例,校验 upVec 状态)
do
	local rigCam = CameraRig.new(nil, ctrl)
	reset(S_ENTRY)
	rigCam:snap()
	local upAtWall, upAfter = nil, nil
	drive({ frames = 200, sprint = false, steerFn = climbScript, onFrame = function(f, tel, st)
		rigCam:update(DT)
		if st.enteredAt and f == st.enteredAt + 45 then upAtWall = rigCam.upVec end
		if st.exitedAt and f >= st.exitedAt + 60 then upAfter = rigCam.upVec end
	end })
	local n = Vector3.new(-1, 0, 0) -- 贴面外法线(面向赛道侧)
	ok("⑩ 入墙 45 帧后 up 滚向墙法线(dot>0.9)", upAtWall ~= nil and upAtWall:Dot(n) > 0.9,
		upAtWall and string.format("dot=%.2f", upAtWall:Dot(n)) or "nil")
	ok("⑩ 出墙落地后 up 回正(Y>0.99)", upAfter ~= nil and upAfter.Y > 0.99,
		upAfter and string.format("Y=%.2f", upAfter.Y) or "nil")
	rigCam:snap()
	ok("⑩ snap 后 up 立即复位世界 Y", rigCam.upVec == Vector3.yAxis, tostring(rigCam.upVec))
end

-- ---- 清理(测试摩托删;WallRig 几何常驻供人工试骑)----
bikeModel:Destroy()

table.insert(log, 1, string.format("== M6.5 验收:%d 通过 / %d 失败 ==", pass, fail))
print(table.concat(log, "\n"))
return string.format("M6.5 accept: %d pass, %d fail", pass, fail)
