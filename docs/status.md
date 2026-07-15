# STATUS — 现场状态(活文档)

> **维护规则:** 「快照」「Studio 侧状态」覆盖式(只放"现在时",历史看 git);「验收基准」「坑表」追加式。ADR 与修订史在 `docs/decisions.md`(只增不改)。

---

## 快照(覆盖式)

- **更新:** 2026-07-14,**M4.1 重生与碰撞确定性+定步长代码落地**(纯代码会话,Studio 未连,**验收未跑**;同日 M6.5 已落地并提交 cd9714e):①定步长(ADR-33)=新模块 `FixedStep`(60Hz 累加器,单帧≤3 步,溢出丢弃)+TestDrive 全模块喂固定 dt+BikeController 渲染位姿双缓冲/`renderInterpolate(alpha)`/`renderPos·renderYaw` 相机插值锚(teleport=快照不跨传送插值)+RaceTimer **计时=步数×1/60**;②物性白名单(ADR-28)=地面探针(悬浮/姿态/着陆/crash 跟地)只认 Terrain+Rideable(`rpGround` Include 动态维护),空中防穿分支:重摔非可骑面(入射≥55°且总速≥20)=硬撞转场、轻掠=钳顶悬滑不落地;③碰撞五规格=三线扫掠(中心+低位+左右前角 `Collision_SideOffset`)+**定档一次性**(接触上升沿分类,接触期不重判——根治石头忽弹忽减)+帧末去穿透钳制(白名单地面豁免——下坡贴地弧线不误钳;修卡出墙外)+碰撞 vy 永不为正;④重生锚点链(ADR-27)=新模块 `RespawnAnchors`(bake 三 lint+墙段上空排除(近样条 40 studs 才算)+persist Attachment 链+load/pick)+`_doRespawn` 弧长回取(≤当前,永不前进;首锚前回发车位=隐式 0 号锚)+0.5s 输入保护+**删检查点黄球 respawnCF 旧路径**(分段门≠锚点铁律)+硬核 gate 接口预留;⑤附带修复:teleport 不清 respawnT(R 撞上硬撞转场会二次传送,已修);RaceTimer resetCount=R+本局硬撞/坠落重生合计(作者牌语义)。新工具 `bake_anchors`/`seed_m4_1_config`/`accept_m4_1`(六组断言,自建 M41Rig@(-2400,200,-550):定档矩阵 9 角×3 速/石头 100×/变帧率 23·47·61·144Hz/锚点 lint/直线+坡顶);selfcheck +2 项;accept_m6_5 地板补 Rideable+坡顶预检自动补 Tag(坑 12)。同日早前:M6.5 贴墙段+ADR-39 宽限(cd9714e);ADR-40 试炼道 `build_gauntlet`;拍板清仓(宪法 v1.1);文档重构 v1.0。
- **重心:** V1 可玩 demo。队列:**Studio 线=①M8.1 验收回填 ②M6.5 验收(accept_m6_5+人工三项,必停)③M4.1 验收(seed→accept_m4_1)④gauntlet 首跑→bake_anchors**;**代码线下一棒=M8.5 P2~P4(TrackBuilder)** → M9a/b → M9.5 外部试玩 → M10 = demo 完成;M11/12/13 后置。
- **里程碑:** M0~M7 ✅(基准表);M2.1 待核实;M8 🔶 仅客户端(归 M12);**M8.1 代码✅待 Studio 验收**;**M6.5 代码✅待 Studio 验收+人工三项(必停)**;**M4.1 代码✅待 Studio 验收**;M8.5 P1 待 Studio 验证。
- **待拍板(人类):** ① 手感参数统一调(`Combat_*`/心流 AB 旋钮属性面板实时生效);④ M6.5 手感三项(**代码已落,试玩后拍板**):进入宽容度(`WallRide_EnterWindowStuds/EnterMaxAngleDeg/EnterTowardMinSpeed/EnterMinSpeed`)/高度带速率与"下坠漂移"开关(`WallRide_HeightBandSpeed`/`FallDriftPerSec`=0 关)/相机滚转速度(`WallRide_CamRollSec`);⑤ **最小点火×心流尾段**(现默认=延续,备选=尾段豁免;M9.5 AB,旋钮 `MinIgnitionBurnSec`)。**已拍板归档(2026-07-14):** 贴墙=B(ADR-36)/能量两轨(ADR-37)/射手只打前方(ADR-38)/输入分层+松键宽限(ADR-39)/节拍模板初版(§7)/名称沿用 NEON RUN/测试赛道 AI 全生成(ADR-40)。
- **已知问题:** ③ TrackShooter1 落位偏高(y=11,人类拖正即可,Tag 已带);④ 剑光/弹反/点火音效缺 assetId(事件钩子 swing/hit/parry/whiff/telegraph/fired/playerHit 已留;BikeAudio 点火 whoosh 已读有效 sprinting);⑥ `Combat_DebugHitbox=true` 临时判定盒可视化(青=平时/绿=盒内有目标/白=命中帧),正式版前移除;⑧ AttackSystem defaultKill 斩后仅隐形、不切 CanCollide → 闸门 Destructible 约定摆 CanCollide=false(无物理阻挡,gauntlet 已按此;"不斩即撞"版=kill/revive 切碰撞,归 M8.5 P3);⑨ **M6.5 墙态内不做障碍扫掠与坠落判定**(墙段按 soft lint 干净授权,墙上障碍/曲墙随 TrackBuilder P3);⑩ 下缘回地有 ≤悬浮高(1.6)的一帧上吸(落地贴地逻辑固有,人工验收留意);⑪ **轻掠非可骑面顶=悬浮 1.6 滑过、不落地不吸附**(M4.1 物性声明的边界结果:障碍不可骑;重摔≥55°且总速≥20 才判硬撞——试玩留意观感)。**已解待复核:** ①石头忽弹忽减(涌现分类)→**定档一次性**、②撞墙卡出墙外→**帧末去穿透钳制**(均归 accept_m4_1 验证);⑤ READY 脉冲+点火白闪(accept_m8_1);⑦ graze 回能路径已整条删除(Studio 残留属性由 seed 清)。
- **⚠️ 接手第一任务:** 带 Studio → ① `tools/seed_m8_1_config.lua`(Energy +5/−2)② `tools/accept_m8_1.lua` 八项,**回填基准表** ③ `tools/seed_m6_5_config.lua`(Energy +1/−2,Handling +8)→ `tools/accept_m6_5.lua` 十组(自建 WallRig),**回填** ④ `tools/seed_m4_1_config.lua`(Handling +6)→ `tools/accept_m4_1.lua` 六组(自建 M41Rig:定档矩阵 9 角×3 速/石头 100×/障碍防穿/变帧率 23·47·61·144Hz/锚点 lint+永不前进+输入保护/直线+坡顶),**回填** ⑤ `tools/selfcheck.lua`(energyM81Missing/energyStrayGraze/energyM65Grace/energyStrayWallRide/handlingM65WallRide/handlingM41 全 OK)⑥ Play 试骑:M8.1 表现层 + **M6.5 人工三项(必停,待拍板④)** + M4.1 抽查(重生 0.5s 输入保护体感/高刷屏插值顺滑)⑦ TrackBuilder P1 验证(下方清单)⑦b P1 过后 `tools/build_gauntlet.lua`(**贴墙件现为活墙段**)→ **`tools/bake_anchors.lua` 烘焙锚点链**(改赛道必重跑;selfcheck respawnAnchors>0)⑧ `tools/jumptable.lua` 出跳距表。纯代码 → 开工 **M8.5 P2**(design §E4)。

