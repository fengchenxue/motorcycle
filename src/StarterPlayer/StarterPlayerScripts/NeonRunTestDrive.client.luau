-- NeonRun 试驾(M3+M2.1+M5+M7+M8):A/D 转向 | W/Shift 冲刺 | S 轻刹 | J 斩 | R 重开
-- 相机→CameraRig | 音效→BikeAudio | 能量→EnergyState+CrystalField | 攻击→AttackSystem | 计时→RaceTimer
local Players = game:GetService("Players")
local RunS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local GuiS = game:GetService("GuiService")
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
local RiderRig = require(mods:WaitForChild("RiderRig"))
local SprintUI = require(mods:WaitForChild("SprintUI"))
local RaceSFX = require(mods:WaitForChild("RaceSFX"))
local WallRideField = require(mods:WaitForChild("WallRideField"))
local FixedStep = require(mods:WaitForChild("FixedStep"))
local RespawnAnchors = require(mods:WaitForChild("RespawnAnchors"))

local wsNr = workspace:WaitForChild("NeonRun")
-- P4a(ADR-51)Streaming 就绪:样条优先读 ReplicatedStorage.NeonRun.TrackData(compile 烘焙的全量
-- 纯数据)。CP 球=BasePart 在 Streaming 下按距截断(坑 24),且客户端可能根本没有 CP01 可 Wait。
-- 旧场景/试炼道(无 TrackData)兜底走 CP 球原路径。
local splinePts, TRACK_CLOSED
do
	-- P4c:WaitForChild 带超时——客户端启动早期 RS 子件可能未复制完,FindFirstChild 竞态输了
	-- 会误入 CP 球兜底(流式下大厅附近无 CP 球=样条断言炸,人类回报"滞留大厅")
	local td = RS:WaitForChild("NeonRun"):WaitForChild("TrackData", 5)
	if td and td:GetAttribute("CP") then
		splinePts = {}
		for triple in string.gmatch(td:GetAttribute("CP"), "[^;]+") do
			local x, y, z = string.match(triple, "([^,]+),([^,]+),([^,]+)")
			splinePts[#splinePts + 1] = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
		end
		TRACK_CLOSED = td:GetAttribute("Closed") == true
	else
		local cpFolder = wsNr:WaitForChild("ControlPoints")
		local cps = cpFolder:GetChildren()
		table.sort(cps, function(a, b) return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0) end)
		splinePts = {}
		for _, cp in ipairs(cps) do
			if cp:IsA("BasePart") or cp:IsA("Attachment") then
				table.insert(splinePts, cp:IsA("Attachment") and cp.WorldPosition or cp.Position)
			end
		end
		TRACK_CLOSED = wsNr:GetAttribute("Closed")
		if TRACK_CLOSED == nil then TRACK_CLOSED = true end
		if workspace.StreamingEnabled then
			warn("[NeonRun] TrackData 缺失且 Streaming 开启:CP 球兜底可能不完整(坑 24)——正式赛道请先在 Edit 跑 tools/compile_track1.lua")
		end
	end
end
assert(splinePts and #splinePts >= 4,
	"[NeonRun] 样条点不足(TrackData 缺失且 CP 球未流入)——请在 Edit 跑 tools/compile_track1.lua 后再 Play")
-- P3f(人类反馈):游戏内隐藏控制点小球(LocalTransparencyModifier=纯客户端,Edit 期照常可见)
-- P4f 修:Streaming 下球随玩家移动才流入,启动一遍藏不全(坑24 变种);流出再流入=新实例
-- (客户端修饰符随实例销毁丢失)——ChildAdded 持续接住两种情况
do
	local function hideCp(inst)
		if inst:IsA("BasePart") then inst.LocalTransparencyModifier = 1 end
	end
	local cpFolder = wsNr:FindFirstChild("ControlPoints") or wsNr:WaitForChild("ControlPoints", 3)
	if cpFolder then
		for _, cp in ipairs(cpFolder:GetChildren()) do hideCp(cp) end
		cpFolder.ChildAdded:Connect(hideCp)
	end
