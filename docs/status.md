# STATUS — 现场状态(活文档)

> **维护规则:** 「快照」「Studio 侧状态」覆盖式(只放"现在时",历史看 git);「验收基准」「坑表」追加式。ADR 与修订史在 `docs/decisions.md`(只增不改)。

---

## 快照(覆盖式)

- **更新:** 2026-07-15,**云端对齐(双线合并)**。两条并行线各自落地,现已缝合:
  **Studio 线(07-15,另会话实跑):** 双 seed 已种(`seed_m8_1`→Energy 18 键;`seed_m6_5`→Energy 17 键+Handling 84 键);`build_gauntlet` 首跑 S 弯 ±100 摆幅 lint 失败(worstR=111.7<167.1),CP04/05 收至 **±60**(worstR=195.5 留 17% 余量)重跑通过,工具已回写;静态核对全过(坡向/贴墙件规格/磁吸探针对真中心线 6.0/10.0/走廊无外来碰撞件);**补终点门**(白拱门+FINISH 牌+地面白线@t=0.99,原三分段门只到 t=0.75 会误判已完赛);Play 实测抓出并修复**"提前完赛"bug**(坑 24:StreamingEnabled=true 截断客户端样条→关闭解决,已持久到场景);核实 `Gate_1 转角 3.7°` 警告=历史遗留外部件,非试炼道。完整人工试骑未跑。
  **代码线(07-14,本线):** **M4.1**(定步长 FixedStep+渲染插值/物性白名单+防穿/碰撞五规格=三线扫掠+定档一次性+去穿透钳制/重生锚点链 RespawnAnchors+0.5s 输入保护+删 respawnCF 旧路径;工具 bake_anchors/seed_m4_1/accept_m4_1)、**M8.5 P2~P4**(ADR-41 混合制:TrackSpecs 声明表+`compile()` 总入口=断口弹道反解→摆放→墙带直墙链→门+锚点→lint 全套→机器人完赛;墙态跨段交接 findContinuation;宪法 v1.2)、**ADR-42**(满蓝不捕获+墙门三型定稿,废"擦碰级减速";AttackSystem 击杀真切物性=已知问题⑧正解;闸门改实体摆放)。四笔验收全部待跑。
  **合并注意:** 场上 gauntlet 是旧代码时代产物——闸门还是**非实体旧版**、无锚点、无 CheckpointTs;Rojo 同步新代码后**重跑 `build_gauntlet.lua`(闸门变实体)或直接 `buildtrack.lua`(MODE=compile,一并出门+锚点+lint+机器人)**。
