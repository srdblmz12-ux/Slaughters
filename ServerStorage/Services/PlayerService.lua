-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Services = ServerStorage:WaitForChild("Services")

-- [ÖNEMLİ] Karakter modellerinin olduğu klasör
local Characters = Shared:WaitForChild("Characters")

local Charm = require(Packages:WaitForChild("Charm"))
local Promise = require(Packages:WaitForChild("Promise"))
local Net = require(Packages:WaitForChild("Net"))

-- Dependencies
local DataService = require(Services:WaitForChild("DataService"))

local PlayerService = {
	Name = script.Name,
	Client = {},

	PlayerChances = {}, 

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
		self.Network.ChanceUpdate:FireClient(player, 0)
	end
end

function PlayerService:AddChance(player, amount)
	local atom = self.PlayerChances[player]
	if atom then
		local value = amount or 1
		local newValue = atom() + value

		atom(newValue)
		self.Network.ChanceUpdate:FireClient(player, newValue)
	end
end

--// SPAWNER SYSTEM

function PlayerService:SpawnSurvivors(runningPlayers, spawnLocations)
	for player, role in pairs(runningPlayers) do
		if role == "Survivor" then
			-- [GÜNCELLEME] Rol bilgisini gönderiyoruz
			self:_spawnPlayer(player, spawnLocations, "Survivor")
		end
	end
end

function PlayerService:SpawnKillers(runningPlayers, spawnLocations)
	for player, role in pairs(runningPlayers) do
		if role == "Killer" then
			-- [GÜNCELLEME] Rol bilgisini gönderiyoruz
			self:_spawnPlayer(player, spawnLocations, "Killer")
		end
	end
end

function PlayerService:DespawnAll()
	for _, player in ipairs(Players:GetPlayers()) do
		player.RespawnLocation = nil
		player:LoadCharacterAsync()
	end
end

function PlayerService:_spawnPlayer(player, spawnLocations, role)
	if not player then return end

	DataService:GetProfile(player):andThen(function(profile)
		-- Spawn noktası belirleme
		local randomSpawn = nil
		if spawnLocations and #spawnLocations > 0 then
			randomSpawn = spawnLocations[math.random(1, #spawnLocations)]
			player.RespawnLocation = randomSpawn
		end
		local spawnCFrame = randomSpawn and (randomSpawn.CFrame * CFrame.new(0, 3, 0)) or CFrame.new(0, 10, 0)

		-- KATİL İSE
		if role == "Killer" then
			local equippedSkin = profile.Data.Equippeds and profile.Data.Equippeds.KillerSkin

			-- Skin bulmaca
			local characterModel = nil
			if equippedSkin then characterModel = Characters:FindFirstChild(equippedSkin) end
			if not characterModel then characterModel = Characters:FindFirstChild("Wendigo") end

			if characterModel then
				local newCharacter = characterModel:Clone()
				newCharacter.Name = player.Name
				newCharacter:PivotTo(spawnCFrame)
				newCharacter.Parent = workspace
				player.Character = newCharacter

				local rootPart = newCharacter:FindFirstChild("HumanoidRootPart")
				if rootPart then
					rootPart:SetNetworkOwner(player)
				end

				return
			else
				warn("HATA: Wendigo modeli bulunamadı!")
			end
		end

		-- SURVIVOR İSE (veya katil modeli yüklenemediyse)
		local connection
		connection = player.CharacterAdded:Connect(function(character)
			local rootPart = character:WaitForChild("HumanoidRootPart", 5)
			if rootPart then
				character:PivotTo(spawnCFrame)
			end
			if connection then connection:Disconnect() end
		end)

		player:LoadCharacterAsync()

	end):catch(function(err)
		warn("Spawn hatası:", err)
		player:LoadCharacterAsync()
	end)
end

function PlayerService:OnStart()
	Players.PlayerAdded:Connect(function(player)
		self.PlayerChances[player] = Charm.atom(0)
		task.wait(1) 
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