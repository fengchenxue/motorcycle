--[[
NEON RUN — M9b 首图三版 CP 布点草案(ADR-49;Edit 模式执行,幂等)
★ 用法:改下面 VARIANT = "A" | "B" | "C" 后整段执行(Studio 命令栏或 MCP execute_luau,datamodel=Edit)。
  A 大回环·终版(人类拍板+双嫁接:b6 直线俯冲/b7 90°/b9 105°);发车 (3400,320,400) 朝 -Z
     交叠签名:终盘 b11 从 b6 长下坡正下方净空 93 studs 处穿过 @(2784,-4991)
  B 脊线滑降 点对点一路向南,纵向高差最直白;发车 (5200,320,400)
  C 双钳大S  两大瓣,b7/b9 捷径弦价值最直观;发车 (7000,320,400)
★ 本脚本只做三件事(不 build 不 compile,坑 21 无忧):
  ① 备份旧 ControlPoints(非本工具生成的才备份)→ 重建 CP + Closed=false
  ② 立 12 根节拍界碑(Workspace.NeonRun.Track1Draft,选形辅助,可整夹删除)
  ③ 干跑预检:TB.lint(只体检不铺路,坑 23)+ 断口三档预览
     (b6/b11 按 ADR-49 施工扩展 jump.lipDeg=20/25 预演;扩展落地前 compile 会按自动唇 10°
      生成=缺口 20,属预期降级,勿当 bug)
★ ⚠️ 互斥提醒:本工具会替换 Workspace.NeonRun.ControlPoints(试炼道 CP=生成物,直接销毁不备份)。
  回试炼道(跑 accept/Play 清尾前)=重跑 tools/build_gauntlet.lua + bake_anchors,一键全还原。
★ 选形阶段只有 CP 球 + 界碑,无路面;想看路面轮廓可跑 TB.build({closed=false})
  (同样会替换试炼道路面;还原同上=重跑 build_gauntlet)。
★ 选形拍板 + P3c 扩展(wallBridge/rampFork/lipDeg/checkpoints=5)完成后,正式落地走:
     TrackBuilder.compile({ spec = "Track1", closed = false })
离线预检基准(2026-07-16,复刻 Spline/lint/planJumps 同式):三版 lint 最小半径 205/218/209
(阈值 141.4 @转向65;旧 55 口径 167 亦全过)、断口 20/48/58 三档全 OK、离既有 rig ≥850 studs、
y∈[142,320](总落差 -147:b6 长下坡 -91 / 峡谷口 -32)。
]]
local VARIANT = "A" -- ◀◀ 改这里:"A" / "B" / "C"

local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

-- 节拍表(设计弧长/设计时长;sec 权重=弧长比,与 Config/TrackSpecs.Track1 同源)
local BEATS = {
	{ "b1 发车",        710,  8 }, { "b2 流畅弯组",   1200, 12 },
	{ "b3 贴墙断桥",   1000, 10 }, { "b4 能量闸门",   1050, 10 },
	{ "b5 冲刺跳教学",  900,  8 }, { "b6 长下坡爽段", 1600, 12 },
	{ "b7 分叉A跳台",  1320, 12 }, { "b8 缓冲",        800,  8 },
	{ "b9 分叉B贴墙",  1320, 12 }, { "b10 缓冲峡谷口",  600,  6 },
	{ "b11 峡谷巨跳",  1700, 14 }, { "b12 心流冲线",  1150,  8 },
}
local JUMPS = { { beat = 5, lip = nil }, { beat = 6, lip = 20 }, { beat = 11, lip = 25 } } -- nil=自动唇10

