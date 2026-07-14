-- NeonRun / BikeController (M2 物理 + M3 视觉表现层 + M4 碰撞三档/快速重生)
-- 高度/起飞判定 = 中心探针;姿态法线 = 前后探针(ADR-4)。全参数走 Config/Handling Attributes。
-- M3:物理位置 = self.physPos(独立状态);root.CFrame = 物理位姿 × 视觉叠加。视觉量绝不回流物理。
-- M4:碰撞三档(ADR-6)——擦碰(滑墙泄速+回能事件)/硬撞(转场→样条最近点重生,恢复60%速度)/坠落(同硬撞)。
--     事件:graze / hardHit / fell / respawned(供能量系统 M5 与表现层订阅)。
local RS = game:GetService("ReplicatedStorage")

local BikeController = {}
BikeController.__index = BikeController

function BikeController.new(model)
	local self = setmetatable({}, BikeController)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	local inst = nr.Config.Handling
	self.cfg = ConfigLive.bind(inst, require(inst))
	self.model = model
	self.root = model.PrimaryPart
	self.rawSteer = 0
	self.steer = 0
	self.sprint = false
	self.sprintAllowed = true  -- M5 能量门:能量耗尽时由 EnergyState 置 false,强制冲刺失效
	self.flowBoost = false     -- ADR-31 心流冲刺升档:由 EnergyState flowStart/flowEnd 事件驱动
	self.brake = false      -- M2.1 轻刹输入(S);刹车优先于冲刺
	self.brakeFrac = 1      -- M2.1 当前速度/base 比例(HUD 遥测用)
	self.curSpeed = 0
	self.grounded = true
	self.vy = 0
	self.vySurf = 0
	self.wallContact = false
	self.lastHitAngle = nil
	local look = self.root.CFrame.LookVector
	self.yaw = math.atan2(-look.X, -look.Z)
	self.physPos = self.root.Position
	self.smoothNormal = Vector3.yAxis -- 姿态法线时间平滑(Ground_AlignLerpSpeed)
	-- M3 视觉状态(只写 root.CFrame,不参与物理)
	self.visualRoll = 0
	self.rollVel = 0
	self.visualPitch = 0
	self.suspY = 0
	self.suspVel = 0
	self.prevGrounded = true
	self.lastLandVy = 0
	self.forkMotors = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "ForkMotor" then
			table.insert(self.forkMotors, d)
		end
	end
	-- M4 状态
	self.spline = nil        -- setSpline 注入(重生/坠落判定依赖)
	self.respawnT = nil      -- 非 nil = 重生转场倒计时
	self.resetCount = 0      -- 硬撞+坠落重置计数(作者牌"零重置"用)
	self._prevWall = false
	-- 碰撞三档扩展:撞死(滑行+打转)/弹开(法线反射)状态
	self.crashT = nil          -- 非nil = 撞死滑行+打转中
	self.crashSpin = 0         -- 撞死视觉打转累计角度(只写 root.CFrame,相机读 yaw 不受影响)
	self.crashSpinDir = 1
	self.bounceCD = 0          -- 弹开冷却
	self.lastContactPoint = nil   -- 最近墙面接触点(火花定位)
	self.lastContactNormal = nil
	self._events = { graze = {}, hardHit = {}, fell = {}, respawned = {}, bounce = {} }
	self.rp = RaycastParams.new()
	self.rp.FilterType = Enum.RaycastFilterType.Exclude
	self.rp.FilterDescendantsInstances = { model }
	self.root.Anchored = true
	return self
end

function BikeController:setSteer(v) self.rawSteer = math.clamp(v, -1, 1) end
function BikeController:setSprint(b) self.sprint = b == true end
function BikeController:setSprintAllowed(b) self.sprintAllowed = b ~= false end  -- M5 能量门
function BikeController:setBrake(b) self.brake = b == true end
function BikeController:setFlowBoost(b) self.flowBoost = b == true end  -- ADR-31:心流=冲刺倍率升档(唯一数值效果)
function BikeController:applySpeedMultiplier(m)  -- M7:一次性速度惩罚(斩击失误减速);不低于 0
	self.curSpeed = math.max(0, self.curSpeed * math.clamp(m, 0, 1))
