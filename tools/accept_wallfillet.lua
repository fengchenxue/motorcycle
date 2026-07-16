--[[
NEON RUN — 地面→侧墙底部圆角过渡 自动验收(ADR-45;Edit 固定 dt=1/60 仿真)
断言组:
  ⓪ 圆角关(FilletRadius=0,裸墙):入墙首帧 up=墙法线(直角吸附旧语义,基线锚)
  ① 圆角开(R=7,带裙板):入墙首帧 up 近直立(up·Y>0.85)——90° 突变消灭的核心断言
  ② 持续爬升:up 单调滚向墙法线至 up·n>0.99,高度越过弧顶接直墙,不掉墙,速度恒定
  ③ 压 A 下行:穿弧回地——退出帧 up 近直立、≤8 帧落地、零硬撞/重生、落地续骑
  ④ 弧内驻留:无输入 120 帧,全程吸附、高度零漂(φ 恒定)、速度恒定
  ⑤ 确定性:②剧本两跑轨迹逐位一致
配置钉扎先存后还原(坑 27);临时件 x=-4400,用后即焚(坑 28:幂等)。坑 3:require(:Clone())。
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

-- ---- 配置钉扎 ----
local hInst = nr.Config.Handling
local PIN = {
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25, WallRide_ChainMaxTurnDeg = 8,
	Speed_AccelTauSec = 0, Speed_SteerDragFrac = 0, -- ADR-46 基线钉(坑 30):源码默认已=hot 终值(τ0.9/0.05),回归必须钉回线性
	Steering_TurnRateHighDeg = 55, Steering_InputRampInSec = 0.12, -- 同上:锚点/轨迹基准按 55/0.12 校
	WallRide_FilletRadius = 0, -- 各用例按需改;结束还原快照值
}
local saved = {}
for k, v in pairs(PIN) do saved[k] = hInst:GetAttribute(k); hInst:SetAttribute(k, v) end

local TMP = "NeonRunWallFilletAccept_TMP"
local ORIGIN = Vector3.new(-4400, 200, -260) -- 地板顶面高度=200(坑 4:y≥200)
local WALL_T, WALL_H, WALL_LEN = 2, 40, 280
local R = 7

local function cleanupTmp()
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name == TMP or inst.Name == TMP .. "_Bike" then inst:Destroy() end
	end
end

-- 裸墙台(墙底=地板顶);withSkirt=true 加圆弧裙板(Rideable 面片,几何同控制器解析圆角)
local function buildRig(withSkirt)
	cleanupTmp()
	local model = Instance.new("Model"); model.Name = TMP
	local floorPart = Instance.new("Part")
	floorPart.Name = "Floor"; floorPart.Anchored = true; floorPart.Transparency = 0.4
	floorPart.Size = Vector3.new(120, 2, WALL_LEN + 200)
	floorPart.CFrame = CFrame.new(ORIGIN.X - 30, ORIGIN.Y - 1, ORIGIN.Z - WALL_LEN / 2)
	CS:AddTag(floorPart, "Rideable")
	floorPart.Parent = model
	local wall = Instance.new("Part")
	wall.Name = "Wall"; wall.Anchored = true; wall.Transparency = 0.35
	wall.Size = Vector3.new(WALL_T, WALL_H, WALL_LEN)
	wall.CFrame = CFrame.new(ORIGIN.X + WALL_T / 2, ORIGIN.Y + WALL_H / 2, ORIGIN.Z - WALL_LEN / 2)
	-- 贴面 x=ORIGIN.X(−X 侧),墙底 y=ORIGIN.Y;车走西侧
	CS:AddTag(wall, "WallRideSurface")
	wall.Parent = model
	if withSkirt then
		local n = -wall.CFrame.RightVector -- 车侧(−X)
		local halfT, halfH = WALL_T / 2, WALL_H / 2
		local base = wall.Position + n * halfT - Vector3.new(0, halfH, 0)
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
	end
	model.Parent = workspace
	return { model = model, wall = wall }
end

-- 骑行仿真:进场→入墙→按 steerPlan 走 frames 帧;逐帧遥测
--   steerPlan(f, entered, fSinceEnter) -> steer
local function ride(rig, frames, steerPlan, trace, clearRampOnEnter)
	local bikeModel = Instance.new("Model"); bikeModel.Name = TMP .. "_Bike"
	local root = Instance.new("Part")
	root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
	root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.Transparency = 1
	root.Parent = bikeModel; bikeModel.PrimaryPart = root; bikeModel.Parent = workspace
	local ctrl = BikeController.new(bikeModel)
	local field = WallRideField.new()
	ctrl:setWallField(field)
	local along = Vector3.new(0, 0, -1)
	local n = Vector3.new(-1, 0, 0)
	local startPos = Vector3.new(ORIGIN.X - 12, ORIGIN.Y + 1.6, ORIGIN.Z - 8)
	ctrl:teleport(CFrame.lookAt(startPos, startPos + (along - n * 0.35).Unit))
	ctrl.curSpeed = 100
	local res = {
		enteredAt = nil, exitedAt = nil, wallFrames = 0, exits = 0,
		firstUp = nil, upDotN = {}, upDotY = {}, ys = {}, speeds = {},
		landedAt = nil, groundedAfterExit = 0, resets0 = ctrl.resetCount, resets = 0,
		trace = trace and {} or nil, maxH = -math.huge,
	}
	local prevRiding = false
	for f = 1, frames do
		local fSince = res.enteredAt and (f - res.enteredAt) or -1
		ctrl:setSteer(steerPlan and steerPlan(f, res.enteredAt ~= nil, fSince) or 0)
		ctrl:setSprint(false)
		ctrl:step(DT)
		local tel = ctrl:getTelemetry()
		if tel.wallRiding then
			res.wallFrames += 1
			if not res.enteredAt then
				res.enteredAt = f
				res.firstUp = tel.wallUp
				if clearRampOnEnter then ctrl.steer = 0; ctrl.rawSteer = 0 end -- 坑 17 入墙侧:隔离进场按键 ramp-out 残留
			end
			res.upDotN[#res.upDotN + 1] = tel.wallUp:Dot(n)
			res.upDotY[#res.upDotY + 1] = tel.wallUp.Y
			res.ys[#res.ys + 1] = ctrl.physPos.Y
			res.speeds[#res.speeds + 1] = tel.speed
			res.maxH = math.max(res.maxH, ctrl.physPos.Y - ORIGIN.Y)
		elseif prevRiding then
			res.exits += 1
			if not res.exitedAt then res.exitedAt = f end
		end
		if res.exitedAt and tel.grounded then
			if not res.landedAt then res.landedAt = f end
			res.groundedAfterExit += 1
		end
		if res.trace then
			res.trace[f] = string.format("%.17g,%.17g,%.17g,%.6f",
				ctrl.physPos.X, ctrl.physPos.Y, ctrl.physPos.Z, ctrl.yaw)
		end
		prevRiding = tel.wallRiding
	end
	res.resets = ctrl.resetCount - res.resets0
	ctrl:destroy(); bikeModel:Destroy(); field:destroy()
	return res
end

local okRun, runErr = pcall(function()
	-- ⓪ 圆角关基线(裸墙,直角吸附)
	do
		local rig = buildRig(false)
		hInst:SetAttribute("WallRide_FilletRadius", 0)
		local res = ride(rig, 120, function(f, entered) return entered and 0 or ((f <= 12) and -1 or 0) end)
		ok("⓪圆角关:入墙成功", res.enteredAt ~= nil, "未入墙")
		ok("⓪圆角关:首帧 up=墙法线(直角旧语义)", res.firstUp ~= nil and res.firstUp:Dot(Vector3.new(-1, 0, 0)) > 0.999,
			res.firstUp and string.format("%.3f", res.firstUp:Dot(Vector3.new(-1, 0, 0))) or "nil")
	end

	-- ①② 圆角开:入墙近直立 → 持续爬升滚到贴墙
	do
		local rig = buildRig(true)
		hInst:SetAttribute("WallRide_FilletRadius", R)
		-- 剧本:进场弯向墙;入墙后 5 帧起压爬升(steer=-1)40 帧;之后回中
		local plan = function(f, entered, fs)
			if not entered then return (f <= 12) and -1 or 0 end
			return (fs >= 5 and fs < 45) and -1 or 0
		end
		local res = ride(rig, 158, plan, true)
		ok("①圆角开:入墙成功", res.enteredAt ~= nil, "未入墙")
		ok("①圆角开:入墙首帧近直立(up·Y>0.85)", res.firstUp ~= nil and res.firstUp.Y > 0.85,
			res.firstUp and string.format("up·Y=%.3f", res.firstUp.Y) or "nil")
		datum(string.format("①入墙 φ0≈%.1f°(up·Y=%.3f)",
			math.deg(math.asin(math.clamp(res.firstUp and res.firstUp:Dot(Vector3.new(-1, 0, 0)) or 0, 0, 1))),
			res.firstUp and res.firstUp.Y or -1))
		-- 单调滚向墙法线
		local mono, maxDotN = true, -math.huge
		for i = 2, #res.upDotN do
			if res.upDotN[i] < res.upDotN[i - 1] - 1e-4 and res.upDotN[i] < 0.99 then mono = false end
		end
		for _, v in ipairs(res.upDotN) do maxDotN = math.max(maxDotN, v) end
		ok("②爬升:up 单调滚向墙法线至贴墙(max up·n>0.99)", mono and maxDotN > 0.99,
			string.format("mono=%s max=%.3f", tostring(mono), maxDotN))
		ok("②爬升:高度越过弧顶接直墙(maxH>R)", res.maxH > R, string.format("%.2f", res.maxH))
		ok("②爬升全程不掉墙(墙容量内)", res.exits == 0 and res.wallFrames > 120, string.format("exits=%d wf=%d", res.exits, res.wallFrames))
		local spdOK = true
		for _, v in ipairs(res.speeds) do
			if v ~= 100 then spdOK = false break end
		end
		ok("②全程速度恒定 100", spdOK, "有波动")
		datum(string.format("②爬到贴墙用时 %d 帧(理论 弧长(R−1.6)·π/2=8.5 studs ÷26≈20 帧)",
			(function()
				for i, v in ipairs(res.upDotN) do if v > 0.99 then return i end end
				return -1
			end)()))
		-- ⑤ 确定性:同剧本重跑
		local res2 = ride(rig, 158, plan, true)
		local same = true
		for f = 1, 158 do
			if res.trace[f] ~= res2.trace[f] then same = false break end
		end
		ok("⑤确定性:②剧本两跑轨迹逐位一致", same, "轨迹分歧")
	end

	-- ③ 下行穿弧回地
	do
		local rig = buildRig(true)
		hInst:SetAttribute("WallRide_FilletRadius", R)
		-- 入墙→爬到贴墙(40 帧)→压 A(steer=+1)下行直到出墙
		local res = ride(rig, 300, function(f, entered, fs)
			if not entered then return (f <= 12) and -1 or 0 end
			if fs < 45 then return (fs >= 5) and -1 or 0 end
			return 1
		end)
		ok("③下行:出墙发生", res.exitedAt ~= nil, "未出墙")
		local lastUpY = res.upDotY[#res.upDotY]
		ok("③下行:退出帧位姿近直立(up·Y>0.85)", lastUpY ~= nil and lastUpY > 0.85,
			lastUpY and string.format("%.3f", lastUpY) or "nil")
		ok("③下行:≤8 帧落地续骑", res.exitedAt and res.landedAt and (res.landedAt - res.exitedAt) <= 8,
			tostring(res.exitedAt) .. "→" .. tostring(res.landedAt))
		ok("③下行:零硬撞/重生", res.resets == 0, res.resets)
		ok("③下行:落地后持续在地(≥20 帧)", res.groundedAfterExit >= 20, res.groundedAfterExit)
	end

	-- ④ 弧内驻留(无输入)
	do
		local rig = buildRig(true)
		hInst:SetAttribute("WallRide_FilletRadius", R)
		local res = ride(rig, 140, function(f, entered) return entered and 0 or ((f <= 12) and -1 or 0) end, false, true)
		ok("④驻留:全程吸附不掉墙", res.enteredAt and res.exits == 0, string.format("exits=%d", res.exits))
		local minY, maxY = math.huge, -math.huge
		for i, y in ipairs(res.ys) do
			if i > 14 then -- 跳过混合窗(ADR-45a C¹ 混合期径向有意收敛,非漂移)
				minY = math.min(minY, y); maxY = math.max(maxY, y)
			end
		end
		ok("④驻留:高度零漂(混合后 ≤0.05)", (maxY - minY) <= 0.05, string.format("%.3f", maxY - minY))
	end

	cleanupTmp()
end)

for k, v in pairs(saved) do hInst:SetAttribute(k, v) end
cleanupTmp()
ok("配置还原:FilletRadius 回快照值", hInst:GetAttribute("WallRide_FilletRadius") == saved.WallRide_FilletRadius,
	tostring(hInst:GetAttribute("WallRide_FilletRadius")))
if not okRun then
	fail += 1
	log[#log + 1] = "  ✗ 运行时异常:" .. tostring(runErr)
end

local report = "accept_wallfillet(ADR-45):通过 " .. pass .. " / 失败 " .. fail .. "\n" .. table.concat(log, "\n")
print(report)
return report
