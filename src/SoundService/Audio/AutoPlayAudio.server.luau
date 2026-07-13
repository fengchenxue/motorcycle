--[[
	AutoPlayAudio - A utility script to automatically play AudioPlayers tagged with "AutoPlayAudio".
	This is used since AudioPlayers do not have the same auto play functionality as legacy sounds.
--]]

local CollectionService = game:GetService("CollectionService")

local AUTO_PLAY_TAG = "AutoPlayAudio"

local function onAudioPlayerAdded(audioPlayer: Instance)
	assert(
		audioPlayer:IsA("AudioPlayer"),
		`Instance tagged with {AUTO_PLAY_TAG} ({audioPlayer:GetFullName()}) expected to be an AudioPlayer, got {audioPlayer.ClassName}`
	)

	audioPlayer:Play()
end

local function initialize()
	CollectionService:GetInstanceAddedSignal(AUTO_PLAY_TAG):Connect(onAudioPlayerAdded)

	for _, audioPlayer in CollectionService:GetTagged(AUTO_PLAY_TAG) do
		onAudioPlayerAdded(audioPlayer)
	end
end

initialize()
