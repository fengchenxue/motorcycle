-- NeonRun / TrackBuilder (M8.5 / 策划案 §7 / ADR-27/28) —— 样条→赛道烘焙工具
-- ★ 烘焙期 Edit 脚本,非运行时:Instance 只在 Edit 期持久(坑1),Play 里建的会丢。
-- 纯几何 + 样条查询,无客户端专属 API——与 RaceTimer 同哲学,将来可原样复用。
--
-- P1(本文件当前范围):路面几何生成(宽走廊)+ Rideable 自动打 Tag + 弯道半径 lint。
-- P2 判定点入弯/供给密度/机器人完赛 · P3 语法摆放(水晶/核/环)· P4 分段门+重生锚点链——后续追加。
--
-- 用法(Studio 命令栏或 MCP execute_luau,datamodel=Edit):
--   local TB = require(game.ReplicatedStorage.NeonRun.Modules.TrackBuilder)
--   local report = TB.build({ closed = true })   -- 读 Workspace.NeonRun.ControlPoints → 生成 Workspace.NeonRun.Track
--   print(TB.formatReport(report))
--   local report = TB.lint()                      -- 只体检不生成
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Spline = require(RS.NeonRun.Modules.Spline)

local TrackBuilder = {}

local RIDEABLE_TAG = "Rideable"   -- ADR-28 物性声明制白名单;探针只认此 Tag(M4.1 切换后)
local TRACK_FOLDER = "Track"      -- Workspace.NeonRun.Track

local function cfg()
	return require(RS.NeonRun.Config.Track)
end

-- 事实源:全速(心流)可过的最小弯道半径 = v_flow / ω_high(转向角速度),指回 Handling,不硬编码。
local function minTurnRadius()
	local H = require(RS.NeonRun.Config.Handling)
	local vFlow = H.Speed.Base * H.Speed.SprintMultiplier * H.Speed.FlowExtraMultiplier
	local omega = math.rad(H.Steering.TurnRateHighDeg)   -- 最高速转向角速度(心流不降,ADR-31)
	return vFlow / omega   -- studs
end

