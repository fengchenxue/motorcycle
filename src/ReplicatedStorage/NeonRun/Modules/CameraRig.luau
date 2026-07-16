-- NeonRun / CameraRig (M3 + M6.5 + ADR-44) —— 追逐相机
-- 位置弹簧滞后(FollowLagSec)/朝向低通慢半拍(YawLagSec)/冲刺 FOV 推进/冲刺震动/撞墙回退。
-- M6.5:up 向量参数化(E4-3)——墙态 up 平滑滚向墙法线(roll≤90°,WallRide_CamRollSec),FOV 不变;
--       地面 up 恒为世界 Y,数值逐位不变。
-- ADR-44 GR2 手感包:表现特性全走 Config 新键,默认值(0=关)下输出逐位=旧行为:
--   ①转弯相机侧倾 SteerRollGain(①b 低通 SteerRollLerpSec)②连续速度 FOV FOVSpeedGain ③点火 FOV 冲拳 FOVPunchDeg
--   ④落地相机下沉 LandDipPerVy(弹簧复用 Lean_Suspension*)⑤速度比例震动 ShakeSpeedGain ⑥下坠俯视 AirPitchDownDeg
--   ⑦横向独立插值 LatLagSec(人类首轮反馈 2026-07-15:GR2=横向移动插值平滑+倾斜十分克制)
-- 只读 ctrl 状态,不写任何物理。camera 可传任意 Camera 实例(便于 Edit 仿真验收)。
local RS = game:GetService("ReplicatedStorage")

local CameraRig = {}
CameraRig.__index = CameraRig

function CameraRig.new(camera, ctrl)
	local self = setmetatable({}, CameraRig)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	local inst = nr.Config.Handling
	self.cfg = ConfigLive.bind(inst, require(inst))
	self.camera = camera
	self.ctrl = ctrl
	self.flow = false  -- M5 心流档:由 EnergyState 事件通过 setFlow 切换(FOV→FlowFOV,距离→FlowDistance)
	self.rp = RaycastParams.new()
	self.rp.FilterType = Enum.RaycastFilterType.Exclude
	self.rp.FilterDescendantsInstances = { ctrl.model }
	self.t = 0
	self:snap()
	return self
end

-- 车体水平朝向(取物理 yaw,不含视觉 roll/pitch)
-- M4.1:优先读渲染插值 yaw(定步长下相机随插值位姿走);无插值调用方回退物理 yaw(Edit 工具零变化)
function CameraRig:_bikeLook()
	local yaw = self.ctrl.renderYaw or self.ctrl.yaw
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function CameraRig:setFlow(b) self.flow = b == true end  -- M5:EnergyState flowStart/flowEnd 调用

function CameraRig:snap()
	local C = self.cfg.get
	local look = self:_bikeLook()
	self.smoothLook = look
	self.upVec = Vector3.yAxis  -- M6.5:up 状态复位(重生/重开即刻回正)
	-- ADR-44 状态复位(默认键值下全程保持零,不改任何输出)
	self.fovPunchT = 0          -- ③点火冲拳剩余时长
	self.prevSprint = false     -- ③冲刺上升沿检测
	self.dipY, self.dipVel = 0, 0  -- ④落地下沉弹簧(相机系)
	self.airPitch = 0           -- ⑥下坠俯视当前角
	self.prevGroundedCam = true -- ④落地上升沿检测
	self.camRollSm = 0          -- ①b 侧倾低通状态(SteerRollLerpSec;人类首轮反馈:倾斜要克制)
	local target = self.ctrl.physPos
	self.camPos = target - look * C("Camera", "Distance") + Vector3.new(0, C("Camera", "Height"), 0)
	if self.camera then
		self.camera.FieldOfView = C("Camera", "FOVBase")
	end
end

