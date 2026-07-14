-- NeonRun / EnergyState —— 冲刺能量经济(M5 / ADR-9 / 策划案 §4.5)
-- 三档收入:保底=主线水晶(+CrystalGain,受 CrystalCap 约束) | 技巧=擦墙/贴墙/斩击/弹反(显著高于水晶)
-- 铁律:禁纯被动回能;水晶最多充到 CrystalCap,满槽最后一口必靠冒险;碰撞断心流。
-- 职责分工:EnergyState 拥有能量数字 + 心流判定;通过 ctrl:setSprintAllowed 门控控制器。
-- 用法:
--   local energy = EnergyState.new(ctrl)   -- 自动订阅 graze/hardHit/fell
--   energy:step(dt)                        -- 每帧在 ctrl:step 后
--   energy:addCrystal()                    -- 水晶拾取(受 CrystalCap)
--   energy:onSlash() / energy:onParry()    -- M7 攻击命中(预留)
--   local t = energy:getTelemetry()        -- { energy, frac, flow, sprintGated }
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
	self._events = { changed = {}, flowStart = {}, flowEnd = {}, gain = {} }
	if ctrl and ctrl.on then
		ctrl:on("graze", function(p) self:_onGraze(p) end)
		ctrl:on("hardHit", function() self:_breakFlow("collision") end)
		ctrl:on("fell", function() self:_breakFlow("fell") end)
		ctrl:on("respawned", function() end)
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
	if self.energy >= cap then return 0 end
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
function EnergyState:_onGraze(p) self:_add(self.cfg.get("NearMissGain"), "graze") end

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

	-- 冲刺实际生效=按着冲刺且未刹车(ADR-7"刹车优先且冲刺暂停不耗能",M2.1 基准"W+S 同按不耗能")
	local sprintLive = tel.sprinting and not tel.braking
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
	-- 断心流:松键/刹车(冲刺暂停即熄,再进需重新满槽)/燃尽/碰撞坠落(hardHit/fell 订阅);
	-- 空中不断(ADR-30);吃弹擦墙不断(减速=浪费燃烧时间,惩罚自动折算)。
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
end

function EnergyState:destroy() end

return EnergyState