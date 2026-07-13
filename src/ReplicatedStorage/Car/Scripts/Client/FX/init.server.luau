local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Constants = require(script.Parent.Parent.Constants)
local Audio = require(script.Audio)
local Particles = require(script.Particles)
local Haptics = require(script.Haptics)

local car = script.Parent.Parent.Parent
local driverSeat = car.DriverSeat
local engine = car.Engine
local chassis = car.Chassis

local COLLISION_UPDATE_INTERVAL = 0.1 -- Time interval to calculate average change over
local COLLISION_THRESHOLD = 400 -- Amount of average change that must be passed to play a collision sound
local COLLISION_VOLUME_FACTOR = 1 / 800 -- Amount to adjust volume based on the average change

local totalSpeedChange = 0
local lastSpeed = chassis.AssemblyLinearVelocity.Magnitude
local lastCollisionUpdate = os.clock()

local function onOccupantChanged()
	if driverSeat.Occupant then
		Audio.startupEngine()
		local driver = Players:GetPlayerFromCharacter(driverSeat.Occupant.Parent)
		if driver == Players.LocalPlayer then
			Haptics.enable()
		end
	else
		Audio.shutdownEngine()
		Haptics.disable()
	end
end

local function onNitroEnabledChanged()
	local isNitroEnabled = engine:GetAttribute(Constants.NITRO_ENABLED_ATTRIBUTE)
	if isNitroEnabled then
		Audio.startNitro()
		Particles.startNitro()
		Haptics.startNitro()
	else
		Audio.stopNitro()
		Particles.stopNitro()
		Haptics.stopNitro()
	end
end

local function onHeartbeat(_deltaTime: number)
	-- Play collision effects when the speed of the car changes abruptly.
	-- This is more consistent than listening to .Touched,

	-- Calculate the change in the car's speed and add it to totalSpeedChange
	local speed = chassis.AssemblyLinearVelocity.Magnitude
	local change = math.abs(speed - lastSpeed)
	lastSpeed = speed
	totalSpeedChange += change

	local elapsed = os.clock() - lastCollisionUpdate
	if elapsed < COLLISION_UPDATE_INTERVAL then
		return
	end
	lastCollisionUpdate = os.clock()

	-- Calculate the average change in speed over the update interval
	local averageChangeOverInterval = totalSpeedChange / elapsed
	if averageChangeOverInterval > COLLISION_THRESHOLD then
		-- If the change is higher than the threshold, play collision effects
		local strength = averageChangeOverInterval * COLLISION_VOLUME_FACTOR
		Audio.playCollisionSound(strength)
		Haptics.playCollisionHaptic(strength)
	end

	totalSpeedChange = 0
end

local function initialize()
	driverSeat:GetPropertyChangedSignal("Occupant"):Connect(onOccupantChanged)
	engine:GetAttributeChangedSignal(Constants.NITRO_ENABLED_ATTRIBUTE):Connect(onNitroEnabledChanged)

	onOccupantChanged()
	onNitroEnabledChanged()
	RunService.Heartbeat:Connect(onHeartbeat)
end

initialize()