local CPS = {
	A = {
		Vector3.new(3400.0, 320.0, 400.0),
		Vector3.new(3400.0, 320.0, 170.0),
		Vector3.new(3400.0, 320.0, -60.0),
		Vector3.new(3400.0, 320.0, -290.0),
		Vector3.new(3346.2, 320.0, -510.7),
		Vector3.new(3253.9, 320.0, -628.5),
		Vector3.new(3153.6, 320.0, -740.0),
		Vector3.new(3053.2, 320.0, -851.4),
		Vector3.new(2952.8, 320.0, -962.9),
		Vector3.new(2857.4, 320.0, -1078.3),
		Vector3.new(2801.9, 320.0, -1216.8),
		Vector3.new(2793.3, 320.0, -1366.2),
		Vector3.new(2793.3, 320.0, -1596.2),
		Vector3.new(2793.3, 320.0, -1826.2),
		Vector3.new(2793.3, 320.0, -2056.2),
		Vector3.new(2793.3, 320.0, -2286.2),
		Vector3.new(2793.3, 320.0, -2516.2),
		Vector3.new(2793.3, 320.0, -2746.2),
		Vector3.new(2793.3, 320.0, -2976.2),
		Vector3.new(2793.3, 320.0, -3206.2),
		Vector3.new(2793.3, 320.0, -3436.2),
		Vector3.new(2793.3, 320.0, -3666.2),
		Vector3.new(2793.3, 320.0, -3896.2),
		Vector3.new(2793.3, 320.0, -4126.2),
		Vector3.new(2793.3, 311.4, -4356.2),
		Vector3.new(2793.3, 275.4, -4586.2),
		Vector3.new(2793.3, 266.0, -4646.2),
		Vector3.new(2793.3, 256.6, -4706.2),
		Vector3.new(2793.3, 249.7, -4766.2),
		Vector3.new(2793.3, 253.1, -4826.2),
		Vector3.new(2793.3, 264.9, -4886.2),
		Vector3.new(2793.3, 277.4, -4946.2),
		Vector3.new(2793.3, 286.2, -5006.2),
		Vector3.new(2793.3, 284.4, -5066.2),
		Vector3.new(2793.3, 273.3, -5126.2),
		Vector3.new(2793.3, 260.8, -5186.2),
		Vector3.new(2793.3, 249.5, -5246.2),
		Vector3.new(2793.3, 243.0, -5306.2),
		Vector3.new(2793.3, 240.6, -5366.2),
		Vector3.new(2793.3, 232.9, -5596.2),
		Vector3.new(2793.3, 225.5, -5826.2),
		Vector3.new(2823.1, 218.5, -6053.3),
		Vector3.new(2881.4, 214.2, -6191.2),
		Vector3.new(2967.7, 210.0, -6313.5),
		Vector3.new(3078.0, 206.0, -6414.7),
		Vector3.new(3207.4, 202.2, -6490.2),
		Vector3.new(3349.8, 198.5, -6536.4),
		Vector3.new(3498.7, 195.1, -6551.2),
		Vector3.new(3648.7, 191.7, -6551.2),
		Vector3.new(3798.5, 188.6, -6546.1),
		Vector3.new(4018.2, 184.1, -6481.5),
		Vector3.new(4206.8, 179.9, -6351.3),
		Vector3.new(4383.0, 176.2, -6203.4),
		Vector3.new(4534.8, 172.9, -6032.3),
		Vector3.new(4595.9, 170.9, -5895.7),
		Vector3.new(4622.6, 169.2, -5748.5),
		Vector3.new(4613.2, 167.5, -5599.1),
		Vector3.new(4568.3, 166.1, -5456.4),
		Vector3.new(4490.5, 164.8, -5328.6),
		Vector3.new(4384.4, 163.7, -5223.1),
		Vector3.new(4262.0, 162.7, -5136.4),
		Vector3.new(4135.9, 161.9, -5055.4),
		Vector3.new(3916.1, 159.6, -4992.8),
		Vector3.new(3686.1, 155.2, -4990.6),
		Vector3.new(3456.1, 149.0, -4990.6),
		Vector3.new(3396.1, 147.0, -4990.6),
		Vector3.new(3336.1, 144.3, -4990.6),
		Vector3.new(3276.1, 137.0, -4990.6),
		Vector3.new(3216.1, 125.1, -4990.6),
		Vector3.new(3156.1, 112.7, -4990.6),
		Vector3.new(3096.1, 100.2, -4990.6),
		Vector3.new(3036.1, 89.9, -4990.6),
		Vector3.new(2976.1, 84.0, -4990.6),
		Vector3.new(2916.1, 82.4, -4990.6),
		Vector3.new(2856.1, 82.4, -4990.6),
		Vector3.new(2796.1, 82.4, -4990.6),
		Vector3.new(2736.1, 84.1, -4990.6),
		Vector3.new(2676.1, 92.9, -4990.6),
		Vector3.new(2616.1, 105.4, -4990.6),
		Vector3.new(2556.1, 117.8, -4990.6),
		Vector3.new(2496.1, 129.4, -4990.6),
		Vector3.new(2436.1, 134.4, -4990.6),
		Vector3.new(2376.1, 134.5, -4990.6),
		Vector3.new(2316.1, 134.5, -4990.6),
		Vector3.new(2086.1, 134.5, -4990.6),
		Vector3.new(1856.1, 134.5, -4990.6),
		Vector3.new(1626.1, 134.5, -4990.6),
		Vector3.new(1396.1, 134.5, -4990.6),
		Vector3.new(1166.1, 134.5, -4990.6),
		Vector3.new(936.1, 134.5, -4990.6),
		Vector3.new(776.1, 134.5, -4990.6),
	},
	B = {
		Vector3.new(5200.0, 320.0, 400.0),
		Vector3.new(5200.0, 320.0, 170.0),
		Vector3.new(5200.0, 320.0, -60.0),
		Vector3.new(5200.0, 320.0, -290.0),
		Vector3.new(5147.4, 320.0, -511.2),
		Vector3.new(5059.8, 320.0, -632.6),
		Vector3.new(4967.4, 320.0, -750.8),
		Vector3.new(4875.1, 320.0, -869.0),
		Vector3.new(4782.7, 320.0, -987.2),
		Vector3.new(4692.7, 320.0, -1107.1),
		Vector3.new(4638.4, 320.0, -1246.2),
		Vector3.new(4630.1, 320.0, -1395.6),
		Vector3.new(4630.1, 320.0, -1625.6),
		Vector3.new(4630.1, 320.0, -1855.6),
		Vector3.new(4630.1, 320.0, -2085.6),
		Vector3.new(4630.1, 320.0, -2315.6),
		Vector3.new(4630.1, 320.0, -2545.6),
		Vector3.new(4630.1, 320.0, -2775.6),
		Vector3.new(4630.1, 320.0, -3005.6),
		Vector3.new(4630.1, 320.0, -3235.6),
		Vector3.new(4630.1, 320.0, -3465.6),
		Vector3.new(4630.1, 320.0, -3695.6),
		Vector3.new(4630.1, 320.0, -3925.6),
		Vector3.new(4630.1, 320.0, -4155.6),
		Vector3.new(4630.1, 311.4, -4385.6),
		Vector3.new(4630.1, 278.7, -4615.6),
		Vector3.new(4630.1, 262.6, -4845.6),
		Vector3.new(4630.1, 261.4, -4905.6),
		Vector3.new(4630.1, 261.2, -4965.6),
		Vector3.new(4630.1, 261.1, -5025.6),
		Vector3.new(4630.1, 255.9, -5085.6),
		Vector3.new(4630.1, 245.0, -5145.6),
		Vector3.new(4628.8, 237.7, -5205.6),
		Vector3.new(4623.2, 235.1, -5265.3),
		Vector3.new(4613.1, 233.9, -5324.4),
		Vector3.new(4598.6, 233.4, -5382.6),
		Vector3.new(4510.3, 231.4, -5594.7),
		Vector3.new(4413.1, 229.5, -5803.1),
		Vector3.new(4339.7, 227.6, -6020.3),
		Vector3.new(4328.3, 226.4, -6169.6),
		Vector3.new(4346.7, 225.2, -6318.2),
		Vector3.new(4392.4, 224.1, -6460.9),
		Vector3.new(4443.7, 222.9, -6601.9),
		Vector3.new(4495.0, 221.8, -6742.8),
		Vector3.new(4546.4, 220.7, -6883.8),
		Vector3.new(4597.7, 219.6, -7024.7),
		Vector3.new(4649.0, 218.5, -7165.7),
		Vector3.new(4727.6, 216.9, -7381.8),
		Vector3.new(4806.3, 215.4, -7597.9),
		Vector3.new(4885.0, 213.9, -7814.1),
		Vector3.new(4991.1, 212.4, -8016.8),
		Vector3.new(5096.8, 211.5, -8122.7),
		Vector3.new(5224.8, 210.6, -8200.2),
		Vector3.new(5360.7, 209.7, -8263.6),
		Vector3.new(5496.7, 208.9, -8327.0),
		Vector3.new(5632.6, 208.0, -8390.4),
		Vector3.new(5768.6, 207.2, -8453.8),
		Vector3.new(5904.5, 206.4, -8517.2),
		Vector3.new(6038.3, 205.6, -8584.7),
		Vector3.new(6210.7, 190.5, -8736.0),
		Vector3.new(6373.4, 174.2, -8898.6),
		Vector3.new(6536.0, 173.9, -9061.2),
		Vector3.new(6698.7, 173.9, -9223.9),
		Vector3.new(6861.3, 173.9, -9386.5),
		Vector3.new(6903.7, 173.9, -9428.9),
		Vector3.new(6946.1, 173.9, -9471.4),
		Vector3.new(6988.6, 173.2, -9513.8),
		Vector3.new(7031.0, 166.3, -9556.2),
		Vector3.new(7073.4, 155.9, -9598.7),
		Vector3.new(7115.8, 146.1, -9641.1),
		Vector3.new(7158.3, 141.8, -9683.5),
		Vector3.new(7200.7, 144.2, -9725.9),
		Vector3.new(7243.1, 149.1, -9768.4),
		Vector3.new(7285.6, 153.6, -9810.8),
		Vector3.new(7448.2, 166.4, -9973.4),
		Vector3.new(7610.8, 172.3, -10136.1),
		Vector3.new(7773.5, 172.7, -10298.7),
		Vector3.new(7936.1, 172.7, -10461.3),
		Vector3.new(8098.7, 172.7, -10624.0),
		Vector3.new(8261.4, 172.7, -10786.6),
		Vector3.new(8424.0, 172.7, -10949.2),
		Vector3.new(8438.1, 172.7, -10963.4),
	},
	C = {
		Vector3.new(7000.0, 320.0, 400.0),
		Vector3.new(7000.0, 320.0, 170.0),
		Vector3.new(7000.0, 320.0, -60.0),
		Vector3.new(7000.0, 320.0, -290.0),
		Vector3.new(7053.9, 320.0, -510.7),
		Vector3.new(7144.4, 320.0, -629.9),
		Vector3.new(7240.9, 320.0, -744.8),
		Vector3.new(7337.3, 320.0, -859.7),
		Vector3.new(7433.7, 320.0, -974.7),
		Vector3.new(7526.9, 320.0, -1092.0),
		Vector3.new(7582.4, 320.0, -1230.5),
		Vector3.new(7590.9, 320.0, -1379.9),
		Vector3.new(7590.9, 320.0, -1609.9),
		Vector3.new(7590.9, 320.0, -1839.9),
		Vector3.new(7590.9, 320.0, -2069.9),
		Vector3.new(7590.9, 320.0, -2299.9),
		Vector3.new(7590.9, 320.0, -2529.9),
		Vector3.new(7590.9, 320.0, -2759.9),
		Vector3.new(7590.9, 320.0, -2989.9),
		Vector3.new(7590.9, 320.0, -3219.9),
		Vector3.new(7590.9, 320.0, -3449.9),
		Vector3.new(7590.9, 320.0, -3679.9),
		Vector3.new(7590.9, 320.0, -3909.9),
		Vector3.new(7590.9, 320.0, -4139.9),
		Vector3.new(7590.9, 311.4, -4369.9),
		Vector3.new(7590.9, 278.7, -4599.9),
		Vector3.new(7590.9, 262.6, -4829.9),
		Vector3.new(7590.9, 261.4, -4889.9),
		Vector3.new(7590.9, 261.2, -4949.9),
		Vector3.new(7590.9, 261.1, -5009.9),
		Vector3.new(7590.9, 255.9, -5069.9),
		Vector3.new(7590.9, 245.0, -5129.9),
		Vector3.new(7589.7, 237.7, -5189.9),
		Vector3.new(7584.0, 235.1, -5249.6),
		Vector3.new(7574.0, 233.9, -5308.8),
		Vector3.new(7559.5, 233.4, -5367.0),
		Vector3.new(7465.0, 231.4, -5575.8),
		Vector3.new(7333.6, 229.5, -5764.6),
		Vector3.new(7179.9, 227.6, -5934.3),
		Vector3.new(7052.4, 226.4, -6012.6),
		Vector3.new(6910.5, 225.2, -6060.2),
		Vector3.new(6761.5, 224.1, -6074.6),
		Vector3.new(6613.1, 222.9, -6055.1),
		Vector3.new(6472.9, 221.8, -6002.6),
		Vector3.new(6348.2, 220.7, -5919.9),
		Vector3.new(6244.5, 219.6, -5811.8),
		Vector3.new(6148.1, 218.5, -5696.9),
		Vector3.new(6000.3, 216.9, -5520.7),
		Vector3.new(5852.4, 215.4, -5344.5),
		Vector3.new(5704.6, 213.9, -5168.3),
		Vector3.new(5535.5, 212.4, -5014.1),
		Vector3.new(5400.0, 211.5, -4950.7),
		Vector3.new(5253.2, 210.6, -4921.7),
		Vector3.new(5103.7, 209.7, -4928.7),
		Vector3.new(4960.3, 208.9, -4971.3),
		Vector3.new(4831.2, 208.0, -5047.0),
		Vector3.new(4724.0, 207.2, -5151.4),
		Vector3.new(4636.9, 206.4, -5273.5),
		Vector3.new(4554.8, 205.6, -5398.9),
		Vector3.new(4481.1, 190.5, -5616.1),
		Vector3.new(4421.6, 174.2, -5838.2),
		Vector3.new(4362.0, 173.9, -6060.4),
		Vector3.new(4302.5, 173.9, -6282.6),
		Vector3.new(4243.0, 173.9, -6504.7),
		Vector3.new(4227.4, 173.9, -6562.7),
		Vector3.new(4211.9, 173.9, -6620.6),
		Vector3.new(4196.4, 173.2, -6678.6),
		Vector3.new(4180.9, 166.3, -6736.5),
		Vector3.new(4165.3, 155.9, -6794.5),
		Vector3.new(4149.8, 146.1, -6852.5),
		Vector3.new(4134.3, 141.8, -6910.4),
		Vector3.new(4118.7, 144.2, -6968.4),
		Vector3.new(4103.2, 149.1, -7026.3),
		Vector3.new(4087.7, 153.6, -7084.3),
		Vector3.new(4028.2, 166.4, -7306.4),
		Vector3.new(3968.6, 172.3, -7528.6),
		Vector3.new(3909.1, 172.7, -7750.8),
		Vector3.new(3849.6, 172.7, -7972.9),
		Vector3.new(3790.0, 172.7, -8195.1),
		Vector3.new(3730.5, 172.7, -8417.3),
		Vector3.new(3671.0, 172.7, -8639.4),
		Vector3.new(3665.8, 172.7, -8658.7),
	},
}

