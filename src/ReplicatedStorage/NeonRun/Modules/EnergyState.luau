-- NeonRun / EnergyState —— 冲刺能量经济(M5 / ADR-9 / 策划案 §4.5)
-- 收入:保底=水晶(+CrystalGain,受 CrystalCap)/充能环 | 技巧=贴墙 +12/s、斩击/弹反/能量核/闸门(破 Cap)
-- 铁律:禁纯被动回能;水晶最多充到 CrystalCap,满槽最后一口必靠冒险;碰撞断心流;接触擦墙不回能(ADR-23)。
-- 职责分工:EnergyState 拥有能量数字 + 心流判定;通过 ctrl:setSprintAllowed 门控控制器。
-- 用法:
--   local energy = EnergyState.new(ctrl)   -- 自动订阅 hardHit/fell(碰撞坠落断心流)
--   energy:step(dt)                        -- 每帧在 ctrl:step 后
--   energy:addCrystal()                    -- 水晶拾取(受 CrystalCap;满则 fire capFull)
--   energy:onSlash()/onParry()/onCore()/onGate()  -- M7/M8.1 攻击命中入账
--   local t = energy:getTelemetry()        -- { energy, frac, flow, sprintGated, ready }
--   energy:on("ignite"|"emptyBox"|"capFull"|"gain"|"changed"|"flowStart"|"flowEnd", fn)
local RS = game:GetService("ReplicatedStorage")

local EnergyState = {}
EnergyState.__index = EnergyState

function EnergyState.new(ctrl)
	local self = setmetatable({}, EnergyState)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	local inst = nr.Config.Energy
	self.cfg = ConfigLive.bind(inst, require(inst))
	self.ctrl = ctrl
	local C = self.cfg.get
	self.max = C("Max")
	self.energy = math.clamp(C("StartEnergy"), 0, self.max)
	self.flow = false
	-- M8.1 最小点火(ADR-13):ignitionT>0=强制燃烧尾段(松键仍烧,直到烧满 MinIgnitionBurnSec 或能量耗尽)
	self.ignitionT = 0
	self._prevSprintLive = false   -- 上帧是否在燃烧(激活上升沿=一次点火承诺)
	self._prevIntent = false       -- 上帧是否按住冲刺(空箱/点火上升沿检测)
	self._events = { changed = {}, flowStart = {}, flowEnd = {}, gain = {}, ignite = {}, emptyBox = {}, capFull = {} }
	if ctrl and ctrl.on then
		-- 接触擦墙(graze)不再订阅:擦碰=纯惩罚不回能(ADR-23);贴墙 +12/s 见 step
		ctrl:on("hardHit", function() self:_breakFlow("collision") end)
		ctrl:on("fell", function() self:_breakFlow("fell") end)
		ctrl:on("respawned", function() self.ignitionT = 0 end)  -- 重生清空点火承诺
	end
	return self
end

function EnergyState:on(name, fn)
	assert(self._events[name], "未知事件: " .. tostring(name))
	table.insert(self._events[name], fn)
	return fn
end

function EnergyState:_fire(name, payload)
	for _, f in ipairs(self._events[name]) do task.spawn(f, payload) end
end

function EnergyState:_add(amount, source)
	if amount <= 0 then return end
	local before = self.energy
	self.energy = math.min(self.max, self.energy + amount)
	local delta = self.energy - before
	if delta > 0 then
		self:_fire("gain", { amount = delta, source = source })
		self:_fire("changed", { energy = self.energy, delta = delta })
	end
end

-- 水晶(保底):受 CrystalCap 约束——最多把能量充到 CrystalCap,不越;已超则不提升(不扣减)。
function EnergyState:addCrystal()
	local C = self.cfg.get
	local cap = C("CrystalCap")
	if self.energy >= cap then
		self:_fire("capFull", { cap = cap })  -- 蓝区已满:系统可拒绝但不能沉默(ADR-17;UI 出"蓝区已满"轻提示)
		return 0
	end
	local before = self.energy
	self.energy = math.min(cap, self.energy + C("CrystalGain"))
	local delta = self.energy - before
	if delta > 0 then
		self:_fire("gain", { amount = delta, source = "crystal" })
		self:_fire("changed", { energy = self.energy, delta = delta })
	end
	return delta
end

function EnergyState:onSlash() self:_add(self.cfg.get("SlashGain"), "slash") end
function EnergyState:onParry() self:_add(self.cfg.get("ParryGain"), "parry") end
function EnergyState:onCore() self:_add(self.cfg.get("CoreGain"), "core") end   -- 能量核(ADR-18,破 Cap)
function EnergyState:onGate() self:_add(self.cfg.get("GateGain"), "gate") end   -- 能量闸门 +15(斩开通行,交互矩阵 §4.6)
-- 接触擦墙回能(旧 _onGraze/NearMissGain)已删:擦碰=纯惩罚不回能(ADR-23);贴墙 +12/s 见 step

function EnergyState:_breakFlow(reason)
	if self.flow then
		self.flow = false
		self:_fire("flowEnd", { reason = reason })
	end
end

function EnergyState:getTelemetry()
	return {
		energy = self.energy,
		frac = self.energy / math.max(self.max, 1),
		flow = self.flow,
		sprintGated = self.energy <= 0,
		-- 满槽=点燃资格但尚未点燃(UI 出 READY 脉冲;ADR-31 表现层)
		ready = self.energy >= self.cfg.get("FlowThreshold") and not self.flow,
		igniting = self.ignitionT > 0,   -- 最小点火强制尾段(调试/表现用)
	}
end

