--[[
NEON RUN — 示例:AI 一键摆一条开放式测试赛道(M8.5 P1 链路端到端演示)
★ Edit 模式执行(Studio 命令栏 或 MCP execute_luau, datamodel=Edit)。Play 里建的不持久(坑1)。

行为:生成控制点(开放式)→ TrackBuilder 铺灰盒路+Rideable Tag+弯道 lint → 手摆水晶/能量核(打 Tag)。
跑完 Play(F5):从起点 3-2-1 发车 → 沿路骑 → 水晶+18/能量核斩+25/贴墙+12每秒 → 骑到末端完赛计时。

⚠️ 这是链路验证脚本:TrackBuilder P1 与开放式改动尚未 Studio 验证,首跑可能需 debug
   (枚举名/下沉量/lint 边界)。跑通=整条"铺路+手摆内容"链路成立。
]]
local CS = game:GetService("CollectionService")
local RS = game:GetService("ReplicatedStorage")
local wsNr = workspace:FindFirstChild("NeonRun") or Instance.new("Folder")
wsNr.Name = "NeonRun"; wsNr.Parent = workspace

-- ── 1. 开放式赛道控制点(≥4 个;y≥200 避开测试走廊沙丘 y=138,坑4)──────────
local cpFolder = wsNr:FindFirstChild("ControlPoints")
if cpFolder then cpFolder:Destroy() end
cpFolder = Instance.new("Folder"); cpFolder.Name = "ControlPoints"; cpFolder.Parent = wsNr

local path = {
	Vector3.new(0,   210, 0),      -- 起点
	Vector3.new(0,   210, -400),
	Vector3.new(180, 210, -750),   -- 缓右弯(半径需 ≥ ~167 studs,lint 会查)
	Vector3.new(180, 210, -1200),
	Vector3.new(0,   210, -1550),  -- 缓左弯
	Vector3.new(0,   210, -2000),  -- 终点
}
for i, pos in ipairs(path) do
	local cp = Instance.new("Part")
	cp.Name = string.format("CP%02d", i)
	cp:SetAttribute("Index", i)
	cp.Shape = Enum.PartType.Ball
	cp.Size = Vector3.new(3, 3, 3)
	cp.Color = Color3.fromRGB(255, 140, 0)
	cp.Anchored = true; cp.CanCollide = false; cp.Transparency = 0.3
	cp.Position = pos
	cp.Parent = cpFolder
end

-- ── 2. 铺路(TrackBuilder P1):路面 + Rideable Tag + 弯道 lint ──────────────
wsNr:SetAttribute("Closed", false)             -- 开放式(运行时读同一属性)
local TB = require(RS.NeonRun.Modules.TrackBuilder)
local report = TB.build({ closed = false })
print(TB.formatReport(report))                 -- 段数 / Rideable Tag 数 / 弯道体检

-- ── 3. 手摆内容:纯 Tag 驱动,系统实时接管(水晶/能量核)──────────────────
local sp = TB.buildSpline(false)
local function spawnAt(t, shape, tag, color, size)
	local p = Instance.new("Part")
	p.Anchored = true; p.CanCollide = false; p.CanTouch = false
	p.Shape = shape; p.Size = size; p.Color = color
	p.Material = Enum.Material.Neon
	p.Position = sp:GetPoint(t) + Vector3.new(0, 2, 0)   -- 路面上方 2 studs
	p.Parent = wsNr
	CS:AddTag(p, tag)                          -- ← 关键:打 Tag,游戏立刻认(实时注册)
	return p
end
-- 3 水晶(保底,贴主线)+ 2 能量核(偏线;摆直线段避免"斩击点只在直线段"lint 警告)
spawnAt(0.15, Enum.PartType.Ball, "EnergyCrystal", Color3.fromRGB(0, 200, 255), Vector3.new(2, 2, 2))
spawnAt(0.35, Enum.PartType.Ball, "EnergyCrystal", Color3.fromRGB(0, 200, 255), Vector3.new(2, 2, 2))
spawnAt(0.55, Enum.PartType.Ball, "EnergyCrystal", Color3.fromRGB(0, 200, 255), Vector3.new(2, 2, 2))
spawnAt(0.45, Enum.PartType.Block, "EnergyCore", Color3.fromRGB(180, 0, 255), Vector3.new(4, 4, 4))
spawnAt(0.80, Enum.PartType.Block, "EnergyCore", Color3.fromRGB(180, 0, 255), Vector3.new(4, 4, 4))

print("[example_testtrack] 完成:控制点 " .. #path .. " · 路面已铺 · 水晶3 核2 已打 Tag。F5 试骑。")
