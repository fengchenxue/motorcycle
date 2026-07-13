--[[
	playFromStart - A simple utility function to play an AudioPlayer, always starting from the beginning.
	This is used to emulate the legacy sound:Play() behavior.
--]]

local function playFromStart(audioPlayer: AudioPlayer)
	audioPlayer.TimePosition = 0

	if not audioPlayer.IsPlaying then
		audioPlayer:Play()
	end
end

return playFromStart
