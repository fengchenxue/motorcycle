--[[
NEON RUN — 贴墙 90° 圆角过渡弯白盒(ADR-43;GR2 式圆滑弯角)
用法:MCP execute_luau(datamodel=Edit)或命令栏粘贴;幂等(重跑先删同名 rig 再重建)。
形态:直墙 A(180)→ 90° 圆角(四分之一圆弧,凹弯=外墙过弯的赛道语义)→ 直墙 B(140)。
圆弧=内接折线离散小面片(ADR-41 直墙链数据模型):顶点全落在理想圆弧上(半径语义=贴面半径),
单关节转角 JOINT_DEG ≤ Handling.WallRide_ChainMaxTurnDeg(现 8°,门禁不放宽),
面片两端加长 OVERLAP 搭接防缝(findContinuation 探针依赖搭接,勿设 0)。
车行有效半径:凹弯=R−悬浮1.6;(生成器支持 TURN_SIGN=-1 出凸弯,默认不建。)
选址 (-3800,200,-260) 起(坑 4:y≥200);距 accept_m8_5 迷你轨走廊 x=-3200 与各 rig ≥400。
调参:改下方常量重跑;RADIUS 6–8 由人类试玩拍板(status 待拍板)。
]]
local CS = game:GetService("CollectionService")

-- ==== 调参区 ====
local RADIUS = 7 -- 贴面圆弧半径 studs(人类拍板域 6–8)
local JOINT_DEG = 6 -- 单关节转角(须 ≤ WallRide_ChainMaxTurnDeg)
local TURN_SIGN = 1 -- +1=左弯凹圆角(赛道外墙语义);-1=右弯凸圆角(绕柱)
local WALL_T, WALL_H = 2, 30 -- 墙厚/墙高(=WallRig/Gauntlet 现场约定)
local OVERLAP = 0.35 -- 面片两端搭接加长
local LEN_A, LEN_B = 180, 140 -- 弯前/弯后直墙(A > 入墙混合距离 ~54@135)
local ORIGIN = Vector3.new(-3800, 200, -260) -- 墙线起点(Y=地板顶面)
local RIG_NAME = "NeonRunWallCornerRig"
-- ================

-- 链门禁自检:关节角必须过得了 findContinuation
local nrCfg = game:GetService("ReplicatedStorage"):FindFirstChild("NeonRun")
local hInst = nrCfg and nrCfg:FindFirstChild("Config") and nrCfg.Config:FindFirstChild("Handling")
local chainMax = (hInst and hInst:GetAttribute("WallRide_ChainMaxTurnDeg")) or 8
assert(JOINT_DEG <= chainMax + 1e-6, string.format(
	"JOINT_DEG=%d > ChainMaxTurnDeg=%s:必断链。调小 JOINT_DEG(或由人类拍板放宽门禁)", JOINT_DEG, tostring(chainMax)))

-- 幂等重建
local old = workspace:FindFirstChild(RIG_NAME)
if old then old:Destroy() end
local rig = Instance.new("Model")
rig.Name = RIG_NAME

