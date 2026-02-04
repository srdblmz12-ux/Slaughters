-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")

local Charm = require(Packages:WaitForChild("Charm"))
local Promise = require(Packages:WaitForChild("Promise"))

-- Dependencies
local DataService = require(Services:WaitForChild("DataService"))

local PlayerService = {
	Name = script.Name,
	Client = {},

	PlayerChances = {}, 
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
	if atom then atom(0) end
end

function PlayerService:AddChance(player, amount)
	local atom = self.PlayerChances[player]
	if atom then
		local value = amount or 1
		atom(function(current) return current + value end)
	end
end

--// SPAWNER SYSTEM (HATA BURADAYDI, DÜZELTİLDİ)

function PlayerService:SpawnSurvivors(runningPlayers, spawnLocations)
	-- [FIX] roleAtom ismi 'role' yapıldı ve () kaldırıldı.
	for player, role in pairs(runningPlayers) do
		if role == "Survivor" then
			self:_spawnPlayer(player, spawnLocations)
		end
	end
end

function PlayerService:SpawnKillers(runningPlayers, spawnLocations)
	-- [FIX] roleAtom ismi 'role' yapıldı ve () kaldırıldı.
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