--[[
NEON RUN — M4.1 Config 补种(Studio-only 属性对齐;命令栏或 MCP execute_luau 跑)
效果:Handling +6(Respawn_AnchorSpacingSec/SetbackAnchors/InputProtectSec/AnchorMaxTurnDeg/
      AnchorClearAheadStuds + Collision_SideOffset);仅补缺失,保留既有调参;无删除项。
]]
local RS = game:GetService("ReplicatedStorage")
local hInst = RS:WaitForChild("NeonRun").Config.Handling

local ADD = {
	Collision_SideOffset = 1.1,
	Respawn_AnchorSpacingSec = 5,
	Respawn_SetbackAnchors = 0,
	Respawn_InputProtectSec = 0.5,
	Respawn_AnchorMaxTurnDeg = 6,
	Respawn_AnchorClearAheadStuds = 60,
}
local added = {}
for k, v in pairs(ADD) do
	if hInst:GetAttribute(k) == nil then hInst:SetAttribute(k, v); added[#added + 1] = k .. "=" .. tostring(v) end
end
print("M4.1 Config 补种完成")
print("  新增:", #added > 0 and table.concat(added, ", ") or "(全部已存在,未改)")
return "seeded +" .. #added
