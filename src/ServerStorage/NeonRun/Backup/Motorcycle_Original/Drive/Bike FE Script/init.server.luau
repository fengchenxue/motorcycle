--MADE BY NWSPACEK

--please note: this script is modified from the originals (the ones in the cars).
--If you are looking for scripting tips and tricks, I suggest looking at one from
--a car instead of this bike!
wait(0.1)
Players = game:GetService("Players")

seat = script.Parent-- the driving seat
car = seat.Parent

Player = nil

forwardsSpeed = 80--if you removed the Configuration folder, it defaults to this speed forwards
reverseSpeed = 10--if you removed the Configuration folder, it defaults to this speed backwards
StartTime = 1--how long (in seconds) the car should wait before starting up. This is dependant on the starting sfx

engineBlock = car:FindFirstChild("EngineBlock")--maybe someone doesn't like sound?

lightsOn = false-- whether or not the lights turn on
carRunning = false--whether or not the car is running

RemoteControlled = car:FindFirstChild("ControlByRemote")--this is so the car turns properly

function CalculatePitch()--this returns the pitch that the engine should be at when its travelling
	return 1+engineBlock.Velocity.magnitude/100
end

Configuration = car:FindFirstChild("Configuration")-- so you can change the stats of the car
if Configuration then-- if we found an object named Configuration in the car then do this stuff:
	local ReverseSpeedValue = Configuration:FindFirstChild("Reverse Speed")-- do we have a reverse speed?
	if ReverseSpeedValue ~= nil then
		if type(ReverseSpeedValue.Value) == "number" then
			reverseSpeed = ReverseSpeedValue.Value
		end
		ReverseSpeedValue.Changed:connect(function()-- level 1 scripting: go
			if ReverseSpeedValue.Parent ~= nil then-- this script works, but there are some things
				if type(ReverseSpeedValue.Value) == "number" then-- to make it look a little better
					reverseSpeed = ReverseSpeedValue.Value
					UpdateVehicle()
				end
			end
		end)
	end
	local ForwardsSpeedValue = Configuration:FindFirstChild("Forwards Speed")
	if ForwardsSpeedValue then
		if type(ForwardsSpeedValue.Value) == "number" then
			forwardsSpeed = ForwardsSpeedValue.Value
		end
		ForwardsSpeedValue.Changed:connect(function()-- level 2 scripting: go
			if ForwardsSpeedValue.Parent then -- asking if something 'is' is the same as 
				if ForwardsSpeedValue.Value then-- asking if it is "~= nil"
					forwardsSpeed = ForwardsSpeedValue.Value
					UpdateVehicle()
				end		
			end
		end)
	end
	local TorqueValue = Configuration:FindFirstChild("Torque")
	if TorqueValue then
		if type(TorqueValue.Value)=="number" and RemoteControlled then
			RemoteControlled.Torque = TorqueValue.Value
		end
		TorqueValue.Changed:connect(function()
			if TorqueValue.Parent and type(TorqueValue.Value) == "number" and RemoteControlled then
				RemoteControlled.Torque = TorqueValue.Value
			end
		end)
	end
end

script.BikeSteering.Seat.Value = seat

if RemoteControlled and not RemoteControlled:IsA("VehicleSeat") then-- how dare you try to disturb this ancient harmony
	RemoteControlled = nil-- no food 4 u!
end

seat.ChildAdded:connect(function(it)-- something was added to our seat!
	if it:IsA("Weld") and it.Name == "SeatWeld" then-- is it the kind of thing players use to sit with?
		Player = Players:GetPlayerFromCharacter(it.Part1.Parent)-- is there a player attached to it?
		if Player then-- hooray! a player WAS attached to the seat weld. It's time to start the car!
			script.BikeSteering:Clone().Parent = Player.Backpack-- for better driving
			if RemoteControlled then
				RemoteControlled.MaxSpeed = 0-- not yet little child
			end
			if engineBlock and engineBlock:FindFirstChild("Starting") and engineBlock.Starting:IsA("Sound") then
				engineBlock.Starting:Play()
			end
			if engineBlock and engineBlock:FindFirstChild("Stopping") and engineBlock.Stopping:IsA("Sound") then
				engineBlock.Stopping:Stop()
			end
			wait(StartTime)-- just in case you use different starting sound effects
			if it.Parent ~= seat then-- DID OUR LOVELY PLAYER LEAVE WHILE WE WEREN'T LOOKING???????
				byebye()--maybe they did, so it's time to shut down the car
			else-- they didn't leave!
				lightsOn = true-- turn on the lights
				carRunning = true-- turn on the car
				updatelights()-- make sure we turn on the lights
				UpdateVehicle()-- maybe they're in a hurry, so we better check if they have their foot on the gas
				if engineBlock and engineBlock:FindFirstChild("Running") and engineBlock.Running:IsA("Sound") then
					engineBlock.Running:Play()
					engineBlock.Running.Pitch = CalculatePitch()
				end
			end
		end
	end
end)

seat.ChildRemoved:connect(function(it)--did an object get removed?
	if it:isA("Weld") and it.Name == "SeatWeld" then-- if it's a weld and named like a seat weld
		byebye()-- time to shut down the car
	end
end)