function EnergyState:step(dt)
	local C = self.cfg.get
	local tel = self.ctrl and self.ctrl.getTelemetry and self.ctrl:getTelemetry() or {}
	local energyAtFrameStart = self.energy  -- 心流入场用帧初能量(本帧冲刺会立即排能,不应错过满槽入口)

	-- 持续技巧收入:贴墙(地面 + 壁接触 + 速度达阀)——防静止贴墙刷能
	local speed = tel.speed or 0
	if tel.wallContact and tel.grounded and speed >= C("WallRideMinSpeed") then
		self:_add(C("WallRideGainPerSec") * dt, "wallride")
	end
	-- 骑行涓流(AB 阀,默认 0=关):仅在地面且真实前进时给(禁静止回能 ADR-17);默认关则此块零效果
	local moveRegen = C("MoveRegenPerSec")
	if moveRegen and moveRegen > 0 and tel.grounded and speed > 1 then
		self:_add(moveRegen * dt, "move")
	end

	-- 冲刺意图 = 按住冲刺键且未刹车(刹车优先:ADR-7/ADR-31⑤ "W+S 同按能量分毫不动")
	local braking = tel.braking == true
	local intent = (tel.sprint == true) and not braking
	-- 本帧"想烧"=有意图且有能量(尚未含强制尾段)
	local canBurn = intent and self.energy > 0

	-- 最小点火(ADR-13):燃烧上升沿=一次激活 → 承诺至少烧满 MinIgnitionBurnSec;不足则烧完为止。
	-- 按住冲刺时每帧 canBurn 恒真、无新上升沿、forcedSprint 恒假 → 按住路径逐位不变(回归基准不动)。
	if canBurn and not self._prevSprintLive then
		self.ignitionT = C("MinIgnitionBurnSec")
		local cost = C("IgnitionCost")
		if cost and cost > 0 then
			local before = self.energy
			self.energy = math.max(0, self.energy - cost)
			if self.energy ~= before then self:_fire("changed", { energy = self.energy, delta = self.energy - before }) end
		end
		self:_fire("ignite", {})   -- 点火音画尖峰(ADR-31 表现层;UI/音效订阅)
	end
	if braking then self.ignitionT = 0 end                                   -- 刹车即中止点火承诺(是新抉择)
	if self.ignitionT > 0 then self.ignitionT = math.max(0, self.ignitionT - dt) end
	local forcedBurn = self.ignitionT > 0

	-- 空箱反馈(ADR-13):按下冲刺但无能量 → 干点火(系统可拒绝不能沉默;UI 咔哒+条闪红,速度不变)
	if intent and not self._prevIntent and self.energy <= 0 then
		self:_fire("emptyBox", {})
	end

	-- 冲刺实际生效 =(意图 或 强制尾段)且有能量且未刹车
	local sprintLive = (canBurn or forcedBurn) and self.energy > 0 and not braking
	-- 松键但仍在强制尾段时喂控制器 forcedSprint 维持冲刺速(按住时恒假=不干预控制器)
	if self.ctrl and self.ctrl.setForcedSprint then
		self.ctrl:setForcedSprint(forcedBurn and not canBurn)
	end

	-- 消耗:实际生效冲刺时才扣能
	if sprintLive then
		local before = self.energy
		self.energy = math.max(0, self.energy - C("SprintDrainPerSec") * dt)
		if self.energy ~= before then
			self:_fire("changed", { energy = self.energy, delta = self.energy - before })
		end
	end

	-- 能量门:空槽强制冲刺失效
	if self.ctrl and self.ctrl.setSprintAllowed then
		self.ctrl:setSprintAllowed(self.energy > 0)
	end

	-- 心流判定(ADR-30/31 严格兑现式):入场=帧初满槽 + 冲刺实际生效(空中亦可点燃);
	-- 保持=冲刺持续生效且能量未燃尽(FlowExitEnergy 默认 0=烧完整管,AB 60=状态式)。
	-- 断心流:松键/刹车(sprintLive 转 false 即熄,再进需重新满槽)/燃尽/碰撞坠落(hardHit/fell 订阅);
	-- 空中不断(ADR-30);吃弹擦墙不断(减速=浪费燃烧时间,惩罚自动折算)。
	-- 注:sprintLive 含最小点火尾段 → 尾段内心流延续到烧满 0.4s(点火承诺=进攻状态,非"松键即刻熄")。
	local flowThresh = C("FlowThreshold")
	local flowExit = C("FlowExitEnergy")
	if not self.flow then
		if energyAtFrameStart >= flowThresh and sprintLive then
			self.flow = true
			self:_fire("flowStart", {})
		end
	else
		if (not sprintLive) or self.energy <= 0 or self.energy < flowExit then
			self:_breakFlow("drop")
		end
	end

	self._prevSprintLive = sprintLive
	self._prevIntent = intent
end

-- R 重开:能量数值与心流全部归位(CLAUDE.md 铁律"R 重开全部重置";旧缺 reset 违反此律)。
-- 先熄心流(经 flowEnd 同步相机/控制器 flowBoost),再复位到开局能量并广播 changed 刷新 UI。
function EnergyState:reset()
	self:_breakFlow("restart")
	self.energy = math.clamp(self.cfg.get("StartEnergy"), 0, self.max)
	-- 清空最小点火承诺与边沿状态(R 全重置铁律)
	self.ignitionT = 0
	self._prevSprintLive = false
	self._prevIntent = false
	if self.ctrl and self.ctrl.setForcedSprint then self.ctrl:setForcedSprint(false) end
	self:_fire("changed", { energy = self.energy, delta = 0 })
end

function EnergyState:destroy() end

return EnergyState