end
function BikeController:setSpline(sp) self.spline = sp end
function BikeController:isRespawning() return self.respawnT ~= nil end

-- 事件订阅:on("graze"|"hardHit"|"fell"|"respawned", fn)
function BikeController:on(name, fn)
	assert(self._events[name], "未知事件: " .. tostring(name))
	table.insert(self._events[name], fn)
	return fn
end

function BikeController:_fire(name, payload)
	for _, f in ipairs(self._events[name]) do
		task.spawn(f, payload)
	end
end

function BikeController:teleport(cf, keepSpeedFrac)
	self.root.CFrame = cf
	local look = cf.LookVector
	self.yaw = math.atan2(-look.X, -look.Z)
	self.physPos = cf.Position
	self.smoothNormal = Vector3.yAxis
	self.curSpeed = self.curSpeed * (keepSpeedFrac or 0)
	self.grounded = true
	self.vy = 0
	self.vySurf = 0
	self.steer = 0
	self.rawSteer = 0
	self.brake = false
	self.brakeFrac = 1
	self.wallContact = false
	self._prevWall = false
	self.visualRoll, self.rollVel = 0, 0
	self.visualPitch = 0
	self.suspY, self.suspVel = 0, 0
	self.prevGrounded = true
	self.lastLandVy = 0
	self.crashT = nil
	self.crashSpin = 0
	self.bounceCD = 0
	for _, mtr in ipairs(self.forkMotors) do mtr.Transform = CFrame.identity end
end

function BikeController:getTelemetry()
	return {
		speed = self.curSpeed,
		grounded = self.grounded,
		steer = self.steer,
		sprint = self.sprint,
		sprinting = self.sprint and self.sprintAllowed,  -- M5:实际生效的冲刺(区分“按了但无能量”)
		lastHitAngle = self.lastHitAngle,
		wallContact = self.wallContact,
		contactPoint = self.lastContactPoint,
		crashing = self.crashT ~= nil,
		vy = self.grounded and 0 or self.vy,
		roll = self.visualRoll,
		braking = self.brake,
		brakeFrac = self.brakeFrac,
		flowBoost = self.flowBoost,  -- ADR-31(HUD/仿真断言用)
		respawning = self.respawnT ~= nil,
		resetCount = self.resetCount,
	}
end

-- M4:进入重生转场(kind = "hardHit" | "fell")
function BikeController:_beginRespawn(kind)
	if self.respawnT then return end
	local C = self.cfg.get
	self.respawnT = C("Respawn", "TransitionSec")
	self.resetCount += 1
	self:_fire(kind, { speed = self.curSpeed, angle = self.lastHitAngle, pos = self.physPos, resetCount = self.resetCount })
end

-- M4:执行重生——样条最近点 + 切线朝向 + 恢复部分速度
function BikeController:_doRespawn()
	local C = self.cfg.get
	local frac = C("Respawn", "SpeedRestore")
	if self.spline then
		local t = self.spline:NearestPoint(self.physPos)
		local cf = self.spline:GetCFrame(t)
		local pos = cf.Position + Vector3.new(0, C("Ground", "HoverHeight"), 0)
		self:teleport(CFrame.lookAt(pos, pos + cf.LookVector), frac)
	else
		-- 无样条兜底(测试台):原地抬升,保持朝向
		local look = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
		local pos = self.physPos + Vector3.new(0, 2, 0)
		self:teleport(CFrame.lookAt(pos, pos + look), frac)
	end
	self:_fire("respawned", { pos = self.physPos, resetCount = self.resetCount })
end

