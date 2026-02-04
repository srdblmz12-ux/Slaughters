--[[
    GameService.lua
    Oyunun ana döngüsünü, oylama sistemini, oyuncu rollerini ve HUD verilerini yönetir.
    Eklemeler: Client API, PlayerRemoving Kontrolü, Yardımcı Metotlar.
]]

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")
local GameModesFolder = Modules:WaitForChild("GameModes")

-- Dependencies
local Promise = require(Packages:WaitForChild("Promise"))
local Signal = require(Packages:WaitForChild("Signal"))
local Charm = require(Packages:WaitForChild("Charm"))
local Net = require(Packages:WaitForChild("Net"))

-- Service Dependencies
local DataService = require(Services:WaitForChild("DataService")) 
local PlayerService = require(Services:WaitForChild("PlayerService"))
local MapService = require(Services:WaitForChild("MapService"))

-- Constants
local CONFIG = {
	VOTING_TIME = 15,
	WARMUP_TIME = 10,
	GAME_TIME = 90,
	INTERMISSION = 5,
	MIN_PLAYERS = 2
}

-- Module Definition
local GameService = {
	Name = script.Name,
	Client = {}, -- Client tarafına açık fonksiyonlar

	-- Global State Atoms (Charm)
	Gamemode = Charm.atom("Waiting"),
	TimeLeft = Charm.atom(0), 
	GameStatus = Charm.atom("Intermission"), 
	SurvivorCount = Charm.atom(0),

	-- Admin & Voting State
	NextMapOverride = Charm.atom(nil),
	CurrentOptions = Charm.atom({}), 
	Votes = Charm.atom({}),             

	-- Internal Game State
	RunningPlayers = {}, -- { [Player] = "Killer" | "Survivor" }
	_connections = {}, 
	_gameLoopTask = nil,
	_activeModeModule = nil,

	Signals = {
		GameEnded = Signal.new(),
		WarmupStarted = Signal.new(), 
		GameStarted = Signal.new(),   
	},

	Network = {
		StateUpdate = Net:RemoteEvent("StateUpdate"),
		VoteOptions = Net:RemoteEvent("VoteOptions"), 
		VoteUpdate = Net:RemoteEvent("VoteUpdate"),     
		WarmupStarted = Net:RemoteEvent("WarmupStarted"),
		GameStarted = Net:RemoteEvent("GameStarted"),
		GameEnded = Net:RemoteEvent("GameEnded"),
		CastVote = Net:RemoteEvent("CastVote"),
		LoadLighting = Net:RemoteEvent("LoadLighting"),
		Results = Net:RemoteEvent("Results"),
	}
}

-- Client metodlarının ana tabloya erişebilmesi için referans enjeksiyonu
GameService.Client.Server = GameService

---

-- =============================================================================
--  CLIENT API (Net modülü üzerinden çağrılabilir)
-- =============================================================================

-- Tüm oyuncuların isimlerini ve rollerini (Killer/Survivor/Lobby) liste olarak döner
function GameService.Client:GetPlayersStatus(player)
	local list = {}

	for _, p in ipairs(Players:GetPlayers()) do
		-- Eğer RunningPlayers içinde kaydı yoksa Lobby'dedir
		local currentRole = self.Server.RunningPlayers[p] or "Lobby"
		list[p.Name] = currentRole
	end

	return list
end

-- Belirli bir oyuncunun verilerini detaylı döner
function GameService.Client:GetPlayerData(player, targetPlayerName: string)
	local target = Players:FindFirstChild(targetPlayerName)
	if not target then return nil end

	return {
		PlayerName = target.Name,
		Role = self.Server.RunningPlayers[target] or "Lobby",
		UserId = target.UserId,
		IsAlive = (target.Character and target.Character:FindFirstChild("Humanoid") and target.Character.Humanoid.Health > 0) or false
	}
end

---

-- =============================================================================
--  HELPER FUNCTIONS
-- =============================================================================

-- Oylama sayılarını hesaplar
function GameService:_calculateVoteCounts()
	local options = self.CurrentOptions()
	local votes = self.Votes()
	local counts = {}

	for _, data in ipairs(options) do 
		counts[data.Id] = 0 
	end

	for _, mapId in pairs(votes) do
		if counts[mapId] ~= nil then 
			counts[mapId] = counts[mapId] + 1 
		end
	end

	return counts
