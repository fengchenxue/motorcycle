-- NeonRun / SprintUI (表现层) —— 冲刺 UI 动效:速度线爆发+残留 + 边缘流光 + 心流变金/入流闪光(ADR-50g)
-- 蓝本=场上搁置的 SprintCameraFX v2.1"方案B"(人类点名借鉴):其精华是**爆发包络**——
--   按下 0.05s 起攻→0.30s 全强平台→0.25s smoothstep 衰减→0.18 残留;松键 ×6/s 指数淡出;
--   满能=变暖+流速加倍+充满瞬间闪光。本实现只取 UI 层(纯 Frame+UIGradient 程序化,零贴图零资产),
--   蓝本被 ADR-44 否决的部分一概不带回:不碰 FOV(CameraRig 主权)/无 BlurEffect/无暗角/无相机抖动。
-- 驱动=tele.sprinting(与速度线/点火音同源:含最小点火尾段);心流=tele.flowBoost(变金+流速×2+入流白闪)。
-- 布局=两侧各 4 条渐变速度线(带透视倾角)+两侧边缘流光罩,屏幕中心恒净空(读路优先)。
-- 旋钮:VFX_SprintUIAlpha(总强度,0=关)/VFX_SprintUISustain(残留档)。
-- 用法:local sui = SprintUI.new(gui); sui:step(dt, tele); sui:destroy()
local RS = game:GetService("ReplicatedStorage")

local THEME = Color3.fromRGB(140, 230, 255)   -- 冲刺:霓虹青(能量族)
local FLOW_GOLD = Color3.fromRGB(255, 210, 110) -- 心流:金(胆量勋章)
-- 方案B 包络(蓝本数值原样借用)
local BURST_ATTACK = 0.05
local BURST_DURATION = 0.30
local BURST_FADE = 0.25
local GATE_OUT_SPEED = 6
local FLOW_SCROLL = 0.9                        -- 渐变流速(周期/秒);心流 ×2
local FLASH_SEC = 0.18                         -- 入流白闪时长

-- 速度线布局:x=屏宽比例(镜像),rot=透视倾角,w=像素宽(外粗内细)
local LINE_DEFS = {
	{ x = 0.030, rot = 14, w = 3 },
	{ x = 0.070, rot = 10, w = 3 },
	{ x = 0.115, rot = 6, w = 2 },
	{ x = 0.160, rot = 3, w = 2 },
}
local EDGE_W = 0.14                            -- 边缘流光罩宽(屏宽比例)

local SprintUI = {}
SprintUI.__index = SprintUI

local function smoothstep(k)
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

local function mkLine(gui, xFrac, rot, w)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(xFrac, 0, 0.5, 0)
	f.Size = UDim2.new(0, w, 0.92, 0)
	f.Rotation = rot
	f.BorderSizePixel = 0
	f.BackgroundColor3 = THEME
	f.BackgroundTransparency = 1
	f.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	-- 亮段在中部、两端收口;Offset.Y 循环滚动=流动感
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 0.15),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.65, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = f
	return f, g
end

local function mkEdge(gui, leftSide)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(leftSide and 0 or 1, 0.5)
	f.Position = UDim2.new(leftSide and 0 or 1, 0, 0.5, 0)
	f.Size = UDim2.new(EDGE_W, 0, 1, 0)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = THEME
	f.BackgroundTransparency = 1
	f.Parent = gui
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
	self.lines = {}   -- { frame, gradient, phase }
	for _, d in ipairs(LINE_DEFS) do
		local fL, gL = mkLine(self.holder, d.x, d.rot, d.w)
		local fR, gR = mkLine(self.holder, 1 - d.x, -d.rot, d.w)
		table.insert(self.lines, { f = fL, g = gL, phase = d.x * 7 })
		table.insert(self.lines, { f = fR, g = gR, phase = d.x * 13 })
	end
	self.edgeL = mkEdge(self.holder, true)
	self.edgeR = mkEdge(self.holder, false)
	-- 入流白闪(全屏,极短;纯 UI 不冻结不遮读路)
	self.flash = Instance.new("Frame")
	self.flash.Size = UDim2.new(1, 0, 1, 0)
	self.flash.BackgroundColor3 = Color3.new(1, 1, 1)
	self.flash.BackgroundTransparency = 1
	self.flash.BorderSizePixel = 0
	self.flash.ZIndex = 2
	self.flash.Parent = self.holder
	self.sprintT = math.huge  -- 距本次冲刺起点(方案B:帧驱动包络,无定时器)
	self.gate = 0             -- 进出闸门(松键后带整体淡出)
	self.scroll = 0           -- 渐变滚动相位
	self.flashT = 0
	self.prevSprint = false
	self.prevFlow = false
	self.written = -1         -- 上次写入强度(-1=强制首写;归零后停写省帧)
	self.flowWritten = nil
	return self
end

-- 方案B 包络:攻→平台→smoothstep 衰减→残留
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

-- tele = ctrl:getTelemetry()(sprinting 含最小点火尾段;flowBoost=心流)
function SprintUI:step(dt, tele)
	local C = self.cfg.get
	local master = C("VFX", "SprintUIAlpha")
	local sprinting = tele.sprinting == true
	local flow = tele.flowBoost == true

	-- 冲刺上升沿=重开包络;闸门进出(方案B:松键 ×GATE_OUT_SPEED 指数淡出)
	if sprinting and not self.prevSprint then self.sprintT = 0 end
	self.prevSprint = sprinting
	self.sprintT += dt
	if sprinting then
		self.gate = math.min(self.gate + dt / BURST_ATTACK, 1)
	else
		self.gate -= self.gate * math.min(GATE_OUT_SPEED * dt, 1)
		if self.gate < 1e-3 then self.gate = 0 end
	end
	-- 入流白闪(上升沿)
	if flow and not self.prevFlow then self.flashT = FLASH_SEC end
	self.prevFlow = flow
	if self.flashT > 0 then
		self.flashT = math.max(0, self.flashT - dt)
		self.flash.BackgroundTransparency = 1 - 0.35 * (self.flashT / FLASH_SEC)
	end

	local level = master * self.gate * self:_envelope(C("VFX", "SprintUISustain"))
	if level <= 0 and self.written == 0 then return end   -- 静默期零写

	-- 心流换色(仅变化帧写)
	if flow ~= self.flowWritten then
		local col = flow and FLOW_GOLD or THEME
		for _, l in ipairs(self.lines) do l.f.BackgroundColor3 = col end
		self.edgeL.BackgroundColor3 = col
		self.edgeR.BackgroundColor3 = col
		self.flowWritten = flow
	end
	-- 渐变滚动(心流 ×2)+ 每线微闪(noise,与占位版同源手法)
	self.scroll = (self.scroll + dt * FLOW_SCROLL * (flow and 2 or 1)) % 1
	for i, l in ipairs(self.lines) do
		local flicker = 0.75 + 0.25 * math.noise(self.scroll * 6 + l.phase, i * 2.7)
		l.f.BackgroundTransparency = 1 - level * flicker
		l.g.Offset = Vector2.new(0, -self.scroll)
	end
	local edgeA = 1 - level * 0.45
	self.edgeL.BackgroundTransparency = edgeA
	self.edgeR.BackgroundTransparency = edgeA
	self.written = level
end

function SprintUI:destroy()
	self.holder:Destroy()
end

return SprintUI
