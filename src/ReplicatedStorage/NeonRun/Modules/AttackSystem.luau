-- NeonRun / AttackSystem —— 斩击:车体局部空间盒查询(ADR-14/16/20 · design §4.6 v0.6)
-- 一键全程进攻:斩静态靶/远程敌本体/能量核,弹反子弹;同一刀结算体积内全部目标(多杀=关卡高光)。
-- 铁律:
--   · 判定=按键帧对注册目标做局部盒查询(前 HitboxForward/侧 ±HitboxSide/上下 ±HitboxUp/后 -HitboxBack),禁 Touched(ADR-16)
--   · 任何攻击永不减速;空挥代价只有 RecoverySec 硬直与错过能量(ADR-14)
--   · 反馈永不冻结画面与输入,无子弹时间/hitstop(ADR-20);剑光纯 VFX 由表现层订阅事件实现
--   · 窗口时长=盒深÷相对速度,随速自动收窄;InputBufferSec 提前按缓冲
--   · 斩击点只在直线段(注册期 lint 警告);墙不注册不判定(斩墙零收益,ADR-23)
-- 注册两路:CollectionService Tag(静态摆放:SlashEnemy/Destructible/EnergyCore)+ registerTarget API(运行时对象:子弹/射手本体,由 ShooterField 挂入)。
-- 能量入账统一走本模块(slash/core/parry → EnergyState),数字权威在 EnergyState。
-- 用法:
--   local atk = AttackSystem.new(ctrl, energy, spline)
--   atk:step(dt)                    -- 每帧(ctrl:step 后):缓冲结算/预告/遥测
--   atk:attack()                    -- 按键帧调用 → "hit"|"swing"|"recovery"(swing=已出刀,缓冲窗内仍可命中)
--   atk:registerTarget(part, { kind="slash"|"core"|"parry", onHit=fn, revive=fn })
--   atk:unregisterTarget(part)
--   atk:reset()                     -- R 重开:复活全部静态靶(带 revive 的走 revive)
--   atk:on("swing"|"hit"|"whiff"|"parry"|"telegraph", fn)
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")

-- 静态 Tag → 结算类型;ShooterEnemy 本体由 ShooterField 经 API 注册,不在此表
local TAG_KINDS = { SlashEnemy = "slash", Destructible = "slash", EnergyCore = "core" }

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
	self.recoveryT = 0         -- 出刀硬直(按键帧启动,命中与否同长)
	self.bufferT = 0           -- 输入缓冲余量(>0 时每帧重试结算)
	self.nearestDist = math.huge
	self.inVolume = false
	self.targets = {}          -- [part] = { kind, dead, onHit, revive, baseTransparency, telegraphed }
	self._events = { swing = {}, hit = {}, whiff = {}, parry = {}, telegraph = {} }
	self._conns = {}
	for tag, kind in pairs(TAG_KINDS) do
		for _, part in ipairs(CS:GetTagged(tag)) do self:_registerStatic(part, kind) end
		table.insert(self._conns, CS:GetInstanceAddedSignal(tag):Connect(function(p) self:_registerStatic(p, kind) end))
		table.insert(self._conns, CS:GetInstanceRemovedSignal(tag):Connect(function(p) self.targets[p] = nil end))
	end
	-- 旧 M7 Tag 兼容:ParryEnemy(静态弹反靶)已被真子弹取代(ADR-21/22),按 slash 靶保活并告警
	for _, part in ipairs(CS:GetTagged("ParryEnemy")) do
		warn("[AttackSystem] Tag 'ParryEnemy' 已废弃(弹反对象=子弹,ADR-21/22)," .. part.Name .. " 按 SlashEnemy 处理")
		self:_registerStatic(part, "slash")
	end
	return self
end

function AttackSystem:on(name, fn)
	assert(self._events[name], "未知事件: " .. tostring(name))
	table.insert(self._events[name], fn); return fn
end
function AttackSystem:_fire(name, p) for _, f in ipairs(self._events[name]) do task.spawn(f, p) end end

-- 布置 lint:斩击点只在直线段(8 studs 转角 < 阈值);违规只警告,由布置验收捕捉
function AttackSystem:_lintStraight(part)
	if not self.spline or self.spline.Length <= 0 then return end
	local t = select(1, self.spline:NearestPoint(part.Position))
	local look = 8 / self.spline.Length
	local tan1 = self.spline:GetTangent(t)
	local tan2 = self.spline:GetTangent((t + look) % 1)
	local ang = math.deg(math.acos(math.clamp(tan1:Dot(tan2), -1, 1)))
	if ang >= self.cfg.get("Combat", "StraightMaxTurnDeg") then
		warn(string.format("[AttackSystem] 目标 %s 不在直线段(t=%.2f, 转角=%.1f°),违反 '斩击点只在直线段'", part.Name, t, ang))
	end
end

function AttackSystem:_registerStatic(part, kind)
	if not part:IsA("BasePart") then return end
	self:_lintStraight(part)
	self.targets[part] = { kind = kind, dead = false, baseTransparency = part.Transparency, telegraphed = false }
end

-- 运行时对象注册(子弹/射手本体):onHit(part) 做领域处理(消散/击杀/改写目标),revive() 供 reset 复活
function AttackSystem:registerTarget(part, opts)
	self.targets[part] = {
		kind = opts.kind or "slash",
		dead = false,
		onHit = opts.onHit,
		revive = opts.revive,
		baseTransparency = part:IsA("BasePart") and part.Transparency or 0,
		telegraphed = false,
	}
