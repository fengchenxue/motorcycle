# STATUS — 现场状态(活文档)

> **维护规则:** 「快照」「Studio 侧状态」覆盖式(只放"现在时",历史看 git);「验收基准」「坑表」追加式。ADR 与修订史在 `docs/decisions.md`(只增不改)。

---

## 快照(覆盖式)

- **更新:** 2026-07-15(第五会话:**圆角语义纠偏 → ADR-45 地面→侧墙底部圆角过渡落地并部署 Z5**)。人类澄清:圆角="平地开上侧墙"的立面过渡,不是平面墙拐弯(ADR-43 平面弯=误读,展示台已拆,其"折线行走"跨段机制保留);.rbxl 入库=人类拍板放弃;M8.5 accept 仍待跑;ADR-43/44 已并宪(design v1.3),**ADR-45 已归档、待并宪(下次修订必并入,含 design 中 ADR-43 弯角语义的同步修正)**。
  ① **底部圆角(ADR-45,新配置键 `WallRide_FilletRadius`=7,0=关=旧直角吸附):** 墙态截面按四分之一圆弧参数 φ 走——入墙点在弧内则位姿从近直立起步(实测 φ0≈15°、up·Y=0.965,90° 突变消灭),A/D 高度带弧内=沿弧爬降(爬到贴墙 17 帧=理论),弧底驶出=平顺回地;弧顶↔直墙双向衔接 h 连续;走链探针期望贴面距随 φ 放宽;up 有效法线进遥测=相机 roll 渐进。**白盒=墙根 Rideable 裙板**(6 片/90° 法线渐变,几何与物理同源半径,不占 WallRideSurface Tag),生成器 `tools/build_wall_fillet_skirts.lua`(默认目标=Z5 两墙);验收 `tools/accept_wallfillet.lua`。(ADR-43 平面弯工具 `build_wallcorner_rig`/`accept_wallcorner` 保留=链行走回归用。)
  ② **验证(第五会话):** accept_wallfillet **17/17**(⓪钉 0=直角旧语义锚/①入墙首帧近直立/②单调滚到贴墙+越弧顶+速度恒 100/③下行穿弧 ≤8 帧回地零硬撞/④弧内驻留零漂/⑤确定性逐位);三个既有 accept(m6_5/m8_5/wallcorner)钉 `FilletRadius=0` 保直角基线——**m6_5 复跑 42/42、wallcorner 复跑 15/15 零回归**;调参快照先存后还原(BlendSec/CamRollSec 保 0.4,坑 27);Z5 两墙墙底与路面对齐差 0.00 实测。首跑 15/2 双败均为剧本缺陷(跑超墙容量/进场 ramp-out 残留=坑 17 入墙侧变体),控制器零改动。
  ③ **GR2 手感包(ADR-44,第四会话):** CameraRig 六表现特性(转弯侧倾/连续速度FOV/点火冲拳/落地下沉/速度比例震动/下坠俯视)全 Config 新键、**默认 0=关=旧行为逐位不变**;TunePanel +13 滑条;预设切换 `tools/preset_feel.lua`(stock/steady/hot,先回源码值再覆盖=幂等)。**验证:** 冒烟 **12/12**(默认关=相机 UpVector.X 精确 0+内部 upVec=(0,1,0)+dip/airPitch/punch 全零;六特性方向断言含侧倾左右对称;属性现场还原)+ **accept_m6_5 复跑 42/42 零回归**(新 CameraRig 实测,坑 27 快照包裹、坑 28 幂等推送);Handling/CameraRig/TunePanel `.Source` 推平=repo 逐字节(djb2 后验);**Handling Attributes 106→116**(新键 10 个种齐,人类调参值 BlendSec/CamRollSec=0.4 全保留)。**定值待人类 Play 试玩(待拍板⑨)。**
