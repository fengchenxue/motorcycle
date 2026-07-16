-- NeonRun / ShooterField —— 路面远程敌 + 快照弹道(ADR-20/21/22 · design §4.6 v0.6)
-- 敌人物性(ADR-22 生死线):本体=无碰撞脚本对象(强制 CanCollide/CanTouch/CanQuery=false),
--   骑穿零惩罚,威胁全在子弹;本体可斩(+30,经 AttackSystem 注册)。永不做碰撞障碍。
-- 快照弹道(ADR-21):发射瞬间按玩家当帧位置+速度解算提前量,弹道定死永不追踪——
--   变速(冲刺/轻刹)与变线本身即闪避;空中(vy)不计入预测,起跳也是闪避。
-- 弹反(ADR-16/29):子弹作为 kind="parry" 注册进 AttackSystem;被斩=改写目标为射手,
--   以 ParryReflectSpeed 肉眼可见飞回,到达即击杀,+25 于击杀帧入账(ADR-29 杀敌回能:
--   演出高潮=奖励高潮;射手已死则零入账=纯防御,一个敌人永远只付一份能量)。
-- 反馈(ADR-20):命中玩家=减速一档(纯水平,零垂直速度),永不冻结画面/输入,不死。
-- 确定性:固定摆放(Tag: ShooterEnemy),状态机只由距离与计时驱动,R 重开 reset() 全重置。
-- 用法:
--   local field = ShooterField.new(ctrl, attack, energy)   -- attack=AttackSystem;energy=EnergyState(弹反击杀入账用)
--   field:step(dt)                                 -- 每帧(ctrl:step 后、attack:step 前)
--   field:reset()                                  -- R 重开:复活敌人/清空子弹/归零节拍
--   field:on("fired"|"playerHit"|"enemyKilled"|"telegraph", fn)
--   field:getTelemetry()                           -- { alive, bullets, incomingDist }
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")

local TAG = "ShooterEnemy"
local BULLET_COLOR = Color3.fromRGB(255, 60, 110)   -- 危险:品红
local PARRIED_COLOR = Color3.fromRGB(60, 255, 180)  -- 已弹反:青绿
local TELEGRAPH_COLOR = Color3.fromRGB(255, 255, 255)

local ShooterField = {}
ShooterField.__index = ShooterField

function ShooterField.new(ctrl, attack, energy)
	local self = setmetatable({}, ShooterField)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.ctrl = ctrl
	self.attack = attack
	self.energy = energy
	self.enemies = {}          -- [part] = { alive, phase = "idle"|"telegraph"|"cooldown", t, baseColor, baseTransparency }
	self.bullets = {}          -- array of { part, vel, life, parried, shooterPart }
	self._events = { fired = {}, playerHit = {}, enemyKilled = {}, telegraph = {} }
	self._conns = {}
	-- 子弹容器(运行期临时物,Edit 仿真后须清理)
	self.folder = Instance.new("Folder")
	self.folder.Name = "NeonRunBullets"
	self.folder.Parent = workspace
	for _, part in ipairs(CS:GetTagged(TAG)) do self:_registerEnemy(part) end
	table.insert(self._conns, CS:GetInstanceAddedSignal(TAG):Connect(function(p) self:_registerEnemy(p) end))
	table.insert(self._conns, CS:GetInstanceRemovedSignal(TAG):Connect(function(p) self.enemies[p] = nil end))
	return self
end

function ShooterField:on(name, fn)
	assert(self._events[name], "未知事件: " .. tostring(name))
	table.insert(self._events[name], fn); return fn
end
function ShooterField:_fire(name, p) for _, f in ipairs(self._events[name]) do task.spawn(f, p) end end

function ShooterField:_registerEnemy(part)
	if not part:IsA("BasePart") then return end
	-- 物性声明(ADR-22/28):本体强制无碰撞——不信任摆放,注册即矫正
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	local e = { alive = true, phase = "idle", t = 0, baseColor = part.Color, baseTransparency = part.Transparency }
	self.enemies[part] = e
	-- 本体可斩(+30):注册进斩击判定;revive 供 R 重开经 attack:reset() 复活
	if self.attack then
		self.attack:registerTarget(part, {
			kind = "slash",
			onHit = function(p) self:_killEnemy(p, "slash") end,
			revive = function(p) self:_reviveEnemy(p) end,
		})
	end
