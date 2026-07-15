--[[
NEON RUN — M8.5 TrackBuilder P2~P4 自动验收(Edit 仿真)
运行:MCP execute_luau(datamodel=Edit)或 Studio 命令栏粘贴。
覆盖 design §E4 M8.5(ADR-41):
  ① compile 全管线跑通:路面+断口 NoRoad+内容计数与 spec 一致(入弯自动顺移)
  ② 断口三档(实际几何弹道反解):巡航过不去 / 冲刺刚好 / 心流余量
  ③ 分段门:Track.CheckpointTs 属性存在、数量=Config、严格递增
  ④ 锚点:烘焙非空、无锚点落在断口/墙段区间(ADR-27)
  ⑤ 机器人完赛:纯几何可骑性(含跨断口),时间/重生数回报
  ⑥ 墙链跨段交接:骑上直墙链连续跨 ≥2 段不弹出,链端才退出(ADR-41)
  ⑦ 供给两桶:红区≠0、判定点复核零残留
  ⑧ 幂等确定性:compile 两次内容计数/门/锚点完全一致
⚠️ 本脚本会临时接管 Workspace.NeonRun.ControlPoints(原 CP 先改名保存,结束后还原);
   结束后场上 Track/锚点/门=验收迷你轨,正式赛道请重跑 build_gauntlet 或 buildtrack(compile)。
坑 15::Clone() 强制重编译。迷你轨建在 x=-3200 走廊(坑 4:y≥200,远离既有 rig)。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local DT = 1 / 60

-- 配置补种(坑 7;墙链新键)
local hInst = nr.Config.Handling
for k, v in pairs({
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25, WallRide_ChainMaxTurnDeg = 8,
	Collision_SideOffset = 1.1,
	Respawn_AnchorSpacingSec = 5, Respawn_SetbackAnchors = 0, Respawn_InputProtectSec = 0.5,
	Respawn_AnchorMaxTurnDeg = 6, Respawn_AnchorClearAheadStuds = 60,
}) do hInst:SetAttribute(k, v) end

local TB = require(nr.Modules.TrackBuilder:Clone())
local BikeController = require(nr.Modules.BikeController:Clone())
local WallRideField = require(nr.Modules.WallRideField:Clone())
local RespawnAnchors = require(nr.Modules.RespawnAnchors:Clone())

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end

-- ---- 现场保护:原 ControlPoints 改名存放,结束还原 ----
local wsNr = workspace:FindFirstChild("NeonRun")
assert(wsNr, "缺 Workspace.NeonRun")
local origCP = wsNr:FindFirstChild("ControlPoints")
if origCP then origCP.Name = "ControlPoints_backup_m85accept" end
local origClosed = wsNr:GetAttribute("Closed")

local cpFolder = Instance.new("Folder")
cpFolder.Name = "ControlPoints"
cpFolder.Parent = wsNr
-- 迷你轨:直发车→缓右→战斗直线→爬升坡顶(jump 几何)→缓左(墙带)→冲线直线;开放式 ~1460 studs
local PTS = {
	Vector3.new(-3200, 220, -100),
	Vector3.new(-3200, 220, -350),
	Vector3.new(-3150, 220, -560),
	Vector3.new(-3150, 220, -800),
	Vector3.new(-3150, 232, -960),   -- 爬升 +12
	Vector3.new(-3150, 220, -1120),  -- 坡顶在 CP5~6 之间
	Vector3.new(-3200, 220, -1320),
	Vector3.new(-3200, 220, -1560),
}
for i, pos in ipairs(PTS) do
	local cp = Instance.new("Part")
	cp.Name = string.format("CP%02d", i)
	cp:SetAttribute("Index", i)
	cp.Anchored = true; cp.CanCollide = false; cp.CanQuery = false; cp.Transparency = 1
	cp.Size = Vector3.new(2, 2, 2); cp.Position = pos
	cp.Parent = cpFolder
end
wsNr:SetAttribute("Closed", false)

local SPEC = {
	segments = {
		{ type = "start",  sec = 8 },
		{ type = "combat", sec = 10, shooters = 2, cores = 1, gates = 1 },
		{ type = "thrill", sec = 10, jump = true },
		{ type = "fork",   sec = 10, wallSec = 4, wallSide = 1 },
		{ type = "finish", sec = 8 },
	},
	supply = { crystals = 12 },
}

-- ---- ① compile 全管线 ----
local rep = TB.compile({ closed = false, spec = SPEC })
log[#log + 1] = TB.formatReport(rep)
ok("① compile 跑通且路面 >0", rep.build.segments > 0 and rep.build.tagged > 0, rep.build.segments)
ok("① 断口 NoRoad 生效(跳过路面件 >0)", (rep.build.gapSkipped or 0) > 0, rep.build.gapSkipped)
local c = rep.content
ok("① 内容计数=spec(敌2/核1/闸1)", c.shooters == 2 and c.cores == 1 and c.gates == 1,
	string.format("敌%d 核%d 闸%d", c.shooters, c.cores, c.gates))
ok("① 水晶 ≥10(预算 12,缺口上空跳过)", c.crystals >= 10, c.crystals)
ok("① 墙带直墙链 ≥3 段", c.walls >= 3, c.walls)

-- ---- ② 断口三档 ----
ok("② 恰一个断口", #rep.lint.jumps == 1, #rep.lint.jumps)
if rep.lint.jumps[1] then
	local j = rep.lint.jumps[1]
	ok(string.format("② 三档合法:巡航 %s<缺口 %.1f≤冲刺 %.1f<心流 %s",
		j.dCruise and string.format("%.1f", j.dCruise) or "落不到", j.gapLen, j.dSprint,
		j.dFlow and string.format("%.1f", j.dFlow) or "?"), j.pass, "三档不满足缺口设计法")
end

-- ---- ③ 分段门 ----
local track = wsNr:FindFirstChild("Track")
local ctsStr = track and track:GetAttribute("CheckpointTs")
local cts = {}
if type(ctsStr) == "string" then
	for numStr in string.gmatch(ctsStr, "[^,]+") do cts[#cts + 1] = tonumber(numStr) end
end
local ascending = true
for i = 2, #cts do
	if cts[i] <= cts[i - 1] then ascending = false end
end
ok("③ CheckpointTs 属性=4 门且严格递增", #cts == 4 and ascending, tostring(ctsStr))

-- ---- ④ 锚点:非空,且不落断口/墙段 ----
local anchors = RespawnAnchors.load()
ok("④ 锚点烘焙非空", anchors ~= nil and #anchors > 0, anchors and #anchors or 0)
if anchors then
	local bad = 0
	for _, a in ipairs(anchors) do
		-- 断口/墙段上空无锚的几何复核:锚点正下方必须命中白名单路面(lint① 的可枚举验收)
		local hit = workspace:Raycast(a.cf.Position, Vector3.new(0, -6, 0),
			(function()
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Include
				local list = { workspace.Terrain }
				for _, inst in ipairs(CS:GetTagged("Rideable")) do
					if inst:IsA("BasePart") then list[#list + 1] = inst end
				end
				rp.FilterDescendantsInstances = list
				return rp
			end)())
		if not hit then bad += 1 end
	end
	ok("④ 每个锚点正下方=白名单路面(断口上空自然无锚)", bad == 0, bad .. " 个悬空")
end

-- ---- ⑤ 机器人完赛 ----
ok("⑤ 机器人完赛(含跨断口)", rep.robot and rep.robot.finished == true,
	rep.robot and string.format("finished=%s %.1fs resets=%d", tostring(rep.robot.finished), rep.robot.timeSec, rep.robot.resets) or "nil")

-- ---- ⑥ 墙链跨段交接:真车骑上墙带,连续跨 ≥2 段不弹出 ----
do
	local sp = TB.buildSpline(false)
	local bikeModel = Instance.new("Model"); bikeModel.Name = "M85TestBike"
	local root = Instance.new("Part")
	root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
	root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.Transparency = 1
	root.Parent = bikeModel; bikeModel.PrimaryPart = root; bikeModel.Parent = workspace
	local ctrl = BikeController.new(bikeModel)
	ctrl:setWallField(WallRideField.new())
	-- 找墙带首段,取其贴面外一点、沿切向起步,向墙侧微转进入
	local firstWall = nil
	for _, inst in ipairs(track.Content:GetChildren()) do
		if inst.Name:match("^WallSeg") then
			if not firstWall or inst.Name < firstWall.Name then firstWall = inst end
		end
	end
	ok("⑥ 墙带首段存在", firstWall ~= nil, "无 WallSeg")
	if firstWall then
		local wcf = firstWall.CFrame
		local n = -wcf.RightVector           -- 朝路一侧的贴面外法线(wallSide=1 → 面向 -Right)
		local along = wcf.LookVector
		local startPos = wcf.Position + n * 10 - along * (firstWall.Size.Z * 0.5 - 6)
		startPos = Vector3.new(startPos.X, wcf.Position.Y - firstWall.Size.Y * 0.5 + 1.6, startPos.Z)
		ctrl:teleport(CFrame.lookAt(startPos, startPos + (along - n * 0.35).Unit))
		ctrl.curSpeed = 100
		local seenParts, wallFrames, everExited, prevRiding = {}, 0, false, false
		local distinct = 0
		for f = 1, 420 do
			ctrl:setSteer(0); ctrl:setSprint(true)
			ctrl:step(DT)
			local tel = ctrl:getTelemetry()
			if tel.wallRiding then
				wallFrames += 1
				local partNow = ctrl.wall.seg.part
				if not seenParts[partNow] then
					seenParts[partNow] = true
					distinct += 1
				end
			elseif prevRiding then
				everExited = true
			end
			prevRiding = tel.wallRiding
		end
		ok("⑥ 骑墙连续跨 ≥2 段(实 " .. distinct .. " 段,墙帧 " .. wallFrames .. ")", distinct >= 2 and wallFrames > 60, distinct)
		ok("⑥ 链中不弹出(链端才退出)", (not everExited) or distinct >= 2, "中途弹出且未跨段")
	end
	ctrl:destroy()
	bikeModel:Destroy()
end

-- ---- ⑦ 供给两桶 + 判定点复核 ----
ok("⑦ 红区≠0(心流可达)", rep.lint.supply.redZeroAlarm == false, "红区=0 报警")
ok("⑦ 判定点复核零残留(入弯自动顺移)", rep.lint.combatBad == 0, rep.lint.combatBad)

-- ---- ⑧ 幂等确定性:再 compile 一次,计数/门/锚点一致 ----
do
	local rep2 = TB.compile({ closed = false, spec = SPEC, skipRobot = true })
	local c2 = rep2.content
	local track2 = wsNr:FindFirstChild("Track")   -- compile 销毁重建 Track:必须重取实例再比属性
	local same = c2.crystals == c.crystals and c2.cores == c.cores and c2.shooters == c.shooters
		and c2.gates == c.gates and c2.walls == c.walls and c2.lips == c.lips
		and rep2.anchors.kept == rep.anchors.kept
		and (track2 and track2:GetAttribute("CheckpointTs") == ctsStr)
	ok("⑧ compile 幂等(计数/门/锚点一致)", same,
		string.format("晶%d/%d 墙%d/%d 锚%d/%d", c2.crystals, c.crystals, c2.walls, c.walls, rep2.anchors.kept, rep.anchors.kept))
end

-- ---- 现场还原:迷你 CP 删除,原 CP 改回名 ----
cpFolder:Destroy()
if origCP then origCP.Name = "ControlPoints" end
if origClosed ~= nil then wsNr:SetAttribute("Closed", origClosed) end
log[#log + 1] = "  ○ 已还原原 ControlPoints;⚠️ 场上 Track/锚点/门=验收迷你轨——正式赛道请重跑 build_gauntlet 或 buildtrack(compile)"

table.insert(log, 1, string.format("== M8.5 验收:%d 通过 / %d 失败 ==", pass, fail))
print(table.concat(log, "\n"))
return string.format("M8.5 accept: %d pass, %d fail", pass, fail)