- **中断点(已复核):** 上会话 `accept_m8_5` 派发瞬间 Studio 掉线(脚本未开始执行,场上 ControlPoints 未动),该验收仍待跑。**✅ 场景保存完好、未回滚**——本机 selfcheck 复核:18 模块/Handling 106/Energy 17/Rideable 294/CP 13/Gauntlet 37/StreamingEnabled=false 全绿,上会话 Edit 态(.Source 推送/Rig3+Basin Tag/WallRig/M41Rig)均在;逐字节哈希未复跑,动代码前按接手任务补。**遗留偏差:** 一个游离 `WallRide_L`(带 WallRideSurface Tag、size 同 Gauntlet 版)直挂 Workspace 根 @(691,245,-3240),疑协作者(Lee_WL67)/旧 build 残留,赛道验收前确认清理(坑 21)。
- **重心:** V1 可玩 demo。**下一棒=带 Studio 清尾:** ① `accept_m8_5`(八组,自动备份还原 CP)② 重跑 `build_gauntlet`(实体闸门对齐 ADR-42)→ `bake_anchors` ③ `selfcheck` 全 OK ④ `jumptable` 出跳距表 ⑤ Play 全功能试骑+**M6.5 人工三项(必停)**+速度线三项拍板+**GR2 手感包预设 A/B(待拍板⑨)** ⑥ **Z5 圆角过渡试骑+半径拍板(待拍板⑧;.rbxl 入库已放弃,人类拍板 2026-07-15)** → 然后 **M9a/b 首图**(人类导演)→ M9.5 → M10 = demo;M11/12/13 后置。
- **里程碑:** M0~M7 ✅(基准表);M2.1 待核实;M8 🔶 仅客户端(归 M12);**M8.1 ✅ Studio 验收 20/20(2026-07-15)**;**M6.5 自动验收 ✅ 42/42,剩人工三项(必停)**;**M4.1 ✅ Studio 验收 29/29**;**M8.5 accept 首跑 15/17**(compile 功能全绿;2 败=迷你轨测试台缺陷,代码零嫌疑,待修台重跑);试炼道✅(2026-07-15 build_gauntlet 已恢复正式赛道 285 段+bake 锚点 4)Play 全功能试骑=下一棒(人工必停);**表现层速度线:代码✅冒烟✅,待人工拍板**;**GR2 相机手感包(ADR-44):代码✅推送✅冒烟 12/12✅回归 42/42✅,默认关,待人工定值(待拍板⑨)**。
- **待拍板(人类):** ① 手感参数统一调(`Combat_*`/心流 AB 旋钮属性面板实时生效);④ M6.5 手感三项(**自动验收已全绿,试玩后拍板**):进入宽容度(`WallRide_EnterWindowStuds/EnterMaxAngleDeg/EnterTowardMinSpeed/EnterMinSpeed`)/高度带速率与"下坠漂移"开关(`WallRide_HeightBandSpeed`/`FallDriftPerSec`=0 关)/相机滚转速度(`WallRide_CamRollSec`);⑤ **最小点火×心流尾段**(现默认=延续,备选=尾段豁免;M9.5 AB,旋钮 `MinIgnitionBurnSec`);⑥ **Streaming 根本方案**(现=灰盒期关闭;重开需样条锚点持久化 `ModelStreamingMode=Persistent` 或坐标迁 ReplicatedStorage,**移动端长赛道 demo 前必解**,坑 24);⑦ **速度线三项**(线布局 `BikeVFX.SPEEDLINE_OFFSETS`/粒子浓度 `VFX_SpeedLineParticleRate`/流速 `VFX_SpeedLineFlowSpeed`,属性面板实时调)。⑧ **地面→侧墙圆角半径**(活属性 `WallRide_FilletRadius`∈[6,8] 现 7,属性面板实时生效;0=关回直角吸附;改半径后重跑 `tools/build_wall_fillet_skirts.lua` 同步裙板几何;Play 试骑 Z5 后拍板)。⑨ **GR2 手感包三件(ADR-44)**:A/B 法=Play 里跑 `tools/preset_feel.lua`(改顶部 PRESET 切 stock/steady/hot,幂等)+T 面板微调:(a)档位取舍与六旋钮定值(侧倾 `Camera_SteerRollGain`(方向反了改负值)/速度FOV/冲拳/落地下沉/速度震动/下坠俯视)(b)**相机性格**:焊死跟随(YawLag 0.08~0.12,GR2 感)↔ 慢半拍(0.22,现状重量感)(c)**FOV 上限真机(手机)晕动验证**(hot 档 FOVSprint 97);满意后喊"锁定当前参数"→AI 写回源码+更新基准锚点(转向 69.3/55.0 与渐变 0.133s 随 Steering 键变)。**已拍板归档(2026-07-14):** 贴墙=B(ADR-36)/能量两轨(ADR-37)/射手只打前方(ADR-38)/输入分层+松键宽限(ADR-39)/节拍模板初版(§7)/名称沿用 NEON RUN/测试赛道 AI 全生成(ADR-40)/赛道声明混合制(ADR-41,选 C)/满蓝不捕获+墙门三型(ADR-42)。**已拍板归档(2026-07-15):** 地面→侧墙=底部圆角过渡(ADR-45,人类澄清直令;ADR-43 平面弯=误读改判,折线行走机制保留)/.rbxl 入库放弃(如需灾难还原点另议)/GR2 相机手感包六特性默认关+预设 AB(ADR-44,定值=待拍板⑨)。
- **已知问题:** ③ TrackShooter1 落位偏高(y=11,人类拖正即可,Tag 已带);④ 剑光/弹反/点火音效缺 assetId(事件钩子已留;BikeAudio 点火 whoosh 已读有效 sprinting);⑥ `Combat_DebugHitbox=true` 临时判定盒可视化,正式版前移除;⑧〔已解,ADR-42〕defaultKill 切物性;闸门=实体墙摆放(**场上 gauntlet 闸门仍旧非实体版,重跑即对齐**);⑨ M6.5 墙态内不做障碍扫掠与坠落判定(墙段按 soft lint 干净授权);⑩ 下缘回地有 ≤悬浮高(1.6)的一帧上吸(人工验收留意);⑪ 轻掠非可骑面顶=悬浮 1.6 滑过、不落地不吸附(**已由 accept_m4_1③ 平顶障碍用例确定性复现:hover>0、零穿透、不落地**;悬滑窗口仅 0.64 studs,斜面石头掠顶=正确判硬撞;试玩留意观感)。**已解:** ①石头忽弹忽减→定档一次性、②撞墙卡出墙外→帧末去穿透钳制(**accept_m4_1 29/29 实证**);⑤ READY 脉冲+点火白闪(accept_m8_1 20/20 实证);⑦ graze 回能路径已删;Streaming 提前完赛→已关闭(根本方案=待拍板⑥)。**推迟项(backlog):** 墙带默认弯内侧/compile 报告加"冲刺时间预算"行(M9 前顺手)/分段门参照改机器人 split/**"能量归零时长占比"埋点(M9.5 必需)**/CrystalField 冷却常量入 Config。
- **⚠️ 接手第一任务(2026-07-15 本机推进:⓪~④ 全绿,余 Play+存档):** ⓪游离墙已自消失✅ ① `accept_m8_5` 首跑 15/17(2 败=迷你轨测试台缺陷,基准表)✅ ② `build_gauntlet` 正式赛道恢复(285 段/lint worstR=195.5/实体闸门)+ `bake_anchors` 锚点 4✅ ③ `selfcheck` 全绿✅ ④ `jumptable` 出表(Z4 条纹 20°=27/50/58、30°=43/79/92 校准✅)。**余下(人工必停):** ⑤ **Play 全功能试骑**(已人工跑过一轮:"大部分功能能跑通";下列拍板项未逐项裁决)——gauntlet 磁吸边界/闸门未斩挡路·斩后可穿/贴墙段/跳距对条纹 + M8.1 表现层 + **速度线拍板(待拍板⑦)** + **M6.5 人工三项(必停,待拍板④)** + **GR2 手感包 A/B(待拍板⑨:Play 跑 `tools/preset_feel.lua` 切 stock/steady/hot,T 面板微调;侧倾方向反了把 `Camera_SteerRollGain` 改负)** + M4.1 抽查(重生 0.5s 输入保护/高刷插值);⑥ **Z5 圆角过渡试骑**(试炼道 Z5 两墙已铺裙板:贴近墙根即沿裙板滚上墙、D 爬升滚到贴墙、A 下行穿弧回地;嫌陡/嫌缓改 `WallRide_FilletRadius` 即时生效;半径拍板=待拍板⑧)。(.rbxl 已放弃;平面弯展示台已拆。)**旁支(不阻塞):** accept_m8_5 迷你轨 2 败待修台重跑。纯代码线保持清空——之后=**M9a/b 首图**(人类导演)。