end

function ShooterField:_killEnemy(part, cause)
	local e = self.enemies[part]
	if not e or not e.alive then return end
	e.alive = false
	e.phase = "idle"; e.t = 0
	part.Transparency = 1
	part.Color = e.baseColor
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then d.Enabled = false end
	end
	if self.attack then self.attack:markDead(part) end
	-- ADR-29 杀敌回能:弹反的 +25 在此击杀帧入账(上方 alive 卫语句保证一个敌人只付一份;
	-- 已死射手的回飞弹到达会在卫语句处早退=零入账)
	if cause == "parryReturn" and self.energy then self.energy:onParry() end
	self:_fire("enemyKilled", { part = part, cause = cause })
end

function ShooterField:_reviveEnemy(part)
	local e = self.enemies[part]
	if not e then return end
	e.alive = true
	e.phase = "idle"; e.t = 0
	part.Transparency = e.baseTransparency
	part.Color = e.baseColor
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("PointLight") or d:IsA("SurfaceLight") or d:IsA("SpotLight") then d.Enabled = true end
	end
end

-- 快照提前量解算:恒速直线目标 × 恒速子弹的相遇时刻(取最小正根;无解退化为直指当前位置)
local function interceptDir(muzzle, targetPos, targetVel, bulletSpeed)
	local D = targetPos - muzzle
	local a = targetVel:Dot(targetVel) - bulletSpeed * bulletSpeed
	local b = 2 * D:Dot(targetVel)
	local c = D:Dot(D)
	local t
	if math.abs(a) < 1e-4 then
		if math.abs(b) > 1e-4 then t = -c / b end
	else
		local disc = b * b - 4 * a * c
		if disc >= 0 then
			local sq = math.sqrt(disc)
			local t1, t2 = (-b - sq) / (2 * a), (-b + sq) / (2 * a)
			t = math.min(t1 > 0 and t1 or math.huge, t2 > 0 and t2 or math.huge)
			if t == math.huge then t = nil end
		end
	end
	local aim = t and (targetPos + targetVel * t) or targetPos
	local dir = aim - muzzle
	return dir.Magnitude > 1e-3 and dir.Unit or Vector3.new(0, 0, -1)
end

function ShooterField:_spawnBullet(shooterPart)
	local C = self.cfg.get
	local yaw = self.ctrl.yaw
	local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local playerVel = look * (self.ctrl.curSpeed or 0)   -- 水平快照;vy 不计入=起跳即闪避
	local muzzle = shooterPart.Position
	local dir = interceptDir(muzzle, self.ctrl.physPos, playerVel, C("Combat", "BulletSpeed"))
	local p = Instance.new("Part")
	p.Name = "Bullet"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(2, 2, 2)
	p.Material = Enum.Material.Neon
	p.Color = BULLET_COLOR
	p.Anchored = true
	p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
	p.CFrame = CFrame.new(muzzle)
	p.Parent = self.folder
	local b = { part = p, vel = dir * C("Combat", "BulletSpeed"), life = C("Combat", "BulletLifeSec"), parried = false, shooterPart = shooterPart }
	table.insert(self.bullets, b)
	-- 子弹=可弹反脚本对象:被斩=改写目标为射手(ADR-16"弹反=改写其目标为射手")
	if self.attack then
		self.attack:registerTarget(p, {
			kind = "parry",
			onHit = function()
				b.parried = true
				b.life = C("Combat", "BulletLifeSec")   -- 回程重置寿命,保证飞得到
				local back = b.shooterPart.Position - b.part.Position
				b.vel = (back.Magnitude > 1e-3 and back.Unit or -b.vel.Unit) * C("Combat", "ParryReflectSpeed")
				p.Color = PARRIED_COLOR
			end,
		})
	end
	self:_fire("fired", { shooter = shooterPart, dir = dir })
end

function ShooterField:_despawnBullet(i)
	local b = table.remove(self.bullets, i)
	if not b then return end
	if self.attack then self.attack:unregisterTarget(b.part) end
	b.part:Destroy()
end

-- 线段(子弹上帧位置→本帧位置)到点的最近距离:高速子弹防隧穿命中判定
local function segmentDist(a, b, p)
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then return (p - a).Magnitude end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

