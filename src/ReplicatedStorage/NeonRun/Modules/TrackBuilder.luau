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

local Spline = require(RS.NeonRun.Modules.Spline:Clone())   -- 坑15:Edit 会话跨调用缓存,Clone 取最新类

local TrackBuilder = {}

local RIDEABLE_TAG = "Rideable"   -- ADR-28 物性声明制白名单;探针只认此 Tag(M4.1 切换后)
local TRACK_FOLDER = "Track"      -- Workspace.NeonRun.Track

-- 坑15:MCP/命令栏跨调用 require 缓存——烘焙参数经 :Clone() 重编译取最新 .Source(本模块自身也应 Clone 后 require)
local trackCfgCache
local function cfg()
	if not trackCfgCache then
		trackCfgCache = require(RS.NeonRun.Config.Track:Clone())
	end
	return trackCfgCache
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

local function part(name, size, cf, color, parent, className)
	local p = Instance.new(className or "Part")
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

-- ADR-45 裙板(P3d 移植自 gauntlet):墙根四分之一圆弧 Rideable 小面片(几何与解析圆角同源半径)
-- ——任意角贴近墙根=沿裙板滚上墙,消灭"侧向磁吸窗外=被撞开"(人类试玩回报)。不占 WallRideSurface Tag。
local function buildSkirt(wallPart, sideSign, r, facetsN, parent)
	local cf = wallPart.CFrame
	local halfT, halfH, len = wallPart.Size.X / 2, wallPart.Size.Y / 2, wallPart.Size.Z
	local n = cf.RightVector * sideSign
	local base = cf.Position + n * halfT - Vector3.new(0, halfH, 0)
	for i = 1, facetsN do
		local a0 = (i - 1) * (math.pi / 2) / facetsN
		local a1 = i * (math.pi / 2) / facetsN
		local x0, y0 = r * (1 - math.sin(a0)), r * (1 - math.cos(a0))
		local x1, y1 = r * (1 - math.sin(a1)), r * (1 - math.cos(a1))
		local am = (a0 + a1) / 2
		local nu = n * math.sin(am) + Vector3.new(0, math.cos(am), 0)
		local chordLen = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		local chordDir = (n * (x1 - x0) + Vector3.new(0, y1 - y0, 0)) / chordLen
		local sPart = part(wallPart.Name .. "_Skirt" .. i,
			Vector3.new(0.6, chordLen + 0.12, len),
			CFrame.fromMatrix(base + n * ((x0 + x1) / 2) + Vector3.new(0, (y0 + y1) / 2, 0) - nu * 0.3,
				nu, chordDir),
			Color3.fromRGB(90, 175, 185), parent)
		CS:AddTag(sPart, RIDEABLE_TAG)
	end
	return facetsN
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
	local specs = require(RS.NeonRun.Config.TrackSpecs:Clone())   -- 坑15:取最新 spec 声明
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
			-- P3c/P3e:jump=true(全自动)或表 { lipDeg=楔角, lipLen=楔长, at=段内位置0~1(默认0.45),
			--   gapStuds=手定缺口宽(默认=冲刺跳距−余量;手定过宽会在三档断言里亮❌), mercy=false 关救济组 }
			local jdef = type(sg.def.jump) == "table" and sg.def.jump or nil
			local tCut = sg.t0 + (sg.t1 - sg.t0) * ((jdef and jdef.at) or 0.45)
			local tan = spline:GetTangent(tCut)
			local slopeDeg = math.deg(math.atan2(tan.Y, Vector3.new(tan.X, 0, tan.Z).Magnitude))
			local lip = jdef and jdef.lipDeg or nil
			local lipLen = jdef and jdef.lipLen or nil
			local dSprint
			if lip then
				dSprint = jumpDistance(spline, tCut, vSprint, lip)
			else
				dSprint = jumpDistance(spline, tCut, vSprint, nil)
				if (not dSprint or dSprint < 12) or slopeDeg < C.Jump.MinLaunchSlopeDeg then
					-- 平段/几何不足:自动补起跳唇(断桥形态②,ADR-41)
					lip = C.Jump.LipAngleDeg
					dSprint = jumpDistance(spline, tCut, vSprint, lip)
				end
			end
			if dSprint and dSprint >= 12 then
				local gapLen = (jdef and jdef.gapStuds) or (dSprint - C.Jump.SprintMarginStuds)
				gaps[#gaps + 1] = {
					fromT = tCut, toT = tCut + gapLen / spline.Length,
					lip = lip, lipLen = lipLen, gapLen = gapLen, segIndex = sg.index,
					mercy = not (jdef and jdef.mercy == false),   -- P3d:断口救济组默认开(jump={mercy=false} 关)
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

-- P3c(ADR-49)墙桥规划:主线路断(平切无楔=不可跳)+ 墙带跨越(缺口两端各延 margin 供入/出墙)。
-- 机器人不会贴墙:robotRun 对墙桥区间跳渡(该段可通过性由墙带验收线覆盖,ADR-36/43 一脉)。
function TrackBuilder.planBridges(spline, segs, totalSec)
	local B = cfg().Bridge
	local H = require(RS.NeonRun.Config.Handling)
	local vSprint = H.Speed.Base * H.Speed.SprintMultiplier
	local blendSec = (H.WallRide and H.WallRide.BlendSec) or 0.2
	local margin = math.max(B.WallMarginStuds, blendSec * vSprint * 1.2)   -- 入墙混合距 ×1.2 余量
	local bridges = {}
	for _, sg in ipairs(segs) do
		-- P3f 蛇形墙带挖空(人类直令:墙带中段路面删掉=必须贴墙跨越):每条带中央断 slalomGapStuds,
		-- 带两端余量=(带长−缺口)/2,须 ≥入墙混合距——过窄会在墙桥断言亮❌
		if sg.def.wallSlalom and sg.def.slalomGapStuds and sg.def.wallSec and totalSec then
			local d = sg.def
			local L = spline.Length
			local spanLen = (sg.t1 - sg.t0) * L
			local wallLen = math.min((d.wallSec / totalSec) * L, spanLen * 0.9)
			local n = d.wallSlalom
			local usable = spanLen * 0.9
			local bandLen = wallLen / n
			local transLen = (usable - wallLen) / (n + 1)
			local baseS = (sg.t0 + (sg.t1 - sg.t0) * 0.05) * L
			local gap = math.min(d.slalomGapStuds, bandLen - 2 * blendSec * vSprint)
			for k = 1, n do
				local bandFromS = baseS + transLen * k + bandLen * (k - 1)
				local gapFromS = bandFromS + (bandLen - gap) / 2
				bridges[#bridges + 1] = {
					bridge = true, segIndex = sg.index,
					side = (d.wallSide or 1) * ((k % 2 == 1) and 1 or -1),
					fromT = gapFromS / L, toT = (gapFromS + gap) / L, gapLen = gap,
					wallFromT = bandFromS / L, wallToT = (bandFromS + bandLen) / L,
					margin = (bandLen - gap) / 2, slalom = true,
				}
			end
		end
		if sg.def.wallBridge then
			-- P3e:wallBridge=true(默认 at 0.45/宽 Bridge.GapStuds)或表 { at=, gapStuds=, wallSide= }
			local bdef = type(sg.def.wallBridge) == "table" and sg.def.wallBridge or nil
			local gapStuds = (bdef and bdef.gapStuds) or B.GapStuds
			local L = spline.Length
			local tCut = sg.t0 + (sg.t1 - sg.t0) * ((bdef and bdef.at) or 0.45)
			bridges[#bridges + 1] = {
				bridge = true, segIndex = sg.index,
				side = (bdef and bdef.wallSide) or sg.def.wallSide or -1,
				fromT = tCut, toT = tCut + gapStuds / L, gapLen = gapStuds,
				wallFromT = math.max(sg.t0, tCut - margin / L),
				wallToT = math.min(sg.t1, tCut + (gapStuds + margin) / L),
				margin = margin,
			}
		end
	end
	return bridges
end

-- 局部转角(±spanStuds 切线夹角;判定点直线度=Combat_StraightMaxTurnDeg 同源)
local function localTurnDeg(spline, t, spanStuds)
	local d = (spanStuds or 8) / spline.Length
	local a = spline:GetTangent(math.clamp(t - d, 0, 1))
	local b = spline:GetTangent(math.clamp(t + d, 0, 1))
	return math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
end

-- P3b 语法摆放:水晶主线均布 / 红区(敌·核·闸)只落直线点(入弯自动顺移,ADR-41)/ 墙带直墙链 / 起跳唇
-- P3c 追加(ADR-49):bridges=墙桥(墙带跨断口)/ rampFork=跳台高架捷径
function TrackBuilder.buildContent(spline, segs, spec, gaps, totalSec, bridges)
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
		moved = 0, combatTs = {}, notes = {}, wallChainMaxTurn = 0,
		forkDecks = 0, forkNotes = {}, bridgeWalls = 0,
		mercyCrystals = 0, mercyCores = 0, slalomBands = 0, skirts = 0 }

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

	-- 蓝区:水晶全轨均布贴主行车线(磁吸=保底;§7),缺口上空不摆;
	-- P3f(人类反馈):贴断口沿的晶后退到安全位;救济区(断口前 130)已有救济组=均布晶跳过防扎堆
	local budget = (spec.supply and spec.supply.crystals) or 12
	for i = 1, budget do
		local t = (i - 0.5) / budget
		local drop = false
		for _, g in ipairs(gaps or {}) do
			local aheadStuds = (g.fromT - t) * spline.Length
			if aheadStuds > 0 and aheadStuds <= 130 and g.mercy then
				drop = true   -- 救济组窗口内,跳过(防 road358 式扎堆)
				break
			elseif aheadStuds > 0 and aheadStuds <= 40 then
				t = g.fromT - 55 / spline.Length   -- 悬在断口沿=挪到安全位
				break
			end
		end
		if not drop and not tInGaps(t, gaps) then
			itemAt("Crystal", "EnergyCrystal", Vector3.new(2, 2, 2), Enum.PartType.Ball,
				Color3.fromRGB(0, 200, 255), t, 0)
			placed.crystals += 1
		end
	end

	-- 墙带弧长区间(先算:①判定点排除区——§7"墙段内不摆判定点/射手";②墙带生成同源使用)
	local wallSpans = {}
	for _, sg in ipairs(segs) do
		local d = sg.def
		if d.wallSec and d.wallSec > 0 and not (d.wallSlalom and d.slalomGapStuds) then
			-- (蛇形+挖空的带已由 planBridges 生成为墙桥,经 bridges 并入,勿双铺)
			local spanLen = (sg.t1 - sg.t0) * spline.Length
			local wallLen = math.min((d.wallSec / totalSec) * spline.Length, spanLen * 0.9)
			local n = d.wallSlalom or 1
			if n <= 1 then
				local startT = sg.t0 + ((sg.t1 - sg.t0) - wallLen / spline.Length) * 0.5
				wallSpans[#wallSpans + 1] = { fromT = startT, toT = startT + wallLen / spline.Length,
					side = d.wallSide or 1, segIndex = sg.index }
			else
				-- P3d 蛇形墙带(ADR-49b 人类直令"来回切换,一会左一会右"):N 段左右交替,过渡段落地穿越;
				-- 判定点排除只罩墙带本体 → 声明的敌人自动落进过渡段(§7"墙段内不摆判定点/射手"自动成立)
				local usable = spanLen * 0.9
				local bandLen = wallLen / n
				local transLen = (usable - wallLen) / (n + 1)
				local baseS = (sg.t0 + (sg.t1 - sg.t0) * 0.05) * spline.Length
				for k = 1, n do
					local fromS = baseS + transLen * k + bandLen * (k - 1)
					wallSpans[#wallSpans + 1] = {
						fromT = fromS / spline.Length, toT = (fromS + bandLen) / spline.Length,
						side = (d.wallSide or 1) * ((k % 2 == 1) and 1 or -1),
						segIndex = sg.index, slalom = true,
					}
				end
			end
		end
	end
	-- P3c 墙桥的墙带并入同一列表(同一链生成器铺,同享判定点排除)
	for _, b in ipairs(bridges or {}) do
		wallSpans[#wallSpans + 1] = { fromT = b.wallFromT, toT = b.wallToT,
			side = b.side, segIndex = b.segIndex, isBridge = true }
	end

	-- 红区:逐段按声明摆(判定点只落直线点;入弯自动顺移+间距守卫;缺口与墙段区间内不摆)
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
				-- 直线点搜索(段内;避缺口与墙段区间——§7 墙段内不摆判定点/射手)
				local function badSpot(tq)
					return tInGaps(tq, gaps) or tInGaps(tq, wallSpans) or localTurnDeg(spline, tq) > straightMax
				end
				if badSpot(t) then
					local stepT = CC.StraightSearchStepStuds / spline.Length
					local found = nil
					for k = 1, 80 do
						for _, dir in ipairs({ 1, -1 }) do
							local t2 = t + dir * k * stepT
							if t2 > sg.t0 and t2 < sg.t1 and not badSpot(t2) then
								found = t2
								break
							end
						end
						if found then break end
					end
					if found then t, moved = found, true
					else
						placed.notes[#placed.notes + 1] = string.format("段%d:%s 无合法落点(整段弯/被墙段与缺口占满),请拉直或移出本段", sg.index, kind)
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
					if t >= sg.t1 or badSpot(t) then
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
							Vector3.new(3, 5, 3), nil, Color3.fromRGB(255, 40, 40), t, side * CC.ShooterLateral, 0.9)
						p.Material = Enum.Material.SmoothPlastic
						placed.shooters += 1
					elseif kind == "core" then
						itemAt("Core", "EnergyCore", Vector3.new(4, 4, 4), nil,
							Color3.fromRGB(180, 0, 255), t, side * CC.CoreLateral)
						placed.cores += 1
					else
						-- P3g 闸门重设计(ADR-49d,人类反馈可读性+功能性):**全幅门框**(纯视觉,斩后留
						-- "门洞"读感——门框还在、能量幕消失=状态变化一眼可读)+ **ForceField 能量幕**=
						-- Destructible 本体(§7 必可绕行:幕只覆半幅,另半幅=框下空门洞;ADR-42 未斩=实体墙不变)。
						-- 幕=核同紫「紫=可斩」+双面"⚔ 斩"字+紫光(斩后 AttackSystem 连 Gui/灯一起灭,复活复原)。
						-- P3h:gateFull=true(spec 段声明)=幕覆全幅强制斩击——仅限教学闸门(ADR-42 明文豁免);
						-- 斩击免费(J 键不耗能)+锚点在门前=失败重试零成本,无卡死风险
						local w = (d.gateFull and R.Width) or (R.Width * CC.GateCoverFrac)
						local cfG = spline:GetCFrame(t)
						local baseG = cfG.Position - Vector3.new(0, R.SinkBelowSpline, 0)
						local lookG = Vector3.new(cfG.LookVector.X, 0, cfG.LookVector.Z)
						lookG = lookG.Magnitude > 1e-4 and lookG.Unit or Vector3.zAxis
						local rightG = cfG.RightVector
						local FRAME_H = 14
						local frameCol = Color3.fromRGB(28, 34, 50)
						for _, sgn in ipairs({ -1, 1 }) do
							local postPos = baseG + rightG * (sgn * (R.Width / 2 + 1.2)) + Vector3.new(0, FRAME_H / 2, 0)
							local post = part("GateFramePost", Vector3.new(1.6, FRAME_H, 1.6),
								CFrame.lookAt(postPos, postPos + lookG), frameCol, folder)
							post.Material = Enum.Material.SmoothPlastic
							post.CanCollide = false
							post.CanQuery = false
						end
						local beamPos = baseG + Vector3.new(0, FRAME_H - 0.6, 0)
						local beamP = part("GateFrameBeam", Vector3.new(R.Width + 4, 1.6, 1.6),
							CFrame.lookAt(beamPos, beamPos + lookG), frameCol, folder)
						beamP.Material = Enum.Material.SmoothPlastic
						beamP.CanCollide = false
						beamP.CanQuery = false
						-- P3h 斩不中修复:幕中心=路面+5(判定盒竖向 ±5,旧中心 +7 摸不到);下缘沉入路面 2=视觉不变
						local fieldLat = d.gateFull and 0 or (side * (R.Width / 2 - w / 2))
						local fieldPos = baseG + rightG * fieldLat + Vector3.new(0, 5, 0)
						local gp = part("EnergyGate", Vector3.new(w, FRAME_H, 1),
							CFrame.lookAt(fieldPos, fieldPos + lookG), Color3.fromRGB(180, 0, 255), folder)
						gp.Material = Enum.Material.ForceField
						gp.CanCollide = true
						gp.CanQuery = true
						CS:AddTag(gp, "Destructible")
						local glow = Instance.new("PointLight")
						glow.Color = Color3.fromRGB(190, 60, 255)
						glow.Brightness = 2.5
						glow.Range = 24
						glow.Parent = gp
						for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
							local gui = Instance.new("SurfaceGui")
							gui.Face = face
							gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
							gui.PixelsPerStud = 20
							gui.Parent = gp
							local lbl = Instance.new("TextLabel")
							lbl.Size = UDim2.new(1, 0, 1, 0)
							lbl.BackgroundTransparency = 1
							lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
							lbl.TextScaled = true
							lbl.Font = Enum.Font.GothamBlack
							lbl.Text = "⚔ SLASH"   -- P4g 世界字英文化(人类直令)
							lbl.Parent = gui
						end
						placed.gates += 1
					end
				end
			end
		end
	end

	-- 墙带:直墙链(ADR-41 曲墙=离散直墙链;单段守 M6.5 数据模型 Size=(厚,高,长),±X 贴面);
	-- 区间=上面算好的 wallSpans(与判定点排除区同源,§7)
	for _, ws in ipairs(wallSpans) do
		do
			if ws.slalom then placed.slalomBands += 1 end
			local side = ws.side
			local wallLen = (ws.toT - ws.fromT) * spline.Length
			local startT = ws.fromT
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
				local p = part(string.format("WallSeg%d_%02d", ws.segIndex, i + 1),
					Vector3.new(C.Wall.Thickness, C.Wall.Height, step * (1 + C.Wall.OverlapFrac)),
					CFrame.lookAt(center, center + lookH), Color3.fromRGB(0, 180, 220), folder)
				CS:AddTag(p, "WallRideSurface")
				placed.walls += 1
				if ws.isBridge then placed.bridgeWalls += 1 end
				-- P3d:路侧墙根裙板(半径=人类调参现值;0=关)
				local fr = RS.NeonRun.Config.Handling:GetAttribute("WallRide_FilletRadius") or 7
				if (C.Wall.SkirtFacets or 0) > 0 and fr > 0 then
					placed.skirts += buildSkirt(p, -side, fr, C.Wall.SkirtFacets, folder)
				end
			end
		end
	end

	-- 起跳唇(平段 jump 的几何解;Rideable 楔形板,顶端=断口起点)
	for _, g in ipairs(gaps or {}) do
		if g.lip then
			local Llip = g.lipLen or C.Jump.LipLengthStuds
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

	-- P3d 救济组(ADR-49b,人类试玩直令):每个断口前铺 晶×2(中线,磁吸保底)+ 核×1(近线,
	-- MercyRespawn=随玩家锚点重生复现,AttackSystem:reviveMercy)——防"零能量卡死在冲刺门"重试循环
	-- (锚点重生不回能,实证;水晶自带 6s 冷却复现)。首过顺路 +43 能量,已计入供给统计(报告注明)。
	for _, g in ipairs(gaps or {}) do
		if g.lip and g.mercy then
			local Lm = spline.Length
			for i, back in ipairs({ 110, 82 }) do
				local t = g.fromT - back / Lm
				if t > 0 and not tInGaps(t, gaps) then
					itemAt("MercyCrystal" .. g.segIndex .. "_" .. i, "EnergyCrystal", Vector3.new(2, 2, 2),
						Enum.PartType.Ball, Color3.fromRGB(0, 200, 255), t, 0)
					placed.crystals += 1
					placed.mercyCrystals += 1
				end
			end
			local tc = g.fromT - 52 / Lm
			if tc > 0 then
				local core = itemAt("MercyCore" .. g.segIndex, "EnergyCore", Vector3.new(4, 4, 4), nil,
					Color3.fromRGB(180, 0, 255), tc, 6)
				core:SetAttribute("MercyRespawn", true)
				placed.cores += 1
				placed.mercyCores += 1
			end
		end
	end

	-- P3c 跳台高架捷径(ADR-49 rampFork):入口=半幅跳台楔(Rideable)+缺口+高架直桥(弦切弯内),
	-- 末端飞落回主线;主线样条零改动(机器人与不走捷径的玩家路径不变)。
	-- 缺口按同高跳距分档:冲刺 v²sin2θ/g 需 ≥缺口+6,巡航需 ≤缺口−4;巡航失败=落回正下方主线路面(零惩罚)。
	local H2 = require(RS.NeonRun.Config.Handling)
	for _, sg in ipairs(segs) do
		if sg.def.rampFork then
			local F = C.Fork
			local tE = sg.t0 + (sg.t1 - sg.t0) * F.EntryFrac
			local tX = sg.t0 + (sg.t1 - sg.t0) * F.ExitFrac
			local cfE, cfX = spline:GetCFrame(tE), spline:GetCFrame(tX)
			local chord = cfX.Position - cfE.Position
			local side = (chord:Dot(cfE.RightVector) >= 0) and 1 or -1   -- 高架取弦侧(弯内)
			local lookH = Vector3.new(cfE.LookVector.X, 0, cfE.LookVector.Z)
			lookH = lookH.Magnitude > 1e-4 and lookH.Unit or Vector3.zAxis
			local a = math.rad(F.RampAngleDeg)
			local h = math.tan(a) * F.RampLengthStuds
			local base = cfE.Position + cfE.RightVector * (side * F.RampLateralStuds)
				- Vector3.new(0, R.SinkBelowSpline, 0)
			local rampCenter = base + Vector3.new(0, h / 2, 0)
			local ramp = part("ForkRamp" .. sg.index, Vector3.new(F.RampWidth, h, F.RampLengthStuds),
				CFrame.lookAt(rampCenter, rampCenter - lookH), Color3.fromRGB(90, 200, 140), folder, "WedgePart")
			CS:AddTag(ramp, RIDEABLE_TAG)
			-- 高架:楔顶缺口 GapStuds 之后起桥,直指出口点上方(平桥=入口高;出口路面更低→末端自然飞落)
			local lipTop = base + lookH * (F.RampLengthStuds / 2) + Vector3.new(0, h, 0)
			local exitTop = cfX.Position - Vector3.new(0, R.SinkBelowSpline, 0)
			local dirD = Vector3.new(exitTop.X, 0, exitTop.Z) - Vector3.new(lipTop.X, 0, lipTop.Z)
			dirD = dirD.Magnitude > 1e-4 and dirD.Unit or lookH
			local dStart = lipTop + dirD * F.GapStuds
			local dEnd = Vector3.new(exitTop.X, lipTop.Y, exitTop.Z)
			local deckLen = (dEnd - dStart).Magnitude
			local dCenter = (dStart + dEnd) / 2 - Vector3.new(0, 0.5, 0)
			local deck = part("ForkDeck" .. sg.index, Vector3.new(F.DeckWidth, 1, deckLen),
				CFrame.lookAt(dCenter, dCenter + dirD), Color3.fromRGB(70, 90, 120), folder)
			CS:AddTag(deck, RIDEABLE_TAG)
			for k = 1, (F.DeckCrystals or 0) do
				local cpos = dStart + dirD * (deckLen * k / ((F.DeckCrystals or 0) + 1)) + Vector3.new(0, 2, 0)
				local cr = part("ForkCrystal" .. sg.index .. "_" .. k, Vector3.new(2, 2, 2),
					CFrame.new(cpos), Color3.fromRGB(0, 200, 255), folder)
				cr.Shape = Enum.PartType.Ball
				cr.Material = Enum.Material.Neon
				cr.CanCollide = false
				cr.CanQuery = false
				CS:AddTag(cr, "EnergyCrystal")
				placed.crystals += 1
			end
			placed.forkDecks += 1
			local vS = H2.Speed.Base * H2.Speed.SprintMultiplier
			local vC = H2.Speed.Base
			local rangeS = vS * vS * math.sin(2 * a) / H2.Physics.Gravity
			local rangeC = vC * vC * math.sin(2 * a) / H2.Physics.Gravity
			placed.forkNotes[#placed.forkNotes + 1] = {
				segIndex = sg.index, gap = F.GapStuds, rangeSprint = rangeS, rangeCruise = rangeC,
				deckLen = deckLen, lipDeg = F.RampAngleDeg,
				pass = (rangeS >= F.GapStuds + 6) and (rangeC <= F.GapStuds - 4),
			}
		end
	end

	return placed
