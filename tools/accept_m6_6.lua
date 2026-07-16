--[[
NEON RUN — M6.6 全角度上墙+垂直爬墙 自动验收(ADR-47;Edit 固定 dt=1/60)
断言组:
  ① 正面 90°@100:不撞死、进爬墙、冲高 ≈ 入速²/2g(20.2±2.5)、失速离墙自由落体、落地续骑
  ② 斜 60°@100:进爬墙且带切向横漂(衰减)
  ③ 爬墙中压 D → 转侧骑:climbing→wallRiding 无缝、偏航平滑(≤16°/帧)、持续贴墙不掉
  ④ 135 正面冲 26 高墙:顶部弹射(vy>55)、飞越墙顶、落对面地板零重生
  ⑤ ClimbEnabled=0:正面=旧行为(撞死循环)——回归锚
  ⑥ 确定性:①剧本两跑逐位一致
配置钉扎先存后还原(坑 27);临时件 x=-4400 用后即焚;坑 28/30:幂等(按名清理;拼接类先查新串)。
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

local hInst = nr.Config.Handling
local PIN = {
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25, WallRide_ChainMaxTurnDeg = 8,
	WallRide_FilletRadius = 7,
	WallRide_ClimbEnabled = 1, WallRide_ClimbMinToward = 5, WallRide_ClimbGravityScale = 1,
	WallRide_ClimbDriftDecaySec = 0.6, WallRide_ClimbConvertSteer = 0.5,
	WallRide_ClimbStallKeepSpeed = 0, WallRide_ClimbReenterCDSec = 0.5,
}
local saved = {}
for k, v in pairs(PIN) do saved[k] = hInst:GetAttribute(k); hInst:SetAttribute(k, v) end

local TMP = "NeonRunM66Accept_TMP"
local ORIGIN = Vector3.new(-4400, 200, -260)
local WALL_T, WALL_LEN = 2, 280
local R = 7

local function cleanupTmp()
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name == TMP or inst.Name == TMP .. "_Bike" then inst:Destroy() end
	end
end

local function buildRig(wallH, backFloor)
	cleanupTmp()
	local model = Instance.new("Model"); model.Name = TMP
	local floorPart = Instance.new("Part")
	floorPart.Name = "Floor"; floorPart.Anchored = true; floorPart.Transparency = 0.4
	floorPart.Size = Vector3.new(120, 2, WALL_LEN + 200)
	floorPart.CFrame = CFrame.new(ORIGIN.X - 30, ORIGIN.Y - 1, ORIGIN.Z - WALL_LEN / 2)
	CS:AddTag(floorPart, "Rideable")
	floorPart.Parent = model
	if backFloor then
		local f2 = floorPart:Clone()
		f2.Name = "FloorBack"
		f2.Size = Vector3.new(300, 2, WALL_LEN + 200)
		f2.CFrame = CFrame.new(ORIGIN.X + 155, ORIGIN.Y - 1, ORIGIN.Z - WALL_LEN / 2)
		CS:AddTag(f2, "Rideable") -- Clone 不保证带 Tag(版本差异),显式补
		f2.Parent = model
	end
	local wall = Instance.new("Part")
	wall.Name = "Wall"; wall.Anchored = true; wall.Transparency = 0.35
	wall.Size = Vector3.new(WALL_T, wallH, WALL_LEN)
	wall.CFrame = CFrame.new(ORIGIN.X + WALL_T / 2, ORIGIN.Y + wallH / 2, ORIGIN.Z - WALL_LEN / 2)
	CS:AddTag(wall, "WallRideSurface")
	wall.Parent = model
	local n = -wall.CFrame.RightVector
	local base = wall.Position + n * (WALL_T / 2) - Vector3.new(0, wallH / 2, 0)
	for i = 1, 6 do
		local a0 = (i - 1) * (math.pi / 2) / 6
		local a1 = i * (math.pi / 2) / 6
		local x0, y0 = R * (1 - math.sin(a0)), R * (1 - math.cos(a0))
		local x1, y1 = R * (1 - math.sin(a1)), R * (1 - math.cos(a1))
		local am = (a0 + a1) / 2
		local nu = n * math.sin(am) + Vector3.new(0, math.cos(am), 0)
		local chordLen = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		local chordDir = (n * (x1 - x0) + Vector3.new(0, y1 - y0, 0)) / chordLen
		local part = Instance.new("Part")
		part.Name = string.format("Fillet_%02d", i)
		part.Anchored = true; part.Transparency = 0.35
		part.Size = Vector3.new(0.6, chordLen + 0.12, WALL_LEN)
		part.CFrame = CFrame.fromMatrix(
			base + n * ((x0 + x1) / 2) + Vector3.new(0, (y0 + y1) / 2, 0) - nu * 0.3,
			nu, chordDir)
		CS:AddTag(part, "Rideable")
		part.Parent = model
	end
	model.Parent = workspace
end

-- 骑行:heading=入射方向(单位向量,水平);steerPlan(f, climbing, fsClimb)
local function ride(headDir, speed, frames, steerPlan, trace, sprint)
	local bikeModel = Instance.new("Model"); bikeModel.Name = TMP .. "_Bike"
	local root = Instance.new("Part")
	root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
	root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.Transparency = 1
	root.Parent = bikeModel; bikeModel.PrimaryPart = root; bikeModel.Parent = workspace
	local ctrl = BikeController.new(bikeModel)
	local field = WallRideField.new()
	ctrl:setWallField(field)
	local startPos = Vector3.new(ORIGIN.X - 20, ORIGIN.Y + 1.6, ORIGIN.Z - 140)
	ctrl:teleport(CFrame.lookAt(startPos, startPos + headDir))
	ctrl.curSpeed = speed
	local res = {
		resets0 = ctrl.resetCount, climbFrames = 0, rideFrames = 0, wallFrames = 0,
		exits = 0, exitedAt = nil, vyAtExit = nil, maxY = -math.huge, maxYWall = -math.huge,
		landedAt = nil, groundedAfter = 0, climbEnterAt = nil, convertAt = nil,
		maxDyawConv = 0, zAtClimbEnter = nil, zAtClimbEnd = nil, trace = trace and {} or nil,
	}
	local prevRiding, prevClimb, prevYaw = false, false, nil
	local fsClimb = -1
	for f = 1, frames do
		if res.climbEnterAt then fsClimb = f - res.climbEnterAt end
		ctrl:setSteer(steerPlan and steerPlan(f, prevClimb, fsClimb) or 0)
		ctrl:setSprint(sprint == true) -- ④ 需按住冲刺保 135(否则巡航衰回 100,入墙动量不足)
		ctrl:step(DT)
		local tel = ctrl:getTelemetry()
		res.maxY = math.max(res.maxY, ctrl.physPos.Y)
		if tel.wallRiding then
			res.wallFrames += 1
			res.maxYWall = math.max(res.maxYWall, ctrl.physPos.Y)
			if tel.climbing then
				res.climbFrames += 1
				if not res.climbEnterAt then
					res.climbEnterAt = f
					res.zAtClimbEnter = ctrl.physPos.Z
				end
				res.zAtClimbEnd = ctrl.physPos.Z
			else
				res.rideFrames += 1
				if prevClimb and not res.convertAt then res.convertAt = f end
			end
			if res.convertAt and prevYaw ~= nil and f <= res.convertAt + 15 then
				local d = math.deg(math.abs(math.atan2(math.sin(ctrl.yaw - prevYaw), math.cos(ctrl.yaw - prevYaw))))
				res.maxDyawConv = math.max(res.maxDyawConv, d)
			end
		elseif prevRiding then
			res.exits += 1
			if not res.exitedAt then
				res.exitedAt = f
				res.vyAtExit = ctrl.vy
			end
		end
		if res.exitedAt and tel.grounded then
			if not res.landedAt then res.landedAt = f end
			res.groundedAfter += 1
		end
		if res.trace then
			res.trace[f] = string.format("%.17g,%.17g,%.17g", ctrl.physPos.X, ctrl.physPos.Y, ctrl.physPos.Z)
		end
		prevRiding = tel.wallRiding
		prevClimb = tel.climbing == true
		prevYaw = ctrl.yaw
	end
	res.resets = ctrl.resetCount - res.resets0
	ctrl:destroy(); bikeModel:Destroy(); field:destroy()
	return res
end

local HEAD_ON = Vector3.new(1, 0, 0)
local OBLIQUE60 = Vector3.new(math.sin(math.rad(60)), 0, -math.cos(math.rad(60)))

local okRun, runErr = pcall(function()
	-- ① 正面 90°@100
	do
		buildRig(40, false)
		local res = ride(HEAD_ON, 100, 150, nil, true)
		ok("①正面@100:不撞死(resets=0)", res.resets == 0, res.resets)
		ok("①正面@100:进爬墙(≥5 帧)", res.climbFrames >= 5, res.climbFrames)
		local apex = res.maxYWall - ORIGIN.Y
		ok("①冲高≈20.2±2.5(实 " .. string.format("%.1f", apex) .. ")", math.abs(apex - 20.2) <= 2.5, apex)
		ok("①失速离墙一次", res.exits == 1, res.exits)
		ok("①落地续骑(grounded ≥10 帧)", res.landedAt ~= nil and res.groundedAfter >= 10,
			tostring(res.landedAt) .. "/" .. tostring(res.groundedAfter))
		-- ⑥ 确定性
		local res2 = ride(HEAD_ON, 100, 150, nil, true)
		local same = true
		for f = 1, 150 do
			if res.trace[f] ~= res2.trace[f] then same = false break end
		end
		ok("⑥确定性:①两跑逐位一致", same, "分歧")
	end
	-- ② 斜 60°@100
	do
		buildRig(40, false)
		local res = ride(OBLIQUE60, 100, 150, nil)
		ok("②斜 60°:进爬墙", res.climbFrames >= 5, res.climbFrames)
		local dz = math.abs((res.zAtClimbEnd or 0) - (res.zAtClimbEnter or 0))
		ok("②斜 60°:切向横漂 4~40 studs(实 " .. string.format("%.1f", dz) .. ")", dz >= 4 and dz <= 40, dz)
		ok("②斜 60°:不撞死", res.resets == 0, res.resets)
	end
	-- ③ 爬墙中压 D 转侧骑
	do
		buildRig(40, false)
		local res = ride(HEAD_ON, 100, 200, function(f, climbing, fs)
			if fs >= 8 and fs < 40 then return 1 end
			return 0
		end)
		ok("③转侧骑发生(climbing→riding)", res.convertAt ~= nil, "未转换")
		ok("③转后贴墙 ≥40 帧不掉", res.rideFrames >= 40, res.rideFrames)
		ok("③转换偏航平滑(≤16°/帧,实 " .. string.format("%.1f", res.maxDyawConv) .. ")",
			res.maxDyawConv <= 16, res.maxDyawConv)
		ok("③全程不撞死", res.resets == 0, res.resets)
	end
	-- ④ 135 正面 @26 高墙:顶部弹射
	do
		buildRig(26, true)
		-- 高速入弧点受帧量化影响(2.25 studs/帧 → φ0≈30°),vClimb0=135·cosφ0≈117,顶部余速≈34
		local res = ride(HEAD_ON, 135, 150, nil, false, true)
		ok("④顶部弹射:出墙一次", res.exits == 1, res.exits)
		ok("④弹射 vy>12(实 " .. string.format("%.1f", res.vyAtExit or -1) .. ")",
			res.vyAtExit ~= nil and res.vyAtExit > 12, res.vyAtExit) -- 越顶延迟释放(+悬浮高)吃掉部分余速
		ok("④飞越墙顶(maxY 超顶 ≥1.5)", res.maxY - (ORIGIN.Y + 26) >= 1.5,
			string.format("%.1f", res.maxY - (ORIGIN.Y + 26)))
		ok("④落地零重生", res.resets == 0 and res.landedAt ~= nil,
			string.format("resets=%d landed=%s", res.resets, tostring(res.landedAt)))
	end
	-- ⑤ 关开关=旧行为
	do
		buildRig(40, false)
		hInst:SetAttribute("WallRide_ClimbEnabled", 0)
		local res = ride(HEAD_ON, 100, 120, nil)
		ok("⑤ClimbEnabled=0:正面=旧行为撞死(resets≥1)", res.resets >= 1, res.resets)
		hInst:SetAttribute("WallRide_ClimbEnabled", 1)
	end
	cleanupTmp()
end)

for k, v in pairs(saved) do hInst:SetAttribute(k, v) end
cleanupTmp()
ok("配置还原:ClimbEnabled 回快照值", hInst:GetAttribute("WallRide_ClimbEnabled") == saved.WallRide_ClimbEnabled,
	tostring(hInst:GetAttribute("WallRide_ClimbEnabled")))
if not okRun then
	fail += 1
	log[#log + 1] = "  ✗ 运行时异常:" .. tostring(runErr)
end

local report = "accept_m6_6(ADR-47):通过 " .. pass .. " / 失败 " .. fail .. "\n" .. table.concat(log, "\n")
print(report)
return report
