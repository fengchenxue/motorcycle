--MADE BY SPACEK531
b = script.Parent.Parent.Base
b2 = script.Parent.Parent.Base2
l = script.Parent.Parent.Left
r = script.Parent.Parent.Right

for _,i in pairs (script.Parent.Parent:GetChildren()) do
	if i:IsA("Motor") then
		i:Destroy()
	end
end

WheelSize = 2.4--diameter of the wheel

--When you are editing the car, make sure that the Left, Right, and Base parts are in a 
--straight line, or the wheels will be somewhere you do not expect them to be

left = Instance.new("Motor", script.Parent.Parent)
right = Instance.new("Motor", script.Parent.Parent)
left.Name = "LeftMotor"
right.Name = "RightMotor"

left.Part0 = l
right.Part0 = r
left.Part1 = b2
right.Part1 = b
right.C0 = CFrame.new(-WheelSize/2-r.Size.x/2,0,0)*CFrame.Angles(math.pi/2,0,math.pi/2)
right.C1 = CFrame.new(-b.Size.x/2-r.Size.x-WheelSize/2,0,0)*CFrame.Angles(math.pi/2,0,math.pi/2)
left.C0 = CFrame.new(-1,0,0)*CFrame.Angles(0,0,math.pi/2)
left.C1 = CFrame.new()*CFrame.Angles(0,0,math.pi/2)
right.MaxVelocity = 0.02
left.MaxVelocity = 0.02