end

-- P3f 结局大门(人类直令):白霓虹拱门+FINISH 牌+地面线(纯视觉;完赛判定=RaceTimer 读 Track.FinishT)
function TrackBuilder.buildFinishGate(spline, tFin)
	local R = cfg().Road
	local track = workspace.NeonRun:FindFirstChild(TRACK_FOLDER)
	local folder = track and track:FindFirstChild("Content")
	if not folder then return end
	local cf = spline:GetCFrame(tFin)
	local base = cf.Position - Vector3.new(0, R.SinkBelowSpline, 0)
	local up = Vector3.yAxis
	-- P3j:水平航向系(柱竖直/梁水平横跨)——CFrame.new 恒等旋转在非轴向路段横梁必歪
	local lookRaw = cf.LookVector
	local look = Vector3.new(lookRaw.X, 0, lookRaw.Z)
	look = look.Magnitude > 1e-4 and look.Unit or Vector3.zAxis
	local right = Vector3.new(-look.Z, 0, look.X)
	local HALF_W, HEIGHT, BAR = R.Width / 2 + 2, 17, 1.4
	local white = Color3.fromRGB(240, 245, 255)
	local function deco(name, size, cfr)
		local p = part(name, size, cfr, white, folder)
		p.Material = Enum.Material.Neon
		p.CanCollide = false
		p.CanQuery = false
		return p
	end
	deco("FinishPost_L", Vector3.new(BAR, HEIGHT, BAR), CFrame.new(base + right * HALF_W + up * (HEIGHT / 2)))
	deco("FinishPost_R", Vector3.new(BAR, HEIGHT, BAR), CFrame.new(base - right * HALF_W + up * (HEIGHT / 2)))
	deco("FinishBeam", Vector3.new(HALF_W * 2 + BAR, BAR, BAR),
		CFrame.lookAt(base + up * HEIGHT, base + up * HEIGHT + look))
	deco("FinishStripe", Vector3.new(HALF_W * 2, 0.2, 2.5), CFrame.lookAt(base + up * 0.12, base + up * 0.12 + look))
	local signPos = base + up * (HEIGHT - 3)
	local board = part("FinishSign", Vector3.new(20, 5, 0.5),
		CFrame.lookAt(signPos, signPos - look), Color3.fromRGB(10, 14, 22), folder)
	board.Material = Enum.Material.SmoothPlastic
	board.CanCollide = false
	board.CanQuery = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = "🏁 FINISH 🏁"
	lbl.Parent = gui
