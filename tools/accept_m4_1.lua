--[[
NEON RUN — M4.1 重生与碰撞确定性+定步长 自动验收(Edit 仿真)
运行:MCP execute_luau(datamodel=Edit)或 Studio 命令栏粘贴。无需进 Play。
覆盖 design §E4 M4.1 验收清单:
  ① 入射角(5~90°)×速度(100/135/146)矩阵:定档正确(<20 擦 / ≥20 弹 / ≥55&速≥20 撞)
     + 全程零穿透零墙内帧 + 任意碰撞 vy 增量=0(永不为正)
  ② 石头 rig 同线 100 次逐位一致(定档一次性根治涌现分类)+ 零入石帧
  ③ 障碍防穿(白名单时代的垂直路径):重摔上非可骑面=硬撞转场;掠过顶面=钳位悬滑不落地不穿透
  ④ FixedStep 变帧率:23/47/61/144Hz 帧序列与纯 1/60 步序列逐位一致(ADR-33)
  ⑤ 锚点烘焙:三 lint 全过(kept 复检+rejected 理由正确)+ 射手前方剔除 + 弧长回取永不前进
     + 重生 0.5s 输入保护生效后恢复
  ⑥ 地面回归:直线 400 帧 drift/airborne/maxVy=0(白名单探针下);坡顶起飞(场景在则跑,先补 Tag 坑12)
坑 15::Clone() 强制重编译;坑 7:新 Config 键显式 SetAttribute。
测试台 NeonRunM41Rig @(-2400,200,-550)(坑 4:y≥200;距 WallRig 600 studs)。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local DT = 1 / 60

-- ---- 配置补种(坑 7)----
local hInst = nr.Config.Handling
for k, v in pairs({
	Collision_SideOffset = 1.1,
	Respawn_AnchorSpacingSec = 5, Respawn_SetbackAnchors = 0, Respawn_InputProtectSec = 0.5,
	Respawn_AnchorMaxTurnDeg = 6, Respawn_AnchorClearAheadStuds = 60,
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25, WallRide_ChainMaxTurnDeg = 8,
}) do hInst:SetAttribute(k, v) end

local BikeController = require(nr.Modules.BikeController:Clone())
local FixedStep = require(nr.Modules.FixedStep:Clone())
local Spline = require(nr.Modules.Spline:Clone())
local RespawnAnchors = require(nr.Modules.RespawnAnchors:Clone())

-- ---- 断言框架 ----
local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end

-- ---- M41Rig 测试台(Edit 期建,幂等)----
local FLOOR_TOP = 200
local rig = workspace:FindFirstChild("NeonRunM41Rig")
if not rig then
	rig = Instance.new("Folder"); rig.Name = "NeonRunM41Rig"; rig.Parent = workspace
	local floor = Instance.new("Part")
	floor.Name = "Floor"; floor.Anchored = true; floor.Size = Vector3.new(300, 2, 900)
	floor.Position = Vector3.new(-2400, FLOOR_TOP - 1, -550)
	floor.Color = Color3.fromRGB(55, 60, 75); floor.Parent = rig
	CS:AddTag(floor, "Rideable")
	-- 矩阵墙:普通障碍(无 Tag),贴面 x=-2281(-X 侧),z∈[-850,-250]
	local wall = Instance.new("Part")
	wall.Name = "MatrixWall"; wall.Anchored = true; wall.Size = Vector3.new(2, 20, 600)
	wall.Position = Vector3.new(-2280, FLOOR_TOP + 10, -550)
	wall.Color = Color3.fromRGB(120, 60, 60); wall.Parent = rig
	-- 石头簇:三块旋转盒(无 Tag=障碍;涌现分类的历史暴雷现场)
	local rocks = {
		{ Vector3.new(6, 5, 7), CFrame.new(-2400, FLOOR_TOP + 2, -700) * CFrame.Angles(0.3, 0.7, 0.15) },
		{ Vector3.new(4, 6, 5), CFrame.new(-2396, FLOOR_TOP + 3, -697) * CFrame.Angles(0.9, 0.2, 0.5) },
		{ Vector3.new(5, 3, 6), CFrame.new(-2404, FLOOR_TOP + 1.5, -702) * CFrame.Angles(0.2, 1.3, 0.8) },
	}
	for i, r in ipairs(rocks) do
		local p = Instance.new("Part")
		p.Name = "Rock" .. i; p.Anchored = true
		p.Size = r[1]; p.CFrame = r[2]
		p.Color = Color3.fromRGB(90, 85, 80); p.Parent = rig
	end
end
do -- 幂等补 Tag(坑 12)
	local floor = rig:FindFirstChild("Floor")
	if floor and not CS:HasTag(floor, "Rideable") then CS:AddTag(floor, "Rideable") end
end
local WALL_FACE_X = -2281   -- 矩阵墙贴面平面(-X 侧);穿透判据
local ROCKS = { rig:FindFirstChild("Rock1"), rig:FindFirstChild("Rock2"), rig:FindFirstChild("Rock3") }

-- ---- 测试摩托(最小模型)----
local bikeModel = Instance.new("Model"); bikeModel.Name = "M41TestBike"
local rootPart = Instance.new("Part")
rootPart.Name = "BikeRoot"; rootPart.Size = Vector3.new(2, 2.5, 7)
rootPart.Anchored = true; rootPart.CanCollide = false; rootPart.CanQuery = false
rootPart.Transparency = 0.5; rootPart.Parent = bikeModel
bikeModel.PrimaryPart = rootPart; bikeModel.Parent = workspace

local ctrl = BikeController.new(bikeModel)
local bounceCount, grazeCount, hardCount, respawnCount = 0, 0, 0, 0
ctrl:on("bounce", function() bounceCount += 1 end)
ctrl:on("graze", function() grazeCount += 1 end)
ctrl:on("hardHit", function() hardCount += 1 end)
ctrl:on("respawned", function() respawnCount += 1 end)
local function resetCounters() bounceCount, grazeCount, hardCount, respawnCount = 0, 0, 0, 0 end

-- 石头局部空间穿透检查(±half −0.05 内=在石头体内)
local function insideAnyRock(pos)
	for _, r in ipairs(ROCKS) do
		if r then
			local lp = r.CFrame:PointToObjectSpace(pos)
			local h = r.Size * 0.5
			if math.abs(lp.X) < h.X - 0.05 and math.abs(lp.Y) < h.Y - 0.05 and math.abs(lp.Z) < h.Z - 0.05 then
				return true
			end
		end
	end
	return false
end

-- ① 入射角×速度矩阵:定档/零穿透/vy 永不为正
do
	-- 阈值 20/55 两侧夹角覆盖;避开精确边界(asin(sin(x)) 浮点 ±ε 会翻档,坑 18)
	local ANGLES = { 5, 15, 18, 22, 40, 52, 57, 70, 90 }
	local SPEEDS = { { 100, false, false }, { 135, true, false }, { 145.8, true, true } }
	local matrixOK, penet, vyBad = true, 0, 0
	local detail = {}
	for _, sv in ipairs(SPEEDS) do
		local speed, sprint, flow = sv[1], sv[2], sv[3]
		for _, ang in ipairs(ANGLES) do
			local rad = math.rad(ang)
			local look = Vector3.new(math.sin(rad), 0, -math.cos(rad))  -- 朝墙(+X)偏 ang 度
			local start = Vector3.new(WALL_FACE_X - 25, FLOOR_TOP + 1.6, -420)
			ctrl:teleport(CFrame.lookAt(start, start + look))
			ctrl:setFlowBoost(flow)
			ctrl.curSpeed = speed
			resetCounters()
			local sawContact, class = false, nil
			local resets0 = ctrl.resetCount
			for f = 1, 240 do
				ctrl:setSteer(0); ctrl:setSprint(sprint); ctrl:setBrake(false)
				ctrl:step(DT)
				local tel = ctrl:getTelemetry()
				if ctrl.physPos.X > WALL_FACE_X + 0.01 then penet += 1 end
				if ctrl.vy > 0.001 then vyBad += 1 end
				if tel.wallContact and not sawContact then
					sawContact = true
					class = tel.contactClass
				end
				if tel.crashing or tel.respawning or ctrl.resetCount > resets0 then break end
				if sawContact and f > 200 then break end
			end
			local expect = (ang >= 55) and "hard" or (ang >= 20 and "bounce" or "graze")
			local got = class
			-- hard 以撞死/重生为准(contactClass 采样帧可能恰在 crash 转场后)
			if expect == "hard" and (hardCount > 0 or ctrl.resetCount > resets0) then got = "hard" end
			if got ~= expect then
				matrixOK = false
				detail[#detail + 1] = string.format("%d°@%.0f→%s(期望 %s)", ang, speed, tostring(got), expect)
			end
			-- 档位行为佐证
			if expect == "bounce" and bounceCount == 0 then
				matrixOK = false; detail[#detail + 1] = string.format("%d°@%.0f 无 bounce 事件", ang, speed)
			end
			if expect == "graze" and (bounceCount > 0 or hardCount > 0) then
				matrixOK = false; detail[#detail + 1] = string.format("%d°@%.0f 擦档却弹/撞", ang, speed)
			end
			ctrl:setFlowBoost(false)
		end
	end
	ok("① 定档矩阵 7 角×3 速全部正确", matrixOK, table.concat(detail, "; "))
	ok("① 全程零穿透零墙内帧", penet == 0, penet .. " 帧入墙")
	ok("① 碰撞 vy 增量=0(永不为正)", vyBad == 0, vyBad .. " 帧 vy>0")
end

-- ② 石头 rig 同线 100 次逐位一致 + 零入石帧
do
	local firstTrace, mismatch, inRock = nil, 0, 0
	for run = 1, 100 do
		local start = Vector3.new(-2404, FLOOR_TOP + 1.6, -560)
		ctrl:teleport(CFrame.lookAt(start, start + Vector3.new(0, 0, -1)))
		ctrl.curSpeed = 100
		local tr = {}
		for f = 1, 300 do
			ctrl:setSteer(0); ctrl:setSprint(true); ctrl:setBrake(false)
			ctrl:step(DT)
			tr[f] = string.format("%.17g,%.17g,%.17g", ctrl.physPos.X, ctrl.physPos.Y, ctrl.physPos.Z)
			if run == 1 and insideAnyRock(ctrl.physPos) then inRock += 1 end
		end
		local s = table.concat(tr, ";")
		if run == 1 then firstTrace = s
		elseif s ~= firstTrace then mismatch += 1 end
	end
	ok("② 石头同线 100 次逐位一致(定档一次性)", mismatch == 0, mismatch .. " 次不一致")
	ok("② 零入石帧", inRock == 0, inRock .. " 帧在石头体内")
end

-- ③ 障碍防穿(垂直路径):重摔=硬撞转场;掠过顶面=钳位悬滑
do
	-- 重摔:高处自由落体砸 Rock1 顶(横速 0,入射 ~90°,总速>20)
	local drop = Vector3.new(-2400, FLOOR_TOP + 30, -700)
	ctrl:teleport(CFrame.lookAt(drop, drop + Vector3.new(0, 0, -1)))
	local resets0 = ctrl.resetCount
	local tunneled = false
	for f = 1, 120 do
		ctrl:setSteer(0); ctrl:setSprint(false); ctrl:setBrake(false)
		ctrl:step(DT)
		if insideAnyRock(ctrl.physPos) then tunneled = true end
		if ctrl.resetCount > resets0 and not ctrl:isRespawning() then break end
	end
	ok("③ 重摔上石头=硬撞转场(resetCount+1)", ctrl.resetCount == resets0 + 1, ctrl.resetCount - resets0)
	ok("③ 重摔不穿石(零入石帧)", not tunneled, tunneled)
	-- 掠过:高横速低落差蹭石顶(入射 <55°)→ 钳位悬滑滑出,不落地在石头上、不撞、不穿
	local skim = Vector3.new(-2400, FLOOR_TOP + 7, -680)   -- Rock1 顶 ≈ y+5.5;从 +7 掠入
	ctrl:teleport(CFrame.lookAt(skim, skim + Vector3.new(0, 0, -1)))
	ctrl.curSpeed = 135
	resets0 = ctrl.resetCount
	local skimTunnel, groundedOnRock, passed = false, false, false
	for f = 1, 180 do
		ctrl:setSteer(0); ctrl:setSprint(true); ctrl:setBrake(false)
		ctrl:step(DT)
		if insideAnyRock(ctrl.physPos) then skimTunnel = true end
		local tel = ctrl:getTelemetry()
		if tel.grounded and insideAnyRock(ctrl.physPos - Vector3.new(0, 1.7, 0)) then groundedOnRock = true end
		if ctrl.physPos.Z < -712 then passed = true break end   -- 已越过石簇
	end
	ok("③ 掠石顶:滑出石簇(未撞死未卡死)", passed and ctrl.resetCount == resets0,
		string.format("passed=%s resets=%d", tostring(passed), ctrl.resetCount - resets0))
	ok("③ 掠石顶:不穿透不落地于石", (not skimTunnel) and (not groundedOnRock),
		string.format("tunnel=%s groundedOnRock=%s", tostring(skimTunnel), tostring(groundedOnRock)))
end

-- ④ FixedStep 变帧率一致性(ADR-33):23/47/61/144Hz vs 纯 1/60,按步逐位一致
do
	local function runSchedule(hz, totalSteps)
		local start = Vector3.new(-2450, FLOOR_TOP + 1.6, -150)
		ctrl:teleport(CFrame.lookAt(start, start + Vector3.new(0, 0, -1)))
		local fs = FixedStep.new()
		local tr = {}
		local function stepOnce(stepDt, k)
			-- 输入按步号编排(转向方波+冲刺方波;确定性输入序列)
			ctrl:setSteer((k % 120 < 60) and 1 or -1)
			ctrl:setSprint(k % 180 < 90)
			ctrl:setBrake(false)
			ctrl:step(stepDt)
			tr[k] = string.format("%.17g,%.17g,%.17g,%.17g", ctrl.physPos.X, ctrl.physPos.Y, ctrl.physPos.Z, ctrl.yaw)
		end
		if hz == nil then
			for k = 1, totalSteps do stepOnce(DT, k) end
		else
			local frameDt = 1 / hz
			while fs.stepCount < totalSteps do
				fs:update(frameDt, function(stepDt, k)
					if k <= totalSteps then stepOnce(stepDt, k) end
				end)
			end
		end
		return table.concat(tr, ";", 1, totalSteps)
	end
	local STEPS = 600
	local base = runSchedule(nil, STEPS)
	for _, hz in ipairs({ 23, 47, 61, 144 }) do
		ok(string.format("④ %dHz 帧序列与 1/60 逐位一致(%d 步)", hz, STEPS),
			runSchedule(hz, STEPS) == base, "步序列有分歧")
	end
end

-- ⑤ 锚点烘焙三 lint + 射手剔除 + 弧长永不前进 + 输入保护
do
	local pts = {
		Vector3.new(-2500, FLOOR_TOP, -200),
		Vector3.new(-2430, FLOOR_TOP, -400),
		Vector3.new(-2420, FLOOR_TOP, -650),
		Vector3.new(-2500, FLOOR_TOP, -880),
	}
	local sp = Spline.new(pts, false)
	local opts = { spacingStuds = 80, hover = 1.6, maxTurnDeg = 6, clearAheadStuds = 60 }
	local res = RespawnAnchors.bake(sp, opts)
	ok("⑤ 烘焙产出锚点 ≥5(样条 " .. math.floor(sp.Length) .. " studs)", #res.anchors >= 5, #res.anchors)
	-- kept 复检:每个锚点下方 2 studs 内必是白名单地面、锚点间 t 严格递增
	local recheckOK, mono = true, true
	local rpG = RaycastParams.new(); rpG.FilterType = Enum.RaycastFilterType.Include
	rpG.FilterDescendantsInstances = { workspace.Terrain, rig:FindFirstChild("Floor") }
	for i, a in ipairs(res.anchors) do
		local hit = workspace:Raycast(a.cf.Position, Vector3.new(0, -4, 0), rpG)
		if not hit then recheckOK = false end
		if i > 1 and a.t <= res.anchors[i - 1].t then mono = false end
	end
	ok("⑤ kept 锚点全过下射线复检", recheckOK, "有锚点悬空")
	ok("⑤ 锚点弧长严格递增", mono, "乱序")
	-- 射手前方剔除:样条中段放一个 ShooterEnemy,重烘焙应减锚
	local shooter = Instance.new("Part")
	shooter.Name = "M41TestShooter"; shooter.Anchored = true; shooter.CanCollide = false
	shooter.Size = Vector3.new(2, 4, 2); shooter.Position = sp:GetPoint(0.5) + Vector3.new(0, 3, 0)
	shooter.Parent = workspace
	CS:AddTag(shooter, "ShooterEnemy")
	local res2 = RespawnAnchors.bake(sp, opts)
	local shooterRejected = false
	for _, r in ipairs(res2.rejected) do
		if r.reason == "shooterAhead" then shooterRejected = true end
	end
	shooter:Destroy()
	ok("⑤ 射手前方锚点被剔除(lint③)", shooterRejected and #res2.anchors < #res.anchors,
		string.format("rejected=%s kept %d→%d", tostring(shooterRejected), #res.anchors, #res2.anchors))
	-- 弧长回取永不前进(pick 语义)
	local neverForward = true
	for i = 0, 40 do
		local curT = i / 40
		local a = RespawnAnchors.pick(res.anchors, curT, 0)
		if a and a.t > curT then neverForward = false end
	end
	ok("⑤ pick 永不前进(41 采样)", neverForward, "出现向前锚点")
	-- 运行时:装链→中途重生→回后方锚点+输入保护
	ctrl:setSpline(sp)
	ctrl:setAnchors(res.anchors)
	local start = sp:GetPoint(0)
	ctrl:setSpawnCF(CFrame.lookAt(start + Vector3.new(0, 1.6, 0), start + Vector3.new(0, 1.6, 0) + sp:GetTangent(0)))
	local midT = 0.62
	local midPos = sp:GetPoint(midT) + Vector3.new(0, 1.6, 0)
	ctrl:teleport(CFrame.lookAt(midPos, midPos + sp:GetTangent(midT)))
	ctrl:respawnNow()
	local backT = select(1, sp:NearestPoint(ctrl.physPos))
	ok("⑤ 重生回弧长 ≤ 当前(实 t=" .. string.format("%.3f", backT) .. " ≤ 0.62)", backT <= midT + 1e-3, backT)
	local tel = ctrl:getTelemetry()
	ok("⑤ 重生后输入保护开启", tel.inputProtected == true, tostring(tel.inputProtected))
	local yaw0 = ctrl.yaw
	for _ = 1, 24 do  -- 0.4s(窗口 0.5s 内):满舵应被保护清零
		ctrl:setSteer(1); ctrl:setSprint(true)
		ctrl:step(DT)
	end
	ok("⑤ 保护窗内满舵零转向(yaw 不变)", math.abs(ctrl.yaw - yaw0) < 1e-6, ctrl.yaw - yaw0)
	for _ = 1, 30 do  -- 越过窗口:恢复操控
		ctrl:setSteer(1); ctrl:setSprint(false)
		ctrl:step(DT)
	end
	ok("⑤ 保护窗后转向恢复", math.abs(ctrl.yaw - yaw0) > 0.05, ctrl.yaw - yaw0)
	ctrl:setSpline(nil); ctrl:setAnchors(nil)
end

-- ⑥ 地面回归:直线 400 帧(白名单探针)+ 坡顶起飞(场景在则跑)
do
	local start = Vector3.new(-2450, FLOOR_TOP + 1.6, -150)
	ctrl:teleport(CFrame.lookAt(start, start + Vector3.new(0, 0, -1)))
	local drift, airborne, maxVy = 0, 0, 0
	for f = 1, 400 do
		ctrl:setSteer(0); ctrl:setSprint(false); ctrl:setBrake(false)
		ctrl:step(DT)
		drift = math.max(drift, math.abs(ctrl.physPos.X - (-2450)))
		local tel = ctrl:getTelemetry()
		if not tel.grounded then airborne += 1 end
		maxVy = math.max(maxVy, math.abs(tel.vy or 0))
	end
	ok("⑥ 直线 400 帧 drift=0", drift == 0, drift)
	ok("⑥ 直线 400 帧 airborne=0", airborne == 0, airborne)
	ok("⑥ 直线 400 帧 maxVy=0", maxVy == 0, maxVy)
end
do
	local sceneHit = workspace:Raycast(Vector3.new(1500, 210, 130), Vector3.new(0, -60, 0))
	if sceneHit then
		local tagged = {}
		for z = 130, -560, -20 do
			local hit = workspace:Raycast(Vector3.new(1500, 260, z), Vector3.new(0, -120, 0))
			if hit and hit.Instance ~= workspace.Terrain and not CS:HasTag(hit.Instance, "Rideable") then
				CS:AddTag(hit.Instance, "Rideable")
				tagged[hit.Instance.Name] = true
			end
		end
		local names = {}
		for nm in pairs(tagged) do names[#names + 1] = nm end
		if #names > 0 then log[#log + 1] = "  ○ ⑥ 坡顶路径补 Rideable Tag(坑12):" .. table.concat(names, ",") end
		ctrl:teleport(CFrame.lookAt(Vector3.new(1500, 202.6, 130), Vector3.new(1500, 202.6, 30)))
		local flights, airborne, maxFlight, cur, prevG, landed = 0, 0, 0, 0, true, false
		for f = 1, 1200 do
			ctrl:setSteer(0); ctrl:setSprint(true); ctrl:setBrake(false)
			ctrl:step(DT)
			local g = ctrl.grounded
			if not g then airborne += 1; cur += 1; maxFlight = math.max(maxFlight, cur) end
			if g and not prevG then
				if cur > 3 then flights += 1 end
				cur = 0
				if flights >= 2 then landed = true break end
			end
			prevG = g
		end
		ok("⑥ 坡顶:flights=2 且落地", flights == 2 and landed, flights .. "/" .. tostring(landed))
		ok("⑥ 坡顶:airborne=117", airborne == 117, airborne)
		ok("⑥ 坡顶:maxFlight=85", maxFlight == 85, maxFlight)
		local e = ctrl.physPos
		ok(string.format("⑥ 坡顶:endPos≈(1500,-17.5,-538.2) 实(%.1f,%.1f,%.1f)", e.X, e.Y, e.Z),
			near(e.X, 1500, 0.5) and near(e.Y, -17.5, 0.5) and near(e.Z, -538.2, 0.5), tostring(e))
	else
		log[#log + 1] = "  ○ ⑥ 坡顶起飞:SKIP(本场景无沙丘;带正式场景会话复跑)"
	end
end

-- ---- 清理(测试摩托删;M41Rig 几何常驻)----
ctrl:destroy()
bikeModel:Destroy()

table.insert(log, 1, string.format("== M4.1 验收:%d 通过 / %d 失败 ==", pass, fail))
print(table.concat(log, "\n"))
return string.format("M4.1 accept: %d pass, %d fail", pass, fail)
