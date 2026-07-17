-- NeonRun / RaceSFX (表现层) —— 比赛流程与状态音效:游戏事件→音效的唯一映射处(ADR-50j)
-- 素材=ProSoundEffects 官方(选品双重验证管线见 ADR-50i);唯一例外:敌火=内置占位变调
-- (官方库激光类关键词零命中,rbxasset 引擎自带=零许可风险,正式激光待补选)。
-- 变调复用一件素材出多个语义:GO=倒计时 beep 升调 1.4/终点=beep 族低速 0.75/心流=点火 whoosh 升调 1.3。
-- 音量全走 Sound_* Attributes(0=静,实时生效);播放永不阻塞、永不触碰物理(表现层铁律)。
-- 用法:sfx = RaceSFX.new(rootPart); sfx:play("pickup"); sfx:playAt("enemyFire", part); sfx:destroy()
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local SLOTS = {
	pickup    = { id = "rbxassetid://9120162271", vol = "PickupVolume" },                 -- Tone Clusters High Pitch 20(0.5s,UI 类)
	countdown = { id = "rbxassetid://9125540237", vol = "CountdownVolume" },              -- Electronic Tinkles Falling Beeps 1(0.6s)
	go        = { id = "rbxassetid://9125540237", vol = "CountdownVolume", speed = 1.4 }, -- 同 beep 升调=GO(一件素材两语义)
	finish    = { id = "rbxassetid://9125540222", vol = "FinishVolume", speed = 0.75 },   -- beep 族低速=临时终点 sting(正经终点乐待选品)
	playerHit = { id = "rbxassetid://9125672739", vol = "PlayerHitVolume" },              -- Sledge Hammer 族亲兄弟(与斩击命中 ...726 区分)
	respawn   = { id = "rbxassetid://9114444008", vol = "RespawnVolume" },                -- Fire Whoosh 3(回取瞬移感)
	flow      = { id = "rbxassetid://9125920594", vol = "FlowVolume", speed = 1.3 },      -- Searing Whoosh 升调=心流升档(与冲刺点火 1.0 区分)
	emptyBox  = { id = "rbxassetid://9120149295", vol = "EmptyClickVolume", speed = 0.8 },-- Tone Clusters 5 降速=干点火咔哒(M8.1 欠账清)
	enemyFire = { id = "rbxasset://sounds/electronicpingshort.wav", vol = "EnemyFireVolume", speed = 0.6 }, -- 内置占位:激光 pew
}

-- BGM(ADR-50n,人类直令"找个有动感的背景音乐"):官方曲库选品(同 ADR-50i 双重验证:
-- GetProductInfo 验官方号 + Sound IsLoaded 装载验证)。循环 2D 声源挂 SoundService(不走 rootPart
-- 3D 衰减);音量键 Sound_MusicVolume 实时生效(0=停,>0=起播/调量);跨 R 重开连续不断流。
-- 备选(已过同管线,换曲改 id 即可):9038252619 Metal Sci-Fi Universe(APM 154s,合成器金属更冲)
--   / 139421275515323 Neon Skyline(Distrokid 164.7s,复古合成波较柔)。听感/选曲=人类试玩裁决。
local MUSIC = { id = "rbxassetid://9044545570", vol = "MusicVolume" } -- Night Run(APM,183s,夜驰 Drum&Bass)

local RaceSFX = {}
RaceSFX.__index = RaceSFX

function RaceSFX.new(rootPart)
	local self = setmetatable({}, RaceSFX)
	local nr = RS:WaitForChild("NeonRun")
	local ConfigLive = require(nr.Modules.ConfigLive)
	self.cfg = ConfigLive.bind(nr.Config.Handling, require(nr.Config.Handling))
	self.sounds = {}
	for name, def in pairs(SLOTS) do
		local s = Instance.new("Sound")
		s.Name = "RaceSFX_" .. name
		s.SoundId = def.id
		s.PlaybackSpeed = def.speed or 1
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMaxDistance = 250
		s.Parent = rootPart
		self.sounds[name] = s
	end
	-- BGM:循环 2D 声源+音量键实时监听(0=停;attribute 信号驱动,面板改值即生效)
	local music = Instance.new("Sound")
	music.Name = "RaceSFX_music"
	music.SoundId = MUSIC.id
	music.Looped = true
	music.Parent = game:GetService("SoundService")
	self.music = music
	local function applyMusic()
		local vol = self.cfg.get("Sound", MUSIC.vol)
		if not vol or vol <= 0 then
			if music.IsPlaying then music:Stop() end
		else
			music.Volume = vol
			if not music.IsPlaying then music:Play() end
		end
	end
	self._musicConn = nr.Config.Handling:GetAttributeChangedSignal("Sound_" .. MUSIC.vol):Connect(applyMusic)
	applyMusic()
	return self
end

-- 车根播放(声源=听者旁≈2D 感);音量键=0 时连 Play 都不调(移动端省混音)
function RaceSFX:play(name)
	local def, s = SLOTS[name], self.sounds[name]
	if not (def and s) then return end
	local vol = self.cfg.get("Sound", def.vol)
	if not vol or vol <= 0 then return end
	s.Volume = vol
	s:Play()
end

-- 位置化播放(敌火=声从射手方位来,可听声辨位):克隆挂到目标件,播完 Debris 自灭
function RaceSFX:playAt(name, part)
	local def, s = SLOTS[name], self.sounds[name]
	if not (def and s and part and part.Parent) then return end
	local vol = self.cfg.get("Sound", def.vol)
	if not vol or vol <= 0 then return end
	local c = s:Clone()
	c.Volume = vol
	c.Parent = part
	c:Play()
	Debris:AddItem(c, 4)
end

function RaceSFX:destroy()
	for _, s in pairs(self.sounds) do s:Destroy() end
	self.sounds = {}
	if self._musicConn then self._musicConn:Disconnect(); self._musicConn = nil end
	if self.music then self.music:Destroy(); self.music = nil end
end

return RaceSFX