local cps = CPS[VARIANT]
assert(cps, "VARIANT 必须是 A/B/C")

local wsNr = workspace:FindFirstChild("NeonRun") or Instance.new("Folder")
wsNr.Name = "NeonRun"; wsNr.Parent = workspace

-- ① 备份旧 CP(gauntlet 同款惯用法)→ 重建
local oldCp = wsNr:FindFirstChild("ControlPoints")
if oldCp and not oldCp:GetAttribute("NeonRunGenerated") then
	local bk = SS:FindFirstChild("NeonRun") or Instance.new("Folder")
	bk.Name = "NeonRun"; bk.Parent = SS
	local bkRoot = bk:FindFirstChild("Backup") or Instance.new("Folder")
	bkRoot.Name = "Backup"; bkRoot.Parent = bk
	oldCp.Name = "ControlPoints_bak_" .. os.time()
	oldCp.Parent = bkRoot
	print("[track1] 旧 ControlPoints 已备份 → ServerStorage.NeonRun.Backup." .. oldCp.Name)
elseif oldCp then
	oldCp:Destroy()
end
local cpFolder = Instance.new("Folder")
cpFolder.Name = "ControlPoints"
cpFolder:SetAttribute("NeonRunGenerated", true)
cpFolder:SetAttribute("Track1Variant", VARIANT)
cpFolder.Parent = wsNr
for i, pos in ipairs(cps) do
	local cp = Instance.new("Part")
	cp.Name = string.format("CP%02d", i)
	cp:SetAttribute("Index", i)
	cp.Shape = Enum.PartType.Ball
	cp.Size = Vector3.new(3, 3, 3)
	cp.Color = Color3.fromRGB(255, 140, 0)
	cp.Anchored = true; cp.CanCollide = false; cp.CanQuery = false; cp.Transparency = 0.3
	cp.Position = pos
	cp.Parent = cpFolder
