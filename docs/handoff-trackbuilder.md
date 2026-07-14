# 交接说明 — TrackBuilder / 测试赛道(给带 MCP 的接手会话)

> 目的:让接手 AI 用 Roblox Studio MCP 把"铺路 + 手摆内容"链路跑通,产出一条可玩测试赛道。
> 权威顺序仍是 `design.md` > `status.md` > 本文件。手感/爽感 AI 无裁决权(CLAUDE.md)。

## 现状(2026-07-14)

M8.5 TrackBuilder **P1 地基**已落代码,**尚未在 Studio 验证**(上一会话无 MCP)。已交付:

- `src/ReplicatedStorage/NeonRun/Modules/TrackBuilder.luau` — 样条→路面几何 + `Rideable` Tag + 弯道半径 lint
- `src/ReplicatedStorage/NeonRun/Config/Track.luau` — 烘焙参数(路宽40/段长12/下沉1.6/安全系数1.10;直 require)
- `tools/buildtrack.lua` — 烘焙驱动(`BUILD`/`CLOSED` 开关)
- `tools/example_testtrack.lua` — 一键摆完整测试赛道的示例(控制点+铺路+手摆水晶/核)
- `tools/selfcheck.lua` — 加了 `trackRoadSegs` / `rideableTags` 核对项
- 开放式赛道支持:`Workspace.NeonRun.Closed` 属性(默认 true=环道)统一驱动运行时/TrackBuilder/RaceTimer

## 你的第一动作(务必按序)

1. **Edit 模式**跑 `tools/example_testtrack.lua`(execute_luau, datamodel=Edit)。
   - 预期:生成 6 个控制点、`Workspace.NeonRun.Track.Road` 一串路面件、3 水晶 + 2 能量核带 Tag。
   - 首跑可能报错的点:`Enum.PartType` 名、路面下沉量、lint 边界、Spline 断言(开放式需 ≥4 控制点)。**修掉再往下。**
2. 跑 `tools/selfcheck.lua`,确认 `trackRoadSegs > 0`、`rideableTags == 路面段数`。
3. 看 `TB.formatReport` 输出的弯道 lint:若报"❌过紧弯"(<167 studs),说明控制点弯太急——挪控制点重跑。
4. **Play(F5)试骑**:从起点 3-2-1 发车 → 沿路骑 → 水晶+18/斩核+25/贴墙+12每秒 → 骑到末端完赛。
5. 把验证结果(段数/Tag数/lint/试骑观察)**回填 `status.md`**(会话收尾义务)。

## 手摆内容速查(纯 Tag 驱动,系统实时接管)

| 实体 | 建件 + | 效果 | 备注 |
|---|---|---|---|
| 水晶 | `CS:AddTag(p,"EnergyCrystal")` | 骑过 8 studs 内 +18 | 磁吸(M8.1)未做 |
| 能量核 | `CS:AddTag(p,"EnergyCore")` | 斩击 +25(破 Cap) | 自动跑"只在直线段"lint,摆弯道会警告 |
| 可破坏物/闸门 | `CS:AddTag(p,"Destructible")` | 斩开 | M8.1 落闸门改 GateGain+15 |
| 射手敌 | `CS:AddTag(p,"ShooterEnemy")` | 迎面弹,弹反+25/斩本体+30/骑穿免费 | 略需重注册;比水晶/核麻烦 |

所有实体**不受开放/闭环影响**,骑上去当场生效。R 重开全部复活(已修 energy:reset)。

## 已知限制 / 未做

- P1 只生成**平截面宽走廊**;微谷截面/bank 倾斜留 P2/P3。
- 开放式赛道最少 **4 个控制点**(Spline 断言)。
- RaceTimer 检查点仍是默认 `{0.25,0.5,0.75}` 匀布;精细分段门是 P4。
- **未做:** P2(判定点入弯 lint/供给密度统计/机器人完赛)、P3(水晶/核/环**自动**摆放)、P4(可见分段门 + ADR-27 重生锚点链烘焙,顺带清 M4.1 一半)。
- M8 计时/奖牌仍**仅客户端**(ADR-32 欠账,服务端权威归 M12)。

## 下一步建议

先验证 P1 + 手摆出一条测试赛道跑通 → 再按价值选 **P4(重生锚点,顺带清 M4.1 一半)** 或 **P3(内容自动摆放)**。
