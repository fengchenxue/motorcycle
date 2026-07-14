# NeonRun — 摩托竞速游戏（git + Rojo）

代码从 Studio（place：**比赛**）提取到 `src/`，按 Roblox 数据模型层级镜像。
文件命名遵循 Rojo 约定：`Name.luau` = ModuleScript，`.server.luau` = Script，
`.client.luau` = LocalScript，`Name/init*.luau` = 带子脚本的容器。

> 原本的 Roblox 官方赛车/竞速模板（Car、CarSpawning、Racing、Constants、Utility、
> Client 等代码，以及 Car 模型、Garage、Spawners、Race 等实体）已删除，本仓库现在
> 只包含 NeonRun 摩托游戏。

## 结构

```
src/
  ReplicatedStorage/NeonRun/
    Modules/   BikeController, CameraRig, BikeAudio, TunePanel, Spline, EnergyState,
               CrystalField, AttackSystem, ShooterField, RaceTimer, ConfigLive,
               SplineViz, TrackBuilder
    Config/    Handling, Energy, Medals, Track
  StarterPlayer/StarterPlayerScripts/NeonRunTestDrive.client.luau   -- 主入口(试驾)
  SoundService/Audio/   Listener, AutoPlayAudio        -- 通用音频(未纳入 Rojo 同步)
  ServerStorage/NeonRun/Backup/Motorcycle_Original/    -- 旧摩托模型的遗留脚本(备份)
```

## Rojo 同步

`default.project.json` 映射了 NeonRun 的全部核心代码 —— 这些脚本都不含内嵌的非脚本
实例，可以安全地双向对应，`rojo serve` 不会误删游戏里的东西：

- `ReplicatedStorage.NeonRun`（Modules + Config 全部）
- `StarterPlayer.StarterPlayerScripts.NeonRunTestDrive`

同步是**单向的：磁盘 → Studio**。在 VS Code 里改这些文件并保存，Studio 会实时更新；
在 Studio 里改则不会写回磁盘（对已映射脚本请只在磁盘编辑，避免被覆盖）。

未纳入同步：`SoundService.Audio` 的两个脚本（所在文件夹还有音频设备，留在 Studio
编辑），以及 `ServerStorage` 里的遗留备份脚本。

## 启动

```powershell
# 装 Rojo CLI（当前只装了 Studio 插件，还缺 CLI）
winget install rojo-rbx.rokit
rokit add rojo-rbx/rojo
rokit install

rojo serve            # 然后在 Studio 的 Rojo 插件里点 Connect
```

## 关于 place 文件

`code.rbxlx`（被 git 忽略）仍是所有非代码内容（地形、摩托模型、场景、GUI）的唯一来源。
建议在 Studio 里 `File → Save to File` 存一份，并考虑从 `.gitignore` 移除后提交，做整份备份。
