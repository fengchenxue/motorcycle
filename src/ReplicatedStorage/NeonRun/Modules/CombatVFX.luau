-- NeonRun / CombatVFX (表现层) —— 斩击剑光 + 命中爆点 + 弹反闪光 + 敌人装饰 + 子弹拖尾(ADR-50)
-- 纯程序化(引擎内置贴图/内置音效,零外部资产=V1 灰盒不破);只读物理、只写渲染实例(物理与视觉分离)。
-- 剑光弧=判定窗可视化:出刀扫掠后以低透明度"留在外面",时长=Combat_InputBufferSec(机制与画面同一事实源);
--   命中=白闪(窗不收,可多段);空挥=灰化速灭。反馈永不冻结画面与输入(ADR-20)。
-- 敌人装饰=运行时挂在 ShooterEnemy 本体上的视觉子件(轨道卫星+悬浮盘+核心光):
--   本体判定/物性零改动(子件全 CanQuery/CanCollide/CanTouch=false);充能=转速×4+色带白→红;
--   死亡=爆点+子件隐藏;复活由轮询 part.Transparency 侦测(R 重开无独立事件)。
--   装饰在 step 内轮询补挂(信号 deferred 兜底,坑 26;赛道重建后自动重挂)。
-- 子弹装饰=Trail+光,颜色跟随弹体 Color(弹反变青由 ShooterField 改色,拖尾自动跟色)。
-- 拾取物装饰(ADR-50a)=水晶(EnergyCrystal:碎晶×2 环绕+光)/能量核(EnergyCore:卫星×4 环绕+光),
--   颜色自适应本体 part.Color;隐现随本体透明度轮询(水晶被拾=隐没沿爆一朵拾取爆点;核之死已由 hit 爆点覆盖不重爆);
--   磁吸飞入期装饰逐帧跟 part.Position=自动跟飞。
-- 音效=内置 rbxasset 占位(正式素材=官方音频库替换,BikeAudio 先例);音量走 Sound_* Attributes,0=静。
-- 用法:
--   local cvfx = CombatVFX.new(model, ctrl, attack, shooters)  -- shooters 可 nil(冒烟)
--   cvfx:step(dt)      -- 每帧(渲染节奏;attack/shooters step 之后)
--   cvfx:destroy()     -- 零残留
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")

local ENEMY_TAG = "ShooterEnemy"
local ARC_COLOR = Color3.fromRGB(90, 220, 255)      -- 剑光:霓虹青
local ARC_HIT_COLOR = Color3.fromRGB(255, 255, 255) -- 命中帧白闪
local ARC_WHIFF_COLOR = Color3.fromRGB(140, 150, 160) -- 空挥灰化
local PARRY_COLOR = Color3.fromRGB(60, 255, 180)    -- 弹反:青绿(与 ShooterField 弹反色一致)
local ENEMY_CORE_COLOR = Color3.fromRGB(255, 60, 110) -- 敌核:品红(与子弹同族)
local CHARGE_COLOR = Color3.fromRGB(255, 40, 40)    -- 充能末态:红

-- 内置占位音效(引擎自带,零许可风险;正式素材=Roblox 官方音频库替换,改这里)
local SFX = {
	Swing = "rbxasset://sounds/swordslash.wav",
	Hit = "rbxasset://sounds/swordlunge.wav",
	Parry = "rbxasset://sounds/electronicpingshort.wav",
}

local CombatVFX = {}
CombatVFX.__index = CombatVFX