## TrackBuilder P1 验证清单(原 handoff 并入)

1. Edit 跑 `tools/example_testtrack.lua`:预期 6 控制点、`Workspace.NeonRun.Track.Road` 路面串、3 水晶+2 核带 Tag;首跑易错点:PartType 名/路面下沉量/lint 边界/开放式需 ≥4 控制点——修掉再往下。
2. `tools/selfcheck.lua`:`trackRoadSegs>0`、`rideableTags==路面段数`。
3. 弯道 lint 报 ❌ 过紧弯(<167 studs)则挪控制点重跑。
4. Play 试骑:发车→水晶 +18/斩核 +25→完赛。开放式=`Workspace.NeonRun.Closed=false` 统一驱动(运行时/TB/RaceTimer 三方同源;终点=样条末端 t≥0.997,强制单圈)。
5. 手摆速查(打 Tag 即生效,R 全复活):`EnergyCrystal` 骑过 +18(磁吸 7)/ `EnergyCore` 斩 +25 / `Destructible` 斩开(闸门 +15)/ `ShooterEnemy` 弹反 +25·斩本体 +30·骑穿免费(需重注册,稍麻烦)。
6. 未做:P2(lint 全套)/P3(自动摆放+墙带+断口段)/P4(分段门+锚点烘焙);微谷截面留 P2/P3。
7. **试炼道(ADR-40,P1 过后):** Edit 跑 `tools/build_gauntlet.lua`(幂等;非本脚本生成的旧 ControlPoints 自动备份进 ServerStorage.NeonRun.Backup)。核对:① 楔形坡薄边朝来车(反了改脚本头 `RAMP_FLIP=true` 重跑)② Z1 磁吸边界探针=+6 那颗骑中线该吸、+10 不该吸 ③ 闸门斩后隐形可穿(CanCollide=false 约定,已知问题⑧)④ 贴墙件 2(**M6.5 已落地:Rojo 同步后=磁吸活墙段**,骑近侧向切入即上墙;若想测普通墙碰撞,临时摘 WallRideSurface Tag)⑤ selfcheck 口径变化:rideableTags=路面段数+2(两坡)⑥ 弯道 lint ❌ 则按报告 t 值挪 CP04/CP05 外扩重跑。

