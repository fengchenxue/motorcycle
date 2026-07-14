-- NeonRun / RaceTimer —— 计时 + 四奖牌 + 一键重开 + 发车标准化(M8 / 策划案 §3.2§8 / ADR-11)
-- 发车标准化:所有成绩从完全相同的静止起步—→3-2-1 固定点火→绿灯起计(不存在抢跑)。
-- 计时公平:检查点门(样条六职责之一)必须按序穿过=防抄近道;R 任意时刑重开且计入重置次数。
-- 四奖牌:铜(完赛)/银/金(吃透赛道)/作者牌(精通机制,可要求零重置)。阀值在 Config/Medals。
-- 结算命门:"距下一枚奖牌还差 X 秒" + 一键重开。
-- 状态机:idle → countdown(3-2-1) → racing → finished。
-- ⚠️ 欠账(ADR-32,归 M12):本模块当前**全程运行在客户端**(TestDrive 灰盒),
--    计时/门序/奖牌均可被客户端篡改,尚未兑现设计宪法"计时/奖牌只在服务端产生"(E2/§10)。
--    服务端权威=M12(随反作弊/榜单一起做):门序校验+计时结算迁到 ServerScriptService,
--    客户端只做表现;RemoteEvent 上报位置样本,服务端复算。本模块为纯数据+样条查询、
--    无客户端专属 API 依赖,设计为可原样搬到服务端,迁移时只换宿主与输入源。当前灰盒够用。
-- 用法:
--   local timer = RaceTimer.new(ctrl, spline, { trackId = "Track01", laps = 1 })
--   timer:startCountdown()             -- 开始发车序列(车冻结直到绿灯)
--   timer:step(dt)                     -- 每帧;返回当前状态
--   timer:restart()                    -- 一键重开(回发车线,resetCount+1)
--   local t = timer:getTelemetry()     -- { state, countdown, time, checkpoint, medal }
--   timer:on("go"|"finish"|"checkpoint"|"countdown", fn)
--   发车冻结需 TestDrive 配合:timer:isControlLocked() 为 true 时忽略输入
local RS = game:GetService("ReplicatedStorage")

local COUNTDOWN_STEPS = { 3, 2, 1 }   -- 固定点火曲线:每数字 1s,总 3s 后绿灯
local STEP_SEC = 1

local RaceTimer = {}
RaceTimer.__index = RaceTimer

function RaceTimer.new(ctrl, spline, opts)
	opts = opts or {}
	local self = setmetatable({}, RaceTimer)
	self.ctrl = ctrl
	self.spline = spline
	self.trackId = opts.trackId or "Track01"
	self.laps = math.max(1, opts.laps or 1)
	-- 检查点(按序):起点/终点 t=0,中间门均匀布于环上(防倒行/抄近道)
	self.checkpointTs = opts.checkpoints or { 0.25, 0.5, 0.75 }
	-- 读奖牌阀值(结构化数据,直接 require)
	local medalsCfg = require(RS.NeonRun.Config.Medals)
	self.thresholds = (medalsCfg.Tracks and medalsCfg.Tracks[self.trackId]) or
		{ Bronze = 90, Silver = 75, Gold = 65, Author = 58, AuthorZeroReset = true }
	self.state = "idle"
	self.countdownT = 0
	self.countdownNum = nil
	self.time = 0
	self.resetCount = 0
	self.lapsDone = 0
	self.nextCheckpoint = 1     -- 下一个必须穿过的检查点索引
	self.result = nil
	self._prevT = 0
	self._events = { countdown = {}, go = {}, checkpoint = {}, finish = {}, restart = {} }
	return self
end

function RaceTimer:on(name, fn)
	assert(self._events[name], "未知事件: " .. tostring(name))
	table.insert(self._events[name], fn); return fn
end
function RaceTimer:_fire(name, p) for _, f in ipairs(self._events[name]) do task.spawn(f, p) end end

-- 发车标准化:进入倒计时(车冻结),3-2-1 后绿灯起计
function RaceTimer:startCountdown()
	self.state = "countdown"
	self.countdownT = #COUNTDOWN_STEPS * STEP_SEC
	self.countdownNum = COUNTDOWN_STEPS[1]
	self.time = 0
	self.lapsDone = 0
	self.nextCheckpoint = 1
	self.result = nil
	if self.ctrl and self.ctrl.physPos and self.spline then
		self._prevT = select(1, self.spline:NearestPoint(self.ctrl.physPos))
	end
	self:_fire("countdown", { num = self.countdownNum })
end

-- 发车冻结:倒计时期间输入忽略(TestDrive 检查此位)
function RaceTimer:isControlLocked()
	return self.state == "countdown" or self.state == "idle" or self.state == "finished"
end

function RaceTimer:restart()
	-- 一键重开:回发车线,重置次数 +1(R 也走此路)
	self.resetCount += 1
	self:_fire("restart", { resetCount = self.resetCount })
	self:startCountdown()
