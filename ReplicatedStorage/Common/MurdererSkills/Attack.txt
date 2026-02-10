local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService") -- Decoy'ları bulmak için gerekli
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = Workspace.CurrentCamera

local DefaultSkill = {}

-- // AYARLAR //
local COLOR_START = Color3.fromRGB(255, 170, 0)
local COLOR_END = Color3.fromRGB(255, 0, 0)
local COLOR_OUT_OF_RANGE = Color3.fromRGB(150, 150, 150)

local MAX_DISTANCE = 12 -- Menzili biraz artırdım, daha rahat seçim için
local SELECTION_RADIUS_PIXELS = 250
local SKILL_COOLDOWN = 1.5

local LIMB_ORDER = {
	"Left Arm", "Right Arm", "Left Leg", "Right Leg", "Head"
}

-- Durum Değişkenleri
local currentAdornee = nil
local lastAttackTime = 0

-- // YARDIMCI FONKSİYONLAR //

local function getNextTargetLimb(character)
	if not character then return nil, nil end

	for _, limbName in ipairs(LIMB_ORDER) do
		local limb = character:FindFirstChild(limbName)
		-- "IsEaten" attribute'ü sunucudan set ediliyor, client bunu okur
		if limb and not limb:GetAttribute("IsEaten") then
			return limb, limbName
		end
	end
	return nil, nil
end

