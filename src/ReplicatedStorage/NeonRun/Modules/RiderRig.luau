-- NeonRun / RiderRig (表现层) —— 玩家 avatar 骑车 + 程序化长剑 + 出刀挥砍(ADR-50b)
-- 兑现 ADR-10"三人称=皮肤可见性":用玩家自己的 avatar 上车,不造假人。
-- 挂载=壳件同机制(ADR-3):HRP 焊到锚定 BikeRoot(WeldConstraint),Play 内随根刚体跟动;
--   全角色件 CanCollide/CanQuery/CanTouch=false+Massless——**CanQuery=false 是硬要求**:
--   否则贴身角色件会被 BikeController 的障碍扫掠/地面探针射中=幻影硬撞(饰品异步加载由 DescendantAdded 兜底)。
-- 姿态=Motor6D C0 乘偏移(前倾骑姿;R15 全套/R6 降级基本坐姿);Animate 脚本禁用+停既有动画轨。
-- 长剑=程序化(刃+霓虹锋+护手+柄,零资产),Motor6D 挂右手;出刀=肩+剑扫掠动画,
--   时窗同步 Combat_InputBufferSec(与剑光弧同一事实源:扫掠 SlashSweepSec→持窗→收刀回位)。
-- 复活/换角色=CharacterAdded 自动重挂;VFX_RiderEnabled=0 时 TestDrive 走旧"停机坪"路径。
-- 只写渲染层(关节 C0/焊接),物理零参与;姿态角=首版盲调,观感微调改下方 POSE 表。
local RS = game:GetService("ReplicatedStorage")

local SADDLE = CFrame.new(0, 1.7, 0.55)            -- HRP 在 BikeRoot 局部系的鞍座位(朝 -Z 同向)
local ARC_COLOR = Color3.fromRGB(90, 220, 255)     -- 锋刃霓虹青(与剑光同族)
local BLADE_LEN = 4.6                              -- 长剑刃长(studs)

