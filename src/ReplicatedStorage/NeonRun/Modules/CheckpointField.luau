-- NeonRun / CheckpointField —— 检查点门框扫掠检测(替换 RaceTimer 的"比 t"过门)
-- 设计:每个检查点 = 一个 Model(Gate 薄幕 + Ball 黄球刷新点)。检测走"上帧→本帧线段 vs
--   门的有向有限矩形"相交:穿越(免高速穿模)+ 框内(免拐弯误判)+ 前向(方向对)三条同时满足。
-- 顺序只由门在样条上的投影 t 升序决定,与名字无关;插入新门零重排。构建只开局跑一次。
-- 用法:
--   local field = CheckpointField.new(spline, folder, hoverHeight)  -- folder 内名为 "Finish" 的 Model 作终点门
--   field:rebuild(); field:getCount()
--   field:crossed(index, prevPos, curPos) / field:crossedFinish(prevPos, curPos) -> boolean
--   field:getRespawnCF(index) / field:getStartCF()
--   for _,w in ipairs(field:validate()) do warn(w) end

local CheckpointField = {}
CheckpointField.__index = CheckpointField

local FINISH_NAME = "Finish"

function CheckpointField.new(spline, folder, hoverHeight, finishGate)
	local self = setmetatable({}, CheckpointField)
	self.spline = spline
	self.folder = folder
	self.hover = hoverHeight or 3
	self.finishGate = finishGate   -- 可选:外部直接传入终点门 Model(否则用 folder 内名为 Finish 的 Model)
	self.gates = {}                -- 检查点门表(按 t 升序):{ model, gate, ball, cf, halfW, halfH, t, respawnCF }
	self.finish = nil              -- 终点门条目(同结构,t 不参与排序)
	self.startCF = nil
	self:rebuild()
	return self
end

-- 由一个 Model 组装一个门条目
function CheckpointField:_entryFromModel(model)
	local gate = model.PrimaryPart or model:FindFirstChild("Gate")
	local ball = model:FindFirstChild("Ball")
	if not gate then return nil end
	local cf = gate.CFrame
	local t = select(1, self.spline:NearestPoint(gate.Position))
	-- 复活位姿:球位置 + 悬浮高 + 门朝向(水平)
	local fwd = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	fwd = fwd.Magnitude > 1e-4 and fwd.Unit or Vector3.zAxis
	local ballPos = ball and ball.Position or gate.Position
	local pos = ballPos + Vector3.new(0, self.hover, 0)
	local respawnCF = CFrame.lookAt(pos, pos + fwd)
	return {
		model = model, gate = gate, ball = ball, cf = cf,
		halfW = gate.Size.X * 0.5, halfH = gate.Size.Y * 0.5,
		t = t, respawnCF = respawnCF,
		order = model:GetAttribute("Order"),   -- 可选:手动顺序(number);一旦本场有任一门设了它,整场改按 Order 排(复杂/自交路段兜底)
	}
end

function CheckpointField:rebuild()
	self.gates = {}
	self.finish = nil
	if self.finishGate then
		self.finish = self:_entryFromModel(self.finishGate)
	end
	for _, child in ipairs(self.folder:GetChildren()) do
		if child:IsA("Model") then
			if not self.finishGate and child.Name == FINISH_NAME then
				self.finish = self:_entryFromModel(child)
			else
				local e = self:_entryFromModel(child)
				if e then table.insert(self.gates, e) end
			end
		end
	end
	-- 排序:本场只要有任一门设了 Order,就整场按 Order(缺失的排末尾,validate 会告警);
	-- 一个都没设则按投影 t 全自动。避免 Order(整数)与 t(0..1)混用错位。
	local anyOrder = false
	for _, e in ipairs(self.gates) do if e.order ~= nil then anyOrder = true break end end
	if anyOrder then
		table.sort(self.gates, function(a, b) return (a.order or math.huge) < (b.order or math.huge) end)
	else
		table.sort(self.gates, function(a, b) return a.t < b.t end)
	end
end

function CheckpointField:getCount() return #self.gates end