local function mkPart(name, size, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.CastShadow = false
	return p
end

local function mkSound(parent, id)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 200
	s.Parent = parent
	return s
end

-- 剑光弧:车头前一条带弧度的 Beam,两端附件从中心向两侧张开=扫掠
local function makeArc(rootPart)
	local a0 = Instance.new("Attachment"); a0.Name = "SlashArcL"; a0.Parent = rootPart
	local a1 = Instance.new("Attachment"); a1.Name = "SlashArcR"; a1.Parent = rootPart
	local beam = Instance.new("Beam")
	beam.Name = "SlashArc"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(ARC_COLOR)
	beam.Transparency = NumberSequence.new(1)
	beam.Width0 = 0.9; beam.Width1 = 0.9
	beam.CurveSize0 = -4; beam.CurveSize1 = -4   -- 朝车前拱出新月弧
	beam.Enabled = true                           -- 常开,可见性走透明度(BikeVFX 同法)
	beam.Parent = rootPart
	return { a0 = a0, a1 = a1, beam = beam }
end

-- 命中爆点发射器模板(挂到一次性爆点件上)
local function mkBurstEmitter(parent, color)
	local emit = Instance.new("ParticleEmitter")
	emit.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emit.Color = ColorSequence.new(color, ARC_COLOR)
	emit.LightEmission = 1
	emit.LightInfluence = 0
	emit.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emit.Lifetime = NumberRange.new(0.2, 0.45)
	emit.Speed = NumberRange.new(24, 46)
	emit.SpreadAngle = Vector2.new(180, 180)
	emit.Drag = 5
	emit.Rate = 0
	emit.Enabled = false
	emit.Parent = parent
	return emit
end

function CombatVFX.new(model, ctrl, attack, shooters)
	local self = setmetatable({}, CombatVFX)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.ctrl = ctrl
	self.root = model.PrimaryPart
	self.arc = makeArc(self.root)
	self.arcState = "idle"      -- idle|active|fadeHit|fadeWhiff
	self.arcT = 0               -- 出刀以来时长
	self.arcWindow = 0          -- 本刀判定窗(出刀帧读定,窗尽转 fade)
	self.flashT = 0             -- 命中白闪余量
	self.fadeT = 0              -- fade 态余量
	self.bursts = {}            -- 一次性爆点件 { part, ttl, light }
	self.enemyFx = {}           -- [enemyPart] = { sats={}, disc, light, phase, charge, hidden }
	self.itemFx = {}            -- [itemPart] = { kind="crystal"|"core", shards={}, light, hidden, bobPhase }
	self.bulletFolder = shooters and shooters.folder or nil
	self.time = 0
	self._enemyScanT = 0
	self._conns = {}

	self.sounds = {
		swing = mkSound(self.root, SFX.Swing),
		hit = mkSound(self.root, SFX.Hit),
		parry = mkSound(self.root, SFX.Parry),
	}

	-- 攻击事件(AttackSystem):挥刀/命中/空挥/弹反
	if attack then
		attack:on("swing", function()
			self.arcState = "active"
			self.arcT = 0
			self.arcWindow = self.cfg.get("Combat", "InputBufferSec")
			self:_playSound("swing", self.cfg.get("Sound", "SlashVolume"))
		end)
		attack:on("hit", function(e)
			self.flashT = 0.08
			self:_playSound("hit", self.cfg.get("Sound", "HitVolume"))
			for _, part in ipairs(e.parts or {}) do
				if part:IsA("BasePart") then
					self:_burst(part.Position, part.Color)
					self:_magnetBeam(part.Position)
				end
			end
		end)
		attack:on("whiff", function()
			if self.arcState == "active" then
				self.arcState = "fadeWhiff"
				self.fadeT = 0.12
			end
		end)
		attack:on("parry", function()
			self.flashT = 0.1
			self:_playSound("parry", self.cfg.get("Sound", "ParryVolume"))
		end)
	end
	-- 射手事件(ShooterField):充能/开火/死亡
	if shooters then
		shooters:on("telegraph", function(e)
			local fx = self.enemyFx[e.part]
			if fx then fx.phase = "charge"; fx.charge = 0 end
		end)
		shooters:on("fired", function(e)
			local fx = self.enemyFx[e.shooter]
			if fx then
				fx.phase = "idle"; fx.charge = 0
				if fx.light then fx.light.Brightness = 12 end   -- 炮口闪,step 内衰减
			end
		end)
		shooters:on("enemyKilled", function(e)
			local fx = self.enemyFx[e.part]
			if fx then
				self:_burst(e.part.Position, ENEMY_CORE_COLOR)
				self:_hideEnemyFx(fx, true)
			end
		end)
	end
	return self
end

function CombatVFX:_playSound(name, vol)
	local s = self.sounds[name]
	if s and vol and vol > 0 then
		s.Volume = vol
		s:Play()
	end
end

-- 一次性爆点:霓虹碎片 + 光脉冲,ttl 到期销毁(step 内清理,冒烟可断言零残留)
function CombatVFX:_burst(pos, color)
	local C = self.cfg.get
	local n = C("VFX", "HitBurstParticles")
	if n <= 0 then return end
	local p = mkPart("CombatHitBurst", Vector3.new(0.2, 0.2, 0.2), color, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local emit = mkBurstEmitter(p, color)
	emit:Emit(n)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = C("VFX", "HitLightBrightness")
	light.Range = 18
	light.Parent = p
	table.insert(self.bursts, { part = p, ttl = 0.5, light = light })
end

-- 视觉磁吸:剑光末端向命中目标甩一道速消光带(物理零参与,观感=刀追着目标)
function CombatVFX:_magnetBeam(pos)
	local C = self.cfg.get
	local sec = C("VFX", "MagnetBeamSec")
	if sec <= 0 then return end
	local p = mkPart("CombatMagnetBeam", Vector3.new(0.2, 0.2, 0.2), ARC_COLOR, 1)
	p.CFrame = CFrame.new(pos)
	p.Parent = workspace
	local a0 = Instance.new("Attachment"); a0.Parent = self.root
	local a1 = Instance.new("Attachment"); a1.Parent = p
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0; beam.Attachment1 = a1
	beam.FaceCamera = true
	beam.LightEmission = 1; beam.LightInfluence = 0
	beam.Color = ColorSequence.new(ARC_HIT_COLOR, ARC_COLOR)
	beam.Width0 = 1.6; beam.Width1 = 0.3
	beam.Transparency = NumberSequence.new(0.1)
	beam.Parent = p
	table.insert(self.bursts, { part = p, ttl = sec, light = nil, homeAtt = a0 })
end

-- 敌人装饰:轨道卫星×3 + 悬浮盘 + 核心光(子件挂本体下,part 销毁即随葬;位置每帧绝对写)
function CombatVFX:_decorateEnemy(part)
	if self.enemyFx[part] then return end
	local fx = { sats = {}, phase = "idle", charge = 0, hidden = false, bobPhase = math.random() * 6.28 }
	for i = 1, 3 do
		local s = mkPart("EnemyFxSat", Vector3.new(0.55, 0.55, 0.55), ENEMY_CORE_COLOR, 0.1)
		s.Parent = part
		fx.sats[i] = s
	end
	local disc = mkPart("EnemyFxDisc", Vector3.new(0.4, 4.6, 4.6), ENEMY_CORE_COLOR, 0.45)
	disc.Shape = Enum.PartType.Cylinder
	disc.Parent = part
	fx.disc = disc
	local light = Instance.new("PointLight")
	light.Name = "EnemyFxLight"
	light.Color = ENEMY_CORE_COLOR
	light.Brightness = 2.5
	light.Range = 16
	light.Parent = part
	fx.light = light
	self.enemyFx[part] = fx
	if part.Transparency >= 0.9 then self:_hideEnemyFx(fx, true) end   -- 挂上时已死(重挂场景)
end

function CombatVFX:_hideEnemyFx(fx, hidden)
	fx.hidden = hidden
	for _, s in ipairs(fx.sats) do s.Transparency = hidden and 1 or 0.1 end
	if fx.disc then fx.disc.Transparency = hidden and 1 or 0.45 end
	-- 光交给 ShooterField 的 kill/revive 灯扫描统一开关(它遍历 descendants)
end

-- 拾取物装饰(ADR-50a):水晶=碎晶×2,核=卫星×4;颜色取本体色;初始位就位(spin=0 时为静态环)
function CombatVFX:_decorateItem(part, kind)
	if self.itemFx[part] then return end
	local n = kind == "crystal" and 2 or 4
	local sz = kind == "crystal" and 0.7 or 1.0
	local r = kind == "crystal" and 2.4 or 3.8
	local fx = { kind = kind, shards = {}, hidden = false, bobPhase = math.random() * 6.28, radius = r }
	for i = 1, n do
		local s = mkPart("ItemFxShard", Vector3.new(sz, sz * 1.6, sz), part.Color, 0.15)
		local ang = (i - 1) * (math.pi * 2 / n)
		s.CFrame = CFrame.new(part.Position + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r))
			* CFrame.Angles(math.rad(45), ang, math.rad(45))
		s.Parent = part
		fx.shards[i] = s
	end
	local light = Instance.new("PointLight")
	light.Name = "ItemFxLight"
	light.Color = part.Color
	light.Brightness = kind == "crystal" and 2 or 3
	light.Range = kind == "crystal" and 12 or 20
	light.Parent = part
	fx.light = light
	self.itemFx[part] = fx
	if part.Transparency >= 0.9 then self:_hideItemFx(fx, true) end
end

function CombatVFX:_hideItemFx(fx, hidden)
	fx.hidden = hidden
	for _, s in ipairs(fx.shards) do s.Transparency = hidden and 1 or 0.15 end
	-- 光:水晶由 CrystalField 的 PointLight 开关顺带管;兜底自己也切
	if fx.light then fx.light.Enabled = not hidden end
end

function CombatVFX:step(dt)
	local C = self.cfg.get
	self.time += dt

	-- ── 剑光弧状态机 ─────────────────────────────────────────────
	local arc = self.arc
	if self.arcState == "active" then
		self.arcT += dt
		local sweep = math.max(C("VFX", "SlashSweepSec"), 1e-3)
		local halfW = C("Combat", "HitboxSide") * C("VFX", "SlashWidthScale")
		local fwd = -C("Combat", "HitboxForward") * 0.55
		local k = math.clamp(self.arcT / sweep, 0.12, 1)   -- 中心张开到全宽
		arc.a0.Position = Vector3.new(-halfW * k, 0.8, fwd)
		arc.a1.Position = Vector3.new(halfW * k, 0.8, fwd)
		local alpha
		if self.arcT <= sweep then
			alpha = 1                                       -- 扫掠段全亮
		else
			alpha = C("VFX", "SlashHoldAlpha")              -- 持窗段低亮="刀留在外面"
		end
		if self.flashT > 0 then
			alpha = 1
			arc.beam.Color = ColorSequence.new(ARC_HIT_COLOR)
		else
			arc.beam.Color = ColorSequence.new(ARC_COLOR)
		end
		arc.beam.Transparency = NumberSequence.new(1 - alpha)
		if self.arcT >= self.arcWindow then                 -- 窗尽(命中与否都收刀)
			self.arcState = "fadeHit"
			self.fadeT = 0.1
		end
	elseif self.arcState == "fadeHit" or self.arcState == "fadeWhiff" then
		self.fadeT -= dt
		if self.arcState == "fadeWhiff" then
			arc.beam.Color = ColorSequence.new(ARC_WHIFF_COLOR)
		end
		local a = math.max(self.fadeT, 0) / 0.12
		arc.beam.Transparency = NumberSequence.new(1 - a * C("VFX", "SlashHoldAlpha"))
		if self.fadeT <= 0 then
			self.arcState = "idle"
			arc.beam.Transparency = NumberSequence.new(1)
		end
	end
	if self.flashT > 0 then self.flashT = math.max(0, self.flashT - dt) end

	-- ── 一次性爆点/磁吸光带清理 ──────────────────────────────────
	for i = #self.bursts, 1, -1 do
		local b = self.bursts[i]
		b.ttl -= dt
		if b.light then b.light.Brightness *= math.max(0, b.ttl / 0.5) end
		if b.ttl <= 0 then
			if b.homeAtt then b.homeAtt:Destroy() end
			b.part:Destroy()
			table.remove(self.bursts, i)
		end
	end

	-- ── 敌人装饰:轮询补挂(信号 deferred 兜底,坑 26)+ 动画 ─────────
	self._enemyScanT -= dt
	if self._enemyScanT <= 0 then
		self._enemyScanT = 0.5
		for _, part in ipairs(CS:GetTagged(ENEMY_TAG)) do
			if part:IsA("BasePart") and part.Parent then self:_decorateEnemy(part) end
		end
		for _, part in ipairs(CS:GetTagged("EnergyCrystal")) do
			if part:IsA("BasePart") and part.Parent then self:_decorateItem(part, "crystal") end
		end
		for _, part in ipairs(CS:GetTagged("EnergyCore")) do
			if part:IsA("BasePart") and part.Parent then self:_decorateItem(part, "core") end
		end
	end
	local spin = math.rad(C("VFX", "EnemySatSpinDeg"))
	local bobAmp = C("VFX", "EnemyBobStuds")
	for part, fx in pairs(self.enemyFx) do
		if not part.Parent then
			self.enemyFx[part] = nil
		else
			-- 复活侦测(R 重开无事件):本体回不透明即重现装饰
			if fx.hidden and part.Transparency < 0.9 then self:_hideEnemyFx(fx, false) end
			if not fx.hidden then
				local charging = fx.phase == "charge"
				if charging then fx.charge = math.min(fx.charge + dt / math.max(C("Combat", "ShooterTelegraphSec"), 1e-3), 1) end
				local rate = charging and spin * 4 or spin
				local bob = math.sin(self.time * 2 + fx.bobPhase) * bobAmp
				local center = part.Position + Vector3.new(0, bob, 0)
				local col = charging and ENEMY_CORE_COLOR:Lerp(CHARGE_COLOR, fx.charge) or ENEMY_CORE_COLOR
				for i, s in ipairs(fx.sats) do
					local ang = self.time * rate + (i - 1) * (math.pi * 2 / 3)
					s.CFrame = CFrame.new(center + Vector3.new(math.cos(ang) * 3.4, math.sin(ang * 1.7) * 0.9, math.sin(ang) * 3.4))
					s.Color = col
				end
				fx.disc.CFrame = CFrame.new(center) * CFrame.Angles(0, self.time * rate * 0.5, math.rad(90))
				fx.disc.Color = col
				if fx.light then
					fx.light.Color = col
					if fx.light.Brightness > 2.5 then
						fx.light.Brightness = math.max(2.5, fx.light.Brightness - dt * 40)   -- 炮口闪衰减
					elseif charging then
						fx.light.Brightness = 2.5 + fx.charge * 4
					else
						fx.light.Brightness = 2.5
					end
				end
			end
		end
	end

	-- ── 拾取物装饰:环绕/悬浮 + 隐现随本体(水晶被拾=隐没沿拾取爆点)──
	local bobItem = C("VFX", "ItemBobStuds")
	for part, fx in pairs(self.itemFx) do
		if not part.Parent then
			self.itemFx[part] = nil
		else
			local visible = part.Transparency < 0.9
			if fx.hidden and visible then
				self:_hideItemFx(fx, false)                       -- 复现(冷却结束/R 重开)
			elseif not fx.hidden and not visible then
				if fx.kind == "crystal" then self:_burst(part.Position, part.Color) end -- 拾取爆点(核之死已有 hit 爆点,不重爆)
				self:_hideItemFx(fx, true)
			end
			if not fx.hidden then
				local spinKey = fx.kind == "crystal" and "CrystalSpinDeg" or "CoreSpinDeg"
				local rate = math.rad(C("VFX", spinKey))
				if rate > 0 then                                  -- 0=静态装饰,省每帧写(移动端阀)
					local bob = math.sin(self.time * 2.4 + fx.bobPhase) * bobItem
					local center = part.Position + Vector3.new(0, bob, 0)
					local n = #fx.shards
					for i, s in ipairs(fx.shards) do
						local ang = self.time * rate + (i - 1) * (math.pi * 2 / n)
						s.CFrame = CFrame.new(center + Vector3.new(math.cos(ang) * fx.radius, math.sin(ang * 2) * 0.5, math.sin(ang) * fx.radius))
							* CFrame.Angles(math.rad(45), ang + self.time * rate, math.rad(45))
					end
				end
			end
		end
	end

	-- ── 子弹装饰:轮询补挂(ChildAdded deferred 兜底)──────────────
	if self.bulletFolder and self.bulletFolder.Parent then
		for _, p in ipairs(self.bulletFolder:GetChildren()) do
			if p:IsA("BasePart") and not p:FindFirstChild("CombatBulletFx") then
				local a0 = Instance.new("Attachment"); a0.Name = "CombatBulletFx"; a0.Position = Vector3.new(0, 0.8, 0); a0.Parent = p
				local a1 = Instance.new("Attachment"); a1.Name = "CombatBulletFxB"; a1.Position = Vector3.new(0, -0.8, 0); a1.Parent = p
				local trail = Instance.new("Trail")
				trail.Attachment0 = a0; trail.Attachment1 = a1
				trail.Lifetime = C("VFX", "BulletTrailSec")
				trail.LightEmission = 1; trail.LightInfluence = 0
				trail.Color = ColorSequence.new(p.Color)
				trail.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.1),
					NumberSequenceKeypoint.new(1, 1),
				})
				trail.WidthScale = NumberSequence.new(1)
				trail.FaceCamera = true
				trail.Parent = p
				local light = Instance.new("PointLight")
				light.Color = p.Color
				light.Brightness = 3
				light.Range = 12
				light.Parent = p
				-- 弹反变色(ShooterField 改 part.Color)→ 拖尾/光即时跟色;连接随 part 销毁自动断
				p:GetPropertyChangedSignal("Color"):Connect(function()
					trail.Color = ColorSequence.new(p.Color)
					light.Color = p.Color
				end)
			end
		end
	end
end

function CombatVFX:destroy()
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}
	for i = #self.bursts, 1, -1 do
		local b = self.bursts[i]
		if b.homeAtt then b.homeAtt:Destroy() end
		b.part:Destroy()
	end
	self.bursts = {}
	for part, fx in pairs(self.enemyFx) do
		for _, s in ipairs(fx.sats) do s:Destroy() end
		if fx.disc then fx.disc:Destroy() end
		if fx.light then fx.light:Destroy() end
	end
	self.enemyFx = {}
	for part, fx in pairs(self.itemFx) do
		for _, s in ipairs(fx.shards) do s:Destroy() end
		if fx.light then fx.light:Destroy() end
	end
	self.itemFx = {}
	if self.arc then
		self.arc.beam:Destroy(); self.arc.a0:Destroy(); self.arc.a1:Destroy()
		self.arc = nil
	end
	for _, s in pairs(self.sounds) do s:Destroy() end
	self.sounds = {}
end

return CombatVFX