## Studio 侧状态(覆盖式)

(截至 2026-07-14;M8.1 为纯代码会话,Studio 侧尚未同步验证)

- **⚠️ M8.1 待补种:** 跑 `tools/seed_m8_1_config.lua` → Config.Energy **+5 属性**(MinIgnitionBurnSec=0.4/IgnitionCost=0/CrystalMagnetRadius=7/MoveRegenPerSec=0/GateGain=15)、**−2 旧属性**(NearMissGain/Window),Energy 属性 15→18;Handling 无新增。分段门拱门=运行时客户端建(`Workspace.NeonRunSegmentGates`,非持久,CanQuery=false)。
- **⚠️ M6.5 待补种:** 跑 `tools/seed_m6_5_config.lua` → Config.Energy **+1**(ReleaseGraceSec=0.12)**−2**(WallRideGainPerSec/WallRideMinSpeed,墙=经济中性),Handling **+8**(WallRide_*)。测试台 **WallRig**=accept_m6_5 首跑自建(`Workspace.NeonRunWallRig`@(-1800,200,-600),地板 260×800(Rideable)+直墙 700×30 带 WallRideSurface Tag,常驻可复用)。**墙件摆放约定:直墙 Part,±X 大面=可贴面(两侧皆可),Z 轴=切向,Size=(厚,高,长);打 WallRideSurface Tag 即生效**(build_gauntlet Z5 已按此)。
- **⚠️ M4.1 待补种:** 跑 `tools/seed_m4_1_config.lua` → Handling **+6**(Collision_SideOffset=1.1/Respawn_AnchorSpacingSec=5/SetbackAnchors=0/InputProtectSec=0.5/AnchorMaxTurnDeg=6/AnchorClearAheadStuds=60)。测试台 **M41Rig**=accept_m4_1 首跑自建(`Workspace.NeonRunM41Rig`@(-2400,200,-550):地板 300×900(Rideable)+矩阵墙+三块旋转石头,常驻)。**白名单迁移(坑 12):一切可骑地面件必须带 Rideable Tag(Terrain 天然白名单),否则探针视为不存在→假失败**;accept 脚本沿坡顶路径自动补 Tag 并打印清单。**锚点链:赛道就绪后跑 `tools/bake_anchors.lua`**(读 ControlPoints → `Workspace.NeonRun.RespawnAnchors` 不可见 Attachment 链;改赛道必重跑;未烘焙场景重生走样条最近点 dev fallback)。
- **⚠️ 试炼道待生成:** `tools/build_gauntlet.lua`(P1 验证过后 Edit 跑)→ 13 CP(x≈700/y220/z 100→−3300)+ `Workspace.NeonRun.Gauntlet`(晶 11(含边界探针 2)/核 2/射手 2/闸门 1/贴墙面 2/坡 2/落点条纹 6/路牌 6);跑后旧走廊 Tag 件(TrackShooter 等)与试炼道并存注册,selfcheck 计数会变。
- Modules:repo=**16 件**(M6.5 +WallRideField;M4.1 +FixedStep/RespawnAnchors);Studio 以 selfcheck 实测为准;M4.1 改动=新增 2 件+既有 4 件原地改(BikeController/RaceTimer/CameraRig/试驾脚本),Rojo sync 即生效;Handling Attributes=75→89(WallRide_* 8 + M4.1 6 键待 seed 或首跑自补)。
- Workspace.NeonRun.**CombatRig**(@(-1200,200,-200) 直道 40×2×800,地板已打 Rideable):EnergyCore ×4/CombatShooterA·B/发车标线;主赛道 TrackShooter1@(-91,11,-440)、TrackShooter2@(-134,5,-515)、旧 M7 靶已核化 EnergyCore_1~3。
- Tag 计数:EnergyCore 7/ShooterEnemy 4/Destructible 1/Rideable 1/SlashEnemy 0/ParryEnemy 0。
- **Rojo serve 活跃**(repo 改动即时同步;`.Source` 推送只作断连兜底,推前先查)。
- Workspace.NeonRun:ControlPoints CP01~09(Index 定序)/SplineViz ~230 件/SpikeSite 7 台(y≈200~370)。
- Workspace.Motorcycle:PrimaryPart=BikeRoot(2×2.5×7),66 件焊接,Root 锚定;备份 ServerStorage.NeonRun.Backup。
- 模板脚本与 RaceGui 均 Disabled(勿删);测试走廊沙丘最高 y=138。

