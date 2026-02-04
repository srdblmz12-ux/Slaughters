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
	_lastStateChange = 0, -- Delay çakışmasını önlemek için
}

-- Tüm stateleri buraya ekledik ki ekranda düzgün gözüksün
local GameStateName = {
	["Intermission"] = "Waiting for players...",
	["OnVoting"] = "Voting for map...",
	["Loading"] = "Loading map...",
	["Warmup"] = "Selecting skills...",
	["GameRunning"] = "Killer spawned, run!",
	["MurdererWin"] = "No survivor is left...",
	["SurvivorsWin"] = "Survivors won!"
}

function GameController:OnStart()
	local GameStatusHUD = PlayerGui:WaitForChild("GameStatusHUD")
	local StatusContainer = GameStatusHUD:WaitForChild("StatusContainer")

	-- Timer kurulumu
	local Timer = TimerKit.NewTimer(1)
	Timer.OnTick:Connect(function(_, Remaining : number)
		-- Kalan saniye 0'dan küçükse 0 yazdır
		local displayTime = math.max(0, Remaining)
		StatusContainer.Timer.Text = FormatKit.FormatTime(displayTime, "m:ss")
	end)

	-- Merkezi State Takibi
	Net:Connect("StateUpdate", function(State : string, Data)
		if (State == "GameStatus") then
			local OldText = StatusContainer.GameState.Text
			local NewText = GameStateName[Data] or Data

			StatusContainer.GameState.Text = NewText

			-- Eğer yazı değiştiyse 10 saniye göster sonra gizle
			if (NewText ~= OldText) then
				self._lastStateChange = tick()
				local currentChange = self._lastStateChange

				StatusContainer.GameState.Visible = true

				task.delay(10, function()
					-- Eğer aradan geçen 10 saniyede yeni bir state gelmemişse gizle
					if (self._lastStateChange == currentChange) then
						StatusContainer.GameState.Visible = false
					end
				end)
			end

			-- Oylama sırasında ana HUD'ı gizle (Oylama HUD'ı açılacağı için)
			StatusContainer.Visible = (Data ~= "OnVoting")

		elseif (State == "TimeLeft") then
			-- Sunucudan yeni süre geldiğinde yerel sayacı güncelle
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

	-- Faz geçişlerini direkt dinleyerek süreyi garantiye alalım
	Net:Connect("WarmupStarted", function(_, _, Time)
		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()
	end)

	Net:Connect("GameStarted", function(Time)
		Timer:Stop()
		Timer:AdjustDuration(Time)
		Timer:Start()
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
end

return GameController