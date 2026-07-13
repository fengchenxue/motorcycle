wait(0.5)
function unanchor (m)
	for _,i in pairs (m:GetChildren()) do
		if i:IsA("BasePart") then
			i:MakeJoints()
			i.Anchored = false
		else
			unanchor(i)
		end
	end
end
unanchor(script.Parent)