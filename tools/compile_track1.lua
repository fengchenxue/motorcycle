--[[
NEON RUN — Track1 一键重建(Edit 模式,命令栏或 MCP execute_luau;幂等)
★ 什么时候跑:改了 CP 球 / 改了 Config/TrackSpecs.luau / 改了 Config/Track.luau 之后。
★ 修改赛道的正确姿势(ADR-41 混合制,三层各管各的;直接删 Track 里的路面板=白删,重建就回来):
  ① 宏观形/坡/高差 —— 拖 Workspace.NeonRun.ControlPoints 里的 CP 球(可增删,按 Index 排序;
     删一段=把那一带 CP 删掉或拉直)→ 跑本脚本重建。
  ② 节拍/内容/供给 —— 改 repo 的 src/.../Config/TrackSpecs.luau(每段 sec 权重/jump 楔角/
     wallBridge/wallSlalom/敌核闸数量都在这;Rojo 已同步,保存即到 Studio)→ 跑本脚本。
  ③ 微调摆件 —— Studio 直接拖件+打 Tag 即生效(ADR-40);⚠️ 必须放在自建文件夹
     (例:Workspace.NeonRun.HandPlaced),Track 文件夹内的一切会被本脚本整体重建吞掉。
★ 想删掉整个节拍段:TrackSpecs.Track1.segments 里删那一行(其余段按 sec 权重自动摊满全长),
  同时把对应区域的 CP 拉直/缩短;只删 CP 不删 spec=所有段边界按比例前移,内容会跟着挪,提前有数。
]]
local TB = require(game.ReplicatedStorage.NeonRun.Modules.TrackBuilder:Clone()) -- 坑15
local report = TB.compile({ spec = "Track1", closed = false })
print(TB.formatReport(report))
