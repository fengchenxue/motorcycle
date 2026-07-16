-- NeonRun / BikeVFX (表现层) —— 碰撞火花 + 冲刺速度线(相机) + 冲刺尾焰/地面尾迹/底光(ADR-50a)
-- 火花:发射器直接挂在载具上(随车移动)。接触墙壁(擦墙/弹开/撞死滑行)时持续喷火花;
-- 0.3秒内没有再接触就停(linger 防抖,避免逐帧断触闪断)。bounce/hardHit 额外爆一簇。
-- 速度线:相机空间双层——Beam 放射线(屏心远→屏边近,贴图由远及近慢流)+ 风粒子掠过。
-- 由 tele.sprinting 驱动(与点火音效同源:含最小点火尾段,空能量按键不触发),
-- 开关走透明度淡入淡出(硬切 Enabled 贴图相位会跳)。参数=Handling VFX_* Attributes 实时调。
-- 冲刺三件(ADR-50a):尾焰喷口(车尾粒子射流)+地面尾迹(低位 Trail 光带)+车底霓虹光;
-- 均由 sprinting 驱动,心流(flowBoost)换金色=心流状态一眼可读("心流=胆量勋章"可视化)。
-- 只读 ctrl,不写物理。钉相机需在相机写完后调 cameraStep()(NeonRunTestDrive 的 rig:update 之后)。
local RS = game:GetService("ReplicatedStorage")

local BikeVFX = {}
BikeVFX.__index = BikeVFX

local LINGER = 0.3   -- 脱离接触后火花继续持续的秒数
local SPRINT_COLOR = Color3.fromRGB(0, 220, 255)   -- 冲刺:霓虹青(能量族)
local FLOW_COLOR = Color3.fromRGB(255, 200, 80)    -- 心流:金(胆量勋章)

-- 速度线贴图(手作参照:Workspace.VFX.Beam;换正式素材改这里)
local SPEEDLINE_TEXTURE = "rbxassetid://6967022163"
-- 放射线摆位(相机局部系,-Z=视线前方):{远端(靠屏心), 近端(冲出屏边)}
-- 四角 4 条 + 左右腰线 2 条,屏幕中心留空不挡车;加减线=改这张表
local SPEEDLINE_OFFSETS = {
	{ Vector3.new(-7, 4.5, -30), Vector3.new(-15, 9.5, -6) },
	{ Vector3.new(7, 4.5, -30), Vector3.new(15, 9.5, -6) },
	{ Vector3.new(-7, -4.5, -30), Vector3.new(-15, -9.5, -6) },
	{ Vector3.new(7, -4.5, -30), Vector3.new(15, -9.5, -6) },
	{ Vector3.new(-9, 0, -30), Vector3.new(-18, 0, -6) },
	{ Vector3.new(9, 0, -30), Vector3.new(18, 0, -6) },
}

local function makeEmitter(parent)
	local att = Instance.new("Attachment")
	att.Name = "BikeSparkFX"
	att.Position = Vector3.new(0, -1.2, 0)   -- 下移到车底附近,贴地火花
	att.Parent = parent

	local emit = Instance.new("ParticleEmitter")
	emit.Parent = att
	emit.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emit.Color = ColorSequence.new(Color3.fromRGB(255, 235, 150), Color3.fromRGB(255, 110, 20))
	emit.LightEmission = 1
	emit.LightInfluence = 0
	emit.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emit.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	emit.Lifetime = NumberRange.new(0.15, 0.35)
	emit.Speed = NumberRange.new(14, 32)
	emit.SpreadAngle = Vector2.new(45, 45)
	emit.Acceleration = Vector3.new(0, -80, 0)
	emit.Drag = 6
	emit.Rotation = NumberRange.new(0, 360)
	emit.Rate = 0
	emit.Enabled = false
	return emit
end

