-- NeonRun / BikeController (M2 物理 + M3 视觉表现层 + M4 碰撞三档/快速重生 + M6.5 贴墙段)
-- 高度/起飞判定 = 中心探针;姿态法线 = 前后探针(ADR-4)。全参数走 Config/Handling Attributes。
-- M3:物理位置 = self.physPos(独立状态);root.CFrame = 物理位姿 × 视觉叠加。视觉量绝不回流物理。
-- M4:碰撞三档(ADR-6)——擦碰(滑墙泄速,纯惩罚)/硬撞(转场→样条最近点重生,恢复60%速度)/坠落(同硬撞)。
--     事件:graze / hardHit / fell / respawned(供能量系统 M5 与表现层订阅)。
-- M6.5:墙态(ADR-36 授权段磁吸)=与 crash/respawn 并列的独立分支,地面/空中路径零改动;
--     进入=触发区探测(纯观察,命中翻状态)→段内磁吸 down=−墙法线+A/D 高度带→退出三种(段尾/上缘弹道、下缘回地)。
--     墙=经济中性(ADR-37):墙态不发 graze、不置 wallContact,与能量零往来。
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

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
	self.forcedSprint = false   -- M8.1 最小点火尾段:松键后 EnergyState 仍强制维持冲刺速直到烧满 0.4s(ADR-13)
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
	-- M6.5 墙态(ADR-36):wall ≠ nil = 磁吸中;wallField 由 setWallField 注入(无场=永不入墙,老场景零影响)
	self.wallField = nil
	self.wall = nil
	-- M4.1 渲染插值(ADR-33):物理步产出 prev/cur 位姿双缓冲,renderInterpolate(alpha) 混合写 root;
	-- renderPos/renderYaw=插值后的相机锚(未调用插值=nil,消费方回退 physPos/yaw——Edit 工具零变化)
	self.prevRenderCF = nil
	self.curRenderCF = nil
	self.prevPhysPos = nil
	self.curPhysPos = nil
	self.prevYawR = nil
	self.curYawR = nil
	self.renderPos = nil
	self.renderYaw = nil
	-- M4.1 重生输入保护:>0 期间转向/冲刺/刹车输入强制中立(Respawn_InputProtectSec)
	self.inputProtectT = 0
	-- M4 状态
	self.spline = nil        -- setSpline 注入(重生/坠落判定依赖)
	-- M4.1(ADR-27):烘焙锚点链=重生唯一正路;旧"检查点黄球 respawnCF"已删(分段门≠锚点,严禁纠缠)
	self.anchors = nil       -- setAnchors 注入(RespawnAnchors.load() 的排序表)
	self.spawnCF = nil       -- 发车位=隐式 0 号锚(首锚之前坠落回这里)
	self.respawnMode = "anchor"  -- 硬核="gate" 接口预留(V1 不实现,分段门重考归硬核模式)
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
	-- M4.1 物性声明制(ADR-28):地面探针(悬浮/姿态/着陆/crash 跟地)只认 Terrain+Rideable 白名单;
	-- 其余一切 BasePart=障碍,只走碰撞扫掠(self.rp 全体)。世界物性是声明的,不是涌现的。
	self.rpGround = RaycastParams.new()
	self.rpGround.FilterType = Enum.RaycastFilterType.Include
	self._rideableConns = {
		CollectionService:GetInstanceAddedSignal("Rideable"):Connect(function() self:_rebuildGroundFilter() end),
		CollectionService:GetInstanceRemovedSignal("Rideable"):Connect(function() self:_rebuildGroundFilter() end),
	}
	self:_rebuildGroundFilter()
	-- M4.1 碰撞定档一次性(ADR-28):接触上升沿分类,接触期内不重判(nil|"graze"|"bounce"|"hard")
	self.contactClass = nil
	self.root.Anchored = true
	return self
end

