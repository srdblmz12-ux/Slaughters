-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local GameController = {
	Name = script.Name,
	_lastStateChange = 0,
	_isParticipating = false, -- Oyuncunun o anki turda oynayıp oynamadığını takip eder
	_currentStatus = "Intermission" -- Oyunun o anki durumu
}

local GameStateName = {
	["Intermission"] = "Waiting for players...",
	["OnVoting"] = "Voting for map...",
	["Loading"] = "Loading map...",
	["Warmup"] = "Selecting skills...",
	["GameRunning"] = "Killer spawned, run!",
	["MurdererWin"] = "No survivor is left...",
	["SurvivorsWin"] = "Survivors won!"
}

-- HUD Görünürlüğünü Kontrol Eden Fonksiyon
function GameController:UpdateInterfaceVisibility()
	local LevelHUD = PlayerGui:FindFirstChild("LevelHUD")
	local IngameHUD = PlayerGui:FindFirstChild("IngameHUD")

	-- Kural 1: Oyun aktif bir evredeyse (Warmup veya GameRunning) VE oyuncu katılımcıysa (ölmediyse) gizle.
	local isGameActive = (self._currentStatus == "Warmup" or self._currentStatus == "GameRunning")
	local isActiveParticipant = (isGameActive and self._isParticipating)

	-- Kural 2: [YENİ] Oylama (OnVoting) aşamasındaysa da gizle (böylece oylama ekranı net görünür).
	local isVoting = (self._currentStatus == "OnVoting")

	-- Oylama sırasındaysa VEYA (Aktif oyunda ve katılımcıysa) -> Gizle
	local shouldHide = isVoting or isActiveParticipant

	if LevelHUD then 
		LevelHUD.Enabled = not shouldHide 
	end

	if IngameHUD then 
		IngameHUD.Enabled = not shouldHide 
	end
end

function GameController:OnStart()
	-- print("[GameController] Başlatıldı (OnStart)") -- [KAPATILDI]

	local GameStatusHUD = PlayerGui:WaitForChild("GameStatusHUD")
	local StatusContainer = GameStatusHUD:WaitForChild("StatusContainer")

	local Timer = TimerKit.NewTimer(1)
	Timer.OnTick:Connect(function(_, Remaining : number)
		local displayTime = math.max(0, Remaining)
		StatusContainer.Timer.Text = FormatKit.FormatTime(displayTime, "m:ss")
	end)

	-- Karakter öldüğünde arayüzü geri getirmek için dinleyici
	local function MonitorCharacter(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				-- Oyuncu ölürse, oyun devam etse bile katılımcı olmaktan çıkar
				self._isParticipating = false
				self:UpdateInterfaceVisibility()
			end)
		end
	end

	if LocalPlayer.Character then MonitorCharacter(LocalPlayer.Character) end
	LocalPlayer.CharacterAdded:Connect(MonitorCharacter)

	Net:Connect("StateUpdate", function(State : string, Data)
		if (State == "GameStatus") then
			self._currentStatus = Data -- Durumu kaydet
			self:UpdateInterfaceVisibility() -- Arayüzü güncelle

			local OldText = StatusContainer.GameState.Text
			local NewText = GameStateName[Data] or Data

			StatusContainer.GameState.Text = NewText

			if (NewText ~= OldText) then
				self._lastStateChange = tick()
				local currentChange = self._lastStateChange

				StatusContainer.GameState.Visible = true

				task.delay(10, function()
					if (self._lastStateChange == currentChange) then
						StatusContainer.GameState.Visible = false
					end
				end)
			end

			StatusContainer.Visible = (Data ~= "OnVoting")

		elseif (State == "TimeLeft") then
			Timer:Stop()
			if (Data and Data > 0) then
				Timer:AdjustDuration(Data)
				Timer:Start()
			else
				StatusContainer.Timer.Text = "0:00"
			end

		elseif (State == "SurvivorCount") then
			StatusContainer.Remaining.Text = `{Data} Survivor Left`
		end
	end)

	-- Isınma başladığında rol kontrolü yap
	Net:Connect("WarmupStarted", function(Mode, Roles, Time)
		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()

		-- ARTIK KONTROL UserId İLE YAPILIYOR
		local myUserId = tostring(LocalPlayer.UserId)

		if Roles[myUserId] then
			self._isParticipating = true
		else
			self._isParticipating = false
		end
		self:UpdateInterfaceVisibility()
	end)

	Net:Connect("GameStarted", function(Time)
		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()

		-- Oyun başladığında arayüzü tekrar kontrol et
		self:UpdateInterfaceVisibility()
	end)

	Net:Connect("VoteOptions", function(_, Time)
		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()
	end)

	Net:Connect("MapLoaded", function(MapName : string)
		StatusContainer.MapName.Text = MapName
	end)

	Net:Connect("MapUnloaded", function()
		StatusContainer.MapName.Text = ""
	end)

	-- Oyun bittiğinde herkesi tekrar "katılımcı değil" yap ve arayüzü aç
	Net:Connect("GameEnded", function()
		self._isParticipating = false
		self._currentStatus = "Intermission"
		self:UpdateInterfaceVisibility()
	end)
end

return GameController