-- §2.3 扫掠 × 有限门框:线段 prev→cur 是否"前向"穿过门 e 的有限矩形
local function sweepCross(e, prevPos, curPos)
	local G = e.cf
	local p0 = G:PointToObjectSpace(prevPos)   -- 局部系: X=右, Y=上, Z=后(LookVector = -Z)
	local p1 = G:PointToObjectSpace(curPos)
	if not (p0.Z > 0 and p1.Z <= 0) then return false end   -- 前向穿越:门后(+Z)→门前(-Z)
	local denom = p0.Z - p1.Z
	if math.abs(denom) < 1e-9 then return false end
	local f = p0.Z / denom                                   -- 命中门平面(Z=0)的插值系数
	local xc = p0.X + f * (p1.X - p0.X)
	local yc = p0.Y + f * (p1.Y - p0.Y)
	return math.abs(xc) <= e.halfW and math.abs(yc) <= e.halfH
end

function CheckpointField:crossed(index, prevPos, curPos)
	local e = self.gates[index]
	if not e then return false end
	return sweepCross(e, prevPos, curPos)
end

function CheckpointField:crossedFinish(prevPos, curPos)
	if not self.finish then return false end
	return sweepCross(self.finish, prevPos, curPos)
end

function CheckpointField:getRespawnCF(index)
	local e = self.gates[index]
	return e and e.respawnCF or nil
end

function CheckpointField:getBall(index)
	local e = self.gates[index]
	return e and e.ball or nil
end

-- 调试:返回车当前相对第 index 个门的局部偏移(zBehind>0=在门后, |x|<=halfW & |y|<=halfH=在框内)
function CheckpointField:offsetInfo(index, pos)
	local e = self.gates[index]
	if not e then return nil end
	local lp = e.cf:PointToObjectSpace(pos)
	return { z = lp.Z, x = lp.X, y = lp.Y, halfW = e.halfW, halfH = e.halfH,
		inFrame = math.abs(lp.X) <= e.halfW and math.abs(lp.Y) <= e.halfH }
end

function CheckpointField:setStartCF(cf) self.startCF = cf end
function CheckpointField:getStartCF() return self.startCF end

-- §4 校验:返回告警列表(warn 输出,不阻断)
function CheckpointField:validate()
	local warns = {}
	local all = {}
	for _, e in ipairs(self.gates) do table.insert(all, e) end
	if self.finish then table.insert(all, self.finish) end
	for _, e in ipairs(all) do
		local name = e.model.Name
		if not e.gate or not e.ball then
			table.insert(warns, name .. ": 缺 Gate 或 Ball 子件")
		end
		local _, _, dist = self.spline:NearestPoint(e.gate.Position)
		if dist and dist > 30 then
			table.insert(warns, string.format("%s: 离赛道过远(%.0f studs),投影/排序可能错", name, dist))
		end
		if e.halfW <= 0 or e.halfH <= 0 then
			table.insert(warns, name .. ": 门宽/高 ≤ 0")
		end
		local tan = self.spline:GetTangent(e.t)
		local look = e.cf.LookVector
		local dot = math.clamp(look:Dot(tan), -1, 1)
		if math.deg(math.acos(math.abs(dot))) > 60 then
			table.insert(warns, name .. ": 门朝向与赛道切线夹角 >60°,玩家可能穿不过")
		end
	end
	for i = 2, #self.gates do
		if math.abs(self.gates[i].t - self.gates[i-1].t) < 0.01 then
			table.insert(warns, string.format("%s 与 %s 的 t 过近(<0.01),顺序易错(可给二者填 Order 手动锁序)", self.gates[i-1].model.Name, self.gates[i].model.Name))
		end
	end
	-- Order 兜底:混用/重复检查
	local withOrder, seen = 0, {}
	for _, e in ipairs(self.gates) do
		if e.order ~= nil then
			withOrder += 1
			if seen[e.order] then
				table.insert(warns, string.format("%s 的 Order=%s 与 %s 重复,先后不稳", e.model.Name, tostring(e.order), seen[e.order]))
			end
			seen[e.order] = e.model.Name
		end
	end
	if withOrder > 0 and withOrder < #self.gates then
		table.insert(warns, string.format("有 %d/%d 个门设了 Order、其余没设——没设的会被排到末尾;要用手动顺序请给本场所有门都填 Order", withOrder, #self.gates))
	end
	return warns
end

return CheckpointField
