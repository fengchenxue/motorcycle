--[[
NEON RUN — 贴墙 90° 圆角过渡弯自动验收(ADR-43;Edit 固定 dt=1/60 仿真,不需进 Play)
最小断言集:
  ① 圆角弯 R=7 × 速{100,135}:入墙后全程吸附(唯一一次退出=末墙尾)、净转向 +90°±2、
     出弯速度 ≥ 入弯−0.5、墙上高度零漂 ≤0.15
  ② 直墙链回归:两段共线搭接——跨段不弹出、单帧零转向、贴面距=悬浮高(折线行走不改直墙)
  ③ 配置钉扎还原(坑 27:不吃人类调参)
临时件建在 x=-4400 走廊(坑 4:y≥200),结束销毁;不触碰常驻台/正式赛道。
坑 3:模块 require(:Clone());坑 28:MCP 可能重复执行——脚本幂等(按名清理重建)。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local DT = 1 / 60

local BikeController = require(nr.Modules.BikeController:Clone())
local WallRideField = require(nr.Modules.WallRideField:Clone())

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end
local function datum(line) log[#log + 1] = "  ○ " .. line end

-- ---- 配置钉扎(存→钉→终还原)----
local hInst = nr.Config.Handling
local PIN = {
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25, WallRide_ChainMaxTurnDeg = 8,
	Speed_AccelTauSec = 0, Speed_SteerDragFrac = 0, -- ADR-46 基线钉(坑 30):源码默认已=hot 终值(τ0.9/0.05),回归必须钉回线性
	Steering_TurnRateHighDeg = 55, Steering_InputRampInSec = 0.12, -- 同上:锚点/轨迹基准按 55/0.12 校
	WallRide_FilletRadius = 0, -- ADR-45 圆角关:平面弯链与圆角正交,分开验收
}
local saved = {}
for k, v in pairs(PIN) do saved[k] = hInst:GetAttribute(k); hInst:SetAttribute(k, v) end

local TMP = "NeonRunWallCornerAccept_TMP"
local JOINT_DEG = 6
local WALL_T, WALL_H = 2, 30
local ORIGIN = Vector3.new(-4400, 200, -260)

local function cleanupTmp()
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name == TMP or inst.Name == TMP .. "_Bike" then inst:Destroy() end
	end
end

-- plan 元素:{kind="fwd",len} | {kind="arc",deg,r,sign}
local function buildWallLine(plan)
	local model = Instance.new("Model"); model.Name = TMP
	local p = Vector3.new(ORIGIN.X, ORIGIN.Y + WALL_H / 2, ORIGIN.Z)
	local dir = Vector3.new(0, 0, -1)
	local verts = { p }
	for _, seg in ipairs(plan) do
		if seg.kind == "fwd" then
			p += dir * seg.len
			verts[#verts + 1] = p
		else
			local steps = math.ceil(seg.deg / JOINT_DEG)
			local stepRad = math.rad(seg.deg / steps) * seg.sign
			local center = p + Vector3.yAxis:Cross(dir).Unit * (seg.r * seg.sign)
			for _ = 1, steps do
				local rot = CFrame.Angles(0, stepRad, 0)
				p = center + rot:VectorToWorldSpace(p - center)
				dir = rot:VectorToWorldSpace(dir)
				verts[#verts + 1] = p
			end
		end
	end
	local parts = {}
	for i = 1, #verts - 1 do
		local v1, v2 = verts[i], verts[i + 1]
		local dirE = (v2 - v1).Unit
		local n = Vector3.yAxis:Cross(dirE).Unit
		local part = Instance.new("Part")
		part.Name = string.format("W%03d", i)
		part.Anchored = true; part.CanCollide = true; part.Transparency = 0.4
		part.Size = Vector3.new(WALL_T, WALL_H, (v2 - v1).Magnitude + 0.7)
		part.CFrame = CFrame.fromMatrix((v1 + v2) / 2 - n * (WALL_T / 2), n, Vector3.yAxis)
		CS:AddTag(part, "WallRideSurface")
		part.Parent = model
		parts[i] = part
	end
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, v in ipairs(verts) do
		minX = math.min(minX, v.X); maxX = math.max(maxX, v.X)
		minZ = math.min(minZ, v.Z); maxZ = math.max(maxZ, v.Z)
	end
	local floorPart = Instance.new("Part")
	floorPart.Name = "Floor"; floorPart.Anchored = true; floorPart.Transparency = 0.4
	floorPart.Size = Vector3.new(maxX - minX + 260, 2, maxZ - minZ + 260)
	floorPart.CFrame = CFrame.new((minX + maxX) / 2, ORIGIN.Y - 1, (minZ + maxZ) / 2)
	CS:AddTag(floorPart, "Rideable")
	floorPart.Parent = model
	model.Parent = workspace
	return {
		model = model, verts = verts, parts = parts,
		firstDir = (verts[2] - verts[1]).Unit,
		lastEnd = verts[#verts],
	}
end

-- ---- 骑行仿真:入墙→过弯→链端退出;逐帧遥测 ----
local function ride(rig, opt)
	local bikeModel = Instance.new("Model"); bikeModel.Name = TMP .. "_Bike"
	local root = Instance.new("Part")
	root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
	root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.Transparency = 1
	root.Parent = bikeModel; bikeModel.PrimaryPart = root; bikeModel.Parent = workspace
	local ctrl = BikeController.new(bikeModel)
	local field = WallRideField.new()
	ctrl:setWallField(field)
	local along = rig.firstDir
	local n = Vector3.yAxis:Cross(along).Unit
	local startPos = rig.verts[1] + n * 10 + along * 8
	startPos = Vector3.new(startPos.X, rig.verts[1].Y - WALL_H / 2 + 1.6, startPos.Z)
	ctrl:teleport(CFrame.lookAt(startPos, startPos + (along - n * 0.35).Unit))
	ctrl.curSpeed = opt.speed
	local res = {
		exits = 0, wallFrames = 0, maxTickYawDeg = 0, attached = false,
		speedAtAttach = nil, speedLast = nil, yawAtAttach = nil, yawLast = nil,
		minY = math.huge, maxY = -math.huge, lastWallPos = nil,
	}
	local prevRiding, prevYaw, coast = false, nil, 0
	for _ = 1, opt.ticks or 900 do
		ctrl:setSteer(0)
		ctrl:setSprint(opt.sprint or false)
		ctrl:step(DT)
		local tel = ctrl:getTelemetry()
		if tel.wallRiding then
			res.wallFrames += 1
			if not res.attached then
				res.attached = true
				res.speedAtAttach = tel.speed
				res.yawAtAttach = ctrl.yaw
			elseif res.wallFrames == 13 and not res.yawPostBlend then
				res.yawPostBlend = ctrl.yaw -- ADR-45a:入墙 yaw 缓转(0.2s=12 帧),净转向从混合后起量
			end
			if prevRiding and prevYaw ~= nil then
				local d = math.deg(math.abs(math.atan2(math.sin(ctrl.yaw - prevYaw), math.cos(ctrl.yaw - prevYaw))))
				if d > res.maxTickYawDeg then res.maxTickYawDeg = d end
			end
			res.speedLast = tel.speed
			res.yawLast = ctrl.yaw
			res.minY = math.min(res.minY, ctrl.physPos.Y)
			res.maxY = math.max(res.maxY, ctrl.physPos.Y)
			res.lastWallPos = ctrl.physPos
		elseif prevRiding then
			res.exits += 1
		end
		prevRiding = tel.wallRiding
		prevYaw = ctrl.yaw
		if res.exits > 0 then
			coast += 1
			if coast >= 30 then break end
		end
	end
	ctrl:destroy(); bikeModel:Destroy(); field:destroy()
	return res
end

local function wrapDeg(rad) return math.deg(math.atan2(math.sin(rad), math.cos(rad))) end

-- ---- 主流程(pcall 包裹;无论成败均还原配置+清场)----
local RADIUS = 7
local okRun, runErr = pcall(function()
	cleanupTmp()

	-- ① 圆角过渡弯 R=7 两档速度
	for _, spd in ipairs({ { v = 100, sprint = false }, { v = 135, sprint = true } }) do
		cleanupTmp()
		local rig = buildWallLine({
			{ kind = "fwd", len = 120 },
			{ kind = "arc", deg = 90, r = RADIUS, sign = 1 },
			{ kind = "fwd", len = 120 },
		})
		local res = ride(rig, { speed = spd.v, sprint = spd.sprint })
		local label = string.format("①R%d v%d", RADIUS, spd.v)
		ok(label .. " 入墙且全程吸附(唯一退出=链端)", res.attached and res.exits == 1,
			string.format("attached=%s exits=%d wf=%d", tostring(res.attached), res.exits, res.wallFrames))
		local tailD = res.lastWallPos and
			(Vector3.new(res.lastWallPos.X, 0, res.lastWallPos.Z) - Vector3.new(rig.lastEnd.X, 0, rig.lastEnd.Z)).Magnitude or 999
		ok(label .. " 退出点=末墙尾(≤12)", tailD <= 12, string.format("%.1f", tailD))
		local net = res.yawLast and wrapDeg(res.yawLast - (res.yawPostBlend or res.yawAtAttach)) or 999
		ok(label .. " 净转向(混合后)=+90°±2", math.abs(net - 90) <= 2, string.format("%.2f", net))
		ok(label .. " 速度不减(≥入弯−0.5)", res.speedLast ~= nil and res.speedAtAttach ~= nil
			and res.speedLast >= res.speedAtAttach - 0.5,
			string.format("%s→%s", tostring(res.speedAtAttach), tostring(res.speedLast)))
		ok(label .. " 墙上高度零漂(≤0.15)", (res.maxY - res.minY) <= 0.15, string.format("%.3f", res.maxY - res.minY))
		datum(string.format("%s:最大单帧转角 %.1f°(理论 %.1f°,弯径=R−1.6)",
			label, res.maxTickYawDeg, math.deg((res.speedAtAttach or spd.v) * DT / (RADIUS - 1.6))))
	end

	-- ② 直墙链回归
	do
		cleanupTmp()
		local rig = buildWallLine({ { kind = "fwd", len = 120 }, { kind = "fwd", len = 120 } })
		local res = ride(rig, { speed = 100, sprint = false })
		ok("②直链:跨段不弹出且链端才退出", res.attached and res.exits == 1,
			string.format("exits=%d wf=%d", res.exits, res.wallFrames))
		ok("②直链:单帧零转向(≤0.01°)", res.maxTickYawDeg <= 0.01, string.format("%.4f", res.maxTickYawDeg))
		ok("②直链:速度恒定 100", res.speedAtAttach == 100 and res.speedLast == 100,
			string.format("%s→%s", tostring(res.speedAtAttach), tostring(res.speedLast)))
		local faceX = rig.verts[1].X -- 贴面平面 x;车在 −X 侧悬浮 1.6
		ok("②直链:贴面距=悬浮高(±0.01)", res.lastWallPos ~= nil
			and math.abs((faceX - res.lastWallPos.X) - 1.6) <= 0.01,
			res.lastWallPos and string.format("%.3f", faceX - res.lastWallPos.X) or "nil")
	end

	cleanupTmp()
end)

-- ---- 还原配置(坑 27)+ 终清场 ----
for k, v in pairs(saved) do hInst:SetAttribute(k, v) end
cleanupTmp()
ok("③配置还原:BlendSec 回人类调参值", hInst:GetAttribute("WallRide_BlendSec") == saved.WallRide_BlendSec,
	tostring(hInst:GetAttribute("WallRide_BlendSec")))
if not okRun then
	fail += 1
	log[#log + 1] = "  ✗ 运行时异常:" .. tostring(runErr)
end

local report = "accept_wallcorner(ADR-43):通过 " .. pass .. " / 失败 " .. fail .. "\n" .. table.concat(log, "\n")
print(report)
return report