-- 撞死——进入滑行+打转状态(不冻结),结束后重生
function BikeController:_beginCrash()
	if self.crashT or self.respawnT then return end
	local C = self.cfg.get
	self.crashT = C("Collision", "CrashSlideSec")
	self.crashSpin = 0
	self.resetCount += 1
	-- 顺撞击法线甩:法线在行进方向左侧则逆时针,右侧则顺时针
	local look = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
	local n = self.lastContactNormal or Vector3.yAxis
	local nH = Vector3.new(n.X, 0, n.Z)
	local side = (nH.Magnitude > 1e-4) and look:Cross(nH.Unit).Y or 0
	self.crashSpinDir = (side >= 0) and 1 or -1
	self:_fire("hardHit", { speed = self.curSpeed, angle = self.lastHitAngle, pos = self.lastContactPoint or self.physPos, resetCount = self.resetCount })
end

-- 弹开——速度方向沿墙面法线反射,泄速,发火花事件,继续行驶
function BikeController:_doBounce()
	local C = self.cfg.get
	local n = self.lastContactNormal or Vector3.yAxis
	local nH = Vector3.new(n.X, 0, n.Z)
	if nH.Magnitude < 1e-4 then return end
	nH = nH.Unit
	local look = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
	local refl = look - 2 * look:Dot(nH) * nH
	refl = Vector3.new(refl.X, 0, refl.Z)
	if refl.Magnitude > 1e-4 then
		refl = refl.Unit
		self.yaw = math.atan2(-refl.X, -refl.Z)
	end
	self.curSpeed *= C("Collision", "BounceSlowdown")
	self.bounceCD = C("Collision", "BounceCooldown")
	self:_fire("bounce", { pos = self.lastContactPoint, normal = n, speed = self.curSpeed, angle = self.lastHitAngle })
end

function BikeController:_sweepMove(pos, look, stepLen)
	local C = self.cfg.get
	local margin = C("Collision", "SkinWidth") + C("Collision", "FrontOffset")
	local hover = C("Ground", "HoverHeight")
	local hit = workspace:Raycast(pos, look * (stepLen + margin), self.rp)
	local lowHit = workspace:Raycast(pos - Vector3.new(0, hover * 0.6, 0), look * (stepLen + margin), self.rp)
	if lowHit and (not hit or lowHit.Distance < hit.Distance) then hit = lowHit end
	self.wallContact = false
	if not hit then
		return look * stepLen
	end
	local slope = math.deg(math.acos(math.clamp(hit.Normal:Dot(Vector3.yAxis), -1, 1)))
	if self.grounded and slope <= C("Physics", "MaxSlopeDeg") then
		return look * stepLen
	end
	-- M4 修正:低矮可跨越物豁免——在"地面 + MaxStepUp"高度再扫一次,
	-- 该高度畅通(或命中物远于当前障碍)则障碍低于台阶上限,放行交给贴地逻辑爬升。
	-- 可跨越高度与爬升 stepCap 共用 Physics_MaxStepUp,判定必然一致。
	if self.grounded then
		local stepY = pos.Y - hover + C("Physics", "MaxStepUp") + 0.15
		local stepHit = workspace:Raycast(Vector3.new(pos.X, stepY, pos.Z), look * (stepLen + margin), self.rp)
		if not stepHit or stepHit.Distance > hit.Distance + margin then
			return look * stepLen
		end
	end
	self.wallContact = true
	self.lastContactPoint = hit.Position
	self.lastContactNormal = hit.Normal
	local nH = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
	if nH.Magnitude > 1e-4 then
		self.lastHitAngle = math.deg(math.asin(math.clamp(-look:Dot(nH.Unit), 0, 1)))
	end
	local allowed = math.max(0, hit.Distance - margin)
	local remaining = stepLen - allowed
	local slide = look - hit.Normal * look:Dot(hit.Normal)
	slide = Vector3.new(slide.X, 0, slide.Z)
	local move = look * allowed
	if slide.Magnitude > 1e-3 and remaining > 0 then
		slide = slide.Unit
		local keep = math.clamp(look:Dot(slide), 0, 1)
		local slideLen = remaining * keep
		local s2 = workspace:Raycast(pos + move, slide * (slideLen + margin), self.rp)
		if s2 then slideLen = math.min(slideLen, math.max(0, s2.Distance - margin)) end
		move += slide * slideLen
	end
	return move
