--[[
NEON RUN — M4.1 重生锚点烘焙(ADR-27;Edit 期跑,命令栏或 MCP execute_luau)
读 Workspace.NeonRun.ControlPoints(Index 定序)+ Closed 属性 → 样条 →
按 Respawn_AnchorSpacingSec × Speed_Base 弧长采样 → 三 lint + 墙段上空排除 →
写 Workspace.NeonRun.RespawnAnchors(不可见锚根 + Attachment 链,幂等重建)。
改赛道(挪 CP/摆墙/摆射手)后必须重跑;M8.5 P4 起由 TrackBuilder 顺带调用。
坑 15:require 用 :Clone() 强制重编译。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local Spline = require(nr.Modules.Spline:Clone())
local RespawnAnchors = require(nr.Modules.RespawnAnchors:Clone())

local h = nr.Config.Handling
local function attr(k, fallback)
	local v = h:GetAttribute(k)
	return v ~= nil and v or fallback
end

local wsNr = workspace:FindFirstChild("NeonRun")
local cpFolder = wsNr and wsNr:FindFirstChild("ControlPoints")
if not cpFolder or #cpFolder:GetChildren() < 3 then
	print("[bake_anchors] ✗ 无 ControlPoints(或 <3 个),先建赛道")
	return "no controlpoints"
end
local closed = wsNr:GetAttribute("Closed")
if closed == nil then closed = true end

local cps = cpFolder:GetChildren()
table.sort(cps, function(a, b) return (a:GetAttribute("Index") or 0) < (b:GetAttribute("Index") or 0) end)
local pts = {}
for _, cp in ipairs(cps) do pts[#pts + 1] = cp.Position end
local spline = Spline.new(pts, closed)

local spacingStuds = attr("Respawn_AnchorSpacingSec", 5) * attr("Speed_Base", 100)
local result = RespawnAnchors.bake(spline, {
	spacingStuds = spacingStuds,
	hover = attr("Ground_HoverHeight", 1.6),
	maxTurnDeg = attr("Respawn_AnchorMaxTurnDeg", 6),
	clearAheadStuds = attr("Respawn_AnchorClearAheadStuds", 60),
})
RespawnAnchors.persist(result)

local byReason = {}
for _, r in ipairs(result.rejected) do byReason[r.reason] = (byReason[r.reason] or 0) + 1 end
local parts = {}
for k, v in pairs(byReason) do parts[#parts + 1] = k .. "×" .. v end
print(string.format("[bake_anchors] ✓ 锚点 %d(样条 %.0f studs,间距 %.0f)| 剔除:%s",
	#result.anchors, spline.Length, spacingStuds, #parts > 0 and table.concat(parts, " ") or "无"))
for _, r in ipairs(result.rejected) do
	print(string.format("  剔 t=%.3f(%s)", r.t, r.reason))
end
return string.format("baked %d anchors, rejected %d", #result.anchors, #result.rejected)
