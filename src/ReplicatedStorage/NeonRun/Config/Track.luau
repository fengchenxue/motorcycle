-- NeonRun / Config / Track —— TrackBuilder 烘焙参数(M8.5 / 策划案 §7 / ADR-27/28)
-- 烘焙期数据(Edit 脚本消费),非运行时调参:与 Medals 一样直接 require 表(RaceTimer 先例),
-- 不走 ConfigLive Attributes——赛道生成是构建动作,参数改了要重烘焙,不适合属性面板热调。
-- 单位:studs / Sec / Deg。lint 阈值的事实源仍指回 Handling(转向)与 Energy(供给),此处只放几何。
return {
	Road = {
		Width = 40,             -- 宽走廊(§7 高速段宽走廊);薄走廊回归 Rig 另立
		SegmentLengthStuds = 12, -- 沿弧长每隔此距离生成一块路面件(越小越贴合弯,件数越多)
		Thickness = 2,          -- 路面件厚度
		SinkBelowSpline = 1.6,  -- 路面顶面比样条低此值(样条=行车中心线,车悬浮 HoverHeight=1.6 于顶面)
		Color = Color3.fromRGB(40, 44, 52),   -- 灰盒中性色(V1 禁美术)
		EdgeNeon = true,        -- 两侧霓虹条导航(§7 可贴墙面统一霓虹条);灰盒下仅占位色块
	},
	Lint = {
		-- 弯道半径下限=全速(心流)可过:阈值由 Handling 动态算(v_flow / ω_high),此处只留安全系数。
		RadiusSafetyFactor = 1.10, -- 实际弯半径需 ≥ 理论最小半径 × 此系数(留手感余量)
		CurvatureSampleStuds = 6,  -- 曲率数值微分的弧长步长(与 Combat.StraightMaxTurnDeg 的 8studs 同源思路)
	},
}