end

-- M3 视觉层:滚转弹簧/空中抬头/落地悬挂/前叉 Motor6D
function BikeController:_visualStep(dt, baseCF)
	local C = self.cfg.get
	local rollMax = C("Lean", "BodyRollMaxDeg")
	local target = self.steer * rollMax
	local wn = math.max(C("Lean", "LerpSpeed"), 0.1)
	local r = math.clamp(C("Lean", "OvershootDeg") / math.max(rollMax, 1e-3), 0.001, 0.93)
	local L = math.log(1 / r)
	local zeta = L / math.sqrt(math.pi ^ 2 + L ^ 2)
	self.rollVel += ((target - self.visualRoll) * wn * wn - 2 * zeta * wn * self.rollVel) * dt
	self.visualRoll += self.rollVel * dt
	local pitchTarget = (not self.grounded and self.vy > 0) and C("Lean", "AirPitchUpDeg") or 0
	self.visualPitch += (pitchTarget - self.visualPitch) * math.min(wn * dt, 1)
	if self.grounded and not self.prevGrounded then
		local dip = math.min(math.abs(self.lastLandVy) * C("Lean", "SuspensionDipPerVy"), C("Lean", "SuspensionDipMax"))
		self.suspY = -dip
		self.suspVel = 0
	end
	local sw = 2 * math.pi * math.max(C("Lean", "SuspensionFreqHz"), 0.1)
	local sz = C("Lean", "SuspensionDamping")
	self.suspVel += ((0 - self.suspY) * sw * sw - 2 * sz * sw * self.suspVel) * dt
	self.suspY += self.suspVel * dt
	self.prevGrounded = self.grounded
	local forkRad = math.rad(self.steer * C("Lean", "ForkMaxDeg"))
	for _, mtr in ipairs(self.forkMotors) do
		mtr.Transform = CFrame.Angles(0, forkRad, 0)
	end
	self.root.CFrame = baseCF
		* CFrame.new(0, self.suspY, 0)
		* CFrame.Angles(math.rad(self.visualPitch), 0, math.rad(self.visualRoll))
end

