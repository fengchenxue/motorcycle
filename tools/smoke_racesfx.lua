--[[
NEON RUN — 流程与状态音效 RaceSFX 冒烟(ADR-50j;Edit 固定 dt=1/60)
断言组:
  ① 九槽位就位:Sound 实例齐 + assetId 正确 + 变调正确(GO 1.4/终点 0.75/心流 1.3/咔哒 0.8/敌火 0.6)
  ② 音量键=0:play 不触发(Playing=false,连 Play 都不调)
  ③ 音量键>0:play 触发 + 音量写入
  ④ playAt:克隆挂目标件并播放(Debris 4s 自灭,Edit 内断言克隆存在)
  ⑤ destroy:声源全清
  ⑥ 配置还原
纯实例断言(Edit 不出声,验 Playing/Volume 属性);钉扎自还原(坑 27/32);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local RaceSFX = require(nr.Modules.RaceSFX:Clone())

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end

local hInst = nr.Config.Handling
local PIN = {
	Sound_PickupVolume = 0, Sound_CountdownVolume = 0, Sound_FinishVolume = 0,
	Sound_PlayerHitVolume = 0, Sound_RespawnVolume = 0, Sound_FlowVolume = 0,
	Sound_EmptyClickVolume = 0, Sound_EnemyFireVolume = 0, Sound_GateVolume = 0,
}
local saved = {}
for k in pairs(PIN) do saved[k] = hInst:GetAttribute(k) end
for k, v in pairs(PIN) do hInst:SetAttribute(k, v) end

local TMP = "NeonRunRaceSfxSmoke_TMP"
for _, inst in ipairs(workspace:GetChildren()) do
	if inst.Name:sub(1, #TMP) == TMP then inst:Destroy() end
end
local root = Instance.new("Part")
root.Name = TMP .. "_Root"
root.Anchored = true; root.CanCollide = false; root.CanQuery = false
root.Position = Vector3.new(-4600, 620, -300)
root.Parent = workspace

local sfx = RaceSFX.new(root)

-- ① 九槽位就位(id+变调)
do
	local EXPECT = {
		pickup    = { id = "rbxassetid://9120162271", speed = 1 },
		countdown = { id = "rbxassetid://9125540237", speed = 1 },
		go        = { id = "rbxassetid://9125540237", speed = 1.4 },
		finish    = { id = "rbxassetid://9125540222", speed = 0.75 },
		playerHit = { id = "rbxassetid://9125672739", speed = 1 },
		respawn   = { id = "rbxassetid://9114444008", speed = 1 },
		flow      = { id = "rbxassetid://9125920594", speed = 1.3 },
		emptyBox  = { id = "rbxassetid://9120149295", speed = 0.8 },
		enemyFire = { id = "rbxasset://sounds/electronicpingshort.wav", speed = 0.6 },
	}
	local bad = {}
	local n = 0
	for name, e in pairs(EXPECT) do
		n += 1
		local s = sfx.sounds[name]
		if not s then
			bad[#bad + 1] = name .. "缺失"
		elseif s.SoundId ~= e.id then
			bad[#bad + 1] = name .. " id=" .. s.SoundId
		elseif math.abs(s.PlaybackSpeed - e.speed) > 1e-4 then
			bad[#bad + 1] = name .. " speed=" .. s.PlaybackSpeed
		end
	end
	ok("①a 九槽位 id+变调全对", #bad == 0, table.concat(bad, ";"))
	local cnt = 0
	for _, d in ipairs(root:GetChildren()) do
		if d:IsA("Sound") and d.Name:sub(1, 8) == "RaceSFX_" then cnt += 1 end
	end
	ok("①b 声源实例数=" .. n, cnt == n, cnt)
end

-- ② 音量 0=静(连 Play 都不调)
do
	sfx:play("pickup")
	ok("② 音量 0:Playing=false", sfx.sounds.pickup.Playing == false, tostring(sfx.sounds.pickup.Playing))
end

-- ③ 音量>0=播 + 音量写入
do
	hInst:SetAttribute("Sound_PickupVolume", 0.55)
	sfx:play("pickup")
	ok("③ 音量 0.55:Playing=true 且 Volume 写入", sfx.sounds.pickup.Playing == true
		and math.abs(sfx.sounds.pickup.Volume - 0.55) < 1e-4,
		tostring(sfx.sounds.pickup.Playing) .. "/" .. sfx.sounds.pickup.Volume)
	sfx.sounds.pickup:Stop()
	hInst:SetAttribute("Sound_PickupVolume", 0)
end

-- ④ playAt:克隆挂目标件
do
	local enemy = Instance.new("Part")
	enemy.Name = TMP .. "_Enemy"
	enemy.Anchored = true; enemy.CanCollide = false
	enemy.Position = root.Position + Vector3.new(0, 0, -60)
	enemy.Parent = workspace
	sfx:playAt("enemyFire", enemy)
	ok("④a 音量 0:不产克隆", enemy:FindFirstChildOfClass("Sound") == nil, "有克隆")
	hInst:SetAttribute("Sound_EnemyFireVolume", 0.4)
	sfx:playAt("enemyFire", enemy)
	local c = enemy:FindFirstChildOfClass("Sound")
	ok("④b 音量 0.4:克隆挂目标件并播放", c ~= nil and c.Playing == true and math.abs(c.Volume - 0.4) < 1e-4,
		c and (tostring(c.Playing) .. "/" .. c.Volume) or "无克隆")
	hInst:SetAttribute("Sound_EnemyFireVolume", 0)
	enemy:Destroy()
end

-- ⑤ destroy 全清
do
	sfx:destroy()
	local resid = 0
	for _, d in ipairs(root:GetChildren()) do
		if d:IsA("Sound") then resid += 1 end
	end
	ok("⑤ destroy:声源全清", resid == 0, resid .. " 件残留")
end

-- ⑥ 还原
root:Destroy()
for k in pairs(PIN) do hInst:SetAttribute(k, saved[k]) end
local restoreOK = true
for k in pairs(PIN) do
	if hInst:GetAttribute(k) ~= saved[k] then restoreOK = false end
end
ok("⑥ 配置还原回快照", restoreOK, "未还原")

print(string.format("[smoke_racesfx] %d/%d 通过", pass, pass + fail))
for _, line in ipairs(log) do print(line) end
if fail > 0 then warn(string.format("[smoke_racesfx] %d 项失败", fail)) end
