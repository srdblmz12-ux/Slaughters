local Infection = {}

Infection.Name = "Infection"
Infection.MinPlayers = 3 
Infection.Time = 130 -- Enfeksiyon biraz daha uzun sürebilir
Infection.Description = "Ölenler enfekte olur ve Katil tarafına geçer!"

function Infection:Start(gameService, players)
	local roles = {}
	local remainingPlayers = {unpack(players)}

	-- İlk enfekte kişiyi (Başlangıç Katili) seç
	local firstInfected = gameService:SelectWeightedKiller(remainingPlayers)

	for _, player in ipairs(players) do
		if player == firstInfected then
			roles[player] = "Killer" -- İlk Zombi
		else
			roles[player] = "Survivor"
		end
	end

	return roles
end

function Infection:OnPlayerDied(gameService, player)
	local currentRole = gameService.RunningPlayers[player]

	-- Infection Kuralı: Survivor ölürse Killer (Zombi) olur!
	if currentRole == "Survivor" then
		print(player.Name .. " enfekte oldu! Artık bir Katil.")

		-- [ÖNEMLİ] Rolü string olarak değiştiriyoruz
		gameService.RunningPlayers[player] = "Killer"

		-- Enfeksiyon yayılınca süre biraz uzasın
		local currentTime = gameService.TimeLeft()
		gameService.TimeLeft(currentTime + 10) 

		-- Not: Oyuncu respawn olduğunda GameService onun yeni rolüne göre (Killer) spawn edecektir.
	end
end

function Infection:CheckWinCondition(gameService)
	local survivorCount = 0
	local killerCount = 0

	for _, role in pairs(gameService.RunningPlayers) do
		if role == "Survivor" then
			survivorCount = survivorCount + 1
		elseif role == "Killer" then
			killerCount = killerCount + 1
		end
	end

	-- Herkes enfekte olduysa Katiller (Zombiler) kazanır
	if survivorCount == 0 then
		self:EndRound(gameService, "Infected", "Enfeksiyon tüm sunucuyu ele geçirdi!")
		return true
	end

	-- Tüm enfekteler bir şekilde oyundan çıktıysa
	if killerCount == 0 then
		self:EndRound(gameService, "Survivors", "Enfeksiyon durduruldu.")
		return true
	end

	return false
end

function Infection:EndRound(gameService, winnerRole, message)
	print("Infection Bitti! Kazanan:", winnerRole)
end

return Infection