end

-- Yaşayan Survivor sayısını döndürür
function GameService:_countSurvivors()
	local count = 0
	for _, role in pairs(self.RunningPlayers) do
		if role == "Survivor" then 
			count = count + 1 
		end
	end
	return count
end

-- Yaşayan Killer sayısını döndürür (Özellikle oyuncu çıkış kontrolleri için)
function GameService:_countKillers()
	local count = 0
	for _, role in pairs(self.RunningPlayers) do
		if role == "Killer" then
			count = count + 1
		end
	end
	return count
end

-- Ağırlıklı Şans Sistemi (Katil Seçimi)
function GameService:SelectWeightedKiller(playerCandidates)
	local totalChance = 0
	local selectionPool = {}

	for _, player in ipairs(playerCandidates) do
		local chance = PlayerService:GetChance(player)
		if chance <= 0 then chance = 1 end

		totalChance = totalChance + chance
		table.insert(selectionPool, {Player = player, Weight = totalChance})
	end

	local randomNumber = math.random(1, totalChance)
	for _, poolEntry in ipairs(selectionPool) do
		if randomNumber <= poolEntry.Weight then
			return poolEntry.Player
		end
	end
	return playerCandidates[1]
end

function GameService:SetNextMap(mapName)
	local mapModule = MapService:FindMapModule(mapName)
	if mapModule then
		self.NextMapOverride(mapModule)
		return true
	end
	return false
end

function GameService:CastVote(player, mapId)
	if self.GameStatus() ~= "OnVoting" then return end

	local isValid = false
	for _, op in ipairs(self.CurrentOptions()) do 
		if op.Id == mapId then 
			isValid = true 
			break 
		end 
	end

	if not isValid then return end

	self.Votes(function(v) 
		local n = table.clone(v) 
		n[player.UserId] = mapId 
		return n 
	end)
end

---

-- =============================================================================
--  GAME PHASES
-- =============================================================================

