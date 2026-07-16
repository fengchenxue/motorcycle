-- NeonRun / SprintUI (表现层) —— 冲刺 UI 动效 v2:动态模糊+暗角+边缘流光+心流金/入流闪(ADR-50g/50h)
-- 蓝本=场上搁置的 SprintCameraFX v2.1(人类点名借鉴,50h 实机改判追加模糊/暗角):
--   · 模糊=Lighting BlurEffect,Size=BlurMax×强度;强度=冲刺开关平滑值(指数趋近 6/s)×能量权重(0.5+0.5e);
--   · 暗角=双线性渐变近似径向(竖横两层黑框,免贴图),透明度=1−Vignette×强度;心流时叠脉动(蓝本满能行为);
--   · 边缘流光=两侧亮色渐变罩,走"方案B爆发包络"(0.05 攻→0.30 全强→0.25 衰减→残留,松键 ×6/s 淡出);
--   · 心流=全套变金+流速加倍+入流白闪 0.18s。2D 速度线层已删(50h 人类裁决"不好看";3D 速度线在 BikeVFX)。
-- ⚠ ADR-44 曾否决全屏后处理;50h=人类实机改判部分推翻——模糊/暗角进场但**全旋钮化**:
--   VFX_SprintBlurMax=0 / VFX_SprintVignette=0 即一键回退;移动端性能/晕动=M9.5 真机验证义务。
-- 不写 FOV(CameraRig 主权)/无相机抖动。
-- 用法:local sui = SprintUI.new(gui); sui:step(dt, tele, energyFrac?); sui:destroy()
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local THEME = Color3.fromRGB(140, 230, 255)     -- 冲刺:霓虹青
local FLOW_GOLD = Color3.fromRGB(255, 210, 110) -- 心流:金
-- 方案B 包络(蓝本数值)
local BURST_ATTACK = 0.05
local BURST_DURATION = 0.30
local BURST_FADE = 0.25
local GATE_OUT_SPEED = 6
local INTENSITY_LERP = 6                        -- 模糊/暗角进出速度(蓝本 INTENSITY_LERP)
local FLASH_SEC = 0.18
local EDGE_W = 0.14

local SprintUI = {}
SprintUI.__index = SprintUI

local function smoothstep(k)
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- 暗角层(蓝本手法:线性渐变两层近似径向,黑框中透边实)
local function mkVignette(holder, rotation)
	local f = Instance.new("Frame")
	f.Name = "Vignette" .. rotation
	f.Size = UDim2.new(1, 0, 1, 0)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Parent = holder
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	g.Parent = f
	return f
end

local function mkEdge(holder, leftSide)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(leftSide and 0 or 1, 0.5)
	f.Position = UDim2.new(leftSide and 0 or 1, 0, 0.5, 0)
	f.Size = UDim2.new(EDGE_W, 0, 1, 0)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = THEME
	f.BackgroundTransparency = 1
	f.ZIndex = 2
	f.Parent = holder
	local g = Instance.new("UIGradient")
	g.Rotation = leftSide and 0 or 180
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f
end

function SprintUI.new(gui)
	local self = setmetatable({}, SprintUI)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.holder = Instance.new("Frame")
	self.holder.Name = "SprintUI"
	self.holder.Size = UDim2.new(1, 0, 1, 0)
	self.holder.BackgroundTransparency = 1
	self.holder.Parent = gui
	self.vigV = mkVignette(self.holder, 90)  -- 压上下
	self.vigH = mkVignette(self.holder, 0)   -- 压左右
	self.edgeL = mkEdge(self.holder, true)
	self.edgeR = mkEdge(self.holder, false)
	self.flash = Instance.new("Frame")
	self.flash.Size = UDim2.new(1, 0, 1, 0)
	self.flash.BackgroundColor3 = Color3.new(1, 1, 1)
	self.flash.BackgroundTransparency = 1
	self.flash.BorderSizePixel = 0
	self.flash.ZIndex = 3
	self.flash.Parent = self.holder
	-- 动态模糊(Lighting 后处理;BlurMax=0 时恒 0=等效关)
	self.blur = Instance.new("BlurEffect")
	self.blur.Name = "NeonRunSprintBlur"
	self.blur.Size = 0
	self.blur.Enabled = true
	self.blur.Parent = Lighting
	self.sprintT = math.huge
	self.gate = 0
	self.sprintAlpha = 0     -- 冲刺开关平滑值(蓝本:驱动模糊/暗角,稳定不随包络)
	self.clock = 0
	self.flashT = 0
	self.prevSprint = false
	self.prevFlow = false
	self.written = -1
	self.flowWritten = nil
	return self
