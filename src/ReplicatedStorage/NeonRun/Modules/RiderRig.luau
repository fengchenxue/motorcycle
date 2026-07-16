-- NeonRun / RiderRig (表现层) —— 玩家 avatar 骑车 + 程序化长剑 + 骑姿/挥砍动画(ADR-50b/50c)
-- 兑现 ADR-10"三人称=皮肤可见性":用玩家自己的 avatar 上车,不造假人。
-- 挂载=壳件同机制(ADR-3):HRP 焊到锚定 BikeRoot(WeldConstraint),Play 内随根刚体跟动;
--   全角色件 CanCollide/CanQuery/CanTouch=false+Massless——**CanQuery=false 是硬要求**:
--   否则贴身角色件会被 BikeController 的障碍扫掠/地面探针射中=幻影硬撞(饰品异步加载由 DescendantAdded 兜底)。
-- 挂载=step 内自愈轮询(0.5s):未挂→凑齐件即挂;焊断/角色换代→重挂——一次性事件时序(CharacterAdded
--   与脚本就绪的竞态、Humanoid 晚到)全部免疫(坑 26/33;2026-07-16 实测事件式在 Play 竞态漏挂,已改)。
-- 动画=程序化两层(ADR-50c,零动画资产):
--   · 静态骑姿=Motor6D C0 乘偏移(挂载时一次):左手前伸握车把/右臂自然下垂**拖剑**(刃尖朝后下)/前倾跨坐;
--   · 双骨架通道(坑 35):Animator 存在即每帧覆写 Transform(零动画轨也覆写)——程序化姿态/挥砍走
--     "位形通道":经典骨架(Motor6D)=写 C0;**新版骨架(AnimationConstraint,2026 平台迁移已实测上线)**
--     =写其 Part0 侧 RigAttachment.CFrame(动画系统不碰 attachment,语义=C0 等价物);
--   · 挥砍=位形通道逐帧(仅挥砍期写):起手上扬(肩+肘+腰)→横扫(时长=VFX_SlashSweepSec)
--     →持窗定格("刀在外面",窗=Combat_InputBufferSec,与剑光/判定同一事实源)→回位垂剑;
--   · 剑特效(ADR-50d/50e):锋刃呼吸辉光+刃光源(挥砍增亮)/心流=剑变金;
--     (刀光 Trail 与拖地火星已删=人类试玩裁决 2026-07-16:太粗挡视野/不要火星;挥砍可读性由 CombatVFX 前侧剑痕承担)。
-- VFX_RiderEnabled=0 时 TestDrive 走旧"停机坪"路径。
-- 只写渲染层(关节/焊接),物理零参与;姿态角=截图迭代版,观感微调改下方 POSE 表。
local RS = game:GetService("ReplicatedStorage")

local SADDLE = CFrame.new(0, 1.7, 1.15)            -- HRP 在 BikeRoot 局部系的鞍座位(实测 Seat 中心 z=+1.9,前倾骑姿取 1.15;朝 -Z 同向)
local ARC_COLOR = Color3.fromRGB(90, 220, 255)     -- 锋刃霓虹青(与剑光同族)
local FLOW_COLOR = Color3.fromRGB(255, 200, 80)    -- 心流金(与冲刺三件同语义,ADR-50a)
local BLADE_LEN = 4.6                              -- 长剑刃长(studs)