-- ---- 墙贴面折线(顶点在贴面上,y=墙中心高;车走墙线左侧)----
local p = Vector3.new(ORIGIN.X, ORIGIN.Y + WALL_H / 2, ORIGIN.Z)
local dir = Vector3.new(0, 0, -1)
local verts, arcEdges = { p }, {}
local function fwd(len)
	p += dir * len
	verts[#verts + 1] = p
end
local function arc(totalDeg, r, turnSign)
	local steps = math.ceil(totalDeg / JOINT_DEG)
	local stepRad = math.rad(totalDeg / steps) * turnSign
	local center = p + Vector3.yAxis:Cross(dir).Unit * (r * turnSign)
	for _ = 1, steps do
		local rot = CFrame.Angles(0, stepRad, 0)
		p = center + rot:VectorToWorldSpace(p - center)
		dir = rot:VectorToWorldSpace(dir)
		arcEdges[#verts] = true -- 边 i:verts[i]→verts[i+1]
		verts[#verts + 1] = p
	end
	return steps
end

fwd(LEN_A)
local facets = arc(90, RADIUS, TURN_SIGN)
fwd(LEN_B)

-- ---- 面片墙(±X 贴面/Z 墙长约定,Size=(厚,高,长))----
local COL_STRAIGHT = Color3.fromRGB(95, 95, 105)
local COL_ARC_A = Color3.fromRGB(70, 130, 180)
local COL_ARC_B = Color3.fromRGB(110, 170, 215)
for i = 1, #verts - 1 do
	local v1, v2 = verts[i], verts[i + 1]
	local dirE = (v2 - v1).Unit
	local n = Vector3.yAxis:Cross(dirE).Unit -- 贴面外法线(车所在侧)
	local part = Instance.new("Part")
	part.Name = string.format("Wall_%03d", i)
	part.Anchored = true
	part.CanCollide = true
	part.Size = Vector3.new(WALL_T, WALL_H, (v2 - v1).Magnitude + 2 * OVERLAP)
	part.CFrame = CFrame.fromMatrix((v1 + v2) / 2 - n * (WALL_T / 2), n, Vector3.yAxis)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = arcEdges[i] and (i % 2 == 0 and COL_ARC_A or COL_ARC_B) or COL_STRAIGHT
	CS:AddTag(part, "WallRideSurface")
	part.Parent = rig
end

-- ---- 地板(折线 AABB+边距;Rideable 白名单)----
local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
for _, v in ipairs(verts) do
	minX = math.min(minX, v.X); maxX = math.max(maxX, v.X)
	minZ = math.min(minZ, v.Z); maxZ = math.max(maxZ, v.Z)
end
local MARGIN = 70 -- 走廊+出弯着陆余量
local floorPart = Instance.new("Part")
floorPart.Name = "Floor"
floorPart.Anchored = true
floorPart.Size = Vector3.new(maxX - minX + 2 * MARGIN, 2, maxZ - minZ + 2 * MARGIN)
floorPart.CFrame = CFrame.new((minX + maxX) / 2, ORIGIN.Y - 1, (minZ + maxZ) / 2)
floorPart.Material = Enum.Material.SmoothPlastic
floorPart.Color = Color3.fromRGB(40, 42, 48)
CS:AddTag(floorPart, "Rideable")
floorPart.Parent = rig

-- 发车提示垫(Rideable,免障碍判定;站上垫朝 -Z 沿墙骑、轻贴墙即入)
local pad = Instance.new("Part")
pad.Name = "StartPad"
pad.Anchored = true
pad.Size = Vector3.new(8, 0.4, 8)
pad.CFrame = CFrame.new(ORIGIN.X - 10, ORIGIN.Y + 0.2, ORIGIN.Z + 4)
pad.Material = Enum.Material.Neon
pad.Color = Color3.fromRGB(80, 220, 140)
CS:AddTag(pad, "Rideable")
pad.Parent = rig

rig:SetAttribute("Radius", RADIUS)
rig:SetAttribute("JointDeg", JOINT_DEG)
rig:SetAttribute("TurnSign", TURN_SIGN)
rig:SetAttribute("Overlap", OVERLAP)
rig:SetAttribute("WallT", WALL_T)
rig:SetAttribute("WallH", WALL_H)
rig:SetAttribute("ArcFacets", facets)
rig.Parent = workspace

local msg = string.format(
	"%s 已建:90° 圆角过渡弯 R=%d 关节=%d° 弧面片=%d 墙计=%d 起点=(%.0f,%.0f,%.0f)",
	RIG_NAME, RADIUS, JOINT_DEG, facets, #verts - 1, ORIGIN.X, ORIGIN.Y, ORIGIN.Z)
print(msg)
return msg
