--[[
	Listener - Initializes the main AudioListener, placing it in the camera.
--]]

local Workspace = game:GetService("Workspace")

local camera = Workspace.CurrentCamera
local listener = script.Parent.MainListener

listener.Parent = camera