-- 骑姿偏移表(C0 = 原C0 × 偏移;观感微调改这里)
local POSE_R15 = {
	Waist = CFrame.Angles(math.rad(-22), 0, 0),            -- 前倾
	Neck = CFrame.Angles(math.rad(18), 0, 0),              -- 抬头看路
	RightShoulder = CFrame.Angles(math.rad(50), math.rad(-8), 0),  -- 双臂前伸握把
	LeftShoulder = CFrame.Angles(math.rad(50), math.rad(8), 0),
	RightElbow = CFrame.Angles(math.rad(25), 0, 0),
	LeftElbow = CFrame.Angles(math.rad(25), 0, 0),
	RightHip = CFrame.Angles(math.rad(-72), 0, math.rad(6)),       -- 屈髋跨坐
	LeftHip = CFrame.Angles(math.rad(-72), 0, math.rad(-6)),
	RightKnee = CFrame.Angles(math.rad(58), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(58), 0, 0),
}
local POSE_R6 = {
	Neck = CFrame.Angles(math.rad(-12), 0, 0),
	["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(-45)),
	["Left Shoulder"] = CFrame.Angles(0, 0, math.rad(45)),
	["Right Hip"] = CFrame.Angles(0, 0, math.rad(-70)),
	["Left Hip"] = CFrame.Angles(0, 0, math.rad(70)),
}
-- 挥砍编排(右肩偏移;t=扫掠进度 0→1:从右上抡到左侧;之后持窗定格,窗尽回位)
local SWING_WINDUP = CFrame.Angles(math.rad(95), 0, math.rad(70))
local SWING_FOLLOW = CFrame.Angles(math.rad(55), 0, math.rad(-75))
local SWING_RETURN_SEC = 0.18

local RiderRig = {}
RiderRig.__index = RiderRig

local function mkSwordPart(name, size, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	return p
end

-- 程序化长剑:柄→护手→刃(暗色)+锋(霓虹);返回模型与柄件(Motor6D 挂点)
local function buildSword()
	local m = Instance.new("Model"); m.Name = "RiderSword"
	local grip = mkSwordPart("Grip", Vector3.new(0.28, 1.15, 0.28), Color3.fromRGB(35, 35, 45), Enum.Material.SmoothPlastic)
	grip.Parent = m
	local guard = mkSwordPart("Guard", Vector3.new(0.95, 0.14, 0.4), Color3.fromRGB(70, 75, 95), Enum.Material.Metal)
	guard.CFrame = grip.CFrame * CFrame.new(0, 0.64, 0)
	guard.Parent = m
	local blade = mkSwordPart("Blade", Vector3.new(0.24, BLADE_LEN, 0.14), Color3.fromRGB(200, 210, 230), Enum.Material.Metal)
	blade.CFrame = grip.CFrame * CFrame.new(0, 0.71 + BLADE_LEN / 2, 0)
	blade.Parent = m
	local edge = mkSwordPart("Edge", Vector3.new(0.08, BLADE_LEN, 0.2), ARC_COLOR, Enum.Material.Neon, 0.1)
	edge.CFrame = blade.CFrame * CFrame.new(0, 0, -0.04)
	edge.Parent = m
	for _, p in ipairs({ guard, blade, edge }) do
		local w = Instance.new("WeldConstraint")
		w.Part0 = grip; w.Part1 = p; w.Parent = grip
	end
	m.PrimaryPart = grip
	return m, grip
end

function RiderRig.new(player, bikeModel, attack)
	local self = setmetatable({}, RiderRig)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.root = bikeModel.PrimaryPart
	self.player = player
	self.mounted = nil          -- { char, weld, sword, gripMotor, joints={[Motor6D]=原C0}, conns={} }
	self.swingT = -1            -- <0=闲;>=0=挥砍进行时
	self.swingWindow = 0
	self._charConn = nil
	if attack then
		attack:on("swing", function()
			self.swingT = 0
			self.swingWindow = self.cfg.get("Combat", "InputBufferSec")
		end)
	end
	if player then
		if player.Character then self:mount(player.Character) end
		self._charConn = player.CharacterAdded:Connect(function(char)
			task.defer(function() self:mount(char) end)   -- 等 HRP/关节就位
		end)
	end
	return self
end

-- 全件物性矫正(CanQuery=false 防障碍扫掠误撞;饰品异步到货由 DescendantAdded 兜底)
local function neutralize(char, conns)
	local function fix(d)
		if d:IsA("BasePart") then
			d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			d.Massless = true
		end
	end
	for _, d in ipairs(char:GetDescendants()) do fix(d) end
	table.insert(conns, char.DescendantAdded:Connect(fix))
end

function RiderRig:mount(char)
	if self.mounted and self.mounted.char == char then return end
	self:unmount()
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end
	local m = { char = char, joints = {}, conns = {} }

	humanoid.PlatformStand = true                       -- 禁 Humanoid 状态机接管(非载具控制,ADR-1 无涉)
	humanoid.AutoRotate = false
	local animate = char:FindFirstChild("Animate")
	if animate then animate.Disabled = true end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do tr:Stop(0) end
	end
	neutralize(char, m.conns)

	-- 上鞍:先摆位再焊(壳件同机制,Play 内物理随锚定根刚体跟动)
	hrp.Anchored = false
	hrp.CFrame = self.root.CFrame * SADDLE
	local weld = Instance.new("WeldConstraint")
	weld.Name = "RiderSaddleWeld"
	weld.Part0 = self.root; weld.Part1 = hrp
	weld.Parent = hrp
	m.weld = weld

	-- 骑姿:按 rig 类型乘偏移,存原值供还原
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local pose = isR15 and POSE_R15 or POSE_R6
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") then
			local off = pose[d.Name]
			if off then
				m.joints[d] = d.C0
				d.C0 = d.C0 * off
			end
			if d.Name == (isR15 and "RightShoulder" or "Right Shoulder") then
				m.swingJoint = d
				m.swingIdleC0 = d.C0                    -- 骑姿态右肩(挥完回这里)
			end
		end
	end

	-- 长剑入右手
	local hand = char:FindFirstChild(isR15 and "RightHand" or "Right Arm")
	if hand then
		local sword, grip = buildSword()
		sword.Parent = char
		local motor = Instance.new("Motor6D")
		motor.Name = "SwordGrip"
		motor.Part0 = hand; motor.Part1 = grip
		-- 握持:刃沿手前方偏外,骑行时斜指前上(观感微调改这串)
		motor.C0 = CFrame.new(0, isR15 and -0.15 or -1.0, 0) * CFrame.Angles(math.rad(-105), 0, math.rad(12))
		motor.Parent = hand
		m.sword = sword
		m.gripMotor = motor
	end

	self.mounted = m
end

function RiderRig:unmount()
	local m = self.mounted
	if not m then return end
	for _, c in ipairs(m.conns) do c:Disconnect() end
	for joint, c0 in pairs(m.joints) do
		if joint.Parent then joint.C0 = c0 end
	end
	if m.gripMotor then m.gripMotor:Destroy() end
	if m.sword then m.sword:Destroy() end
	if m.weld then m.weld:Destroy() end
	if m.char.Parent then
		local humanoid = m.char:FindFirstChildOfClass("Humanoid")
		if humanoid then humanoid.PlatformStand = false; humanoid.AutoRotate = true end
		local animate = m.char:FindFirstChild("Animate")
		if animate then animate.Disabled = false end
	end
	self.mounted = nil
	self.swingT = -1
end

-- 每帧:挥砍编排(闲时零写;扫掠→持窗定格→窗尽回位)
function RiderRig:step(dt)
	local m = self.mounted
	if not m or not m.swingJoint or not m.swingJoint.Parent then return end
	if self.swingT < 0 then return end
	self.swingT += dt
	local sweep = math.max(self.cfg.get("VFX", "SlashSweepSec"), 1e-3)
	local idle = m.swingIdleC0
	if self.swingT <= sweep then
		local k = self.swingT / sweep                          -- 抡:右上→左侧
		m.swingJoint.C0 = idle * SWING_WINDUP:Lerp(SWING_FOLLOW, k)
	elseif self.swingT <= self.swingWindow then
		m.swingJoint.C0 = idle * SWING_FOLLOW                  -- 持窗定格("刀留在外面")
	elseif self.swingT <= self.swingWindow + SWING_RETURN_SEC then
		local k = (self.swingT - self.swingWindow) / SWING_RETURN_SEC
		m.swingJoint.C0 = idle * SWING_FOLLOW:Lerp(CFrame.identity, k)
	else
		m.swingJoint.C0 = idle                                 -- 归位收工
		self.swingT = -1
	end
end

function RiderRig:destroy()
	if self._charConn then self._charConn:Disconnect(); self._charConn = nil end
	self:unmount()
end

return RiderRig
