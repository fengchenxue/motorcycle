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
	for i = 0, count - 1 do
		local s = (i + 0.5) * step    -- 段中心
		local t = s / L
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
		folder = folder,
		lint = TrackBuilder.lint(spline),
	}
	return report
end

function TrackBuilder.formatReport(r)
	if not r then return "TrackBuilder: 无报告" end
	local lines = {}
	if r.kind == "build" then
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
