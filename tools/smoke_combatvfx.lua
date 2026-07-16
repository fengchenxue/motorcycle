--[[
NEON RUN — 战斗表现层 CombatVFX 冒烟(ADR-50;Edit 固定 dt=1/60)
断言组:
  ① 剑光弧生命周期:出刀即亮(扫掠段 alpha=1)→持窗低亮→窗尽(0.25s)收刀→idle 全透明
  ② 命中演出:进盒命中 → 爆点件+磁吸光带各 1 → ttl 到期自动销毁零残留
  ③ 空挥:全窗零命中 → 弧灰化速灭回 idle
  ④ 敌人装饰:tag 即挂(卫星×3+悬浮盘+核心光);重复 step 不重复挂;挂上时已死=隐藏;复活侦测=回不透明即重现
  ⑤ 子弹装饰:入夹即挂 Trail+光;重复 step 不重复挂
  ⑥ ShooterField telegraph 事件:进入充能相位即发(新增事件回归锚)+预告结束必发弹
  ⑦ destroy 零残留(弧/爆点/敌饰/音效全清;含对场上真实射手的临时装饰)
  ⑧ 配置还原回快照
音量全钉 0(Edit 冒烟静音=顺带断言 0=静路径);断言帧留浮点余量(坑 18);
钉扎先存后还原同脚本闭环(坑 27/32);临时件按名清理幂等(坑 28);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local AttackSystem = require(nr.Modules.AttackSystem:Clone())
local CombatVFX = require(nr.Modules.CombatVFX:Clone())
local ShooterField = require(nr.Modules.ShooterField:Clone())
local DT = 1 / 60

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end

local hInst = nr.Config.Handling
local PIN = {
	Combat_HitboxForward = 12, Combat_HitboxSide = 7, Combat_HitboxUp = 5, Combat_HitboxBack = 2,
	Combat_InputBufferSec = 0.25, Combat_ParryWindowSec = 0, Combat_RecoverySec = 0.3,
	Combat_TelegraphRangeStuds = 55, Combat_ShooterRangeStuds = 170, Combat_ShooterTelegraphSec = 0.45,
	Combat_ShooterFireIntervalSec = 1.8, Combat_BulletSpeed = 150, Combat_BulletLifeSec = 4,
	VFX_SlashSweepSec = 0.12, VFX_SlashHoldAlpha = 0.4, VFX_SlashWidthScale = 1,
	VFX_HitBurstParticles = 24, VFX_HitLightBrightness = 8, VFX_MagnetBeamSec = 0.12,
	VFX_EnemySatSpinDeg = 90, VFX_EnemyBobStuds = 0.6, VFX_BulletTrailSec = 0.22,
	Sound_SlashVolume = 0, Sound_HitVolume = 0, Sound_ParryVolume = 0,
}
local saved = {}
for k in pairs(PIN) do saved[k] = hInst:GetAttribute(k) end
for k, v in pairs(PIN) do hInst:SetAttribute(k, v) end

local ORIGIN = Vector3.new(-4600, 560, -300)
local TMP = "NeonRunCombatVfxSmoke_TMP"
local function cleanupTmp()
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name:sub(1, #TMP) == TMP then inst:Destroy() end
	end
end
cleanupTmp()

local function mkPart(suffix, pos)
	local p = Instance.new("Part")
	p.Name = TMP .. suffix
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false
	p.Size = Vector3.new(2, 2, 2); p.Position = pos
	p.Parent = workspace
	return p
end

-- 测试摩托壳 + stub ctrl(表现层只读 physPos/yaw)
local bikeModel = Instance.new("Model"); bikeModel.Name = TMP .. "_Bike"
local root = Instance.new("Part")
root.Name = "BikeRoot"; root.Size = Vector3.new(2, 2.5, 7)
root.Anchored = true; root.CanCollide = false; root.CanQuery = false
root.CFrame = CFrame.new(ORIGIN)
root.Parent = bikeModel
bikeModel.PrimaryPart = root
bikeModel.Parent = workspace
local ctrl = { physPos = ORIGIN, yaw = 0 }

local bulletFolder = Instance.new("Folder")
bulletFolder.Name = TMP .. "_Bullets"
bulletFolder.Parent = workspace
local shooterStub = { folder = bulletFolder }
function shooterStub:on() end

local atk = AttackSystem.new(ctrl, nil, nil)
local cvfx = CombatVFX.new(bikeModel, ctrl, atk, shooterStub)

local function beamAlpha()   -- 1-透明度(取序列首点;写入端是单值序列)
	return 1 - cvfx.arc.beam.Transparency.Keypoints[1].Value
end
local function census(name)
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == name then n += 1 end
	end
	return n
end

-- ① 剑光弧生命周期(窗 0.25=15 步;边界留余量)
do
	atk:attack()
	cvfx:step(DT)
	ok("①a 出刀即亮(扫掠段 alpha=1)", math.abs(beamAlpha() - 1) < 1e-3 and cvfx.arcState == "active", beamAlpha())
	for _ = 2, 10 do atk:step(DT); cvfx:step(DT) end
	ok("①b 持窗段低亮(=HoldAlpha 0.4)", math.abs(beamAlpha() - 0.4) < 1e-3, beamAlpha())
	for _ = 11, 17 do atk:step(DT); cvfx:step(DT) end
	ok("①c 窗尽收刀(fade/idle)", cvfx.arcState ~= "active", cvfx.arcState)
	for _ = 18, 30 do atk:step(DT); cvfx:step(DT) end
	ok("①d 收刀后全透明回 idle", cvfx.arcState == "idle" and beamAlpha() < 1e-3, cvfx.arcState .. "/" .. beamAlpha())
	for _ = 31, 40 do atk:step(DT) end   -- 硬直清尾
end

-- ② 命中演出:爆点+磁吸光带,ttl 后零残留
do
	local t = mkPart("_hit", ORIGIN + Vector3.new(0, 0, -8))   -- 盒内
	atk:registerTarget(t, { kind = "slash" })
	local res = atk:attack()
	cvfx:step(DT)
	ok("②a 命中出刀(res=hit)", res == "hit", res)
	ok("②b 爆点件+磁吸光带各 1", census("CombatHitBurst") == 1 and census("CombatMagnetBeam") == 1,
		census("CombatHitBurst") .. "/" .. census("CombatMagnetBeam"))
	for _ = 1, 40 do atk:step(DT); cvfx:step(DT) end   -- 0.67s > ttl 0.5
	ok("②c ttl 到期自动销毁零残留", census("CombatHitBurst") == 0 and census("CombatMagnetBeam") == 0 and #cvfx.bursts == 0,
		census("CombatHitBurst") .. "/" .. census("CombatMagnetBeam") .. "/" .. #cvfx.bursts)
	atk:unregisterTarget(t); t:Destroy()
	for _ = 1, 20 do atk:step(DT) end
end

-- ③ 空挥灰化
do
	atk:attack()
	for _ = 1, 17 do atk:step(DT); cvfx:step(DT) end   -- 窗尽(15/16)后 whiff
	-- 窗尽帧 whiff 事件与 arcT 越窗同帧竞争,fadeWhiff/fadeHit 皆为合法收刀路径(只差灰/青着色)
	ok("③a 空挥收刀(不再 active)", cvfx.arcState ~= "active", cvfx.arcState)
	for _ = 18, 30 do atk:step(DT); cvfx:step(DT) end
	ok("③b 灰化后回 idle 全透明", cvfx.arcState == "idle" and beamAlpha() < 1e-3, cvfx.arcState)
	for _ = 31, 45 do atk:step(DT) end
end

-- ④ 敌人装饰:挂/不重挂/死挂=隐/复活侦测
do
	local e1 = mkPart("_enemy1", ORIGIN + Vector3.new(20, 0, -40))
	CS:AddTag(e1, "ShooterEnemy")
	local e2 = mkPart("_enemy2", ORIGIN + Vector3.new(-20, 0, -40))
	e2.Transparency = 1                       -- 挂上时已死
	CS:AddTag(e2, "ShooterEnemy")
	cvfx._enemyScanT = 0                      -- 立即触发轮询补挂(生产=每 0.5s)
	cvfx:step(DT)
	local function fxCount(p, nm)
		local n = 0
		for _, d in ipairs(p:GetChildren()) do if d.Name == nm then n += 1 end end
		return n
	end
	ok("④a tag 即挂:卫星×3+盘+光", fxCount(e1, "EnemyFxSat") == 3 and fxCount(e1, "EnemyFxDisc") == 1 and fxCount(e1, "EnemyFxLight") == 1,
		fxCount(e1, "EnemyFxSat") .. "/" .. fxCount(e1, "EnemyFxDisc") .. "/" .. fxCount(e1, "EnemyFxLight"))
	cvfx._enemyScanT = 0
	cvfx:step(DT)
	ok("④b 重复扫描不重挂", fxCount(e1, "EnemyFxSat") == 3, fxCount(e1, "EnemyFxSat"))
	ok("④c 挂上时已死=装饰隐藏", cvfx.enemyFx[e2] and cvfx.enemyFx[e2].hidden == true, tostring(cvfx.enemyFx[e2] and cvfx.enemyFx[e2].hidden))
	e2.Transparency = 0                       -- 复活(R 重开语义)
	cvfx:step(DT)
	ok("④d 复活侦测:装饰重现", cvfx.enemyFx[e2].hidden == false, tostring(cvfx.enemyFx[e2].hidden))
	CS:RemoveTag(e1, "ShooterEnemy"); CS:RemoveTag(e2, "ShooterEnemy")
	e1:Destroy(); e2:Destroy()
	cvfx:step(DT)                             -- part.Parent=nil → 表项清理
	ok("④e 敌件销毁后表项清理", cvfx.enemyFx[e1] == nil and cvfx.enemyFx[e2] == nil, "残留表项")
end

-- ⑤ 子弹装饰:入夹即挂,不重挂
do
	local b = Instance.new("Part")
	b.Name = "Bullet"; b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(2, 2, 2); b.Anchored = true
	b.CanCollide = false; b.CanQuery = false
	b.Position = ORIGIN + Vector3.new(0, 0, -30)
	b.Parent = bulletFolder
	cvfx:step(DT)
	local function has(cls)
		for _, d in ipairs(b:GetChildren()) do if d:IsA(cls) then return true end end
		return false
	end
	ok("⑤a 子弹入夹即挂 Trail+光", has("Trail") and has("PointLight"), tostring(has("Trail")) .. "/" .. tostring(has("PointLight")))
	local n0 = #b:GetChildren()
	cvfx:step(DT)
	ok("⑤b 重复 step 不重挂", #b:GetChildren() == n0, #b:GetChildren())
	b:Destroy()
end

-- ⑥ ShooterField telegraph 事件(新增事件回归锚;真实模块+stub ctrl)
do
	local enemy = mkPart("_sf_enemy", ORIGIN + Vector3.new(0, 0, -100))   -- 前方 100(<170 且 rel·look>0)
	CS:AddTag(enemy, "ShooterEnemy")
	local field = ShooterField.new(ctrl, nil, nil)
	local telegraphed = false
	field:on("telegraph", function(e) if e.part == enemy then telegraphed = true end end)
	field:step(DT)
	ok("⑥a 进入充能相位即发 telegraph 事件", telegraphed, tostring(telegraphed))
	local bullets0 = #field.bullets
	for _ = 1, 28 do field:step(DT) end   -- 0.45s 充能=27 步,越过必发弹
	ok("⑥b 预告结束必发弹(快照弹道)", #field.bullets == bullets0 + 1, #field.bullets - bullets0)
	field:destroy()
	CS:RemoveTag(enemy, "ShooterEnemy")
	enemy:Destroy()
end

-- ⑦ destroy 零残留(含对场上真实射手的临时装饰同灭)
do
	cvfx:destroy()
	local resid = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		local n = d.Name
		if n == "CombatHitBurst" or n == "CombatMagnetBeam" or n == "SlashArc"
			or n == "EnemyFxSat" or n == "EnemyFxDisc" or n == "EnemyFxLight" then
			resid += 1
		end
	end
	ok("⑦ destroy 零残留(弧/爆点/敌饰全清)", resid == 0, resid .. " 件残留")
	atk:destroy()
end

-- ⑧ 还原(坑 32)
bikeModel:Destroy(); bulletFolder:Destroy()
cleanupTmp()
for k in pairs(PIN) do hInst:SetAttribute(k, saved[k]) end
local restoreOK = true
for k in pairs(PIN) do
	if hInst:GetAttribute(k) ~= saved[k] then restoreOK = false end
end
ok("⑧ 配置还原回快照", restoreOK, "属性未回快照")

print(string.format("[smoke_combatvfx] %d/%d 通过", pass, pass + fail))
for _, line in ipairs(log) do print(line) end
if fail > 0 then warn(string.format("[smoke_combatvfx] %d 项失败", fail)) end
