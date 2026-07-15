--[[
NEON RUN — 功能试炼道(Gauntlet)一键生成:V1 全功能串联测试赛道
★ Edit 模式执行(Studio 命令栏 或 MCP execute_luau, datamodel=Edit)。Play 里建的不持久(坑1)。
★ 幂等:重复跑=删旧重建;首跑会把非本脚本生成的 ControlPoints 备份到 ServerStorage.NeonRun.Backup。
前置:tools/seed_m8_1_config.lua 已跑(Energy 新属性);Workspace.Motorcycle 模板在位。
建议顺序:example_testtrack.lua(P1 最小验证)通过后再跑本脚本。

分区(开放式,y=220 平路,全长 ≈3400 studs,巡航 ≈35s):
  Z1 发车直线   水晶列 + 磁吸边界探针(+6 该吸 / +10 不该吸)
  Z2 S 弯组     全速走线(弯道 lint 半径校验)
  Z3 战斗直线   射手×2(骑穿免费/弹反)+ 能量核×2(偏线)+ 可破闸门(左道,右侧可绕)
  Z4 跳跃段     20°/30° 坡(可绕行)+ 巡航/冲刺/心流理论落点条纹(同高近似,实际落点更远)
  Z5 贴墙段     WallRideSurface 直墙 L200/R120(M6.5 落地前=普通碰撞墙,几何先行)
  Z6 冲线直线   水晶收尾;终点=样条末端 t≥0.997(RaceTimer 自动)

运行时自动接管(零手工):水晶/核/闸门/射手=Tag 实时注册;分段门拱门=RaceTimer
checkpointTs(0.25/0.5/0.75)客户端自建;发车点=CP01→CP02;重生走样条回取。
]]
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")

local RAMP_FLIP = false -- 首跑核对:若楔形坡背对来车(撞立面),改 true 重跑

local wsNr = workspace:FindFirstChild("NeonRun") or Instance.new("Folder")
wsNr.Name = "NeonRun"; wsNr.Parent = workspace

-- ── 0. 备份旧控制点(破坏性操作先备份;本脚本生成的不重复备份)──────────────
local oldCp = wsNr:FindFirstChild("ControlPoints")
if oldCp and not oldCp:GetAttribute("NeonRunGenerated") then
	local bk = SS:FindFirstChild("NeonRun") or Instance.new("Folder")
	bk.Name = "NeonRun"; bk.Parent = SS
	local bkRoot = bk:FindFirstChild("Backup") or Instance.new("Folder")
	bkRoot.Name = "Backup"; bkRoot.Parent = bk
	oldCp.Name = "ControlPoints_bak_" .. os.time()
	oldCp.Parent = bkRoot
	print("[gauntlet] 旧 ControlPoints 已备份 → ServerStorage.NeonRun.Backup." .. oldCp.Name)
elseif oldCp then
	oldCp:Destroy()
end

-- ── 1. 控制点(开放式;直线区用共线点钉直,S 弯半径按 lint 阈值 ≈184 放宽)────
local cpFolder = Instance.new("Folder")
cpFolder.Name = "ControlPoints"
cpFolder:SetAttribute("NeonRunGenerated", true)
cpFolder.Parent = wsNr

local Y = 220 -- 坑4:测试走廊沙丘最高 y=138,新几何 y≥200
local path = {
	Vector3.new(700, Y, 100),    -- CP01 发车(SPAWN=CP01→CP02)
	Vector3.new(700, Y, -200),
	Vector3.new(700, Y, -450),   -- Z1 直线尾
	Vector3.new(800, Y, -850),   -- Z2 右摆顶点
	Vector3.new(600, Y, -1350),  -- Z2 左摆顶点
	Vector3.new(700, Y, -1700),  -- Z2 出弯;此后至终点全直(战斗/跳跃/贴墙区要求直线段)
	Vector3.new(700, Y, -1950),
	Vector3.new(700, Y, -2200),
	Vector3.new(700, Y, -2450),
	Vector3.new(700, Y, -2700),
	Vector3.new(700, Y, -2950),
	Vector3.new(700, Y, -3200),
	Vector3.new(700, Y, -3300),  -- CP13 终点
}
for i, pos in ipairs(path) do
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

