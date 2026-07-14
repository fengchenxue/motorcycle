-- NeonRun 试驾(M3+M2.1+M5+M7+M8):A/D 转向 | W/Shift 冲刺 | S 轻刹 | J 斩 | R 重开
-- 相机→CameraRig | 音效→BikeAudio | 能量→EnergyState+CrystalField | 攻击→AttackSystem | 计时→RaceTimer
local Players = game:GetService("Players")
local RunS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mods = RS:WaitForChild("NeonRun"):WaitForChild("Modules")
local BikeController = require(mods:WaitForChild("BikeController"))
local CameraRig = require(mods:WaitForChild("CameraRig"))
local BikeAudio = require(mods:WaitForChild("BikeAudio"))
local TunePanel = require(mods:WaitForChild("TunePanel"))
local Spline = require(mods:WaitForChild("Spline"))
local EnergyState = require(mods:WaitForChild("EnergyState"))
local CrystalField = require(mods:WaitForChild("CrystalField"))
local AttackSystem = require(mods:WaitForChild("AttackSystem"))
local RaceTimer = require(mods:WaitForChild("RaceTimer"))
local ShooterField = require(mods:WaitForChild("ShooterField"))

local cpFolder = workspace:WaitForChild("NeonRun"):WaitForChild("ControlPoints")
local cp1 = cpFolder:WaitForChild("CP01")
local cp2 = cpFolder:WaitForChild("CP02")
local SPAWN = CFrame.lookAt(cp1.Position + Vector3.new(0, 1.2, 0), Vector3.new(cp2.Position.X, cp1.Position.Y + 1.2, cp2.Position.Z))

task.spawn(function()
	local char = player.Character or player.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart")
	task.wait(0.3)
	hrp.Anchored = true
	hrp.CFrame = CFrame.new(SPAWN.Position + Vector3.new(0, 150, 0))
end)

-- HUD
local gui = Instance.new("ScreenGui")
gui.Name = "NeonRunTestDriveHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")
local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, 0, 0, 34)
label.Position = UDim2.new(0, 0, 0, 8)
label.BackgroundTransparency = 0.35
label.BackgroundColor3 = Color3.new(0, 0, 0)
label.TextColor3 = Color3.fromRGB(0, 220, 255)
label.TextSize = 18
label.Font = Enum.Font.GothamMedium
label.Parent = gui
TunePanel.mount(gui)

-- M5 能量 HUD:底部能量条(水晶段青色,冒险段>80 金色,心流白光,空槽暗红)
local energyBarBG = Instance.new("Frame")
energyBarBG.AnchorPoint = Vector2.new(0.5, 1)
energyBarBG.Position = UDim2.new(0.5, 0, 1, -24)
energyBarBG.Size = UDim2.new(0, 360, 0, 22)
energyBarBG.BackgroundColor3 = Color3.fromRGB(10, 14, 20)
energyBarBG.BackgroundTransparency = 0.25
energyBarBG.BorderSizePixel = 0
energyBarBG.Parent = gui
local energyBarFill = Instance.new("Frame")
energyBarFill.AnchorPoint = Vector2.new(0, 0.5)
energyBarFill.Position = UDim2.new(0, 2, 0.5, 0)
energyBarFill.Size = UDim2.new(0, 0, 1, -4)
energyBarFill.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
energyBarFill.BorderSizePixel = 0
energyBarFill.Parent = energyBarBG
local capMark = Instance.new("Frame")
capMark.AnchorPoint = Vector2.new(0.5, 0.5)
capMark.Position = UDim2.new(0.8, 0, 0.5, 0)
capMark.Size = UDim2.new(0, 2, 1, 0)
capMark.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
capMark.BackgroundTransparency = 0.3
capMark.BorderSizePixel = 0
capMark.ZIndex = 2
capMark.Parent = energyBarBG
local energyText = Instance.new("TextLabel")
energyText.Size = UDim2.new(1, 0, 1, 0)
energyText.BackgroundTransparency = 1
energyText.TextColor3 = Color3.fromRGB(255, 255, 255)
energyText.TextSize = 13
energyText.Font = Enum.Font.GothamBold
energyText.ZIndex = 3
energyText.Parent = energyBarBG

