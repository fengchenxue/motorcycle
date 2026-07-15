--[[
NEON RUN — M6.5 Config 补种(Studio-only 状态对齐;命令栏或 MCP execute_luau 跑)
背景:Rojo 已同步 Energy.luau / Handling.luau 源码,但 Config Attributes 是 Studio-only 状态(不在 git)。
      ConfigLive.bind 只补"缺失"属性(保用户调参),不删旧字段,故删除需本脚本显式处理。
效果:Energy 实例 +1(ReleaseGraceSec=0.12,ADR-39),−2 旧贴墙收入属性(WallRideGainPerSec/
      WallRideMinSpeed,ADR-37 墙=经济中性);Handling 实例 +8(WallRide_*,ADR-36)。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local eInst = nr.Config.Energy
local hInst = nr.Config.Handling

-- Energy 新增(仅当缺失才种,保留既有调参值)
local ADD_E = { ReleaseGraceSec = 0.12 }
local added = {}
for k, v in pairs(ADD_E) do
	if eInst:GetAttribute(k) == nil then eInst:SetAttribute(k, v); added[#added + 1] = "Energy." .. k .. "=" .. tostring(v) end
end

-- Handling 新增(WallRide_*;首次跑控制器时 ConfigLive 也会补,这里显式种齐便于核对)
local ADD_H = {
	WallRide_EnterWindowStuds = 6, WallRide_EnterMinSpeed = 60, WallRide_EnterMaxAngleDeg = 45,
	WallRide_EnterTowardMinSpeed = 5, WallRide_BlendSec = 0.2, WallRide_HeightBandSpeed = 26,
	WallRide_FallDriftPerSec = 0, WallRide_CamRollSec = 0.25,
	WallRide_ChainMaxTurnDeg = 8,   -- M8.5 直墙链跨段交接(ADR-41)
}
for k, v in pairs(ADD_H) do
	if hInst:GetAttribute(k) == nil then hInst:SetAttribute(k, v); added[#added + 1] = "Handling." .. k .. "=" .. tostring(v) end
end

-- Energy 删除(贴墙收入字段,ADR-37:墙=经济中性)
local removed = {}
for _, dead in ipairs({ "WallRideGainPerSec", "WallRideMinSpeed" }) do
	if eInst:GetAttribute(dead) ~= nil then eInst:SetAttribute(dead, nil); removed[#removed + 1] = "Energy." .. dead end
end

-- 汇总
local keys = {}
for k in pairs(eInst:GetAttributes()) do keys[#keys + 1] = k end
table.sort(keys)
print("M6.5 Config 补种完成")
print("  新增:", #added > 0 and table.concat(added, ", ") or "(全部已存在,未改)")
print("  删除:", #removed > 0 and table.concat(removed, ", ") or "(无旧字段,已干净)")
print("  Energy 现有属性(" .. #keys .. "):", table.concat(keys, ", "))
return "seeded +" .. #added .. " -" .. #removed