function byebye()
	if engineBlock and carRunning then-- remember scripting level 3? that applies to below:
		if engineBlock and engineBlock:FindFirstChild("Stopping") and engineBlock.Stopping:IsA("Sound") then
			engineBlock.Stopping:Play()-- where if it didn't do it like that, the above would error!
			wait(0.1)					-- because engineBlock.Stopping would not exist, so :IsA() is
		end								-- "not a valid member"
		if engineBlock and engineBlock:FindFirstChild("Running") and engineBlock.Running:IsA("Sound") then
			engineBlock.Running:Stop()-- WE MUST NOT STOP
		end
		if engineBlock and engineBlock:FindFirstChild("Starting") and engineBlock.Starting:IsA("Sound") then
			engineBlock.Starting:Stop()-- THIS SCRIPT IS BREAK-PROOF >:U
		end
	end
	if RemoteControlled then
		RemoteControlled.MaxSpeed = 0--make sure that the car doesn't drive off without us
	end
	carRunning = false
	lightsOn = false
	updatelights()--turn the lights off
	UpdateVehicle()--make sure the car stops now that it's off
end

RearLight = {}--all the brake lights. These contain one SpotLight that gets manipulated
RearBulb = {}--the brake lights that use a Surface GUI to light up
FrontLight = {}--same as the RearLight but for the front
FrontBulb = {}--same as the RearBulb but for the front
ReverseLight = {}--These light up when you reverse
ReverseBulb = {}--these also light up when you reverse: SurfaceGui style

for _, i in pairs (car:GetChildren()) do--populate the tables for ease of modularity.
	if i.Name == "RearBulb" then-- you can have any number of these items you want
		table.insert(RearBulb,i)-- and you don't have to change the script one bit!
	elseif i.Name == "RearLight" then
		table.insert(RearLight,i.SpotLight)
	elseif i.Name == "FrontLight" then
		table.insert(FrontLight,i.SpotLight)
	elseif i.Name == "ReverseLight" then
		table.insert(ReverseLight,i.SpotLight)
	elseif i.Name == "FrontBulb" then
		table.insert(FrontBulb,i)
	elseif i.Name == "ReverseBulb" then
		table.insert(ReverseBulb,i)
	end
end

function updatelights()-- this turns the lights on and off based on the lightsOn value
	for _,i in pairs (RearLight) do
		i.Enabled = lightsOn
	end
	for _,i in pairs (FrontLight) do
		i.Enabled = lightsOn
	end
	for _,i in pairs (FrontBulb) do
		SurfaceGuiStandard(i,lightsOn)
	end
	for _,g in pairs (RearBulb) do
		SurfaceGuiBrightness(g,lightsOn,seat.Throttle == 0)
	end
end

function CreateStabilizer()
	if car:FindFirstChild("Stabilizer") then
		car.Stabilizer:Destroy()
	end
	if car:FindFirstChild("LeftHelper") then
		local stabilizer = Instance.new("Part",car)
		stabilizer.CanCollide = false--the bike not working was because I forgot this!
		stabilizer.BottomSurface = "Smooth"
		stabilizer.TopSurface = "Smooth"
		stabilizer.FormFactor = "Custom"
		stabilizer.Size = Vector3.new(3,3,1)
		stabilizer.Transparency = 1
		stabilizer.Name = "Stabilizer"
		stabilizer.CFrame = car.LeftHelper.CFrame*CFrame.new(0,0,1)
		local Hinge = Instance.new("Rotate",stabilizer)--mega hax!
		Hinge.C0 = CFrame.new()
		Hinge.C1 = CFrame.new(0,0,-1)
		Hinge.Part0 = car.LeftHelper
		Hinge.Part1 = stabilizer
		local gyro = Instance.new("BodyGyro",stabilizer)
		gyro.D = 700
		gyro.maxTorque = Vector3.new(600000, 0, 600000)
		gyro.P = 30000
		gyro.cframe = CFrame.new()*CFrame.Angles(math.pi,math.pi/2,0)
	end
end

flippingDebounce = false-- a debounce is a simple way of preventing a function from
						-- being called multiple times while it's still running
function Flip()
	if not flippingDebounce then-- here's how it works: the function checks if the debounce is off
		flippingDebounce = true-- if it's on, then the function stops, but if it's off, set it to true
		local bodypos = Instance.new("BodyPosition",seat)-- so we get uninterupted function fun
		bodypos.maxForce = Vector3.new(100000,10000000,100000)
		bodypos.position = seat.Position + Vector3.new(0,2,0)
		local bodygyro = Instance.new("BodyGyro",seat)
		game:GetService("Debris"):AddItem(bodypos, 3)-- this makes sure that the flippy bit
		game:GetService("Debris"):AddItem(bodygyro, 3)-- deletes itself automatically
		wait(2)
		CreateStabilizer()
		wait(1)
		flippingDebounce = false-- when we are done with our fun, allow the function to work again
	end
end

