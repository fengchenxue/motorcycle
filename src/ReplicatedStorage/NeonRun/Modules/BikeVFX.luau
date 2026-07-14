-- NeonRun / BikeVFX (表现层) —— 碰撞火花
-- 火花发射器直接挂在载具上(随车移动)。接触墙壁(擦墙/弹开/撞死滑行)时持续喷火花;
-- 0.3秒内没有再接触就停(linger 防抖,避免逐帧断触闪断)。bounce/hardHit 额外爆一簇。
-- 只读 ctrl,不写物理。
local BikeVFX = {}
BikeVFX.__index = BikeVFX

local LINGER = 0.3   -- 脱离接触后火花继续持续的秒数

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

function BikeVFX.new(model, ctrl)
	local self = setmetatable({}, BikeVFX)
	self.ctrl = ctrl
	self.emit = makeEmitter(model.PrimaryPart)
	self.sinceContact = math.huge   -- 距上次接触的时长;<LINGER 则持续喷
	ctrl:on("bounce", function() self.emit:Emit(22) end)
	ctrl:on("hardHit", function() self.emit:Emit(40) end)
	return self
end

-- 每帧:接触墙壁(擦墙/弹开/撞死滑行)时重置计时并喷火花;脱离超过 LINGER 秒才停
function BikeVFX:step(dt)
	local t = self.ctrl:getTelemetry()
	if t.wallContact or t.crashing then
		self.sinceContact = 0
	else
		self.sinceContact += dt
	end
	local on = self.sinceContact < LINGER
	self.emit.Rate = on and 120 or 0
	self.emit.Enabled = on
end

function BikeVFX:destroy()
	if self.emit then self.emit:Destroy() end
end

return BikeVFX
