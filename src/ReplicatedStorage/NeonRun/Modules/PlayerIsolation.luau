-- NeonRun / PlayerIsolation —— 多人隔离(ADR-54 方案 A「平行单机化」;ADR-54a 存量角色竞态修)
-- 现状(2026-07-17 多人审计):gameplay 全客户端——车=本地克隆不复制,水晶/敌人/计时=本地状态,
--   多客户端天然互不干扰;唯一跨端泄漏源=【其他玩家的角色】(引擎默认全服复制):
--   ① 障碍扫掠只排除自车+自角色(BikeController.rp),而 Humanoid 每帧强制躯干 CanCollide=true(坑 34)
--      → 发车线幻影人墙、赛道幽灵障碍;② 相机 popper 被别人角色顶成伪第一人称;③ 观感=无车幽灵骑手。
-- 方案 A(人类拍板 2026-07-17):其他玩家角色一律【本地销毁】——物理/相机/视觉一次剔除。
--   客户端 Destroy 复制实例只在本地生效,不上行、不影响对方本人与其他客户端;
--   零碰 BikeController/CameraRig(运动学核心不动=回归面最小)。
--   幽灵可见化(位置上报+无碰撞幽灵车渲染)=方案 B,归 M12 随服务端权威一并做,届时整模块替换。
-- ADR-54a(同日,人类回报"几个人同时在起点,后进的人发车即青屏"):首版对【进服前已在场】的角色
--   只查一次 plr.Character 快照——初始复制期该引用可能未解析(=nil),而 CharacterAdded 只在服务端
--   装新角色时点火、不为"引用迟到"补发;ChildAdded 兜底对初始快照里已 parent 的角色也不触发(坑 38)
--   → 漏剔=发车线残留幻影角色(都焊在各自倒计时的车上=堆在起点),后进者绿灯即 hardHit。
--   修=三层防御:①事件层(PlayerAdded/CharacterAdded/ChildAdded)即时剔;②存量层:enable 时全扫
--   workspace 直子级,引用未解析用「Model 名=某玩家名+带 Humanoid」兜底判归属;③巡检层:Heartbeat
--   每 2s 低频复扫(Character 引用终会解析,漏网必被接住)。Destroy 失败(复制中父锁)0.2s 重试一次。
-- 单人零影响:无其他玩家=各层全部空转;Edit 期 LocalPlayer=nil 且玩家表空,enable 不炸。
local Players = game:GetService("Players")
local RunS = game:GetService("RunService")

local PlayerIsolation = {}

local function scrub(char)
	-- defer 一帧:避开"销毁复制中实例"的父锁竞态(角色部件/饰品可能仍在流入)
	task.defer(function()
		if not char.Parent then return end
		if not pcall(char.Destroy, char) then
			task.delay(0.2, function() -- 复制中被锁=静默失败,补一次;再失败交巡检层
				if char.Parent then pcall(char.Destroy, char) end
			end)
		end
	end)
end

-- 归属判定:引用路径(权威)→ 名字路径(坑 38 兜底:初始复制期 Character 引用未解析时,
-- 角色 Model 名=玩家名+带 Humanoid;加 Humanoid 校验防误删撞名场景件)
local function isForeignCharacter(inst)
	if not inst:IsA("Model") then return false end
	local byRef = Players:GetPlayerFromCharacter(inst)
	if byRef then return byRef ~= Players.LocalPlayer end
	local byName = Players:FindFirstChild(inst.Name)
	return byName ~= nil and byName ~= Players.LocalPlayer
		and inst:FindFirstChildOfClass("Humanoid") ~= nil
end

local function hookPlayer(plr)
	if plr == Players.LocalPlayer then return end
	plr.CharacterAdded:Connect(scrub) -- 重生换代持续剔;连接随 plr 离服由引擎回收
	if plr.Character then scrub(plr.Character) end
end

-- 返回连接表(仅测试/热替换用清理;正式客户端全程存活不需断开)
function PlayerIsolation.enable()
	local conns = {}
	-- ① 事件层
	conns[#conns + 1] = Players.PlayerAdded:Connect(hookPlayer)
	for _, plr in ipairs(Players:GetPlayers()) do
		hookPlayer(plr)
	end
	conns[#conns + 1] = workspace.ChildAdded:Connect(function(child)
		-- 兼管 Streaming 重流入与迟到的初始复制;归属判定含名字兜底
		if isForeignCharacter(child) then scrub(child) end
	end)
	-- ② 存量层(坑 38 主修):进服时已在场的角色,CharacterAdded 不会再来、引用可能未解析
	for _, child in ipairs(workspace:GetChildren()) do
		if isForeignCharacter(child) then scrub(child) end
	end
	-- ③ 巡检层:每 2s 复扫玩家表(引用终会解析);单人=空循环,开销可忽略
	local lastSweep = os.clock()
	conns[#conns + 1] = RunS.Heartbeat:Connect(function()
		if os.clock() - lastSweep < 2 then return end
		lastSweep = os.clock()
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= Players.LocalPlayer then
				local c = plr.Character
				if c and c.Parent then scrub(c) end
			end
		end
	end)
	return conns
end

return PlayerIsolation
