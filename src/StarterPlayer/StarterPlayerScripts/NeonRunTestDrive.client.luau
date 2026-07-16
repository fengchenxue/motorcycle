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
local BikeVFX = require(mods:WaitForChild("BikeVFX"))
local CombatVFX = require(mods:WaitForChild("CombatVFX"))
local WallRideField = require(mods:WaitForChild("WallRideField"))
local FixedStep = require(mods:WaitForChild("FixedStep"))
local RespawnAnchors = require(mods:WaitForChild("RespawnAnchors"))

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
-- M8.1 能量条红区(80~100)独立段:冒险段与蓝区分色渲染(80 分段义务,§4.5)
local energyBarRed = Instance.new("Frame")
energyBarRed.AnchorPoint = Vector2.new(0, 0.5)
energyBarRed.Position = UDim2.new(0.8, 0, 0.5, 0)
energyBarRed.Size = UDim2.new(0, 0, 1, -4)
energyBarRed.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
energyBarRed.BorderSizePixel = 0
energyBarRed.ZIndex = 1
energyBarRed.Parent = energyBarBG
-- M8.1 满槽 READY 脉冲描边(ADR-31 表现层:满槽 100=点燃资格)
local readyStroke = Instance.new("UIStroke")
readyStroke.Thickness = 0
readyStroke.Color = Color3.fromRGB(255, 255, 255)
readyStroke.Transparency = 1
readyStroke.Parent = energyBarBG
-- M8.1 "蓝区已满"轻提示 toast(capFull 事件;ADR-17 系统可拒绝但不能沉默)
local capFullToast = Instance.new("TextLabel")
capFullToast.AnchorPoint = Vector2.new(0.5, 1)
capFullToast.Position = UDim2.new(0.5, 0, 0, -6)
capFullToast.Size = UDim2.new(0, 160, 0, 20)
capFullToast.BackgroundTransparency = 1
capFullToast.TextColor3 = Color3.fromRGB(120, 220, 255)
capFullToast.TextStrokeTransparency = 0.4
capFullToast.TextSize = 14
capFullToast.Font = Enum.Font.GothamMedium
capFullToast.Text = "蓝区已满"
capFullToast.TextTransparency = 1
capFullToast.ZIndex = 4
capFullToast.Parent = energyBarBG

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
-- M6.5:授权贴墙段(WallRideSurface Tag 注册表;场上无 Tag 则永不入墙,零影响)
ctrl:setWallField(WallRideField.new())
-- M4.1(ADR-27):烘焙锚点链装载;发车位=隐式 0 号锚。未烘焙场景走 dev fallback(正式赛道必须烘焙)
ctrl:setSpawnCF(SPAWN)
local anchors = RespawnAnchors.load()
if anchors then ctrl:setAnchors(anchors) end
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
-- 碰撞火花(订阅 bounce/hardHit + 读 wallContact/crashing 拖火花)
local vfx = BikeVFX.new(bike, ctrl)

-- M5:能量系统(订阅 ctrl 事件) + 水晶场(拾取→加能);心流→相机档
local energy = EnergyState.new(ctrl)
-- ADR-42:回调返回入账 delta——蓝区已满时 addCrystal 返回 0 → 水晶不捕获、留在原地
local field = CrystalField.new(function() return energy:addCrystal() end)
energy:on("flowStart", function() rig:setFlow(true); ctrl:setFlowBoost(true) end)   -- ADR-31 心流升档接线
energy:on("flowEnd", function() rig:setFlow(false); ctrl:setFlowBoost(false) end)
-- M8.1 能量表现层:空箱红闪 / 点火尖峰 / 蓝区已满 toast(计时器在 RenderStepped 衰减)
local emptyFlash, igniteFlash, capFullT = 0, 0, 0
energy:on("emptyBox", function() emptyFlash = 1 end)   -- 0 能量按键:条闪红+抖动(干点火;咔哒音待 assetId)
energy:on("ignite", function() igniteFlash = 1 end)    -- 点火:条白亮尖峰
energy:on("capFull", function() capFullT = 0.8 end)    -- 蓝区已满:toast 0.8s

-- M7:攻击系统(自动锁定·时机判定·斩击点只在直线段);命中回能由 AttackSystem 内部调 energy
local spline = ctrl.spline
local attack = AttackSystem.new(ctrl, energy, spline)