end
local SPAWN = CFrame.lookAt(splinePts[1] + Vector3.new(0, 1.2, 0),
	Vector3.new(splinePts[2].X, splinePts[1].Y + 1.2, splinePts[2].Z))

-- 角色处置在 handlingCfg 就位后决定(ADR-50b):RiderEnabled=1 → 骑手上车;0 → 旧停机坪(见下方 rider 接线)

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
label.Visible = false   -- P4g 人类直令:顶部调试条默认隐藏(F2 开关);正式 HUD=秒表/CP/能量条自足
label.Parent = gui
TunePanel.mount(gui)
-- P4g PC 按键提示(右下角,仅非触屏;触屏端=图标按钮自说明)
local keyHint = Instance.new("TextLabel")
keyHint.AnchorPoint = Vector2.new(1, 1)
keyHint.Position = UDim2.new(1, -14, 1, -12)
keyHint.Size = UDim2.new(0, 480, 0, 18)
keyHint.BackgroundTransparency = 1
keyHint.TextXAlignment = Enum.TextXAlignment.Right
keyHint.TextColor3 = Color3.fromRGB(150, 200, 230)
keyHint.TextTransparency = 0.25
keyHint.TextStrokeTransparency = 0.7
keyHint.TextSize = 14
keyHint.Font = Enum.Font.GothamMedium
keyHint.Text = "A/D Steer   ·   W/Shift Sprint   ·   S Brake   ·   J Slash   ·   R Restart"
keyHint.Visible = not UIS.TouchEnabled
keyHint.Parent = gui

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
capFullToast.Position = UDim2.new(0.5, 0, 0, -40)   -- 速度读数占了条顶 -4~-34,toast 再上移(ADR-52)
capFullToast.Size = UDim2.new(0, 160, 0, 20)
capFullToast.BackgroundTransparency = 1
capFullToast.TextColor3 = Color3.fromRGB(120, 220, 255)
capFullToast.TextStrokeTransparency = 0.4
capFullToast.TextSize = 14
capFullToast.Font = Enum.Font.GothamMedium
capFullToast.Text = "CAP FULL"
capFullToast.TextTransparency = 1
capFullToast.ZIndex = 4
capFullToast.Parent = energyBarBG
-- 当前速度读数(ADR-52,人类拍板:能量条正上方组「速度大字+能量条」仪表盘簇+状态配色):
-- 数字=studs/s 原值(1 stud≈0.28m → 数值≈km/h,免换算);白=巡航/青=冲刺/金=心流,色语言同 SprintUI。
local speedLabel = Instance.new("TextLabel")
speedLabel.AnchorPoint = Vector2.new(0.5, 1)
speedLabel.Position = UDim2.new(0.5, 0, 0, -4)
speedLabel.Size = UDim2.new(0, 200, 0, 30)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(235, 245, 255)
speedLabel.TextStrokeTransparency = 0.6
speedLabel.TextSize = 30
speedLabel.Font = Enum.Font.GothamBlack
speedLabel.Text = "0"
speedLabel.ZIndex = 3
speedLabel.Parent = energyBarBG
local SPEED_TIER_COL = {
	[0] = Color3.fromRGB(235, 245, 255), -- 巡航白
	[1] = Color3.fromRGB(140, 230, 255), -- 冲刺青(=SprintUI THEME)
	[2] = Color3.fromRGB(255, 210, 110), -- 心流金(=SprintUI FLOW_GOLD)
}
local speedShown, speedTierShown = -1, -1

-- 冲刺 UI 动效(ADR-50g,借鉴场上搁置的 SprintCameraFX 方案B包络):爆发+残留速度线/边缘流光/心流金+入流闪
local sprintUI = SprintUI.new(gui)

