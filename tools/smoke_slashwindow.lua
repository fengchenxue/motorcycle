--[[
NEON RUN — 斩击判定窗(统一窗+持续多中) 冒烟(ADR-48;Edit 固定 dt=1/60)
人类拍板(2026-07-16):攻击间隔 0.3 内 ~80% 为判定窗(试验值 0.25);弹反与斩击不做区分;窗内进盒即中且不收窗。
断言组:
  ① 旧行为锚(窗=0.1/不区分):步4进盒命中;步12进盒不中且空挥帧∈[6,7];弹反步4命中+parry 事件
  ② 试验窗(0.25):步12进盒命中(与①b 同剧本对照=新能力);无目标空挥帧∈[15,16]
  ③ 统一窗:0.25 下子弹步12进盒被弹+parry 事件(弹反与斩击同权,不区分)
  ④ 应急分窗开关(ParryWindowSec=0.1):子弹步12不可弹、同帧斩靶仍中(逃生舱有效)
  ⑤ 攻击间隔不变:出刀后立即与步15二连均=recovery;步19可再出刀(0.3s 语义不动)
  ⑥ 持续多中:窗内 A 步5、B 步10 先后进盒均命中(hit 事件=2);全窗有命中则不发 whiff
  ⑦ 确定性:②剧本两跑命中帧逐位一致
  ⑧ 配置还原回快照
注意:断言帧避开窗尽浮点边界(坑 18:0.1 窗尽=6/7 步夹逼、0.25=15/16);
钉扎先存后还原且在同一脚本内闭环(坑 27/32);临时件按名清理幂等(坑 28);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local AttackSystem = require(nr.Modules.AttackSystem:Clone())
local DT = 1 / 60

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end

-- 配置钉扎(坑 27/30:冒烟只依赖 Combat 键,全部钉基线;ParryWindowSec 基线=0=不区分)
local hInst = nr.Config.Handling
local PIN = {
	Combat_HitboxForward = 12, Combat_HitboxSide = 7, Combat_HitboxUp = 5, Combat_HitboxBack = 2,
	Combat_InputBufferSec = 0.1, Combat_ParryWindowSec = 0, Combat_RecoverySec = 0.3,
	Combat_TelegraphRangeStuds = 55,
}
local saved = {}
for k in pairs(PIN) do saved[k] = hInst:GetAttribute(k) end
for k, v in pairs(PIN) do hInst:SetAttribute(k, v) end

-- 隔离场(y=520 空域,远离赛道/测试台;场上 Tag 目标 |rel.Y|≥300 永不进盒,不扰断言)
local ORIGIN = Vector3.new(-4600, 520, -300)
local FAR = ORIGIN + Vector3.new(0, 0, -60)   -- 盒外前方 fwd=60(>Telegraph 55 亦不预告)
local IN_BOX = ORIGIN + Vector3.new(0, 0, -8) -- 盒内 fwd=8(≤HitboxForward 12)
local TMP = "NeonRunSlashWindowSmoke_TMP"

local function cleanupTmp()
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name:sub(1, #TMP) == TMP then inst:Destroy() end
	end
end
cleanupTmp()

local function mkTarget(suffix)
	local p = Instance.new("Part")
	p.Name = TMP .. suffix
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false
	p.Size = Vector3.new(1, 1, 1); p.Position = FAR
	p.Parent = workspace
	return p
end

local ctrl = { physPos = ORIGIN, yaw = 0 } -- look=(0,0,-1)

-- 一次剧本:第 0 帧出刀,targets={{part,enterStep,kind?}},跑 steps 步
local function run(cfgOverride, targets, steps)
	for k, v in pairs(cfgOverride) do hInst:SetAttribute(k, v) end
	local atk = AttackSystem.new(ctrl, nil, nil)
	local res = { hitFrames = {}, whiffFrame = nil, parryFired = false, hitEvents = 0 }
	atk:on("hit", function() res.hitEvents += 1 end)
	atk:on("parry", function() res.parryFired = true end)
	local reg = { curStep = 0 }
	for _, t in ipairs(targets) do
		t.part.Position = FAR
		atk:registerTarget(t.part, { kind = t.kind or "slash", onHit = function(part)
			res.hitFrames[part] = reg.curStep
		end })
	end
	atk:attack()
	for step = 1, steps do
		reg.curStep = step
		for _, t in ipairs(targets) do
			if t.enterStep == step then t.part.Position = IN_BOX end
		end
		local before = atk.bufferT
		atk:step(DT)
		if res.whiffFrame == nil and before > 0 and atk.bufferT <= 0 and atk.windowHits == 0 then
			res.whiffFrame = step
		end
	end
	atk:destroy()
	for k in pairs(cfgOverride) do hInst:SetAttribute(k, PIN[k]) end
	return res
end

-- ① 旧行为锚(窗=0.1、不区分,与旧单窗版同径)
do
	local t = mkTarget("_a1")
	local r = run({}, { { part = t, enterStep = 4 } }, 10)
	ok("①a 旧窗0.1:步4进盒命中", r.hitFrames[t] == 4, r.hitFrames[t])
	t:Destroy()
	local t2 = mkTarget("_a2")
	local r2 = run({}, { { part = t2, enterStep = 12 } }, 20)
	ok("①b 旧窗0.1:步12进盒不中", r2.hitFrames[t2] == nil, r2.hitFrames[t2])
	ok("①c 空挥帧∈[6,7](0.1 窗尽)", r2.whiffFrame == 6 or r2.whiffFrame == 7, r2.whiffFrame)
	t2:Destroy()
	local b = mkTarget("_a3")
	local r3 = run({}, { { part = b, enterStep = 4, kind = "parry" } }, 10)
	ok("①d 旧窗弹反:步4子弹被弹+parry事件", r3.hitFrames[b] == 4 and r3.parryFired,
		tostring(r3.hitFrames[b]) .. "/" .. tostring(r3.parryFired))
	b:Destroy()
end

-- ② 试验窗 0.25
do
	local t = mkTarget("_b1")
	local r = run({ Combat_InputBufferSec = 0.25 }, { { part = t, enterStep = 12 } }, 20)
	ok("②a 试验窗0.25:步12进盒命中(①b同剧本不中=新能力)", r.hitFrames[t] == 12, r.hitFrames[t])
	t:Destroy()
	local r2 = run({ Combat_InputBufferSec = 0.25 }, {}, 20)
	ok("②b 无目标空挥帧∈[15,16](0.25 窗尽)", r2.whiffFrame == 15 or r2.whiffFrame == 16, r2.whiffFrame)
end

-- ③ 统一窗:弹反与斩击不区分(人类拍板)
do
	local b = mkTarget("_c1")
	local r = run({ Combat_InputBufferSec = 0.25 }, { { part = b, enterStep = 12, kind = "parry" } }, 20)
	ok("③ 0.25 统一窗:步12子弹被弹+parry事件(不区分)", r.hitFrames[b] == 12 and r.parryFired,
		tostring(r.hitFrames[b]) .. "/" .. tostring(r.parryFired))
	b:Destroy()
end

-- ④ 应急分窗开关(ParryWindowSec>0 时子弹只在窗前段可弹)
do
	local s, b = mkTarget("_d1s"), mkTarget("_d1b")
	local r = run({ Combat_InputBufferSec = 0.25, Combat_ParryWindowSec = 0.1 },
		{ { part = s, enterStep = 12 }, { part = b, enterStep = 12, kind = "parry" } }, 20)
	ok("④a 分窗开关:步12斩靶仍中", r.hitFrames[s] == 12, r.hitFrames[s])
	ok("④b 分窗开关:步12子弹不可弹(0.1已过)", r.hitFrames[b] == nil and not r.parryFired, tostring(r.hitFrames[b]))
	s:Destroy(); b:Destroy()
end

-- ⑤ 攻击间隔 0.3 语义不动(避边界:15 步=0.25<0.3 仍硬直,19 步=0.3167>0.3 已解)
do
	hInst:SetAttribute("Combat_InputBufferSec", 0.25)
	local atk = AttackSystem.new(ctrl, nil, nil)
	atk:attack()
	ok("⑤a 出刀后立即二连=recovery", atk:attack() == "recovery", "非recovery")
	for _ = 1, 15 do atk:step(DT) end
	ok("⑤b 步15二连仍recovery(间隔0.3不变)", atk:attack() == "recovery", "非recovery")
	for _ = 16, 19 do atk:step(DT) end
	local r = atk:attack()
	ok("⑤c 步19可再出刀", r == "swing" or r == "hit", r)
	atk:destroy()
	hInst:SetAttribute("Combat_InputBufferSec", PIN.Combat_InputBufferSec)
end

-- ⑥ 持续多中:命中不收窗(人类拍板"窗内可斩所有")
do
	local A, B = mkTarget("_f1a"), mkTarget("_f1b")
	local r = run({ Combat_InputBufferSec = 0.25 },
		{ { part = A, enterStep = 5 }, { part = B, enterStep = 10 } }, 20)
	ok("⑥a 首靶步5命中", r.hitFrames[A] == 5, r.hitFrames[A])
	ok("⑥b 第二靶步10仍命中(不收窗)", r.hitFrames[B] == 10, r.hitFrames[B])
	ok("⑥c hit事件=2(两段结算)", r.hitEvents == 2, r.hitEvents)
	ok("⑥d 有命中则全窗不发whiff", r.whiffFrame == nil, r.whiffFrame)
	A:Destroy(); B:Destroy()
end

-- ⑦ 确定性:②a 剧本两跑逐位一致
do
	local t1 = mkTarget("_e1")
	local r1 = run({ Combat_InputBufferSec = 0.25 }, { { part = t1, enterStep = 12 } }, 20)
	local f1 = r1.hitFrames[t1]; t1:Destroy()
	local t2 = mkTarget("_e2")
	local r2 = run({ Combat_InputBufferSec = 0.25 }, { { part = t2, enterStep = 12 } }, 20)
	local f2 = r2.hitFrames[t2]; t2:Destroy()
	ok("⑦ 确定性:两跑命中帧一致且非nil", f1 ~= nil and f1 == f2, tostring(f1) .. "/" .. tostring(f2))
end

-- ⑧ 还原(坑 32:还原是跑完的下一个动作;快照时不存在的键 SetAttribute(nil)=删除)
cleanupTmp()
for k in pairs(PIN) do hInst:SetAttribute(k, saved[k]) end
local restoreOK = true
for k in pairs(PIN) do
	if hInst:GetAttribute(k) ~= saved[k] then restoreOK = false end
end
ok("⑧ 配置还原回快照", restoreOK, "属性未回快照")

print(string.format("[smoke_slashwindow] %d/%d 通过", pass, pass + fail))
for _, line in ipairs(log) do print(line) end
if fail > 0 then warn(string.format("[smoke_slashwindow] %d 项失败", fail)) end
