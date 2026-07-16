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
--   wallSlalom 蛇形墙带段数(左右交替,首段=wallSide 侧;过渡段落地穿越,声明的敌自动落过渡段)
--   jump     断口(挖空一段路,跳台楔过):true=全自动(位置=段内 45%,宽=冲刺跳距−余量,平段自动补唇)
--            或表 { lipDeg=楔角, lipLen=楔长, at=段内位置 0~1, gapStuds=手定宽, mercy=false 关救济组 }
--   wallBridge 墙桥(挖空一段路,唯一过法=贴左/右墙带):true=默认(45% 处断 70)
--            或表 { at=段内位置, gapStuds=断口宽, wallSide=1 右/-1 左 }
--   ★ 填回地面=删掉该段的 jump/wallBridge 字段重 compile;纯挖洞无过法的形态不提供
--     (主线必须可通过=机器人完赛证明,ADR-41;要"死洞"请用 CP 把路画绕开)
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

	-- M9b 首图(ADR-49,人类拍板 2026-07-16):120s / ~13350 studs / 12 beat。
	-- 体验目标:快速爽感+"感觉自己很强";主词汇=「冲刺×跳」三级呈现(教学20→爽段48→峡谷爆点58),
	-- 贴墙两处(b3 强制教学断桥 → b9 自愿捷径;生效前提=人类 Z2b 试骑过关),斩击=能量供给辅轴(直斩门)。
	-- ★ sec=弧长权重(非目标秒!)——速度沿程变化,秒权重会把段边界/内容错位 ~490 studs;
	--   真实设计时长见行注释。CP 三版草案=tools/build_track1_cp.lua(A 大回环/B 脊线滑降/C 双钳大S)。
	-- ★ P3c 已实现(ADR-49):wallBridge(断口不可跳+墙带跨越+机器人跳渡豁免)/ rampFork(半幅跳台楔+
	--   缺口+高架直桥,失败落回主线)/ jump={lipDeg,lipLen} 声明式楔角 / checkpoints 覆写 / 冲刺预算报告行。
	Track1 = {
		checkpoints = 5,                                                        -- 120s 赛道分段门 5(§7:3~5)
		finishAt = 0.885,   -- P3f 结局大门(人类直令 road985≈t0.885):峡谷落点双杀+心流后即冲线,其后=滑行区
		segments = {
			{ type = "start",  sec = 6.4 },                                     -- b1 发车 710(8s,τ0.9 渐近起步)
			{ type = "sweeps", sec = 10.8 },                                    -- b2 流畅弯组 1200(12s,弯心水晶钓走线)
			{ type = "cruise", sec = 9.0, wallBridge = { gapStuds = 120 }, wallSide = -1 }, -- b3 贴墙断桥教学(路断 70→120:人类反馈"仿佛冲刺能过")
			{ type = "combat", sec = 9.4, gates = 1, gateFull = true, shooters = 1, cores = 1 }, -- b4 教学闸门全幅(ADR-42 豁免;人类直令强制斩击)+斩=加油
			{ type = "cruise", sec = 8.1, jump = true },                        -- b5 冲刺跳教学 900(8s,自动唇10°=缺口~20)
			{ type = "thrill", sec = 14.4, jump = { lipDeg = 20, lipLen = 30, at = 0.25 }, shooters = 1 }, -- b6 长下坡+拱桥(P3j:断口挪到坡段 at0.25,拱=完整上半圆跨弧谷,人类点名 road455~479)
			{ type = "fork",   sec = 11.9, rampFork = true, cores = 1 },        -- b7 分叉A:冲刺跳台上高架捷径 1320(12s,失败落回主线)
			{ type = "cruise", sec = 7.2, shooters = 2 },                       -- b8 缓冲 800(8s;中后段敌 +1,人类直令)
			{ type = "fork",   sec = 11.9, wallSec = 6, wallSlalom = 3, slalomGapStuds = 90, wallSide = 1, shooters = 1 }, -- b9 蛇形贴墙 R/L/R+每带中央路断 90=必须贴墙跨越(人类直令删 road739~803 三窗)+过渡敌
			{ type = "cruise", sec = 5.4 },                                     -- b10 缓冲·峡谷口 600(6s,-32 下探+平直助跑台)
			{ type = "climax", sec = 15.3, jump = { lipDeg = 25, lipLen = 30 }, cores = 2, shooters = 1 }, -- b11 弧谷巨跳(P3h 半圆弧谷:弧底断开+25°跳板跨到对壁;落点双核+守点敌→心流)
			{ type = "finish", sec = 10.3 },                                    -- b12 心流冲线 1150(8s)
		},
		supply = { crystals = 20 }, -- 新手加密(§7 参考 12~18 的上浮=刻意;lint ⚠ 属预期;高架另 +2)
	},
}
