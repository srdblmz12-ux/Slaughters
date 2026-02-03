-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Loader = require(Packages:WaitForChild("Loader"))

-- Init
Loader:Load(ServerStorage.Services)