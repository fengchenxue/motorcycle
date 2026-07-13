-- NeonRun / SplineViz —— 编辑期样条可视化(快照,移动控制点后需重建)
-- SplineViz.Build(spline, parentFolder) -> 生成的中心线段数
local SplineViz = {}

local STEP = 10       -- 中心线分段步长 (studs)
local TICK_EVERY = 5  -- 每隔多少段画一个法向刻度

local function makePart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

function SplineViz.Build(spline, parentFolder)
	for _, c in ipairs(parentFolder:GetChildren()) do
		c:Destroy()
	end
	local n = math.max(2, math.floor(spline.Length / STEP))
	local prev = spline:GetPoint(0)
	for i = 1, n do
		local t = i / n
		local cur = spline:GetPoint(t)
		local mid = (prev + cur) / 2
		local len = (cur - prev).Magnitude
		if len > 0.05 then
			local seg = makePart({
				Name = "Seg" .. i,
				Size = Vector3.new(0.35, 0.35, len),
				CFrame = CFrame.lookAt(mid, cur),
				Color = Color3.fromRGB(0, 255, 255),
			})
			seg.Parent = parentFolder
		end
		if i % TICK_EVERY == 0 then
			local cf = spline:GetCFrame(t)
			local tick = makePart({
				Name = "Tick" .. i,
				Size = Vector3.new(6, 0.25, 0.25),
				CFrame = CFrame.lookAt(cur, cur + cf.LookVector),
				Color = Color3.fromRGB(255, 0, 170),
			})
			tick.Parent = parentFolder
		end
		prev = cur
	end
	local startCf = spline:GetCFrame(0)
	local s = makePart({
		Name = "StartMarker",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		CFrame = CFrame.new(startCf.Position),
		Color = Color3.fromRGB(0, 255, 80),
	})
	s.Parent = parentFolder
	local arrow = makePart({
		Name = "StartDir",
		Size = Vector3.new(0.6, 0.6, 8),
		CFrame = CFrame.lookAt(startCf.Position + startCf.LookVector * 6, startCf.Position + startCf.LookVector * 14),
		Color = Color3.fromRGB(0, 255, 80),
	})
	arrow.Parent = parentFolder
	return n
end

return SplineViz
