-- NeonRun / AttackSystem —— 单键攻击/弹反/破机关(M7 / ADR-8 / 策划案 §4.6§7)
-- 一键两味:斩击近战敌 / 弹反远程弹 / 破坏机关(能量闸门·捷径挡板·水晶),同一单键。
-- 铁律:自动锁定(零矄准)·时机判定·斩击点只在直线段(不与转向重叠)·全程可绕开(不按也能完赛)。
-- 命中=能量(onSlash+30/onParry+25)+毁目标+不减速;失误(窗口外按)=减速不死;不按=安全绕过。
-- Tag:SlashEnemy / ParryEnemy / Destructible。纯判定/表现层,能量由 EnergyState 权威。
-- 用法:
--   local atk = AttackSystem.new(ctrl, energy, spline)
--   atk:step(dt)                  -- 每帧(ctrl:step 后);维护锁定/窗口
--   local r = atk:attack()        -- 按键时调用 → "hit"|"miss"|"cooldown"
--   local t = atk:getTelemetry()  -- { locked, lockedType, inWindow, dist }
--   atk:on("hit", fn) / atk:on("miss", fn)
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")

local TYPE_TAGS = { SlashEnemy = "slash", ParryEnemy = "parry", Destructible = "destructible" }

local AttackSystem = {}
AttackSystem.__index = AttackSystem

function AttackSystem.new(ctrl, energy, spline)
	local self = setmetatable({}, AttackSystem)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.ctrl = ctrl
	self.energy = energy
	self.spline = spline
	self.cooldownT = 0
	self.locked = nil          -- 当前锁定目标 part
	self.lockedType = nil
	self.dist = math.huge
	self.inWindow = false
	self.targets = {}          -- [part] = { t = splineParam, kind = "slash"|..., dead = false, baseTransparency = n }
	self._events = { hit = {}, miss = {}, lock = {}, telegraph = {} }
	self._conns = {}
	for tag, kind in pairs(TYPE_TAGS) do
		for _, part in ipairs(CS:GetTagged(tag)) do self:_register(part, kind) end
		table.insert(self._conns, CS:GetInstanceAddedSignal(tag):Connect(function(p) self:_register(p, kind) end))
		table.insert(self._conns, CS:GetInstanceRemovedSignal(tag):Connect(function(p) self.targets[p] = nil end))
	end
	return self
end

-- 判定某样条参数处是否直线段(8studs 转角 < 阀值)
function AttackSystem:_isStraightAt(t)
	local C = self.cfg.get
	local look = self.spline.Length > 0 and (8 / self.spline.Length) or 0.004
	local tan1 = self.spline:GetTangent(t)
	local tan2 = self.spline:GetTangent((t + look) % 1)
	local ang = math.deg(math.acos(math.clamp(tan1:Dot(tan2), -1, 1)))
	return ang < C("Attack", "StraightMaxTurnDeg"), ang
end

function AttackSystem:_register(part, kind)
	if not part:IsA("BasePart") then return end
	local t = self.spline and select(1, self.spline:NearestPoint(part.Position)) or 0
	local straight, ang = self:_isStraightAt(t)
	if not straight then
		-- 铁律违反:斩击目标不在直线段——警告但仍注册(由布置验收捕捉)
		warn(string.format("[AttackSystem] 目标 %s 不在直线段(t=%.2f, 转角=%.1f°),违反 '斩击点只在直线段'", part.Name, t, ang))
	end
	self.targets[part] = { t = t, kind = kind, dead = false, baseTransparency = part.Transparency, straight = straight }
end

function AttackSystem:on(name, fn)
	assert(self._events[name], "未知事件: " .. tostring(name))
	table.insert(self._events[name], fn); return fn
end
function AttackSystem:_fire(name, p) for _, f in ipairs(self._events[name]) do task.spawn(f, p) end end

-- 沿前方向的环形弧长距离(目标必须在车前方才锁定)
function AttackSystem:_arcAhead(bikeT, targetT)
	local d = (targetT - bikeT) % 1        -- [0,1) 向前
	return d * self.spline.Length
end

function AttackSystem:step(dt)
	if self.cooldownT > 0 then self.cooldownT = math.max(0, self.cooldownT - dt) end
	local C = self.cfg.get
	local bikePos = self.ctrl.physPos
	if not bikePos or not self.spline then self.locked = nil; return end
	local bikeT = select(1, self.spline:NearestPoint(bikePos))
	local lockRange = C("Attack", "LockRangeStuds")

	-- 选前方最近的未死目标(弧长距离 ≤ LockRange)
	local best, bestKind, bestArc, bestEuclid = nil, nil, math.huge, math.huge
	for part, info in pairs(self.targets) do
		if part and part.Parent and not info.dead then
			local arc = self:_arcAhead(bikeT, info.t)
			if arc <= lockRange and arc < bestArc then
				best, bestKind, bestArc = part, info.kind, arc
				bestEuclid = (part.Position - bikePos).Magnitude
			end
		end
	end

	local prevLocked = self.locked
	self.locked = best
	self.lockedType = bestKind
	self.dist = best and bestEuclid or math.huge
	self.inWindow = best ~= nil and bestEuclid <= C("Attack", "HitWindowStuds")

	if best and best ~= prevLocked then
		self:_fire("lock", { part = best, kind = bestKind })
		self:_fire("telegraph", { part = best, kind = bestKind })  -- 音画预告
	end
end

-- 按键触发。命中→能量+毁目标+不减速;失误→减速;无目标/窗口外→miss。
function AttackSystem:attack()
	if self.cooldownT > 0 then return "cooldown" end
	local C = self.cfg.get
	self.cooldownT = C("Attack", "CooldownSec")
	if self.locked and self.inWindow then
		local info = self.targets[self.locked]
		info.dead = true
		-- 隐藏/禁用被毁目标
		self.locked.Transparency = 1
		if self.locked:FindFirstChildWhichIsA("PointLight") then self.locked:FindFirstChildWhichIsA("PointLight").Enabled = false end
		-- 按类型加能(危险渠道,显著高于水晶)
		if self.energy then
			if info.kind == "parry" then self.energy:onParry()
			else self.energy:onSlash() end  -- slash 与 destructible 同价(斩开机关=斩击)
		end
		local killed = self.locked
		self.locked = nil; self.inWindow = false
		self:_fire("hit", { part = killed, kind = info.kind })
		return "hit"
	else
		-- 失误:一次性减速(不死)
		if self.ctrl.applySpeedMultiplier then
			self.ctrl:applySpeedMultiplier(C("Attack", "MissSlowdown"))
		end
		self:_fire("miss", {})
		return "miss"
	end
end

function AttackSystem:getTelemetry()
	return { locked = self.locked ~= nil, lockedType = self.lockedType, inWindow = self.inWindow, dist = self.dist }
end

function AttackSystem:destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}; self.targets = {}
end

return AttackSystem