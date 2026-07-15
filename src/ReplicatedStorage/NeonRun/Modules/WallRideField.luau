-- NeonRun / WallRideField (M6.5) —— 授权贴墙段注册与进入查询(ADR-36,design §4.9/E4-1)
-- 数据模型:带 `WallRideSurface` Tag 的 Part = 一段直墙(曲墙随 TrackBuilder P3)。
-- 摆放约定(TrackBuilder P3 生成沿用):
--   Part ±X 两个大面 = 可贴面(两侧皆可骑);Z 轴 = 墙长(切向);Y 轴 = 墙高。
--   即 Size = (厚度, 墙高, 墙长);V1 直墙要求 UpVector ≈ 世界 Y(倾斜/倒挂 = V3)。
-- 职责:纯几何注册+触发区查询,零物理零状态;策略阈值(速度/角度/窗口)由调用方传入。
-- 经济中性(ADR-37):本模块与能量零往来——墙段不存在任何收入语义。
local CollectionService = game:GetService("CollectionService")

local TAG = "WallRideSurface"

local WallRideField = {}
WallRideField.__index = WallRideField

local function makeSegment(part)
	return {
		part = part,
		halfT = part.Size.X * 0.5, -- 厚度半宽(法线轴)
		halfH = part.Size.Y * 0.5, -- 墙高半高
		halfL = part.Size.Z * 0.5, -- 墙长半长(切向轴)
	}
end

function WallRideField.new()
	local self = setmetatable({}, WallRideField)
	self.segments = {}
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		if part:IsA("BasePart") then
			self.segments[part] = makeSegment(part)
		end
	end
	self._addedConn = CollectionService:GetInstanceAddedSignal(TAG):Connect(function(part)
		if part:IsA("BasePart") then
			self.segments[part] = makeSegment(part)
		end
	end)
	self._removedConn = CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
		self.segments[part] = nil
	end)
	return self
end

-- 进入触发查询(地面/空中皆可;调用方每帧在自身物理步末尾调用)。
-- pos: 车 physPos;lookH: 水平航向单位向量;speed: 当前速度。
-- opts: { window, minSpeed, maxAngleDeg, minToward } —— 全部来自 WallRide_* Config。
-- 返回命中面描述(取 sideDist 最近的合格面,几何择优与遍历顺序无关=确定性):
--   { seg, sign, n(世界外法线), along(世界切向,已对齐航向), localY, localZ }
function WallRideField:findEntry(pos, lookH, speed, opts)
	if speed < opts.minSpeed then
		return nil
	end
	local cosMax = math.cos(math.rad(opts.maxAngleDeg))
	local best, bestDist = nil, math.huge
	for part, seg in pairs(self.segments) do
		if part.Parent then
			local cf = part.CFrame
			local lp = cf:PointToObjectSpace(pos)
			local sideDist = math.abs(lp.X) - seg.halfT
			-- 触发区:面外 [0, window] × 墙长内 × 墙高内
			if sideDist >= 0 and sideDist <= opts.window
				and math.abs(lp.Z) <= seg.halfL
				and math.abs(lp.Y) <= seg.halfH then
				local sign = (lp.X >= 0) and 1 or -1
				local n = cf.RightVector * sign -- 所在侧外法线
				local segLook = cf.LookVector
				local dotAlong = lookH:Dot(segLook)
				local along = (dotAlong >= 0) and segLook or -segLook
				-- 航向与切向夹角 ≤ maxAngleDeg,且有朝墙横向分速(平行路过不误吸)
				local toward = (lookH * speed):Dot(-n)
				if math.abs(dotAlong) >= cosMax and toward >= opts.minToward and sideDist < bestDist then
					best = { seg = seg, sign = sign, n = n, along = along, localY = lp.Y, localZ = lp.Z }
					bestDist = sideDist
				end
			end
		end
	end
	return best
end

-- 墙面命中描述的世界几何(墙态每帧钉扎/边界判定用;直墙静态,数值恒定)
--   hoverPlanePoint: 面上过 Part 中心的点 + 法向;调用方以 (pos-点)·n 求离面距离
function WallRideField.facePoint(hit)
	local seg, cf = hit.seg, hit.seg.part.CFrame
	return cf.Position + hit.n * seg.halfT
end

-- M8.5 直墙链跨段交接(ADR-41:曲墙=离散直墙链):当前段 Z 越界时,找"同面、同向、
-- 覆盖当前位置"的相邻段无缝续吸;找不到=真·段尾(调用方走弹道交接)。
-- opts: { minDot(面/切向对齐余弦), hover, tol(离面高容差) }
-- 交接段几何择优与遍历顺序无关:候选唯一性由链搭接保证(相邻段小搭接,当前段已 Z 越界被自然排除)。
function WallRideField:findContinuation(pos, n, along, opts)
	local best, bestErr = nil, math.huge
	for part, seg in pairs(self.segments) do
		if part.Parent then
			local cf = part.CFrame
			local lp = cf:PointToObjectSpace(pos)
			if math.abs(lp.Z) <= seg.halfL and math.abs(lp.Y) <= seg.halfH then
				local sign = (lp.X >= 0) and 1 or -1
				local n2 = cf.RightVector * sign
				local segLook = cf.LookVector
				local along2 = (along:Dot(segLook) >= 0) and segLook or -segLook
				local sideDist = math.abs(lp.X) - seg.halfT
				local err = math.abs(sideDist - opts.hover)
				if n2:Dot(n) >= opts.minDot and along2:Dot(along) >= opts.minDot
					and err <= opts.tol and err < bestErr then
					best = { seg = seg, sign = sign, n = n2, along = along2 }
					bestErr = err
				end
			end
		end
	end
	return best
end

function WallRideField:destroy()
	if self._addedConn then self._addedConn:Disconnect() end
	if self._removedConn then self._removedConn:Disconnect() end
	self.segments = {}
end

return WallRideField
