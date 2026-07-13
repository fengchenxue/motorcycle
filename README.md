# NeonRun — Roblox source (git + Rojo)

All 94 game scripts were extracted from Studio (place: **比赛**) into `src/`, mirroring the
Roblox datamodel. Folders = containers; files use Rojo naming:

| On disk                | Roblox class |
|------------------------|--------------|
| `Name.luau`            | ModuleScript |
| `Name.server.luau`     | Script       |
| `Name.client.luau`     | LocalScript  |
| `Name/init*.luau`      | a script that has child scripts |

```
src/
  ReplicatedStorage/   Constants, Utility, Client, Car/Scripts, NeonRun/{Modules,Config}
  ServerScriptService/ CarSpawning, Collision, Racing
  SoundService/Audio/  Listener, AutoPlayAudio
  StarterPlayer/StarterPlayerScripts/ NeonRunTestDrive
  ServerStorage/       NeonRun/Backup/Motorcycle_Original (legacy backup)
```

## What Rojo currently syncs

`default.project.json` maps **only the code that is 100% scripts** (no embedded
non-script instances), so `rojo serve` can never delete anything in your game:

- `ReplicatedStorage.Constants`, `ReplicatedStorage.Utility`, `ReplicatedStorage.NeonRun`
- `ServerScriptService.Collision`
- `StarterPlayer.StarterPlayerScripts.NeonRunTestDrive`

Everything else is on disk (git-tracked) but **edited in Studio for now** — see below.

## Not yet Rojo-managed (edit in Studio)

These scripts contain **embedded non-script template instances** that the script clones at
runtime. Mapping them via Rojo would drop those instances, so they're left for Studio:

| Script | Embedded instance |
|--------|-------------------|
| `ServerScriptService.CarSpawning` | `SpawnPrompt` (ProximityPrompt) |
| `ServerScriptService.Racing.RaceManager` | `RaceGui` (BillboardGui) |
| `ServerScriptService.Racing.RaceManager.createBorderBeams` | `BorderBeam` (Beam) |
| `ServerScriptService.Racing.Race.holdPlayers` | `RaceLineupAlignPosition` (AlignPosition) |
| `ReplicatedStorage.Client.GuiModules.LeaderboardGui` | `PlayerFrame` (Frame) |
| `ReplicatedStorage.Client.CheckpointFlags.createCheckpointFlags` | `CheckpointFlag`, `FinishFlag` (Models) |
| `ReplicatedStorage.Car.Scripts.Client.Input` | `ControlsGui` (ScreenGui) |
| `ReplicatedStorage.Car.Scripts.Client.Input.Touch` | `TouchGui` (ScreenGui) |
| `ReplicatedStorage.Car.Scripts.Client.Speedometer` | `SpeedometerGui` (ScreenGui) |
| `ReplicatedStorage.Car.Scripts.Client.Camera` | `CycleCameraMode` (BindableEvent) |
| `ReplicatedStorage.Car.Scripts.Client.ClientController.DestructionHandler` | `BindToCar` (BindableEvent) |

`SoundService.Audio.{Listener,AutoPlayAudio}` are also left unmanaged because the `Audio`
folder holds audio devices (`MainOutput`, `MainListener`, `Busses`, `Players`).

To bring these under Rojo later, generate `.rbxmx` model files for each embedded instance
(the `rbxlx-to-rojo` tool does this automatically from a saved `.rbxlx`).

## Setup

```sh
# 1. Install the toolchain (rokit manages Rojo)
#    https://github.com/rojo-rbx/rokit
rokit add rojo-rbx/rojo
rokit install

# 2. Start the server, then click Connect in the Studio Rojo plugin
rojo serve
```

## The place file

`code.rbxlx` (git-ignored) is still the source of truth for everything Rojo doesn't manage
— geometry, GUIs, models, and the embedded template instances above. Consider committing it
as a full backup: remove `/code.rbxlx` from `.gitignore` and `git add` it.

## Cleanup TODO

The old placeholder project synced Rojo's default template into Studio, leaving duplicate
junk scripts (`"Hello, world!"` stubs, 3 copies each):
`ReplicatedStorage.Shared.Hello`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`.
Delete these in Studio (or ask Claude to remove them).
