-- NeonRun / Config / TrackSpecs —— 赛道声明表(M8.5 / ADR-41 混合制 / §7 节拍语法)
-- 空间的归空间:路线形状(宏观形/坡/高差)=人类拖 Workspace.NeonRun.ControlPoints。
-- 结构的归结构:节拍/区段/供给=本表(repo 版本化,可 diff 可复现;改了重跑 TrackBuilder.compile)。
--
-- 区段字段:
--   type     区段类型(报告与默认值用):start|sweeps|combat|thrill|fork|climax|finish|cruise
--   sec      目标节拍时长(§7 模板;各段按 sec 权重归一到实际弧长——画的路短于/长于模板总时长
--            不报错,lint 回报"实际≈Xs vs 模板 Ys",要不要改路由人裁)
--   crystals 本段水晶数(蓝区;不写则从 supply.crystals 按弧长摊到非战斗段)
--   shooters/cores/gates  红区内容(战斗收入;判定点只落直线点,入弯自动顺移,ADR-41)
--   wallSec  贴墙捷径:沿本段生成 ≈sec 等效弧长的直墙链(wallSide=1 右/-1 左;M6.5 摆放约定)
--   jump     断口:按实际几何弹道反解缺口宽(主线缺口=冲刺刚好−余量;平段自动补起跳唇)
-- supply.crystals:全轨蓝区口粮预算(§7 参考密度 晶 12~18/核 3~6/敌 3~5/闸 0~2)。
return {
	-- §7 节拍配比初版模板(90s;v1.1 拍板):爽 35% / 技巧 30% / 战斗 15% / 缓冲 20%
	Default = {
		segments = {
			{ type = "start",  sec = 8 },                                    -- 发车直线:读路+水晶列
			{ type = "sweeps", sec = 14 },                                   -- 技巧弯组(全速 S 弯)
			{ type = "combat", sec = 10, shooters = 2, cores = 1 },          -- 战斗直线(敌×2+核)
			{ type = "thrill", sec = 12, jump = true },                      -- 爽段(长下坡+坡顶跳;坡=CP 画)
			{ type = "fork",   sec = 10, wallSec = 3, wallSide = 1 },        -- 分叉段:主线宽弯+右侧贴墙捷径
			{ type = "sweeps", sec = 14, gates = 1 },                        -- 技巧弯组变奏+能量闸门
			{ type = "climax", sec = 12, wallSec = 4, wallSide = -1, cores = 2, shooters = 1 }, -- 高潮连段:墙段+落点双核+守点敌(敌合计 3,合参考密度)
			{ type = "finish", sec = 10 },                                   -- 冲线直线
		},
		supply = { crystals = 14 },
	},
}
