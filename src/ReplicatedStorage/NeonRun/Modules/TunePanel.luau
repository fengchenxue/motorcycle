-- NeonRun / TunePanel (M3) —— Play 内实时调参面板(调参协议工具)
-- 滑条直写 Config/Handling Attributes,ConfigLive 每帧读取 → 拖动即生效,边骑边调。
-- 人类调好后对 AI 说"锁定当前参数",AI 写回 Config 源码。
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

-- 手感关键参数(组, 键, 最小, 最大, 小数位)
local PARAMS = {
	{ "Speed", "Base", 40, 200, 0 },
	{ "Speed", "SprintMultiplier", 1.0, 2.0, 2 },
	{ "Steering", "TurnRateLowDeg", 40, 180, 0 },
	{ "Steering", "TurnRateHighDeg", 20, 120, 0 },
	{ "Steering", "InputRampInSec", 0.02, 0.40, 2 },
	{ "Steering", "InputRampOutSec", 0.05, 0.50, 2 },
	{ "Ground", "AlignLerpSpeed", 2, 40, 0 },
	{ "Physics", "MaxStepUp", 0.5, 6, 1 },
	{ "Lean", "BodyRollMaxDeg", 5, 40, 0 },
	{ "Lean", "OvershootDeg", 0, 10, 1 },
	{ "Lean", "LerpSpeed", 3, 20, 1 },
	{ "Lean", "ForkMaxDeg", 0, 35, 0 },
	{ "Camera", "FOVBase", 55, 90, 0 },
	{ "Camera", "FOVSprint", 70, 110, 0 },
	{ "Camera", "FlowFOV", 70, 115, 0 },
	{ "Camera", "FOVLerpSec", 0.05, 0.50, 2 },
	{ "Camera", "FollowLagSec", 0.02, 0.30, 2 },
	{ "Camera", "YawLagSec", 0.05, 0.50, 2 },
	{ "Camera", "Distance", 8, 30, 0 },
	{ "Camera", "Height", 2, 14, 1 },
	{ "Camera", "LookAhead", 4, 24, 0 },
	{ "Camera", "LookUp", 0, 8, 1 },
	{ "Camera", "ShakeSprint", 0, 0.6, 2 },
	{ "Camera", "ShakeFreqHz", 5, 20, 0 },
	-- ADR-44 GR2 手感包(默认 0=关,拖离 0 即生效;SteerRollGain 负值=反向侧倾)
	{ "Camera", "SteerRollGain", -1, 1, 2 },
	{ "Camera", "SteerRollMaxDeg", 0, 25, 0 },
	{ "Camera", "SteerRollLerpSec", 0, 0.60, 2 },
	{ "Camera", "LatLagSec", 0, 0.60, 2 },
	{ "Camera", "FOVSpeedGain", 0, 0.30, 2 },
	{ "Camera", "FOVPunchDeg", 0, 12, 0 },
	{ "Camera", "FOVPunchDecaySec", 0.10, 0.80, 2 },
	{ "Camera", "LandDipPerVy", 0, 0.02, 3 },
	{ "Camera", "ShakeSpeedGain", 0, 0.40, 2 },
	{ "Camera", "AirPitchDownDeg", 0, 12, 0 },
}

local TunePanel = {}

function TunePanel.mount(parentGui)
	local host = RS:WaitForChild("NeonRun"):WaitForChild("Config"):WaitForChild("Handling")

	local frame = Instance.new("Frame")
	frame.Name = "TunePanel"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -10, 0, 50)
	frame.Size = UDim2.new(0, 320, 0, math.min(#PARAMS * 26 + 40, 620))
	frame.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parentGui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 26)
	title.BackgroundTransparency = 1
	title.TextColor3 = Color3.fromRGB(0, 220, 255)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 14
	title.Text = "调参面板 [T 开关]  调好后告诉 AI:锁定当前参数"
	title.Parent = frame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.new(0, 0, 0, 28)
	scroll.Size = UDim2.new(1, 0, 1, -28)
	scroll.CanvasSize = UDim2.new(0, 0, 0, #PARAMS * 26 + 6)
	scroll.ScrollBarThickness = 4
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Parent = frame

	local dragging = nil -- {bar, apply}

	local function fmt(v, dec) return string.format("%." .. dec .. "f", v) end

	for i, p in ipairs(PARAMS) do
		local grp, key, mn, mx, dec = p[1], p[2], p[3], p[4], p[5]
		local attr = grp .. "_" .. key

		local row = Instance.new("Frame")
		row.Position = UDim2.new(0, 6, 0, (i - 1) * 26 + 3)
		row.Size = UDim2.new(1, -16, 0, 22)
		row.BackgroundTransparency = 1
		row.Parent = scroll

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(0, 150, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(200, 210, 225)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 12
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = attr
		lbl.Parent = row

		local val = Instance.new("TextLabel")
		val.Position = UDim2.new(1, -44, 0, 0)
		val.Size = UDim2.new(0, 44, 1, 0)
		val.BackgroundTransparency = 1
		val.TextColor3 = Color3.fromRGB(0, 220, 255)
		val.Font = Enum.Font.GothamMedium
		val.TextSize = 12
		val.Parent = row

		local bar = Instance.new("Frame")
		bar.Position = UDim2.new(0, 152, 0.5, -3)
		bar.Size = UDim2.new(1, -200, 0, 6)
		bar.BackgroundColor3 = Color3.fromRGB(45, 55, 75)
		bar.BorderSizePixel = 0
		bar.Parent = row

		local fill = Instance.new("Frame")
		fill.Size = UDim2.new(0, 0, 1, 0)
		fill.BackgroundColor3 = Color3.fromRGB(0, 180, 220)
		fill.BorderSizePixel = 0
		fill.Parent = bar

		local function refresh()
			local v = host:GetAttribute(attr) or mn
			val.Text = fmt(v, dec)
			fill.Size = UDim2.new(math.clamp((v - mn) / (mx - mn), 0, 1), 0, 1, 0)
		end

		local function applyFromX(x)
			local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			local v = mn + (mx - mn) * rel
			local q = 10 ^ dec
			v = math.floor(v * q + 0.5) / q
			host:SetAttribute(attr, v)
			refresh()
		end

		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = applyFromX
				applyFromX(input.Position.X)
			end
		end)

		host:GetAttributeChangedSignal(attr):Connect(refresh)
		refresh()
	end

	UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			dragging(input.Position.X)
		end
	end)
	UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = nil
		end
	end)
	UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.T then
			frame.Visible = not frame.Visible
		end
	end)

	return frame
end

return TunePanel