function BikeController:step(dt)
	dt = math.min(dt, 1 / 20)
	local C = self.cfg.get

	-- M4:重生转场中——车冻结原地(故障艺术占位),输入忽略,倒计时结束执行重生
	if self.respawnT then
		self.respawnT -= dt
		if self.respawnT <= 0 then
			self.respawnT = nil
			self:_doRespawn()
		end
		return
	end

	-- 撞死滑行+打转中——不冻结,每帧滑行泄速+视觉打转,结束才重生
	if self.crashT then
		self.crashT -= dt
		self.curSpeed = math.max(0, self.curSpeed * math.pow(C("Collision", "CrashSlowdown"), dt * 6))
		local look = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
		local moveVec = self:_sweepMove(self.physPos, look, self.curSpeed * dt) -- 贴墙滑行,不穿墙;同时刷新 lastContactPoint(火花跟随)
		local np = self.physPos + moveVec
		local hover = C("Ground", "HoverHeight")
		local gC = workspace:Raycast(np + Vector3.new(0, hover + 4, 0), Vector3.new(0, -(hover + 16), 0), self.rp)
		local y = gC and (gC.Position.Y + hover) or self.physPos.Y
		self.physPos = Vector3.new(np.X, y, np.Z)
		self.crashSpin += C("Collision", "CrashSpinDegPerSec") * self.crashSpinDir * dt
		if self.crashT <= 0 then
			self.crashT = nil
			self:_doRespawn()
			return
		end
		-- 打转只写 root.CFrame(相机读 yaw/physPos,不跟随旋转)
		self.root.CFrame = CFrame.lookAt(self.physPos, self.physPos + look, Vector3.yAxis)
			* CFrame.Angles(0, math.rad(self.crashSpin), 0)
		return
	end
	if self.bounceCD > 0 then self.bounceCD = math.max(0, self.bounceCD - dt) end

	local rampIn = C("Steering", "InputRampInSec")
	local rampOut = C("Steering", "InputRampOutSec")
	local engaging = math.abs(self.rawSteer) > math.abs(self.steer)
		or (self.rawSteer ~= 0 and math.sign(self.rawSteer) ~= math.sign(self.steer))
	local ramp = engaging and rampIn or rampOut
	local maxDelta = dt / math.max(ramp, 1e-3)
	self.steer += math.clamp(self.rawSteer - self.steer, -maxDelta, maxDelta)

	local base = C("Speed", "Base")
	local sprintSpeed = base * C("Speed", "SprintMultiplier")
	-- ADR-31 心流升档:冲刺目标 ×FlowExtraMultiplier(总速≈146);flowBoost 滞后一帧无害
	local maxSpeed = sprintSpeed * (self.flowBoost and C("Speed", "FlowExtraMultiplier") or 1)
	-- M2.1 轻刹(S):刹车优先于冲刺。BrakeEnabled 实验开关关闭则无轻刹。
	--   目标速度 = base × BrakeFloor;刹车时 sprint 被压制,永不乘 SprintMultiplier(=不抬目标=不耗能)。
	--   渐入速率 = base×(1-BrakeFloor)/BrakeRampInSec ⇒ 巡航→地板 恰 BrakeRampInSec(clamp 积分,不硬置)。
	-- M5:实际冲刺 = 输入冲刺 且 能量允许(空槽不能冲)。
	local brakeOn = self.brake and (C("Speed", "BrakeEnabled") ~= false)
	local brakeFloor = C("Speed", "BrakeFloor")
	local brakeRampIn = math.max(C("Speed", "BrakeRampInSec"), 1e-3)
	local sprintEff = self.sprint and self.sprintAllowed
	local targetSpeed
	if brakeOn then
		targetSpeed = base * brakeFloor
	else
		targetSpeed = sprintEff and maxSpeed or base
	end
	local rate
	if brakeOn then
		rate = base * (1 - brakeFloor) / brakeRampIn
	else
		local rampT = targetSpeed > self.curSpeed and C("Speed", "RampUpSec") or C("Speed", "RampDownSec")
		rate = maxSpeed / math.max(rampT, 1e-3)
	end
	self.curSpeed += math.clamp(targetSpeed - self.curSpeed, -rate * dt, rate * dt)
	self.brakeFrac = self.curSpeed / math.max(base, 1e-3)
	if self.wallContact then
		self.curSpeed *= math.pow(C("Collision", "GrazeSlowdown"), dt * 6)
	end

	-- 转向插值锚定冲刺速度(135)封顶:心流 146 不再降转向角速度(ADR-31,唯一手感代价=弯弧+8%);
	-- M2 基准"100 速转向率 69.3°/s"依赖此分母,勿改回 maxSpeed
	local frac = math.clamp(self.curSpeed / math.max(sprintSpeed, 1), 0, 1)
	local turnRate = math.rad(C("Steering", "TurnRateLowDeg")
		+ (C("Steering", "TurnRateHighDeg") - C("Steering", "TurnRateLowDeg")) * frac)
	self.yaw += self.steer * turnRate * dt
	local look = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))

	local pos = self.physPos
	local moveVec = self:_sweepMove(pos, look, self.curSpeed * dt)
	local hx = pos + moveVec

	-- 碰撞分三档(阈值全在 Config)——撞死/弹开/擦墙
	if self.wallContact and self.lastHitAngle then
		local ang = self.lastHitAngle
		if ang >= C("Collision", "HardMinAngleDeg") and self.curSpeed >= C("Collision", "HardMinSpeed") then
			-- 撞死:滑行+打转→重生,本帧车停在墙前(moveVec 已被扫掠截断)
			self.physPos = hx
			self:_beginCrash()
			return
		elseif ang >= C("Collision", "BounceMinAngleDeg") then
			-- 弹开(含低速陡角降级):反射方向+泄速+火花,继续行驶
			self.physPos = hx
			if self.bounceCD <= 0 then self:_doBounce() end
		elseif not self._prevWall then
			-- 擦墙上升沿:回能事件(擦墙滑行+持续火花由表现层读 wallContact/contactPoint)
			self:_fire("graze", { angle = ang, speed = self.curSpeed })
		end
	end
	self._prevWall = self.wallContact

	local hover = C("Ground", "HoverHeight")
	local gravity = C("Physics", "Gravity")
	local normal = Vector3.yAxis
	local newPos

	if self.grounded then
		local half = C("Ground", "WheelBase") * 0.5
		local up = C("Physics", "MaxStepUp") + 6
		local down = up + hover + 12
		local function probe(p)
			return workspace:Raycast(Vector3.new(p.X, pos.Y + up, p.Z), Vector3.new(0, -down, 0), self.rp)
		end
		local gC = probe(hx)
		local ballisticY = pos.Y + self.vySurf * dt - 0.5 * gravity * dt * dt
		if gC then
			-- 高度与起飞:只看中心探针(前后探针会提前看到下坡,磨掉起飞速度)
			local targetY = gC.Position.Y + hover
			local dy = targetY - pos.Y
			local horiz = Vector3.new(moveVec.X, 0, moveVec.Z).Magnitude
			local stepCap = math.max(C("Physics", "MaxStepUp"), horiz * math.tan(math.rad(C("Physics", "MaxSlopeDeg"))) + 0.1)
			if dy > stepCap then
				newPos = pos
			elseif targetY < ballisticY - C("Physics", "DetachTolerance") then
				self.grounded = false
				self.vy = self.vySurf - gravity * dt
				newPos = Vector3.new(hx.X, ballisticY, hx.Z)
			else
				newPos = Vector3.new(hx.X, targetY, hx.Z)
				self.vySurf = (targetY - pos.Y) / math.max(dt, 1e-4)
				local gF = probe(hx + look * half)
				local gR = probe(hx - look * half)
				local nSum = gC.Normal
					+ (gF and gF.Normal or gC.Normal)
					+ (gR and gR.Normal or gC.Normal)
				normal = nSum.Unit
			end
		else
			self.grounded = false
			self.vy = self.vySurf - gravity * dt
			newPos = Vector3.new(hx.X, ballisticY, hx.Z)
		end
	else
		self.vy -= gravity * dt
		local newY = pos.Y + self.vy * dt
		if self.vy < 0 then
			local drop = pos.Y - newY
			local land = workspace:Raycast(Vector3.new(hx.X, pos.Y + 0.5, hx.Z), Vector3.new(0, -(drop + hover + 0.5), 0), self.rp)
			if land and land.Position.Y + hover >= newY then
				newY = land.Position.Y + hover
				self.lastLandVy = self.vy
				self.grounded = true
				self.vy = 0
				self.vySurf = 0
				normal = land.Normal
			end
		end
		newPos = Vector3.new(hx.X, newY, hx.Z)
	end

	-- M4:坠落判定(掉出赛道体,同硬撞)
	if self.spline and not self.grounded and self.vy < 0 then
		local _, nearPt = self.spline:NearestPoint(newPos)
		if newPos.Y < nearPt.Y - C("Collision", "FallBelowStuds") then
			self.physPos = newPos
			self:_beginRespawn("fell")
			return
		end
	end

	-- 姿态法线平滑:崎岖地形逐帧法线跳变只影响朝向,不回流物理
	local alignAlpha = 1 - math.exp(-C("Ground", "AlignLerpSpeed") * dt)
	local sn = self.smoothNormal:Lerp(normal, alignAlpha)
	if sn.Magnitude < 1e-4 then sn = normal else sn = sn.Unit end
	self.smoothNormal = sn
	normal = sn
	local surfLook = look - normal * look:Dot(normal)
	if surfLook.Magnitude < 1e-4 then surfLook = look else surfLook = surfLook.Unit end
	self.physPos = newPos
	self:_visualStep(dt, CFrame.lookAt(newPos, newPos + surfLook, normal))
end

function BikeController:destroy()
	for _, mtr in ipairs(self.forkMotors) do mtr.Transform = CFrame.identity end
end

return BikeController