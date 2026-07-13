-- NeonRun / Config / Handling —— 手感基准参数(策划案 §5)
-- 角度 Deg(度),时间 Sec(秒),速度 studs/s
-- 运行时经 ConfigLive 绑定为本实例 Attributes:属性面板即调参面板
return {
	Speed = {
		Base = 100,
		SprintMultiplier = 1.35,
		FlowExtraMultiplier = 1.08,
		RampUpSec = 0.25,       -- 提速到目标的时间(冲刺点火感)
		RampDownSec = 0.35,     -- 降速时间
		BrakeEnabled = true,    -- M2.1 轻刹实验开关(ADR-7,待 AB)
		BrakeFloor = 0.7,       -- M2.1 轻刹稳态 = Base × 此值(不停死不倒车)
		BrakeRampInSec = 0.15,  -- M2.1 刹车渐入:巡航→BrakeFloor 恰用此时长;松开走 RampUpSec 回升
	},
	Steering = {
		TurnRateLowDeg = 110,   -- 低速最大转向角速度
		TurnRateHighDeg = 55,   -- 最高速时
		InputRampInSec = 0.12,  -- 输入渐变进入(重量感)
		InputRampOutSec = 0.20, -- 松键回正
	},
	Lean = {
		BodyRollMaxDeg = 22,
		RiderExtraDeg = 8,
		OvershootDeg = 4,       -- 回正过冲量(弹簧阻尼比由此反解)
		LerpSpeed = 9,          -- roll 弹簧自然频率(rad/s,越大越跟手)
		ForkMaxDeg = 18,        -- M3 前叉视觉最大转角
		AirPitchUpDeg = 6,      -- M3 起跳微抬头
		SuspensionDipPerVy = 0.008, -- M3 落地下沉量 = |vy|×此值(studs)
		SuspensionDipMax = 0.9,     -- M3 落地下沉上限(studs)
		SuspensionFreqHz = 5,       -- M3 悬挂回弹频率
		SuspensionDamping = 0.35,   -- M3 悬挂阻尼比(<1 有回弹)
	},
	Camera = {
		FOVBase = 72,
		FOVSprint = 88,
		FOVLerpSec = 0.2,
		FollowLagSec = 0.10,    -- 位置弹簧滞后
		YawLagSec = 0.22,       -- M3 朝向滞后(转向慢半拍)
		Distance = 16,
		Height = 6,
		ShakeSprint = 0.15,     -- 冲刺震动幅度(studs)
		ShakeFreqHz = 11,       -- M3 震动频率
		LookAhead = 10,         -- M3 看向点前移距离
		LookUp = 2,             -- M3 看向点抬高
		WallSkin = 0.8,         -- M3 撞墙回退余量
		FlowFOV = 92,           -- M3 心流档预留(M5 心流状态接入后生效)
		FlowDistance = 12,      -- M3 心流档预留:近肩距离
	},
	Ground = {
		HoverHeight = 1.6,
		RayLength = 8,
		AlignLerpSpeed = 10,
		WheelBase = 5,          -- 前后探测点间距
	},
	Physics = {
		Gravity = 260,          -- 街机重力(约1.3x)
		MaxSlopeDeg = 50,       -- 可骑坡度上限
		MaxStepUp = 1.5,        -- 单帧台阶上限(基础值,随速度按坡度放宽)
		DetachTolerance = 0.25, -- 弹道脱离阈值(坡顶起飞灵敏度)
	},
	Collision = {
		SkinWidth = 0.6,
		FrontOffset = 3.5,      -- 车头到中心距离(扫掠余量)
		GrazeMaxAngleDeg = 30,
		GrazeSlowdown = 0.92,
		HardMinSpeed = 20,      -- M4 低于此速度的陡角碰撞不触发重生(低速贴墙不惩罚)
		FallBelowStuds = 80,    -- M4 低于样条最近点此深度判定坠落
	},
	Respawn = {
		TransitionSec = 0.4,
		SpeedRestore = 0.6,
	},
	Sound = {
		EngineVolume = 0.4,
		EnginePitchMin = 0.75,  -- 静止/低速音调
		EnginePitchMax = 1.7,   -- 最高速音调
		IgnitionVolume = 0.6,
		WhooshVolume = 0.7,     -- 擦墙呼啸
		WhooshCooldownSec = 0.8,
	},
	Attack = {
		-- M7 攻击/弹反(ADR-8):单键·自动锁定·时机判定·斩击点只在直线段
		LockRangeStuds = 55,    -- 进入此距离(沿接近方向)目标锁定+音画预告
		HitWindowStuds = 14,    -- 命中窗口:车距目标中心 ≤ 此值时按键=成功(时机带宽)
		MissSlowdown = 0.7,     -- 失误(窗口外按键)一次性减速系数
		CooldownSec = 0.35,     -- 攻击键冷却(防连点)
		StraightMaxTurnDeg = 3, -- 目标合法性:所在点 8studs 转角 < 此值才算直线段(布置期校验)
		ParryReflectSpeed = 220,-- 弹反子弹回弹速度(表现用)
	},
}