-- 速度线占位:两侧斜线,冲刺时渐显 + 闪烁
local lines = {}
do
	local defs = {
		{ x = 0.02, rot = 14 }, { x = 0.06, rot = 9 }, { x = 0.11, rot = 5 },
		{ x = 0.98, rot = -14 }, { x = 0.94, rot = -9 }, { x = 0.89, rot = -5 },
	}
	for _, d in ipairs(defs) do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(d.x, 0, 0.5, 0)
		f.Size = UDim2.new(0, 3, 0.85, 0)
		f.Rotation = d.rot
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.fromRGB(180, 240, 255)
		f.BackgroundTransparency = 1
		f.Parent = gui
		table.insert(lines, f)
	end
end

local bike = workspace:WaitForChild("Motorcycle"):Clone()
bike.Name = "TestDriveBike"
bike.Parent = workspace
bike:PivotTo(SPAWN)
local ctrl = BikeController.new(bike)
-- M4:赛道样条注入,重生/坠落判定依赖。闭环/开放由 Workspace.NeonRun 的 Closed 属性定(默认 true=环道)。
-- 开放式赛道(有头有尾)= false;TrackBuilder 读同一属性,两边保持一致(M8.5 开放式支持)。
local TRACK_CLOSED = cpFolder.Parent:GetAttribute("Closed")
if TRACK_CLOSED == nil then TRACK_CLOSED = true end
do
	local cps = cpFolder:GetChildren()
	table.sort(cps, function(a, b) return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0) end)
	local pts = {}
	for _, cp in ipairs(cps) do table.insert(pts, cp.Position) end
	ctrl:setSpline(Spline.new(pts, TRACK_CLOSED))
end
-- M4:硬撞/坠落转场占位——全屏青色故障闪屏,随 TransitionSec 淡出
local crashFlash = Instance.new("Frame")
crashFlash.Size = UDim2.new(1, 0, 1, 0)
crashFlash.BackgroundColor3 = Color3.fromRGB(0, 230, 255)
crashFlash.BackgroundTransparency = 1
crashFlash.BorderSizePixel = 0
crashFlash.ZIndex = 5
crashFlash.Parent = gui
local function flashCrash()
	crashFlash.BackgroundColor3 = Color3.fromRGB(0, 230, 255)
	crashFlash.BackgroundTransparency = 0.25
end
ctrl:on("hardHit", flashCrash)
ctrl:on("fell", flashCrash)
local rig = CameraRig.new(camera, ctrl)
ctrl:on("respawned", function() rig:snap() end)
local audio = BikeAudio.new(bike.PrimaryPart)

-- M5:能量系统(订阅 ctrl 事件) + 水晶场(拾取→加能);心流→相机档
local energy = EnergyState.new(ctrl)
local field = CrystalField.new(function() energy:addCrystal() end)
energy:on("flowStart", function() rig:setFlow(true); ctrl:setFlowBoost(true) end)   -- ADR-31 心流升档接线
energy:on("flowEnd", function() rig:setFlow(false); ctrl:setFlowBoost(false) end)

-- M7:攻击系统(自动锁定·时机判定·斩击点只在直线段);命中回能由 AttackSystem 内部调 energy
local spline = ctrl.spline
local attack = AttackSystem.new(ctrl, energy, spline)

-- 远程敌与快照子弹(ADR-21/22):射手本体/子弹经 AttackSystem 注册,弹反=改写目标为射手
local shooters = ShooterField.new(ctrl, attack, energy)
shooters:on("playerHit", function()
	crashFlash.BackgroundColor3 = Color3.fromRGB(255, 60, 110)
	crashFlash.BackgroundTransparency = 0.55
end)