-- 速度线取景框:隐形锚定件,每帧钉到相机 CFrame,身上挂 Beam 放射线与风粒子
local function makeSpeedLineRig()
	local rig = Instance.new("Part")
	rig.Name = "SpeedLineRig"
	rig.Size = Vector3.new(0.1, 0.1, 0.1)
	rig.Transparency = 1
	rig.Anchored = true
	rig.CanCollide = false
	rig.CanQuery = false
	rig.CanTouch = false
	rig.CastShadow = false

	local beams = {}
	for _, o in ipairs(SPEEDLINE_OFFSETS) do
		local a0 = Instance.new("Attachment")
		a0.Position = o[1]
		a0.Parent = rig
		local a1 = Instance.new("Attachment")
		a1.Position = o[2]
		a1.Parent = rig
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = SPEEDLINE_TEXTURE
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new(1)
		beam.Enabled = true   -- 常开,可见性走透明度
		beam.Parent = rig
		table.insert(beams, beam)
	end

	-- 风粒子:前方 35 studs 朝镜头喷,VelocityParallel 顺速度拉成细线
	local att = Instance.new("Attachment")
	att.Name = "WindFX"
	att.Position = Vector3.new(0, 0, -35)
	att.Parent = rig
	local wind = Instance.new("ParticleEmitter")
	wind.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	wind.Orientation = Enum.ParticleOrientation.VelocityParallel
	wind.EmissionDirection = Enum.NormalId.Back   -- attachment 局部 +Z = 朝镜头
	wind.Size = NumberSequence.new(0.35)
	wind.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(0.8, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	wind.Lifetime = NumberRange.new(0.35, 0.55)
	wind.Speed = NumberRange.new(90, 105)         -- step 里按 Attribute 覆盖
	wind.SpreadAngle = Vector2.new(12, 12)        -- 散开让线从镜头两侧掠过
	wind.LightEmission = 1
	wind.LightInfluence = 0
	wind.Rate = 0                                 -- 开关走 Rate(随淡入系数)
	wind.Enabled = true
	wind.Parent = att

	return rig, beams, wind
end

-- 冲刺尾焰:车尾喷口射流(局部 +Z=车尾;短寿命拉成焰舌)
local function makeJet(rootPart)
	local att = Instance.new("Attachment")
	att.Name = "SprintJetFX"
	att.Position = Vector3.new(0, -0.6, 3.4)
	att.Parent = rootPart
	local jet = Instance.new("ParticleEmitter")
	jet.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	jet.Color = ColorSequence.new(SPRINT_COLOR)
	jet.LightEmission = 1
	jet.LightInfluence = 0
	jet.EmissionDirection = Enum.NormalId.Back
	jet.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	jet.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	jet.Lifetime = NumberRange.new(0.1, 0.2)
	jet.Speed = NumberRange.new(28, 44)
	jet.SpreadAngle = Vector2.new(8, 8)
	jet.Rate = 0
	jet.Enabled = true   -- 开关走 Rate
	jet.Parent = att
	return jet
end

-- 地面尾迹:车底低位 Trail 光带(冲刺时车后拖出能量残迹)
local function makeWake(rootPart)
	local a0 = Instance.new("Attachment"); a0.Name = "SprintWakeL"; a0.Position = Vector3.new(-0.9, -1.1, 2.6); a0.Parent = rootPart
	local a1 = Instance.new("Attachment"); a1.Name = "SprintWakeR"; a1.Position = Vector3.new(0.9, -1.1, 2.6); a1.Parent = rootPart
	local trail = Instance.new("Trail")
	trail.Name = "SprintWake"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(SPRINT_COLOR)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = rootPart
	return trail
end

function BikeVFX.new(model, ctrl)
	local self = setmetatable({}, BikeVFX)
	self.ctrl = ctrl
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	local inst = nr.Config.Handling
	self.cfg = ConfigLive.bind(inst, require(inst))
	self.emit = makeEmitter(model.PrimaryPart)
	self.sinceContact = math.huge   -- 距上次接触的时长;<LINGER 则持续喷
	self.rig, self.lineBeams, self.wind = makeSpeedLineRig()
	self.rig.Parent = workspace.CurrentCamera
	self.lineAlpha = 0     -- 速度线当前可见度 0~1(渐变)
	self.lineWritten = -1  -- 上次写入实例的可见度(-1=强制首写)
	-- 冲刺三件(ADR-50a)
	self.jet = makeJet(model.PrimaryPart)
	self.wake = makeWake(model.PrimaryPart)
	self.flowWritten = nil   -- 上次写入的心流态(nil=强制首写颜色)
	ctrl:on("bounce", function() self.emit:Emit(22) end)
	ctrl:on("hardHit", function() self.emit:Emit(40) end)
	return self
end

-- 每帧(主循环):火花接触检测 + 速度线淡入淡出与参数应用
function BikeVFX:step(dt)
	local t = self.ctrl:getTelemetry()
	-- 火花:接触墙壁(擦墙/弹开/撞死滑行)时重置计时并喷;脱离超过 LINGER 秒才停
	if t.wallContact or t.crashing then
		self.sinceContact = 0
	else
		self.sinceContact += dt
	end
	local on = self.sinceContact < LINGER
	self.emit.Rate = on and 120 or 0
	self.emit.Enabled = on

	-- 速度线:sprinting 淡入/淡出
	local C = self.cfg.get
	local target = t.sprinting and 1 or 0
	if self.lineAlpha ~= target then
		local fadeSec = target > self.lineAlpha and C("VFX", "SpeedLineFadeInSec")
			or C("VFX", "SpeedLineFadeOutSec")
		local move = dt / math.max(fadeSec, 1e-3)
		if target > self.lineAlpha then
			self.lineAlpha = math.min(self.lineAlpha + move, 1)
		else
			self.lineAlpha = math.max(self.lineAlpha - move, 0)
		end
	end
	-- 可见期间每帧写实例(属性面板调参实时生效);归零后补一笔即停写
	if self.lineAlpha > 0 or self.lineWritten ~= 0 then
		local a = self.lineAlpha * C("VFX", "SpeedLineMaxAlpha")
		local seq
		if a <= 0 then
			seq = NumberSequence.new(1)
		else
			local mid = 1 - a   -- 两端收口、中段实,线头线尾不生硬
			seq = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.25, mid),
				NumberSequenceKeypoint.new(0.75, mid),
				NumberSequenceKeypoint.new(1, 1),
			})
		end
		local w = C("VFX", "SpeedLineWidth")
		for _, b in ipairs(self.lineBeams) do
			b.Transparency = seq
			b.Width0, b.Width1 = w, w
			b.TextureSpeed = C("VFX", "SpeedLineFlowSpeed")
			b.TextureLength = C("VFX", "SpeedLineTexLen")
		end
		local spd = C("VFX", "SpeedLineParticleSpeed")
		self.wind.Speed = NumberRange.new(spd * 0.85, spd * 1.15)
		self.wind.Rate = C("VFX", "SpeedLineParticleRate") * self.lineAlpha
		self.lineWritten = self.lineAlpha
	end

	-- 冲刺二件(ADR-50a/50e:Underglow 已删):尾焰 Rate/尾迹开关随 sprinting,颜色随心流(仅变化帧写实例)
	local flow = t.flowBoost == true
	if flow ~= self.flowWritten then
		local col = flow and FLOW_COLOR or SPRINT_COLOR
		self.jet.Color = ColorSequence.new(col)
		self.wake.Color = ColorSequence.new(col)
		self.flowWritten = flow
	end
	local jetRate = C("VFX", "SprintJetRate")
	self.jet.Rate = (t.sprinting and jetRate or 0) * (flow and 1.4 or 1)
	local wakeSec = C("VFX", "SprintWakeSec")
	self.wake.Lifetime = math.max(wakeSec, 0)
	self.wake.Enabled = t.sprinting and wakeSec > 0
	-- (车底常亮 Underglow 已删=人类试玩裁决 2026-07-16:后端灯把地面照亮很怪)
end

-- 相机后置步:必须在相机写完之后调(NeonRunTestDrive 渲染循环 rig:update 之后),
-- 速度线同帧钉上视野,零滞后不抖;不可见时不跟(省写)
function BikeVFX:cameraStep()
	if self.lineAlpha <= 0 then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	if self.rig.Parent ~= cam then self.rig.Parent = cam end
	self.rig.CFrame = cam.CFrame
end

function BikeVFX:destroy()
	if self.emit then self.emit:Destroy() end
	if self.rig then self.rig:Destroy() end
	if self.jet then self.jet:Destroy() end
	if self.wake then self.wake:Destroy() end
end

return BikeVFX