- **重心:** V1 可玩 demo。**纯代码线已清空;下一步=带 Studio 清验收积压**:①`accept_m8_1`(seed 已种)②`accept_m6_5`(seed 已种;**重跑一次 seed_m6_5**,新增 ChainMaxTurnDeg 键)③`seed_m4_1`→`accept_m4_1` ④`accept_m8_5` ⑤selfcheck 全 OK ⑥Play:gauntlet 全功能试骑+**M6.5 人工三项(必停)** ⑦重跑 gauntlet/compile(对齐 ADR-42 实体闸门)→`bake_anchors` ⑧jumptable 校准 Z4 条纹 → 然后 **M9a/b 首图**(人类导演:拖 CP+改 TrackSpecs→compile→试驾反馈)→ M9.5 → M10 = demo;M11/12/13 后置。
- **里程碑:** M0~M7 ✅(基准表);M2.1 待核实;M8 🔶 仅客户端(归 M12);**M8.1 代码✅待 Studio 验收**;**M6.5 代码✅待 Studio 验收+人工三项(必停)**;**M4.1 代码✅待 Studio 验收**;**M8.5 P2~P4 代码✅待 Studio 验收**;M8.5 P1 铺路已由 gauntlet 首跑实证,accept 全套待跑;试炼道生成✅Play 全功能试骑未跑。
- **待拍板(人类):** ① 手感参数统一调(`Combat_*`/心流 AB 旋钮属性面板实时生效);④ M6.5 手感三项(**代码已落,试玩后拍板**):进入宽容度(`WallRide_EnterWindowStuds/EnterMaxAngleDeg/EnterTowardMinSpeed/EnterMinSpeed`)/高度带速率与"下坠漂移"开关(`WallRide_HeightBandSpeed`/`FallDriftPerSec`=0 关)/相机滚转速度(`WallRide_CamRollSec`);⑤ **最小点火×心流尾段**(现默认=延续,备选=尾段豁免;M9.5 AB,旋钮 `MinIgnitionBurnSec`);⑥ **Streaming 根本方案**(现=灰盒期关闭;重开需样条锚点持久化 `ModelStreamingMode=Persistent` 或坐标迁 ReplicatedStorage,**移动端长赛道 demo 前必解**,坑 24)。**已拍板归档(2026-07-14):** 贴墙=B(ADR-36)/能量两轨(ADR-37)/射手只打前方(ADR-38)/输入分层+松键宽限(ADR-39)/节拍模板初版(§7)/名称沿用 NEON RUN/测试赛道 AI 全生成(ADR-40)/赛道声明混合制(ADR-41,选 C)/满蓝不捕获+墙门三型(ADR-42)。
- **已知问题:** ③ TrackShooter1 落位偏高(y=11,人类拖正即可,Tag 已带);④ 剑光/弹反/点火音效缺 assetId(事件钩子 swing/hit/parry/whiff/telegraph/fired/playerHit 已留;BikeAudio 点火 whoosh 已读有效 sprinting);⑥ `Combat_DebugHitbox=true` 临时判定盒可视化(青=平时/绿=盒内有目标/白=命中帧),正式版前移除;⑧〔已解,ADR-42〕defaultKill 现切物性(CanCollide/CanQuery 随斩关、R 复原);闸门=实体墙摆放(TrackBuilder P3 与 gauntlet 工具已改;**场上 gauntlet 闸门=旧非实体版,重跑即对齐**);⑨ **M6.5 墙态内不做障碍扫掠与坠落判定**(墙段按 soft lint 干净授权,墙上障碍/曲墙随 TrackBuilder P3);⑩ 下缘回地有 ≤悬浮高(1.6)的一帧上吸(落地贴地逻辑固有,人工验收留意);⑪ **轻掠非可骑面顶=悬浮 1.6 滑过、不落地不吸附**(M4.1 物性声明的边界结果;重摔≥55°且总速≥20 才判硬撞——试玩留意观感)。**已解待复核:** ①石头忽弹忽减→**定档一次性**、②撞墙卡出墙外→**帧末去穿透钳制**(均归 accept_m4_1 验证);⑤ READY 脉冲+点火白闪(accept_m8_1);⑦ graze 回能路径已删(Studio 残留属性由 seed 清);Streaming 提前完赛→已关闭(根本方案=待拍板⑥)。**推迟项(backlog):** 墙带默认弯内侧/compile 报告加"冲刺时间预算"行(M9 前顺手)/分段门参照改机器人 split/**"能量归零时长占比"埋点(M9.5 必需)**/CrystalField 冷却常量入 Config。
- **⚠️ 接手第一任务:** 带 Studio(seed×2 已种)→ ① `tools/accept_m8_1.lua` 八项,**回填基准表** ② **重跑 `tools/seed_m6_5_config.lua`**(新增 ChainMaxTurnDeg)→ `tools/accept_m6_5.lua` 十组(自建 WallRig),**回填** ③ `tools/seed_m4_1_config.lua`(Handling +6)→ `tools/accept_m4_1.lua` 六组(自建 M41Rig:定档矩阵 9 角×3 速/石头 100×/障碍防穿/变帧率 23·47·61·144Hz/锚点 lint+永不前进+输入保护/直线+坡顶),**回填** ④ `tools/accept_m8_5.lua` 八组(自建迷你 CP 轨,**自动备份还原现场 CP**;跑完场上 Track=迷你轨,之后重跑 gauntlet/compile 恢复),**回填** ⑤ `tools/selfcheck.lua`(energyM81Missing/energyStrayGraze/energyM65Grace/energyStrayWallRide/handlingM65WallRide/handlingM41 全 OK)⑥ **重跑 `tools/build_gauntlet.lua`**(实体闸门+新代码对齐)→ **`tools/bake_anchors.lua`**(selfcheck respawnAnchors>0)⑦ Play 试骑:gauntlet 全功能(磁吸边界/闸门未斩挡路·斩后可穿/贴墙段/跳距对条纹)+ M8.1 表现层 + **M6.5 人工三项(必停,待拍板④)** + M4.1 抽查(重生 0.5s 输入保护/高刷插值顺滑)⑧ `tools/jumptable.lua` 出跳距表 ⑨ **存一份 .rbxl 进 repo**(灾难还原点,现缺)。纯代码线已清空——下一棒=**M9a/b 首图**(人类导演,带 Studio)。