function BikeController:_rebuildGroundFilter()
	local list = { workspace.Terrain }
	for _, inst in ipairs(CollectionService:GetTagged("Rideable")) do
		if inst:IsA("BasePart") then
			list[#list + 1] = inst
		end
	end
	self.rpGround.FilterDescendantsInstances = list
end

function BikeController:setSteer(v) self.rawSteer = math.clamp(v, -1, 1) end
function BikeController:setSprint(b) self.sprint = b == true end
function BikeController:setForcedSprint(b) self.forcedSprint = b == true end  -- M8.1 最小点火尾段(ADR-13):松键后仍强制冲刺
function BikeController:setSprintAllowed(b) self.sprintAllowed = b ~= false end  -- M5 能量门
function BikeController:setBrake(b) self.brake = b == true end
function BikeController:setFlowBoost(b) self.flowBoost = b == true end  -- ADR-31:心流=冲刺倍率升档(唯一数值效果)
function BikeController:applySpeedMultiplier(m)  -- M7:一次性速度惩罚(斩击失误减速);不低于 0
	self.curSpeed = math.max(0, self.curSpeed * math.clamp(m, 0, 1))
end
function BikeController:setSpline(sp) self.spline = sp end
function BikeController:setWallField(f) self.wallField = f end  -- M6.5:注入授权墙段注册表(WallRideField)
function BikeController:setAnchors(list) self.anchors = list end  -- M4.1:烘焙锚点链(RespawnAnchors.load())
function BikeController:setSpawnCF(cf) self.spawnCF = cf end      -- M4.1:发车位=隐式 0 号锚
function BikeController:setRespawnMode(m) self.respawnMode = m end -- 硬核="gate" 接口预留(V1 恒 anchor)
function BikeController:isRespawning() return self.respawnT ~= nil end
-- 立即执行一次重生(绕过转场倒计时;测试/调试用)
function BikeController:respawnNow()
	self.respawnT = nil
	self:_doRespawn()
end

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
	local look = cf.LookVector
	self.yaw = math.atan2(-look.X, -look.Z)
	self.physPos = cf.Position
	self:_setRenderCF(cf, true)  -- M4.1:传送=渲染快照,绝不跨传送插值
	self.inputProtectT = 0       -- R/外部传送清输入保护(重生保护由 _doRespawn 单独设)
	self.smoothNormal = Vector3.yAxis
	self.wall = nil             -- M6.5:R/重生/传送强制退墙态(E4-5)
	self.curSpeed = self.curSpeed * (keepSpeedFrac or 0)
	self.grounded = true
	self.vy = 0
	self.vySurf = 0
	self.steer = 0
	self.rawSteer = 0
	self.brake = false
	self.forcedSprint = false   -- 重生/传送清空最小点火尾段(下一帧 EnergyState 重驱)
	self.brakeFrac = 1
	self.wallContact = false
	self._prevWall = false
	self.contactClass = nil   -- M4.1:传送=接触事件结束(定档一次性状态清零)
	self.visualRoll, self.rollVel = 0, 0
	self.visualPitch = 0
	self.suspY, self.suspVel = 0, 0
	self.prevGrounded = true
	self.lastLandVy = 0
	self.crashT = nil
	self.respawnT = nil   -- M4.1 修:R/传送打断硬撞转场,旧重生倒计时不得跨传送存活(R 全重置铁律)
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
		-- M5+M8.1:实际生效冲刺 =(玩家按住 或 最小点火强制尾段)且能量允许。
		-- A/V 消费者(相机 FOV/震动、引擎点火音、速度线)读此位=尾段内不掉档(ADR-13 防毁视听);
		-- 能量逻辑读 sprint(原始输入),不读此位,故无反馈环。
		sprinting = (self.sprint or self.forcedSprint) and self.sprintAllowed,
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
		-- M6.5 墙态(ADR-36):磁吸中 grounded=false 且 wallContact=false(墙态≠擦墙,经济中性)
		wallRiding = self.wall ~= nil,
		wallUp = self.wall and self.wall.n or nil,  -- 车体 up=墙外法线(相机 roll 目标)
		-- M4.1:重生输入保护窗口 + 碰撞定档结果(HUD/验收断言用)
		inputProtected = self.inputProtectT > 0,
		contactClass = self.contactClass,
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

-- M4.1:执行重生(ADR-27)——烘焙锚点按弧长回取(≤当前,永不前进)+ 恢复部分速度 + 输入保护
function BikeController:_doRespawn()
	local C = self.cfg.get
	local frac = C("Respawn", "SpeedRestore")
	local target = nil
	if self.spline and self.anchors and #self.anchors > 0 then
		local curT = select(1, self.spline:NearestPoint(self.physPos))
		local setback = C("Respawn", "SetbackAnchors") or 0
		-- 弧长≤当前的最近锚点,再回退 setback 个(内联 RespawnAnchors.pick 语义,避免模块循环依赖)
		local idx = nil
		for i = #self.anchors, 1, -1 do
			if self.anchors[i].t <= curT then idx = i break end
		end
		if idx then
			target = self.anchors[math.max(1, idx - setback)].cf
		else
			target = self.spawnCF   -- 首锚之前=回发车位(隐式 0 号锚;仍不前进)
		end
	end
	if target then
		self:teleport(target, frac)
	elseif self.spline then
		-- 兜底:未烘焙锚点的开发场景(正式赛道必须烘焙;运行时裸算=废案,此处仅 dev fallback)
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
	-- 0.5s 输入保护(§4.4:重生瞬间旧输入不再把车送回同一个坑;teleport 已清,故在其后设)
	self.inputProtectT = C("Respawn", "InputProtectSec") or 0
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
	-- M4.1 三线扫掠(ADR-28):中心+左右前角(±SideOffset)取最早命中;低位线保留(矮障碍)
	local dirLen = look * (stepLen + margin)
	local right = Vector3.new(-look.Z, 0, look.X)  -- 水平右向(look 恒水平)
	local side = C("Collision", "SideOffset")
	local hit = workspace:Raycast(pos, dirLen, self.rp)
	for _, origin in ipairs({
		pos - Vector3.new(0, hover * 0.6, 0),
		pos + right * side,
		pos - right * side,
	}) do
		local h = workspace:Raycast(origin, dirLen, self.rp)
		if h and (not hit or h.Distance < hit.Distance) then hit = h end
	end
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

-- M4.1 渲染位姿提交:物理步的最终 CFrame 进双缓冲并直写 root(无插值调用方=旧行为);
-- snap=true(teleport/重生)时 prev=cur,绝不跨传送插值。
function BikeController:_setRenderCF(cf, snap)
	if snap or not self.curRenderCF then
		self.prevRenderCF = cf
	else
		self.prevRenderCF = self.curRenderCF
	end
	self.curRenderCF = cf
	self.root.CFrame = cf
	self.prevPhysPos = snap and self.physPos or (self.curPhysPos or self.physPos)
	self.curPhysPos = self.physPos
	self.prevYawR = snap and self.yaw or (self.curYawR or self.yaw)
	self.curYawR = self.yaw
	if snap then
		self.renderPos, self.renderYaw = nil, nil
	end
end

-- M4.1(ADR-33):渲染插值——两个物理步位姿间按 alpha 混合写 root.CFrame;物理真相仍是 60Hz 定步长。
-- 同时产出 renderPos/renderYaw(yaw 走最短弧)供相机取插值锚。
function BikeController:renderInterpolate(alpha)
	if not (self.prevRenderCF and self.curRenderCF) then return end
	alpha = math.clamp(alpha, 0, 1)
	self.root.CFrame = self.prevRenderCF:Lerp(self.curRenderCF, alpha)
	local pp = self.prevPhysPos or self.physPos
	local cp = self.curPhysPos or self.physPos
	self.renderPos = pp:Lerp(cp, alpha)
	local py = self.prevYawR or self.yaw
	local cy = self.curYawR or self.yaw
	local dy = (cy - py + math.pi) % (2 * math.pi) - math.pi
	self.renderYaw = py + dy * alpha
end

-- 输入渐变(A/D 0.12s 渐入 / 0.20s 回正)——地面转向与墙上高度带共用(M6.5 抽取,数学逐位不变)
function BikeController:_steerRamp(dt)
	local C = self.cfg.get
	local rampIn = C("Steering", "InputRampInSec")
	local rampOut = C("Steering", "InputRampOutSec")
	local engaging = math.abs(self.rawSteer) > math.abs(self.steer)
		or (self.rawSteer ~= 0 and math.sign(self.rawSteer) ~= math.sign(self.steer))
	local ramp = engaging and rampIn or rampOut
	local maxDelta = dt / math.max(ramp, 1e-3)
	self.steer += math.clamp(self.rawSteer - self.steer, -maxDelta, maxDelta)
end

-- 速度渐变(冲刺/轻刹/心流/提降速)——地面与墙态共用("前进沿墙切向复用速度渐变",ADR-36)
-- M6.5 自 step 原样抽取,数学与求值顺序逐位不变;返回 sprintSpeed 供地面转向插值分母(锚 135)
function BikeController:_speedStep(dt)
	local C = self.cfg.get
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
	-- M8.1:实际冲刺 = (玩家按住 或 最小点火强制尾段)且 能量允许(ADR-13)。
	-- 按住冲刺时 forcedSprint 恒为 false(EnergyState 只在"松键但未烧满 0.4s"时置 true),故按住路径逐位不变。
	local sprintEff = (self.sprint or self.forcedSprint) and self.sprintAllowed
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
	return sprintSpeed
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
	self:_setRenderCF(baseCF
		* CFrame.new(0, self.suspY, 0)
		* CFrame.Angles(math.rad(self.visualPitch), 0, math.rad(self.visualRoll)))
end

-- ============================ M6.5 墙态(ADR-36/37,design §4.9) ============================

-- 进入墙态:快照当前位姿作混合起点;前进方向锁墙切向;磁吸自下一帧接管
function BikeController:_enterWall(hit)
	local C = self.cfg.get
	local look = Vector3.new(-math.sin(self.yaw), 0, -math.cos(self.yaw))
	local sn = self.smoothNormal
	local surfLook = look - sn * look:Dot(sn)
	surfLook = (surfLook.Magnitude > 1e-4) and surfLook.Unit or look
	local facePt = hit.seg.part.CFrame.Position + hit.n * hit.seg.halfT
	self.wall = {
		seg = hit.seg,
		n = hit.n,          -- 墙外法线(墙态内 down=−n,车体 up=n)
		along = hit.along,  -- 墙切向(已对齐入墙航向;直墙段内恒定)
		blendT = 0,         -- 已混合时长(位置=法向偏移线性收敛;姿态=Rotation lerp)
		offN0 = (self.physPos - facePt):Dot(hit.n) - C("Ground", "HoverHeight"),
		startCF = CFrame.lookAt(self.physPos, self.physPos + surfLook, sn),
		heightVel = 0,      -- 当前高度带速率(退出时交接为 vy)
	}
	-- 前进方向锁切向:yaw 即刻对齐(相机读 yaw 自然跟随)
	self.yaw = math.atan2(-hit.along.X, -hit.along.Z)
	self.grounded = false
	self.vy = 0
	self.vySurf = 0
	self.wallContact = false   -- 墙态≠擦墙:不发 graze、无泄速、无火花(经济中性,ADR-37)
	self._prevWall = false
end

-- 段内磁吸每帧:速度渐变复用 + A/D 高度带 + 折线行走跨段(ADR-43)+ 法向钉扎 + 三种退出(E4-2)
function BikeController:_wallStep(dt)
	local C = self.cfg.get
	local w = self.wall
	local part = w.seg.part
	if not part.Parent then
		-- 墙实例消失(编辑操作兜底):按段尾弹道交接
		self:_exitWall(w.heightVel)
		return
	end
	self:_steerRamp(dt)
	self:_speedStep(dt)   -- 冲刺/轻刹/心流/提降速与地面同一套("贴墙就是平地跑")

	-- 高度带:A/D 沿车体右轴滑移(along×n=±世界Y:右墙 D=升,左墙 A=升,与相机滚转后的屏幕方向一致);
	-- 下坠漂移(默认 0=关)恒向世界下,不受墙侧影响
	local bikeRightY = w.along:Cross(w.n).Y
	local hVel = (-self.steer) * C("WallRide", "HeightBandSpeed") * bikeRightY
		- C("WallRide", "FallDriftPerSec")
	w.heightVel = hVel

	-- 推进(ADR-43 曲墙圆角=离散直墙链"折线行走"):行程在面片内直走,到当前段 Z 边界即
	-- findContinuation 换段续吸(单关节转角 ≤ChainMaxTurnDeg,与直墙链同门禁),一帧可跨多关节
	-- (R=6 圆角×心流 146 极端 ~6 关节/帧)。直墙段内与链端和旧实现同轨:链端剩余行程沿当前
	-- 切向走完,帧末退出判定接管(其兜底 findContinuation 同时覆盖段间小缝隙的越缝链)。
	-- 法向磁吸帧末钉扎一次;混合期从入墙偏移线性收敛到悬浮高,混合中过关节则探针容差按偏移放宽。
	local blendSec = math.max(C("WallRide", "BlendSec"), 1e-3)
	local offN = 0
	if w.blendT < blendSec then
		w.blendT = math.min(w.blendT + dt, blendSec)
		offN = w.offN0 * (1 - w.blendT / blendSec)
	end
	local hover = C("Ground", "HoverHeight")
	local chainMinDot = math.cos(math.rad(C("WallRide", "ChainMaxTurnDeg")))
	local pos = self.physPos + Vector3.new(0, hVel * dt, 0)
	local remain = self.curSpeed * dt
	for _ = 1, 10 do -- 防御上限:超限=剩余直走,帧末退出判定兜底
		local cf = w.seg.part.CFrame
		local lp = cf:PointToObjectSpace(pos)
		local zSign = (w.along:Dot(cf.ZVector) >= 0) and 1 or -1 -- 行进方向在局部 +Z 轴上的符号(LookVector=−Z,勿用)
		local distToEnd = math.max(w.seg.halfL - zSign * lp.Z, 0)
		if remain <= distToEnd then
			pos += w.along * remain
			remain = 0
			break
		end
		pos += w.along * distToEnd
		remain -= distToEnd
		local nxt = (self.wallField and self.wallField.findContinuation) and
			self.wallField:findContinuation(pos + w.along * 0.05, w.n, w.along, {
				minDot = chainMinDot, hover = hover, tol = 2 + math.abs(offN),
			}) or nil
		if not nxt then
			break
		end
		w.seg, w.n, w.along = nxt.seg, nxt.n, nxt.along
		self.yaw = math.atan2(-nxt.along.X, -nxt.along.Z)
	end
	if remain > 0 then pos += w.along * remain end -- 链端/上限:沿当前切向走完(=旧整帧直走)
	part = w.seg.part -- 行走可能已换段:帧末钉扎与退出判定一律对当前段
	local facePt = part.CFrame.Position + w.n * w.seg.halfT
	pos += w.n * (hover + offN - (pos - facePt):Dot(w.n))
	self.physPos = pos

	-- 退出判定(墙局部坐标):|Z|>半长=段尾;Y>上缘=弹出(墙上高度=落差跳距);Y<下缘=回地。
	-- M8.5(ADR-41)段尾先找直墙链延续段(同面同向、覆盖当前位置)无缝续吸;链端才真·弹道交接。
	local lp = part.CFrame:PointToObjectSpace(pos)
	if math.abs(lp.Z) > w.seg.halfL or math.abs(lp.Y) > w.seg.halfH then
		local handed = false
		if math.abs(lp.Y) <= w.seg.halfH and self.wallField and self.wallField.findContinuation then
			local nxt = self.wallField:findContinuation(pos, w.n, w.along, {
				minDot = math.cos(math.rad(C("WallRide", "ChainMaxTurnDeg"))),
				hover = hover,
				tol = 2,
			})
			if nxt then
				w.seg, w.n, w.along = nxt.seg, nxt.n, nxt.along
				self.yaw = math.atan2(-nxt.along.X, -nxt.along.Z)
				-- 重新钉扎到新段悬浮面(相邻段夹角 ≤ChainMaxTurnDeg,一帧内吸收;视觉/相机 lerp 平滑)
				local facePt2 = nxt.seg.part.CFrame.Position + nxt.n * nxt.seg.halfT
				pos += nxt.n * (hover - (pos - facePt2):Dot(nxt.n))
				self.physPos = pos
				handed = true
			end
		end
		if not handed then
			self:_exitWall(hVel)
			return
		end
	end

	-- 姿态:目标=贴墙框架(up=墙法线);混合期从入墙姿态过渡;视觉弹簧照常(steer 滚转=爬升压弯感)
	local targetCF = CFrame.lookAt(pos, pos + w.along, w.n)
	local baseCF = targetCF
	if w.blendT < blendSec then
		baseCF = w.startCF.Rotation:Lerp(targetCF.Rotation, w.blendT / blendSec) + pos
	end
	self:_visualStep(dt, baseCF)
end

-- 退出墙态:统一弹道交接——段尾/上缘=带高度带速率飞出(高台弹射);下缘=低空立即被着陆逻辑捕获回地
function BikeController:_exitWall(vyOut)
	local w = self.wall
	self.wall = nil
	self.grounded = false
	self.vy = vyOut or 0
	self.vySurf = 0
	-- 姿态从墙法线起步,空中路径逐帧回正到世界 Y(AlignLerpSpeed 平滑,无跳变)
	if w then
		self.smoothNormal = w.n
	end
	-- yaw 已是切向;水平速度=curSpeed 沿切向,普通空中/着陆路径自此接管。
	-- 退出后横向分速为 0 → 进入探测的朝墙分速阈值挡住立即回吸(EnterTowardMinSpeed)。
end

function BikeController:step(dt)
	dt = math.min(dt, 1 / 20)
	local C = self.cfg.get

	-- M4:重生转场中——车冻结原地(故障艺术占位),输入忽略,倒计时结束执行重生
	if self.respawnT then
		-- 冻结帧渲染双缓冲坍缩到最新位姿(插值不再回放冻结前的运动)
		self.prevRenderCF = self.curRenderCF or self.prevRenderCF
		self.prevPhysPos = self.curPhysPos or self.prevPhysPos
		self.prevYawR = self.curYawR or self.prevYawR
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
		local gC = workspace:Raycast(np + Vector3.new(0, hover + 4, 0), Vector3.new(0, -(hover + 16), 0), self.rpGround) -- 白名单(ADR-28)
		local y = gC and (gC.Position.Y + hover) or self.physPos.Y
		self.physPos = Vector3.new(np.X, y, np.Z)
		self.crashSpin += C("Collision", "CrashSpinDegPerSec") * self.crashSpinDir * dt
		if self.crashT <= 0 then
			self.crashT = nil
			self:_doRespawn()
			return
		end
		-- 打转只写渲染位姿(相机读 yaw/physPos,不跟随旋转)
		self:_setRenderCF(CFrame.lookAt(self.physPos, self.physPos + look, Vector3.yAxis)
			* CFrame.Angles(0, math.rad(self.crashSpin), 0))
		return
	end
	if self.bounceCD > 0 then self.bounceCD = math.max(0, self.bounceCD - dt) end

	-- M4.1 重生输入保护(§4.4):窗口内转向回中、冲刺/刹车忽略;客户端每帧重设也会被本处覆写
	if self.inputProtectT > 0 then
		self.inputProtectT = math.max(0, self.inputProtectT - dt)
		self.rawSteer = 0
		self.sprint = false
		self.brake = false
	end

	-- M6.5 墙态分支(ADR-36):磁吸中走独立路径;地面/空中代码在墙态帧完全不执行(零改动铁律)
	if self.wall then
		self:_wallStep(dt)
		return
	end

	self:_steerRamp(dt)
	local sprintSpeed = self:_speedStep(dt)
	-- 擦墙泄速:只在 graze 档接触期生效(M4.1 定档一次性;弹开/硬撞各走自己的泄速,不叠加)
	if self.wallContact and self.contactClass == "graze" then
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

	-- 碰撞三档(阈值全在 Config)——M4.1 定档一次性(ADR-28):
	-- 接触上升沿按入射角分类一次,接触期内沿用该档,不逐帧重判(根治"同一石头忽弹忽减"的涌现分类)。
	if self.wallContact and self.lastHitAngle then
		if not self._prevWall then
			local ang = self.lastHitAngle
			if ang >= C("Collision", "HardMinAngleDeg") and self.curSpeed >= C("Collision", "HardMinSpeed") then
				self.contactClass = "hard"
			elseif ang >= C("Collision", "BounceMinAngleDeg") then
				self.contactClass = "bounce"
			else
				self.contactClass = "graze"
				-- 擦墙上升沿事件(纯惩罚零回能 ADR-23;滑行+持续火花由表现层读 wallContact/contactPoint)
				self:_fire("graze", { angle = ang, speed = self.curSpeed })
			end
		end
		if self.contactClass == "hard" then
			-- 撞死:滑行+打转→重生,本帧车停在墙前(moveVec 已被扫掠截断)
			self.physPos = hx
			self:_beginCrash()
			return
		elseif self.contactClass == "bounce" then
			-- 弹开(含低速陡角降级):反射方向+泄速+火花,继续行驶
			self.physPos = hx
			if self.bounceCD <= 0 then self:_doBounce() end
		end
	else
		self.contactClass = nil   -- 接触结束:下次接触=新事件,重新定档
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
		-- M4.1:高度/姿态探针只认白名单(ADR-28)——非可骑面物理上"不存在于地面语义"
		local function probe(p)
			return workspace:Raycast(Vector3.new(p.X, pos.Y + up, p.Z), Vector3.new(0, -down, 0), self.rpGround)
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
			local rayO = Vector3.new(hx.X, pos.Y + 0.5, hx.Z)
			local rayD = Vector3.new(0, -(drop + hover + 0.5), 0)
			-- 着陆=只认白名单(ADR-28);障碍顶面另走防穿分支(障碍不可骑,不产生着陆)
			local land = workspace:Raycast(rayO, rayD, self.rpGround)
			local obst = workspace:Raycast(rayO, rayD, self.rp)
			if obst and (not CollectionService:HasTag(obst.Instance, "Rideable")) and obst.Instance ~= workspace.Terrain
				and (not land or obst.Position.Y > land.Position.Y) then
				-- M4.1 防穿:下坠撞上非可骑面。陡角高速=硬撞转场(§4.4 三档);
				-- 轻触=钳在顶面悬浮高,vy 归零但不落地(不可骑),水平滑出边缘后继续弹道。
				-- 碰撞永不产生垂直速度:此处只吸收(vy→0),绝不向上。
				if obst.Position.Y + hover >= newY then
					local vel = Vector3.new(moveVec.X / math.max(dt, 1e-6), self.vy, moveVec.Z / math.max(dt, 1e-6))
					local speedTotal = vel.Magnitude
					local sinInc = speedTotal > 1e-4 and math.clamp(-vel.Unit:Dot(obst.Normal), 0, 1) or 0
					local incDeg = math.deg(math.asin(sinInc))
					self.lastContactPoint = obst.Position
					self.lastContactNormal = obst.Normal
					self.lastHitAngle = incDeg
					self.physPos = Vector3.new(hx.X, obst.Position.Y + hover, hx.Z)
					self.vy = 0
					self.vySurf = 0
					if incDeg >= C("Collision", "HardMinAngleDeg") and speedTotal >= C("Collision", "HardMinSpeed") then
						self:_beginRespawn("hardHit")   -- 重摔上障碍=硬撞(跳过滑行:障碍顶无可骑地)
						return
					end
					newPos = self.physPos
					newY = newPos.Y
				end
			elseif land and land.Position.Y + hover >= newY then
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

	-- M4.1 去穿透钳制(ADR-28"滑墙永不入墙/零墙内帧"):帧位移向量最后过一次全体扫掠,
	-- 命中非白名单障碍则钳回 SkinWidth 外;白名单地面(下坡贴地弧线)不钳。钳制不改写任何速度。
	do
		local delta = newPos - pos
		local len = delta.Magnitude
		if len > 1e-4 then
			local hit = workspace:Raycast(pos, delta, self.rp)
			if hit and hit.Instance ~= workspace.Terrain
				and not CollectionService:HasTag(hit.Instance, "Rideable") then
				newPos = pos + delta.Unit * math.max(0, hit.Distance - C("Collision", "SkinWidth"))
			end
		end
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

	-- M6.5 墙段进入探测(纯观察,本帧物理已按原路径走完;命中=下一帧起磁吸)。
	-- 无 wallField 或场上无授权墙时此块恒空转 → 直线/坡顶回归零变化。
	if self.wallField then
		local hit = self.wallField:findEntry(self.physPos, look, self.curSpeed, {
			window = C("WallRide", "EnterWindowStuds"),
			minSpeed = C("WallRide", "EnterMinSpeed"),
			maxAngleDeg = C("WallRide", "EnterMaxAngleDeg"),
			minToward = C("WallRide", "EnterTowardMinSpeed"),
		})
		if hit then
			self:_enterWall(hit)
		end
	end
end

function BikeController:destroy()
	for _, mtr in ipairs(self.forkMotors) do mtr.Transform = CFrame.identity end
	for _, conn in ipairs(self._rideableConns or {}) do conn:Disconnect() end
	self._rideableConns = nil
end

return BikeController