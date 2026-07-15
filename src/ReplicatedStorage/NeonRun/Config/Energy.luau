-- NeonRun / Config / Energy —— 冲刺能量经济(策划案 §4.5 / ADR-9,M5 启用;两轨制 ADR-37)
-- 铁律:危险渠道收益显著高于水晶;CrystalCap<Max 使满槽必靠冒险;禁纯被动回能;
--       墙=经济中性(贴墙/擦墙与一切墙体接触零入账,ADR-36/37)。
return {
	Max = 100,
	StartEnergy = 50,          -- 开局自带(第一脚冲刺零等待)
	-- 保底收入(蓝区):主线水晶,顺路骑过即得(充能环已删,ADR-37)
	CrystalGain = 18,          -- 每个水晶 +18
	CrystalCap = 80,           -- 水晶最多只能充到 80;最后一口必靠冒险
	CrystalMagnetRadius = 7,   -- 磁吸半径:进此半径即捕获入账并飞向玩家(M8.1,design §4.5)
	-- 技巧收入(红区)=战斗专营(ADR-37):斩杀/弹反/能量核/闸门。
	-- 旧非战斗收入全删:接触擦墙(NearMissGain/Window,ADR-23)、贴墙 +12/s(WallRideGainPerSec/MinSpeed,ADR-37);
	-- 近失回能(贴近不触)记 V2 候选,届时另立字段。
	SlashGain = 30,            -- 斩击 +30(远程敌本体/静态靶,破 Cap)
	ParryGain = 25,            -- 弹反 +25(破 Cap)
	CoreGain = 25,             -- 能量核 +25(ADR-18,破 Cap;摆偏线与危险位)
	GateGain = 15,             -- 能量闸门 +15(斩开通行;斩墙零收益,交互矩阵 §4.6)
	-- 消耗与心流
	SprintDrainPerSec = 22,    -- 冲刺耗 22/s
	MinIgnitionBurnSec = 0.4,  -- 最小点火时长:任一次激活至少燃烧 0.4s(不足烧完为止)——防碎点冲刺毁视听/封连点(ADR-13)
	IgnitionCost = 0,          -- 每次点火的一次性开销(AB 预留,默认 0=纯按时长扣;ADR-13)
	MoveRegenPerSec = 0,       -- 骑行涓流回能(AB 阀,默认关;仅当"底层能量归零时长占比"证明饥荒才开;静止回能永禁,ADR-17)
	FlowThreshold = 100,       -- 满槽=点燃资格(ADR-31;资格无限期保留,不衰减)
	FlowExitEnergy = 0,        -- 兑现式:烧完整管才结束(ADR-31 拍板;AB 备选 60=状态式高位维持)
	FlowBreakOnCollision = true, -- 碰撞即断心流(防"零接触冲整段")
	-- FlowSpeedBonus 死键已清(ADR-31):速度加成唯一事实源=Handling.Speed.FlowExtraMultiplier
	ReleaseGraceSec = 0.12,    -- 冲刺松键宽限(ADR-39,AB 0.1↔0.15):宽限内重按=心流不断;
	                           -- 能量与速度仍按真实按键状态走;刹车/燃尽立即断,不走宽限
}
