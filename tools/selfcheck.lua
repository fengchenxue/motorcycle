--[[
NEON RUN — Studio 场景自检脚本
用法:在 Studio 命令栏粘贴执行,或经 MCP execute_luau(datamodel=Edit)运行。
期望值随里程碑推进会变化,以 docs/status.md 快照为准;发现偏差先回填 status 再动手修。
]]

local HS = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local out = {}

-- 模块清单
local nr = RS:FindFirstChild("NeonRun")
if nr and nr:FindFirstChild("Modules") then
	local t = {}
	for _, m in ipairs(nr.Modules:GetChildren()) do
		t[#t + 1] = m.Name
	end
	table.sort(t)
	out.modules = table.concat(t, ",")
else
	out.modules = "MISSING"
end

-- Config Attributes 数量(M2 基线=34;M8.1 后应增加,见 design §E4)
local h = nr and nr:FindFirstChild("Config") and nr.Config:FindFirstChild("Handling")
local c = 0
if h then
	for _ in pairs(h:GetAttributes()) do c += 1 end
end
out.handlingAttrs = c

-- M8.1 Energy 配置核对:新字段齐、旧擦墙字段除(缺/残留则 seed_m8_1_config.lua 补种)
local eInst = nr and nr:FindFirstChild("Config") and nr.Config:FindFirstChild("Energy")
if eInst then
	local ec = 0
	for _ in pairs(eInst:GetAttributes()) do ec += 1 end
	out.energyAttrs = ec
	local miss = {}
	for _, k in ipairs({ "MinIgnitionBurnSec", "IgnitionCost", "CrystalMagnetRadius", "MoveRegenPerSec", "GateGain" }) do
		if eInst:GetAttribute(k) == nil then miss[#miss + 1] = k end
	end
	out.energyM81Missing = #miss > 0 and table.concat(miss, ",") or "OK"   -- 期望 OK
	local stray = {}
	for _, k in ipairs({ "NearMissGain", "NearMissWindow" }) do
		if eInst:GetAttribute(k) ~= nil then stray[#stray + 1] = k end
	end
	out.energyStrayGraze = #stray > 0 and table.concat(stray, ",") or "OK"   -- 期望 OK(旧擦墙字段已清)
	-- M6.5:松键宽限键在、贴墙收入键除(缺/残留则 seed_m6_5_config.lua 补种;ADR-37/39)
	out.energyM65Grace = eInst:GetAttribute("ReleaseGraceSec") ~= nil and "OK" or "MISSING"   -- 期望 OK
	local strayWall = {}
	for _, k in ipairs({ "WallRideGainPerSec", "WallRideMinSpeed" }) do
		if eInst:GetAttribute(k) ~= nil then strayWall[#strayWall + 1] = k end
	end
	out.energyStrayWallRide = #strayWall > 0 and table.concat(strayWall, ",") or "OK"   -- 期望 OK(墙=经济中性)
else
	out.energyAttrs = "MISSING"
end

-- M6.5 Handling WallRide_* 键核对(ConfigLive 首次 bind 自动补;缺则 seed 或跑一次控制器)
if h then
	local missW = {}
	for _, k in ipairs({ "WallRide_EnterWindowStuds", "WallRide_EnterMinSpeed", "WallRide_EnterMaxAngleDeg",
		"WallRide_EnterTowardMinSpeed", "WallRide_BlendSec", "WallRide_HeightBandSpeed",
		"WallRide_FallDriftPerSec", "WallRide_CamRollSec" }) do
		if h:GetAttribute(k) == nil then missW[#missW + 1] = k end
	end
	out.handlingM65WallRide = #missW > 0 and table.concat(missW, ",") or "OK"   -- 期望 OK
end

-- M6.5 授权墙段计数(WallRideSurface Tag;测试台 WallRig 建后 ≥1)
out.wallRideSurfaceTags = #game:GetService("CollectionService"):GetTagged("WallRideSurface")

-- M8.1 静态战斗 Tag(闸门/核):Destructible=闸门 +15,EnergyCore=核 +25
out.destructibleTags = #game:GetService("CollectionService"):GetTagged("Destructible")
out.energyCoreTags = #game:GetService("CollectionService"):GetTagged("EnergyCore")

-- 摩托完整性
local moto = workspace:FindFirstChild("Motorcycle")
out.primaryPart = moto and moto.PrimaryPart and moto.PrimaryPart.Name or "MISSING" -- 期望 BikeRoot
local strayAnchored = 0
if moto then
	for _, d in ipairs(moto:GetDescendants()) do
		if d:IsA("BasePart") and d ~= moto.PrimaryPart and d.Anchored then
			strayAnchored += 1
		end
	end
end
out.strayAnchored = strayAnchored -- 期望 0;非 0 = Ctrl+Z 回滚事故,全部解锚
out.rootAnchored = moto and moto.PrimaryPart and moto.PrimaryPart.Anchored or false -- 期望 true(停放)

-- 赛道数据层
local wsNr = workspace:FindFirstChild("NeonRun")
out.controlPoints = wsNr and wsNr:FindFirstChild("ControlPoints") and #wsNr.ControlPoints:GetChildren() or 0

-- 赛道烘焙(M8.5):Track 文件夹段数 + Rideable Tag 计数(ADR-28 白名单;M4.1 探针切换后即依赖此)
local track = wsNr and wsNr:FindFirstChild("Track")
out.trackRoadSegs = track and track:FindFirstChild("Road") and #track.Road:GetChildren() or 0
out.rideableTags = #game:GetService("CollectionService"):GetTagged("Rideable")

-- 备份与模板隔离
local ss = game:GetService("ServerStorage"):FindFirstChild("NeonRun")
out.backup = ss and ss:FindFirstChild("Backup") and ss.Backup:FindFirstChild("Motorcycle_Original") ~= nil
local racing = game:GetService("ServerScriptService"):FindFirstChild("Racing")
out.templateDisabled = racing == nil or racing.Disabled -- 期望 true

print(HS:JSONEncode(out))
return HS:JSONEncode(out)