-- P4a(ADR-51 补):摩托模板在 Streaming 下曾被克隆成空壳(Model 容器复制但零件按距流式,
-- 角色出生点离模板远=克隆时零件不在 → BikeController 无 BikeRoot 当场死,玩家滞留大厅)。
-- 模板已设 ModelStreamingMode=Persistent;此处再防御性等根件到位才克隆(双保险)。
local bikeTemplate = RS.NeonRun:FindFirstChild("Motorcycle") or workspace:WaitForChild("Motorcycle")
bikeTemplate:WaitForChild("BikeRoot")
local bike = bikeTemplate:Clone()
bike.Name = "TestDriveBike"
bike.Parent = workspace
bike:PivotTo(SPAWN)
local ctrl = BikeController.new(bike)
-- M4:赛道样条注入(P4a:点集与闭环标志已在文件头解析——TrackData 优先,CP 球兜底)
ctrl:setSpline(Spline.new(splinePts, TRACK_CLOSED))
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
local rsfx = RaceSFX.new(bike.PrimaryPart) -- 流程与状态音:事件→音效唯一映射(ADR-50j)
ctrl:on("respawned", function() rsfx:play("respawn") end)
-- 碰撞火花(订阅 bounce/hardHit + 读 wallContact/crashing 拖火花)
local vfx = BikeVFX.new(bike, ctrl)
-- ADR-50m:音效冷加载预载——CDN 冷取实测可 >3s,倒计时仅 ~3s,第一脚点火/首个流程音有概率哑;
-- 车根挂全部 BikeAudio/RaceSFX 声源,后台预载不阻塞启动(表现层:失败静默,顶多回到冷加载现状)
task.spawn(function()
	game:GetService("ContentProvider"):PreloadAsync({ bike })
end)

-- M5:能量系统(订阅 ctrl 事件) + 水晶场(拾取→加能);心流→相机档
local energy = EnergyState.new(ctrl)
-- ADR-42:回调返回入账 delta——蓝区已满时 addCrystal 返回 0 → 水晶不捕获、留在原地
local field = CrystalField.new(function()
	local gained = energy:addCrystal()
	if gained > 0 then rsfx:play("pickup") end -- 只在真入账时响:满箱不捕获=无声(ADR-42 语义一致)
	return gained
end)
energy:on("flowStart", function() rig:setFlow(true); ctrl:setFlowBoost(true) end)   -- ADR-31 心流升档接线
energy:on("flowEnd", function() rig:setFlow(false); ctrl:setFlowBoost(false) end)
-- M8.1 能量表现层:空箱红闪 / 点火尖峰 / 蓝区已满 toast(计时器在 RenderStepped 衰减)
local emptyFlash, igniteFlash, capFullT = 0, 0, 0
energy:on("emptyBox", function() emptyFlash = 1 end)   -- 0 能量按键:条闪红+抖动(干点火)
energy:on("emptyBox", function() rsfx:play("emptyBox") end) -- 干点火咔哒(M8.1 欠账清,ADR-50j)
energy:on("flowStart", function() rsfx:play("flow") end)    -- 心流升档 surge
energy:on("ignite", function() igniteFlash = 1 end)    -- 点火:条白亮尖峰
energy:on("capFull", function() capFullT = 0.8 end)    -- 蓝区已满:toast 0.8s

-- M7:攻击系统(自动锁定·时机判定·斩击点只在直线段);命中回能由 AttackSystem 内部调 energy
local spline = ctrl.spline
local attack = AttackSystem.new(ctrl, energy, spline)
ctrl:on("respawned", function() attack:reviveMercy() end) -- P3d:断口救济核随锚点重生复现(ADR-49b)

-- 远程敌与快照子弹(ADR-21/22):射手本体/子弹经 AttackSystem 注册,弹反=改写目标为射手
local shooters = ShooterField.new(ctrl, attack, energy)
-- 战斗表现层(ADR-50):剑光(=判定窗可视化)/命中爆点/弹反闪/敌人装饰/子弹拖尾/战斗音
local cvfx = CombatVFX.new(bike, ctrl, attack, shooters)
shooters:on("playerHit", function()
	crashFlash.BackgroundColor3 = Color3.fromRGB(255, 60, 110)
	crashFlash.BackgroundTransparency = 0.55
end)
shooters:on("playerHit", function() rsfx:play("playerHit") end)          -- 吃弹重击音(ADR-50j)
shooters:on("fired", function(e) rsfx:playAt("enemyFire", e.shooter) end) -- 敌火 pew:声从射手方位来,可听声辨位

