--[[
NEON RUN — 战斗/拾取/冲刺表现层冒烟(ADR-50/50a;Edit 固定 dt=1/60)
断言组:
  ① 剑光弧生命周期:出刀即亮(扫掠段 alpha=1)→持窗低亮→窗尽(0.25s)收刀→idle 全透明
  ② 命中演出:进盒命中 → 爆点件+磁吸光带各 1 → ttl 到期自动销毁零残留
  ③ 空挥:全窗零命中 → 弧收刀灰化回 idle
  ④ 敌人装饰:tag 即挂(卫星×3+盘+光);不重挂;挂时已死=隐;复活侦测重现;销毁清表
  ⑤ 子弹装饰:入夹即挂 Trail+光;不重挂
  ⑥ 水晶装饰(ADR-50a):挂碎晶×2+光;隐没沿=拾取爆点+装饰隐;复现重亮
  ⑦ 能量核装饰:挂卫星×4;隐没沿不重爆(核之死由 hit 爆点覆盖);隐现同步
  ⑧ 冲刺二件(BikeVFX,ADR-50e 底光已删):尾焰 Rate/尾迹开关随 sprinting;心流=×1.4+变金
  ⑨ ShooterField telegraph 事件:充能相位即发+预告结束必发弹
  ⑩ destroy 零残留(弧/爆点/敌饰/物饰/冲刺件全清)
  ⑪ 配置还原回快照
音量全钉 0(Edit 静音=顺带断言 0=静);断言帧留浮点余量(坑 18);
钉扎先存后还原同脚本闭环(坑 27/32);临时件按名清理幂等(坑 28);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local nr = RS:WaitForChild("NeonRun")
local AttackSystem = require(nr.Modules.AttackSystem:Clone())
local CombatVFX = require(nr.Modules.CombatVFX:Clone())
local ShooterField = require(nr.Modules.ShooterField:Clone())
local BikeVFX = require(nr.Modules.BikeVFX:Clone())
local DT = 1 / 60

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end
local function nearColor(c1, c2)
	return near(c1.R, c2.R, 1e-3) and near(c1.G, c2.G, 1e-3) and near(c1.B, c2.B, 1e-3)
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
	VFX_CrystalSpinDeg = 160, VFX_CoreSpinDeg = 60, VFX_ItemBobStuds = 0.35,
	VFX_SprintJetRate = 90, VFX_SprintWakeSec = 0.3,
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

local function beamAlpha()
	return 1 - cvfx.arc.beam.Transparency.Keypoints[1].Value
end
local function census(name)
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.Name == name then n += 1 end
	end
	return n
end
local function fxCount(p, nm)
	local n = 0
	for _, d in ipairs(p:GetChildren()) do if d.Name == nm then n += 1 end end
	return n
end

-- ① 剑光弧生命周期
do
	atk:attack()
	cvfx:step(DT)
	ok("①a 出刀即亮(扫掠段 alpha=1)", math.abs(beamAlpha() - 1) < 1e-3 and cvfx.arcState == "active", beamAlpha())
	for _ = 2, 10 do atk:step(DT); cvfx:step(DT) end
	ok("①b 持窗段低亮(=HoldAlpha 0.4)", math.abs(beamAlpha() - 0.4) < 1e-3, beamAlpha())
	for _ = 11, 17 do atk:step(DT); cvfx:step(DT) end
	ok("①c 窗尽收刀(fade/idle)", cvfx.arcState ~= "active", cvfx.arcState)
	for _ = 18, 30 do atk:step(DT); cvfx:step(DT) end
	ok("①d 收刀后全透明回 idle", cvfx.arcState == "idle" and beamAlpha() < 1e-3, cvfx.arcState .. "/" .. tostring(beamAlpha()))
	for _ = 31, 40 do atk:step(DT) end
end

-- ② 命中演出
do
	local t = mkPart("_hit", ORIGIN + Vector3.new(0, 0, -8))
	atk:registerTarget(t, { kind = "slash" })
	local res = atk:attack()
	cvfx:step(DT)
	ok("②a 命中出刀(res=hit)", res == "hit", res)
	ok("②b 爆点件+磁吸光带各 1", census("CombatHitBurst") == 1 and census("CombatMagnetBeam") == 1,
		census("CombatHitBurst") .. "/" .. census("CombatMagnetBeam"))
	for _ = 1, 40 do atk:step(DT); cvfx:step(DT) end
	ok("②c ttl 到期自动销毁零残留", census("CombatHitBurst") == 0 and census("CombatMagnetBeam") == 0 and #cvfx.bursts == 0,
		census("CombatHitBurst") .. "/" .. census("CombatMagnetBeam") .. "/" .. #cvfx.bursts)
	atk:unregisterTarget(t); t:Destroy()
	for _ = 1, 20 do atk:step(DT) end
end

-- ③ 空挥
do
	atk:attack()
	for _ = 1, 17 do atk:step(DT); cvfx:step(DT) end
	ok("③a 空挥收刀(不再 active)", cvfx.arcState ~= "active", cvfx.arcState)
	for _ = 18, 30 do atk:step(DT); cvfx:step(DT) end
	ok("③b 灰化后回 idle 全透明", cvfx.arcState == "idle" and beamAlpha() < 1e-3, cvfx.arcState)
	for _ = 31, 45 do atk:step(DT) end
end

-- ④ 敌人装饰
do
	local e1 = mkPart("_enemy1", ORIGIN + Vector3.new(20, 0, -40))
	CS:AddTag(e1, "ShooterEnemy")
	local e2 = mkPart("_enemy2", ORIGIN + Vector3.new(-20, 0, -40))
	e2.Transparency = 1
	CS:AddTag(e2, "ShooterEnemy")
	cvfx._enemyScanT = 0
	cvfx:step(DT)
	ok("④a tag 即挂:卫星×3+盘+光", fxCount(e1, "EnemyFxSat") == 3 and fxCount(e1, "EnemyFxDisc") == 1 and fxCount(e1, "EnemyFxLight") == 1,
		fxCount(e1, "EnemyFxSat") .. "/" .. fxCount(e1, "EnemyFxDisc") .. "/" .. fxCount(e1, "EnemyFxLight"))
	cvfx._enemyScanT = 0
	cvfx:step(DT)
	ok("④b 重复扫描不重挂", fxCount(e1, "EnemyFxSat") == 3, fxCount(e1, "EnemyFxSat"))
	ok("④c 挂上时已死=装饰隐藏", cvfx.enemyFx[e2] and cvfx.enemyFx[e2].hidden == true, tostring(cvfx.enemyFx[e2] and cvfx.enemyFx[e2].hidden))
	e2.Transparency = 0
	cvfx:step(DT)
	ok("④d 复活侦测:装饰重现", cvfx.enemyFx[e2].hidden == false, tostring(cvfx.enemyFx[e2].hidden))
	CS:RemoveTag(e1, "ShooterEnemy"); CS:RemoveTag(e2, "ShooterEnemy")
	e1:Destroy(); e2:Destroy()
	cvfx:step(DT)
	ok("④e 敌件销毁后表项清理", cvfx.enemyFx[e1] == nil and cvfx.enemyFx[e2] == nil, "残留表项")
end

-- ⑤ 子弹装饰
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

-- ⑥ 水晶装饰(ADR-50a):拾取沿爆点
do
	local c = mkPart("_crys", ORIGIN + Vector3.new(30, 0, -60))
	c.Color = Color3.fromRGB(0, 200, 255)
	CS:AddTag(c, "EnergyCrystal")
	cvfx._enemyScanT = 0
	cvfx:step(DT)
	ok("⑥a tag 即挂:碎晶×2+光", fxCount(c, "ItemFxShard") == 2 and fxCount(c, "ItemFxLight") == 1,
		fxCount(c, "ItemFxShard") .. "/" .. fxCount(c, "ItemFxLight"))
	c.Transparency = 1                       -- 模拟 CrystalField 捕获后隐藏
	cvfx:step(DT)
	ok("⑥b 隐没沿=拾取爆点+装饰隐", census("CombatHitBurst") == 1 and cvfx.itemFx[c].hidden == true,
		census("CombatHitBurst") .. "/" .. tostring(cvfx.itemFx[c].hidden))
	c.Transparency = 0                       -- 6s 冷却结束复现
	cvfx:step(DT)
	ok("⑥c 复现重亮(装饰+光)", cvfx.itemFx[c].hidden == false and cvfx.itemFx[c].light.Enabled == true,
		tostring(cvfx.itemFx[c].hidden))
	for _ = 1, 40 do cvfx:step(DT) end       -- 爆点自清
	CS:RemoveTag(c, "EnergyCrystal"); c:Destroy()
	cvfx:step(DT)
	ok("⑥d 水晶销毁后表项清理", cvfx.itemFx[c] == nil, "残留表项")
end

-- ⑦ 能量核装饰:隐没沿不重爆
do
	local k = mkPart("_core", ORIGIN + Vector3.new(-30, 0, -60))
	k.Color = Color3.fromRGB(180, 0, 255)
	CS:AddTag(k, "EnergyCore")
	cvfx._enemyScanT = 0
	cvfx:step(DT)
	ok("⑦a tag 即挂:卫星×4+光", fxCount(k, "ItemFxShard") == 4 and fxCount(k, "ItemFxLight") == 1,
		fxCount(k, "ItemFxShard") .. "/" .. fxCount(k, "ItemFxLight"))
	local bursts0 = census("CombatHitBurst")
	k.Transparency = 1                       -- 模拟被斩(defaultKill;hit 爆点走②路径,此处不该重爆)
	cvfx:step(DT)
	ok("⑦b 隐没沿不重爆(核之死由 hit 爆点覆盖)", census("CombatHitBurst") == bursts0 and cvfx.itemFx[k].hidden == true,
		census("CombatHitBurst") - bursts0)
	k.Transparency = 0                       -- R 重开复活
	cvfx:step(DT)
	ok("⑦c 复活重现", cvfx.itemFx[k].hidden == false, tostring(cvfx.itemFx[k].hidden))
	CS:RemoveTag(k, "EnergyCore"); k:Destroy()
	cvfx:step(DT)
end

-- ⑧ 冲刺三件(BikeVFX,ADR-50a)
do
	local bm2 = Instance.new("Model"); bm2.Name = TMP .. "_Bike2"
	local r2 = Instance.new("Part")
	r2.Name = "BikeRoot"; r2.Size = Vector3.new(2, 2.5, 7)
	r2.Anchored = true; r2.CanCollide = false; r2.CanQuery = false
	r2.CFrame = CFrame.new(ORIGIN + Vector3.new(0, 20, 0))
	r2.Parent = bm2; bm2.PrimaryPart = r2; bm2.Parent = workspace
	local tel = { sprinting = false, flowBoost = false, wallContact = false, crashing = false, speed = 100 }
	local ctrl2 = {}
	function ctrl2:on() end
	function ctrl2:getTelemetry() return tel end
	local bvfx = BikeVFX.new(bm2, ctrl2)
	bvfx:step(DT)
	ok("⑧a 非冲刺:尾焰 Rate=0+尾迹关(底光已删,ADR-50e)", bvfx.jet.Rate == 0 and bvfx.wake.Enabled == false
		and bvfx.underglow == nil,
		bvfx.jet.Rate .. "/" .. tostring(bvfx.wake.Enabled))
	tel.sprinting = true
	bvfx:step(DT)
	ok("⑧b 冲刺:尾焰 Rate=90+尾迹开", near(bvfx.jet.Rate, 90, 0.01) and bvfx.wake.Enabled == true,
		bvfx.jet.Rate .. "/" .. tostring(bvfx.wake.Enabled))
	local cyan = Color3.fromRGB(0, 220, 255)
	ok("⑧c 冲刺色=霓虹青", nearColor(bvfx.jet.Color.Keypoints[1].Value, cyan), tostring(bvfx.jet.Color.Keypoints[1].Value))
	tel.flowBoost = true
	bvfx:step(DT)
	local gold = Color3.fromRGB(255, 200, 80)
	ok("⑧d 心流:尾焰 ×1.4+变金(尾迹同步)", near(bvfx.jet.Rate, 90 * 1.4, 0.01)
		and nearColor(bvfx.jet.Color.Keypoints[1].Value, gold) and nearColor(bvfx.wake.Color.Keypoints[1].Value, gold),
		bvfx.jet.Rate .. "/" .. tostring(bvfx.jet.Color.Keypoints[1].Value))
	bvfx:destroy()
	ok("⑧e BikeVFX destroy 后冲刺件清空", fxCount(r2, "SprintWake") == 0, "有残留")
	bm2:Destroy()
end

-- ⑨ ShooterField telegraph 事件
do
	local enemy = mkPart("_sf_enemy", ORIGIN + Vector3.new(0, 0, -100))
	CS:AddTag(enemy, "ShooterEnemy")
	local field = ShooterField.new(ctrl, nil, nil)
	local telegraphed = false
	field:on("telegraph", function(e) if e.part == enemy then telegraphed = true end end)
	field:step(DT)
	ok("⑨a 进入充能相位即发 telegraph 事件", telegraphed, tostring(telegraphed))
	local bullets0 = #field.bullets
	for _ = 1, 28 do field:step(DT) end
	ok("⑨b 预告结束必发弹(快照弹道)", #field.bullets == bullets0 + 1, #field.bullets - bullets0)
	field:destroy()
	CS:RemoveTag(enemy, "ShooterEnemy")
	enemy:Destroy()
end

-- ⑩ destroy 零残留
do
	cvfx:destroy()
	local resid = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		local n = d.Name
		if n == "CombatHitBurst" or n == "CombatMagnetBeam" or n == "SlashArc"
			or n == "EnemyFxSat" or n == "EnemyFxDisc" or n == "EnemyFxLight"
			or n == "ItemFxShard" or n == "ItemFxLight" then
			resid += 1
		end
	end
	ok("⑩ destroy 零残留(弧/爆点/敌饰/物饰全清)", resid == 0, resid .. " 件残留")
	atk:destroy()
end

-- ⑪ 还原(坑 32)
bikeModel:Destroy(); bulletFolder:Destroy()
cleanupTmp()
for k in pairs(PIN) do hInst:SetAttribute(k, saved[k]) end
local restoreOK = true
for k in pairs(PIN) do
	if hInst:GetAttribute(k) ~= saved[k] then restoreOK = false end
end
ok("⑪ 配置还原回快照", restoreOK, "属性未回快照")

print(string.format("[smoke_combatvfx] %d/%d 通过", pass, pass + fail))
for _, line in ipairs(log) do print(line) end
if fail > 0 then warn(string.format("[smoke_combatvfx] %d 项失败", fail)) end