-- 【临时调试】斩击判定盒可视化(开关=Handling 属性 Combat_DebugHitbox,属性面板实时切;正式版前移除)
-- 盒随物理系(physPos+yaw)走,尺寸实时读 Combat_Hitbox* 四键——调参数时盒子跟着变
local handlingCfg = RS:WaitForChild("NeonRun"):WaitForChild("Config"):WaitForChild("Handling")
local hitboxViz = Instance.new("Part")
hitboxViz.Name = "SlashHitboxViz"
hitboxViz.Anchored = true
hitboxViz.CanCollide = false; hitboxViz.CanTouch = false; hitboxViz.CanQuery = false
hitboxViz.CastShadow = false
hitboxViz.Material = Enum.Material.ForceField
hitboxViz.Color = Color3.fromRGB(0, 220, 255)
hitboxViz.Transparency = 1
hitboxViz.Parent = workspace
local hitboxSel = Instance.new("SelectionBox")
hitboxSel.Adornee = hitboxViz
hitboxSel.LineThickness = 0.04
hitboxSel.Color3 = Color3.fromRGB(0, 220, 255)
hitboxSel.Transparency = 1
hitboxSel.Parent = hitboxViz

-- M8:计时器(发车标准化+检查点+四奖牌+一键重开)
local timer = RaceTimer.new(ctrl, spline, { trackId = "Track01", laps = 1, closed = TRACK_CLOSED })

-- M7 锻点 HUD:中心十字(锁定=橘黄,在窗口=青绿发光=可斩)
local reticle = Instance.new("Frame")
reticle.AnchorPoint = Vector2.new(0.5, 0.5)
reticle.Position = UDim2.new(0.5, 0, 0.44, 0)
reticle.Size = UDim2.new(0, 46, 0, 46)
reticle.BackgroundTransparency = 1
reticle.Parent = gui
local function reticleBar(w, h)
	local b = Instance.new("Frame")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.BorderSizePixel = 0
	b.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	b.BackgroundTransparency = 1
	b.Size = UDim2.new(0, w, 0, h)
	b.Parent = reticle
	return b
end
local retTop = reticleBar(2, 14); retTop.Position = UDim2.new(0.5, 0, 0.5, -16)
local retBot = reticleBar(2, 14); retBot.Position = UDim2.new(0.5, 0, 0.5, 16)
local retL = reticleBar(14, 2); retL.Position = UDim2.new(0.5, -16, 0.5, 0)
local retR = reticleBar(14, 2); retR.Position = UDim2.new(0.5, 16, 0.5, 0)
local retParts = { retTop, retBot, retL, retR }
local attackFlash = 0
attack:on("hit", function() attackFlash = 1 end)
attack:on("whiff", function() attackFlash = -1 end)

-- M8 计时 HUD:顶部中央秒表 + 检查点进度
local timerLabel = Instance.new("TextLabel")
timerLabel.AnchorPoint = Vector2.new(0.5, 0)
timerLabel.Position = UDim2.new(0.5, 0, 0, 46)
timerLabel.Size = UDim2.new(0, 220, 0, 40)
timerLabel.BackgroundTransparency = 0.4
timerLabel.BackgroundColor3 = Color3.new(0, 0, 0)
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextSize = 26
timerLabel.Font = Enum.Font.GothamBold
timerLabel.Text = "0.00"
timerLabel.Parent = gui
local cpLabel = Instance.new("TextLabel")
cpLabel.AnchorPoint = Vector2.new(0.5, 0)
cpLabel.Position = UDim2.new(0.5, 0, 0, 88)
cpLabel.Size = UDim2.new(0, 220, 0, 20)
cpLabel.BackgroundTransparency = 1
cpLabel.TextColor3 = Color3.fromRGB(0, 220, 255)
cpLabel.TextSize = 14
cpLabel.Font = Enum.Font.GothamMedium
cpLabel.Parent = gui

