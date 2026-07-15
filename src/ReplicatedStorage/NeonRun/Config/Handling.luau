-- NeonRun / Config / Handling —— 手感基准参数(策划案 §5)
-- 角度 Deg(度),时间 Sec(秒),速度 studs/s
-- 运行时经 ConfigLive 绑定为本实例 Attributes:属性面板即调参面板
return {
	Speed = {
		Base = 100,
		SprintMultiplier = 1.35,
		FlowExtraMultiplier = 1.08, -- 心流冲刺升档(ADR-31 已接线,总速≈146;AB 备选 1.05)
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
		FrontOffset = 3.5,        -- 车头到中心距离(扫掠余量)
		SideOffset = 1.1,         -- M4.1 三线扫掠:左右前角线的横向偏移(ADR-28)
		-- 碰撞三档角度阈值(速度方向与墙面夹角:0=平行擦过,90=垂直正撞)
		HardMinAngleDeg   = 55,   -- ≥ 撞死(滑行+顺法线打转→重生)
		BounceMinAngleDeg = 20,   -- ≥ 弹开(反射方向+火花,继续行驶);以下=擦墙
		HardMinSpeed = 20,        -- 低于此速度即使陡角也不撞死,降级为弹开(低速贴墙不惩罚)
		GrazeSlowdown = 0.92,     -- 擦墙每帧泄速系数
		-- 撞死档:滑行+顺法线打转,结束才重生
		CrashSlideSec      = 0.5, -- 撞死后滑行+打转时长
		CrashSpinDegPerSec = 540, -- 视觉打转角速度(约1.5圈/秒,只写root.CFrame,相机不转)
		CrashSlowdown      = 0.85,-- 撞死滑行每帧泄速系数
		-- 弹开档:速度沿墙面法线反射
		BounceSlowdown = 0.75,    -- 弹开后保留的速度比例(0.75=掉25%)
		BounceCooldown = 0.25,    -- 弹开冷却(防贴墙每帧连弹)
		FallBelowStuds = 80,      -- M4 低于样条最近点此深度判定坠落
	},
	Respawn = {
		TransitionSec = 0.4,
		SpeedRestore = 0.6,
		-- M4.1 烘焙锚点链(ADR-27)
		AnchorSpacingSec = 5,       -- 采样间距(秒;烘焙换算 ×Speed_Base=studs;AB 5↔15)
		SetbackAnchors = 0,         -- 重生额外回退锚点数(拍板=0)
		InputProtectSec = 0.5,      -- 重生输入保护窗口(§4.4)
		AnchorMaxTurnDeg = 6,       -- lint②:±10 studs 切线转角上限(直线段判据)
		AnchorClearAheadStuds = 60, -- lint③:锚点前方净空(无障碍/无射手)
	},
	WallRide = {
		-- M6.5 贴墙段(ADR-36 授权段磁吸;§4.9)。墙=经济中性,收入键不存在(ADR-37)。
		EnterWindowStuds = 6,   -- 触发区厚度:距可贴墙面此距离内可入墙(侧向窗口)
		EnterMinSpeed = 60,     -- 进入速度阈值(studs/s;低速蹭墙不入墙,按普通碰撞走)
		EnterMaxAngleDeg = 45,  -- 航向与墙切向夹角 ≤ 此值才入墙(更陡=正撞,走碰撞三档)
		EnterTowardMinSpeed = 5, -- 朝墙横向分速 ≥ 此值才入墙(平行路过/驶下下缘不误吸)
		BlendSec = 0.2,         -- 进入位置姿态混合时长(§4.9 拍板 0.2s)
		HeightBandSpeed = 26,   -- A/D 高度带滑移速率(studs/s;人工验收项)
		FallDriftPerSec = 0,    -- 下坠漂移:>0=墙上持续下滑此速率(默认 0=关;M9.5 AB/人工验收)
		CamRollSec = 0.25,      -- 相机滚转平滑时长(roll≤90°;人工验收项)
		ChainMaxTurnDeg = 8,    -- M8.5 直墙链跨段交接:相邻段面/切向夹角上限(ADR-41 曲墙=离散直墙链)
	},
	Sound = {
		EngineVolume = 0.4,
		EnginePitchMin = 0.75,  -- 静止/低速音调
		EnginePitchMax = 1.7,   -- 最高速音调
		IgnitionVolume = 0.6,
		WhooshVolume = 0.7,     -- 擦墙呼啸
		WhooshCooldownSec = 0.8,
	},
	Combat = {
		-- 斩击判定(ADR-16):按键帧对注册目标做车体局部空间盒查询,禁 Touched
		HitboxForward = 12,     -- 判定盒:车前深度(studs)
		HitboxSide = 7,         -- 判定盒:左右各
		HitboxUp = 5,           -- 判定盒:上下各
		HitboxBack = 2,         -- 判定盒:车后
		InputBufferSec = 0.1,   -- 提前按键缓冲:窗口内目标进盒仍判命中(ADR-16)
		RecoverySec = 0.3,      -- 空挥硬直(ADR-14:失误代价只在错过能量,永不减速)
		TelegraphRangeStuds = 55, -- 目标进入此距离触发音画预告(HUD/音效,非判定)
		DebugHitbox = true,     -- 【临时调试】斩击判定盒可视化(青=平时/绿=盒内有目标/白=命中帧;正式版前移除)
		StraightMaxTurnDeg = 3, -- 布置 lint:目标所在点 8studs 转角 < 此值才算直线段
		GateLinkWindowSec = 2.5, -- V2 预埋:节点联动墙开启时长(ADR-19)
		-- 远程敌与快照弹道(ADR-21/22)
		ShooterRangeStuds = 170, -- 玩家进入此距离且位于玩家前方才开火(迎面弹可读)
		ShooterTelegraphSec = 0.45, -- 开火前充能预告时长(本体发光膨胀)
		ShooterFireIntervalSec = 1.8, -- 射击间隔(确定性节拍)
		BulletSpeed = 150,      -- 子弹速度(快照弹道,发射后恒定,永不追踪)
		BulletRadius = 3.2,     -- 子弹命中玩家的判定半径
		BulletLifeSec = 4,      -- 子弹寿命(超时消散)
		BulletHitSlowdown = 0.75, -- 未弹反命中=减速一档(不死;碰撞永不产生垂直速度)
		ParryReflectSpeed = 260, -- 弹反回飞速度(改写目标为射手,演出层)
	},
}