-- ── 骑姿(C0 = 原C0 × 偏移;观感微调改这里)──────────────────────────
-- 设计:左手前伸握把;右臂垂在体侧偏后,剑尖拖在车尾侧后方
-- (2026-07-16 Edit 预览台截图迭代定值:左手落把实测距 0.13(把位=BikeRoot 局部 (-0.5,1.7,-1.6));
--  剑尖拖在侧后下方(局部 (2.0,-2.1,+5.4),悬浮态离地 ~0.7=火花带)。改值后可用预览台复拍验证。)
-- (v5.1 定值 2026-07-16:亮色假人分步截图核对——面向车头/跨坐/左手落把 d=0.56/剑尖离地 0.4 后拖 6.5;
--  符号课:髋 +X=大腿前抬、膝 −X=小腿后折、腰 −X=前倾——首版髋膝取反曾致"像面朝后+手拧背后")
local POSE_R15 = {
	Waist = CFrame.Angles(math.rad(-24), 0, 0),
	Neck = CFrame.Angles(math.rad(18), 0, 0),
	LeftShoulder = CFrame.Angles(math.rad(94), math.rad(-35), math.rad(26)), -- 前伸+内收落把
	LeftElbow = CFrame.Angles(math.rad(14), 0, 0),
	RightShoulder = CFrame.Angles(math.rad(-18), 0, math.rad(4)),            -- 垂后拖剑
	RightElbow = CFrame.Angles(math.rad(8), 0, 0),
	RightHip = CFrame.Angles(math.rad(72), 0, math.rad(6)),
	LeftHip = CFrame.Angles(math.rad(72), 0, math.rad(-6)),
	RightKnee = CFrame.Angles(math.rad(-58), 0, 0),
	LeftKnee = CFrame.Angles(math.rad(-58), 0, 0),
}
local POSE_R6 = {
	Neck = CFrame.Angles(math.rad(-10), 0, 0),
	["Left Shoulder"] = CFrame.Angles(0, 0, math.rad(52)),                    -- 前伸够把(R6 轴系)
	["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(-14)),                  -- 垂后拖剑
	["Right Hip"] = CFrame.Angles(0, 0, math.rad(-70)),
	["Left Hip"] = CFrame.Angles(0, 0, math.rad(70)),
}
-- 长剑握持(SwordGrip Motor6D 的 C0):垂臂时刃尖指向后下=拖剑
local GRIP_TRAIL_R15 = CFrame.new(0, -0.12, 0) * CFrame.Angles(math.rad(148), math.rad(2), 0)
local GRIP_TRAIL_R6 = CFrame.new(0, -1.0, 0) * CFrame.Angles(math.rad(148), math.rad(2), 0)

-- ── 挥砍编排(Transform 通道;phase: windup→sweep→hold→return)────────
local SWING_WINDUP_SEC = 0.06
local SWING_RETURN_SEC = 0.25
-- 每关节 {windup, follow}(R6 缺的关节自动跳过)
local SWING_R15 = {
	RightShoulder = { CFrame.Angles(math.rad(150), math.rad(-25), math.rad(35)), CFrame.Angles(math.rad(80), math.rad(20), math.rad(-95)) },
	RightElbow = { CFrame.Angles(math.rad(65), 0, 0), CFrame.Angles(math.rad(8), 0, 0) },
	Waist = { CFrame.Angles(0, math.rad(14), 0), CFrame.Angles(0, math.rad(-18), 0) },
}
local SWING_R6 = {
	["Right Shoulder"] = { CFrame.Angles(0, math.rad(-30), math.rad(160)), CFrame.Angles(0, math.rad(35), math.rad(20)) },
}

local RiderRig = {}
RiderRig.__index = RiderRig
-- 导出姿态常量(tools/preview_rider_pose.lua 预览台读同一份=单一事实源;改姿态只改上方表)
RiderRig.SADDLE = SADDLE
RiderRig.POSE_R15 = POSE_R15
RiderRig.POSE_R6 = POSE_R6
RiderRig.GRIP_TRAIL_R15 = GRIP_TRAIL_R15
RiderRig.BLADE_LEN = BLADE_LEN

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

-- 程序化长剑:柄→护手→刃(亮银)+锋(霓虹);刃尖带拖地火花发射器
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
	-- 刃光源(挥砍增亮;刀光 Trail/拖地火星已删,ADR-50e 人类裁决)
	local light = Instance.new("PointLight")
	light.Name = "SwordLight"
	light.Color = ARC_COLOR
	light.Brightness = 1.5
	light.Range = 8
	light.Parent = blade
	m.PrimaryPart = grip
	return m, grip, { edge = edge, light = light }
end

function RiderRig.new(player, bikeModel, attack, ctrl)
	local self = setmetatable({}, RiderRig)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.root = bikeModel.PrimaryPart
	self.player = player
	self.ctrl = ctrl               -- 可选:拖剑火花读 grounded/speed
	self.mounted = nil             -- { char, weld, sword, gripMotor, spark, joints={[Motor6D]=原C0}, swing={name→joint}, conns={} }
	self.swingT = -1               -- <0=闲;>=0=挥砍进行时
	self.swingWindow = 0
	self._mountScanT = 0           -- 自愈轮询计时(0=下一步立即检查)
	if attack then
		attack:on("swing", function()
			self.swingT = 0
			self.swingWindow = self.cfg.get("Combat", "InputBufferSec")
		end)
	end
	return self
end

-- 自愈检查:未挂/焊断/角色换代 → (重)挂;件未凑齐(HRP/Humanoid 晚到)=本轮跳过,下轮再试
function RiderRig:_ensureMounted()
	if not self.player then return end
	local char = self.player.Character
	local m = self.mounted
	if m then
		local stale = m.char ~= char
			or not m.char.Parent
			or not m.weld or not m.weld.Parent
		if stale then self:unmount() else return end
	end
	if char and char.Parent then self:mount(char) end
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
	-- 非阻塞取件:未就绪即静默返回,由 step 自愈轮询重试(勿 WaitForChild——挂起会吞掉后续重试)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end
	print(string.format("[RiderRig] 上车:%s(%s)", char.Name, tostring(humanoid.RigType)))
	local m = { char = char, joints = {}, swing = {}, conns = {} }

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

	-- 骑姿:按 rig 类型乘偏移,存原值供还原;记挥砍关节表。
	-- 双骨架(坑 35):Motor6D=C0 通道;AnimationConstraint(新版)=Part0 侧 RigAttachment.CFrame 通道
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15
	local pose = isR15 and POSE_R15 or POSE_R6
	local swingSet = isR15 and SWING_R15 or SWING_R6
	local function jointHandle(d)
		if d:IsA("Motor6D") then
			return { set = function(cf) d.C0 = cf end, get = function() return d.C0 end, alive = function() return d.Parent ~= nil end }
		elseif d.ClassName == "AnimationConstraint" and d.Attachment0 then
			local att = d.Attachment0
			return { set = function(cf) att.CFrame = cf end, get = function() return att.CFrame end, alive = function() return att.Parent ~= nil end }
		end
		return nil
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") or d.ClassName == "AnimationConstraint" then
			local h = jointHandle(d)
			if h then
				local off = pose[d.Name]
				if off then
					m.joints[h] = h.get()
					h.set(m.joints[h] * off)
				end
				if swingSet[d.Name] then m.swing[d.Name] = h end
			end
		end
	end
	m.swingSet = swingSet

	-- 长剑入右手(垂臂拖剑握持)
	local hand = char:FindFirstChild(isR15 and "RightHand" or "Right Arm")
	if hand then
		local sword, grip, fx = buildSword()
		sword.Parent = char
		local motor = Instance.new("Motor6D")
		motor.Name = "SwordGrip"
		motor.Part0 = hand; motor.Part1 = grip
		motor.C0 = isR15 and GRIP_TRAIL_R15 or GRIP_TRAIL_R6
		motor.Parent = hand
		m.sword = sword
		m.gripMotor = motor
		m.edge = fx.edge
		m.swordLight = fx.light
		m.swordFlow = nil            -- 上次写入的心流态(nil=强制首写颜色)
	end

	-- 挥砍基准=骑姿态位形(坑 35:位形通道,基准即姿态定值)
	m.swingBase = {}
	for name, h in pairs(m.swing) do m.swingBase[name] = h.get() end

	self.mounted = m
end

function RiderRig:unmount()
	local m = self.mounted
	if not m then return end
	for _, c in ipairs(m.conns) do c:Disconnect() end
	for h, base in pairs(m.joints) do
		if h.alive() then h.set(base) end
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

-- 挥砍关节写入(位形通道):位形 = 骑姿基准 × lerp(from,to);0 号=identity(=回骑姿)
local function applySwing(m, fromIdx, toIdx, k)
	for name, h in pairs(m.swing) do
		if h.alive() then
			local pair = m.swingSet[name]
			local from = fromIdx == 0 and CFrame.identity or pair[fromIdx]
			local to = toIdx == 0 and CFrame.identity or pair[toIdx]
			h.set(m.swingBase[name] * from:Lerp(to, k))
		end
	end
end

-- 每帧:自愈挂载轮询(0.5s)+ 挥砍编排 + 拖剑火花
function RiderRig:step(dt)
	self._mountScanT -= dt
	if self._mountScanT <= 0 then
		self._mountScanT = 0.5
		self:_ensureMounted()
	end
	local m = self.mounted
	if not m then return end

	-- 剑层(ADR-50d/50e):锋刃呼吸/心流变金(刀光/火星已删=人类裁决)
	if m.sword then
		local swinging = self.swingT >= 0
		local tele = self.ctrl and self.ctrl.getTelemetry and self.ctrl:getTelemetry() or nil
		-- 心流=剑变金(锋/光源同步;仅变化帧写)
		local flow = tele and tele.flowBoost == true or false
		if flow ~= m.swordFlow then
			local col = flow and FLOW_COLOR or ARC_COLOR
			m.edge.Color = col
			m.swordLight.Color = col
			m.swordFlow = flow
		end
		-- 锋刃挥砍全亮否则呼吸;光源挥砍增亮
		if swinging then
			m.edge.Transparency = 0
			m.swordLight.Brightness = 4
		else
			m.edge.Transparency = 0.1 + 0.13 * (math.sin(self._breathT or 0) + 1) * 0.5
			m.swordLight.Brightness = 1.5
		end
		self._breathT = (self._breathT or 0) + dt * 4
	end

	if self.swingT < 0 then return end
	self.swingT += dt
	local sweep = math.max(self.cfg.get("VFX", "SlashSweepSec"), 1e-3)
	local t = self.swingT
	if t <= SWING_WINDUP_SEC then
		applySwing(m, 0, 1, t / SWING_WINDUP_SEC)                          -- 起手上扬
	elseif t <= SWING_WINDUP_SEC + sweep then
		applySwing(m, 1, 2, (t - SWING_WINDUP_SEC) / sweep)                -- 横扫
	elseif t <= self.swingWindow then
		applySwing(m, 2, 2, 1)                                             -- 持窗定格("刀在外面")
	elseif t <= self.swingWindow + SWING_RETURN_SEC then
		applySwing(m, 2, 0, (t - self.swingWindow) / SWING_RETURN_SEC)     -- 回位垂剑
	else
		applySwing(m, 0, 0, 1)                                             -- 归位收工
		self.swingT = -1
	end
end

function RiderRig:destroy()
	self:unmount()
end

return RiderRig
