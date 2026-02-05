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
local Charm = require(Packages:WaitForChild("Charm"))
local Net = require(Packages:WaitForChild("Net")) -- [EKLENDİ]

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
	},

	-- [EKLENDİ] Veri güncelleme kanalı
	Network = {
		DataUpdate = Net:RemoteEvent("DataUpdate")
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

-- [YENİ] Para Ekleme Fonksiyonu
function DataService:AddCurrency(player, amount)
	local profile = self.LoadedProfiles[player]
	if profile then
		local currency = profile.Data.CurrencyData
		if currency then
			currency.Value = currency.Value + amount
			currency.Total = currency.Total + amount

			-- [EKLENDİ] Client'a haber ver
			self.Network.DataUpdate:FireClient(player, "Currency", currency.Value)

			print("[DataService] " .. player.Name .. " +" .. amount .. " Token kazandı! (Toplam: " .. currency.Value .. ")")
		end
	end
end

-- [YENİ] XP Ekleme ve Level Atlama Fonksiyonu
function DataService:AddXP(player, amount)
	local profile = self.LoadedProfiles[player]
	if profile then
		local levelData = profile.Data.LevelData
		if levelData then
			levelData.ValueXP = levelData.ValueXP + amount

			-- Level Atlaması (Döngü ile birden fazla level atlayabilir)
			while levelData.ValueXP >= levelData.TargetXP do
				levelData.ValueXP = levelData.ValueXP - levelData.TargetXP
				levelData.Level = levelData.Level + 1
				-- Her seviyede gereken XP'yi %20 artırıyoruz
				levelData.TargetXP = math.floor(levelData.TargetXP * 1.2)
				print("[DataService] " .. player.Name .. " Level Atladı! Yeni Level: " .. levelData.Level)
			end

			-- [EKLENDİ] Client'a haber ver (Level ve XP verisi)
			self.Network.DataUpdate:FireClient(player, "Level", levelData)
		end
	end
end

function DataService:LoadProfile(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId) 
		profile:Reconcile()

		if player:IsDescendantOf(Players) then
			self.LoadedProfiles[player] = profile

			profile.OnSessionEnd:Connect(function()
				self.LoadedProfiles[player] = nil
				player:Kick("Profile released (Session loaded elsewhere).")
			end)

			self.Signals.ProfileLoaded:Fire(player, profile)
			print("[DataService] Profil yüklendi: " .. player.Name)

			-- [EKLENDİ] İlk girişte verileri gönder ki arayüz dolsun
			task.delay(1, function()
				if player.Parent then
					self.Network.DataUpdate:FireClient(player, "Currency", profile.Data.CurrencyData.Value)
					self.Network.DataUpdate:FireClient(player, "Level", profile.Data.LevelData)
				end
			end)

		else
			profile:Release()
		end
	else
		player:Kick("Profile load failed. Please rejoin.")
	end
end

function DataService:ReleaseProfile(player)
	local profile = self.LoadedProfiles[player]
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