-- NeonRun / RespawnAnchors (M4.1 / ADR-27) —— 烘焙锚点链:采样+三 lint+持久化+弧长回取
-- 哲学:重生点是烘焙的、可枚举验收的;运行时裸算最近点=废案(浮空段悬空+不可枚举)。
-- 烘焙(Edit 期):沿样条每 spacingStuds 弧长采样 →
--   lint① 下射线命中白名单(Terrain+Rideable)——跳跃段断口上空自动无锚;
--   lint② 直线段(±10 studs 切线转角 ≤ maxTurnDeg);
--   lint③ 前方无危险物(切向射线 clearAheadStuds 内无非白名单障碍、无 ShooterEnemy);
--   墙段上空排除:WallRideSurface 沿样条投影区间内不放锚(坠落回段前,§4.4)。
-- 持久:`Workspace.NeonRun.RespawnAnchors`(不可见锚根 Part)下 Attachment,
--   Attribute:ArcT(弧长参数)/Index;分段门(可见,计时)≠锚点(不可见,重生),严禁语义纠缠。
-- 运行时:load() 读回排序表;pick(anchors, curT, setback) = 弧长≤当前的最近锚点再回退 setback 个,
--   **永不前进**;首锚之前由调用方回发车位(0 号锚语义)。
local CollectionService = game:GetService("CollectionService")

local RespawnAnchors = {}

local FOLDER_NAME = "RespawnAnchors"
local PROBE_UP = 20      -- lint① 射线起点抬高
local PROBE_DOWN = 40    -- lint① 射线总长
local TANGENT_SPAN = 10  -- lint② 切线取样跨度(studs)