end

-- P4c 发车出生点(人类反馈"点开始出现在大厅"):角色直接出生在发车线——§8"直进赛道最小入口"
-- 的落地;同时把 Streaming 初始焦点从大厅挪到赛道(开局即围绕发车区加载)。挂 Track 下随 compile 重建。
-- CanQuery=false:出生板对车辆物理隐形(坑 33——本引擎碰撞走查询,否则发车线上多一块未 Tag 障碍)。
function TrackBuilder.buildSpawn(spline)
	local R = cfg().Road
	local track = workspace.NeonRun:FindFirstChild(TRACK_FOLDER)
	if not track then return end
	local cf = spline:GetCFrame(0.001)
	local lookH = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	lookH = lookH.Magnitude > 1e-4 and lookH.Unit or Vector3.zAxis
	local base = cf.Position - Vector3.new(0, R.SinkBelowSpline, 0) + Vector3.new(0, 0.5, 0)
	local spn = Instance.new("SpawnLocation")
	spn.Name = "NeonRunSpawn"
	spn.Size = Vector3.new(8, 1, 8)
	spn.CFrame = CFrame.lookAt(base, base + lookH)
	spn.Anchored = true
	spn.CanCollide = true
	spn.CanQuery = false
	spn.CanTouch = false
	spn.Neutral = true
	spn.Duration = 0
	spn.Transparency = 0.4
	spn.Color = Color3.fromRGB(60, 255, 120)
	spn.Parent = track
	-- 其它出生点让位(大厅出生点=V1 demo 期间禁用;可逆,M11 大厅回启按标记找回)
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("SpawnLocation") and inst ~= spn and inst.Enabled then
			inst.Enabled = false
			inst:SetAttribute("NeonRunDisabled", true)
		end
	end
