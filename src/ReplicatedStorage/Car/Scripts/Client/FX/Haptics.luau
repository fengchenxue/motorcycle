local car = script.Parent.Parent.Parent.Parent
local chassis = car.Chassis
local hapticEffects = chassis.Haptic
local collisionHaptic = hapticEffects.CollisionHaptic
local nitroHaptic = hapticEffects.NitroHaptic

local COLLISION_STRENGTH_FACTOR = 1 / 800 -- Amount to adjust haptic strength based on the average change

local Haptics = {
	enabled = false,
}

function Haptics.playCollisionHaptic(strength: number)
	if not Haptics.enabled then
		return
	end
	local hapticStr = math.clamp(1 - strength * COLLISION_STRENGTH_FACTOR, 0.0, 1.0)
	collisionHaptic.Position = Vector3.new(hapticStr * collisionHaptic.Radius, 0, 0)
	collisionHaptic:Play()
end

function Haptics.startNitro()
	if not Haptics.enabled then
		return
	end
	nitroHaptic:Play()
end

function Haptics.stopNitro()
	if not Haptics.enabled then
		return
	end
	nitroHaptic:Stop()
end

function Haptics.initCustomHapticEffect(hapticEffect: HapticEffect)
	-- Initialize haptic effect with custom curve
	if hapticEffect.Type == Enum.HapticEffectType.Custom then
		local waveformCurve = hapticEffect:GetAttribute("WaveformCurve") -- a NumberSequence attribute to represent waveform
		local waveformCurveLengthMS = hapticEffect:GetAttribute("WaveformLengthMS") -- a number attribute to represent total length of the waveform in ms
		if waveformCurve and waveformCurveLengthMS then
			local floatCurve = {}
			for _, keypoint in waveformCurve.Keypoints do
				table.insert(
					floatCurve,
					FloatCurveKey.new(
						keypoint.Time * waveformCurveLengthMS,
						keypoint.Value,
						Enum.KeyInterpolationMode.Linear
					)
				)
			end
			hapticEffect.Type = Enum.HapticEffectType.Custom
			hapticEffect:SetWaveformKeys(floatCurve)
		end
	end
end

function Haptics.enable()
	Haptics.enabled = true
end

function Haptics.disable()
	Haptics.enabled = false
end

Haptics.initCustomHapticEffect(nitroHaptic)

return Haptics