local function playAttackAnimation(character)
	local animDataModule = character:FindFirstChild("AnimationData")
	if not animDataModule then return end

	local success, animTable = pcall(require, animDataModule)
	if not success or not animTable or not animTable.attack then return end

	local attacks = animTable.attack
	if #attacks == 0 then return end

	local randomEntry = attacks[math.random(1, #attacks)]
	local humanoid = character:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")

	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = randomEntry.id
		local track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
		task.delay(1, function() 
			if animation then animation:Destroy() end 
		end)
	end
end

-- // HEDEF BULMA MANTIĞI //
local function FindBestTargetOnScreen()
	local mousePos = Vector2.new(Mouse.X, Mouse.Y)
	local closestTarget = nil
	local closestDistance = SELECTION_RADIUS_PIXELS

	local myChar = LocalPlayer.Character
	local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
	if not myRoot then return nil end

	local candidates = {}

	-- 1. GERÇEK OYUNCULARI EKLE
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			-- Rolü "Survivor" olan gerçek oyuncuları al
			if player:GetAttribute("Role") == "Survivor" then
				table.insert(candidates, player.Character)
			end
		end
	end

	-- 2. DECOY (KLON) VE NPC'LERİ EKLE
	-- Decoy scriptinde: CollectionService:AddTag(decoyModel, "Survivor") yapmıştık.
	-- Bu yöntem GetDescendants()'dan çok daha performanslıdır.
	local taggedSurvivors = CollectionService:GetTagged("Survivor")

	for _, npc in ipairs(taggedSurvivors) do
		-- Bu zaten bir oyuncu karakteri mi? (Yukarıda ekledik, tekrar eklemeyelim)
		if not Players:GetPlayerFromCharacter(npc) then
			-- Decoy veya NPC'nin canlı olup olmadığına bak
			local hum = npc:FindFirstChild("Humanoid")
			if hum and hum.Health > 0 then
				table.insert(candidates, npc)
			end
		end
	end

	-- YEDEK PLAN: Eğer Tag kullanmıyorsan, Attribute kontrolü (Decoy scriptinde set etmiştik)
	-- Bu kısım opsiyoneldir, yukarıdaki CollectionService çalışıyorsa buraya gerek yok ama garanti olsun.
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("Decoy") == true then
			-- Listede zaten var mı kontrolü
			local alreadyIn = false
			for _, c in ipairs(candidates) do if c == child then alreadyIn = true break end end

			if not alreadyIn then
				local hum = child:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 then
					table.insert(candidates, child)
				end
			end
		end
	end

	-- 3. ADAYLARI TARAMA (Raycast & Mesafe)
	for _, char in ipairs(candidates) do
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			local dist3D = (myRoot.Position - root.Position).Magnitude

			-- 3D Mesafe Kontrolü
			if dist3D > (MAX_DISTANCE + 5) then continue end

			-- Ekran Pozisyonu Kontrolü
			local screenPos, onScreen = Camera:WorldToViewportPoint(root.Position)
			if not onScreen then continue end

			local distToMouse = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude

			-- En yakın adayı seçme
			if distToMouse < closestDistance then

				-- GÖRÜNMEZ DUVAR / ENGEL KONTROLÜ (Raycast)
				local rayParams = RaycastParams.new()
				rayParams.FilterDescendantsInstances = {myChar, char} -- Kendimizi ve Hedefi yoksay
				rayParams.FilterType = Enum.RaycastFilterType.Exclude

				local direction = (root.Position - Camera.CFrame.Position)
				local result = Workspace:Raycast(Camera.CFrame.Position, direction, rayParams)

				local canSee = false

				if not result then
					canSee = true
				else
					-- Çarptığımız şeyin özellikleri
					local hit = result.Instance

					-- Eğer çarptığımız şey şeffafsa veya CanCollide kapalıysa (dekor vs.) GÖRÜYORUZ say.
					if hit.Transparency > 0.5 or hit.CanCollide == false or hit.Name == "Handle" then
						canSee = true
					end
				end

				if canSee then
					-- Uzuv kontrolü (Yenmemiş uzvu var mı?)
					local testLimb = getNextTargetLimb(char)
					if testLimb then
						closestDistance = distToMouse
						closestTarget = char
					end
				end
			end
		end
	end

	return closestTarget
end

-- // ANA MODÜL //

function DefaultSkill:Activate(Trove)
	-- Cooldown Kontrolü
	if (os.clock() - lastAttackTime) < SKILL_COOLDOWN then 
		return nil 
	end

	local box = LocalPlayer.PlayerGui:FindFirstChild("MurdererSkillBox")

	-- Eğer bir hedef seçiliyse ve menzildeyse
	if box and box.Adornee and box.Color3 ~= COLOR_OUT_OF_RANGE then
		lastAttackTime = os.clock()

		if LocalPlayer.Character then 
			playAttackAnimation(LocalPlayer.Character) 
		end

		-- Server'a gönderilecek veriler: (Hedef Model, Tıklanan Pozisyon)
		return box.Adornee.Parent, Mouse.Hit.Position
	end

	return nil
end

function DefaultSkill:OnStart(Trove)
	-- SelectionBox Oluşturma
	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Name = "MurdererSkillBox"
	selectionBox.LineThickness = 0.05
	selectionBox.SurfaceTransparency = 0.8
	selectionBox.Color3 = COLOR_START
	selectionBox.Parent = LocalPlayer:WaitForChild("PlayerGui")
	Trove:Add(selectionBox)

	-- Her karede çalışacak döngü
	Trove:Connect(RunService.RenderStepped, function()
		local myChar = LocalPlayer.Character
		if not myChar then 
			selectionBox.Adornee = nil 
			return 
		end

		-- Hedef Ara
		local bestCharacter = FindBestTargetOnScreen()

		if not bestCharacter then 
			selectionBox.Adornee = nil 
			currentAdornee = nil
			return 
		end

		-- Hedefin uzvunu bul
		local targetLimb, limbName = getNextTargetLimb(bestCharacter)

		if targetLimb then
			selectionBox.Adornee = targetLimb
			currentAdornee = targetLimb

			-- Menzil Renk Değişimi
			local myRoot = myChar:FindFirstChild("HumanoidRootPart")
			local dist = (myRoot.Position - targetLimb.Position).Magnitude

			if dist <= MAX_DISTANCE then
				selectionBox.LineThickness = 0.08
				selectionBox.SurfaceTransparency = 0.6

				if limbName == "Head" then
					selectionBox.Color3 = COLOR_END -- Kafa ise Kırmızı
				else
					selectionBox.Color3 = COLOR_START -- Kol/Bacak ise Turuncu
				end
			else
				-- Menzil Dışı
				selectionBox.LineThickness = 0.02
				selectionBox.SurfaceTransparency = 0.9
				selectionBox.Color3 = COLOR_OUT_OF_RANGE -- Gri
			end
		else
			selectionBox.Adornee = nil
			currentAdornee = nil
		end
	end)
end

return DefaultSkill