-- ── 2. 铺路(TrackBuilder P1)。:Clone() 强制重编译(坑15,MCP require 缓存)──
wsNr:SetAttribute("Closed", false)
local TB = require(RS.NeonRun.Modules.TrackBuilder:Clone())
local report = TB.build({ closed = false })
print(TB.formatReport(report))
local sp = TB.buildSpline(false)

-- ── 3. 内容摆放(全 Tag 驱动;统一挂 Workspace.NeonRun.Gauntlet,幂等重建)────
local old = wsNr:FindFirstChild("Gauntlet")
if old then old:Destroy() end
local G = Instance.new("Folder"); G.Name = "Gauntlet"; G.Parent = wsNr

-- 世界锚点 →(t, 路面系):所有内容以样条最近点定位,横向偏移沿 RightVector
local function at(z, x)
	local t = select(1, sp:NearestPoint(Vector3.new(x or 700, Y, z)))
	return t, sp:GetCFrame(t)
end
local ROAD_DROP = 1.6 -- Config/Track SinkBelowSpline:路面顶面=样条 y−1.6
local function roadTopPos(z, x, lateral, up)
	local _, cf = at(z, x)
	return cf.Position + cf.RightVector * (lateral or 0) + Vector3.new(0, (up or 0) - ROAD_DROP, 0)
end

local function mk(props)
	local p = Instance.new(props.class or "Part")
	p.Anchored = true
	p.CanCollide = props.collide or false
	p.CanTouch = false                       -- 坑11:判定一律射线/体积查询
	p.CanQuery = props.query or false        -- 路上摆件默认不遮探针/扫掠射线
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = props.material or Enum.Material.Neon
	if props.shape then p.Shape = props.shape end
	p.Color = props.color
	p.Size = props.size
	p.Name = props.name
	if props.cf then p.CFrame = props.cf else p.Position = props.pos end
	p.Parent = G
	if props.tag then CS:AddTag(p, props.tag) end
	return p
end

-- 水晶(+18 磁吸7)/ 能量核(斩+25)/ 射手(弹反+25·斩+30·骑穿免费)/ 闸门(斩+15)
local function crystal(z, lateral)
	return mk{ name = "Crystal", tag = "EnergyCrystal", size = Vector3.new(2, 2, 2),
		shape = Enum.PartType.Ball, color = Color3.fromRGB(0, 200, 255),
		pos = roadTopPos(z, 700, lateral, 2 + ROAD_DROP) } -- +2:与 example_testtrack 同高
end
local function core(z, lateral)
	return mk{ name = "Core", tag = "EnergyCore", size = Vector3.new(4, 4, 4),
		color = Color3.fromRGB(180, 0, 255), pos = roadTopPos(z, 700, lateral, 2 + ROAD_DROP) }
end
local function shooter(z, lateral, id)
	return mk{ name = "GauntletShooter" .. id, tag = "ShooterEnemy", size = Vector3.new(3, 5, 3),
		color = Color3.fromRGB(255, 60, 110), material = Enum.Material.SmoothPlastic,
		pos = roadTopPos(z, 700, lateral, 2.5) } -- 立在路面上;注册时强制无碰撞(ADR-22)
end

-- Z1 发车直线:水晶列 + 磁吸边界探针
crystal(-180, 0); crystal(-260, 0)
crystal(-340, 6)   -- 骑中线 3D 距 ≈6.3 < 7:该吸到
crystal(-400, 10)  -- 骑中线 3D 距 ≈10.2 > 7:不该吸到(留着不吸=边界正确)

