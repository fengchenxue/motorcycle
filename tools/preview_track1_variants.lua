--[[
NEON RUN — M9b 三版赛道并排全尺寸预览(ADR-49 选形辅助;Edit 执行,幂等)
一次铺出 A/B/C 三条半透明光带赛道(纯视觉:无 Tag/无碰撞/不占 ControlPoints/不动试炼道),
含:断口缺口(路带真断开)+ 跳台楔占位(10°/20°/25°)+ b3 墙桥与 b9 贴墙捷径的墙板提示 + 12 节拍牌。
删除=整夹删 Workspace.NeonRun.Track1Preview。选定后:tools/build_track1_cp.lua 放该版 CP → P3c 扩展 → compile。
发车台:A (3400,320,400) 青 / B (5200,320,400) 琥珀 / C (7000,320,400) 品红,均朝 -Z。
]]
local RS = game:GetService("ReplicatedStorage")
local Spline = require(RS.NeonRun.Modules.Spline:Clone())

local DESIGN_TOTAL = 13350
local BEATS = {
	{ "b1 发车", 710 }, { "b2 流畅弯组", 1200 }, { "b3 贴墙断桥(强制教学)", 1000 },
	{ "b4 能量闸门·战斗", 1050 }, { "b5 冲刺跳教学", 900 }, { "b6 长下坡爽段", 1600 },
	{ "b7 分叉A·跳台上高架", 1320 }, { "b8 缓冲", 800 }, { "b9 分叉B·贴墙捷径", 1320 },
	{ "b10 缓冲·峡谷口", 600 }, { "b11 峡谷巨跳(爆点)", 1700 }, { "b12 心流冲线", 1150 },
}
local JUMPS = { { beat = 5, lip = 10, gap = 20 }, { beat = 6, lip = 20, gap = 48 }, { beat = 11, lip = 25, gap = 58 } }
local BRIDGE = { beat = 3, gap = 70, side = -1 }  -- b3 墙桥:路断 70,左墙带唯一过法
local WALLFORK = { beat = 9, side = 1, len = 560 } -- b9 右内线贴墙捷径提示

local VARIANTS = {
	{ key = "A", label = "A 大回环·终版", color = Color3.fromRGB(0, 200, 255), cps = {
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
	} },
	{ key = "B", label = "B 脊线滑降", color = Color3.fromRGB(255, 170, 40), cps = {
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
	} },
	{ key = "C", label = "C 双钳大S", color = Color3.fromRGB(255, 80, 200), cps = {
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
	} },
}

local wsNr = workspace:FindFirstChild("NeonRun") or Instance.new("Folder")
wsNr.Name = "NeonRun"; wsNr.Parent = workspace
local old = wsNr:FindFirstChild("Track1Preview")
if old then old:Destroy() end
local root = Instance.new("Folder"); root.Name = "Track1Preview"; root.Parent = wsNr

local function mk(parent, props)
	local p = Instance.new(props.class or "Part")
	p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth; p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.material or Enum.Material.Neon
	p.Transparency = props.tr or 0
	if props.shape then p.Shape = props.shape end
	p.Color = props.color; p.Size = props.size; p.Name = props.name
	if props.cf then p.CFrame = props.cf else p.Position = props.pos end
	p.Parent = parent
	return p
end

local function sign(parent, pos, facePos, text, w)
	local board = mk(parent, { name = "Sign", size = Vector3.new(w or 16, 5, 0.5),
		color = Color3.fromRGB(12, 16, 26), material = Enum.Material.SmoothPlastic,
		cf = CFrame.lookAt(pos, facePos) })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255); lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold; lbl.Text = text; lbl.Parent = gui
	return board
end