end

-- 方案B 包络(边缘流光用)
function SprintUI:_envelope(sustain)
	local t = self.sprintT
	if t < BURST_ATTACK then
		return t / BURST_ATTACK
	elseif t < BURST_ATTACK + BURST_DURATION then
		return 1
	elseif t < BURST_ATTACK + BURST_DURATION + BURST_FADE then
		local k = (t - BURST_ATTACK - BURST_DURATION) / BURST_FADE
		return 1 - (1 - sustain) * smoothstep(k)
	end
	return sustain
end

-- tele=ctrl:getTelemetry();energyFrac=能量比例 0..1(可省,默认 1;蓝本:低能量整体弱一档)
function SprintUI:step(dt, tele, energyFrac)
	local C = self.cfg.get
	local sprinting = tele.sprinting == true
	local flow = tele.flowBoost == true
	self.clock += dt

	if sprinting and not self.prevSprint then self.sprintT = 0 end
	self.prevSprint = sprinting
	self.sprintT += dt
	if sprinting then
		self.gate = math.min(self.gate + dt / BURST_ATTACK, 1)
	else
		self.gate -= self.gate * math.min(GATE_OUT_SPEED * dt, 1)
		if self.gate < 1e-3 then self.gate = 0 end
	end
	-- 冲刺开关平滑值(帧率无关指数趋近,蓝本 expAlpha)
	local target = sprinting and 1 or 0
	self.sprintAlpha += (target - self.sprintAlpha) * (1 - math.exp(-INTENSITY_LERP * dt))
	if self.sprintAlpha < 1e-3 and not sprinting then self.sprintAlpha = 0 end

	if flow and not self.prevFlow then self.flashT = FLASH_SEC end
	self.prevFlow = flow
	if self.flashT > 0 then
		self.flashT = math.max(0, self.flashT - dt)
		self.flash.BackgroundTransparency = 1 - 0.35 * (self.flashT / FLASH_SEC)
	end

	-- 强度=开关平滑值×能量权重(蓝本 currentIntensity)
	local e = energyFrac or 1
	local intensity = self.sprintAlpha * (0.5 + 0.5 * math.clamp(e, 0, 1))
	local master = C("VFX", "SprintUIAlpha")
	local level = master * self.gate * self:_envelope(C("VFX", "SprintUISustain"))
	if level <= 0 and intensity <= 0 and self.written == 0 then return end

	-- 模糊(BlurMax=0=关)
	local blurMax = C("VFX", "SprintBlurMax")
	self.blur.Size = blurMax * intensity
	-- 暗角(Vignette=最大不透明度,0=关);心流叠脉动(蓝本满能行为)
	local vig = C("VFX", "SprintVignette")
	local vigI = intensity
	if flow then vigI = intensity * (0.85 + 0.15 * math.sin(self.clock * 7)) end
	local vt = 1 - vig * vigI
	self.vigV.BackgroundTransparency = vt
	self.vigH.BackgroundTransparency = vt
	-- 边缘流光(爆发包络)+心流换色
	if flow ~= self.flowWritten then
		local col = flow and FLOW_GOLD or THEME
		self.edgeL.BackgroundColor3 = col
		self.edgeR.BackgroundColor3 = col
		self.flowWritten = flow
	end
	local edgeA = 1 - level * 0.45
	self.edgeL.BackgroundTransparency = edgeA
	self.edgeR.BackgroundTransparency = edgeA
	self.written = math.max(level, intensity)
end

function SprintUI:destroy()
	self.holder:Destroy()
	self.blur:Destroy()
end

return SprintUI