-- Z2 S 弯:水晶贴行车线(直接取样条点,§7 磁吸=保底)
do
	for _, anchor in ipairs({ {800, -850}, {700, -1100}, {600, -1350} }) do
		local t = select(1, sp:NearestPoint(Vector3.new(anchor[1], Y, anchor[2])))
		mk{ name = "Crystal", tag = "EnergyCrystal", size = Vector3.new(2, 2, 2),
			shape = Enum.PartType.Ball, color = Color3.fromRGB(0, 200, 255),
			pos = sp:GetPoint(t) + Vector3.new(0, 2, 0) }
	end
end

-- Z3 战斗直线(判定点只在直线段,§7):射手×2 / 核×2 偏线 / 闸门左道 / 水晶×2
shooter(-1800, -8, "A")
shooter(-2050, 8, "B")
core(-1900, 12); core(-2150, -12)
crystal(-1850, 0); crystal(-2100, 0)
-- 闸门:Destructible,覆左半幅(x 682~698),右侧可绕(§7 主路线永不强制斩击)。
-- ADR-42:未斩=实体墙走碰撞三档;斩后 AttackSystem 切物性(CanCollide/CanQuery 关),R 复原。
mk{ name = "EnergyGate", tag = "Destructible", size = Vector3.new(16, 10, 1), collide = true, query = true,
	color = Color3.fromRGB(255, 80, 40), pos = roadTopPos(-1990, 700, -10, 5) }

-- Z4 跳跃段:20°/30° 楔形坡(Rideable,可绕行)+ 理论落点条纹(纯视觉,CanQuery=false)
local STRIPE = {
	{ Color3.fromRGB(200, 200, 200), "巡航" },
	{ Color3.fromRGB(0, 220, 255), "冲刺" },
	{ Color3.fromRGB(255, 200, 60), "心流" },
}
local function ramp(zCenter, lateral, deg, len, dists)
	local h = len * math.tan(math.rad(deg))
	local _, cf = at(zCenter, 700)
	local center = cf.Position + cf.RightVector * lateral + Vector3.new(0, h / 2 - ROAD_DROP, 0)
	local back = RAMP_FLIP and cf.LookVector or -cf.LookVector
	local w = mk{ class = "WedgePart", name = string.format("Ramp%d", deg),
		size = Vector3.new(20, h, len), color = Color3.fromRGB(90, 100, 120),
		material = Enum.Material.SmoothPlastic, collide = true, query = true,
		cf = CFrame.lookAt(center, center + back) } -- 薄边朝来车:楔形斜面从来车侧升起
	CS:AddTag(w, "Rideable") -- ADR-28 可骑面声明(M4.1 白名单切换后必需)
	local lipZ = zCenter - len / 2 -- 行进向 −Z:坡唇在段尾
	for i, d in ipairs(dists) do
		mk{ name = "Land_" .. STRIPE[i][2] .. d, size = Vector3.new(20, 0.2, 1.2),
			color = STRIPE[i][1], pos = roadTopPos(lipZ - d, 700, lateral, 0.15) }
	end
end
ramp(-2280, -6, 20, 30, { 28, 51, 60 })  -- §7:20° 同高跳距 巡航28/冲刺51/心流60
ramp(-2450, 6, 30, 24, { 44, 81, 94 })   -- §7:30° → 44/81/94;精确值跑 tools/jumptable.lua

-- Z5 贴墙段:WallRideSurface 直墙(对齐 WallRideField 数据模型:Size=(厚,高,长),
-- Z 轴=墙长(切向),UpVector≈世界 Y,±X 两大面皆可贴;WallSide 属性仅人读备注)。
-- M6.5 验收前:普通碰撞墙(CanCollide/CanQuery=true),顺带测墙碰撞;墙=经济中性(ADR-37)。
local function wall(zCenter, len, side)
	local lateral = (side == "L" and -1 or 1) * 21 -- 路半宽20 + 半厚1:内面与路缘齐平
	local _, cf = at(zCenter, 700)
	local center = cf.Position + cf.RightVector * lateral + Vector3.new(0, 13 - ROAD_DROP, 0)
	local w = mk{ name = "WallRide_" .. side, size = Vector3.new(2, 26, len),
		color = Color3.fromRGB(0, 150, 200), material = Enum.Material.SmoothPlastic,
		collide = true, query = true, tag = "WallRideSurface",
		cf = CFrame.lookAt(center, center + cf.LookVector) }
	w:SetAttribute("WallSide", side)
	return w