function ShooterField:step(dt)
	local C = self.cfg.get
	local playerPos = self.ctrl.physPos
	local yaw = self.ctrl.yaw
	local look = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	local respawning = self.ctrl.isRespawning and self.ctrl:isRespawning() or false

	-- 敌人状态机:固定节拍,只由距离与计时驱动(确定性)
	for part, e in pairs(self.enemies) do
		if e.alive and part.Parent then
			if e.phase == "idle" then
				local rel = part.Position - playerPos
				-- 只对"尚在玩家前方"的目标开火:迎面弹=最可读弹道(ADR-22);骑过即沉默
				if not respawning and rel.Magnitude <= C("Combat", "ShooterRangeStuds") and rel:Dot(look) > 0 then
					e.phase = "telegraph"
					e.t = C("Combat", "ShooterTelegraphSec")
					part.Color = TELEGRAPH_COLOR   -- 充能预告(变白;强化演出由 CombatVFX 订阅 telegraph 事件,ADR-50)
					self:_fire("telegraph", { part = part })
				end
			elseif e.phase == "telegraph" then
				e.t -= dt
				if e.t <= 0 then
					part.Color = e.baseColor
					self:_spawnBullet(part)      -- 预告结束必发射(已充能承诺,确定性)
					e.phase = "cooldown"
					e.t = C("Combat", "ShooterFireIntervalSec")
				end
			elseif e.phase == "cooldown" then
				e.t -= dt
				if e.t <= 0 then e.phase = "idle"; e.t = 0 end
			end
		end
	end

	-- 子弹推进与命中(倒序遍历,安全移除)
	local radius = C("Combat", "BulletRadius")
	for i = #self.bullets, 1, -1 do
		local b = self.bullets[i]
		local prev = b.part.Position
		local now = prev + b.vel * dt
		b.part.CFrame = CFrame.new(now)
		b.life -= dt
		if b.parried then
			-- 回程:到达射手=击杀(演出兑现;能量已在弹反帧入账)
			if segmentDist(prev, now, b.shooterPart.Position) <= radius + 2 then
				self:_killEnemy(b.shooterPart, "parryReturn")
				self:_despawnBullet(i)
			elseif b.life <= 0 then
				self:_despawnBullet(i)
			end
		else
			local hit = segmentDist(prev, now, playerPos) <= radius
			if hit and not respawning then
				-- 命中在即:先给输入缓冲一次结算机会(按键优先于吃弹)
				if self.attack and self.attack.resolvePending then self.attack:resolvePending() end
			end
			if b.parried then
				-- 上面的 resolvePending 刚把这颗弹反掉了:本帧不再判命中
			elseif hit and not respawning then
				-- 减速一档:纯水平泄速,零垂直速度(ADR-28),不死不冻结(ADR-20)
				if self.ctrl.applySpeedMultiplier then
					self.ctrl:applySpeedMultiplier(C("Combat", "BulletHitSlowdown"))
				end
				self:_fire("playerHit", { pos = now })
				self:_despawnBullet(i)
			elseif b.life <= 0 then
				self:_despawnBullet(i)
			end
		end
	end
end

-- R 重开:敌人复活/子弹清空/节拍归零(敌人与机关确定性刷新断言点)
function ShooterField:reset()
	for i = #self.bullets, 1, -1 do self:_despawnBullet(i) end
	for part, _ in pairs(self.enemies) do
		if part.Parent then self:_reviveEnemy(part) end
	end
end

function ShooterField:getTelemetry()
	local alive, total = 0, 0
	for _, e in pairs(self.enemies) do
		total += 1
		if e.alive then alive += 1 end
	end
	local incoming = math.huge
	local playerPos = self.ctrl.physPos
	for _, b in ipairs(self.bullets) do
		if not b.parried then
			incoming = math.min(incoming, (b.part.Position - playerPos).Magnitude)
		end
	end
	return { alive = alive, total = total, bullets = #self.bullets, incomingDist = incoming }
end

function ShooterField:destroy()
	for i = #self.bullets, 1, -1 do self:_despawnBullet(i) end
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}; self.enemies = {}
	if self.folder then self.folder:Destroy(); self.folder = nil end
end

return ShooterField
