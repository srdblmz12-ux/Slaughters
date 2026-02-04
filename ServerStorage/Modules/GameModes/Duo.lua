local Duo = {}

Duo.Name = "Duo"
Duo.MinPlayers = 4 -- 2 Katil olması için en az 4 kişi lazım
Duo.Time = 180
Duo.Description = "İki katil var! Dikkatli ol."

function Duo:Start(gameService, players)
	local roles = {}
	local availablePlayers = {unpack(players)}

	-- 1. Katili seç
	local killer1 = gameService:SelectWeightedKiller(availablePlayers)
	roles[killer1] = "Killer"

	-- Seçilen katili listeden çıkar (Aynı kişi tekrar seçilmesin)
	for i, p in ipairs(availablePlayers) do
		if p == killer1 then
			table.remove(availablePlayers, i)
			break
		end
	end

	-- 2. Katili seç
	if #availablePlayers > 0 then
		local killer2 = gameService:SelectWeightedKiller(availablePlayers)
		roles[killer2] = "Killer"
	end

	-- Geriye kalan herkes Survivor
	for _, player in ipairs(players) do
		if not roles[player] then
			roles[player] = "Survivor"
		end
	end

	return roles
end

function Duo:OnPlayerDied(gameService, player)
	-- GameService standart işlemleri yapar
end

function Duo:CheckWinCondition(gameService)
	local survivorCount = 0
	local killerCount = 0

	for _, role in pairs(gameService.RunningPlayers) do
		if role == "Survivor" then
			survivorCount = survivorCount + 1
		elseif role == "Killer" then
			killerCount = killerCount + 1
		end
	end

	if survivorCount == 0 then
		self:EndRound(gameService, "Killers", "Katiller herkesi temizledi!")
		return true
	end

	if killerCount == 0 then
		self:EndRound(gameService, "Survivors", "Tüm katiller elendi!")
		return true
	end

	return false
end

function Duo:EndRound(gameService, winnerRole, message)
	print("Duo Modu Bitti! Kazanan:", winnerRole)
end

return Duo