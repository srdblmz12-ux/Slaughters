-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ServerStorage:WaitForChild("Modules")

local ProfileStore = require(Modules:WaitForChild("ProfileStore"))
local Promise = require(Packages:WaitForChild("Promise"))
local Signal = require(Packages:WaitForChild("Signal"))

-- Profile Template
local Store = ProfileStore.New(RunService:IsStudio() and "Test" or "Live0", {
	CurrencyData = {
		Spent = 0,
		Total = 0,
		Value = 0,
		Name = "Token"
	},
	LevelData = {
		TargetXP = 100,
		ValueXP = 0,
		Level = 1,
		Name = "Level"
	},
	KillerSkins = {
		["Wendigo"] = true
	},
	KillerSkills = {},
	Equippeds = {
		KillerSkin = "Wendigo",
		KillerSkill = "",
	},
	
	MurdererSkill = "Default"
})

local DataService = {
	Name = script.Name,
	Client = {},

	LoadedProfiles = {}, -- { [Player] = Profile }

	Signals = {
		ProfileLoaded = Signal.new(), -- (player, profile)
		ProfileReleased = Signal.new() -- (player)
	}
}

--// Client Functions
function DataService.Client:GetData(player)
	return DataService:GetData(player)
end

--// Server Functions

function DataService:GetData(player)
	local profile = self.LoadedProfiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

function DataService:GetProfile(player)
	return Promise.new(function(resolve, reject)
		local profile = self.LoadedProfiles[player]
		if profile then
			resolve(profile)
		else
			reject("Profile not loaded for: " .. player.Name)
		end
	end)
end

function DataService:LoadProfile(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId) 
		profile:Reconcile()

		if player:IsDescendantOf(Players) then
			self.LoadedProfiles[player] = profile

			-- [DÜZELTME BURADA YAPILDI]
			-- Eski: profile:ListenToRelease(...) -> Bu fonksiyon yok.
			-- Yeni: profile.OnSessionEnd:Connect(...) -> Doğrusu bu.
			profile.OnSessionEnd:Connect(function()
				self.LoadedProfiles[player] = nil
				player:Kick("Profile released (Session loaded elsewhere).")
			end)

			self.Signals.ProfileLoaded:Fire(player, profile)
			print("[DataService] Profil yüklendi: " .. player.Name)
		else
			profile:Release()
		end
	else
		player:Kick("Profile load failed. Please rejoin.")
	end
end

function DataService:ReleaseProfile(player)
	local profile = self.LoadedProfiles[player] :: ProfileStore.Profile<any>
	if profile then
		profile:EndSession()
		self.LoadedProfiles[player] = nil
		self.Signals.ProfileReleased:Fire(player)
		print("[DataService] Profil ayrıldı: " .. player.Name)
	end
end

function DataService:OnStart()
	Players.PlayerAdded:Connect(function(player)
		self:LoadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:ReleaseProfile(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:LoadProfile(player)
		end)
	end
end

return DataService