-- M8 倒计时大数字(3-2-1 GO)
local countdownLabel = Instance.new("TextLabel")
countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
countdownLabel.Size = UDim2.new(0, 200, 0, 200)
countdownLabel.BackgroundTransparency = 1
countdownLabel.TextColor3 = Color3.fromRGB(0, 230, 255)
countdownLabel.TextSize = 120
countdownLabel.Font = Enum.Font.GothamBold
countdownLabel.Text = ""
countdownLabel.ZIndex = 6
countdownLabel.Parent = gui

-- M8 结算面板:奖牌 + “差 X 秒就是<下一枚>” + 一键重开
local settlePanel = Instance.new("Frame")
settlePanel.AnchorPoint = Vector2.new(0.5, 0.5)
settlePanel.Position = UDim2.new(0.5, 0, 0.5, 0)
settlePanel.Size = UDim2.new(0, 380, 0, 220)
settlePanel.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
settlePanel.BackgroundTransparency = 0.1
settlePanel.BorderSizePixel = 0
settlePanel.Visible = false
settlePanel.ZIndex = 7
settlePanel.Parent = gui
local settleMedal = Instance.new("TextLabel")
settleMedal.Position = UDim2.new(0, 0, 0, 20)
settleMedal.Size = UDim2.new(1, 0, 0, 50)
settleMedal.BackgroundTransparency = 1
settleMedal.TextColor3 = Color3.fromRGB(255, 210, 80)
settleMedal.TextSize = 34
settleMedal.Font = Enum.Font.GothamBold
settleMedal.ZIndex = 8
settleMedal.Parent = settlePanel
local settleTime = Instance.new("TextLabel")
settleTime.Position = UDim2.new(0, 0, 0, 74)
settleTime.Size = UDim2.new(1, 0, 0, 28)
settleTime.BackgroundTransparency = 1
settleTime.TextColor3 = Color3.fromRGB(255, 255, 255)
settleTime.TextSize = 22
settleTime.Font = Enum.Font.GothamMedium
settleTime.ZIndex = 8
settleTime.Parent = settlePanel
local settleGap = Instance.new("TextLabel")
settleGap.Position = UDim2.new(0, 0, 0, 104)
settleGap.Size = UDim2.new(1, 0, 0, 24)
settleGap.BackgroundTransparency = 1
settleGap.TextColor3 = Color3.fromRGB(120, 220, 255)
settleGap.TextSize = 16
settleGap.Font = Enum.Font.Gotham
settleGap.ZIndex = 8
settleGap.Parent = settlePanel
local restartBtn = Instance.new("TextButton")
restartBtn.AnchorPoint = Vector2.new(0.5, 0)
restartBtn.Position = UDim2.new(0.5, 0, 0, 148)
restartBtn.Size = UDim2.new(0, 240, 0, 44)
restartBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
restartBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
restartBtn.TextSize = 20
restartBtn.Font = Enum.Font.GothamBold
restartBtn.Text = "一键重开 (R)"
restartBtn.BorderSizePixel = 0
restartBtn.ZIndex = 8
restartBtn.Parent = settlePanel

-- 重开逻辑:回发车线 + 重启倒计时(R 与按钮共用)
local function doRestart()
	ctrl:teleport(SPAWN)
	rig:snap()
	settlePanel.Visible = false
	attack:reset()      -- R 重开全部重置:靶/核复活(验收断言点)
	shooters:reset()    -- 敌人复活/子弹清空/节拍归零
	energy:reset()      -- 能量数值+心流归位(修 status.md 已知问题⑤:R 不重置能量)
	timer:restart()
end
restartBtn.MouseButton1Click:Connect(doRestart)