-- 远程敌与快照子弹(ADR-21/22):射手本体/子弹经 AttackSystem 注册,弹反=改写目标为射手
local shooters = ShooterField.new(ctrl, attack, energy)
-- 战斗表现层(ADR-50):剑光(=判定窗可视化)/命中爆点/弹反闪/敌人装饰/子弹拖尾/战斗音
local cvfx = CombatVFX.new(bike, ctrl, attack, shooters)
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
-- M8.5 P4:分段门 Ts 优先读 TrackBuilder 烘焙属性(Track.CheckpointTs,与门拱/校验同源);无则模块默认
local checkpointTs = nil
do
	local trackFolder = cpFolder.Parent:FindFirstChild("Track")
	local s = trackFolder and trackFolder:GetAttribute("CheckpointTs")
	if type(s) == "string" and #s > 0 then
		checkpointTs = {}
		for num in string.gmatch(s, "[^,]+") do
			local v = tonumber(num)
			if v then checkpointTs[#checkpointTs + 1] = v end
		end
		if #checkpointTs == 0 then checkpointTs = nil end
	end
end
local timer = RaceTimer.new(ctrl, spline, { trackId = "Track01", laps = 1, closed = TRACK_CLOSED, checkpoints = checkpointTs })

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

-- 命中飘字(ADR-50 表现层):+能量合计/多杀 ×N/弹反击杀;0.6s 上浮淡出
local hitPop = Instance.new("TextLabel")
hitPop.AnchorPoint = Vector2.new(0.5, 1)
hitPop.Position = UDim2.new(0.5, 0, 0.40, 0)
hitPop.Size = UDim2.new(0, 240, 0, 30)
hitPop.BackgroundTransparency = 1
hitPop.Font = Enum.Font.GothamBlack
hitPop.TextSize = 22
hitPop.TextColor3 = Color3.fromRGB(60, 255, 140)
hitPop.TextStrokeTransparency = 0.4
hitPop.Text = ""
hitPop.TextTransparency = 1
hitPop.Parent = gui
local hitPopT = 0
local KIND_GAIN = { core = 25, gate = 15, slash = 30 }   -- 显示用;数字权威在 EnergyState
attack:on("hit", function(e)
	local sum, hasParry = 0, false
	for _, k in ipairs(e.kinds or {}) do
		sum += KIND_GAIN[k] or 0
		if k == "parry" then hasParry = true end
	end
	local txt
	if sum > 0 then txt = "+" .. sum
	elseif hasParry then txt = "弹反!"
	else txt = "斩!" end
	if (e.count or 1) > 1 then txt = txt .. " ×" .. e.count end
	hitPop.Text = txt
	hitPop.TextColor3 = Color3.fromRGB(60, 255, 140)
	hitPopT = 1
end)
shooters:on("enemyKilled", function(e)
	if e.cause == "parryReturn" then
		hitPop.Text = "弹反击杀 +25"
		hitPop.TextColor3 = Color3.fromRGB(60, 255, 180)
		hitPopT = 1
	end
end)

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

-- M8.1 分段门:把校验门渲染为可见霓虹拱门 + 过门弹 ±差值(§3.2;参照先用 PB/奖牌线,幽灵实体 M12)
-- 拱门=纯视觉标记(CanQuery=false 不参与碰撞/贴地);过门判定仍走 RaceTimer 参数化 t。
local gateArches = {}   -- [index] = { Part,.. }
local gateFlash = {}    -- [index] = 剩余闪光时长
do
	local checkpointTs = timer.checkpointTs or {}
	local archFolder = Instance.new("Folder")
	archFolder.Name = "NeonRunSegmentGates"
	archFolder.Parent = workspace
	local HALF_W, HEIGHT, BAR = 14, 15, 1.2
	local function mkBar(model, size, cframe)
		local p = Instance.new("Part")
		p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(0, 220, 255)
		p.Size = size
		p.CFrame = cframe
		p.Parent = model
		return p
	end
	for i, t in ipairs(checkpointTs) do
		local cf = spline:GetCFrame(t)
		local base, right, up = cf.Position, cf.RightVector, Vector3.new(0, 1, 0)
		local model = Instance.new("Model")
		model.Name = "SegGate" .. i
		local frames = {
			mkBar(model, Vector3.new(BAR, HEIGHT, BAR), CFrame.new(base + right * HALF_W + up * (HEIGHT / 2))),
			mkBar(model, Vector3.new(BAR, HEIGHT, BAR), CFrame.new(base - right * HALF_W + up * (HEIGHT / 2))),
			mkBar(model, Vector3.new(HALF_W * 2 + BAR, BAR, BAR), CFrame.new(base + up * HEIGHT)),
		}
		model.Parent = archFolder
		gateArches[i] = frames
		gateFlash[i] = 0
	end
end
-- 过门差值浮字(0.8s 淡出;绿=领先 / 红=落后 / 青=无参照只闪色)
local diffLabel = Instance.new("TextLabel")
diffLabel.AnchorPoint = Vector2.new(0.5, 0.5)
diffLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
diffLabel.Size = UDim2.new(0, 240, 0, 56)
diffLabel.BackgroundTransparency = 1
diffLabel.TextStrokeTransparency = 0.3
diffLabel.TextColor3 = Color3.fromRGB(120, 220, 255)
diffLabel.TextSize = 40
diffLabel.Font = Enum.Font.GothamBold
diffLabel.Text = ""
diffLabel.TextTransparency = 1
diffLabel.ZIndex = 6
diffLabel.Parent = gui
local diffT = 0
-- HUD 追赶角标(§3.2 常驻"追赶:<参照>")
local chaseLabel = Instance.new("TextLabel")
chaseLabel.AnchorPoint = Vector2.new(1, 0)
chaseLabel.Position = UDim2.new(1, -12, 0, 92)
chaseLabel.Size = UDim2.new(0, 170, 0, 20)
chaseLabel.BackgroundTransparency = 1
chaseLabel.TextXAlignment = Enum.TextXAlignment.Right
chaseLabel.TextColor3 = Color3.fromRGB(150, 200, 230)
chaseLabel.TextSize = 14
chaseLabel.Font = Enum.Font.GothamMedium
chaseLabel.Text = ""
chaseLabel.Parent = gui
local CHASE_CN = { PB = "PB", Bronze = "铜牌线", Silver = "银牌线", Gold = "金牌线", Author = "作者线" }
timer:on("checkpoint", function(p)
	local idx = p.index
	local ahead = p.diff and p.diff < 0
	local col = (p.diff == nil) and Color3.fromRGB(0, 220, 255)
		or (ahead and Color3.fromRGB(80, 255, 140) or Color3.fromRGB(255, 90, 110))
	if p.diff then
		diffLabel.Text = string.format("%s%.2f", ahead and "−" or "+", math.abs(p.diff))
	else
		diffLabel.Text = string.format("分段 %d/%d", idx, p.total)
	end
	diffLabel.TextColor3 = col
	diffT = 0.8
	local arch = gateArches[idx]
	if arch then
		for _, f in ipairs(arch) do f.Color = col end
		gateFlash[idx] = 0.8
	end
end)

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

-- M4.1(ADR-33):60Hz 定步长累加器——物理/经济/计时全部固定 dt,渲染插值在 RenderStepped
local fixed = FixedStep.new()
RunS.Heartbeat:Connect(function(dt)
	-- 输入采样(帧级;步内保持不变)
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
	fixed:update(dt, function(stepDt)
		ctrl:step(stepDt)
		timer:step(stepDt)  -- M8:计时/检查点/发车状态机(ctrl:step 后;计时=步数×1/60)
		-- M5:能量与水晶(ctrl:step 后,读最新遥测)
		energy:step(stepDt)
		field:step(bike.PrimaryPart and bike.PrimaryPart.Position or nil, stepDt)
		shooters:step(stepDt)  -- 射手节拍/子弹推进(attack:step 前:弹反缓冲优先于吃弹)
		attack:step(stepDt)  -- M7:维护锁定/窗口(ctrl:step 后,用最新位置)
	end)
	local t = ctrl:getTelemetry()
	local et = energy:getTelemetry()
	local at = attack:getTelemetry()
	local rt = timer:getTelemetry()
	audio:update(t, dt)
	vfx:step(dt)
	cvfx:step(dt)
	-- M8 计时/倒计时 HUD
	if rt.state == "countdown" then
		countdownLabel.Text = rt.countdown and tostring(rt.countdown) or ""
		timerLabel.Text = "0.00"
	elseif rt.state == "racing" then
		timerLabel.Text = string.format("%.2f", rt.time)
	end
	cpLabel.Text = string.format("检查点 %d/%d", rt.checkpoint, rt.totalCheckpoints)
	chaseLabel.Text = rt.chasing and ("追赶: " .. (CHASE_CN[rt.chasing] or rt.chasing)) or ""
	label.Text = string.format("M8 计时  |  速度 %d  |  能量 %d  |  %s%s%s%s  |  A/D·W/Shift冲·S刹·J斩·R重开",
		math.floor(t.speed + 0.5),
		math.floor(et.energy + 0.5),
		rt.state == "finished" and "完赛" or (rt.state == "countdown" and "发车"
			or (t.wallRiding and "贴墙" or (t.grounded and "地面" or "空中"))),
		t.sprinting and "·冲刺" or "",
		et.flow and "·心流!" or "",
		at.inVolume and "·可斩!" or "")
end)

local clock = 0
RunS.RenderStepped:Connect(function(dt)
	if not bike.PrimaryPart then return end
	ctrl:renderInterpolate(fixed:alpha())  -- M4.1:两物理步间插值写渲染位姿(高帧率平滑)
	rig:update(dt)
	vfx:cameraStep()  -- 冲刺速度线钉相机(必须在 rig:update 写完相机后,同帧零滞后)
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
	-- M5+M8.1 能量条:0~80 蓝区 / 80~100 红区双段渲染 + READY 脉冲 + 空箱红闪 + 点火尖峰
	local frac = et.frac
	local blueFrac = math.min(frac, 0.8)
	local redFrac = math.clamp(frac - 0.8, 0, 0.2)
	energyBarFill.Size = UDim2.new(blueFrac, -4, 1, -4)
	energyBarRed.Size = UDim2.new(redFrac, 0, 1, -4)
	local blueCol, redCol
	if et.flow then
		blueCol, redCol = Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255)  -- 心流白光
	elseif et.sprintGated then
		blueCol, redCol = Color3.fromRGB(120, 40, 40), Color3.fromRGB(120, 40, 40)      -- 空槽暗红
	else
		blueCol, redCol = Color3.fromRGB(0, 220, 255), Color3.fromRGB(255, 200, 60)      -- 蓝区青 / 红区金
	end
	if emptyFlash > 0 then   -- 空箱:整条闪红 + 抖动
		blueCol, redCol = Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 60, 60)
		emptyFlash = math.max(0, emptyFlash - dt / 0.25)
	end
	if igniteFlash > 0 then  -- 点火尖峰:白亮一下
		blueCol = blueCol:Lerp(Color3.fromRGB(255, 255, 255), igniteFlash)
		redCol = redCol:Lerp(Color3.fromRGB(255, 255, 255), igniteFlash)
		igniteFlash = math.max(0, igniteFlash - dt / 0.2)
	end
	energyBarFill.BackgroundColor3 = blueCol
	energyBarRed.BackgroundColor3 = redCol
	energyBarBG.Position = UDim2.new(0.5, (emptyFlash > 0 and math.sin(clock * 80) * 3 or 0), 1, -24)
	-- 满槽 READY 脉冲(未点燃):描边呼吸 + 文案(ADR-31 表现层)
	if et.ready then
		local pulse = 0.5 + 0.5 * math.sin(clock * 8)
		readyStroke.Thickness = 1 + 1.5 * pulse
		readyStroke.Transparency = 0.2 + 0.5 * (1 - pulse)
		energyText.Text = "READY ▸ 点火"
	else
		readyStroke.Thickness = 0
		readyStroke.Transparency = 1
		energyText.Text = et.flow and "心流 FLOW" or string.format("能量 %d", math.floor(et.energy + 0.5))
	end
	-- 蓝区已满 toast 淡出(0.8s)
	if capFullT > 0 then
		capFullT = math.max(0, capFullT - dt)
		capFullToast.TextTransparency = 1 - capFullT / 0.8
	else
		capFullToast.TextTransparency = 1
	end
	-- 分段门差值浮字淡出(0.8s)+ 拱门闪光复位 + 追赶角标
	if diffT > 0 then
		diffT = math.max(0, diffT - dt)
		diffLabel.TextTransparency = 1 - diffT / 0.8
	else
		diffLabel.TextTransparency = 1
	end
	for i, remain in pairs(gateFlash) do
		if remain > 0 then
			local nremain = math.max(0, remain - dt)
			gateFlash[i] = nremain
			if nremain == 0 and gateArches[i] then
				for _, f in ipairs(gateArches[i]) do f.Color = Color3.fromRGB(0, 220, 255) end
			end
		end
	end
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
	-- 命中飘字上浮淡出
	if hitPopT > 0 then
		hitPopT = math.max(0, hitPopT - dt * 1.6)
		hitPop.TextTransparency = 1 - math.min(hitPopT * 3, 1)
		hitPop.Position = UDim2.new(0.5, 0, 0.40 - (1 - hitPopT) * 0.05, 0)
	end
	local sprintOn = t.sprinting and t.speed > 100
	for i, f in ipairs(lines) do
		local target = sprintOn and (0.45 + 0.35 * math.abs(math.noise(clock * 9, i * 2.7))) or 1
		f.BackgroundTransparency += (target - f.BackgroundTransparency) * math.min(dt * 10, 1)
	end
end)