--[[
NEON RUN — M8.1 Config 补种(Studio-only 状态对齐;命令栏或 MCP execute_luau 跑)
背景:Rojo 已同步 Energy.luau 源码,但 Config Attributes 是 Studio-only 状态(不在 git),
      新增字段需补种、删除字段需清除。ConfigLive.bind 只补"缺失"属性(保用户调参),
      不会删旧字段、不会覆盖已存在值,故删除/复位需本脚本显式处理。
效果:Energy 实例 +5 新属性(如已存在则跳过,保留你的调参),−2 旧擦墙属性(NearMissGain/Window)。
      Handling 的 Combat_* / GateLinkWindowSec 已在源码,rebind 自动补,无需本脚本。
]]
local RS = game:GetService("ReplicatedStorage")
local nr = RS:WaitForChild("NeonRun")
local eInst = nr.Config.Energy

-- 新增(仅当缺失才种,保留既有调参值)
local ADD = { MinIgnitionBurnSec = 0.4, IgnitionCost = 0, CrystalMagnetRadius = 7, MoveRegenPerSec = 0, GateGain = 15 }
local added = {}
for k, v in pairs(ADD) do
	if eInst:GetAttribute(k) == nil then eInst:SetAttribute(k, v); added[#added + 1] = k .. "=" .. tostring(v) end
end

-- 删除(接触擦墙回能字段,ADR-23)
local removed = {}
for _, dead in ipairs({ "NearMissGain", "NearMissWindow" }) do
	if eInst:GetAttribute(dead) ~= nil then eInst:SetAttribute(dead, nil); removed[#removed + 1] = dead end
end

-- 汇总当前 Energy 属性
local keys = {}
for k in pairs(eInst:GetAttributes()) do keys[#keys + 1] = k end
table.sort(keys)
print("M8.1 Config 补种完成")
print("  新增:", #added > 0 and table.concat(added, ", ") or "(全部已存在,未改)")
print("  删除:", #removed > 0 and table.concat(removed, ", ") or "(无旧字段,已干净)")
print("  Energy 现有属性(" .. #keys .. "):", table.concat(keys, ", "))
return "seeded +" .. #added .. " -" .. #removed