function CameraRig:update(dt)
	local C = self.cfg.get
	local ctrl = self.ctrl
	local target = ctrl.renderPos or ctrl.physPos  -- M4.1:插值位姿优先(定步长渲染平滑)
	local tele = ctrl:getTelemetry()
	self.t += dt

	-- M6.5 up 参数化:墙态滚向墙法线,否则回世界 Y;nlerp 平滑(垂直墙恰 90°,永不越)。FOV 档位不变。
	local targetUp = (tele.wallRiding and tele.wallUp) and tele.wallUp or Vector3.yAxis
	local upAlpha = 1 - math.exp(-dt / math.max(C("WallRide", "CamRollSec"), 1e-3))
	local up = (self.upVec or Vector3.yAxis):Lerp(targetUp, upAlpha)
	if up.Magnitude < 1e-3 then
		up = (targetUp + Vector3.yAxis * 0.05).Unit -- 对向翻墙兜底(左右墙急换),经由竖直过渡
	else
		up = up.Unit
	end
	self.upVec = up

	-- 朝向慢半拍:朝向低通比位置更慢
	local look = self:_bikeLook()
	local yawAlpha = 1 - math.exp(-dt / math.max(C("Camera", "YawLagSec"), 1e-3))
	local sl = self.smoothLook:Lerp(look, yawAlpha)
	if sl.Magnitude < 1e-3 then sl = look else sl = sl.Unit end
	self.smoothLook = sl

	-- ADR-44①转弯相机侧倾:地面态把 up 绕视线轴滚 visualRoll×Gain(墙态不叠,墙有自己的 roll 语义)。
	-- rolledUp 只用于本帧取景;self.upVec 存未滚的 up,侧倾不跨帧累积。Gain=0 → rolledUp==up=旧行为。
	local rolledUp = up
	local rollGain = C("Camera", "SteerRollGain") or 0
	if rollGain ~= 0 and not tele.wallRiding then
		local maxDeg = C("Camera", "SteerRollMaxDeg") or 0
		local camRoll = math.clamp((tele.roll or 0) * rollGain, -maxDeg, maxDeg)
		-- ①b 侧倾低通(人类首轮反馈 2026-07-15:GR2 倾斜十分克制):>0=慢进慢出、吃掉车倾弹簧的过冲;0=直通
		local rollSec = C("Camera", "SteerRollLerpSec") or 0
		if rollSec > 0 then
			self.camRollSm += (camRoll - self.camRollSm) * (1 - math.exp(-dt / rollSec))
			camRoll = self.camRollSm
		else
			self.camRollSm = camRoll
		end
		if math.abs(camRoll) > 1e-4 then
			rolledUp = (CFrame.fromAxisAngle(sl, -math.rad(camRoll)) * up).Unit
		end
	else
		self.camRollSm = 0
	end

	-- 位置弹簧滞后(心流档拉近至 FlowDistance);高度偏移沿 up(地面=世界 Y,逐位不变)
	-- ⑦横向独立插值(人类首轮反馈 2026-07-15:GR2 左右移动有插值平滑):LatLagSec>0 时
	-- 水平横向分量单独低通(比 FollowLag 软)→ 转向/变线时车在画面里横移、镜头缓缓回中;
	-- 0=关=整体 lerp 旧行为逐位不变;墙态不拆(墙上"横向"≠屏幕横向,走旧路径)
	local dist = self.flow and C("Camera", "FlowDistance") or C("Camera", "Distance")
	local latDir = sl:Cross(Vector3.yAxis)
	local desired = target - sl * dist + rolledUp * C("Camera", "Height")
	-- ADR-44⑧ 转向横移方向(人类四轮之问"镜头平移同向还是反向"):
	-- 正=镜头向转弯方向领先(车偏画面外侧、看穿弯内);负=反向加强"车冲向弯内";0=关=纯滞后语义(现状)。
	-- 用渐变后 steer,再经 FollowLag/LatLag 二次平滑,无需新时间常数。
	local lead = C("Camera", "SteerLeadStuds") or 0
	if lead ~= 0 and not tele.wallRiding and latDir.Magnitude > 1e-4 then
		desired += latDir.Unit * (-(tele.steer or 0) * lead)
	end
	local posAlpha = 1 - math.exp(-dt / math.max(C("Camera", "FollowLagSec"), 1e-3))
	local latSec = C("Camera", "LatLagSec") or 0
	if latSec > 0 and not tele.wallRiding and latDir.Magnitude > 1e-4 then
		latDir = latDir.Unit
		local delta = desired - self.camPos
		local lat = delta:Dot(latDir)
		self.camPos += (delta - latDir * lat) * posAlpha
			+ latDir * (lat * (1 - math.exp(-dt / latSec)))
	else
		self.camPos = self.camPos:Lerp(desired, posAlpha)
	end

	-- 撞墙回退:从看点向相机射线,命中则拉到墙内侧(验收项:任何情况不穿墙)
	local anchor = target + rolledUp * 2
	local camPos = self.camPos
	local off = camPos - anchor
	local dist = off.Magnitude
	if dist > 1e-3 then
		local hit = workspace:Raycast(anchor, off, self.rp)
		if hit then
			camPos = hit.Position + hit.Normal * C("Camera", "WallSkin")
		end
	end

	-- 冲刺震动(平滑噪声,不打断跟随)+ ADR-44⑤速度比例震动(巡航微颤→心流最烈;Gain=0=纯开关式)
	local shakeAmp = 0
	if tele.grounded then  -- sprinting=有效冲刺(含最小点火尾段),松键不闪 FOV/震动(ADR-13)
		if tele.sprinting then shakeAmp += C("Camera", "ShakeSprint") end
		local sGain = C("Camera", "ShakeSpeedGain") or 0
		if sGain > 0 then
			shakeAmp += sGain * tele.speed / math.max(C("Speed", "Base"), 1e-3)
		end
	end
	if shakeAmp > 0 then
		local f = C("Camera", "ShakeFreqHz")
		camPos += Vector3.new(
			math.noise(self.t * f, 0.7) * shakeAmp,
			math.noise(3.1, self.t * f) * shakeAmp,
			0)
	end

	-- ADR-44④落地相机下沉:重落地镜头随 |落地vy| 下沉再弹回(与车体悬挂同一组弹簧参数,律动一致)
	local dipPerVy = C("Camera", "LandDipPerVy") or 0
	if dipPerVy > 0 and tele.grounded and not self.prevGroundedCam then
		local dip = math.min(math.abs(ctrl.lastLandVy or 0) * dipPerVy, C("Camera", "LandDipMax") or 0)
		if dip > 0 then
			self.dipY = -dip
			self.dipVel = 0
		end
	end
	self.prevGroundedCam = tele.grounded
	if self.dipY ~= 0 or self.dipVel ~= 0 then
		local sw = 2 * math.pi * math.max(C("Lean", "SuspensionFreqHz"), 0.1)
		local sz = C("Lean", "SuspensionDamping")
		self.dipVel += ((0 - self.dipY) * sw * sw - 2 * sz * sw * self.dipVel) * dt
		self.dipY += self.dipVel * dt
		if math.abs(self.dipY) < 1e-4 and math.abs(self.dipVel) < 1e-4 then
			self.dipY, self.dipVel = 0, 0
		end
		camPos += rolledUp * self.dipY
	end

	-- ADR-44⑥下坠俯视:滞空下落时看点沿 up 下移(找落点),落地/上升/墙态平滑回正。Deg=0=关。
	local apDeg = C("Camera", "AirPitchDownDeg") or 0
	local apTarget = (apDeg > 0 and not tele.grounded and not tele.wallRiding and (tele.vy or 0) < 0) and apDeg or 0
	local apAlpha = 1 - math.exp(-dt / math.max(C("Camera", "AirPitchLerpSec") or 0.25, 1e-3))
	self.airPitch += (apTarget - self.airPitch) * apAlpha

	-- 看向点:车前方(带前移与抬高,抬高沿 up)
	local lookAt = target + sl * C("Camera", "LookAhead") + rolledUp * C("Camera", "LookUp")
	if self.airPitch > 1e-3 then
		lookAt -= rolledUp * (math.tan(math.rad(self.airPitch)) * C("Camera", "LookAhead"))
	end
	self.lastCamPos = camPos
	self.lastLookAt = lookAt

	if self.camera then
		self.camera.CameraType = Enum.CameraType.Scriptable
		self.camera.CFrame = CFrame.lookAt(camPos, lookAt, rolledUp)
		local targetFov = self.flow and C("Camera", "FlowFOV") or (tele.sprinting and C("Camera", "FOVSprint") or C("Camera", "FOVBase"))
		-- ADR-44②连续速度 FOV:随实时速度在档位上加减(巡航=档位原值;Gain=0=关)
		local fovGain = C("Camera", "FOVSpeedGain") or 0
		if fovGain ~= 0 then
			targetFov += (tele.speed - C("Speed", "Base")) * fovGain
		end
		-- ADR-44③点火冲拳:冲刺上升沿 FOV 目标额外冲高 PunchDeg,PunchDecaySec 内线性回落
		local punchDeg = C("Camera", "FOVPunchDeg") or 0
		local punchSec = C("Camera", "FOVPunchDecaySec") or 0.35
		if punchDeg > 0 and punchSec > 0 then
			if tele.sprinting and not self.prevSprint then
				self.fovPunchT = punchSec
			end
			if self.fovPunchT > 0 then
				targetFov += punchDeg * (self.fovPunchT / punchSec)
				self.fovPunchT = math.max(0, self.fovPunchT - dt)
			end
		end
		self.prevSprint = tele.sprinting
		local fovAlpha = 1 - math.exp(-dt / math.max(C("Camera", "FOVLerpSec"), 1e-3))
		self.camera.FieldOfView += (targetFov - self.camera.FieldOfView) * fovAlpha
	end
end

function CameraRig:destroy() end

return CameraRig
