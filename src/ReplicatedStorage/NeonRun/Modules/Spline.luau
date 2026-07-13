-- NeonRun / Spline (M1 数据层)
-- Centripetal Catmull-Rom 样条:构建 / 弧长均匀求值 / 切线 / 最近点查询
-- 用法:
--   local Spline = require(ReplicatedStorage.NeonRun.Modules.Spline)
--   local sp = Spline.new(points, true)   -- points: {Vector3}, closed: boolean
--   sp.Length                              -- 总弧长 (studs)
--   sp:GetPoint(t)     -> Vector3          -- t 在 [0,1),弧长均匀参数
--   sp:GetTangent(t)   -> Vector3 (单位向量)
--   sp:GetCFrame(t)    -> CFrame           -- 前方=切线,上方约等于世界Y
--   sp:NearestPoint(p) -> t, Vector3, dist -- 最近点查询(重生/防抄近道用)

local Spline = {}
Spline.__index = Spline

local SAMPLES_PER_SEGMENT = 16

local function crCentripetal(p0, p1, p2, p3, t)
	local alpha = 0.5
	local t0 = 0
	local t1 = (p1 - p0).Magnitude ^ alpha + t0
	local t2 = (p2 - p1).Magnitude ^ alpha + t1
	local t3 = (p3 - p2).Magnitude ^ alpha + t2
	if t1 <= t0 or t2 <= t1 or t3 <= t2 then
		return p1:Lerp(p2, t)
	end
	local tt = t1 + (t2 - t1) * t
	local A1 = p0 * ((t1 - tt) / (t1 - t0)) + p1 * ((tt - t0) / (t1 - t0))
	local A2 = p1 * ((t2 - tt) / (t2 - t1)) + p2 * ((tt - t1) / (t2 - t1))
	local A3 = p2 * ((t3 - tt) / (t3 - t2)) + p3 * ((tt - t2) / (t3 - t2))
	local B1 = A1 * ((t2 - tt) / (t2 - t0)) + A2 * ((tt - t0) / (t2 - t0))
	local B2 = A2 * ((t3 - tt) / (t3 - t1)) + A3 * ((tt - t1) / (t3 - t1))
	return B1 * ((t2 - tt) / (t2 - t1)) + B2 * ((tt - t1) / (t2 - t1))
end

function Spline.new(points, closed)
	assert(type(points) == "table" and #points >= (closed and 3 or 4), "Spline.new: 控制点不足")
	local self = setmetatable({}, Spline)
	self.Closed = closed == true
	self.Points = table.clone(points)
	self:_build()
	return self
end

function Spline:_controlFor(seg)
	local pts, n = self.Points, #self.Points
	local function get(k)
		if self.Closed then
			return pts[(k - 1) % n + 1]
		end
		return pts[math.clamp(k, 1, n)]
	end
	return get(seg - 1), get(seg), get(seg + 1), get(seg + 2)
end

function Spline:_build()
	local n = #self.Points
	local segCount = self.Closed and n or n - 1
	self.SegCount = segCount
	local samples, cum, segIdx, segT = {}, {}, {}, {}
	local total, prev = 0, nil
	for seg = 1, segCount do
		local p0, p1, p2, p3 = self:_controlFor(seg)
		local jStart = (seg == 1) and 0 or 1
		for j = jStart, SAMPLES_PER_SEGMENT do
			local lt = j / SAMPLES_PER_SEGMENT
			local pos = crCentripetal(p0, p1, p2, p3, lt)
			if prev then
				total += (pos - prev).Magnitude
			end
			samples[#samples + 1] = pos
			cum[#cum + 1] = total
			segIdx[#segIdx + 1] = seg
			segT[#segT + 1] = lt
			prev = pos
		end
	end
	self.Samples, self.CumLen = samples, cum
	self.SampleSeg, self.SampleT = segIdx, segT
	self.Length = total
end

local function upperBound(cum, s)
	local lo, hi = 1, #cum
	while lo < hi do
		local mid = math.ceil((lo + hi) / 2)
		if cum[mid] <= s then lo = mid else hi = mid - 1 end
	end
	return lo
end

function Spline:_wrap(t)
	if self.Closed then
		t = t % 1
		if t < 0 then t += 1 end
		return t
	end
	return math.clamp(t, 0, 1)
end

function Spline:GetPoint(t)
	t = self:_wrap(t)
	local s = t * self.Length
	local k = upperBound(self.CumLen, s)
	local k2 = math.min(k + 1, #self.Samples)
	if k2 == k then
		return self.Samples[k]
	end
	local d = self.CumLen[k2] - self.CumLen[k]
	local f = d > 1e-6 and (s - self.CumLen[k]) / d or 0
	if self.SampleSeg[k] == self.SampleSeg[k2] then
		local lt = self.SampleT[k] + (self.SampleT[k2] - self.SampleT[k]) * f
		local p0, p1, p2, p3 = self:_controlFor(self.SampleSeg[k])
		return crCentripetal(p0, p1, p2, p3, lt)
	end
	return self.Samples[k]:Lerp(self.Samples[k2], f)
end

function Spline:GetTangent(t)
	local dt = 0.25 / #self.Samples
	local a, b
	if self.Closed then
		a, b = self:GetPoint(t - dt), self:GetPoint(t + dt)
	else
		a, b = self:GetPoint(math.max(0, t - dt)), self:GetPoint(math.min(1, t + dt))
	end
	local v = b - a
	if v.Magnitude < 1e-6 then
		return Vector3.zAxis
	end
	return v.Unit
end

function Spline:GetCFrame(t)
	local pos = self:GetPoint(t)
	local look = self:GetTangent(t)
	local up = Vector3.yAxis
	if math.abs(look:Dot(up)) > 0.99 then
		up = Vector3.xAxis
	end
	return CFrame.lookAt(pos, pos + look, up)
end

function Spline:NearestPoint(pos)
	local samples = self.Samples
	local bestI, bestD = 1, math.huge
	for i = 1, #samples do
		local d = (samples[i] - pos).Magnitude
		if d < bestD then
			bestD, bestI = d, i
		end
	end
	local function refine(iA, iB)
		local lo, hi = self.CumLen[iA], self.CumLen[iB]
		for _ = 1, 24 do
			local m1 = lo + (hi - lo) / 3
			local m2 = hi - (hi - lo) / 3
			local d1 = (self:GetPoint(m1 / self.Length) - pos).Magnitude
			local d2 = (self:GetPoint(m2 / self.Length) - pos).Magnitude
			if d1 < d2 then hi = m2 else lo = m1 end
		end
		local s = (lo + hi) / 2
		local t = self:_wrap(s / self.Length)
		local p = self:GetPoint(t)
		return t, p, (p - pos).Magnitude
	end
	local t, p, d = refine(math.max(1, bestI - 1), math.min(#samples, bestI + 1))
	if self.Closed and (bestI <= 2 or bestI >= #samples - 1) then
		local t2, p2, d2 = refine(math.max(1, #samples - 2), #samples)
		if d2 < d then t, p, d = t2, p2, d2 end
		local t3, p3, d3 = refine(1, math.min(3, #samples))
		if d3 < d then t, p, d = t3, p3, d3 end
	end
	return t, p, d
end

return Spline