---

## 验收基准(追加式,回归对照)

| 测试 | 基准 | 备注 |
|---|---|---|
| 样条最近点(1000 随机) | 误差 0.140 stud,单查 0.036ms | M1 |
| 直线巡航(Rig1,400 帧) | drift=0,airborne=0,maxVy=0 | 常跑回归,Edit dt=1/60 |
| 输入渐变 | 进 0.133s/出 0.200s(±1 帧) | |
| 转向角速度锚点 | 100 速=69.3°/s;135=55.0;146=55.0(心流不降,分母锚 135) | |
| 薄墙 100 车道 @220/400 | 零穿透,停点差 0.01 | Rig4 |
| **坡顶起飞(Rig3,setup v2)** | 起点 (1500,202.6,130) 朝 -Z,全程冲刺,无样条,第二段落地即停:flights=2,airborne=117,maxFlight=85,landed=true,endPos=(1500,-17.5,-538.2)(两段滞空:落 FlatB→平台尽头二次飞出坠盆地) | **改贴地/起飞必复跑**;旧 setup(177/77)起步参数未记不可比,已废(坑 14) |
| 空中冲刺抉择(Rig3 第二跳 A/B) | 按住:速恒 135,endZ=-538.2,烧 31 能;松开:衰回 100,endZ=-490,零耗;**断桥差 48.2 studs** | ADR-30 |
| 心流锚点(ADR-31 八项) | 顶速实测 145.8;燃尽 272 帧后回 100;严格松键(78 能量再按只得 135);W+S 120 帧能量 80.00 不动;刹车瞬熄且停扣(89.0→89.0);心流跳 endZ=-555.1(较冲刺跳 +16.9) | 2026-07-14 全过 |
| 战斗 11 场景(CombatRig) | S1 直线零漂/S2 斩靶 +30 无损/S3 提前 6 studs 缓冲命中+核 +25/S4 斩射手 +30/S5 骑穿 Δv=0 vy=0/S6 弹反 fire@29·parry@57·kill@73 全程零减速/S7 吃弹速度比 0.750 不死/S8 空挥零减速+硬直拒二连/S9 一刀双杀 +60/S10 R 全重置/S11 重放帧号逐位一致 | 2026-07-14;能量断言先压 energy=20(坑 13);ADR-29 后弹反 +25 入账在击杀帧(f73) |
| M2.1 预期(待核实) | 刹车渐入 0.15s±1 帧;稳态 70%±1%;W+S 同按不耗能 | |
| M8.1 八项(代码已落,待回填) | 点火不足 0.4s 自动烧满;0 能量=空箱且速度不变;磁吸边界拾取;核/门/敌入账正确;斩墙 0;R 全重置;擦碰零入账;80 分段+READY | `tools/accept_m8_1.lua` |
| M4.1 预期 | 石头 rig 100 次全同+零入石帧;碰撞 vy 永不为正;定档矩阵 9 角(5~90,夹 20/55 边界)×3 速正确+零穿透零墙内帧;重摔非可骑面=硬撞/轻掠=悬滑不穿;锚点三 lint+射手剔除+弧长永不前进+0.5s 输入保护;**变帧率(23/47/61/144Hz)与 1/60 逐位一致**;直线+坡顶零变化 | `tools/accept_m4_1.lua` 六组,待跑;rig 地面件补 Tag=脚本自动 |
| M6.5 预期 | 墙态进出 100 次逐位一致;墙态全程能量零变动(巡航=常量/冲刺=与平地流水逐位同);空中进入;高位退出跳距对弹道模型;直线 400 帧+转向锚点 69.3/55/55+坡顶零变化;三退出(段尾/下缘/上缘);R 全重置 | `tools/accept_m6_5.lua` ①~⑦⑨⑩,待跑 |
| 松键宽限预期(ADR-39) | 松 6 帧(0.1s)重按心流在;松 10 帧(0.167s)断;能量流水与无宽限版逐位一致(除 flow 标志);刹车立即断;满槽按住燃尽 273 帧不变 | `tools/accept_m6_5.lua` ⑧,待跑 |
| 历史核证 | M3~M8 代码实证(2026-07-13 三 agent):相机三档/碰撞三档+转场冻结/能量心流/贴墙(旧)/体积盒判定/快照弹道均属实;M8 仅客户端 | 全文见 git d19ef25 |

