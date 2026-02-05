-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")

local Signal = require(Packages:WaitForChild("Signal"))
local Net = require(Packages:WaitForChild("Net"))

local Interface = Common:WaitForChild("Interface")
local NotificationAssets = Interface:WaitForChild("NotificationAssets")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local NotificationController = {
	Name = script.Name,
	Signals = {
		SendNotification = Signal.new()
	}
}

function NotificationController:CreateNotification(Text : string, Lifetime : number)
	if (typeof(Text) ~= "string") then return end
	if (typeof(Lifetime) ~= "number") then return end
	
	local NewNotification = NotificationAssets.Notification:Clone()
	NewNotification.Text = Text
	task.delay(Lifetime or 5, function()
		NewNotification:Destroy()
	end)
end

function NotificationController:OnStart()
	local NotificationHUD = PlayerGui:WaitForChild("NotificationHUD")
	local function AddNotification(Text : string, Lifetime : number)
		local Notification = self:CreateNotification(Text, Lifetime)
		if (not Notification) then return end
		
		Notification.Parent = NotificationHUD
	end
	
	self.Signals.SendNotification:Connect(AddNotification)
	
	local NotificationListener = Net:RemoteEvent("SendNotification")
	if (NotificationListener) then
		NotificationListener.OnClientEvent:Connect(AddNotification)
	end
end

return NotificationController