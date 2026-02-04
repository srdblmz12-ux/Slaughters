local Classic = {}

Classic.Name = "Classic"
Classic.MinPlayers = 2
Classic.Time = 180 -- 3 Dakika
Classic.Description = "Katil herkesi avlamadan hayatta kal!"

-- Oyun başladığında rolleri belirler
function Classic:Start(gameService, players)
	local roles = {}
	local remainingPlayers = {unpack(players)}

	-- Katili gameService'in helper fonksiyonuyla seçiyoruz
	local killer = gameService:SelectWeightedKiller(remainingPlayers)
	roles[killer] = "Killer"

	-- Geri kalan herkes Survivor
	for _, player in ipairs(remainingPlayers) do
		if player ~= killer then
			roles[player] = "Survivor"
		end
	end

	return roles
end

-- Bir oyuncu öldüğünde ne olacak?
function Classic:OnPlayerDied(gameService, player)
	-- Classic modunda biri ölünce sadece süre eklenir (GameService zaten 7sn ekliyor)
	-- Buraya ekstra mod spesifik logic eklenebilir.
	print(player.Name .. " öldü. (Classic Modu)")
end

-- Her saniye çalışır, oyunun bitip bitmediğini kontrol eder
function Classic:CheckWinCondition(gameService)
	local survivorCount = 0
	local killerCount = 0

	-- [DÜZELTİLDİ] roleAtom() yok, direkt role string
	for _, role in pairs(gameService.RunningPlayers) do
		if role == "Survivor" then
			survivorCount = survivorCount + 1
		elseif role == "Killer" then
			killerCount = killerCount + 1
		end
	end

	-- Eğer survivor kalmadıysa Katil kazanır
	if survivorCount == 0 then
		self:EndRound(gameService, "Killer", "Kimse sağ kalamadı.")
		return true
	end

	-- Katil oyundan çıktıysa Survivor kazanır
	if killerCount == 0 then
		self:EndRound(gameService, "Survivors", "Katil ortadan kayboldu.")
		return true
	end

	return false
end

function Classic:EndRound(gameService, winnerRole, message)
	print("Oyun Bitti! Kazanan:", winnerRole)
	-- RewardService entegrasyonu buraya yapılabilir
end

return Classic