end

-- P4a 分段门:均匀目标吸附到节拍区段边界(语义分段);写 Track.CheckpointTs 属性(运行时同源)
function TrackBuilder.bakeCheckpoints(spline, segs, spec)
	local count = (spec and spec.checkpoints) or cfg().Checkpoints.Count
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
	local RespawnAnchors = require(RS.NeonRun.Modules.RespawnAnchors:Clone())   -- 坑15:取最新(锚点已迁 RS)
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
	local RespawnAnchors = require(RS.NeonRun.Modules.RespawnAnchors:Clone())   -- 坑15:取最新(锚点已迁 RS)
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
	-- P3h:教学闸门=战斗动词——机器人视作已斩开(ADR-41 纯几何可骑性,锁经济不模拟战斗;跑后复原)。
	-- 否则 gateFull 全幅门会把机器人堵死在门前(实测 149 次重生耗尽预算)。
	-- ⚠ 本引擎碰撞=射线/体积查询(坑11):放行必须连 CanQuery 一起关,只关 CanCollide 射线照样命中
	local gatesOff = {}
	for _, inst in ipairs(CS:GetTagged("Destructible")) do
		if inst:IsA("BasePart") and (inst.CanCollide or inst.CanQuery) then
			gatesOff[#gatesOff + 1] = { p = inst, c = inst.CanCollide, q = inst.CanQuery }
			inst.CanCollide = false
			inst.CanQuery = false
		end
	end
	local resets0 = ctrl.resetCount
	local finished, steps = false, 0
	local bridgeSkips = 0
	for k = 1, budget do
		steps = k
		tEst += (ctrl.curSpeed * DT) / spline.Length
		-- P3c 墙桥跳渡(ADR-49):机器人不会贴墙,墙桥段=非几何可骑性段(可通过性由墙带验收线覆盖)
		if opts.bridges then
			for _, b in ipairs(opts.bridges) do
				if tEst >= b.fromT - 30 / spline.Length and tEst < b.toT + 10 / spline.Length then
					local tt = b.toT + 40 / spline.Length
					local cf2 = spline:GetCFrame(tt)
					ctrl:teleport(CFrame.lookAt(cf2.Position, cf2.Position + cf2.LookVector))
					tEst = tt
					prevCorrected = tt
					bridgeSkips += 1
					break
				end
			end
		end
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
		if not closed and tEst >= (opts.finishT or 0.997) then   -- P3f:结局大门前移时机器人同步(奖牌线草稿口径一致)
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
	for _, g in ipairs(gatesOff) do g.p.CanCollide = g.c; g.p.CanQuery = g.q end   -- 门物性复原
	return { finished = finished, steps = steps, timeSec = steps / 60, resets = resets, budget = budget,
		bridgeSkips = bridgeSkips }
end

-- P2 lint 全套:弯道(几何,报告制)+判定点复核+供给两桶(红区=0 报警)+跳跃三档
-- P3c 追加:墙桥断言(缺口不可跳+墙带覆盖余量)+ 冲刺时间预算
function TrackBuilder.lintAll(spline, segs, content, gaps, spec, totalSec, bridges)
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
	-- P3c 墙桥断言:缺口不可跳(平切无楔,心流平飞短于缺口/落不进)+ 墙带覆盖含入/出余量 + 墙件已铺
	local vFlow = H.Speed.Base * H.Speed.SprintMultiplier * H.Speed.FlowExtraMultiplier
	local bridgeResults = {}
	for _, b in ipairs(bridges or {}) do
		local dFlow = jumpDistance(spline, b.fromT, vFlow, nil)
		bridgeResults[#bridgeResults + 1] = {
			segIndex = b.segIndex, gapLen = b.gapLen, margin = b.margin, dFlow = dFlow,
			unjumpable = (dFlow == nil) or (dFlow < b.gapLen),
			wallCovered = (b.fromT - b.wallFromT) * spline.Length >= b.margin * 0.9
				and (b.wallToT - b.toT) * spline.Length >= b.margin * 0.9,
			wallsBuilt = content.bridgeWalls > 0,
		}
	end
	-- P3c 冲刺时间预算(报告行;弹反/斩敌=技巧收入另计,不进保底预算)
	local E = require(RS.NeonRun.Config.Energy)
	local supplyEnergy = E.StartEnergy + content.crystals * E.CrystalGain
		+ content.cores * E.CoreGain + content.gates * E.GateGain
	local sprintBudget = {
		energy = supplyEnergy,
		sec = supplyEnergy / E.SprintDrainPerSec,
		jumps = #(gaps or {}),   -- 需要冲刺的断口数(每处 ~2.5s 助跑+滞空)
	}
	-- 节拍:实际时长 vs 模板(比例制归一,差异只报告,裁决归人)
	local estSec = spline.Length / (H.Speed.Base * H.Speed.SprintMultiplier)
	return {
		curve = curve,
		combatBad = combatBad,
		supply = supply,
		jumps = jumpResults,
		bridges = bridgeResults,
		forkNotes = content.forkNotes,
		sprintBudget = sprintBudget,
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
	-- P4a(ADR-51)样条数据迁 ReplicatedStorage:CP 球=BasePart 会被 Streaming 按距截断(坑 24),
	-- 客户端(TestDrive)从 TrackData 全量重建样条;CP 球降级为纯编辑器工件
	do
		local td = RS.NeonRun:FindFirstChild("TrackData")
		if not td then
			td = Instance.new("Folder")
			td.Name = "TrackData"
			td.Parent = RS.NeonRun
		end
		local pts = TrackBuilder.getControlPoints()
		local buf = table.create(#pts)
		for i, p in ipairs(pts) do
			buf[i] = string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z)
		end
		td:SetAttribute("CP", table.concat(buf, ";"))
		td:SetAttribute("Closed", closed)
	end
	local segs, totalSec = TrackBuilder.resolveSegments(spline, spec)
	local gaps, jumpNotes = TrackBuilder.planJumps(spline, segs)
	local bridges = TrackBuilder.planBridges(spline, segs, totalSec)
	-- 路面/摆件的避让区 = 跳跃断口 ∪ 墙桥断口
	local allGaps = {}
	for _, g in ipairs(gaps) do allGaps[#allGaps + 1] = g end
	for _, b in ipairs(bridges) do allGaps[#allGaps + 1] = b end
	local buildReport = TrackBuilder.build({ closed = closed, gaps = allGaps })
	local content = TrackBuilder.buildContent(spline, segs, spec, allGaps, totalSec, bridges)
	local gateTs = TrackBuilder.bakeCheckpoints(spline, segs, spec)
	-- P3f 结局大门:FinishT 属性(RaceTimer/机器人同源)+ 拱门;其后路段=冲线滑行区
	if spec.finishAt then
		local trackFolder = workspace.NeonRun:FindFirstChild(TRACK_FOLDER)
		if trackFolder then trackFolder:SetAttribute("FinishT", spec.finishAt) end
		TrackBuilder.buildFinishGate(spline, spec.finishAt)
	end
	TrackBuilder.buildSpawn(spline)   -- P4c:发车线出生点(其它出生点让位)
	local anchorResult = TrackBuilder.bakeAnchors(spline)
	local lint = TrackBuilder.lintAll(spline, segs, content, gaps, spec, totalSec, bridges)
	local robot = nil
	if not opts.skipRobot then
		robot = TrackBuilder.robotRun(spline, { closed = closed, bridges = bridges, finishT = spec.finishAt })
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
		lines[#lines + 1] = string.format("  内容:晶 %d / 核 %d / 敌 %d / 闸 %d / 墙段 %d / 唇 %d(入弯自动顺移 %d 处;含救济 晶%d+核%d;蛇形墙带 %d 段;裙板 %d 片)",
			c.crystals, c.cores, c.shooters, c.gates, c.walls, c.lips, c.moved,
			c.mercyCrystals or 0, c.mercyCores or 0, c.slalomBands or 0, c.skirts or 0)
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
		for _, b in ipairs(l.bridges or {}) do
			lines[#lines + 1] = string.format("  %s 墙桥@段%d:路断 %.0f+墙带余量 ±%.0f | 不可跳 %s(心流平切飞距 %s)| 墙件 %s",
				(b.unjumpable and b.wallCovered and b.wallsBuilt) and "✅" or "❌",
				b.segIndex, b.gapLen, b.margin,
				b.unjumpable and "✓" or "✗", b.dFlow and string.format("%.1f", b.dFlow) or "落不进",
				b.wallsBuilt and "已铺" or "缺失")
		end
		for _, f in ipairs(l.forkNotes or {}) do
			lines[#lines + 1] = string.format("  %s 跳台捷径@段%d:楔 %d°+缺口 %.0f | 冲刺同高跳 %.1f ✓/巡航 %.1f ✗(失败落回主线)| 高架 %.0f studs",
				f.pass and "✅" or "❌", f.segIndex, f.lipDeg, f.gap, f.rangeSprint, f.rangeCruise, f.deckLen)
		end
		if l.sprintBudget then
			lines[#lines + 1] = string.format("  冲刺预算:保底供给 %.0f 能量 ≈ %.1fs 冲刺(开局+晶+核+闸,弹反/斩敌另计);需冲刺断口 %d 处(~2.5s/处)",
				l.sprintBudget.energy, l.sprintBudget.sec, l.sprintBudget.jumps)
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
			lines[#lines + 1] = string.format("  机器人:%s %.1fs(重生 %d 次%s;奖牌线草稿参考,标定归作者跑)",
				r.robot.finished and "✅ 完赛" or "❌ 未完赛(预算 " .. r.robot.budget .. " 步)",
				r.robot.timeSec, r.robot.resets,
				(r.robot.bridgeSkips or 0) > 0 and string.format(",墙桥跳渡 %d 处=墙带段豁免", r.robot.bridgeSkips) or "")
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
