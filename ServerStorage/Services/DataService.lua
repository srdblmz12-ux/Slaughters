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
local Net = require(Packages:WaitForChild("Net"))

-- Profile Template
local PROFILE_TEMPLATE = {
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
}

local Store = ProfileStore.New(RunService:IsStudio() and "Test" or "Live0", PROFILE_TEMPLATE)

-- Service Definition
local DataService = {
	Name = "DataService",
	Client = {}, -- Framework buradaki fonksiyonları RemoteFunction'a çevirecek
	LoadedProfiles = {},
	Signals = {
		ProfileLoaded = Signal.new(),
		ProfileReleased = Signal.new()
	},
	Network = {
		-- İsimle erişebilmek için Key ataması yaptım
		DataUpdate = Net:RemoteEvent("DataUpdate") 
	}
}

--// Helper Functions (Local)

-- "CurrencyData.Value" gibi string yollarını tablo referansına çevirir
local function GetTablePath(root, path)
	local parts = string.split(path, ".")
	local current = root

	for i = 1, #parts - 1 do
		current = current[parts[i]]
		if not current then return nil, nil end
	end

	return current, parts[#parts]
end

--// Client Functions

function DataService.Client:GetData(player)
	return DataService:GetData(player)
end

--// Server Functions

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

--[[
	Yeni Eklenen Fonksiyon: SetValue
	Belirli bir path'teki veriyi direkt değiştirir.
	Örnek: DataService:SetValue(player, "CurrencyData.Value", 100)
]]
function DataService:SetValue(player, path, value)
	local profile = self.LoadedProfiles[player]
	if not profile then return end

	local dataTable, key = GetTablePath(profile.Data, path)

	if dataTable and key then
		dataTable[key] = value
		-- Client'a güncelleme bilgisini gönder
		self.Network.DataUpdate:FireClient(player, path, value)
	else
		warn("[DataService] SetValue için geçersiz yol: " .. tostring(path))
	end
end

--[[
	Yeni Eklenen Fonksiyon: UpdateValue
	Mevcut değerin üzerine işlem yapar. Sayı veya Fonksiyon alabilir.
	Örnek: DataService:UpdateValue(player, "CurrencyData.Value", 50) -- 50 ekler
]]
function DataService:UpdateValue(player, path, callbackOrAmount)
	local profile = self.LoadedProfiles[player]
	if not profile then return end

	local dataTable, key = GetTablePath(profile.Data, path)

	if dataTable and key then
		local oldValue = dataTable[key]
		local newValue

		if type(callbackOrAmount) == "number" and type(oldValue) == "number" then
			newValue = oldValue + callbackOrAmount
		elseif type(callbackOrAmount) == "function" then
			newValue = callbackOrAmount(oldValue)
		else
			newValue = callbackOrAmount
		end

		dataTable[key] = newValue
		-- Client'a güncelleme bilgisini gönder
		self.Network.DataUpdate:FireClient(player, path, newValue)

		return newValue
	else
		warn("[DataService] UpdateValue için geçersiz yol: " .. tostring(path))
	end
end

function DataService:GetData(player)
	-- 1. Durum: Profil zaten yüklü
	local profile = self.LoadedProfiles[player]
	if profile then
		return profile.Data
	end

	-- 2. Durum: Profil yükleniyor (Race Condition Çözümü)
	local maxRetries = 100 -- 10 saniye bekleme
	local attempts = 0

	while player:IsDescendantOf(Players) and attempts < maxRetries do
		attempts += 1
		profile = self.LoadedProfiles[player]
		if profile then
			return profile.Data
		end
		task.wait(0.1)
	end

	warn("[DataService] Data timeout or player left: " .. player.Name)
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
	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile ~= nil then
		if player:IsDescendantOf(Players) then
			profile:AddUserId(player.UserId)
			profile:Reconcile() -- Eksik verileri template'ten tamamlar

			profile.OnSessionEnd:Connect(function()
				self.LoadedProfiles[player] = nil
				player:Kick("Your profile session has ended. Please rejoin.") 
			end)

			self.LoadedProfiles[player] = profile

			self.Signals.ProfileLoaded:Fire(player, profile)
			print("[DataService] Profile loaded: " .. player.Name)
		else
			profile:EndSession()
		end
	else
		player:Kick("Profile data could not be loaded. Please rejoin.")
	end
end

function DataService:ReleaseProfile(player)
	local profile = self.LoadedProfiles[player]
	if profile then
		profile:EndSession()
		self.LoadedProfiles[player] = nil
		self.Signals.ProfileReleased:Fire(player)
		print("[DataService] Profile released: " .. player.Name)
	end
end

return DataService