-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = ServerStorage:WaitForChild("Services")

local ShopAssets = Shared:WaitForChild("ShopAssets")

local DataService = require(Services:WaitForChild("DataService"))

-- Module
local ShopService = {
	Name = script.Name,
	Client = {},
	ItemList = {}
}

function ShopService.Client:Purchase(Player : Player, ItemName : string)
	
end

function ShopService:OnStart()
	for _,Category in ipairs(ShopAssets:GetChildren()) do
		
	end
end


return ShopService