-- 【临时调试】斩击判定盒可视化(开关=Handling 属性 Combat_DebugHitbox,属性面板实时切;正式版前移除)
-- 盒随物理系(physPos+yaw)走,尺寸实时读 Combat_Hitbox* 四键——调参数时盒子跟着变
local handlingCfg = RS:WaitForChild("NeonRun"):WaitForChild("Config"):WaitForChild("Handling")

-- 骑手上车(ADR-50b):玩家 avatar 焊上车+程序化长剑,出刀随判定窗挥砍;0=回旧停机坪
local riderRig
if (handlingCfg:GetAttribute("VFX_RiderEnabled") or 1) ~= 0 then
	riderRig = RiderRig.new(player, bike, attack, ctrl)
	-- 坑 34:Humanoid 每帧强制躯干 CanCollide=true(CanQuery=false 随之对射线失效)——
	-- 相机 popper 与障碍扫掠必须显式排除角色,否则骑手后背=幻影墙(相机被拉成伪第一人称)
	local function excludeChar(char)
		rig:setCharacterExclude(char)
		ctrl:setCharacterExclude(char)
	end
	if player.Character then excludeChar(player.Character) end
	player.CharacterAdded:Connect(excludeChar)
else
	task.spawn(function()
		local char = player.Character or player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart")
		task.wait(0.3)
		hrp.Anchored = true
		hrp.CFrame = CFrame.new(SPAWN.Position + Vector3.new(0, 150, 0))
	end)
end
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
	local trackFolder = wsNr:FindFirstChild("Track")   -- P4c 修:顶层 cpFolder 已删,残留引用=index nil 炸(滞留大厅真凶)
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
-- P3f:完赛线优先读 TrackBuilder 烘焙属性(Track.FinishT,结局大门同源);无则默认样条末端
local finishT = nil
do
	local trackFolder = workspace.NeonRun:FindFirstChild("Track")
	finishT = trackFolder and trackFolder:GetAttribute("FinishT") or nil
end
local timer = RaceTimer.new(ctrl, spline, { trackId = "Track1", laps = 1, closed = TRACK_CLOSED, checkpoints = checkpointTs, finishT = finishT })

-- M7 锻点 HUD 准星=已移除(P4d 人类直令"隐藏准星";可斩/锁定反馈由剑光弧+敌人充能装饰+命中飘字承担)
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
	elseif hasParry then txt = "PARRY!"
	else txt = "SLASH!" end
	if (e.count or 1) > 1 then txt = txt .. " ×" .. e.count end
	hitPop.Text = txt
	hitPop.TextColor3 = Color3.fromRGB(60, 255, 140)
	hitPopT = 1
