--[[
NEON RUN — TrackBuilder 烘焙驱动(M8.5 P1)
用法:Studio 命令栏粘贴执行,或经 MCP execute_luau(datamodel=Edit)运行。
★ 必须 Edit 模式:生成的路面 Instance 只在 Edit 期持久(坑1)。
前置:Workspace.NeonRun.ControlPoints 已有 ≥3 个控制点(带 Index 属性定序)。

行为:读控制点 → 建样条 → 生成 Workspace.NeonRun.Road 灰盒路面 + 自动打 Rideable Tag → 打印 lint 报告。
只体检不生成:把下面 BUILD 改成 false。
]]
local BUILD = true    -- true=生成路面并烘焙 Tag;false=只跑弯道 lint 不改场景
local CLOSED = false  -- false=开放式赛道(有头有尾);true=环形。会写入 Workspace.NeonRun.Closed 让运行时一致

local RS = game:GetService("ReplicatedStorage")
local TB = require(RS.NeonRun.Modules.TrackBuilder)

-- 单一事实源:把闭环意图写进 Workspace.NeonRun.Closed,运行时试驾脚本读同一属性(样条与终点判定一致)
local wsNr = workspace:FindFirstChild("NeonRun")
if wsNr then wsNr:SetAttribute("Closed", CLOSED) end

local report
if BUILD then
	report = TB.build({ closed = CLOSED })
else
	report = TB.lint(TB.buildSpline(CLOSED))
end
print(TB.formatReport(report))
return TB.formatReport(report)