## TrackBuilder P1 验证清单(原 handoff 并入)

1. Edit 跑 `tools/example_testtrack.lua`:预期 6 控制点、`Workspace.NeonRun.Track.Road` 路面串、3 水晶+2 核带 Tag;首跑易错点:PartType 名/路面下沉量/lint 边界/开放式需 ≥4 控制点——修掉再往下。
2. `tools/selfcheck.lua`:`trackRoadSlabs>0`、`rideableTags` 对口径(板+坡+rig 地板)。
3. 弯道 lint 报 ❌ 过紧弯(<167 studs)则挪控制点重跑。
4. Play 试骑:发车→水晶 +18/斩核 +25→完赛。开放式=`Workspace.NeonRun.Closed=false` 统一驱动(运行时/TB/RaceTimer 三方同源;终点=样条末端 t≥0.997,强制单圈)。
5. 手摆速查(打 Tag 即生效,R 全复活):`EnergyCrystal` 骑过 +18(磁吸 7;满蓝不捕获,ADR-42)/ `EnergyCore` 斩 +25 / `Destructible` 斩开(闸门 +15;未斩=实体墙)/ `ShooterEnemy` 弹反 +25·斩本体 +30·骑穿免费(需重注册,稍麻烦)/ `WallRideSurface` 直墙约定 Size=(厚,高,长)·±X 贴面。
6. P2~P4 已并入 `TrackBuilder.compile`(ADR-41);单独 P1 行为=`TB.build`。
7. **试炼道(ADR-40)✅已生成(2026-07-15;1~4 的 example_testtrack 未单独跑,铺路/lint 已由 gauntlet 首跑实证):** 静态核对完成:① 坡向✅(射线实证薄边朝来车)② 探针摆位✅(对真中心线 6.0/10.0;**动态吸取待 Play**)③ 闸门:场上=旧非实体版;**重跑 build_gauntlet 后=实体墙(ADR-42)**——未斩正撞硬撞(右侧可绕)、斩后可穿、R 复原(动态待 Play)④ 贴墙件✅规格合约定(=磁吸活墙段,骑近侧向切入即上墙;测普通墙碰撞=临时摘 Tag)⑤ selfcheck 口径:trackRoadSlabs=285(Road children=板×3=855),Rideable=288(285 板+2 坡+1 CombatRig 地板)⑥ lint✅(CP04/05 摆幅 ±60,worstR=195.5;试探法=改 CP 后 `TB.lint(TB.buildSpline(false))` 空跑)。

