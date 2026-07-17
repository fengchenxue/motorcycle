--[[
NEON RUN — 冲刺 UI 动效 SprintUI v4 冒烟(ADR-50g/50h/50k/50l;Edit 固定 dt=1/60)
断言组(①~⑥ 钉 SprintEdgeBurstSec=0 = 50k 恒定微光档回归;⑨ = v4 点火包络):
  ① 静默:未冲刺模糊 0/暗角全透/边缘全透,归零后停写
  ② 冲刺 0.5s:模糊≈BlurMax×强度(能量权重 1)/暗角=1-0.45×强度/边缘=master×α×EdgeAlpha 微光
  ③ 恒定微光(旋钮 0 档=50k 语义):再 0.5s 边缘值不衰减不爆发,恒守公式值
  ④ 松键:模糊/暗角/边缘 0.8s 内近零(常驻=零)
  ⑤ 心流:边缘变金+入流白闪回透
  ⑥ 旋钮=0:BlurMax=0→模糊 0;Vignette=0→暗角全透;EdgeAlpha=0→冲刺中边缘也全透
  ⑨ v4 点火短促流光(ADR-50l):起步亮起=公式含包络/按住不放 BurstSec 后退净(仍在冲刺)/
     断冲再冲=再来一次/旋钮 0=即时回 v3 恒定
  ⑦ destroy:Lighting 无残留 Blur
  ⑧ 配置还原
纯实例断言(Edit 不渲染);钉扎自还原(坑 27/32);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local nr = RS:WaitForChild("NeonRun")
local SprintUI = require(nr.Modules.SprintUI:Clone())
local DT = 1 / 60

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end

local hInst = nr.Config.Handling
local PIN = { VFX_SprintUIAlpha = 0.85, VFX_SprintEdgeAlpha = 0.12, VFX_SprintBlurMax = 8, VFX_SprintVignette = 0.45,
	VFX_SprintEdgeBurstSec = 0 }   -- ①~⑥ 钉 0=50k 恒定档;⑨ 内自行改值自行还原
local saved = {}
for k in pairs(PIN) do saved[k] = hInst:GetAttribute(k) end
for k, v in pairs(PIN) do hInst:SetAttribute(k, v) end

local TMP = "NeonRunSprintUISmoke_TMP"
for _, inst in ipairs(workspace:GetChildren()) do
	if inst.Name:sub(1, #TMP) == TMP then inst:Destroy() end
end
local folder = Instance.new("Folder")
folder.Name = TMP
folder.Parent = workspace
local gui = Instance.new("ScreenGui")
gui.Parent = folder

local tele = { sprinting = false, flowBoost = false }
local sui = SprintUI.new(gui)

-- ① 静默
sui:step(DT, tele, 1)
ok("①a 静默:模糊 0/暗角全透/边缘全透", sui.blur.Size == 0 and sui.vigV.BackgroundTransparency > 0.999
	and sui.edgeL.BackgroundTransparency > 0.999, sui.blur.Size)
sui:step(DT, tele, 1)
ok("①b 归零后停写", sui.written == 0, tostring(sui.written))

-- ② 冲刺 0.5s(α≈1-e^-3≈0.95;强度=α×1)
tele.sprinting = true
for _ = 1, 30 do sui:step(DT, tele, 1) end
local a = sui.sprintAlpha
ok("②a 模糊=BlurMax×强度", math.abs(sui.blur.Size - 8 * a) < 0.05 and sui.blur.Size > 7, sui.blur.Size)
ok("②b 暗角=1-0.45×强度", math.abs(sui.vigV.BackgroundTransparency - (1 - 0.45 * a)) < 0.01, sui.vigV.BackgroundTransparency)
local eExpect = 1 - 0.85 * a * 0.12
ok("②c 边缘=master×α×EdgeAlpha 微光(≈0.9 透)", math.abs(sui.edgeL.BackgroundTransparency - eExpect) < 0.01
	and sui.edgeL.BackgroundTransparency > 0.88, sui.edgeL.BackgroundTransparency)

-- ③ 恒定微光:再 0.5s 不衰减不爆发(包络已删)
do
	local e0 = sui.edgeL.BackgroundTransparency
	for _ = 1, 30 do sui:step(DT, tele, 1) end
	local e1 = sui.edgeL.BackgroundTransparency
	ok("③ 边缘恒定(0.5s 后漂移<0.005,无包络相变)", math.abs(e1 - e0) < 0.005
		and math.abs(e1 - (1 - 0.85 * sui.sprintAlpha * 0.12)) < 0.01, e1 - e0)
end

-- ④ 松键 0.8s:全部近零(常驻=零)
tele.sprinting = false
for _ = 1, 48 do sui:step(DT, tele, 1) end
ok("④ 松键后近零(模糊<0.15/暗角>0.99/边缘>0.99)", sui.blur.Size < 0.15
	and sui.vigV.BackgroundTransparency > 0.99 and sui.edgeL.BackgroundTransparency > 0.99, sui.blur.Size)

-- ⑤ 心流:变金+白闪
tele.sprinting = true
for _ = 1, 10 do sui:step(DT, tele, 1) end
tele.flowBoost = true
sui:step(DT, tele, 1)
ok("⑤a 入流白闪", sui.flash.BackgroundTransparency < 0.99, sui.flash.BackgroundTransparency)
ok("⑤b 边缘变金", sui.edgeL.BackgroundColor3 == Color3.fromRGB(255, 210, 110), tostring(sui.edgeL.BackgroundColor3))
for _ = 1, 15 do sui:step(DT, tele, 1) end
ok("⑤c 白闪回透", sui.flash.BackgroundTransparency > 0.999, sui.flash.BackgroundTransparency)
tele.flowBoost = false
sui:step(DT, tele, 1)
ok("⑤d 退心流回青", sui.edgeL.BackgroundColor3 == Color3.fromRGB(140, 230, 255), tostring(sui.edgeL.BackgroundColor3))

-- ⑥ 旋钮=0=关(ADR-44 一键回退;EdgeAlpha=0=冲刺中边缘也无)
hInst:SetAttribute("VFX_SprintBlurMax", 0)
hInst:SetAttribute("VFX_SprintVignette", 0)
hInst:SetAttribute("VFX_SprintEdgeAlpha", 0)
sui:step(DT, tele, 1)
ok("⑥ 三旋钮=0:模糊 0+暗角全透+冲刺中边缘全透", sui.blur.Size == 0 and sui.vigV.BackgroundTransparency > 0.999
	and sui.edgeL.BackgroundTransparency > 0.999,
	sui.blur.Size .. "/" .. sui.vigV.BackgroundTransparency .. "/" .. sui.edgeL.BackgroundTransparency)
hInst:SetAttribute("VFX_SprintBlurMax", PIN.VFX_SprintBlurMax)
hInst:SetAttribute("VFX_SprintVignette", PIN.VFX_SprintVignette)
hInst:SetAttribute("VFX_SprintEdgeAlpha", PIN.VFX_SprintEdgeAlpha)

-- ⑨ v4 点火短促流光(ADR-50l):冲刺开始亮、按住不放也在 BurstSec 内退净;断冲再冲=再来一次
hInst:SetAttribute("VFX_SprintEdgeBurstSec", 0.6)
tele.sprinting = false
for _ = 1, 60 do sui:step(DT, tele, 1) end   -- 归零复位(prevSprinting=false,edgeT 耗尽)
tele.sprinting = true
for _ = 1, 6 do sui:step(DT, tele, 1) end    -- 0.1s 起步
do
	local k = sui.edgeT / 0.6
	local env = k * k * (3 - 2 * k)
	local eExp = 1 - 0.85 * sui.sprintAlpha * 0.12 * env
	ok("⑨a 冲刺起步边缘亮起(=公式含包络)", sui.edgeL.BackgroundTransparency < 0.97
		and math.abs(sui.edgeL.BackgroundTransparency - eExp) < 0.01, sui.edgeL.BackgroundTransparency)
end
for _ = 1, 45 do sui:step(DT, tele, 1) end   -- 累计 0.85s > BurstSec
ok("⑨b 按住不放 BurstSec 后退净(仍在冲刺中)", tele.sprinting and sui.sprintAlpha > 0.9
	and sui.edgeL.BackgroundTransparency > 0.999, sui.edgeL.BackgroundTransparency)
tele.sprinting = false
for _ = 1, 30 do sui:step(DT, tele, 1) end   -- 断冲 0.5s
tele.sprinting = true
for _ = 1, 3 do sui:step(DT, tele, 1) end
ok("⑨c 断冲后再冲刺=再来一次", sui.edgeT > 0.5 and sui.edgeL.BackgroundTransparency < 0.995,
	sui.edgeT .. "/" .. sui.edgeL.BackgroundTransparency)
hInst:SetAttribute("VFX_SprintEdgeBurstSec", 0)
sui:step(DT, tele, 1)
do
	local eExp = 1 - 0.85 * sui.sprintAlpha * 0.12
	ok("⑨d 旋钮 0=即时回 v3 恒定微光(env 恒 1)", math.abs(sui.edgeL.BackgroundTransparency - eExp) < 0.01,
		sui.edgeL.BackgroundTransparency)
end
hInst:SetAttribute("VFX_SprintEdgeBurstSec", PIN.VFX_SprintEdgeBurstSec)

-- ⑦ destroy
sui:destroy()
ok("⑦ destroy:Lighting 无残留 Blur", Lighting:FindFirstChild("NeonRunSprintBlur") == nil and gui:FindFirstChild("SprintUI") == nil, "残留")

-- ⑧ 还原
folder:Destroy()
for k in pairs(PIN) do hInst:SetAttribute(k, saved[k]) end
local restoreOK = true
for k in pairs(PIN) do
	if hInst:GetAttribute(k) ~= saved[k] then restoreOK = false end
end
ok("⑧ 配置还原回快照", restoreOK, "未还原")

print(string.format("[smoke_sprintui] %d/%d 通过", pass, pass + fail))
for _, line in ipairs(log) do print(line) end
if fail > 0 then warn(string.format("[smoke_sprintui] %d 项失败", fail)) end
