-- NeonRun / FixedStep (M4.1 / ADR-33) —— 60Hz 固定步长累加器
-- 物理/经济/计时全部以固定 dt=1/60 推进;渲染帧率与物理步解耦(渲染插值见 BikeController:renderInterpolate)。
-- 单帧最多 maxSteps(3)步 ≈ 旧 `dt=math.min(dt,1/20)` 钳制;超出丢弃——卡顿不补步、物理不欠账,
-- 计时=步数×1/60 与物理同基(卡顿设备不吃亏也偷不到时间,ADR-33)。
-- 确定性:同一输入序列,无论宿主帧率(23/47/61/144Hz)如何切帧,步序列与纯 1/60 逐位一致(accept_m4_1 ⑤)。
local FixedStep = {}
FixedStep.__index = FixedStep

FixedStep.STEP_DT = 1 / 60

function FixedStep.new(opts)
	local self = setmetatable({}, FixedStep)
	self.stepDt = (opts and opts.stepDt) or FixedStep.STEP_DT
	self.maxSteps = (opts and opts.maxSteps) or 3
	self.acc = 0
	self.stepCount = 0   -- 累计物理步数(时间=stepCount×stepDt)
	return self
end

-- 喂入一帧真实 dt;对每个应执行的固定步调用 stepFn(stepDt, stepCount)。返回本帧步数。
function FixedStep:update(frameDt, stepFn)
	self.acc += frameDt
	local n = 0
	while self.acc >= self.stepDt and n < self.maxSteps do
		self.acc -= self.stepDt
		self.stepCount += 1
		n += 1
		stepFn(self.stepDt, self.stepCount)
	end
	if self.acc >= self.stepDt then
		self.acc = self.acc % self.stepDt   -- 溢出丢弃(严重卡顿帧;≈旧 1/20 钳)
	end
	return n
end

-- 渲染插值系数:累加器余量/步长 ∈ [0,1)
function FixedStep:alpha()
	return self.acc / self.stepDt
end

function FixedStep:reset()
	self.acc = 0
	self.stepCount = 0
end

return FixedStep