## Studio 侧状态(覆盖式)

(截至 2026-07-15,本机现场对账;**✅ 已复核:场景保存完好、未回滚**——selfcheck 结构核对全绿,下列计数均本次实测;逐字节哈希未复跑,动代码前按接手任务补)

- **代码同步:** repo 23 脚本(Modules 18+Config 5)+TestDrive = Studio 哈希逐字节一致(2026-07-15 全量 djb2 比对;第三/五会话 BikeController 折线行走+ADR-45 解析圆角,复核 len 41008/djb2 3575926232 逐字节一致;**第四会话 Handling/CameraRig/TunePanel 三件 `.Source` 整体推平,djb2 后验=repo:Handling 8916/4097828324(第五会话补 FilletRadius 默认行后)、CameraRig 8687/309854658、TunePanel 5748/4104482586**)。**Rojo 插件断连中:插件版本≠服务端 7.7.0(`Can't parse JSON` 刷屏)——人工更新 Studio 端插件到 7.7.0,只留一份插件(坑 25)。**
- **Rojo serve 起法(固定):** 用正式版二进制 `/home/showhand/users/ljx/bin/rojo-7.7.0 serve default.project.json --port 34873 --address 192.168.110.69`,Studio 连 `192.168.110.69:34873`。**别用 rokit 的 `rojo`**——rokit.toml 钉在 `7.7.0-rc.1`,rc 与老版插件(现场 7.0.0)协议握手崩(`attempt to index number with 'protocolVersion'`/rejectWrongProtocolVersion);正式版 7.7.0 能握手。don't-ask 下全路径 `serve` 会被 Bash 拦,需人类 `!` 前缀跑。
- **✅ M8.1 已种+验收 20/20:** Energy 17 键(实测)。分段门拱门=运行时客户端建(非持久)。
- **✅ M6.5 已种+验收 42/42:** seed 重跑 +0(ChainMaxTurnDeg 在);**WallRig 已建**(accept 自建,常驻 @(-1800,200,-600):地板 260×800 Rideable + 直墙 700×30 WallRideSurface)。墙件摆放约定不变(±X 贴面/Z 切向/Size=(厚,高,长))。**第四会话换新 CameraRig(ADR-44)后复跑仍 42/42**(坑 27 快照包裹,调参值还原)。
- **✅ M4.1 已种+验收 29/29:** seed +0(6 键全在);**M41Rig 已建**(常驻 @(-2400,200,-550):地板 300×900 Rideable + 矩阵墙 + 三旋转石头,墙石无 Tag=障碍)。**Rig3 走廊白名单收尾:Rig3_Ramp/FlatA/FlatB + Rig3_Basin(坡底盆地,顶面 y=-19.1)已补 Rideable Tag**——Basin 漏打=坡顶基准漂移前科(117/85→142/110),accept 预检射线已深探 320 覆盖(坑 26)。锚点链:场上 RespawnAnchors 仍无,赛道就绪后跑 `tools/bake_anchors.lua`。
- **✅ ADR-45 底部圆角已上线:** 活属性 `WallRide_FilletRadius=7`;**Z5 两墙(WallRide_L/R)已铺 Rideable 裙板**(±X 双面 6 片/90°,`<墙名>_FilletSkirt` 挂 Gauntlet 下;墙底与路面差实测 0.00;重建=重跑 `tools/build_wall_fillet_skirts.lua`);WallRig/M41Rig 等测试台**不铺裙**(保 m6_5 直角基线台)。ADR-43 平面弯展示台 `NeonRunWallCornerRig` **已拆**(误读产物;工具保留,要复现重跑生成器)。
- **Handling Attributes:实测 117**(含 VFX_ 8 键+ADR-44 Camera_ 10 键(默认全关)+**ADR-45 `WallRide_FilletRadius=7`**;人类调参值 `WallRide_BlendSec/CamRollSec=0.4` 保留);Energy 17;Config 含 TrackSpecs(ADR-41 声明表)。
- **试炼道(2026-07-15 本机重跑就绪):** `build_gauntlet` 已恢复正式赛道:CP13 + Road 285 段(lint worstR=195.5✅ 无过紧弯)+ Gauntlet 37 件(**闸门=实体墙 ADR-42**;晶 11/核 2/射手 2/闸 1/墙 2/坡 2)。`bake_anchors`✅ 锚点 4(样条 3428/间距 500,剔 wallspan×1+turn×1,正下方全白名单 grounded OK)。CheckpointTs 仍 NONE(RaceTimer 客户端自建 0.25/0.5/0.75)。`accept_m8_5` 首跑 15/17(基准表)。**Play 全功能试骑=下一棒(人工必停)。**
- Tag 计数(2026-07-15 实测):**Rideable 318**(285 板+2 坡+CombatRig/WallRig/M41Rig 地板+Rig3 三件+Basin+**Z5 圆角裙板 24**)/EnergyCrystal 27/EnergyCore 11/ShooterEnemy 7/Destructible 2/WallRideSurface 3(Gauntlet 2+WallRig 墙 1;圆角裙板=Rideable 不占此 Tag;**对账时的游离 WallRide_L@(691,245,-3240,旧 build 残留 size554)现已不在场上**——赛道重建后消失,疑随旧 Track 清除或协作者清理,正合预期无游离墙)/SlashEnemy 0/ParryEnemy 0。
- **StreamingEnabled=false**(已持久到场景;根本方案=待拍板⑥,坑 24)。
- .rbxl 入库=人类拍板放弃(2026-07-15;如需灾难还原点另议——快照另见 ServerStorage.NeonRun.Backup)。
- Workspace.NeonRun:SplineViz 随 TB 重建/SpikeSite 7 台(不侵入试炼道走廊);Workspace.Motorcycle:PrimaryPart=BikeRoot,66 件焊接,Root 锚定;备份 ServerStorage.NeonRun.Backup;模板脚本与 RaceGui 均 Disabled(勿删);测试走廊沙丘最高 y=138。

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
| M8.1 八项 | 点火不足 0.4s 自动烧满;0 能量=空箱且速度不变;磁吸边界拾取;核/门/敌入账正确;斩墙 0;R 全重置;擦碰零入账;80 分段+READY | `tools/accept_m8_1.lua`,**2026-07-15 Studio 验收 20/20 全过** |
| M4.1 六组 | 石头 rig 100 次全同+零入石帧;碰撞 vy 永不为正;定档矩阵 9 角(5~90,夹 20/55 边界)×3 速正确+零穿透零墙内帧(**限墙 z 范围**);重摔非可骑面=硬撞(**Speed_Base 临时 0=纯垂直**)/掠平顶=悬滑 hover>0(问题⑪);锚点三 lint+射手**路边位**剔除+弧长永不前进+0.5s 输入保护;**变帧率(23/47/61/144Hz)与 1/60 逐位一致**;直线+坡顶零变化 | **2026-07-15 修复版 29/29 全过** |
| M6.5 十组 | 墙态进出 100 次逐位一致;墙态全程能量零变动(巡航=常量/冲刺=与平地流水逐位同);空中进入;高位退出跳距对弹道模型(实 58.3/模 57.9);直线 400 帧+转向锚点 69.3/55.0/55.0+坡顶零变化;三退出(段尾 z≈-950/下缘 ≤6 帧回地/上缘);R 全重置;相机 up 参数化 | **2026-07-15 42/42 全过**(坡顶依赖 Rig3_Basin Tag,坑 26) |
| 松键宽限(ADR-39) | 松 6 帧(0.1s)重按心流在;松 10 帧(0.167s)断;能量流水与无宽限版逐位一致(除 flow 标志);刹车立即断;满槽按住燃尽 273 帧不变 | `tools/accept_m6_5.lua` ⑧,**2026-07-15 全过** |
| M8.5 预期 | compile 全管线跑通(断口 NoRoad>0/内容计数=spec/墙链≥3 段);断口三档(巡航✗冲刺✓心流余量);CheckpointTs=4 门递增;锚点非空且正下方=白名单;机器人完赛;墙链跨段 ≥2 不弹出;红区≠0+判定点零残留;compile 幂等 | `tools/accept_m8_5.lua` 八组,**2026-07-15 首跑 15/17**——compile 功能全绿(断口三档/CheckpointTs 4 门递增/锚点/墙链跨段 distinct=3/幂等);2 败=迷你轨测试台缺陷(⑤两处急弯 48/77<167→机器人全程冲刺过不去、重生 7 次未完赛;⑥墙带 3 段墙帧 53<阈值 60,但跨段核心 distinct=3 不弹出均过);BikeController/TB 代码零嫌疑,待修台重跑 |
| 试炼道生成(ADR-40) | S 弯 CP04/05 ±60 → lint worstR=195.5(>167.1 留 17%);Road 板 285/Rideable 288;Gauntlet 37 件含终点门;静态核对 6 项全过 | 2026-07-15 实跑;Play 全功能试骑待跑 |
| BikeVFX 冒烟(dt=1/60) | 淡入 FadeIn/dt+1 帧到 1(默认 12+1)/淡出 15+1 帧到 0;Beam 中段透明度=1−MaxAlpha;归零补一笔即停写;cameraStep 同帧 rig=cam;火花 linger 0.3s(断触 17 帧仍喷、18 帧停);destroy 零残留 | **2026-07-15 23/23**;实例属性经 float32 round-trip,断言用 1e-3 容差 |
| 历史核证 | M3~M8 代码实证(2026-07-13 三 agent):相机三档/碰撞三档+转场冻结/能量心流/贴墙(旧)/体积盒判定/快照弹道均属实;M8 仅客户端 | 全文见 git d19ef25 |
| 贴墙 90° 圆角弯(ADR-43) | R7 凹弯 ×{100,135}:全程吸附、唯一退出=链端(末墙尾 ≤12)、净转 +90°±2、速度不减、墙上高度零漂 ≤0.15;直链回归跨段不弹出+单帧零转向+贴面距=悬浮高;最大单帧转角 18.0°/24.0°(理论 17.7/23.9,凹弯车径=R−1.6) | `tools/accept_wallcorner.lua`,**2026-07-15 15/15**;复跑 accept_m6_5 42/42 零回归 |
| 地面→侧墙圆角过渡(ADR-45) | ⓪钉 0=直角旧语义(首帧 up=n);①R7 入墙首帧近直立(φ0=15.3°,up·Y=0.965);②爬升单调滚到贴墙(17 帧=理论)+越弧顶接直墙+速度恒 100;③下行穿弧 ≤8 帧回地零硬撞;④弧内驻留零漂 ≤0.05;⑤确定性逐位 | `tools/accept_wallfillet.lua`,**2026-07-15 17/17**;钉 0 复跑 m6_5 42/42+wallcorner 15/15 零回归 |
| GR2 手感包冒烟(ADR-44,Edit stub 相机) | 默认关:相机 UpVector.X 精确 ==0(绕视轴零滚转)+内部 upVec 严格 (0,1,0)+FOV 收敛=档位+dip/airPitch/punch 全零;特性开:侧倾左倾 up.X<-0.05·右倾 >+0.05(对称)/速度FOV 收敛=档位+(146−100)×gain/冲拳 A/B 点火后 15 帧 FOV 差 ≥0.5°/落地 dipY≈-0.36 且 180 帧弹簧归零/速度震动关静(<0.005)开颤(>0.01)/下坠俯视 airPitch>4 落地回 <0.5;属性现场还原 | **2026-07-15 12/12**(首跑 1 假败=断言拿 UpVector==世界Y 当判据,坑 29);同日新 CameraRig 复跑 accept_m6_5 42/42 |

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
21. compile/accept_m8_5 会整体销毁重建 Track/Content/锚点/门属性:跑赛道类验收前先确认场上没有"只存在于 Studio 的手调摆件"(有则先挪出 Track 文件夹);accept_m8_5 自动备份还原 ControlPoints,但 Track 产物=迷你轨,结束后需重跑 compile/gauntlet 恢复正式赛道。
22. 断口的"平段无解":jumpDistance 对持续下坡/纯平起跳返回 nil 或极小值——这不是 bug,是弹道事实;builder 自动补起跳唇,若仍无解=报告让人挪 CP(在 jump 段画坡顶),勿在代码里硬造距离。
23. Catmull-Rom 弯道控制点的偏移会经切线传导进相邻"直线"段,产生反向预摆(gauntlet 实测:CP04 x+60 → CP02~CP03 段中心线反向偏 3.1 studs@z≈-360)。两个推论:① 摆件必须用样条局部系(NearestPoint+RightVector)② **核对"对中线距离"必须以样条为基准**——拿世界坐标直线当中线会把正确摆位误判成错位。lint 快速试探法:改 CP 后 `TB.lint(TB.buildSpline(false))` 空跑,不必全量铺路。
24. **StreamingEnabled=true 截断客户端稀疏锚点→提前完赛(2026-07-15 实测)**:客户端脚本(TestDrive/RaceTimer)开局只流式加载附近 ControlPoints(13 CP 只见 CP01-04),样条止于 S 弯→撞 `t≥0.997` 提前完赛。Server datamodel 数据齐全,是**复制**问题;定位法=Play 时 Client/Server 各读 CP 数比对(4 vs 13 即中招)。当前修复=Edit 关 StreamingEnabled(已持久);根本方案(重开 Streaming)=锚点 `ModelStreamingMode=Persistent` 或坐标迁 ReplicatedStorage,**移动端长赛道 demo 前必解**(待拍板⑥)。教训:凡"客户端一次性需要全赛道数据"的,Streaming 下都是隐雷。
25. Rojo 插件×服务端版本必须严格一致:7.7.0 起线格式=MessagePack,旧服务端(7.6.1 JSON / 7.7.0-rc.1)对 7.7 插件一律报 `attempt to index number with 'protocolVersion'`(msgpack 把 `{` 解成数字 123)。服务端=工作区 `users/ljx/bin/rojo-7.7.0`(人工拖入的官方 Linux 包);核对法=`curl <addr>:<port>/api/rojo`,7.7=二进制 msgpack 开头 0x89、≤7.6=JSON。另:Studio 同时装商店云版+CLI 管理版两份插件会互相干扰,只留一份(user_RojoManagedPlugin.rbxm)。
26. **CollectionService 的 GetInstanceAdded/RemovedSignal 同线程内 deferred**:execute_luau 一口气跑完不派发,运行中补的 Tag 对"信号驱动缓存"(BikeController 白名单过滤表)不可见→探针视件不存在(坡顶全程滞空假失败)。修法=补 Tag 后显式 `ctrl:_rebuildGroundFilter()`(GetTagged 是即时查询,不受影响)。连带教训:① accept 预检射线深度必须覆盖低位地面件(Rig3_Basin 顶 y≈-19,原 -120 探不到→坡顶基准漂移 117/85→142/110,险些误判 M4.1 改了物理);② 旋转石头顶面自带 ~20° 斜度,贴面掠过入射角轻易 ≥55°=正确判硬撞,"掠顶悬滑"用例必须用平顶障碍(悬滑窗口仅 0.64 studs=障碍顶+0.96~+1.6);③ teleport 后 curSpeed 自动回涨(RampUp),"纯垂直下落"用例需临时 Speed_Base=0;④ 穿透判据要限障碍物 z 范围,滑出墙尾后越过延长面≠穿透。
27. **accept 脚本会无条件覆写调参键**:accept_m6_5/accept_m8_5 对 WallRide_* 等直接 SetAttribute(不是"缺失才种"),复跑回归就吃掉人类调参(实测 BlendSec 0.4→0.2、CamRollSec 0.4→0.25)。修法=跑前把 Handling/Energy 全 Attributes JSON 快照进 ServerStorage,跑后逐键还原(含删除快照外新增键);新写 accept 学 accept_wallcorner:钉扎前存值、结束还原并断言。
28. **MCP execute_luau 可能把同一段代码执行两遍**(管线重试):非幂等脚本第二遍会报假错(如 `.Source` 锚点拼接第二遍 `anchor not found`,而第一遍其实已成功写入)。判失败前先核对目标状态(哈希/计数);一切经 MCP 跑的源码/场景变更脚本必须幂等:锚点断言(旧串不在时校验新串在)、按名清理重建、Destroy 前判存在。
29. **相机断言别拿"UpVector==输入 up"当判据**:`CFrame.lookAt(camPos, lookAt, up)` 会把 up 对视轴正交化,视轴带俯仰时 UpVector 天然含 Y/Z 分量(旧代码亦然)——"零滚转"的正确判据=**UpVector.X==0(视轴水平朝 -Z 时)或读 rig 内部 upVec**。GR2 包冒烟首跑 1 假败即此(用例缺陷,非代码);另:Team Create 协作者在线时 Play 模式随时被人开,Edit 数据模型会突然不可用——execute 报 `Edit datamodel is not available` 先等/问人,别抢 start_stop_play。