function GameService:RunVotingPhase()
	self.GameStatus("OnVoting")
	self.TimeLeft(CONFIG.VOTING_TIME)

	local processedOptions = MapService:GetProcessedVoteOptions(3)
	self.CurrentOptions(processedOptions)
	self.Votes({})

	self.Network.VoteOptions:FireAllClients(processedOptions, CONFIG.VOTING_TIME)

	for t = CONFIG.VOTING_TIME, 1, -1 do
		self.TimeLeft(t)
		task.wait(1)

		if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then 
			return nil 
		end
	end

	local counts = self:_calculateVoteCounts()
	local maxV, candidates = -1, {}

	for id, c in pairs(counts) do
		if c > maxV then 
			maxV = c 
			candidates = {id} 
		elseif c == maxV then 
			table.insert(candidates, id) 
		end
	end

	local winnerId = candidates[math.random(1, #candidates)]
	local winnerModule = MapService:FindMapModule(winnerId)

	if not winnerModule and #processedOptions > 0 then 
		winnerModule = MapService:FindMapModule(processedOptions[1].Id) 
	end

	return winnerModule
end

function GameService:StartGame()
	local activePlayers = Players:GetPlayers()

	if #activePlayers < CONFIG.MIN_PLAYERS then 
		return Promise.reject("Yetersiz Oyuncu") 
	end

	local mapModule = self.NextMapOverride() or self:RunVotingPhase()
	self.NextMapOverride(nil)

	if not mapModule then 
		return Promise.reject("Harita seçilemedi") 
	end

	self.GameStatus("Loading")

	local promises = {}
	for _, player in ipairs(activePlayers) do 
		table.insert(promises, DataService:GetProfile(player)) 
	end

	return Promise.all(promises):andThen(function()
		local mapData = MapService:LoadMap(mapModule)
		if not mapData then error("Harita Yüklenemedi") end

		if mapData.Lighting then 
			self.Network.LoadLighting:FireAllClients(mapData.Lighting) 
		end

		self:_setupGameMode(activePlayers)
		self.SurvivorCount(self:_countSurvivors())

		self.GameStatus("Warmup")
		self.TimeLeft(CONFIG.WARMUP_TIME)

		self.Network.WarmupStarted:FireAllClients(self.Gamemode(), self.RunningPlayers, CONFIG.WARMUP_TIME)
		self.Signals.WarmupStarted:Fire()

		PlayerService:SpawnSurvivors(self.RunningPlayers, mapData.Spawns)
		self:_setupPlayerMonitoring()

		for t = CONFIG.WARMUP_TIME, 1, -1 do
			self.TimeLeft(t)
			task.wait(1)

			if #Players:GetPlayers() < CONFIG.MIN_PLAYERS then 
				self:EndGame(nil) 
				return 
			end
		end

		self.GameStatus("GameRunning")
		PlayerService:SpawnKillers(self.RunningPlayers, mapData.Spawns)

		local modeDuration = (self._activeModeModule and self._activeModeModule.Time) or CONFIG.GAME_TIME
		self.Network.GameStarted:FireAllClients(modeDuration)
		self.Network.StateUpdate:FireAllClients("TimeLeft", modeDuration) 
		self.Signals.GameStarted:Fire()

		self:_startTimeLoop()

	end):catch(function(err)
		warn("StartGame Error:", err)
		self:EndGame(nil)
	end)
end

function GameService:_setupGameMode(players)
	local modes = GameModesFolder:GetChildren()
	local selectedScript = modes[math.random(1, #modes)]
	local modeModule = require(selectedScript)

	if modeModule.MinPlayers and #players < modeModule.MinPlayers then
		modeModule = require(GameModesFolder.Classic)
		selectedScript = GameModesFolder.Classic
	end

	self._activeModeModule = modeModule
	self.Gamemode(selectedScript.Name)

	local roles = modeModule:Start(self, players)
	self.RunningPlayers = roles 

	for player, role in pairs(roles) do
		if role == "Killer" then 
			PlayerService:ResetChance(player)
		else 
			PlayerService:AddChance(player, 1) 
		end
	end
end

function GameService:_setupPlayerMonitoring()
	for player, role in pairs(self.RunningPlayers) do

		local function monitorCharacter(character)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if not humanoid then return end

			local conn = humanoid.Died:Connect(function()
				if self.GameStatus() ~= "GameRunning" and self.GameStatus() ~= "Warmup" then return end

				if self._activeModeModule and self._activeModeModule.OnPlayerDied then
					self._activeModeModule:OnPlayerDied(self, player)
				end

				if role == "Survivor" then
					-- Survivor ölürse katile zaman ekle ve listeyi güncelle
					local newTime = self.TimeLeft() + 7
					self.TimeLeft(newTime)
					self.Network.StateUpdate:FireAllClients("TimeLeft", newTime)

					self.RunningPlayers[player] = nil
					self.SurvivorCount(self:_countSurvivors())

					task.delay(3, function()
						if player and player.Parent then player:LoadCharacter() end
					end)

					if self:_countSurvivors() <= 0 then
						self:EndGame("Killer")
					end

				elseif role == "Killer" then
					-- Killer ölürse direkt survivorlar kazanır
					self:EndGame("Survivors")
				end
			end)

			table.insert(self._connections, conn)
		end

		if player.Character then monitorCharacter(player.Character) end
		local conn = player.CharacterAdded:Connect(monitorCharacter)
		table.insert(self._connections, conn)
	end
end

function GameService:_startTimeLoop()
	if self._gameLoopTask then task.cancel(self._gameLoopTask) end

	local modeDuration = (self._activeModeModule and self._activeModeModule.Time) or CONFIG.GAME_TIME
	self.TimeLeft(modeDuration)

	self._gameLoopTask = task.spawn(function()
		while self.TimeLeft() > 0 do
			task.wait(1)
			self.TimeLeft(self.TimeLeft() - 1)

			if self._activeModeModule and self._activeModeModule.CheckWinCondition then
				local winner = self._activeModeModule:CheckWinCondition(self)
				if winner then 
					self:EndGame(winner) 
					return
				end
			end
		end

		-- Süre biterse Killer'ları öldür ve survivorları kazandır
		if self.TimeLeft() <= 0 then
			for player, role in pairs(self.RunningPlayers) do
				if role == "Killer" and player.Character then
					local hum = player.Character:FindFirstChild("Humanoid")
					if hum then hum.Health = 0 end
				end
			end

			task.wait(1) 
			if self.GameStatus() == "GameRunning" then
				self:EndGame("Survivors")
			end
		end
	end)
end

---

-- =============================================================================
--  END GAME LOGIC
-- =============================================================================

function GameService:EndGame(winningTeam, Executable)
	if self._gameLoopTask then 
		task.cancel(self._gameLoopTask) 
		self._gameLoopTask = nil 
	end

	for _, conn in ipairs(self._connections) do 
		conn:Disconnect() 
	end
	self._connections = {}

	self.TimeLeft(0)
	self.Network.StateUpdate:FireAllClients("TimeLeft", 0)

	if winningTeam == "Killer" then
		self.GameStatus("MurdererWin")
	elseif winningTeam == "Survivors" then
		self.GameStatus("SurvivorsWin")
	else
		self.GameStatus("Intermission")
	end

	self.Network.Results:FireAllClients(winningTeam)
	self.Network.GameEnded:FireAllClients()
	self.Signals.GameEnded:Fire()

	-- Reset States
	self.GameStatus("Intermission") 
	self.Gamemode("Waiting")
	self._activeModeModule = nil
	self.RunningPlayers = {} 
	self.Votes({})
	self.CurrentOptions({})
	self.NextMapOverride(nil)
	self.SurvivorCount(0)

	MapService:Cleanup()
	PlayerService:DespawnAll() 

	if Executable then 
		task.spawn(Executable) 
	end
end

---

-- =============================================================================
--  INITIALIZATION
-- =============================================================================

function GameService:OnStart()
	-- Sync Logic (Charm Effects)
	local function sync(name, atom)
		Charm.effect(function() 
			self.Network.StateUpdate:FireAllClients(name, atom()) 
		end)
	end

	sync("Gamemode", self.Gamemode)
	sync("GameStatus", self.GameStatus)
	sync("SurvivorCount", self.SurvivorCount)

	Charm.effect(function() 
		self.Network.VoteUpdate:FireAllClients(self:_calculateVoteCounts()) 
	end)

	-- Oyuncu Çıkış Kontrolü (Rage-quit handling)
	Players.PlayerRemoving:Connect(function(player)
		if self.RunningPlayers[player] then
			local role = self.RunningPlayers[player]
			self.RunningPlayers[player] = nil

			-- Oyun devam ediyorsa win condition kontrolü yap
			if self.GameStatus() == "GameRunning" or self.GameStatus() == "Warmup" then
				if role == "Survivor" then
					self.SurvivorCount(self:_countSurvivors())
					if self:_countSurvivors() <= 0 then
						self:EndGame("Killer")
					end
				elseif role == "Killer" then
					if self:_countKillers() <= 0 then
						self:EndGame("Survivors")
					end
				end
			end
		end
	end)

	self.Network.CastVote.OnServerEvent:Connect(function(p, id) 
		self:CastVote(p, id) 
	end)

	-- Yeni giren oyuncuya güncel durumu bildir
	Players.PlayerAdded:Connect(function(player)
		self.Network.StateUpdate:FireClient(player, "Gamemode", self.Gamemode())
		self.Network.StateUpdate:FireClient(player, "GameStatus", self.GameStatus())
		self.Network.StateUpdate:FireClient(player, "SurvivorCount", self.SurvivorCount())
		self.Network.StateUpdate:FireClient(player, "TimeLeft", self.TimeLeft())

		if self.GameStatus() == "OnVoting" and #self.CurrentOptions() > 0 then
			self.Network.VoteOptions:FireClient(player, self.CurrentOptions(), self.TimeLeft())
			task.defer(function() 
				if player.Parent then 
					self.Network.VoteUpdate:FireClient(player, self:_calculateVoteCounts()) 
				end 
			end)
		end
	end)

	-- Main Game Loop Task
	task.spawn(function()
		while true do
			while #Players:GetPlayers() < CONFIG.MIN_PLAYERS do 
				if self.GameStatus() ~= "Intermission" then
					self.GameStatus("Intermission")
				end
				task.wait(5) 
			end

			task.wait(CONFIG.INTERMISSION)

			local promise = self:StartGame()
			if promise and promise:getStatus() ~= Promise.Status.Rejected then
				-- Oyunun bitmesini bekle
				self.Signals.GameEnded:Wait()
			end

			task.wait(3)
		end
	end)
end

return GameService