-- NeonRun / SprintUI (表现层) —— 冲刺 UI 动效 v4:动态模糊+暗角+边缘点火流光+心流金/入流闪(ADR-50g/50h/50k/50l)
-- v4(ADR-50l,人类直令"流光只在冲刺时产生,而不是一直存在"):
--   实机发现 v3"冲刺期恒定"在 Track1 b4 之后读感回到常驻——红区收入群(闸/弹反/斩敌/核)让能量不再清零,
--   拇指常驻/W 别名下冲刺≈全程,恒定微光=恒亮。改=**点火短促流光**:冲刺【开始】亮起,
--   VFX_SprintEdgeBurstSec(默认 0.9)内 smoothstep 退净,长按中段不再亮;断冲后再冲刺才再来一次。
--   **旋钮 0=回 v3 恒定微光**(50k 语义原样保留在 0 档);松键淡出仍走 sprintAlpha(同 v3)。
-- v3(ADR-50k,人类实机裁决"流光太重且常驻,应只在冲刺时有一点"):
--   边缘流光的方案B爆发包络整删(gate/sprintT/envelope 机器全拆)——边缘=仅冲刺期恒定微光,
--   强度=master×冲刺平滑值×VFX_SprintEdgeAlpha(默认 0.12,一点点;0=关),与模糊/暗角同一驱动、同进同出;
--   宽度 14%→10%;旧 VFX_SprintUISustain 键随包络退役。
--   (50l 注:v4 的"点火包络"≠方案B"爆发+残留包络"——方案B死于**残留常驻**,v4 是纯衰减、零残留。)
--   · 模糊=Lighting BlurEffect,Size=BlurMax×强度;强度=冲刺开关平滑值(指数趋近 6/s)×能量权重(0.5+0.5e);
--   · 暗角=双线性渐变近似径向(竖横两层黑框,免贴图),透明度=1−Vignette×强度;心流时叠脉动(蓝本满能行为);
--   · 心流=全套变金+入流白闪 0.18s。2D 速度线层已删(50h);FOV 主权归 CameraRig,无相机抖动。
-- ⚠ ADR-44 曾否决全屏后处理;50h=人类实机改判部分推翻——模糊/暗角进场但**全旋钮化**:
--   VFX_SprintBlurMax=0 / VFX_SprintVignette=0 即一键回退;移动端性能/晕动=M9.5 真机验证义务。
-- 用法:local sui = SprintUI.new(gui); sui:step(dt, tele, energyFrac?); sui:destroy()
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local THEME = Color3.fromRGB(140, 230, 255)     -- 冲刺:霓虹青
local FLOW_GOLD = Color3.fromRGB(255, 210, 110) -- 心流:金
local INTENSITY_LERP = 6                        -- 模糊/暗角/边缘进出速度(蓝本 INTENSITY_LERP)
local FLASH_SEC = 0.18
local EDGE_W = 0.10                             -- v3:14%→10%(减重)

local SprintUI = {}
SprintUI.__index = SprintUI

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
	self.sprintAlpha = 0     -- 冲刺开关平滑值(驱动模糊/暗角/边缘)
	self.edgeT = 0           -- v4(ADR-50l):边缘点火包络余量(冲刺上升沿=BurstSec,逐帧衰减)
	self.prevSprinting = false
	self.clock = 0
	self.flashT = 0
	self.prevFlow = false
	self.written = -1
	self.flowWritten = nil
	return self
end

-- tele=ctrl:getTelemetry();energyFrac=能量比例 0..1(可省,默认 1;蓝本:低能量整体弱一档)
function SprintUI:step(dt, tele, energyFrac)
	local C = self.cfg.get
	local sprinting = tele.sprinting == true
	local flow = tele.flowBoost == true
	self.clock += dt

	-- 冲刺开关平滑值(帧率无关指数趋近,蓝本 expAlpha);模糊/暗角同源驱动
	local target = sprinting and 1 or 0
	self.sprintAlpha += (target - self.sprintAlpha) * (1 - math.exp(-INTENSITY_LERP * dt))
	if self.sprintAlpha < 1e-3 and not sprinting then self.sprintAlpha = 0 end

	-- v4(ADR-50l)边缘点火包络:冲刺上升沿装填 BurstSec,逐帧无条件衰减;
	-- 旋钮 0=回 v3 恒定微光(env 恒 1)。放在早退之前,保证上升沿永不丢检。
	local burstSec = C("VFX", "SprintEdgeBurstSec") or 0
	if sprinting and not self.prevSprinting and burstSec > 0 then
		self.edgeT = burstSec
	end
	self.prevSprinting = sprinting
	if self.edgeT > 0 then self.edgeT = math.max(0, self.edgeT - dt) end
	local edgeEnv = 1
	if burstSec > 0 then
		local k = math.clamp(self.edgeT / burstSec, 0, 1)
		edgeEnv = k * k * (3 - 2 * k)
	end

	if flow and not self.prevFlow then self.flashT = FLASH_SEC end
	self.prevFlow = flow
	if self.flashT > 0 then
		self.flashT = math.max(0, self.flashT - dt)
		self.flash.BackgroundTransparency = 1 - 0.35 * (self.flashT / FLASH_SEC)
	end

	-- 强度=开关平滑值×能量权重(蓝本 currentIntensity)
	local e = energyFrac or 1
	local intensity = self.sprintAlpha * (0.5 + 0.5 * math.clamp(e, 0, 1))
	if intensity <= 0 and self.written == 0 then return end

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
	-- 边缘流光(v4):冲刺开始短促亮起,BurstSec 内退净(BurstSec=0 时 env=1=v3 恒定微光);心流换色
	if flow ~= self.flowWritten then
		local col = flow and FLOW_GOLD or THEME
		self.edgeL.BackgroundColor3 = col
		self.edgeR.BackgroundColor3 = col
		self.flowWritten = flow
	end
	local edgeA = 1 - C("VFX", "SprintUIAlpha") * self.sprintAlpha * C("VFX", "SprintEdgeAlpha") * edgeEnv
	self.edgeL.BackgroundTransparency = edgeA
	self.edgeR.BackgroundTransparency = edgeA
	self.written = intensity
end

function SprintUI:destroy()
	self.holder:Destroy()
	self.blur:Destroy()
end

return SprintUI
