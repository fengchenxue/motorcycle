--MADE BY NWSPACEK
wait(1)-- give it time to adjust to the scary and new environment of Backpack
SeatValue = script:WaitForChild("Seat")-- orient ourselves to the car we are sitting in
if SeatValue:IsA("ObjectValue") and SeatValue.Value and SeatValue.Value:IsA("VehicleSeat") then
	seat = SeatValue.Value
	car = seat.Parent
	if seat:FindFirstChild("RocketPropulsion") then
		seat.RocketPropulsion:Fire()--THIS DOESNT WORK MEGA QQ
	end
	while seat:FindFirstChild("SeatWeld") do--what this loop does is continue running until the 
		wait()--statement between the "while" and "do" is not true. 
		if car:FindFirstChild("LeftMotor") then
			car.LeftMotor.DesiredAngle = seat.Steer*math.rad(20-seat.Velocity.magnitude/10)
		end
		if car:FindFirstChild("RightMotor") then
			car.RightMotor.DesiredAngle = seat.Steer*math.rad(20-seat.Velocity.magnitude/10)
		end
		if car:FindFirstChild("Configuration") then
			if seat.Throttle == 1 and car.Configuration:FindFirstChild("Forwards Speed") then
				seat.MaxSpeed = car.Configuration["Forwards Speed"].Value
			elseif seat.Throttle == 0 then
				seat.MaxSpeed = 0
			elseif seat.Throttle == -1 and car.Configuration:FindFirstChild("Reverse Speed") then
				seat.MaxSpeed = car.Configuration["Reverse Speed"].Value
			end
		end
	end
	-- the interesting thing about loops is they stop everything below them from running
	-- until the loop stops. When the loop stops because the player is no longer sitting
	-- the below code will run:
	if seat:FindFirstChild("RocketPropulsion") then
		seat.RocketPropulsion:Abort()--I'LL JUST LEAVE IT IN IN CASE IT EVER DOES
	end
end
script:Destroy()-- momma always said to clean up after yourself