end)
shooters:on("enemyKilled", function(e)
	if e.cause == "parryReturn" then
		hitPop.Text = "PARRY KILL +25"
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
restartBtn.Text = "RESTART (R)"
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

-- 奖牌显示名(P4g 英文化;顶牌改 CHAMPION=人类直令"作者牌太奇怪,改王者类";内部键仍 Author=代码/文档/Medals 口径不动)
local MEDAL_TXT = { Bronze = "🥉 BRONZE", Silver = "🥈 SILVER", Gold = "🥇 GOLD", Author = "👑 CHAMPION" }
timer:on("finish", function(res)
	settleMedal.Text = res.medal and MEDAL_TXT[res.medal] or "FINISHED"
	settleTime.Text = string.format("TIME %.2fs  ·  RESETS %d", res.time, res.resetCount)
	if res.nextMedal and res.gapToNext then
		settleGap.Text = string.format("%.2fs TO %s", res.gapToNext, MEDAL_TXT[res.nextMedal] or res.nextMedal)
	else
		settleGap.Text = "CHAMPION — TOP MEDAL!"
	end
	settlePanel.Visible = true
end)
timer:on("go", function() countdownLabel.Text = "GO!" end)
timer:on("countdown", function() rsfx:play("countdown") end) -- 3-2-1 beep(ADR-50j)
timer:on("go", function() rsfx:play("go") end)               -- GO=同 beep 升调
timer:on("finish", function() rsfx:play("finish") end)       -- 终点 sting(临时=beep 族低速)

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
		-- P3j(人类反馈"上部门框都是歪的"):CFrame.new=恒等旋转,横梁恒指世界 X——非轴向路段必歪;
		-- 改水平航向系:柱=世界竖直,梁=lookAt 水平航向(X 轴自然横跨路面),坡上路段也水平端正
		local look = cf.LookVector
		local lookH = Vector3.new(look.X, 0, look.Z)
		lookH = lookH.Magnitude > 1e-4 and lookH.Unit or Vector3.zAxis
		local rightH = Vector3.new(-lookH.Z, 0, lookH.X)
		local base, up = cf.Position, Vector3.new(0, 1, 0)
		local model = Instance.new("Model")
		model.Name = "SegGate" .. i
		local beamPos = base + up * HEIGHT
		local frames = {
			mkBar(model, Vector3.new(BAR, HEIGHT, BAR), CFrame.new(base + rightH * HALF_W + up * (HEIGHT / 2))),
			mkBar(model, Vector3.new(BAR, HEIGHT, BAR), CFrame.new(base - rightH * HALF_W + up * (HEIGHT / 2))),
			mkBar(model, Vector3.new(HALF_W * 2 + BAR, BAR, BAR), CFrame.lookAt(beamPos, beamPos + lookH)),
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
local CHASE_TXT = { PB = "PB", Bronze = "BRONZE", Silver = "SILVER", Gold = "GOLD", Author = "CHAMPION" }
timer:on("checkpoint", function(p)
	local idx = p.index
	local ahead = p.diff and p.diff < 0
	local col = (p.diff == nil) and Color3.fromRGB(0, 220, 255)
		or (ahead and Color3.fromRGB(80, 255, 140) or Color3.fromRGB(255, 90, 110))
	if p.diff then
		diffLabel.Text = string.format("%s%.2f", ahead and "−" or "+", math.abs(p.diff))
	else
		diffLabel.Text = string.format("CP %d/%d", idx, p.total)
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
	elseif input.KeyCode == Enum.KeyCode.F2 then
		label.Visible = not label.Visible   -- P4g 调试条开关
	elseif input.KeyCode == Enum.KeyCode.J
		or input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		-- M7 单键攻击(J / 左键 / 手柄R2);命中闪青,失误闪红
		if not timer:isControlLocked() then attack:attack() end  -- 反馈走 hit/whiff 事件
	end
end)

-- P4b 触控层(ADR-39 两拇指默认布局:左拇指◀▶转向,右拇指 冲刺按住+斩点按+刹;ADR-34 冲刺=按住)
-- 仅触屏设备显示;位置/尺寸=手感域常量供人调;爪握预设+键位自定义=M10 余项。
local touch = { left = false, right = false, sprint = false, brake = false }
if UIS.TouchEnabled then
	-- P4e:本作全程骑行无步行玩法——关系统默认触控(移动摇杆+跳跃钮),跨重生持久;自建按钮不走 TouchGui 不受影响
	GuiS.TouchControlsEnabled = false
	local BTN = 78          -- 主键边长(px)
	local BIG = 96          -- 冲刺键边长(右拇指主键)
	local M = 22            -- 屏缘留白
	-- P4g 图标化(人类直令"为移动端按钮绘制 UI 图标"):零资产程序化——圆形键+大字形图标+底部英文小标,
	-- 功能色描边(转向青/冲刺金/斩紫/刹红/R 白),V1 灰盒不引外部贴图
	local function mkBtn(icon, sub, accent, anchorX, posX, posY, size)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(anchorX, 1)
		b.Position = UDim2.new(anchorX, posX, 1, posY)
		b.Size = UDim2.new(0, size, 0, size)
		b.BackgroundColor3 = Color3.fromRGB(12, 18, 30)
		b.BackgroundTransparency = 0.45
		b.TextColor3 = accent
		b.TextSize = math.floor(size * 0.40)
		b.Font = Enum.Font.GothamBold
		b.Text = icon
		b.AutoButtonColor = false
		b.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = accent
		stroke.Thickness = 2
		stroke.Transparency = 0.35
		stroke.Parent = b
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)   -- 圆形键
		corner.Parent = b
		if sub then
			local s = Instance.new("TextLabel")
			s.AnchorPoint = Vector2.new(0.5, 1)
			s.Position = UDim2.new(0.5, 0, 1, -math.floor(size * 0.08))
			s.Size = UDim2.new(1, 0, 0, math.floor(size * 0.17))
			s.BackgroundTransparency = 1
			s.TextColor3 = accent
			s.TextTransparency = 0.25
			s.TextSize = math.max(10, math.floor(size * 0.14))
			s.Font = Enum.Font.GothamBold
			s.Text = sub
			s.Parent = b
		end
		b.Parent = gui
		return b
	end
	-- 按住键:InputBegan/Ended 各自捕获独立触点(左右手同时按住互不干扰)
	-- P4g 卡键根治(人类回报"冲刺流光出现后一直存在"):手指按住后滑出按钮再松手,GuiObject.InputEnded
	-- 不发(引擎只发给松手时指针所在元素)→ touch.sprint 永久卡 true=冲刺挂死——流光只是可见症状:
	-- 能量耗尽表现灭、拾晶自动复燃="中间出现"。修=活跃触点集+UIS.InputEnded 全局兜底逐触点核销。
	-- P4h 追加兜底(cancel 类卡键):切后台/Roblox 菜单夺走触点时引擎不发任何 InputEnded
	-- (P4g 的 UIS.InputEnded 兜底也收不到)→ 所有按住键触点集整体核销,杜绝"回前台后冲刺挂死"。
	local holdClears = {}
	local function bindHold(btn, set)
		local active = {}
		local function release(io)
			if active[io] then
				active[io] = nil
				if next(active) == nil then
					set(false)
					btn.BackgroundTransparency = 0.45
				end
			end
		end
		btn.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
				active[io] = true
				set(true)
				btn.BackgroundTransparency = 0.15
			end
		end)
		btn.InputEnded:Connect(release)   -- 快路径:松手时仍在钮上
		UIS.InputEnded:Connect(release)   -- 兜底:滑出按钮后松手(卡键真凶路径)
		holdClears[#holdClears + 1] = function()
			if next(active) ~= nil then
				table.clear(active)
				set(false)
				btn.BackgroundTransparency = 0.45
			end
		end
	end
	-- P4d 布局 v2(人类直令:R 移左侧,右侧重排)
	-- 左拇指:◀▶ 双键转向;R(低频)在 ◀ 正上方留 20px 距防误触
	-- 右拇指 L 形:拇指常驻「冲刺」(角落最大键,按住),上滚=「⚔斩」(次大,点按),左伸=「刹」(小,低频)
	local CYAN = Color3.fromRGB(0, 220, 255)
	bindHold(mkBtn("◀", nil, CYAN, 0, M, -M, BTN), function(v) touch.left = v end)
	bindHold(mkBtn("▶", nil, CYAN, 0, M + BTN + 14, -M, BTN), function(v) touch.right = v end)
	local rBtn = mkBtn("↻", nil, Color3.fromRGB(230, 235, 245), 0, M, -(M + BTN + 20), 52)
	rBtn.Activated:Connect(doRestart)
	bindHold(mkBtn("⚡", "SPRINT", Color3.fromRGB(255, 205, 80), 1, -M, -M, BIG), function(v) touch.sprint = v end)
	local slashBtn = mkBtn("⚔", "SLASH", Color3.fromRGB(200, 120, 255), 1, -M, -(M + BIG + 12), 84)
	slashBtn.Activated:Connect(function()
		if not timer:isControlLocked() then attack:attack() end
	end)
	bindHold(mkBtn("▼", "BRAKE", Color3.fromRGB(255, 110, 110), 1, -(M + BIG + 12), -M, 64), function(v) touch.brake = v end)
	-- P4h:cancel 类兜底接线——两事件都意味着"活跃触点已被系统夺走且不会再有 InputEnded"
	local function clearAllHolds()
		for _, f in ipairs(holdClears) do f() end
	end
	UIS.WindowFocusReleased:Connect(clearAllHolds)   -- 切后台/来电/系统手势
	GuiS.MenuOpened:Connect(clearAllHolds)           -- Roblox 主菜单夺触点
end

-- M4.1(ADR-33):60Hz 定步长累加器——物理/经济/计时全部固定 dt,渲染插值在 RenderStepped
local fixed = FixedStep.new()
RunS.Heartbeat:Connect(function(dt)
	-- 输入采样(帧级;步内保持不变)
	local steer = 0
	if UIS:IsKeyDown(Enum.KeyCode.A) or touch.left then steer += 1 end
	if UIS:IsKeyDown(Enum.KeyCode.D) or touch.right then steer -= 1 end
	ctrl:setSteer(steer)
	-- M8 发车标准化:倒计时/结算期间输入冻结(不存在抢跑)
	local locked = timer:isControlLocked()
	-- W=冲刺别名(与 Shift 等价,ADR-7);S=轻刹至 70%(刹车优先在 BikeController 处理);触控合并(P4b)
	ctrl:setSprint((not locked) and (UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift) or UIS:IsKeyDown(Enum.KeyCode.W) or touch.sprint))
	ctrl:setBrake((not locked) and (UIS:IsKeyDown(Enum.KeyCode.S) or touch.brake))
	if locked then ctrl:setSteer(0) end
	fixed:update(dt, function(stepDt)
		-- P3f 溜车修复(人类反馈):本作=自动前进,倒计时只锁输入挡不住 RampUp——绿灯前整台物理不走步
		-- (§8 发车标准化"车冻结直到绿灯"的落地;finished 不冻=冲线后滑行区可继续骑)
		local rtState = timer.state
		if rtState == "idle" or rtState == "countdown" then
			timer:step(stepDt)   -- 只推进发车状态机
			return
		end
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
	if riderRig then riderRig:step(dt) end
	-- M8 计时/倒计时 HUD
	if rt.state == "countdown" then
		countdownLabel.Text = rt.countdown and tostring(rt.countdown) or ""
		timerLabel.Text = "0.00"
	elseif rt.state == "racing" then
		timerLabel.Text = string.format("%.2f", rt.time)
	end
	cpLabel.Text = string.format("CP %d/%d", rt.checkpoint, rt.totalCheckpoints)
	chaseLabel.Text = rt.chasing and ("CHASE " .. (CHASE_TXT[rt.chasing] or rt.chasing)) or ""
	if label.Visible then   -- P4g:调试条默认隐藏(F2 开关),隐藏时不费字符串
		label.Text = string.format("DBG  |  SPD %d  |  EN %d  |  %s%s%s%s",
			math.floor(t.speed + 0.5),
			math.floor(et.energy + 0.5),
			rt.state == "finished" and "FINISH" or (rt.state == "countdown" and "START"
				or (t.wallRiding and "WALL" or (t.grounded and "GROUND" or "AIR"))),
			t.sprinting and "·SPRINT" or "",
			et.flow and "·FLOW!" or "",
			at.inVolume and "·SLASH!" or "")
	end
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
		energyText.Text = "READY ▸ IGNITE"
	else
		readyStroke.Thickness = 0
		readyStroke.Transparency = 1
		energyText.Text = et.flow and "FLOW" or string.format("ENERGY %d", math.floor(et.energy + 0.5))
	end
	-- 当前速度读数(ADR-52):值变才写字符串、档变才写色(t.speed=studs/s 物理真相,60Hz 定步已平滑)
	local spdInt = math.floor(t.speed + 0.5)
	if spdInt ~= speedShown then
		speedLabel.Text = tostring(spdInt)
		speedShown = spdInt
	end
	local spdTier = et.flow and 2 or (t.sprinting and 1 or 0)
	if spdTier ~= speedTierShown then
		speedLabel.TextColor3 = SPEED_TIER_COL[spdTier]
		speedTierShown = spdTier
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
	-- P4d:准星已移除;at 仍供【临时调试】判定盒配色
	local at = attack:getTelemetry()
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
	sprintUI:step(dt, t, (et.energy or 100) / 100)
end)