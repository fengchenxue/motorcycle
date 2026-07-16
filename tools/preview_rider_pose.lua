--[[
NEON RUN — 骑姿预览台(ADR-50c;Edit 专用,MCP execute_luau 或命令栏粘贴)
用途:不进 Play 直接在 Edit 里看骑姿终值——标准 R15 假人 + 真摩托克隆 + 程序化长剑,
     姿态值 require 自 RiderRig(单一事实源:改 RiderRig 顶部 POSE 表→重跑本脚本即见)。
原理:CreateHumanoidModelFromDescription 的新版假人无 Motor6D(AnimationConstraint 骨架),
     故用 RigAttachment 反推 15 关节做纯数学 FK 直写件 CFrame(Edit 不步进物理,所见即所得)。
用法:重跑=幂等重建;顶部 CLEANUP=true 再跑一次=清场。脚本会把 Edit 相机含到预览位。
位置:PREVIEW_ORIGIN(默认 (-4650,500,-200) 高空隔离区,不碰赛道)。
]]
local CLEANUP = false                      -- true=只清场退出
local PREVIEW_ORIGIN = Vector3.new(-4650, 500, -200)

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

for _, inst in ipairs(workspace:GetChildren()) do
	if inst.Name:sub(1, 16) == "RiderPosePreview" then inst:Destroy() end
end
if CLEANUP then print("[preview_rider_pose] 已清场") return end

local RiderRig = require(RS.NeonRun.Modules.RiderRig:Clone())
local POSE = RiderRig.POSE_R15
local SADDLE = RiderRig.SADDLE
local GRIP = RiderRig.GRIP_TRAIL_R15
local BLADE_LEN = RiderRig.BLADE_LEN

local bike = workspace:WaitForChild("Motorcycle"):Clone()
bike.Name = "RiderPosePreview_Bike"
bike.Parent = workspace
bike:PivotTo(CFrame.new(PREVIEW_ORIGIN))
local root = bike.PrimaryPart

local char = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
char.Name = "RiderPosePreview_Dummy"
char.Parent = workspace
local hrp = char:WaitForChild("HumanoidRootPart")

-- R15 标准关节表(RigAttachment 定 C0/C1)
local JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", "RootRigAttachment" },
	{ "Waist", "LowerTorso", "UpperTorso", "WaistRigAttachment" },
	{ "Neck", "UpperTorso", "Head", "NeckRigAttachment" },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", "LeftShoulderRigAttachment" },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", "LeftElbowRigAttachment" },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", "LeftWristRigAttachment" },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", "RightShoulderRigAttachment" },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", "RightElbowRigAttachment" },
	{ "RightWrist", "RightLowerArm", "RightHand", "RightWristRigAttachment" },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", "LeftHipRigAttachment" },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", "LeftKneeRigAttachment" },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", "LeftAnkleRigAttachment" },
	{ "RightHip", "LowerTorso", "RightUpperLeg", "RightHipRigAttachment" },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", "RightKneeRigAttachment" },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", "RightAnkleRigAttachment" },
}
hrp.CFrame = root.CFrame * SADDLE
for _, d in ipairs(char:GetDescendants()) do
	if d:IsA("BasePart") then d.Anchored = true end
end
for _, j in ipairs(JOINTS) do
	local p0, p1 = char:FindFirstChild(j[2]), char:FindFirstChild(j[3])
	local a0 = p0 and p0:FindFirstChild(j[4])
	local a1 = p1 and p1:FindFirstChild(j[4])
	if p0 and p1 and a0 and a1 then
		p1.CFrame = p0.CFrame * (a0.CFrame * (POSE[j[1]] or CFrame.identity)) * a1.CFrame:Inverse()
	end
end

-- 程序化长剑(与 RiderRig.buildSword 同规格)
local function mkP(n, sz, col, mat, tr)
	local p = Instance.new("Part"); p.Name = n; p.Size = sz; p.Color = col; p.Material = mat
	p.Transparency = tr or 0; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CastShadow = false
	return p
end
local sword = Instance.new("Model"); sword.Name = "RiderPosePreview_Sword"; sword.Parent = workspace
local grip = mkP("Grip", Vector3.new(0.28, 1.15, 0.28), Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic); grip.Parent = sword
local guard = mkP("Guard", Vector3.new(0.95, 0.14, 0.4), Color3.fromRGB(70, 75, 95), Enum.Material.Metal); guard.Parent = sword
local blade = mkP("Blade", Vector3.new(0.24, BLADE_LEN, 0.14), Color3.fromRGB(200, 210, 230), Enum.Material.Metal); blade.Parent = sword
local edge = mkP("Edge", Vector3.new(0.08, BLADE_LEN, 0.2), Color3.fromRGB(90, 220, 255), Enum.Material.Neon, 0.1); edge.Parent = sword
grip.CFrame = char.RightHand.CFrame * GRIP
guard.CFrame = grip.CFrame * CFrame.new(0, 0.64, 0)
blade.CFrame = grip.CFrame * CFrame.new(0, 0.71 + BLADE_LEN / 2, 0)
edge.CFrame = blade.CFrame * CFrame.new(0, 0, -0.04)

-- 数值报告 + 相机含位(右后 3/4=玩家视角)
local inv = root.CFrame:Inverse()
local lhL = (inv * char.LeftHand.CFrame).Position
local tipL = (inv * (blade.CFrame * CFrame.new(0, BLADE_LEN / 2, 0))).Position
local cam = workspace.CurrentCamera
cam.CFrame = CFrame.lookAt(PREVIEW_ORIGIN + Vector3.new(10, 3, 11), PREVIEW_ORIGIN + Vector3.new(0, 0.5, 1))
cam.Focus = CFrame.new(PREVIEW_ORIGIN)
print(string.format("[preview_rider_pose] 就位@%s | 左手→把位距=%.2f | 剑尖局部(%.1f,%.1f,%.1f)",
	tostring(PREVIEW_ORIGIN), (lhL - Vector3.new(-0.5, 1.7, -1.6)).Magnitude, tipL.X, tipL.Y, tipL.Z))
print("[preview_rider_pose] 相机已对准(右后 3/4);自由查看=视口里滚轮/右键;清场=脚本顶部 CLEANUP=true 重跑")
