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
	-- ===== M8.5 P2~P4(ADR-41)=====
	Content = {
		ItemHeight = 2,                -- 摆件中心距路面顶高(与 gauntlet/example 同高)
		CoreLateral = 12,              -- 能量核偏线横向偏移(±,危险位)
		ShooterLateral = 8,            -- 射手路侧偏移(±交替)
		GateCoverFrac = 0.4,           -- 闸门覆幅比例(≤半幅=主路线永不强制斩击,§7)
		MinCombatSpacingStuds = 60,    -- 相邻判定点最小弧长间距(同时决策数峰值≤2 的落地)
		StraightSearchStepStuds = 6,   -- 判定点入弯自动顺移的搜索步长
	},
	Wall = {
		Height = 30,                   -- 墙带高(=WallRig 基准)
		Thickness = 2,
		OffsetFromEdge = 2,            -- 墙内侧贴面距路缘
		SegmentLengthStuds = 40,       -- 直墙链每段长(曲线离散;单段=M6.5 直墙数据模型)
		OverlapFrac = 0.06,            -- 相邻墙段搭接比例(跨段交接的覆盖保证)
	},
	Jump = {
		SprintMarginStuds = 4,         -- 缺口=冲刺跳距−此余量("冲刺刚好",缺口设计法)
		LipAngleDeg = 10,              -- 平段无解时自动补的起跳唇坡度(断桥形态②)
		LipLengthStuds = 24,           -- 起跳唇沿路长度
		BallisticStepStuds = 2,        -- 弹道积分采样步长(对实际样条高度)
		MinLaunchSlopeDeg = 3,         -- 起跳切线坡度低于此值=平段(需补唇)
	},
	Checkpoints = {
		Count = 4,                     -- 分段门数量(§7:3~5 个/条;写 Track.CheckpointTs 属性)
	},
	Robot = {
		LookaheadStuds = 26,           -- 机器人循线前视距离
		SteerGain = 2.2,               -- 航向误差→转向输入增益
		CorrectEverySteps = 20,        -- 每 N 步用最近点校正弧长估计
		BudgetFactor = 3,              -- 步数预算=理想时间×此倍数(超时=不可完赛)
	},
}
