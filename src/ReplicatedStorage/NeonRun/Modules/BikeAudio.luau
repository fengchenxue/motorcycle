-- NeonRun / BikeAudio (M3) —— 占位音效三层(策划案 §5 声音三层)
-- 1 引擎底噪随速度升调 | 2 冲刺点火爆音 | 3 近距擦墙呼啸
-- 素材全部来自 Roblox 官方免费音频库(Pro Sound Effects),正式音效 V2 美术 Pass 替换。
local RS = game:GetService("ReplicatedStorage")

-- 占位 assetId 常量区
local SFX = {
	Engine   = "rbxassetid://9119386571", -- Spacecraft Engine Idle(循环底噪,赛博感)
	Ignition = "rbxassetid://9125920594", -- Searing Whoosh Fast Rushing(1.3s 点火)
	Whoosh   = "rbxassetid://9114377713", -- Fast Whoosh By Air Mass(载具掠过)
}

local BikeAudio = {}
BikeAudio.__index = BikeAudio

local function mkSound(parent, id, looped)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped or false
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 220
	s.Parent = parent
	return s
end

function BikeAudio.new(rootPart)
	local self = setmetatable({}, BikeAudio)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	local inst = nr.Config.Handling
	self.cfg = ConfigLive.bind(inst, require(inst))
	self.engine = mkSound(rootPart, SFX.Engine, true)
	self.ignition = mkSound(rootPart, SFX.Ignition, false)
	self.whoosh = mkSound(rootPart, SFX.Whoosh, false)
	self.prevSprint = false
	self.prevWall = false
	self.whooshAt = -math.huge
	self.time = 0
	return self
end

-- tele = ctrl:getTelemetry()
function BikeAudio:update(tele, dt)
	local C = self.cfg.get
	self.time += dt
	-- 层1:引擎升调
	local maxSpeed = C("Speed", "Base") * C("Speed", "SprintMultiplier")
	local frac = math.clamp(tele.speed / math.max(maxSpeed, 1), 0, 1)
	self.engine.Volume = C("Sound", "EngineVolume")
	self.engine.PlaybackSpeed = C("Sound", "EnginePitchMin")
		+ (C("Sound", "EnginePitchMax") - C("Sound", "EnginePitchMin")) * frac
	if not self.engine.IsPlaying then self.engine:Play() end
	-- 层2:冲刺点火(上升沿)
	-- 读 sprinting(=有效冲刺,含最小点火尾段、且能量允许)而非原始 sprint:
	-- 空箱按键 0 能量时 sprinting 恒 false → 不放点火 whoosh,干点火"咔哒"由 UI 空箱反馈出(ADR-13)
	if tele.sprinting and not self.prevSprint then
		self.ignition.Volume = C("Sound", "IgnitionVolume")
		self.ignition:Play()
	end
	self.prevSprint = tele.sprinting == true
	-- 层3:擦墙呼啸(wallContact 上升沿 + 冷却)
	if tele.wallContact and not self.prevWall
		and self.time - self.whooshAt >= C("Sound", "WhooshCooldownSec") then
		self.whoosh.Volume = C("Sound", "WhooshVolume")
		self.whoosh.PlaybackSpeed = 1.2 + 0.5 * frac
		self.whoosh:Play()
		self.whooshAt = self.time
	end
	self.prevWall = tele.wallContact == true
end

function BikeAudio:destroy()
	self.engine:Destroy()
	self.ignition:Destroy()
	self.whoosh:Destroy()
end

return BikeAudio