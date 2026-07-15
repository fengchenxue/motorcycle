--[[
NEON RUN — TrackBuilder 驱动(M8.5 / ADR-41 混合制)
用法:Studio 命令栏粘贴执行,或经 MCP execute_luau(datamodel=Edit)运行。
★ 必须 Edit 模式:生成的 Instance 只在 Edit 期持久(坑1)。
前置:Workspace.NeonRun.ControlPoints 已有控制点(带 Index 属性定序;路线=人类拖球)。

MODE:
  "compile" = 全管线(P1~P4):段解析→断口反解→路面→内容摆放→分段门+锚点→lint 全套→机器人完赛
  "build"   = 只铺路面+弯道 lint(P1 旧行为)
  "lint"    = 只体检不改场景
SPEC:TrackSpecs 里的键(节拍/区段/供给声明;"Default"=§7 模板)。改 spec=改 repo 文件后重跑。
坑 15:require 用 :Clone() 强制重编译。
]]
local MODE = "compile"
local CLOSED = false  -- false=开放式(有头有尾);true=环形。写入 Workspace.NeonRun.Closed 与运行时同源
local SPEC = "Default"

local RS = game:GetService("ReplicatedStorage")
local TB = require(RS.NeonRun.Modules.TrackBuilder:Clone())

local wsNr = workspace:FindFirstChild("NeonRun")
if wsNr then wsNr:SetAttribute("Closed", CLOSED) end

local report
if MODE == "compile" then
	report = TB.compile({ closed = CLOSED, spec = SPEC })
elseif MODE == "build" then
	report = TB.build({ closed = CLOSED })
else
	report = TB.lint(TB.buildSpline(CLOSED))
end
print(TB.formatReport(report))
return TB.formatReport(report)