function SurfaceGuiStandard(part,on)-- this makes it so the lights turn on or off
	for _,i in pairs (part:GetChildren()) do
		if i:IsA("SurfaceGui") then
			i.Enabled = on
		end
	end
end

function SurfaceGuiBrightness(part,on,bright)-- this is so the brake lights dim when we drive
	for _,i in pairs (part:GetChildren()) do
		if i:IsA("SurfaceGui") then
			i.Enabled = on
			if i:FindFirstChild("Frame") and i.Frame:IsA("Frame") then
				i.Frame.Transparency = bright and 0 or 0.5-- scripting level 4: go
			end-- for simple statements, you can have a boolean value decide between 2 values
			-- which is the same as writing	
			-- "if bright then
			--		i.Frame.Transparency = 0
			--	else
			--		i.Frame.Transparency = 0.5
			-- end"
			--but instead of "then" and "else", you use "and" and "or"
		end
	end
end

hornDebounce = false
function Honk()-- if you are reading this then congratulations! you win a prize!
	if hornDebounce then return end-- unfortunately, I could not think of a way
	if engineBlock and engineBlock:FindFirstChild("Horn") and engineBlock.Horn:IsA("Sound") then
		hornDebounce = true-- to allow people to be able to honk the horn for both PC and mobile
		engineBlock.horn:Play()	-- in an unobtrusive way. Sorry! :(
		print("beep beep") -- UristMcSparks, the guy in charge of the toolbox, doesn't want print statements
		wait(0.5)-- but since this is a secret, lets keep it between you and me, OK?
		engineBlock.horn:Stop()
		hornDebounce = false
	end
end

function UpdateVehicle()-- this is for the brake lights and speed and stuff like that
	if seat.Throttle == 1 and carRunning then-- if we're going forwards
		seat.MaxSpeed = forwardsSpeed-- give it forwards speed
	elseif seat.Throttle == -1 and carRunning then-- if we're going backwards
		seat.MaxSpeed = reverseSpeed-- give it backwards speed
	else
		seat.MaxSpeed = 0 -- otherwise, give it 0 speed
	end
	if workspace.FilteringEnabled and RemoteControlled then--the idea from scripting level 2 applies to false as well
		RemoteControlled.Throttle = seat.Throttle-- that is, it also works for "~= false"
	end-- the reason this line exists is to prevent the server from doing something the client
	-- is already doing.
	for _,h in pairs (ReverseLight) do-- all these loops below are just updating the lights
		h.Enabled = lightsOn and seat.Throttle == -1
	end
	for _,i in pairs (ReverseBulb) do
		SurfaceGuiStandard(i,lightsOn and seat.Throttle == -1)
	end
	for _,j in pairs (RearLight) do
		j.Brightness = 4-math.abs(seat.Throttle)*3
	end
	for _,k in pairs (RearBulb) do
		SurfaceGuiBrightness(k,lightsOn,seat.Throttle == 0)
	end
end

seat.Changed:connect(UpdateVehicle)-- this is so that when someone drives the car
								   -- the brake and reverse lights change
								   -- and the speed of the car changes
CreateStabilizer()

while true do
	for i = 1, 60 do--60/30 == 2, 2 seconds between deciding if it's upside down
		wait()-- we want the steering and sfx to update as many times a second as we can
		if workspace.FilteringEnabled then
			if car:FindFirstChild("LeftMotor") then
				car.LeftMotor.DesiredAngle = seat.Steer*math.rad(20-seat.Velocity.magnitude/10)
			end
			if car:FindFirstChild("RightMotor") then
				car.RightMotor.DesiredAngle = seat.Steer*math.rad(20-seat.Velocity.magnitude/10)
			end
		end
		-- below: make sure there's a sound to play
		if carRunning and engineBlock and engineBlock:FindFirstChild("Running") and engineBlock.Running:IsA("Sound") then
			engineBlock.Running.Pitch = CalculatePitch()-- and make sure that the car is on before trying
												-- to make sure the engine sounds good
		end
	end
	if car:FindFirstChild("Stabilizer") and car:FindFirstChild("LeftHelper") then
		if car.Stabilizer.CFrame.lookVector:Dot(car.LeftHelper.CFrame.lookVector) < 0.85 then
			CreateStabilizer()
		end 
	elseif car:FindFirstChild("LeftHelper") then
		CreateStabilizer()
	end
	if not flippingDebounce and (seat.CFrame*CFrame.Angles(math.pi/2,0,0)).lookVector.Y < 0.2 then--am I upside down?
		Spawn(Flip)--flip the bike right side up
		
		-- as a fun experiment, see what happens if you replace "Spawn(Flip)" with "Flip()"
		-- and see what the difference is when you drive the car off the baseplate
		-- if you did it right, you'll notice that the engine sound changes differently!
	end
end

-- scripting level 1000000: go
-- if you type 2 dashes like this "--" you can create a comment
-- comments aren't executed, so you can type stuff like this!

--[==[
	
	if you want to make longer comments
	
	you can surround them with the double dashes and double square brackets "--[[" and "--]]"
	
	and you can surround those by ones with equals signs in them too

	so you don't have to type the "--" every single line
	
--]==]


--Thanks for watching!
--NWSpacek