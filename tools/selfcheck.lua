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