-- 控制点:Workspace.NeonRun.ControlPoints 子件,按 Index 属性定序(缺 Index 的排最后,按名字兜底)
function TrackBuilder.getControlPoints()
	local wsNr = workspace:FindFirstChild("NeonRun")
	local cpFolder = wsNr and wsNr:FindFirstChild("ControlPoints")
	assert(cpFolder, "TrackBuilder: 找不到 Workspace.NeonRun.ControlPoints")
	local items = {}
	for _, c in ipairs(cpFolder:GetChildren()) do
		if c:IsA("BasePart") or c:IsA("Attachment") then
			local idx = c:GetAttribute("Index")
			items[#items + 1] = { inst = c, idx = idx or math.huge, name = c.Name }
		end
	end
	table.sort(items, function(a, b)
		if a.idx ~= b.idx then return a.idx < b.idx end
		return a.name < b.name
	end)
	local pts = {}
	for _, it in ipairs(items) do
		pts[#pts + 1] = (it.inst:IsA("Attachment")) and it.inst.WorldPosition or it.inst.Position
	end
	assert(#pts >= 3, "TrackBuilder: 控制点不足 3 个(closed 样条最少 3)")
	return pts
end

-- 闭环解析:显式传参优先;否则读 Workspace.NeonRun 的 Closed 属性(与运行时同一事实源);再否则默认 true。
function TrackBuilder.resolveClosed(closed)
	if closed ~= nil then return closed end
	local wsNr = workspace:FindFirstChild("NeonRun")
	local attr = wsNr and wsNr:GetAttribute("Closed")
	if attr ~= nil then return attr end
	return true
end

function TrackBuilder.buildSpline(closed)
	return Spline.new(TrackBuilder.getControlPoints(), TrackBuilder.resolveClosed(closed))
end

-- 弯道半径 lint:沿弧长以 CurvatureSampleStuds 步长数值微分切线,κ=dθ/ds → R=1/κ。
-- 违规=实际半径 < 理论最小半径 × 安全系数。返回 worst 与违规区间列表(合并相邻样点)。
function TrackBuilder.lint(spline)
	spline = spline or TrackBuilder.buildSpline()
	local C = cfg()
	local step = C.Lint.CurvatureSampleStuds
	local minR = minTurnRadius()
	local threshold = minR * C.Lint.RadiusSafetyFactor
	local L = spline.Length
	local n = math.max(8, math.floor(L / step))
	local ds = L / n

	local worstR, worstT = math.huge, 0
	local violations = {}
	local cur = nil
	for i = 0, n - 1 do
		local s = i * ds
		local t0 = (s) / L
		local t1 = (s + step) / L
		local a = spline:GetTangent(t0)
		local b = spline:GetTangent(t1)
		local dot = math.clamp(a:Dot(b), -1, 1)
		local dTheta = math.acos(dot)          -- 两切线夹角(rad)
		local R = (dTheta > 1e-6) and (step / dTheta) or math.huge
		if R < worstR then worstR, worstT = R, t0 end
		if R < threshold then
			if cur and (t0 - cur.toT) < (2.5 * step / L) then
				cur.toT = t1
				cur.minR = math.min(cur.minR, R)
			else
				cur = { fromT = t0, toT = t1, minR = R }
				violations[#violations + 1] = cur
			end
		else
			cur = nil
		end
	end

	return {
		kind = "lint",
		length = L,
		minRadiusTheory = minR,
		threshold = threshold,
		worstRadius = worstR,
		worstAtT = worstT,
		violations = violations,   -- {fromT,toT,minR}
		pass = #violations == 0,
	}
end

-- t 是否落在任一断口区间(P3 断口段:NoRoad;弧长参数)
local function tInGaps(t, gaps)
	if not gaps then return false end
	for _, g in ipairs(gaps) do
		if t >= g.fromT and t <= g.toT then return true end
	end
	return false
end

local function part(name, size, cf, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true      -- 射线探针需可命中(车本体 CanCollide=false massless,不受影响)
	p.CanTouch = false       -- 禁物理接触(坑11:一律射线/体积查询)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Parent = parent
	return p
end

-- 生成路面几何 + 打 Rideable Tag。清掉旧 Track 文件夹重建(幂等)。
function TrackBuilder.build(opts)
	opts = opts or {}
	if RunService:IsRunning() then
		warn("[TrackBuilder] 检测到运行态(Play):生成的 Instance 不会持久(坑1)。请在 Edit 模式烘焙。")
	end
	local closed = opts.closed
	local spline = TrackBuilder.buildSpline(closed)
	local C = cfg()
	local R = C.Road

	local wsNr = workspace:FindFirstChild("NeonRun")
	assert(wsNr, "TrackBuilder: 缺 Workspace.NeonRun")
	local old = wsNr:FindFirstChild(TRACK_FOLDER)
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = TRACK_FOLDER
	folder.Parent = wsNr
	local roadFolder = Instance.new("Folder")
	roadFolder.Name = "Road"
	roadFolder.Parent = folder

	local L = spline.Length
	local segLen = R.SegmentLengthStuds
	local count = math.max(1, math.floor(L / segLen))
	local step = L / count           -- 均匀分配,首尾无缝
	local tagged = 0
	local skipped = 0
	for i = 0, count - 1 do
		local s = (i + 0.5) * step    -- 段中心
		local t = s / L
		-- P3 断口段(ADR-41):落在缺口区间的路面件不生成(NoRoad;两端路件自带 Rideable=断言"两端打 Tag")
		if tInGaps(t, opts.gaps) then
			skipped += 1
			continue
		end
		local cf = spline:GetCFrame(t)
		-- 路面顶面比样条低 SinkBelowSpline(样条=行车中心线,车悬浮于顶面);沿样条 up 下沉。
		local up = cf.UpVector
		local center = cf.Position - up * (R.SinkBelowSpline + R.Thickness / 2)
		local segCf = CFrame.lookAt(center, center + cf.LookVector, up)
		local seg = part(string.format("Road_%03d", i + 1),
			Vector3.new(R.Width, R.Thickness, step * 1.04), segCf, R.Color, roadFolder)
		CS:AddTag(seg, RIDEABLE_TAG)   -- ADR-28:可骑面声明制,TrackBuilder 自动打 Tag
		tagged += 1

		if R.EdgeNeon then
			for _, sgn in ipairs({ -1, 1 }) do
				local ecf = segCf * CFrame.new(sgn * (R.Width / 2), R.Thickness / 2 + 0.4, 0)
				local edge = part(string.format("Edge_%03d_%s", i + 1, sgn < 0 and "L" or "R"),
					Vector3.new(0.6, 0.8, step * 1.04), ecf, Color3.fromRGB(0, 200, 255), roadFolder)
				edge.Material = Enum.Material.Neon
				-- 霓虹条=纯装饰导航,不是可骑面:不打 Rideable Tag(ADR-28:非白名单即障碍,故禁碰撞免误撞)
				edge.CanCollide = false
			end
		end
	end

	local report = {
		kind = "build",
		length = L,
		segments = count,
		tagged = tagged,
		gapSkipped = skipped,   -- P3 断口跳过的路面件数
		folder = folder,
		lint = TrackBuilder.lint(spline),
	}
	return report
end

-- ==================== M8.5 P2/P3/P4(ADR-41 混合制)====================
-- 路线=人类拖 CP;节拍/内容=Config/TrackSpecs 声明;本区=编译器+质检员,不发明设计。

-- spec 解析:表直传或按名取(默认 Default=§7 节拍模板)
function TrackBuilder.getSpec(specOrName)
	if type(specOrName) == "table" then return specOrName end
	local specs = require(RS.NeonRun.Config.TrackSpecs)
	return specs[specOrName or "Default"] or specs.Default
end

-- 区段归一:sec 权重 → 弧长区间 [t0,t1)(ADR-41:画的路长短不报错,lint 回报实际 vs 模板)
function TrackBuilder.resolveSegments(spline, spec)
	local total = 0
	for _, s in ipairs(spec.segments) do total += s.sec end
	local acc, out = 0, {}
	for i, s in ipairs(spec.segments) do
		local t0 = acc / total
		acc += s.sec
		out[#out + 1] = { index = i, t0 = t0, t1 = acc / total, def = s }
	end
	return out, total
end

-- 弹道积分(对实际样条高度):从 tCut 沿切向以速度 v 起跳(可加起跳唇仰角),
-- 返回回落到路面高度的弧长距离 studs;nil=几何无解(如持续下坡)。
local function jumpDistance(spline, tCut, v, extraPitchDeg)
	local H = require(RS.NeonRun.Config.Handling)
	local g = H.Physics.Gravity
	local step = cfg().Jump.BallisticStepStuds
	local tan = spline:GetTangent(tCut)
	local dir = tan
	if extraPitchDeg and extraPitchDeg > 0 then
		local horiz = Vector3.new(tan.X, 0, tan.Z)
		if horiz.Magnitude > 1e-4 then
			local pitch = math.atan2(tan.Y, horiz.Magnitude) + math.rad(extraPitchDeg)
			dir = horiz.Unit * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		end
	end
	local vel = dir * v
	local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if horizSpeed < 1 then return nil end
	local L = spline.Length
	local y, vy = spline:GetPoint(tCut).Y, vel.Y
	local s, wasAbove = 0, false
	for _ = 1, 800 do
		local dt = step / horizSpeed
		y += vy * dt - 0.5 * g * dt * dt
		vy -= g * dt
		s += step
		local t2 = tCut + s / L
		if t2 >= 1 then return nil end   -- 飞出样条末端(断口太靠后)
		local roadY = spline:GetPoint(t2).Y
		if y - roadY > 0.5 then wasAbove = true end
		if wasAbove and y <= roadY then return s end
	end
	return nil
end

-- P3a 断口规划:按区段声明,以实际几何反解三档距离,缺口=冲刺距−余量("冲刺刚好",缺口设计法)
function TrackBuilder.planJumps(spline, segs)
	local C = cfg()
	local H = require(RS.NeonRun.Config.Handling)
	local vCruise = H.Speed.Base
	local vSprint = vCruise * H.Speed.SprintMultiplier
	local vFlow = vSprint * H.Speed.FlowExtraMultiplier
	local gaps, notes = {}, {}
	for _, sg in ipairs(segs) do
		if sg.def.jump then
			local tCut = sg.t0 + (sg.t1 - sg.t0) * 0.45   -- 段中前部起跳(段尾留落地缓冲)
			local tan = spline:GetTangent(tCut)
			local slopeDeg = math.deg(math.atan2(tan.Y, Vector3.new(tan.X, 0, tan.Z).Magnitude))
			local lip = nil
			local dSprint = jumpDistance(spline, tCut, vSprint, nil)
			if (not dSprint or dSprint < 12) or slopeDeg < C.Jump.MinLaunchSlopeDeg then
				-- 平段/几何不足:自动补起跳唇(断桥形态②,ADR-41)
				lip = C.Jump.LipAngleDeg
				dSprint = jumpDistance(spline, tCut, vSprint, lip)
			end
			if dSprint and dSprint >= 12 then
				local gapLen = dSprint - C.Jump.SprintMarginStuds
				gaps[#gaps + 1] = {
					fromT = tCut, toT = tCut + gapLen / spline.Length,
					lip = lip, gapLen = gapLen, segIndex = sg.index,
					dCruise = jumpDistance(spline, tCut, vCruise, lip),
					dSprint = dSprint,
					dFlow = jumpDistance(spline, tCut, vFlow, lip),
				}
			else
				notes[#notes + 1] = string.format(
					"段%d(jump)几何无解(起跳坡 %.1f°,加唇仍不足):在此段画坡顶/下坡,或删 jump 声明",
					sg.index, slopeDeg)
			end
		end
	end
	return gaps, notes
end

-- 局部转角(±spanStuds 切线夹角;判定点直线度=Combat_StraightMaxTurnDeg 同源)
local function localTurnDeg(spline, t, spanStuds)
	local d = (spanStuds or 8) / spline.Length
	local a = spline:GetTangent(math.clamp(t - d, 0, 1))
	local b = spline:GetTangent(math.clamp(t + d, 0, 1))
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- P3b 语法摆放:水晶主线均布 / 红区(敌·核·闸)只落直线点(入弯自动顺移,ADR-41)/ 墙带直墙链 / 起跳唇
function TrackBuilder.buildContent(spline, segs, spec, gaps, totalSec)
	local C = cfg()
	local CC, R = C.Content, C.Road
	local H = require(RS.NeonRun.Config.Handling)
	local straightMax = H.Combat.StraightMaxTurnDeg
	local wsNr = workspace:FindFirstChild("NeonRun")
	local track = wsNr and wsNr:FindFirstChild(TRACK_FOLDER)
	assert(track, "TrackBuilder.buildContent: 先 build 路面")
	local old = track:FindFirstChild("Content")
	if old then old:Destroy() end
	local folder = Instance.new("Folder")
	folder.Name = "Content"
	folder.Parent = track

	local placed = { crystals = 0, cores = 0, shooters = 0, gates = 0, walls = 0, lips = 0,
		moved = 0, combatTs = {}, notes = {}, wallChainMaxTurn = 0 }

	local function itemAt(name, tag, size, shape, color, t, lateral, extraUp)
		local cf = spline:GetCFrame(t)
		local p = part(name, size, CFrame.new(cf.Position + cf.RightVector * (lateral or 0)
			+ Vector3.new(0, (extraUp or CC.ItemHeight), 0)), color, folder)
		p.CanCollide = false
		p.CanQuery = false     -- 摆件不遮探针/扫掠(坑11:判定一律 Tag+查询)
		p.Material = Enum.Material.Neon
		if shape then p.Shape = shape end
		CS:AddTag(p, tag)
		return p
	end

	-- 蓝区:水晶全轨均布贴主行车线(磁吸=保底;§7),缺口上空不摆
	local budget = (spec.supply and spec.supply.crystals) or 12
	for i = 1, budget do
		local t = (i - 0.5) / budget
		if not tInGaps(t, gaps) then
			itemAt("Crystal", "EnergyCrystal", Vector3.new(2, 2, 2), Enum.PartType.Ball,
				Color3.fromRGB(0, 200, 255), t, 0)
			placed.crystals += 1
		end
	end

	-- 红区:逐段按声明摆(判定点只落直线点;入弯自动顺移+间距守卫)
	local minSpacingT = CC.MinCombatSpacingStuds / spline.Length
	for _, sg in ipairs(segs) do
		local d = sg.def
		local kinds = {}
		for _ = 1, (d.shooters or 0) do kinds[#kinds + 1] = "shooter" end
		for _ = 1, (d.cores or 0) do kinds[#kinds + 1] = "core" end
		for _ = 1, (d.gates or 0) do kinds[#kinds + 1] = "gate" end
		local slots = #kinds
		if slots > 0 then
			local placedTs = {}
			for si, kind in ipairs(kinds) do
				local t = sg.t0 + (sg.t1 - sg.t0) * (si / (slots + 1))
				local moved = false
				-- 直线点搜索(段内,避缺口)
				if localTurnDeg(spline, t) > straightMax or tInGaps(t, gaps) then
					local stepT = CC.StraightSearchStepStuds / spline.Length
					local found = nil
					for k = 1, 80 do
						for _, dir in ipairs({ 1, -1 }) do
							local t2 = t + dir * k * stepT
							if t2 > sg.t0 and t2 < sg.t1 and not tInGaps(t2, gaps)
								and localTurnDeg(spline, t2) <= straightMax then
								found = t2
								break
							end
						end
						if found then break end
					end
					if found then t, moved = found, true
					else
						placed.notes[#placed.notes + 1] = string.format("段%d:%s 无直线落点(整段弯),请拉直或移出本段", sg.index, kind)
						t = nil
					end
				end
				-- 间距守卫(同时决策数峰值≤2 的落地近似)
				if t then
					for _, pt in ipairs(placedTs) do
						if math.abs(t - pt) < minSpacingT then
							t = pt + minSpacingT
							moved = true
						end
					end
					if t >= sg.t1 or tInGaps(t, gaps) then
						placed.notes[#placed.notes + 1] = string.format("段%d:%s 间距挤不下(段太短/判定点太密)", sg.index, kind)
						t = nil
					end
				end
				if t then
					placedTs[#placedTs + 1] = t
					placed.combatTs[#placed.combatTs + 1] = t
					if moved then placed.moved += 1 end
					local side = (si % 2 == 0) and 1 or -1
					if kind == "shooter" then
						local p = itemAt("TBShooter" .. sg.index .. "_" .. si, "ShooterEnemy",
							Vector3.new(3, 5, 3), nil, Color3.fromRGB(255, 60, 110), t, side * CC.ShooterLateral, 0.9)
						p.Material = Enum.Material.SmoothPlastic
						placed.shooters += 1
					elseif kind == "core" then
						itemAt("Core", "EnergyCore", Vector3.new(4, 4, 4), nil,
							Color3.fromRGB(180, 0, 255), t, side * CC.CoreLateral)
						placed.cores += 1
					else -- gate:覆半幅内(§7 主路线永不强制斩击=必可绕行);CanCollide=false 现行约定(已知问题⑧)
						local w = R.Width * CC.GateCoverFrac
						itemAt("EnergyGate", "Destructible", Vector3.new(w, 10, 1), nil,
							Color3.fromRGB(255, 80, 40), t, side * (R.Width / 2 - w / 2), 3.4)
						placed.gates += 1
					end
				end
			end
		end
	end

	-- 墙带:直墙链(ADR-41 曲墙=离散直墙链;单段守 M6.5 数据模型 Size=(厚,高,长),±X 贴面)
	for _, sg in ipairs(segs) do
		local d = sg.def
		if d.wallSec and d.wallSec > 0 then
			local side = d.wallSide or 1
			local wallLen = (d.wallSec / totalSec) * spline.Length
			local spanLen = (sg.t1 - sg.t0) * spline.Length
			wallLen = math.min(wallLen, spanLen * 0.9)
			local startT = sg.t0 + ((sg.t1 - sg.t0) - wallLen / spline.Length) * 0.5
			local n = math.max(1, math.floor(wallLen / C.Wall.SegmentLengthStuds))
			local step = wallLen / n
			local prevLook = nil
			for i = 0, n - 1 do
				local t = startT + ((i + 0.5) * step) / spline.Length
				local cf = spline:GetCFrame(t)
				local lookH = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				lookH = lookH.Magnitude > 1e-4 and lookH.Unit or Vector3.zAxis
				if prevLook then
					local turn = math.deg(math.acos(math.clamp(prevLook:Dot(lookH), -1, 1)))
					placed.wallChainMaxTurn = math.max(placed.wallChainMaxTurn, turn)
				end
				prevLook = lookH
				local center = cf.Position + cf.RightVector * side * (R.Width / 2 + C.Wall.OffsetFromEdge + C.Wall.Thickness / 2)
					+ Vector3.new(0, C.Wall.Height / 2 - R.SinkBelowSpline, 0)
				local p = part(string.format("WallSeg%d_%02d", sg.index, i + 1),
					Vector3.new(C.Wall.Thickness, C.Wall.Height, step * (1 + C.Wall.OverlapFrac)),
					CFrame.lookAt(center, center + lookH), Color3.fromRGB(0, 180, 220), folder)
				CS:AddTag(p, "WallRideSurface")
				placed.walls += 1
			end
		end
	end

	-- 起跳唇(平段 jump 的几何解;Rideable 楔形板,顶端=断口起点)
	for _, g in ipairs(gaps or {}) do
		if g.lip then
			local Llip = C.Jump.LipLengthStuds
			local pitch = math.rad(g.lip)
			local tStart = g.fromT - Llip / spline.Length
			local cf0 = spline:GetCFrame(math.max(tStart, 0))
			local lookH = Vector3.new(cf0.LookVector.X, 0, cf0.LookVector.Z)
			lookH = lookH.Magnitude > 1e-4 and lookH.Unit or Vector3.zAxis
			local basePos = cf0.Position - Vector3.new(0, R.SinkBelowSpline, 0)  -- 路面顶
			local center = basePos + lookH * (Llip / 2)
				+ Vector3.new(0, (Llip * math.tan(pitch)) / 2 - 0.5, 0)
			local p = part(string.format("JumpLip%d", g.segIndex),
				Vector3.new(R.Width, 1, Llip / math.cos(pitch)),
				CFrame.lookAt(center, center + lookH) * CFrame.Angles(pitch, 0, 0),
				Color3.fromRGB(80, 90, 110), folder)
			CS:AddTag(p, RIDEABLE_TAG)
			placed.lips += 1
		end
	end

	return placed
end

-- P4a 分段门:均匀目标吸附到节拍区段边界(语义分段);写 Track.CheckpointTs 属性(运行时同源)
function TrackBuilder.bakeCheckpoints(spline, segs)
	local count = cfg().Checkpoints.Count
	local boundaries = {}
	for i = 2, #segs do boundaries[#boundaries + 1] = segs[i].t0 end
	local ts, used = {}, {}
	for k = 1, count do
		local target = k / (count + 1)
		local best, bestD = target, math.huge
		for _, b in ipairs(boundaries) do
			local dd = math.abs(b - target)
			if dd < bestD and not used[b] then best, bestD = b, dd end
		end
		used[best] = true
		ts[#ts + 1] = best
	end
	table.sort(ts)
	local strs = {}
	for _, t in ipairs(ts) do strs[#strs + 1] = string.format("%.4f", t) end
	local track = workspace.NeonRun:FindFirstChild(TRACK_FOLDER)
	if track then track:SetAttribute("CheckpointTs", table.concat(strs, ",")) end
	return ts
end

-- P4b 锚点烘焙(ADR-27;RespawnAnchors 模块,参数事实源=Handling 模块默认)
function TrackBuilder.bakeAnchors(spline)
	local RespawnAnchors = require(RS.NeonRun.Modules.RespawnAnchors)
	local H = require(RS.NeonRun.Config.Handling)
	local result = RespawnAnchors.bake(spline, {
		spacingStuds = H.Respawn.AnchorSpacingSec * H.Speed.Base,
		hover = H.Ground.HoverHeight,
		maxTurnDeg = H.Respawn.AnchorMaxTurnDeg,
		clearAheadStuds = H.Respawn.AnchorClearAheadStuds,
	})
	RespawnAnchors.persist(result)
	return result
end

-- P2 机器人完赛:纯几何可骑性证明(锁 sprintAllowed,不模拟经济,ADR-41);
-- 循线=前视点追踪;坠落走锚点重生续跑;回报时间=奖牌线草稿参考(标定仍归人类作者跑)。
function TrackBuilder.robotRun(spline, opts)
	opts = opts or {}
	local Rb = cfg().Robot
	local BikeController = require(RS.NeonRun.Modules.BikeController)
	local RespawnAnchors = require(RS.NeonRun.Modules.RespawnAnchors)
	local H = require(RS.NeonRun.Config.Handling)
	local model = Instance.new("Model")
	model.Name = "TBRobot"
	local root = Instance.new("Part")
	root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
	root.Anchored = true; root.CanCollide = false; root.CanQuery = false; root.Transparency = 1
	root.Parent = model; model.PrimaryPart = root; model.Parent = workspace
	local ctrl = BikeController.new(model)
	ctrl:setSpline(spline)
	local anchors = RespawnAnchors.load()
	if anchors then ctrl:setAnchors(anchors) end
	local cf0 = spline:GetCFrame(0)
	local spawnCF = CFrame.lookAt(cf0.Position, cf0.Position + cf0.LookVector)
	ctrl:setSpawnCF(spawnCF)
	ctrl:teleport(spawnCF)
	local DT = 1 / 60
	local closed = opts.closed == true
	local vSprint = H.Speed.Base * H.Speed.SprintMultiplier
	local budget = math.floor((spline.Length / vSprint) * 60 * Rb.BudgetFactor)
	local tEst, prevCorrected, needCorrect = 0, 0, false
	ctrl:on("respawned", function() needCorrect = true end)
	local resets0 = ctrl.resetCount
	local finished, steps = false, 0
	for k = 1, budget do
		steps = k
		tEst += (ctrl.curSpeed * DT) / spline.Length
		if needCorrect or k % Rb.CorrectEverySteps == 0 then
			needCorrect = false
			local cur = select(1, spline:NearestPoint(ctrl.physPos))
			if closed and prevCorrected > 0.9 and cur < 0.1 then
				finished = true
				break
			end
			prevCorrected = cur
			tEst = cur
		end
		if not closed and tEst >= 0.997 then
			finished = true
			break
		end
		local lookT = tEst + Rb.LookaheadStuds / spline.Length
		if closed then lookT %= 1 else lookT = math.min(lookT, 1) end
		local target = spline:GetPoint(lookT)
		local to = target - ctrl.physPos
		local desired = math.atan2(-to.X, -to.Z)
		local dy = (desired - ctrl.yaw + math.pi) % (2 * math.pi) - math.pi
		ctrl:setSteer(math.clamp(dy * Rb.SteerGain, -1, 1))
		ctrl:setSprint(true)
		ctrl:step(DT)
	end
	local resets = ctrl.resetCount - resets0
	ctrl:destroy()
	model:Destroy()
	return { finished = finished, steps = steps, timeSec = steps / 60, resets = resets, budget = budget }
end

-- P2 lint 全套:弯道(几何,报告制)+判定点复核+供给两桶(红区=0 报警)+跳跃三档
function TrackBuilder.lintAll(spline, segs, content, gaps, spec, totalSec)
	local C = cfg()
	local H = require(RS.NeonRun.Config.Handling)
	local curve = TrackBuilder.lint(spline)
	-- 判定点入弯复核(摆放已自动顺移;残留=段内无直线点,notes 已带)
	local combatBad = 0
	for _, t in ipairs(content.combatTs) do
		if localTurnDeg(spline, t) > H.Combat.StraightMaxTurnDeg then combatBad += 1 end
	end
	-- 供给两桶(§7 参考密度:晶 12~18/核 3~6/敌 3~5/闸 0~2)
	local redCount = content.cores + content.shooters + content.gates
	local supply = {
		blue = content.crystals, cores = content.cores, shooters = content.shooters, gates = content.gates,
		redZeroAlarm = redCount == 0,   -- 红区=0:心流不可达,报警(ADR-37)
		warnings = {},
	}
	local function warnRange(name, v, lo, hi)
		if v < lo or v > hi then
			supply.warnings[#supply.warnings + 1] = string.format("%s=%d(参考 %d~%d)", name, v, lo, hi)
		end
	end
	warnRange("晶", content.crystals, 12, 18)
	warnRange("核", content.cores, 3, 6)
	warnRange("敌", content.shooters, 3, 5)
	warnRange("闸", content.gates, 0, 2)
	-- 跳跃三档:巡航过不去 / 冲刺刚好 / 心流余量(缺口设计法断言)
	local jumpResults = {}
	for _, g in ipairs(gaps or {}) do
		jumpResults[#jumpResults + 1] = {
			segIndex = g.segIndex, gapLen = g.gapLen, lip = g.lip,
			dCruise = g.dCruise, dSprint = g.dSprint, dFlow = g.dFlow,
			pass = (g.dCruise == nil or g.dCruise < g.gapLen)
				and (g.dSprint ~= nil and g.dSprint >= g.gapLen)
				and (g.dFlow ~= nil and g.dFlow >= g.gapLen + 2),
		}
	end
	-- 节拍:实际时长 vs 模板(比例制归一,差异只报告,裁决归人)
	local estSec = spline.Length / (H.Speed.Base * H.Speed.SprintMultiplier)
	return {
		curve = curve,
		combatBad = combatBad,
		supply = supply,
		jumps = jumpResults,
		wallChainMaxTurn = content.wallChainMaxTurn,
		wallChainLimit = H.WallRide and 8 or 8,
		rhythm = { templateSec = totalSec, estSec = estSec },
		notes = content.notes,
	}
end

-- 总入口(ADR-41):段解析→断口反解→几何(NoRoad)→内容→门+锚点→lint→机器人→总报告
function TrackBuilder.compile(opts)
	opts = opts or {}
	local closed = TrackBuilder.resolveClosed(opts.closed)
	local spline = TrackBuilder.buildSpline(closed)
	local spec = TrackBuilder.getSpec(opts.spec)
	local segs, totalSec = TrackBuilder.resolveSegments(spline, spec)
	local gaps, jumpNotes = TrackBuilder.planJumps(spline, segs)
	local buildReport = TrackBuilder.build({ closed = closed, gaps = gaps })
	local content = TrackBuilder.buildContent(spline, segs, spec, gaps, totalSec)
	local gateTs = TrackBuilder.bakeCheckpoints(spline, segs)
	local anchorResult = TrackBuilder.bakeAnchors(spline)
	local lint = TrackBuilder.lintAll(spline, segs, content, gaps, spec, totalSec)
	local robot = nil
	if not opts.skipRobot then
		robot = TrackBuilder.robotRun(spline, { closed = closed })
	end
	return {
		kind = "compile",
		build = buildReport, content = content, gateTs = gateTs,
		anchors = { kept = #anchorResult.anchors, rejected = #anchorResult.rejected },
		lint = lint, robot = robot, jumpNotes = jumpNotes,
		length = spline.Length, segments = segs,
	}
end

function TrackBuilder.formatReport(r)
	if not r then return "TrackBuilder: 无报告" end
	local lines = {}
	if r.kind == "compile" then
		local c, l = r.content, r.lint
		lines[#lines + 1] = string.format("[TrackBuilder.compile] 弧长 %.0f studs | 路面 %d 段(断口跳过 %d)",
			r.length, r.build.segments, r.build.gapSkipped or 0)
		lines[#lines + 1] = string.format("  内容:晶 %d / 核 %d / 敌 %d / 闸 %d / 墙段 %d / 唇 %d(入弯自动顺移 %d 处)",
			c.crystals, c.cores, c.shooters, c.gates, c.walls, c.lips, c.moved)
		lines[#lines + 1] = string.format("  P4:分段门 %d(Track.CheckpointTs)| 锚点 %d(剔 %d)",
			#r.gateTs, r.anchors.kept, r.anchors.rejected)
		lines[#lines + 1] = string.format("  节拍:实际 ≈%.0fs(冲刺参考速)vs 模板 %.0fs——差异由人裁,不算错",
			l.rhythm.estSec, l.rhythm.templateSec)
		if l.supply.redZeroAlarm then
			lines[#lines + 1] = "  🚨 红区=0:心流不可达(ADR-37)——spec 需至少一处战斗收入"
		end
		if #l.supply.warnings > 0 then
			lines[#lines + 1] = "  ⚠️ 供给密度:" .. table.concat(l.supply.warnings, ";")
		end
		for _, j in ipairs(l.jumps) do
			lines[#lines + 1] = string.format("  %s 断口@段%d:缺口 %.1f | 巡航 %s / 冲刺 %.1f / 心流 %s%s",
				j.pass and "✅" or "❌", j.segIndex, j.gapLen,
				j.dCruise and string.format("%.1f", j.dCruise) or "落不到", j.dSprint,
				j.dFlow and string.format("%.1f", j.dFlow) or "?", j.lip and string.format("(唇 %d°)", j.lip) or "")
		end
		if l.wallChainMaxTurn > 0 then
			lines[#lines + 1] = string.format("  墙链最大相邻夹角 %.1f°(交接上限 8°)%s",
				l.wallChainMaxTurn, l.wallChainMaxTurn > 8 and " ❌ 弯太急,墙链会断——挪 CP 或缩 wallSec" or " ✅")
		end
		if l.combatBad > 0 then
			lines[#lines + 1] = string.format("  ❌ %d 个判定点仍在弯上(段内无直线落点)", l.combatBad)
		end
		for _, n in ipairs(l.notes or {}) do lines[#lines + 1] = "  ⚠️ " .. n end
		for _, n in ipairs(r.jumpNotes or {}) do lines[#lines + 1] = "  ⚠️ " .. n end
		if r.robot then
			lines[#lines + 1] = string.format("  机器人:%s %.1fs(重生 %d 次;奖牌线草稿参考,标定归作者跑)",
				r.robot.finished and "✅ 完赛" or "❌ 未完赛(预算 " .. r.robot.budget .. " 步)",
				r.robot.timeSec, r.robot.resets)
		end
		lines[#lines + 1] = "  " .. string.rep("—", 30)
		r = r.lint.curve   -- 尾接弯道 lint 详情
	elseif r.kind == "build" then
		lines[#lines + 1] = string.format("[TrackBuilder] 烘焙完成:弧长 %.0f studs,路面 %d 段,Rideable Tag %d 个",
			r.length, r.segments, r.tagged)
		r = r.lint
	end
	lines[#lines + 1] = string.format("[lint 弯道半径] 理论最小 %.1f × 安全系数 = 阈值 %.1f studs;全程最小实测 %.1f @t=%.3f",
		r.minRadiusTheory, r.threshold, r.worstRadius, r.worstAtT)
	if r.pass then
		lines[#lines + 1] = "  ✅ 无过紧弯:全程心流速(146)可全速通过"
	else
		lines[#lines + 1] = string.format("  ❌ %d 处弯道过紧(心流速会被逼刹车,违 §7):", #r.violations)
		for _, v in ipairs(r.violations) do
			lines[#lines + 1] = string.format("     t=%.3f~%.3f 最小半径 %.1f studs(需 ≥ %.1f)", v.fromT, v.toT, v.minR, r.threshold)
		end
	end
	return table.concat(lines, "\n")
end

return TrackBuilder