## TrackBuilder P1 验证清单(原 handoff 并入)

1. Edit 跑 `tools/example_testtrack.lua`:预期 6 控制点、`Workspace.NeonRun.Track.Road` 路面串、3 水晶+2 核带 Tag;首跑易错点:PartType 名/路面下沉量/lint 边界/开放式需 ≥4 控制点——修掉再往下。
2. `tools/selfcheck.lua`:`trackRoadSlabs>0`、`rideableTags` 对口径(板+坡+rig 地板)。
3. 弯道 lint 报 ❌ 过紧弯(<167 studs)则挪控制点重跑。
4. Play 试骑:发车→水晶 +18/斩核 +25→完赛。开放式=`Workspace.NeonRun.Closed=false` 统一驱动(运行时/TB/RaceTimer 三方同源;终点=样条末端 t≥0.997,强制单圈)。
5. 手摆速查(打 Tag 即生效,R 全复活):`EnergyCrystal` 骑过 +18(磁吸 7;满蓝不捕获,ADR-42)/ `EnergyCore` 斩 +25 / `Destructible` 斩开(闸门 +15;未斩=实体墙)/ `ShooterEnemy` 弹反 +25·斩本体 +30·骑穿免费(需重注册,稍麻烦)/ `WallRideSurface` 直墙约定 Size=(厚,高,长)·±X 贴面。
6. P2~P4 已并入 `TrackBuilder.compile`(ADR-41);单独 P1 行为=`TB.build`。
7. **试炼道(ADR-40)✅已生成(2026-07-15;1~4 的 example_testtrack 未单独跑,铺路/lint 已由 gauntlet 首跑实证):** 静态核对完成:① 坡向✅(射线实证薄边朝来车)② 探针摆位✅(对真中心线 6.0/10.0;**动态吸取待 Play**)③ 闸门:场上=旧非实体版;**重跑 build_gauntlet 后=实体墙(ADR-42)**——未斩正撞硬撞(右侧可绕)、斩后可穿、R 复原(动态待 Play)④ 贴墙件✅规格合约定(=磁吸活墙段,骑近侧向切入即上墙;测普通墙碰撞=临时摘 Tag)⑤ selfcheck 口径:trackRoadSlabs=285(Road children=板×3=855),Rideable=288(285 板+2 坡+1 CombatRig 地板)⑥ lint✅(CP04/05 摆幅 ±60,worstR=195.5;试探法=改 CP 后 `TB.lint(TB.buildSpline(false))` 空跑)。

## Studio 侧状态(覆盖式)

(截至 2026-07-15 云端对齐;seed×2 已种、试炼道已生成(旧代码版);四笔 accept 与 Play 全功能试骑未跑)

