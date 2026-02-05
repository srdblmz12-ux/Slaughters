-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Services = ServerStorage:WaitForChild("Services")
local DataService = require(Services:WaitForChild("DataService")) -- Dataya erişmek için gerekli

local RewardService = {
	Name = script.Name,
	Client = {}
}

--// ÖDÜL SİSTEMİ

-- Para (Token) Ekleme
function RewardService:AddCurrency(player, amount)
	-- DataService'den profili çekiyoruz
	local profile = DataService.LoadedProfiles[player]
	if profile then
		local currency = profile.Data.CurrencyData
		if currency then
			currency.Value = currency.Value + amount
			currency.Total = currency.Total + amount

			-- Client'ı güncellemek için DataService'in ağını kullanıyoruz
			DataService.Network.DataUpdate:FireClient(player, "Currency", currency.Value)

			print("[RewardService] " .. player.Name .. " +" .. amount .. " Token kazandı! (Toplam: " .. currency.Value .. ")")
		end
	end
end

-- XP Ekleme ve Level Atlama
function RewardService:AddXP(player, amount)
	local profile = DataService.LoadedProfiles[player]
	if profile then
		local levelData = profile.Data.LevelData
		if levelData then
			levelData.ValueXP = levelData.ValueXP + amount

			-- Level Atlaması (Döngü ile birden fazla level atlayabilir)
			local leveledUp = false
			while levelData.ValueXP >= levelData.TargetXP do
				levelData.ValueXP = levelData.ValueXP - levelData.TargetXP
				levelData.Level = levelData.Level + 1
				-- Her seviyede gereken XP'yi %20 artırıyoruz
				levelData.TargetXP = math.floor(levelData.TargetXP * 1.2)
				leveledUp = true
				print("[RewardService] " .. player.Name .. " Level Atladı! Yeni Level: " .. levelData.Level)
			end

			-- Client'ı güncelle
			DataService.Network.DataUpdate:FireClient(player, "Level", levelData)

			-- Eğer level atladıysa burada ekstra ödül veya efekt tetikleyebilirsin
			if leveledUp then
				-- Örnek: Level atlayınca 50 Token ver
				-- self:AddCurrency(player, 50) 
			end
		end
	end
end

function RewardService:OnStart()
	print("[RewardService] Başlatıldı.")
end

return RewardService