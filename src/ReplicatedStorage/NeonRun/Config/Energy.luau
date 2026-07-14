-- NeonRun / Config / Energy —— 冲刺能量经济(策划案 §4.5 / ADR-9,M5 启用)
-- 铁律:危险渠道收益显著高于水晶;CrystalCap<Max 使满槽必靠冒险;禁纯被动回能。
return {
	Max = 100,
	StartEnergy = 50,          -- 开局自带(第一脚冲刺零等待)
	-- 保底收入(底层):主线水晶/充能环,顺路骑过即得
	CrystalGain = 18,          -- 每个水晶 +18
	CrystalCap = 80,           -- 水晶最多只能充到 80;最后一口必靠冒险
	-- 技巧收入(中顶层):危险渠道,显著高于水晶
	NearMissGain = 8,          -- 擦墙 +8
	NearMissWindow = 3.5,
	WallRideGainPerSec = 12,   -- 贴墙 +12/s
	SlashGain = 30,            -- 斩击 +30(远程敌本体/静态靶,破 Cap)
	ParryGain = 25,            -- 弹反 +25(破 Cap)
	CoreGain = 25,             -- 能量核 +25(ADR-18,破 Cap;摆偏线与危险位)
	-- 消耗与心流
	SprintDrainPerSec = 22,    -- 冲刺耗 22/s
	FlowThreshold = 100,       -- 满槽进入心流
	FlowExitEnergy = 60,       -- 心流迟滞下阀:能量降到此值才出心流(防闪烁)
	FlowSpeedBonus = 1.05,     -- 心流小幅加成(仅能量层标记,未接速度)
	FlowBreakOnCollision = true, -- 碰撞即断心流
	WallRideMinSpeed = 40,     -- 贴墙回能最低速度(防静止贴墙刷能=禁纯被动)
}