end
wsNr:SetAttribute("Closed", false)

-- ② 节拍界碑(选形辅助;正式 compile 前手动删 Track1Draft 或留着无碍——CanQuery=false)
local oldDraft = wsNr:FindFirstChild("Track1Draft")
if oldDraft then oldDraft:Destroy() end
local draft = Instance.new("Folder"); draft.Name = "Track1Draft"; draft.Parent = wsNr

local TB = require(RS.NeonRun.Modules.TrackBuilder:Clone()) -- 坑15:Clone 躲 require 缓存
local sp = TB.buildSpline(false)
local totalDesign = 0
for _, b in ipairs(BEATS) do totalDesign += b[2] end
local acc = 0
for i, b in ipairs(BEATS) do
	local t = acc / totalDesign
	acc += b[2]
	local cf = sp:GetCFrame(math.min(t, 0.999))
	local pos = cf.Position + Vector3.new(0, 10, 0)
	local pillar = Instance.new("Part")
	pillar.Name = string.format("Beat%02d_%s", i, b[1])
	pillar.Size = Vector3.new(1.5, 20, 1.5)
	pillar.Color = (b[1]:find("跳") or b[1]:find("峡谷")) and Color3.fromRGB(255, 170, 40)
		or (b[1]:find("分叉") and Color3.fromRGB(80, 220, 120) or Color3.fromRGB(0, 200, 255))
	pillar.Material = Enum.Material.Neon
	pillar.Anchored = true; pillar.CanCollide = false; pillar.CanQuery = false; pillar.CanTouch = false
	pillar.Position = pos
	pillar.Parent = draft
