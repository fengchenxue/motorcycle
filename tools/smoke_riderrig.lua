--[[
NEON RUN — 骑手上车 RiderRig 冒烟(ADR-50b;Edit 固定 dt=1/60;R6 假人验证机制,R15 观感=Play 人工)
断言组:
  ① 挂载:鞍座焊(RiderSaddleWeld)+HRP 落位=root×SADDLE+Anchored=false
  ② 物性矫正:全件 CanQuery/CanCollide=false+Massless(防障碍扫掠幻影撞,硬要求)
  ③ Humanoid:PlatformStand=true
  ④ 骑姿:Right Shoulder C0 已乘偏移(≠原值)
  ⑤ 长剑:RiderSword(刃+霓虹锋)+SwordGrip Motor6D 挂右手
  ⑥ 挥砍(C0 通道,坑 35)+剑特效(ADR-50f):窄条拖痕挥砍开关;锋挥砍全亮;心流金退青;挥完 C0 归骑姿
  ⑦ 幂等:重复 mount 同角色不重焊不重剑
  ⑧ 卸载还原:C0 回原值/焊与剑消失/PlatformStand=false
  ⑨ 自愈轮询(坑 33):角色晚到自动上车/焊断重挂/离场卸载/回归重挂
  ⑩ 角色排除 API(坑 34)
  ⑪ 配置还原回快照
  ⑫ 新版骨架(AnimationConstraint,坑 35):骑姿/挥砍/还原走 attachment.CFrame 通道
钉扎先存后还原同脚本闭环(坑 27/32);临时件按名清理(坑 28);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local RiderRig = require(nr.Modules.RiderRig:Clone())
local DT = 1 / 60

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end
local function nearV3(a, b, eps) return (a - b).Magnitude <= (eps or 1e-3) end
local function nearCF(a, b)
	local d = a:ToObjectSpace(b)
	local ax, ang = d:ToAxisAngle()
	return d.Position.Magnitude < 1e-3 and math.abs(ang) < 1e-3
end

local hInst = nr.Config.Handling
local PIN = { Combat_InputBufferSec = 0.25, VFX_SlashSweepSec = 0.12, VFX_SwordStreakSec = 0.35 }
local saved = {}
for k in pairs(PIN) do saved[k] = hInst:GetAttribute(k) end
for k, v in pairs(PIN) do hInst:SetAttribute(k, v) end

local ORIGIN = Vector3.new(-4600, 600, -300)
local TMP = "NeonRunRiderSmoke_TMP"
for _, inst in ipairs(workspace:GetChildren()) do
	if inst.Name:sub(1, #TMP) == TMP then inst:Destroy() end
end

-- 测试摩托
local bikeModel = Instance.new("Model"); bikeModel.Name = TMP .. "_Bike"
local root = Instance.new("Part")
root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
root.Anchored = true; root.CanCollide = false; root.CanQuery = false
root.CFrame = CFrame.new(ORIGIN)
root.Parent = bikeModel
bikeModel.PrimaryPart = root
bikeModel.Parent = workspace

-- R6 假人(HRP+躯干+头+四肢,关节名按 R6 约定)
local function mkLimb(name, size, parent)
	local p = Instance.new("Part")
	p.Name = name; p.Size = size
	p.Anchored = false; p.CanCollide = true
	p.Parent = parent
	return p
end
local char = Instance.new("Model"); char.Name = TMP .. "_Dummy"
local hrp = mkLimb("HumanoidRootPart", Vector3.new(2, 2, 1), char)
hrp.Anchored = true
hrp.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 0, 40))
local torso = mkLimb("Torso", Vector3.new(2, 2, 1), char)
local head = mkLimb("Head", Vector3.new(1.2, 1.2, 1.2), char)
local rArm = mkLimb("Right Arm", Vector3.new(1, 2, 1), char)
local lArm = mkLimb("Left Arm", Vector3.new(1, 2, 1), char)
local rLeg = mkLimb("Right Leg", Vector3.new(1, 2, 1), char)
local lLeg = mkLimb("Left Leg", Vector3.new(1, 2, 1), char)
local function joint(name, p0, p1, c0, c1)
	local j = Instance.new("Motor6D")
	j.Name = name; j.Part0 = p0; j.Part1 = p1
	j.C0 = c0; j.C1 = c1 or CFrame.new()
	j.Parent = p0
	return j
end
joint("RootJoint", hrp, torso, CFrame.new())
joint("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.6, 0))
local rShoulder = joint("Right Shoulder", torso, rArm, CFrame.new(1, 0.5, 0) * CFrame.Angles(0, math.rad(90), 0), CFrame.new(-0.5, 0.5, 0))
joint("Left Shoulder", torso, lArm, CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, math.rad(-90), 0), CFrame.new(0.5, 0.5, 0))
joint("Right Hip", torso, rLeg, CFrame.new(1, -1, 0) * CFrame.Angles(0, math.rad(90), 0), CFrame.new(0.5, 1, 0))
joint("Left Hip", torso, lLeg, CFrame.new(-1, -1, 0) * CFrame.Angles(0, math.rad(-90), 0), CFrame.new(-0.5, 1, 0))
local humanoid = Instance.new("Humanoid")
humanoid.RigType = Enum.HumanoidRigType.R6
humanoid.Parent = char
char.Parent = workspace
local shoulderOrig = rShoulder.C0

-- attack 事件桩:捕获 swing 订阅
local swingFn
local atkStub = {}
function atkStub:on(name, fn)
	if name == "swing" then swingFn = fn end
end

-- player 桩:直接手动 mount(不走 CharacterAdded)
-- ctrl 桩:拖剑火花读 grounded/speed
local ctrlTele = { grounded = true, speed = 100, flowBoost = false }
local ctrlStub = {}
function ctrlStub:getTelemetry() return ctrlTele end

local rr = RiderRig.new(nil, bikeModel, atkStub, ctrlStub)
rr:mount(char)

-- ① 挂载
local weld = hrp:FindFirstChild("RiderSaddleWeld")
ok("①a 鞍座焊存在(Part0=root,Part1=HRP)", weld ~= nil and weld.Part0 == root and weld.Part1 == hrp, tostring(weld))
ok("①b HRP 落位=root×SADDLE(1.15) 且未锚定", nearV3(hrp.Position, (root.CFrame * CFrame.new(0, 1.7, 1.15)).Position) and hrp.Anchored == false,
	tostring(hrp.Position))

-- ② 物性矫正
do
	local bad = 0
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.CanQuery or d.CanCollide or not d.Massless then bad += 1 end
		end
	end
	ok("② 全件 CanQuery/CanCollide=false+Massless", bad == 0, bad .. " 件不合规")
end

-- ③④
ok("③ PlatformStand=true", humanoid.PlatformStand == true, tostring(humanoid.PlatformStand))
ok("④ 骑姿已上肩(C0≠原值)", not nearCF(rShoulder.C0, shoulderOrig), "C0 未变")

-- ⑤ 长剑
local sword = char:FindFirstChild("RiderSword")
local motor = rArm:FindFirstChild("SwordGrip")
ok("⑤a RiderSword 挂入(刃+霓虹锋)", sword ~= nil and sword:FindFirstChild("Blade") ~= nil and sword:FindFirstChild("Edge") ~= nil,
	tostring(sword))
ok("⑤b SwordGrip Motor6D 在右手", motor ~= nil and motor.Part1 == sword.PrimaryPart, tostring(motor))

-- ⑥ 挥砍(C0 通道,坑 35)+剑特效(ADR-50e 裁决后:锋辉光/心流金;刀光与火星已删)
do
	local edge = sword.Edge
	local streak = edge.SwordStreak
	ok("⑥a 火星/全刃刀光已删,窄条拖痕在位(附件距 1.0)", edge:FindFirstChild("DragSpark") == nil and edge:FindFirstChild("SwordTrail") == nil
		and streak ~= nil and (edge.SwordTipA.Position - edge.SwordTipB.Position).Magnitude == 1, "异常")
	ok("⑥b swing 事件已被订阅", swingFn ~= nil, "未订阅")
	local idleC0 = rShoulder.C0                     -- 骑姿基准(挥完应回这里;坑 35:C0 通道)
	swingFn()
	rr:step(DT)
	ok("⑥c 挥砍期肩 C0 离开骑姿+锋全亮+拖痕开", not nearCF(rShoulder.C0, idleC0) and edge.Transparency == 0 and streak.Enabled == true,
		tostring(streak.Enabled))
	for _ = 2, 35 do rr:step(DT) end               -- 0.58s > 起手0.06+窗0.25+回位0.25
	ok("⑥d 挥完 C0 归骑姿且闲+拖痕关", nearCF(rShoulder.C0, idleC0) and rr.swingT < 0 and streak.Enabled == false, tostring(rr.swingT))
	ctrlTele.flowBoost = true
	rr:step(DT)
	ok("⑥e 心流=剑变金", edge.Color == Color3.fromRGB(255, 200, 80), tostring(edge.Color))
	ctrlTele.flowBoost = false
	rr:step(DT)
	ok("⑥f 退心流=剑回青", edge.Color == Color3.fromRGB(90, 220, 255), tostring(edge.Color))
end

-- ⑦ 幂等
do
	rr:mount(char)
	local welds, swords = 0, 0
	for _, d in ipairs(char:GetDescendants()) do
		if d.Name == "RiderSaddleWeld" then welds += 1 end
		if d.Name == "RiderSword" then swords += 1 end
	end
	ok("⑦ 重复 mount 不重焊不重剑", welds == 1 and swords == 1, welds .. "/" .. swords)
end

-- ⑧ 卸载还原
do
	rr:destroy()
	local weldGone = hrp:FindFirstChild("RiderSaddleWeld") == nil
	local swordGone = char:FindFirstChild("RiderSword") == nil
	ok("⑧a 焊与剑消失", weldGone and swordGone, tostring(weldGone) .. "/" .. tostring(swordGone))
	ok("⑧b 肩 C0 回原值", nearCF(rShoulder.C0, shoulderOrig), "未还原")
	ok("⑧c PlatformStand 复位 false", humanoid.PlatformStand == false, tostring(humanoid.PlatformStand))
end

-- ⑨ 自愈轮询(修复版核心:事件式在 Play 竞态漏挂,坑 33)——角色晚到/焊断/离场/回归
do
	local playerStub = { Character = nil }
	local rr2 = RiderRig.new(playerStub, bikeModel, nil)
	rr2:step(DT)
	ok("⑨a 角色未到:不挂不炸", rr2.mounted == nil, tostring(rr2.mounted))
	playerStub.Character = char                  -- 角色"晚到"
	for _ = 1, 32 do rr2:step(DT) end            -- >0.5s 轮询窗
	ok("⑨b 自愈轮询自动上车", rr2.mounted ~= nil and hrp:FindFirstChild("RiderSaddleWeld") ~= nil, tostring(rr2.mounted))
	hrp.RiderSaddleWeld:Destroy()                -- 焊被外力清除
	for _ = 1, 32 do rr2:step(DT) end
	ok("⑨c 焊断自愈重挂", hrp:FindFirstChild("RiderSaddleWeld") ~= nil, "未重挂")
	playerStub.Character = nil                   -- 角色离场(死亡/重生间隙)
	for _ = 1, 32 do rr2:step(DT) end
	ok("⑨d 角色离场自动卸载", rr2.mounted == nil and humanoid.PlatformStand == false, tostring(rr2.mounted))
	playerStub.Character = char                  -- 回归
	for _ = 1, 32 do rr2:step(DT) end
	ok("⑨e 角色回归自动重挂", rr2.mounted ~= nil, tostring(rr2.mounted))
	rr2:destroy()
end

-- ⑩ 还原
-- ⑩ 角色排除 API(坑 34:Humanoid 强制 CanCollide=true→CanQuery 失效,popper/扫掠须显式排除)
do
	local BikeController = require(nr.Modules.BikeController:Clone())
	local CameraRig = require(nr.Modules.CameraRig:Clone())
	local cam = workspace.CurrentCamera
	local camCF, camType = cam.CFrame, cam.CameraType         -- CameraRig.new 会动相机,现场保护
	local ctrl2 = BikeController.new(bikeModel)
	local rig2 = CameraRig.new(cam, ctrl2)
	ctrl2:setCharacterExclude(char)
	rig2:setCharacterExclude(char)
	ok("⑩a 扫掠排除=模型+角色", #ctrl2.rp.FilterDescendantsInstances == 2 and ctrl2.rp.FilterDescendantsInstances[2] == char,
		#ctrl2.rp.FilterDescendantsInstances)
	ok("⑩b popper 排除=模型+角色", #rig2.rp.FilterDescendantsInstances == 2 and rig2.rp.FilterDescendantsInstances[2] == char,
		#rig2.rp.FilterDescendantsInstances)
	ctrl2:setCharacterExclude(nil)
	rig2:setCharacterExclude(nil)
	ok("⑩c 传 nil=清除回只排模型", #ctrl2.rp.FilterDescendantsInstances == 1 and #rig2.rp.FilterDescendantsInstances == 1,
		#ctrl2.rp.FilterDescendantsInstances .. "/" .. #rig2.rp.FilterDescendantsInstances)
	ctrl2:destroy()
	cam.CameraType = camType; cam.CFrame = camCF               -- 还原现场
end

-- ⑫ 新版骨架通道(坑 35:AnimationConstraint=写 Part0 侧 attachment.CFrame;2026 平台迁移实测已上线)
do
	local char2 = Instance.new("Model"); char2.Name = TMP .. "_AnimDummy"
	local hrp2 = mkLimb("HumanoidRootPart", Vector3.new(2, 2, 1), char2)
	local lower = mkLimb("LowerTorso", Vector3.new(2, 0.4, 1), char2)
	local upper = mkLimb("UpperTorso", Vector3.new(2, 1.6, 1), char2)
	local rua = mkLimb("RightUpperArm", Vector3.new(1, 1.4, 1), char2)
	hrp2.Anchored = true
	hrp2.CFrame = CFrame.new(ORIGIN + Vector3.new(30, 0, 40))
	local function animJoint(name, p0, p1, c0, c1)
		local a0 = Instance.new("Attachment"); a0.Name = name .. "RigAttachment"; a0.CFrame = c0; a0.Parent = p0
		local a1 = Instance.new("Attachment"); a1.Name = name .. "RigAttachment"; a1.CFrame = c1 or CFrame.new(); a1.Parent = p1
		local ac = Instance.new("AnimationConstraint")
		ac.Name = name; ac.Attachment0 = a0; ac.Attachment1 = a1; ac.Parent = p1
		return ac, a0
	end
	animJoint("Root", hrp2, lower, CFrame.new())
	local _, waistA0 = animJoint("Waist", lower, upper, CFrame.new(0, 0.2, 0))
	local _, shA0 = animJoint("RightShoulder", upper, rua, CFrame.new(1.2, 0.6, 0))
	local hum2 = Instance.new("Humanoid"); hum2.RigType = Enum.HumanoidRigType.R15; hum2.Parent = char2
	char2.Parent = workspace
	local waistOrig, shOrig = waistA0.CFrame, shA0.CFrame
	local swingFn2
	local atk2 = {}
	function atk2:on(n, f) if n == "swing" then swingFn2 = f end end
	local rr3 = RiderRig.new(nil, bikeModel, atk2)
	rr3:mount(char2)
	ok("⑫a 新骨架:骑姿写入 attachment(腰≠原值)", (waistA0.CFrame:ToObjectSpace(waistOrig)).Position.Magnitude > 1e-6
		or select(2, (waistA0.CFrame:ToObjectSpace(waistOrig)):ToAxisAngle()) > 1e-3, "未变")
	local shPose = shA0.CFrame
	swingFn2()
	rr3:step(DT)
	ok("⑫b 新骨架:挥砍写 attachment(肩离开骑姿)", select(2, (shA0.CFrame:ToObjectSpace(shPose)):ToAxisAngle()) > 1e-3, "未动")
	for _ = 2, 35 do rr3:step(DT) end
	ok("⑫c 新骨架:挥完归骑姿", (shA0.CFrame.Position - shPose.Position).Magnitude < 1e-3
		and select(2, (shA0.CFrame:ToObjectSpace(shPose)):ToAxisAngle()) < 1e-3, "未归位")
	rr3:destroy()
	ok("⑫d 新骨架:卸载还原 attachment 原值", select(2, (shA0.CFrame:ToObjectSpace(shOrig)):ToAxisAngle()) < 1e-3
		and select(2, (waistA0.CFrame:ToObjectSpace(waistOrig)):ToAxisAngle()) < 1e-3, "未还原")
	char2:Destroy()
end

char:Destroy(); bikeModel:Destroy()
for k in pairs(PIN) do hInst:SetAttribute(k, saved[k]) end
local restoreOK = true
for k in pairs(PIN) do
	if hInst:GetAttribute(k) ~= saved[k] then restoreOK = false end
end
ok("⑩ 配置还原回快照", restoreOK, "属性未回快照")

print(string.format("[smoke_riderrig] %d/%d 通过", pass, pass + fail))
for _, line in ipairs(log) do print(line) end
if fail > 0 then warn(string.format("[smoke_riderrig] %d 项失败", fail)) end