end
wall(-2720, 200, "L")  -- 长墙:地面进入/段尾退出
wall(-2800, 120, "R")  -- 短墙,与长墙重叠 80 studs:双侧走廊 + 换边测试

-- Z6 冲线直线:水晶收尾(终点 t≥0.997 由 RaceTimer 自动判)
crystal(-3000, 0); crystal(-3100, 0)

-- ── 4. 分区路牌(路右侧,SurfaceGui 文字;纯视觉)────────────────────────────
local SIGNS = {
	{ 60,    "Z1 发车 · 水晶列|磁吸边界: +6该吸 / +10不该吸" },
	{ -500,  "Z2 S弯组 · 全速走线|lint 半径≥阈值" },
	{ -1760, "Z3 战斗直线|射手×2 · 核×2 · 闸门(可绕)" },
	{ -2240, "Z4 跳跃 20°/30°|条纹=同高理论落点:白巡航/青冲刺/金心流" },
	{ -2610, "Z5 贴墙段 WallRideSurface|M6.5 前=普通墙" },
	{ -2960, "Z6 冲线" },
}
for _, s in ipairs(SIGNS) do
	local _, cf = at(s[1], 700)
	local pos = cf.Position + cf.RightVector * 27 + Vector3.new(0, 6 - ROAD_DROP, 0)
	local board = mk{ name = "Sign", size = Vector3.new(12, 5, 0.5),
		color = Color3.fromRGB(15, 20, 30), material = Enum.Material.SmoothPlastic,
		cf = CFrame.lookAt(pos, pos - cf.LookVector) } -- 牌面正对来车方向
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(0, 220, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Text = s[2]:gsub("|", "\n")
	lbl.Parent = gui
end

-- ── 5. 汇总 ─────────────────────────────────────────────────────────────────
local counts = {}
for _, tag in ipairs({ "EnergyCrystal", "EnergyCore", "ShooterEnemy", "Destructible", "WallRideSurface" }) do
	local n = 0
	for _, inst in ipairs(CS:GetTagged(tag)) do
		if inst:IsDescendantOf(G) then n += 1 end
	end
	counts[tag] = n
end
print(string.format(
	"[gauntlet] 完成:CP %d · 水晶 %d(含边界探针2) · 核 %d · 射手 %d · 闸门 %d · 贴墙面 %d · 坡2 · 路牌 %d",
	#path, counts.EnergyCrystal, counts.EnergyCore, counts.ShooterEnemy,
	counts.Destructible, counts.WallRideSurface, #SIGNS))
print("[gauntlet] 供给预算:晶 " .. counts.EnergyCrystal .. "×18(蓝区) · 核 2×25+闸 15+弹反 25/斩敌 30(红区)→ 心流在 Z3 可达")
if not report.lint.pass then
	warn("[gauntlet] ❌ 弯道 lint 未过:按报告 t 值挪 CP04/CP05(外扩 x 或拉长 z)后重跑本脚本")
end
warn("[gauntlet] 首跑核对:① 楔形坡薄边应朝来车(反了改 RAMP_FLIP=true 重跑)② selfcheck 的 rideableTags=路面段数+2(两坡)③ 主赛道旧 Tag 件(TrackShooter 等)仍在远处注册,计数勿混")
print("[gauntlet] F5 试骑:3-2-1 发车 → Z1 吸晶 → Z2 走线 → Z3 弹反/斩核/破闸 → Z4 跳坡对条纹 → Z5(现阶段=墙碰撞)→ 冲线结算 → R 全重置复跑")
