--[[
NEON RUN — 冲刺 UI 动效 SprintUI 冒烟(ADR-50g;Edit 固定 dt=1/60)
断言组(方案B 包络:攻 0.05→平台 0.30→衰减 0.25→残留;松键 ×6/s 指数淡出):
  ① 静默:未冲刺全透明,归零后停写
  ② 爆发:点火后平台期速度线可见(强度≈master,含 noise 微闪下限)+边缘流光按 0.45 系数
  ③ 残留:0.8s 后衰减到 sustain 档(master×0.18)
  ④ 松键:0.5s 指数淡出至近零
  ⑤ 心流:变金+入流白闪(上升沿闪、0.2s 内回透明)
  ⑥ master=0=总关
  ⑦ destroy 零残留
  ⑧ 配置还原
纯 UI 实例(Folder 下 ScreenGui,Edit 不渲染但属性可断言);钉扎自还原(坑 27/32);require(Clone)(坑 15)。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local SprintUI = require(nr.Modules.SprintUI:Clone())
local DT = 1 / 60

local pass, fail, log = 0, 0, {}
local function ok(name, cond, got)
	if cond then pass += 1; log[#log + 1] = "  ✓ " .. name
	else fail += 1; log[#log + 1] = "  ✗ " .. name .. "  →得到: " .. tostring(got) end
end

local hInst = nr.Config.Handling
local PIN = { VFX_SprintUIAlpha = 0.8, VFX_SprintUISustain = 0.18 }
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
local function minLineT()
	local m = 1
	for _, l in ipairs(sui.lines) do m = math.min(m, l.f.BackgroundTransparency) end
	return m
end

-- ① 静默
sui:step(DT, tele)
ok("①a 未冲刺全透明", minLineT() > 0.999, minLineT())
sui:step(DT, tele)
ok("①b 归零后停写(written=0)", sui.written == 0, tostring(sui.written))

-- ② 爆发平台(0.1s 处:攻 0.05 已过,平台 level=0.8;微闪下限 0.5 → 最亮线透明度 ≤ 1-0.4)
tele.sprinting = true
for _ = 1, 6 do sui:step(DT, tele) end
ok("②a 平台期速度线可见(最亮线透明度≤0.62)", minLineT() <= 0.62, minLineT())
local edgeExpect = 1 - 0.8 * 0.45
ok("②b 边缘流光=1-level×0.45", math.abs(sui.edgeL.BackgroundTransparency - edgeExpect) < 0.02, sui.edgeL.BackgroundTransparency)

-- ③ 残留(0.8s:攻+平台+衰减 0.6s 已过 → sustain=0.8×0.18=0.144)
for _ = 7, 48 do sui:step(DT, tele) end
local t3 = minLineT()
ok("③ 残留档(透明度∈[0.84,0.94])", t3 >= 0.84 and t3 <= 0.94, t3)

-- ④ 松键淡出(0.5s → gate≈e^-3)
tele.sprinting = false
for _ = 1, 30 do sui:step(DT, tele) end
ok("④ 松键 0.5s 后近零(透明度>0.98)", minLineT() > 0.98, minLineT())

-- ⑤ 心流:再点火进平台 → flow 上升沿=变金+白闪
tele.sprinting = true
for _ = 1, 6 do sui:step(DT, tele) end
tele.flowBoost = true
sui:step(DT, tele)
ok("⑤a 入流白闪(闪帧透明度<1)", sui.flash.BackgroundTransparency < 0.99, sui.flash.BackgroundTransparency)
ok("⑤b 心流线变金", sui.lines[1].f.BackgroundColor3 == Color3.fromRGB(255, 210, 110), tostring(sui.lines[1].f.BackgroundColor3))
for _ = 1, 15 do sui:step(DT, tele) end
ok("⑤c 白闪 0.25s 内回透明", sui.flash.BackgroundTransparency > 0.999, sui.flash.BackgroundTransparency)
tele.flowBoost = false
sui:step(DT, tele)
ok("⑤d 退心流回青", sui.lines[1].f.BackgroundColor3 == Color3.fromRGB(140, 230, 255), tostring(sui.lines[1].f.BackgroundColor3))

-- ⑥ master=0=总关
hInst:SetAttribute("VFX_SprintUIAlpha", 0)
sui:step(DT, tele)
sui:step(DT, tele)
ok("⑥ master=0 全透明且停写", minLineT() > 0.999 and sui.written == 0, minLineT())
hInst:SetAttribute("VFX_SprintUIAlpha", PIN.VFX_SprintUIAlpha)

-- ⑦ destroy
sui:destroy()
ok("⑦ destroy 零残留", gui:FindFirstChild("SprintUI") == nil, "残留")

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