end
function AttackSystem:unregisterTarget(part) self.targets[part] = nil end

-- 外部击杀入账(如弹反子弹飞回击杀射手):只改注册表状态,不给能量(能量已在弹反帧入账)
function AttackSystem:markDead(part)
	local info = self.targets[part]
	if info then info.dead = true end
end

-- 供 ShooterField 在"子弹即将命中玩家"帧先给缓冲一次结算机会(按键优先于吃弹,白送性质)
function AttackSystem:resolvePending()
	if self.bufferT > 0 then return self:_tryResolve() end
	return 0
end

-- 车体局部空间盒判定(物理真相系:physPos + yaw;roll/悬挂是视觉量,不参与)
function AttackSystem:_inHitbox(pos)
	local C = self.cfg.get
	local rel = pos - self.ctrl.physPos
	local yaw = self.ctrl.yaw
	local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local right = Vector3.new(math.cos(yaw), 0, -math.sin(yaw))
	local fwd = rel:Dot(look)
	return fwd <= C("Combat", "HitboxForward") and fwd >= -C("Combat", "HitboxBack")
		and math.abs(rel:Dot(right)) <= C("Combat", "HitboxSide")
		and math.abs(rel.Y) <= C("Combat", "HitboxUp")
end

-- 默认击毁表现:隐藏 + 关灯(灰盒;正式 VFX 由表现层订阅 hit 事件)
local function defaultKill(part)
	part.Transparency = 1
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then d.Enabled = false end
	end
end

-- 结算一次体积查询:命中体积内全部有效目标;返回命中数
function AttackSystem:_tryResolve()
	local hits = {}
	for part, info in pairs(self.targets) do
		if part.Parent and not info.dead and self:_inHitbox(part.Position) then
			table.insert(hits, part)
		end
	end
	if #hits == 0 then return 0 end
	local kinds = {}
	local parried = false
	for _, part in ipairs(hits) do
		local info = self.targets[part]
		info.dead = true
		if info.onHit then info.onHit(part) else defaultKill(part) end
		if self.energy then
			if info.kind == "parry" then self.energy:onParry()
			elseif info.kind == "core" then self.energy:onCore()
			elseif info.kind == "slash" then self.energy:onSlash() end
		end
		if info.kind == "parry" then parried = true end
		table.insert(kinds, info.kind)
	end
	self.bufferT = 0
	self:_fire("hit", { parts = hits, kinds = kinds, count = #hits })
	if parried then self:_fire("parry", {}) end
	return #hits
end

-- 按键帧:出刀。硬直中拒绝;否则立即查询,未中则留 InputBufferSec 缓冲逐帧重试。
-- 永不减速:本函数(及本模块)不触碰任何速度量(ADR-14 断言点)。
function AttackSystem:attack()
	if self.recoveryT > 0 then return "recovery" end
	local C = self.cfg.get
	self.recoveryT = C("Combat", "RecoverySec")
	self.bufferT = C("Combat", "InputBufferSec")
	self:_fire("swing", {})
	if self:_tryResolve() > 0 then return "hit" end
	return "swing"
end

function AttackSystem:step(dt)
	if self.recoveryT > 0 then self.recoveryT = math.max(0, self.recoveryT - dt) end
	-- 缓冲窗:提前按了但目标未进盒 → 后续帧目标进盒仍算命中;窗尽未中=空挥
	if self.bufferT > 0 then
		self.bufferT -= dt
		if self:_tryResolve() == 0 and self.bufferT <= 0 then
			self.bufferT = 0
			self:_fire("whiff", {})
		end
	end
	-- 预告与遥测:最近有效目标距离/是否有目标在盒内(HUD 十字用)
	local C = self.cfg.get
	local telegraphRange = C("Combat", "TelegraphRangeStuds")
	local bikePos = self.ctrl.physPos
	local nearest, inVol = math.huge, false
	for part, info in pairs(self.targets) do
		if part.Parent and not info.dead then
			local d = (part.Position - bikePos).Magnitude
			if d < nearest then nearest = d end
			if d <= telegraphRange and not info.telegraphed then
				info.telegraphed = true
				self:_fire("telegraph", { part = part, kind = info.kind })
			end
			if not inVol and self:_inHitbox(part.Position) then inVol = true end
		end
	end
	self.nearestDist = nearest
	self.inVolume = inVol
end

-- R 重开:全部目标重置(敌人与机关确定性刷新的验收断言点)
function AttackSystem:reset()
	self.recoveryT = 0
	self.bufferT = 0
	for part, info in pairs(self.targets) do
		if info.dead then
			if info.revive then
				info.revive(part)
			elseif part.Parent then
				part.Transparency = info.baseTransparency
				for _, d in ipairs(part:GetDescendants()) do
					if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then d.Enabled = true end
				end
			end
			info.dead = false
		end
		info.telegraphed = false
	end
end

function AttackSystem:getTelemetry()
	return {
		telegraph = self.nearestDist <= self.cfg.get("Combat", "TelegraphRangeStuds"),
		inVolume = self.inVolume,
		nearestDist = self.nearestDist,
		recovery = self.recoveryT > 0,
	}
end

function AttackSystem:destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}; self.targets = {}
end

return AttackSystem
