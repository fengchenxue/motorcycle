-- NeonRun / CameraRig (M3) —— 追逐相机
-- 位置弹簧滞后(FollowLagSec)/朝向低通慢半拍(YawLagSec)/冲刺 FOV 推进/冲刺震动/撞墙回退。
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
function CameraRig:_bikeLook()
	local yaw = self.ctrl.yaw
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

function CameraRig:setFlow(b) self.flow = b == true end  -- M5:EnergyState flowStart/flowEnd 调用

function CameraRig:snap()
	local C = self.cfg.get
	local look = self:_bikeLook()
	self.smoothLook = look
	local target = self.ctrl.physPos
	self.camPos = target - look * C("Camera", "Distance") + Vector3.new(0, C("Camera", "Height"), 0)
	if self.camera then
		self.camera.FieldOfView = C("Camera", "FOVBase")
	end
end

function CameraRig:update(dt)
	local C = self.cfg.get
	local ctrl = self.ctrl
	local target = ctrl.physPos
	self.t += dt

	-- 朝向慢半拍:朝向低通比位置更慢
	local look = self:_bikeLook()
	local yawAlpha = 1 - math.exp(-dt / math.max(C("Camera", "YawLagSec"), 1e-3))
	local sl = self.smoothLook:Lerp(look, yawAlpha)
	if sl.Magnitude < 1e-3 then sl = look else sl = sl.Unit end
	self.smoothLook = sl

	-- 位置弹簧滞后(心流档拉近至 FlowDistance)
	local dist = self.flow and C("Camera", "FlowDistance") or C("Camera", "Distance")
	local desired = target - sl * dist + Vector3.new(0, C("Camera", "Height"), 0)
	local posAlpha = 1 - math.exp(-dt / math.max(C("Camera", "FollowLagSec"), 1e-3))
	self.camPos = self.camPos:Lerp(desired, posAlpha)

	-- 撞墙回退:从看点向相机射线,命中则拉到墙内侧(验收项:任何情况不穿墙)
	local anchor = target + Vector3.new(0, 2, 0)
	local camPos = self.camPos
	local off = camPos - anchor
	local dist = off.Magnitude
	if dist > 1e-3 then
		local hit = workspace:Raycast(anchor, off, self.rp)
		if hit then
			camPos = hit.Position + hit.Normal * C("Camera", "WallSkin")
		end
	end

	-- 冲刺震动(平滑噪声,不打断跟随)
	local tele = ctrl:getTelemetry()
	if tele.sprinting and tele.grounded then  -- sprinting=有效冲刺(含最小点火尾段),松键不闪 FOV/震动(ADR-13)
		local a = C("Camera", "ShakeSprint")
		local f = C("Camera", "ShakeFreqHz")
		camPos += Vector3.new(
			math.noise(self.t * f, 0.7) * a,
			math.noise(3.1, self.t * f) * a,
			0)
	end

	-- 看向点:车前方(带前移与抬高)
	local lookAt = target + sl * C("Camera", "LookAhead") + Vector3.new(0, C("Camera", "LookUp"), 0)
	self.lastCamPos = camPos
	self.lastLookAt = lookAt

	if self.camera then
		self.camera.CameraType = Enum.CameraType.Scriptable
		self.camera.CFrame = CFrame.lookAt(camPos, lookAt)
		local targetFov = self.flow and C("Camera", "FlowFOV") or (tele.sprinting and C("Camera", "FOVSprint") or C("Camera", "FOVBase"))
		local fovAlpha = 1 - math.exp(-dt / math.max(C("Camera", "FOVLerpSec"), 1e-3))
		self.camera.FieldOfView += (targetFov - self.camera.FieldOfView) * fovAlpha
	end
end

function CameraRig:destroy() end

return CameraRig