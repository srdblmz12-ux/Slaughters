-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")

local Charm = require(Packages:WaitForChild("Charm"))
local Promise = require(Packages:WaitForChild("Promise"))
local Net = require(Packages:WaitForChild("Net")) -- [EKLENDİ]

-- Dependencies
local DataService = require(Services:WaitForChild("DataService"))

local PlayerService = {
	Name = script.Name,
	Client = {},

	PlayerChances = {}, 

	-- [EKLENDİ]
	Network = {
		ChanceUpdate = Net:RemoteEvent("ChanceUpdate")
	}
}

--// Client Functions
function PlayerService.Client:GetChance(player)
	return PlayerService:GetChance(player)
end

--// CHANCE SYSTEM

function PlayerService:GetChance(player)
	local atom = self.PlayerChances[player]
	if atom then return atom() end
	return 0
end

function PlayerService:ResetChance(player)
	local atom = self.PlayerChances[player]
	if atom then 
		atom(0) 
		-- [EKLENDİ] Haber ver
		self.Network.ChanceUpdate:FireClient(player, 0)
	end
end

function PlayerService:AddChance(player, amount)
	local atom = self.PlayerChances[player]
	if atom then
		local value = amount or 1
		local newValue = atom() + value

		atom(newValue)
		-- [EKLENDİ] Haber ver
		self.Network.ChanceUpdate:FireClient(player, newValue)
	end
end

--// SPAWNER SYSTEM

function PlayerService:SpawnSurvivors(runningPlayers, spawnLocations)
	for player, role in pairs(runningPlayers) do
		if role == "Survivor" then
			self:_spawnPlayer(player, spawnLocations)
		end
	end
end

function PlayerService:SpawnKillers(runningPlayers, spawnLocations)
	for player, role in pairs(runningPlayers) do
		if role == "Killer" then
			self:_spawnPlayer(player, spawnLocations)
		end
	end
end

function PlayerService:DespawnAll()
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = nil
		player:LoadCharacterAsync()
	end
end

function PlayerService:_spawnPlayer(player, spawnLocations)
	if not player then return end

	if spawnLocations and #spawnLocations > 0 then
		local randomSpawn = spawnLocations[math.random(1, #spawnLocations)]
		player.RespawnLocation = randomSpawn

		local connection
		connection = player.CharacterAdded:Connect(function(character)
			local rootPart = character:WaitForChild("HumanoidRootPart", 5)
			if rootPart then
				character:PivotTo(randomSpawn.CFrame * CFrame.new(0, 3, 0))
			end
			connection:Disconnect()
		end)
	end
	player:LoadCharacterAsync()
end

function PlayerService:OnStart()
	Players.PlayerAdded:Connect(function(player)
		self.PlayerChances[player] = Charm.atom(0)
		-- [EKLENDİ] İlk girişte şansı bildir
		task.wait(1) -- Biraz bekle ki UI yüklensin
		self.Network.ChanceUpdate:FireClient(player, 0)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self.PlayerChances[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if not self.PlayerChances[player] then
			self.PlayerChances[player] = Charm.atom(0)
		end
	end
end

return PlayerService