- **✅ M8.1 已补种(2026-07-15):** Energy 18 键(+MinIgnitionBurnSec=0.4/IgnitionCost=0/CrystalMagnetRadius=7/MoveRegenPerSec=0/GateGain=15,−NearMissGain/Window)。分段门拱门=运行时客户端建(`Workspace.NeonRunSegmentGates`,非持久,CanQuery=false)。
- **✅ M6.5 已补种(2026-07-15,需重跑一次):** Energy 17 键(+ReleaseGraceSec=0.12,−WallRide 收入两键),Handling 84 键(+WallRide_* 8 键);**合并后 seed_m6_5 新增 `WallRide_ChainMaxTurnDeg`(M8.5 墙链),重跑补 1 键**。测试台 **WallRig 尚未建**=accept_m6_5 首跑自建(@(-1800,200,-600),地板 260×800(Rideable)+直墙 700×30 带 Tag,常驻)。**墙件摆放约定:直墙 Part,±X 大面=可贴面(两侧皆可),Z 轴=切向,Size=(厚,高,长);打 WallRideSurface Tag 即生效**(gauntlet Z5 已按此)。
- **⚠️ M4.1 待补种:** `tools/seed_m4_1_config.lua` → Handling **+6**(Collision_SideOffset=1.1/Respawn_AnchorSpacingSec=5/SetbackAnchors=0/InputProtectSec=0.5/AnchorMaxTurnDeg=6/AnchorClearAheadStuds=60)。测试台 **M41Rig**=accept_m4_1 首跑自建(@(-2400,200,-550):地板 300×900(Rideable)+矩阵墙+三块旋转石头,常驻)。**白名单迁移(坑 12/20):一切可骑地面件必须带 Rideable Tag,否则探针视为不存在→假失败**;accept 沿坡顶路径自动补 Tag 并打印。**锚点链:赛道就绪后跑 `tools/bake_anchors.lua`**(→`Workspace.NeonRun.RespawnAnchors` 不可见 Attachment 链;改赛道必重跑;未烘焙场景重生走样条最近点 dev fallback)。
- **✅ 试炼道已生成(2026-07-15,lint worstR=195.5;旧代码版,重跑对齐):** ControlPoints=CP01~13(x≈700/y220/z 100→−3300,S 弯 ±60)+ `Workspace.NeonRun.Gauntlet` 37 件(晶 11 含边界探针 2/核 2/射手 2/闸门 1(旧非实体)/贴墙面 2/坡 2/落点条纹 6/路牌 6/**终点门 5**@t=0.99·z=-3266)+ Track.Road 855 children(285 板+边条 570)。旧 38 件 ControlPoints→`Backup.ControlPoints_bak_1784086038`。无锚点/无 CheckpointTs(重跑 compile 或 gauntlet+bake 后齐)。**Play 全功能试骑未跑。**
- Modules:repo=**16 件**=Studio 实测一致(2026-07-15 selfcheck;M4.1 +FixedStep/RespawnAnchors 随 Rojo 即同步);Config 模块 **+1**(TrackSpecs,ADR-41 声明表——**改节拍/供给=改 repo 文件后重跑 compile**);Handling Attributes:实测 84 → 重跑 seed_m6_5(+1)+seed_m4_1(+6)后 91,以 selfcheck 实测为准。
- **M8.5 工作流(ADR-41):** 人类拖 CP 画路线 → 改 `TrackSpecs`(或用 Default=§7 模板)→ Edit 跑 `buildtrack.lua`(MODE=compile)→ 看报告(节拍实际 vs 模板/断口三档/供给两桶/墙链夹角/机器人时间)→ ❌ 几何=挪 CP,⚠️ 摆放=已自动顺移只需过目 → Play 试驾。改一版=分钟级。
- Workspace.NeonRun.**CombatRig**(@(-1200,200,-200) 直道 40×2×800,地板已打 Rideable):EnergyCore ×4/CombatShooterA·B/发车标线;主赛道 TrackShooter1@(-91,11,-440)、TrackShooter2@(-134,5,-515)、旧 M7 靶已核化 EnergyCore_1~3。
- Tag 计数(2026-07-15,含 Gauntlet):EnergyCrystal 27(Gauntlet 11+旧 16)/EnergyCore 11(2+9)/ShooterEnemy 7(2+5)/Destructible 2(1+1)/WallRideSurface 2(全 Gauntlet)/Rideable 288(285 板+2 坡+1 CombatRig)/SlashEnemy 0/ParryEnemy 0。
- **StreamingEnabled=false(2026-07-15 关闭,已持久到场景)**:原 true 导致客户端样条数据被流式截断(坑 24,提前完赛);灰盒测试期关闭;根本方案=待拍板⑥。
- **远程 Studio 通路(2026-07-14 实测):** Studio 跑在局域网 Windows 机 `192.168.110.168`(用户 Ymz);MCP=全局配置的 SSH stdio 桥(这台 Linux → 那台的 Roblox 官方 `mcp.bat`,**SSH 已实测通**;工具出现的前提=那头 Studio 开着且 MCP 插件已连,然后本会话 set_active)。**Rojo:本项目 serve 常驻于 tmux 会话 `ljx-rojo-motorcycle`,监听 `192.168.110.69:34873`**(Studio 端 Rojo 插件填此地址连;3087/9908/34872/8123 被其他工位占用勿撞)。管理:`tmux attach -t ljx-rojo-motorcycle` 看现场,`tmux kill-session -t ljx-rojo-motorcycle` 停;机器重启后重起=`tmux new -d -s ljx-rojo-motorcycle "rojo serve default.project.json --address 192.168.110.69 --port 34873"`(在 motorcycle 目录)。`.Source` 推送只作断连兜底,推前先查。**⚠️ repo 无 .rbxl:place 只存在于 Studio 侧,下次 Studio 会话务必存一份 .rbxl 进 repo(灾难还原点,CLAUDE.md 义务)。**
- Workspace.NeonRun:SplineViz 随 TB 重建/SpikeSite 7 台(y≈200~370,走廊扫描确认不侵入试炼道 x∈[640,760])。
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
| M8.5 预期 | compile 全管线跑通(断口 NoRoad>0/内容计数=spec/墙链≥3 段);断口三档(巡航✗冲刺✓心流余量);CheckpointTs=4 门递增;锚点非空且正下方=白名单;机器人完赛;墙链跨段 ≥2 不弹出;红区≠0+判定点零残留;compile 幂等 | `tools/accept_m8_5.lua` 八组,待跑 |
| 试炼道生成(ADR-40) | S 弯 CP04/05 ±60 → lint worstR=195.5(>167.1 留 17%);Road 板 285/Rideable 288;Gauntlet 37 件含终点门;静态核对 6 项全过 | 2026-07-15 实跑;Play 全功能试骑待跑 |
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
21. compile/accept_m8_5 会整体销毁重建 Track/Content/锚点/门属性:跑赛道类验收前先确认场上没有"只存在于 Studio 的手调摆件"(有则先挪出 Track 文件夹);accept_m8_5 自动备份还原 ControlPoints,但 Track 产物=迷你轨,结束后需重跑 compile/gauntlet 恢复正式赛道。
22. 断口的"平段无解":jumpDistance 对持续下坡/纯平起跳返回 nil 或极小值——这不是 bug,是弹道事实;builder 自动补起跳唇,若仍无解=报告让人挪 CP(在 jump 段画坡顶),勿在代码里硬造距离。
23. Catmull-Rom 弯道控制点的偏移会经切线传导进相邻"直线"段,产生反向预摆(gauntlet 实测:CP04 x+60 → CP02~CP03 段中心线反向偏 3.1 studs@z≈-360)。两个推论:① 摆件必须用样条局部系(NearestPoint+RightVector)② **核对"对中线距离"必须以样条为基准**——拿世界坐标直线当中线会把正确摆位误判成错位。lint 快速试探法:改 CP 后 `TB.lint(TB.buildSpline(false))` 空跑,不必全量铺路。
24. **StreamingEnabled=true 截断客户端稀疏锚点→提前完赛(2026-07-15 实测)**:客户端脚本(TestDrive/RaceTimer)开局只流式加载附近 ControlPoints(13 CP 只见 CP01-04),样条止于 S 弯→撞 `t≥0.997` 提前完赛。Server datamodel 数据齐全,是**复制**问题;定位法=Play 时 Client/Server 各读 CP 数比对(4 vs 13 即中招)。当前修复=Edit 关 StreamingEnabled(已持久);根本方案(重开 Streaming)=锚点 `ModelStreamingMode=Persistent` 或坐标迁 ReplicatedStorage,**移动端长赛道 demo 前必解**(待拍板⑥)。教训:凡"客户端一次性需要全赛道数据"的,Streaming 下都是隐雷。
