-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Loader = require(Packages:WaitForChild("Loader"))

-- Init
Loader:Load(ReplicatedStorage.Controllers)