---

## 坑与经验(追加式)

1. Run/Play 模式一切改动不持久;Instance 必须 Edit 期创建,运行期只验证。
2. 人类 Ctrl+Z 会回滚 Studio 侧改造(已发生:26 件被撤回锚定)。总成不动→先查漏网 Anchored;控制器只锚 Root。
3. 运动学控制器可在 Edit 固定 dt=1/60 同步仿真验收,不必进 Play。
4. 测试走廊沙丘最高 y=138;新建测试几何 y≥200。
5. 免费模型遗留:MakeJoints 已废弃;无授权音频刷屏(选官方公共素材并记录 assetId)。
6. MCP play 控制通道可能超时:请人类手动 Run/F5;Studio 重连后 id 会变,重新 set_active。
7. 配置模块更新用 `.Source` 原地赋值+重 bind;销毁重建丢用户调参。
8. 改贴地/起飞前读 ADR-4(decisions.md),改后复跑起飞回归(基准表)。
9. 控制台是第一诊断工具;无报错的"不动"多半是物理层(锚定/质量/约束目标)。
10. 人工验收点必停等人类;AI 无权凭感觉改手感参数。
11. 锚定件之间 Touched 不触发——检查点/拾取/战斗判定一律射线或体积查询。
12. 涌现分类的教训:石头忽"弹飞"忽减速=角度阈值给任意几何分类的必然结果;物性必须声明(Rideable,ADR-28);切白名单时给既有 rig 地面件补 Tag,否则起飞回归假失败。
13. 能量入账断言前先把能量压离 Max/CrystalCap(如 `energy.energy=20`),否则 +N 被截断产生假 FAIL。
14. 回归基准必须连 setup 一起记(起点/朝向/输入/停止条件),只记结果数字后人无法复现(Rig3 教训)。
15. execute_luau 的 require 缓存跨调用存活:`.Source` 更新后须 `require(实例:Clone())` 强制重编译;Rojo 同步同理。
16. 宪法漂移会咬人:拍板只记 ADR 不修宪,权威顺序会让过期宪法获胜。规则:**拍板即修宪**;来不及靠元规则(ADR 未并宪前以 ADR 为准)。
17. 墙态退出帧的高度带按键有 ramp-out 残留(InputRampOutSec),空中转向会把弹道拐向墙、可能落上薄墙顶面:验收剧本出墙即回正 steer(accept_m6_5 drive());真实玩家松键同样有 0.2s 残留,人工验收留意上缘弹出手感。
18. 阈值角上的浮点抖动:`asin(sin(x))` 有 ±ε,定档验收矩阵永远避开 20°/55° 精确边界(用 18/22、52/57 夹逼),否则边界用例随机翻档=假失败。
19. teleport 曾不清 respawnT(R 撞上硬撞转场→重开后被旧倒计时再传送一次,已修):涉及"转场+传送"的测试先断言 respawnT 已清;新增传送路径记得清 crashT/respawnT/inputProtectT 三件套。
20. 白名单迁移的连锁:凡出现"车沉进地板/直线回归假失败",第一嫌疑=地面件缺 Rideable Tag(坑 12 的 M4.1 版);accept 脚本建 rig 时必须随手打 Tag,老场景跑 accept 的坡顶预检会自动补并打印。