-- 奖牌中文名
local MEDAL_CN = { Bronze = "🥉 铜牌", Silver = "🥈 银牌", Gold = "🥇 金牌", Author = "👑 作者牌" }
timer:on("finish", function(res)
	settleMedal.Text = res.medal and MEDAL_CN[res.medal] or "未完赛"
	settleTime.Text = string.format("用时 %.2f 秒  ·  重置 %d 次", res.time, res.resetCount)
	if res.nextMedal and res.gapToNext then
		settleGap.Text = string.format("差 %.2f 秒就是 %s", res.gapToNext, MEDAL_CN[res.nextMedal] or res.nextMedal)
	else
		settleGap.Text = "已是最高奖牌!"
	end
	settlePanel.Visible = true
end)
timer:on("go", function() countdownLabel.Text = "GO!" end)

-- M8 发车标准化:开局即进入倒计时
timer:startCountdown()

UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.R then
		doRestart()
	elseif input.KeyCode == Enum.KeyCode.J
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		-- M7 单键攻击(J / 左键 / 手柄R2);命中闪青,失误闪红
		if not timer:isControlLocked() then attack:attack() end  -- 反馈走 hit/whiff 事件
	end
end)

RunS.Heartbeat:Connect(function(dt)
	local steer = 0
	if UIS:IsKeyDown(Enum.KeyCode.A) then steer += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) then steer -= 1 end
	ctrl:setSteer(steer)
	-- M8 发车标准化:倒计时/结算期间输入冻结(不存在抢跑)
	local locked = timer:isControlLocked()
	-- W=冲刺别名(与 Shift 等价,ADR-7);S=轻刹至 70%(刹车优先在 BikeController 处理)
	ctrl:setSprint((not locked) and (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) or UIS:IsKeyDown(Enum.KeyCode.W)))
	ctrl:setBrake((not locked) and UIS:IsKeyDown(Enum.KeyCode.S))
	if locked then ctrl:setSteer(0) end
	ctrl:step(dt)
	timer:step(dt)  -- M8:计时/检查点/发车状态机(ctrl:step 后)
	-- M5:能量与水晶(ctrl:step 后,读最新遥测)
	energy:step(dt)
	field:step(bike.PrimaryPart and bike.PrimaryPart.Position or nil, dt)
	shooters:step(dt)  -- 射手节拍/子弹推进(attack:step 前:弹反缓冲优先于吃弹)
	attack:step(dt)  -- M7:维护锁定/窗口(ctrl:step 后,用最新位置)
	local t = ctrl:getTelemetry()
	local et = energy:getTelemetry()
	local at = attack:getTelemetry()
	local rt = timer:getTelemetry()
	audio:update(t, dt)
	-- M8 计时/倒计时 HUD
	if rt.state == "countdown" then
		countdownLabel.Text = rt.countdown and tostring(rt.countdown) or ""
		timerLabel.Text = "0.00"
	elseif rt.state == "racing" then
		timerLabel.Text = string.format("%.2f", rt.time)
	end
	cpLabel.Text = string.format("检查点 %d/%d", rt.checkpoint, rt.totalCheckpoints)
	label.Text = string.format("M8 计时  |  速度 %d  |  能量 %d  |  %s%s%s%s  |  A/D·W/Shift冲·S刹·J斩·R重开",
		math.floor(t.speed + 0.5),
		math.floor(et.energy + 0.5),
		rt.state == "finished" and "完赛" or (rt.state == "countdown" and "发车" or (t.grounded and "地面" or "空中")),
		t.sprinting and "·冲刺" or "",
		et.flow and "·心流!" or "",
		at.inVolume and "·可斩!" or "")
end)