end

-- 根据时间定奖牌(作者牌颜外需 resetCount==0 若 AuthorZeroReset)
function RaceTimer:_computeMedal(time)
	local th = self.thresholds
	local authorOK = time <= th.Author and (not th.AuthorZeroReset or self.resetCount == 0)
	if authorOK then return "Author" end
	if time <= th.Gold then return "Gold" end
	if time <= th.Silver then return "Silver" end
	if time <= th.Bronze then return "Bronze" end
	return nil  -- 未完赛阀(理论上完赛即铜,除非 Bronze 阀设得比完赛时间还严)
end

-- 结算:"距下一枚奖牌还差 X 秒"
function RaceTimer:_buildResult(time)
	local th = self.thresholds
	local medal = self:_computeMedal(time)
	-- 下一枚更高奖牌与差值
	local ladder = { { "Author", th.Author }, { "Gold", th.Gold }, { "Silver", th.Silver }, { "Bronze", th.Bronze } }
	local nextMedal, gap = nil, nil
	-- 找比当前成绩更快、且玩家尚未达到的最近一档
	for i = #ladder, 1, -1 do
		local name, thresh = ladder[i][1], ladder[i][2]
		if time > thresh then
			nextMedal = name
			gap = time - thresh
			break
		end
	end
	return {
		time = time,
		medal = medal,
		resetCount = self.resetCount,
		nextMedal = nextMedal,
		gapToNext = gap,   -- “差 X 秒就是<nextMedal>”
		thresholds = th,
	}
end

function RaceTimer:step(dt)
	if self.state == "countdown" then
		-- 车冻结(双保险:速度归零),倒数
		if self.ctrl and self.ctrl.applySpeedMultiplier then self.ctrl:applySpeedMultiplier(0) end
		local prev = self.countdownT
		self.countdownT = math.max(0, self.countdownT - dt)
		local newNum = math.ceil(self.countdownT / STEP_SEC)
		if newNum ~= self.countdownNum and newNum >= 1 then
			self.countdownNum = newNum
			self:_fire("countdown", { num = newNum })
		end
		if self.countdownT <= 0 then
			-- 绿灯!起计
			self.state = "racing"
			self.time = 0
			self.countdownNum = nil
			if self.ctrl and self.ctrl.physPos and self.spline then
				self._prevT = select(1, self.spline:NearestPoint(self.ctrl.physPos))
			end
			self:_fire("go", {})
		end
		return self.state
	end

	if self.state ~= "racing" then return self.state end

	-- 计时推进
	self.time += dt

	-- 检查点门:当前样条参数跨过下一检查点 t 则计数(防抄近道需按序)
	if self.ctrl and self.ctrl.physPos and self.spline then
		local curT = select(1, self.spline:NearestPoint(self.ctrl.physPos))
		-- 处理环形包围:向前进展量。
		-- 关键防坑:一帧向后微动(如 0.02→0.005)经 mod 会被误读为“前进 98%”而扫过所有门。
		-- 真实帧进展极小(百速约 0.0015/帧),故超过 MAX_ADV 的“前进”实为倒行/传送,不计门。
		local MAX_ADV = 0.15
		local frameAdv = (curT - self._prevT) % 1
		local forwardValid = frameAdv <= MAX_ADV  -- 合理向前进展才允许过门
		local function crossedForward(fromT, toT, gateT)
			if not forwardValid then return false end
			local adv = (toT - fromT) % 1
			local gateAdv = (gateT - fromT) % 1
			return gateAdv > 0 and gateAdv <= adv + 1e-6
		end
		if self.nextCheckpoint <= #self.checkpointTs then
			local gateT = self.checkpointTs[self.nextCheckpoint]
			if crossedForward(self._prevT, curT, gateT) then
				self.nextCheckpoint += 1
				self:_fire("checkpoint", { index = self.nextCheckpoint - 1, total = #self.checkpointTs })
			end
		else
			-- 所有检查点已过,检测终点(t=0/1 包围)
			if crossedForward(self._prevT, curT, 0) then
				self.lapsDone += 1
				if self.lapsDone >= self.laps then
					self.state = "finished"
					self.result = self:_buildResult(self.time)
					self:_fire("finish", self.result)
				else
					-- 下一圈:重置检查点序列
					self.nextCheckpoint = 1
				end
			end
		end
		self._prevT = curT
	end
	return self.state
end

function RaceTimer:getResult() return self.result end

function RaceTimer:getTelemetry()
	return {
		state = self.state,
		countdown = self.countdownNum,
		time = self.time,
		checkpoint = self.nextCheckpoint - 1,
		totalCheckpoints = #self.checkpointTs,
		lapsDone = self.lapsDone,
		laps = self.laps,
		resetCount = self.resetCount,
		medal = self.result and self.result.medal or nil,
	}
end

function RaceTimer:destroy() end

return RaceTimer