local function groundParams()
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	local list = { workspace.Terrain }
	for _, inst in ipairs(CollectionService:GetTagged("Rideable")) do
		if inst:IsA("BasePart") then list[#list + 1] = inst end
	end
	rp.FilterDescendantsInstances = list
	return rp
end

-- 墙段沿样条的排除区间:[tMin-margin, tMax+margin] 列表。
-- 距样条 > NEAR_WALL_STUDS 的墙不属于本路线(别的测试台/别条赛道),不排除。
local NEAR_WALL_STUDS = 40
local function wallExclusions(spline)
	local out = {}
	for _, part in ipairs(CollectionService:GetTagged("WallRideSurface")) do
		if part:IsA("BasePart") and part.Parent then
			local cf, halfL = part.CFrame, part.Size.Z * 0.5
			local t1, _, d1 = spline:NearestPoint(cf.Position + cf.LookVector * halfL)
			local t2, _, d2 = spline:NearestPoint(cf.Position - cf.LookVector * halfL)
			if math.min(d1, d2) <= NEAR_WALL_STUDS then
				local lo, hi = math.min(t1, t2), math.max(t1, t2)
				if hi - lo <= 0.5 then   -- 跨起点回绕的区间放弃排除(闭环边界罕见;lint 报告提示)
					out[#out + 1] = { lo = lo - 0.01, hi = hi + 0.01 }
				end
			end
		end
	end
	return out
end

-- 烘焙:纯计算(射线打当前场景),不落任何实例。
-- opts = { spacingStuds, hover, maxTurnDeg, clearAheadStuds }
-- 返回 { anchors = {{t, cf}}, rejected = {{t, reason}} }
function RespawnAnchors.bake(spline, opts)
	local rpG = groundParams()
	local rpAll = RaycastParams.new()
	rpAll.FilterType = Enum.RaycastFilterType.Exclude
	rpAll.FilterDescendantsInstances = {}
	local excl = wallExclusions(spline)
	local shooters = CollectionService:GetTagged("ShooterEnemy")
	local anchors, rejected = {}, {}
	local n = math.max(2, math.floor(spline.Length / math.max(opts.spacingStuds, 1)))
	for i = 0, n - 1 do
		local t = i / n
		local reason = nil
		for _, e in ipairs(excl) do
			if t >= e.lo and t <= e.hi then reason = "wallspan" break end
		end
		local pos = spline:GetPoint(t)
		local tan = spline:GetTangent(t)
		-- lint② 直线段
		if not reason then
			local dtT = TANGENT_SPAN / math.max(spline.Length, 1)
			local a = spline:GetTangent(t - dtT)
			local b = spline:GetTangent(t + dtT)
			local ang = math.deg(math.acos(math.clamp(a:Dot(b), -1, 1)))
			if ang > opts.maxTurnDeg then reason = "turn" end
		end
		-- lint① 下射线命中白名单
		local groundHit = nil
		if not reason then
			groundHit = workspace:Raycast(pos + Vector3.new(0, PROBE_UP, 0), Vector3.new(0, -PROBE_DOWN, 0), rpG)
			if not groundHit then reason = "noGround" end
		end
		-- lint③ 前方无危险物
		if not reason then
			local origin = groundHit.Position + Vector3.new(0, opts.hover + 1, 0)
			local fwd = Vector3.new(tan.X, 0, tan.Z)
			fwd = fwd.Magnitude > 1e-4 and fwd.Unit or tan
			local block = workspace:Raycast(origin, fwd * opts.clearAheadStuds, rpAll)
			if block and block.Instance ~= workspace.Terrain
				and not CollectionService:HasTag(block.Instance, "Rideable") then
				reason = "blocked"
			end
			if not reason then
				for _, s in ipairs(shooters) do
					local sp = s:IsA("BasePart") and s.Position or (s:IsA("Model") and s:GetPivot().Position)
					if sp then
						local to = sp - origin
						if to.Magnitude < opts.clearAheadStuds and to:Dot(fwd) > 0 then
							reason = "shooterAhead"
							break
						end
					end
				end
			end
		end
		if reason then
			rejected[#rejected + 1] = { t = t, reason = reason }
		else
			local p = groundHit.Position + Vector3.new(0, opts.hover, 0)
			local fwd = Vector3.new(tan.X, 0, tan.Z)
			fwd = fwd.Magnitude > 1e-4 and fwd.Unit or Vector3.zAxis
			anchors[#anchors + 1] = { t = t, cf = CFrame.lookAt(p, p + fwd) }
		end
	end
	return { anchors = anchors, rejected = rejected }
end

-- 持久化(Edit 期):清旧建新,不可见锚根 + Attachment 链
function RespawnAnchors.persist(bakeResult)
	local nrFolder = workspace:FindFirstChild("NeonRun") or workspace
	local old = nrFolder:FindFirstChild(FOLDER_NAME)
	if old then old:Destroy() end
	local rootPart = Instance.new("Part")
	rootPart.Name = FOLDER_NAME
	rootPart.Anchored = true
	rootPart.CanCollide = false; rootPart.CanQuery = false; rootPart.CanTouch = false
	rootPart.Transparency = 1
	rootPart.Size = Vector3.new(1, 1, 1)
	rootPart.CFrame = CFrame.new()
	for i, a in ipairs(bakeResult.anchors) do
		local att = Instance.new("Attachment")
		att.Name = string.format("Anchor%03d", i)
		att.WorldCFrame = a.cf
		att:SetAttribute("ArcT", a.t)
		att:SetAttribute("Index", i)
		att.Parent = rootPart
	end
	rootPart.Parent = nrFolder
	return rootPart
end

-- 运行时读回:排序 {t, cf} 表;无烘焙返回 nil
function RespawnAnchors.load()
	local nrFolder = workspace:FindFirstChild("NeonRun")
	local rootPart = nrFolder and nrFolder:FindFirstChild(FOLDER_NAME)
	if not rootPart then return nil end
	local list = {}
	for _, att in ipairs(rootPart:GetChildren()) do
		if att:IsA("Attachment") and att:GetAttribute("ArcT") ~= nil then
			list[#list + 1] = { t = att:GetAttribute("ArcT"), cf = att.WorldCFrame }
		end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a.t < b.t end)
	return list
end

-- 弧长回取:最大的 t ≤ curT 的锚点,再向后回退 setback 个(钳到首锚);无合格锚返回 nil(调用方回发车位)。
-- 永不前进:绝不返回 t > curT 的锚点。
function RespawnAnchors.pick(anchors, curT, setback)
	if not anchors or #anchors == 0 then return nil end
	local idx = nil
	for i = #anchors, 1, -1 do
		if anchors[i].t <= curT then idx = i break end
	end
	if not idx then return nil end
	idx = math.max(1, idx - (setback or 0))
	return anchors[idx]
end

return RespawnAnchors