local clock = 0
RunS.RenderStepped:Connect(function(dt)
	if not bike.PrimaryPart then return end
	rig:update(dt)
	-- M8:绿灯后 GO! 短暂停留再渐隐;倒计时期间大数字实时显示
	local rtState = timer:getTelemetry().state
	if rtState == "racing" and countdownLabel.Text == "GO!" then
		countdownLabel.TextTransparency = math.min(1, countdownLabel.TextTransparency + dt * 1.5)
		if countdownLabel.TextTransparency >= 1 then countdownLabel.Text = ""; countdownLabel.TextTransparency = 0 end
	elseif rtState == "countdown" then
		countdownLabel.TextTransparency = 0
	end
	if crashFlash.BackgroundTransparency < 1 then
		crashFlash.BackgroundTransparency = math.min(1, crashFlash.BackgroundTransparency + dt / 0.4)
	end
	clock += dt
	local t = ctrl:getTelemetry()
	local et = energy:getTelemetry()
	-- M5 能量条:宽度按比例;冒险段(>80)金色,心流白光,空槽暗红,否则青色
	local frac = et.frac
	energyBarFill.Size = UDim2.new(frac, -4, 1, -4)
	if et.flow then
		energyBarFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	elseif frac > 0.8 then
		energyBarFill.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	elseif et.sprintGated then
		energyBarFill.BackgroundColor3 = Color3.fromRGB(120, 40, 40)
	else
		energyBarFill.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
	end
	energyText.Text = et.flow and "心流 FLOW" or string.format("能量 %d", math.floor(et.energy + 0.5))
	-- M7 锻点颜色:可斩(在窗口)=青绿发光,锁定=橘黄,无=淡白低调;命中/失误闪光
	local at = attack:getTelemetry()
	local rc
	if attackFlash > 0 then rc = Color3.fromRGB(60, 255, 140)      -- 命中闪青
	elseif attackFlash < 0 then rc = Color3.fromRGB(255, 70, 70)    -- 失误闪红
	elseif at.inVolume then rc = Color3.fromRGB(60, 255, 140)       -- 可斩
	elseif at.telegraph then rc = Color3.fromRGB(255, 180, 40)         -- 锁定
	else rc = Color3.fromRGB(180, 200, 220) end                     -- 平时
	local retAlpha = (at.telegraph or attackFlash ~= 0) and 0 or 0.55
	for _, b in ipairs(retParts) do b.BackgroundColor3 = rc; b.BackgroundTransparency = retAlpha end
	-- 【临时调试】判定盒渲染:青=平时,绿=盒内有目标(此刻按=必中),白=命中帧
	if handlingCfg:GetAttribute("Combat_DebugHitbox") then
		local fw = handlingCfg:GetAttribute("Combat_HitboxForward") or 12
		local bk = handlingCfg:GetAttribute("Combat_HitboxBack") or 2
		local sd = handlingCfg:GetAttribute("Combat_HitboxSide") or 7
		local up = handlingCfg:GetAttribute("Combat_HitboxUp") or 5
		hitboxViz.Size = Vector3.new(sd * 2, up * 2, fw + bk)
		hitboxViz.CFrame = CFrame.new(ctrl.physPos) * CFrame.Angles(0, ctrl.yaw, 0) * CFrame.new(0, 0, -(fw - bk) / 2)
		local hc
		if attackFlash > 0 then hc = Color3.fromRGB(255, 255, 255)
		elseif at.inVolume then hc = Color3.fromRGB(60, 255, 140)
		else hc = Color3.fromRGB(0, 220, 255) end
		hitboxViz.Color = hc; hitboxSel.Color3 = hc
		hitboxViz.Transparency = 0.85
		hitboxSel.Transparency = 0.2
	else
		hitboxViz.Transparency = 1
		hitboxSel.Transparency = 1
	end
	if attackFlash > 0 then attackFlash = math.max(0, attackFlash - dt * 3)
	elseif attackFlash < 0 then attackFlash = math.min(0, attackFlash + dt * 3) end
	local sprintOn = t.sprinting and t.speed > 100
	for i, f in ipairs(lines) do
		local target = sprintOn and (0.45 + 0.35 * math.abs(math.noise(clock * 9, i * 2.7))) or 1
		f.BackgroundTransparency += (target - f.BackgroundTransparency) * math.min(dt * 10, 1)
	end
end)