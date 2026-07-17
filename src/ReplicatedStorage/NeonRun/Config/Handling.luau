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
		-- ADR-46 GR2 速度手感;**2026-07-16 人类锁定=hot 终值**(回归基线=accept 钉 0/0,坑 30;旧手感=preset legacy)
		AccelTauSec = 0.9,      -- 渐近式加速:>0=加速方向指数逼近顶速(时间常数,越近越慢;0=关=线性即达)
		SteerDragFrac = 0.05,   -- 转向泄速:满转向时目标速度打此折(0.05=掉 5%,回正回升;0=关)
	},
	Steering = {
		TurnRateLowDeg = 110,   -- 低速最大转向角速度
		TurnRateHighDeg = 65,   -- 最高速时(2026-07-16 锁定;回归基线=accept 钉 55——锚点 69.3/55.0 按 55 校,坑 30)
		InputRampInSec = 0.07,  -- 输入渐变进入(2026-07-16 锁定;回归基线=accept 钉 0.12)
		InputRampOutSec = 0.20, -- 松键回正
	},
	Lean = {
		BodyRollMaxDeg = 30,    -- 2026-07-16 锁定(旧 22=preset legacy)
		RiderExtraDeg = 8,
		OvershootDeg = 6,       -- 回正过冲量(弹簧阻尼比由此反解;2026-07-16 锁定,旧 4)
		LerpSpeed = 13,         -- roll 弹簧自然频率(rad/s,越大越跟手;2026-07-16 锁定,旧 9)
		ForkMaxDeg = 18,        -- M3 前叉视觉最大转角
		AirPitchUpDeg = 6,      -- M3 起跳微抬头
		SuspensionDipPerVy = 0.008, -- M3 落地下沉量 = |vy|×此值(studs)
		SuspensionDipMax = 0.9,     -- M3 落地下沉上限(studs)
		SuspensionFreqHz = 5,       -- M3 悬挂回弹频率
		SuspensionDamping = 0.35,   -- M3 悬挂阻尼比(<1 有回弹)
	},
	Camera = {
		-- **2026-07-16 人类锁定=hot v5 终值**(五轮试玩定;旧默认=preset legacy 档,A/B 可回)
		FOVBase = 80,
		FOVSprint = 97,
		FOVLerpSec = 0.12,
		FollowLagSec = 0.07,    -- 位置弹簧滞后
		YawLagSec = 0.4,        -- 朝向滞后(慢半拍性格,人类定调;旧 0.22)
		Distance = 9,
		Height = 5,
		ShakeSprint = 0.24,     -- 冲刺震动幅度(studs)
		ShakeFreqHz = 11,       -- M3 震动频率
		LookAhead = 16,         -- 看向点前移距离
		LookUp = 3.2,           -- 看向点抬高
		WallSkin = 0.8,         -- M3 撞墙回退余量
		FlowFOV = 103,          -- 心流档
		FlowDistance = 12,      -- M3 心流档:近肩距离
		-- GR2 手感包(ADR-44):锁定值;0 仍=对应特性关(回归相机组断言不依赖这些键的具体值)
		SteerRollGain = 0.12,   -- ①转弯相机侧倾:up 绕视线轴滚 visualRoll×此值(负值=反向;人类:十分克制)
		SteerRollMaxDeg = 2,    -- ①侧倾上限(度;人类终裁 2°)
		SteerRollLerpSec = 0.3, -- ①b 侧倾低通:镜头侧倾慢进慢出、吃掉车倾弹簧过冲(0=直通)
		FOVSpeedGain = 0.10,    -- ②连续速度 FOV:每 stud/s 相对 Speed_Base 的度数增减(0=关)
		FOVPunchDeg = 6,        -- ③点火冲拳:冲刺上升沿 FOV 额外冲高(0=关)
		FOVPunchDecaySec = 0.30,-- ③冲拳线性回落时长
		LandDipPerVy = 0.008,   -- ④落地相机下沉 = |落地vy|×此值(studs;0=关)
		LandDipMax = 1.4,       -- ④下沉上限(studs;弹簧复用 Lean_Suspension* 与车体悬挂同律动)
		ShakeSpeedGain = 0.04,  -- ⑤速度比例震动:幅度 += 此值×(速度/Speed_Base)(0=关=纯冲刺开关式)
		AirPitchDownDeg = 5,    -- ⑥下坠俯视:滞空下落看点下移角(0=关)
		AirPitchLerpSec = 0.20, -- ⑥俯视进出平滑时长
		LatLagSec = 0.2,        -- ⑦横向独立插值:相机水平横向分量单独低通(车在画面里横移、缓缓回中;0=关)
		SteerLeadStuds = 2,     -- ⑧转向横移:正=镜头向转弯方向领先(车偏画面外、看穿弯内;人类终裁 2)
		SteerLeadLerpSec = 0.5, -- ⑧b 横移渐近时间常数:偏移量逐渐逼近目标位(GR2 缓冲;0=直通瞬移)
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
		FilletRadius = 7,       -- ADR-45 地面→侧墙底部圆角半径(截面四分之一圆;0=关=直角吸附;人类拍板域 6–8)
		ClimbEnabled = 1,       -- M6.6 爬墙动词(ADR-47):>入墙角度门的进场经裙板转垂直爬升;0=关=正面照旧撞
		ClimbMinToward = 5,     -- 爬墙入口朝墙分速下限(studs/s)
		ClimbGravityScale = 1,  -- 爬升重力系数(沿面分量;1=真实重力,越小冲得越高)
		ClimbDriftDecaySec = 0.6, -- 斜角入墙的切向残速衰减时长(横漂手感)
		ClimbConvertSteer = 0.5, -- 爬墙中 |A/D|≥此值=转侧骑(>1=禁用转换);转换走 C¹ 混合
		ClimbStallKeepSpeed = 0, -- 失速离墙保留的前速比例(0=清零防贴脸;>0 可能贴墙振荡,调参注意)
		ClimbReenterCDSec = 0.5, -- 失速后爬墙再入冷却(防落回裙板立刻回吸的微跳循环)
		ChainSmoothSec = 0.08,  -- ADR-43a 链关节平滑:yaw/姿态朝切向指数趋近时长(0=关=关节瞬跳)
		StickyArcBottom = 0,    -- P3i(ADR-49f)弧底粘滞:0=旧(滑到弧底即回地);1=仅高度带主动下压才驶出
		                        -- ——治低位贴墙"回地→再磁吸"循环(试玩"卡一下扭正");试验值走属性层
	},
	Sound = {
		EngineVolume = 0.4,
		EnginePitchMin = 0.75,  -- 静止/低速音调
		EnginePitchMax = 1.7,   -- 最高速音调
		IgnitionVolume = 0.6,
		IgnitePunchVolume = 0.35, -- 冲刺点火低频重击层(ADR-50m GR2"哐+咻";吃弹锤击件 9125672739 降速 0.45 两语义;0=关=纯 whoosh)
		WhooshVolume = 0.7,     -- 擦墙呼啸
		WhooshCooldownSec = 0.8,
		-- 战斗音(CombatVFX;ADR-50i 已转官方正式素材,assetId 见模块顶 SFX 表,0=静)
		SlashVolume = 0.6,      -- 挥刀 whoosh(官方 9114377700)
		HitVolume = 0.7,        -- 命中斩(官方 9125672726)
		ParryVolume = 0.8,      -- 弹反铿(官方 9125819216)
		GateVolume = 0.7,       -- 闸门碎裂玻璃音(官方 9114592102,ADR-50j)
		-- 流程与状态音(RaceSFX,ADR-50j;assetId 见模块顶 SLOTS 表,0=静)
		PickupVolume = 0.5,     -- 水晶拾取叮(仅入账>0 时响,满箱不捕获无声=真实反馈)
		CountdownVolume = 0.6,  -- 倒计时 beep(GO=同件升调 1.4)
		FinishVolume = 0.7,     -- 终点 sting(临时=beep 族低速,正经终点乐待选品)
		PlayerHitVolume = 0.8,  -- 吃弹重击
		RespawnVolume = 0.5,    -- 重生回取 whoosh
		FlowVolume = 0.6,       -- 心流升档 surge(点火 whoosh 升调 1.3)
		EmptyClickVolume = 0.5, -- 空箱干点火咔哒(M8.1 欠账清)
		EnemyFireVolume = 0.35, -- 敌火 pew(内置占位变调;正式激光待选品)
		MusicVolume = 0.35,     -- BGM「Night Run」循环(ADR-50n 官方 APM 183s;0=静;备选见 RaceSFX 头注)
	},
	VFX = {
		-- 冲刺速度线(BikeVFX 表现层):相机空间放射线,tele.sprinting 淡入淡出,贴图由远及近流动
		SpeedLineFlowSpeed = 1,     -- 贴图流速(正=屏心远处流向屏边近处=迎面冲来;越大越急)
		SpeedLineTexLen = 8,        -- 一段贴图的长度(studs,Wrap 重复)
		SpeedLineFadeInSec = 0.2,   -- 冲刺开始淡入时长
		SpeedLineFadeOutSec = 0.25, -- 冲刺结束/燃尽淡出时长
		SpeedLineMaxAlpha = 0.85,   -- 最亮时可见度(0~1)
		SpeedLineWidth = 1.2,       -- 线宽(studs,离镜头 6~30 studs 处的观感宽度)
		SpeedLineParticleRate = 80, -- 风粒子每秒条数(0=只留 Beam 层)
		SpeedLineParticleSpeed = 90,-- 风粒子飞行速度(studs/s,由前方朝镜头掠过)
		-- 战斗表现层(CombatVFX,ADR-50):程序化零资产;剑光=判定窗可视化(时长自动=Combat_InputBufferSec)
		SlashSweepSec = 0.12,       -- 挥砍横扫段时长(RiderRig 动作编排;车前剑痕弧已删=ADR-50f)
		HitBurstParticles = 24,     -- 命中爆点碎片数(0=关爆点与爆光)
		HitLightBrightness = 8,     -- 命中爆点光强(0.5s 内衰减归零)
		MagnetBeamSec = 0.12,       -- 视觉磁吸:剑光向命中目标甩出的光带存续(0=关;物理零参与)
		EnemySatSpinDeg = 90,       -- 敌人轨道卫星角速度(度/s;充能期 ×4)
		EnemyBobStuds = 0.6,        -- 敌人装饰悬浮起伏幅度(本体判定位置不动,纯视觉)
		BulletTrailSec = 0.22,      -- 子弹拖尾存续(颜色自动跟弹体,弹反变青同步)
		-- 拾取物造型+冲刺三件(ADR-50a):装饰颜色自适应本体 part.Color
		CrystalSpinDeg = 160,       -- 水晶碎晶环绕角速度(度/s;0=静态装饰省每帧写,移动端阀)
		CoreSpinDeg = 60,           -- 能量核卫星角速度(度/s;0=静态)
		ItemBobStuds = 0.35,        -- 拾取物装饰悬浮起伏幅度
		RiderEnabled = 1,           -- 骑手上车(ADR-50b):玩家 avatar 骑车+长剑;0=回旧停机坪(重进 Play 生效)
		SwordStreakSec = 0.35,      -- 刃尖窄条拖痕存续(ADR-50f:剑痕挂剑上,挥砍期随刃尖划弧;0=关)
		SprintUIAlpha = 0.85,       -- 冲刺 UI 总强度 master(0=关)
		SprintEdgeAlpha = 0.12,     -- 边缘微光最大不透明度(ADR-50k:仅冲刺期一点点;0=关)
		SprintEdgeBurstSec = 0.9,   -- 边缘流光点火包络(ADR-50l:冲刺开始亮起此秒数内退净,长按不常驻;0=回 50k 恒定微光)
		SprintBlurMax = 8,          -- 冲刺动态模糊上限(ADR-50h 实机改判进场;0=关=回 ADR-44 原判;移动端 M9.5 必验)
		SprintVignette = 0.45,      -- 冲刺暗角最大不透明度(双渐变近似径向;0=关;心流叠脉动)
		SprintJetRate = 90,         -- 冲刺尾焰粒子率(0=关;心流自动 ×1.4+变金)
		SprintWakeSec = 0.3,        -- 冲刺地面尾迹存续(0=关;心流变金)
		GateShardCount = 12,        -- 闸门碎裂碎片数(ADR-50j:斩开=板面切片外抛自旋淡出;0=关,移动端阀)
	},
	Combat = {
		-- 斩击判定(ADR-16):按键帧对注册目标做车体局部空间盒查询,禁 Touched
		HitboxForward = 12,     -- 判定盒:车前深度(studs)
		HitboxSide = 7,         -- 判定盒:左右各
		HitboxUp = 5,           -- 判定盒:上下各
		HitboxBack = 2,         -- 判定盒:车后
		InputBufferSec = 0.1,   -- 判定窗:出刀后窗内逐帧结算,进盒即中、持续可多段(ADR-16/48;设计关系≈RecoverySec 的 80%;源码默认=旧值,0.25 试玩值走属性层,锁定后写回)
		ParryWindowSec = 0,     -- 独立弹反窗应急开关(ADR-48):0=不区分(弹反与斩击同窗,人类拍板 2026-07-16);>0=子弹只在出刀后前段可弹(若试玩发现弹反白送再启)
		RecoverySec = 0.3,      -- 攻击间隔=空挥硬直(ADR-14:失误代价只在错过能量,永不减速;判定窗/间隔=连打覆盖率,0.25/0.3≈83%=人类拍板档)
		TelegraphRangeStuds = 55, -- 目标进入此距离触发音画预告(HUD/音效,非判定)
		DebugHitbox = false,    -- 【临时调试】斩击判定盒可视化(青=平时/绿=盒内有目标/白=命中帧;正式版前移除;P4d 人类直令默认关)
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