end

-- ③ 干跑预检:lint(不铺路)+ 断口三档预览(复刻 planJumps 弹道;lip 可覆写=P3c 扩展预演)
print(TB.formatReport(TB.lint(sp)))
print(string.format("[track1:%s] 样条弧长 %.0f(设计 13350)| CP %d | 发车 (%.0f,%.0f,%.0f)",
	VARIANT, sp.Length, #cps, cps[1].X, cps[1].Y, cps[1].Z))

local H = require(RS.NeonRun.Config.Handling:Clone())
local C = require(RS.NeonRun.Config.Track:Clone())
local g, ballStep = H.Physics.Gravity, C.Jump.BallisticStepStuds
local function jumpDist(tCut, v, extraPitchDeg)
	local tan = sp:GetTangent(tCut)
	local dir = tan
	if extraPitchDeg and extraPitchDeg > 0 then
		local horiz = Vector3.new(tan.X, 0, tan.Z)
		if horiz.Magnitude > 1e-4 then
			local pitch = math.atan2(tan.Y, horiz.Magnitude) + math.rad(extraPitchDeg)
			dir = horiz.Unit * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		end
	end
	local vel = dir * v
	local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	if horizSpeed < 1 then return nil end
	local y, vy = sp:GetPoint(tCut).Y, vel.Y
	local s, wasAbove = 0, false
	for _ = 1, 800 do
		local dt = ballStep / horizSpeed
		y += vy * dt - 0.5 * g * dt * dt
		vy -= g * dt
		s += ballStep
		local t2 = tCut + s / sp.Length
		if t2 >= 1 then return nil end
		local roadY = sp:GetPoint(t2).Y
		if y - roadY > 0.5 then wasAbove = true end
		if wasAbove and y <= roadY then return s end
	end
	return nil
end
local vC = H.Speed.Base
local vS = vC * H.Speed.SprintMultiplier
local vF = vS * H.Speed.FlowExtraMultiplier
for _, j in ipairs(JUMPS) do
	local s0, s1 = 0, 0
	local a = 0
	for i, b in ipairs(BEATS) do
		if i == j.beat then s0, s1 = a, a + b[2] break end
		a += b[2]
	end
	local tCut = (s0 + 0.45 * (s1 - s0)) / totalDesign
	local lip = j.lip or C.Jump.LipAngleDeg
	local dS = jumpDist(tCut, vS, lip)
	if dS then
		local gap = dS - C.Jump.SprintMarginStuds
		local dCr = jumpDist(tCut, vC, lip)
		local dF = jumpDist(tCut, vF, lip)
		print(string.format("[track1] 断口@%s 楔%d° 缺口%.1f | 巡航 %s / 冲刺 %.1f / 心流 %s %s",
			BEATS[j.beat][1], lip, gap, dCr and string.format("%.1f", dCr) or "落不到", dS,
			dF and string.format("%.1f", dF) or "?",
			((dCr == nil or dCr < gap) and dS >= gap and dF and dF >= gap + 2) and "✅" or "❌"))
	else
		print("[track1] 断口@" .. BEATS[j.beat][1] .. " ❌ 弹道无解")
	end
end
print("[track1] 下一步:三版都跑一遍选形 → 人类拍板 → P3c 扩展落地 → TrackBuilder.compile({spec=\"Track1\", closed=false})")