local ROAD_DROP, STEP = 1.6, 36
for _, v in ipairs(VARIANTS) do
	local folder = Instance.new("Folder"); folder.Name = "Variant_" .. v.key; folder.Parent = root
	local sp = Spline.new(v.cps, false)
	local L = sp.Length
	local scale = L / DESIGN_TOTAL
	-- beat 边界(studs)与区间
	local bounds, acc = {}, 0
	for i, b in ipairs(BEATS) do
		bounds[i] = { s0 = acc * scale, s1 = (acc + b[2]) * scale, name = b[1] }
		acc += b[2]
	end
	-- 缺口区间
	local gaps = {}
	for _, j in ipairs(JUMPS) do
		local bb = bounds[j.beat]
		local cut = bb.s0 + 0.45 * (bb.s1 - bb.s0)
		gaps[#gaps + 1] = { from = cut, to = cut + j.gap, lip = j.lip }
	end
	do
		local bb = bounds[BRIDGE.beat]
		local cut = bb.s0 + 0.45 * (bb.s1 - bb.s0)
		gaps[#gaps + 1] = { from = cut, to = cut + BRIDGE.gap, bridge = true }
	end
	local function inGap(s)
		for _, g in ipairs(gaps) do if s >= g.from and s <= g.to then return true end end
		return false
	end
	-- 光带路面
	local n = math.floor(L / STEP)
	local slabs = 0
	for i = 0, n - 1 do
		local s = (i + 0.5) * (L / n)
		if not inGap(s) then
			local cf = sp:GetCFrame(s / L)
			local up = cf.UpVector
			local center = cf.Position - up * (ROAD_DROP + 0.5)
			mk(folder, { name = string.format("Rib_%03d", i), size = Vector3.new(40, 1, (L / n) * 1.05),
				color = v.color, tr = 0.35, cf = CFrame.lookAt(center, center + cf.LookVector, up) })
			slabs += 1
		end
	end
	-- 跳台楔占位(斜面从来车侧升起)+ 缺口牌
	for _, g in ipairs(gaps) do
		local t = g.from / L
		local cf = sp:GetCFrame(t)
		local lookH = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		if g.lip then
			local h = math.tan(math.rad(g.lip)) * 24
			local base = cf.Position - Vector3.new(0, ROAD_DROP, 0) - lookH * 12
			local center = base + Vector3.new(0, h / 2, 0)
			mk(folder, { class = "WedgePart", name = "JumpWedge" .. g.lip, size = Vector3.new(40, h, 24),
				color = Color3.fromRGB(230, 235, 245), material = Enum.Material.SmoothPlastic, tr = 0.1,
				cf = CFrame.lookAt(center, center - lookH) })
			sign(folder, cf.Position + Vector3.new(0, 14, 0), cf.Position + Vector3.new(0, 14, 0) + lookH,
				string.format("跳台 %d° · 缺口 %.0f", g.lip, g.to - g.from), 14)
		else
			-- b3 墙桥:缺口两侧铺墙板提示(左侧连续墙带=唯一过法)
			local wallFrom, wallTo = g.from - 90, g.to + 90
			local wn = math.floor((wallTo - wallFrom) / 40)
			for k = 0, wn - 1 do
				local ws = wallFrom + (k + 0.5) * ((wallTo - wallFrom) / wn)
				local wcf = sp:GetCFrame(ws / L)
				local wlookH = Vector3.new(wcf.LookVector.X, 0, wcf.LookVector.Z).Unit
				local wc = wcf.Position + wcf.RightVector * BRIDGE.side * 21 + Vector3.new(0, 13 - ROAD_DROP, 0)
				mk(folder, { name = "BridgeWall" .. k, size = Vector3.new(2, 26, 42), color = Color3.fromRGB(0, 150, 200),
					tr = 0.45, cf = CFrame.lookAt(wc, wc + wlookH) })
			end
			sign(folder, cf.Position + Vector3.new(0, 16, 0), cf.Position + Vector3.new(0, 16, 0) + lookH,
				"贴墙断桥:路断 70,走左墙带过", 18)
		end
	end
	-- b9 贴墙捷径提示墙(右内线)
	do
		local bb = bounds[WALLFORK.beat]
		local mid = (bb.s0 + bb.s1) / 2
		local from = mid - WALLFORK.len / 2
		local wn = math.floor(WALLFORK.len / 40)
		for k = 0, wn - 1 do
			local ws = from + (k + 0.5) * (WALLFORK.len / wn)
			local wcf = sp:GetCFrame(ws / L)
			local wlookH = Vector3.new(wcf.LookVector.X, 0, wcf.LookVector.Z).Unit
			local wc = wcf.Position + wcf.RightVector * WALLFORK.side * 21 + Vector3.new(0, 13 - ROAD_DROP, 0)
			mk(folder, { name = "ForkWall" .. k, size = Vector3.new(2, 26, 42), color = Color3.fromRGB(80, 220, 120),
				tr = 0.55, cf = CFrame.lookAt(wc, wc + wlookH) })
		end
	end
	-- 12 节拍牌 + 发车台
	for i, bb in ipairs(bounds) do
		local t = math.min(bb.s0 / L, 0.995)
		local cf = sp:GetCFrame(t)
		local lookH = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
		local pos = cf.Position + cf.RightVector * 26 + Vector3.new(0, 8 - ROAD_DROP, 0)
		mk(folder, { name = "BeatPillar" .. i, size = Vector3.new(1.2, 16, 1.2),
			color = v.color, tr = 0.2, pos = pos + Vector3.new(0, 2, 0) })
		sign(folder, pos + Vector3.new(0, 10, 0), pos + Vector3.new(0, 10, 0) + lookH, v.label .. " · " .. bb.name, 15)
	end
	do
		local cf = sp:GetCFrame(0)
		local base = cf.Position - Vector3.new(0, ROAD_DROP, 0)
		mk(folder, { name = "StartPad", size = Vector3.new(44, 1.2, 44), color = Color3.fromRGB(60, 255, 120),
			tr = 0.15, pos = base })
		sign(folder, base + Vector3.new(0, 22, 0), base + Vector3.new(0, 22, 0) + cf.LookVector,
			"◤ " .. v.label .. " 发车 ◢", 26)
	end
	print(string.format("[preview:%s] 弧长 %.0f | 光带 %d 片 | 发车 (%.0f, %.0f, %.0f)",
		v.key, L, slabs, v.cps[1].X, v.cps[1].Y, v.cps[1].Z))
end
print("[preview] 三版已铺 Workspace.NeonRun.Track1Preview(纯视觉:无Tag/无碰撞/不占ControlPoints)。")
print("[preview] 相机飞到 (5200, 900, -500) 俯视可同框三版;删除=删 Track1Preview 文件夹。")
