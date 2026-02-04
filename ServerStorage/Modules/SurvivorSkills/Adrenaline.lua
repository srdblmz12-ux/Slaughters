--- START OF FILE Adrenaline.txt ---

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Adrenaline = {}

--// GENEL AYARLAR
Adrenaline.Name = "Adrenaline"
Adrenaline.Cooldown = 40 -- Skilli tekrar kullanma süresi

--// SÜRE AYARLARI (İstediğin Gibi Ayrıldı)
Adrenaline.BoostDuration = 10   -- Kaç saniye hızlı koşacak
Adrenaline.FatigueDuration = 6  -- Kaç saniye yorgun (yavaş) kalacak
Adrenaline.Duration = 10        -- UI'da görünecek aktiflik süresi (Genelde boost süresi yazılır)

--// GÖRSEL AYARLAR
Adrenaline.Description = "10 saniye hızlanırsın, ardından 6 saniye yorgun düşersin."
Adrenaline.Image = "rbxassetid://0" -- İkon ID

--// HIZ DEĞERLERİ
local BOOST_AMOUNT = 8      -- Hızlanırken eklenecek hız (+8)
local FATIGUE_DROP = 12     -- Hızlı halden yorgun hale geçiş düşüşü 
-- (Mantık: +8 hızdayız, -12 düşersek, normalin -4 altına ineriz)
local RECOVERY_AMOUNT = 4   -- Yorgunluk bitince eklenecek hız (+4) -> Normale dönüş

function Adrenaline:Activate(player, gameService)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- 1. HIZLANMA BAŞLA (+8 Speed)
	humanoid.WalkSpeed = humanoid.WalkSpeed + BOOST_AMOUNT

	-- 2. HIZLANMA SÜRESİ DOLUNCA (10 Saniye Sonra)
	task.delay(Adrenaline.BoostDuration, function()
		-- Karakter hala oyunda mı ve yaşıyor mu kontrol et
		if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return end

		-- Hızlı halden yorgun hale geçiş
		-- Şu an hızımız (16+8=24). 12 çıkarırsak 12 kalır. (Normali 16 idi, yani -4 yemiş oluruz)
		humanoid.WalkSpeed = math.max(0, humanoid.WalkSpeed - FATIGUE_DROP)

		-- 3. YORGUNLUK SÜRESİ DOLUNCA (6 Saniye Sonra)
		task.delay(Adrenaline.FatigueDuration, function()
			if not character or not character.Parent or not humanoid or humanoid.Health <= 0 then return end

			-- Normale dönüş (+4 ekle)
			humanoid.WalkSpeed = humanoid.WalkSpeed + RECOVERY_AMOUNT
		end)
	end)
end

return Adrenaline