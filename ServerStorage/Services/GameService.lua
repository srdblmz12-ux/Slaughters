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
local RewardService = require(Services:WaitForChild("RewardService"))

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
	RoundStartSnapshots = {},
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

	-- [GÜNCELLEME BURADA] UserId string'e çevrilip bakılıyor
	local targetId = tostring(target.UserId)

	-- self.Server.RunningPlayers[targetId] ile doğru veriye ulaşıyoruz
	local role = self.Server.RunningPlayers[targetId] or "Lobby"

	return {
		PlayerName = target.Name,
		Role = role,
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
		
		-- [YENİ EKLENEN KISIM] Tur Başı Snapshot Al (Token ve XP kaydet)
		self.RoundStartSnapshots = {}
		for _, player in ipairs(activePlayers) do
			self.RoundStartSnapshots[player] = self:_getPlayerDataSnapshot(player)
		end
		-- [EKLEME BİTTİ]

		local mapData = MapService:LoadMap(mapModule)
		if not mapData then error("Harita Yüklenemedi") end

		if mapData.Lighting then 
			self.Network.LoadLighting:FireAllClients(mapData.Lighting) 
		end

		-- [AŞAMA 4] OYUN MODU & ROLLER
		self:_setupGameMode(activePlayers)

		local sCount = 0
		for _, r in pairs(self.RunningPlayers) do 
			if r == "Survivor" then sCount += 1 end 
		end
		self.SurvivorCount(sCount)

		self.GameStatus("Warmup")
		self.TimeLeft(CONFIG.WARMUP_TIME)

		self.Network.WarmupStarted:FireAllClients(self.Gamemode(), self.RunningPlayers, CONFIG.WARMUP_TIME)
		self.Signals.WarmupStarted:Fire()

		-- [SPAWN HAZIRLIĞI] UserId -> Player Instance Dönüşümü
		local activeInstancesRoles = {}
		for uid, role in pairs(self.RunningPlayers) do
			local p = Players:GetPlayerByUserId(tonumber(uid))
			if p then activeInstancesRoles[p] = role end
		end

		PlayerService:SpawnSurvivors(activeInstancesRoles, mapData.Spawns)
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

		-- Warmup sırasında çıkan oyuncular olabilir, listeyi tazeliyoruz
		local currentPlayersForSpawn = {}
		for uid, role in pairs(self.RunningPlayers) do
			local p = Players:GetPlayerByUserId(tonumber(uid))
			-- Sadece oyunda olanları (Parent'i olanları) listeye al
			if p and p.Parent then 
				currentPlayersForSpawn[p] = role 
			end
		end

		-- Artık self.RunningPlayers değil, Instance içeren taze listeyi yolluyoruz
		PlayerService:SpawnKillers(currentPlayersForSpawn, mapData.Spawns)

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

	-- Modülden gelen ham roller (Hala [Player Instance] = "Rol" formatında gelir)
	local rawRoles = modeModule:Start(self, players)
	self.RunningPlayers = {} -- Tabloyu sıfırla

	-- [GÜNCELLEME] Player Instance'larını UserId String'e çevirerek ana tabloya kaydet
	for playerInstance, roleName in pairs(rawRoles) do
		if playerInstance and playerInstance:IsA("Player") then
			-- ANAHTAR NOKTA BURASI: Player objesini değil, ID'sini string olarak kullanıyoruz.
			local userIdStr = tostring(playerInstance.UserId)
			self.RunningPlayers[userIdStr] = roleName

			if roleName == "Killer" then 
				PlayerService:ResetChance(playerInstance)
			else 
				PlayerService:AddChance(playerInstance, 1) 
			end
		end
	end
end

function GameService:_setupPlayerMonitoring()
	-- RunningPlayers artık UserId (String) -> Role yapısında
	for userIdStr, role in pairs(self.RunningPlayers) do
		local userId = tonumber(userIdStr)
		local player = Players:GetPlayerByUserId(userId)

		if player then
			local function monitorCharacter(character)
				local humanoid = character:WaitForChild("Humanoid", 10)
				if not humanoid then return end

				local conn = humanoid.Died:Connect(function()
					if self.GameStatus() ~= "GameRunning" and self.GameStatus() ~= "Warmup" then return end

					if self._activeModeModule and self._activeModeModule.OnPlayerDied then
						self._activeModeModule:OnPlayerDied(self, player)
					end

					if role == "Survivor" then
						local newTime = self.TimeLeft() + 7
						self.TimeLeft(newTime)
						self.Network.StateUpdate:FireAllClients("TimeLeft", newTime)

						self.RunningPlayers[userIdStr] = nil -- Listeden sil (String key kullanıyoruz)
						self.SurvivorCount(self:_countSurvivors())

						task.delay(3, function()
							if player and player.Parent then player:LoadCharacter() end
						end)

						if self:_countSurvivors() <= 0 then
							self:EndGame("Killer")
						end

					elseif role == "Killer" then
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

		-- [DÜZELTME BURADA] Süre biterse Killer'ları öldür
		if self.TimeLeft() <= 0 then
			for userIdStr, role in pairs(self.RunningPlayers) do
				if role == "Killer" then
					local player = Players:GetPlayerByUserId(tonumber(userIdStr))
					if player and player.Character then
						local hum = player.Character:FindFirstChild("Humanoid")
						if hum then hum.Health = 0 end
					end
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
function GameService:_getPlayerDataSnapshot(player)
	local data = DataService:GetData(player)
	if data then
		return {
			Token = data.CurrencyData.Value,
			XP = data.LevelData.ValueXP,
			Level = data.LevelData.Level,
			TargetXP = data.LevelData.TargetXP
		}
	end
	return {Token = 0, XP = 0, Level = 1, TargetXP = 100}
end

-- // YARDIMCI: İki snapshot arasındaki kazancı hesapla
function GameService:_calculateEarnings(startData, endData)
	if not startData or not endData then return {Token = 0, XP = 0} end

	local earnedToken = math.max(0, endData.Token - startData.Token)

	local earnedXP = 0
	if endData.Level == startData.Level then
		earnedXP = math.max(0, endData.XP - startData.XP)
	else
		-- Level atladıysa basit bir hesaplama (Level farkı * HedefXP + Kalan XP)
		local levelDiff = endData.Level - startData.Level
		earnedXP = (levelDiff * startData.TargetXP) + (endData.XP - startData.XP) 
	end

	return {
		Token = earnedToken,
		XP = math.max(0, earnedXP)
	}
end

-- =============================================================================
--  END GAME LOGIC
-- =============================================================================

function GameService:EndGame(winningTeam, Executable)
	if self._gameLoopTask then task.cancel(self._gameLoopTask) self._gameLoopTask = nil end
	for _, conn in ipairs(self._connections) do conn:Disconnect() end
	self._connections = {}
	
	-- 1. Kazananları Belirle ve Bonusları Dağıt (Veritabanına işle)
	for userIdStr, role in pairs(self.RunningPlayers) do
		local player = Players:GetPlayerByUserId(tonumber(userIdStr))
		if player then
			if winningTeam == "Killer" and role == "Killer" then
				RewardService:AddXP(player, 100)
				RewardService:AddCurrency(player, 50)
			elseif winningTeam == "Survivors" and role == "Survivor" then
				RewardService:AddXP(player, 25)
				RewardService:AddCurrency(player, 25)
			else
				-- Kaybedenlere teselli
				RewardService:AddXP(player, 10)
				RewardService:AddCurrency(player, 5)
			end
		end
	end

	-- 2. Sonuç Paketini Hazırla (GENEL VERİ)
	local resultsPayload = {
		Winner = winningTeam,
		KillerName = "None",
		KillerId = 0,
		KillerSkin = "Wendigo", -- [YENİ] Varsayılan kostüm
		Survivors = {}, 
	}

	-- Katil Bilgisi ve Kostümü
	for userIdStr, role in pairs(self.RunningPlayers) do
		if role == "Killer" then
			local killerPlayer = Players:GetPlayerByUserId(tonumber(userIdStr))
			if killerPlayer then
				resultsPayload.KillerName = killerPlayer.Name
				resultsPayload.KillerId = killerPlayer.UserId

				-- [YENİ] Katilin profiline bakıp kostümünü alıyoruz
				local profile = DataService.LoadedProfiles[killerPlayer]
				if profile and profile.Data.Equippeds.KillerSkin then
					resultsPayload.KillerSkin = profile.Data.Equippeds.KillerSkin
				end
			else
				resultsPayload.KillerName = "Disconnected"
			end
			break 
		end
	end

	-- [DÜZELTME] DÖNGÜ A: Önce Survivor Listesini TAMAMEN Doldur
	-- Bu döngü sadece listeyi hazırlar, kimseye bir şey göndermez.
	for _, player in ipairs(Players:GetPlayers()) do
		local uid = tostring(player.UserId)
		local role = self.RunningPlayers[uid]
		local isDead = (role == nil) -- Listede yoksa ölmüştür

		-- Eğer katil değilse listeye ekle
		if uid ~= tostring(resultsPayload.KillerId) then
			table.insert(resultsPayload.Survivors, {
				Name = player.Name,
				UserId = player.UserId,
				IsDead = isDead
			})
		end
	end

	-- [DÜZELTME] DÖNGÜ B: Herkesin Kazancını Hesapla ve Gönder
	-- Artık 'resultsPayload.Survivors' tamamen dolu olduğu için herkes tam listeyi alacak.
	for _, player in ipairs(Players:GetPlayers()) do
		-- Snapshot Hesaplaması
		local startData = self.RoundStartSnapshots[player]
		local endData = self:_getPlayerDataSnapshot(player)
		local earned = self:_calculateEarnings(startData, endData)

		-- Paketi Kopyala ve Kişisel Ödülü Ekle
		local personalizedData = table.clone(resultsPayload)
		personalizedData.MyRewards = earned
		
		self.Network.Results:FireClient(player, personalizedData)
	end

	-- Durum Güncellemeleri
	self.TimeLeft(0)
	self.Network.StateUpdate:FireAllClients("TimeLeft", 0)

	if winningTeam == "Killer" then self.GameStatus("MurdererWin")
	elseif winningTeam == "Survivors" then self.GameStatus("SurvivorsWin")
	else self.GameStatus("Intermission") end

	self.Network.GameEnded:FireAllClients()
	self.Signals.GameEnded:Fire()

	-- Reset
	task.delay(10, function()
		self.GameStatus("Intermission") 
		self.Gamemode("Waiting")
		self._activeModeModule = nil
		self.RunningPlayers = {} 
		self.RoundStartSnapshots = {}
		self.Votes({})
		self.CurrentOptions({})
		self.NextMapOverride(nil)
		self.SurvivorCount(0)

		MapService:Cleanup()
		PlayerService:DespawnAll() 

		if Executable then task.spawn(Executable) end
	end)
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
		local userIdStr = tostring(player.UserId) -- Anahtarı oluştur

		if self.RunningPlayers[userIdStr] then -- Anahtar ile kontrol et
			local role = self.RunningPlayers[userIdStr]
			self.RunningPlayers[userIdStr] = nil -- Listeden sil

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
			
			task.wait(5)
			MapService:Cleanup()
			task.wait(5)
		end
	end)
end

return GameService