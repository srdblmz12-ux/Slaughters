-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Shared = ReplicatedStorage:WaitForChild("Shared") -- [YENİ] Shared klasörü
local Interface = Common:WaitForChild("Interface")
local ResultAssets = Interface:WaitForChild("ResultAssets")

-- Characters Folder (Katil modelleri burada)
local CharactersFolder = Shared:WaitForChild("Characters")

local Net = require(Packages:WaitForChild("Net"))
local Trove = require(Packages:WaitForChild("Trove"))
local spr = require(Packages:WaitForChild("spr"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ResultsController = {
	Name = script.Name,
	UITrove = Trove.new(),
}

--// YARDIMCI: UIScale Kontrolü
local function EnsureUIScale(container)
	if not container then return nil end
	local scale = container:FindFirstChild("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "UIScale"
		scale.Parent = container
	end
	return scale
end

--// Katil Modelini Yükleme (Custom Model - Wendigo vb.)
function ResultsController:LoadKillerModel(skinName, viewportFrame)
	-- WorldModel kontrolü
	local worldModel = viewportFrame:FindFirstChild("WorldModel")
	if not worldModel then
		worldModel = Instance.new("WorldModel")
		worldModel.Name = "WorldModel"
		worldModel.Parent = viewportFrame
	else
		worldModel:ClearAllChildren()
	end

	-- Kamera Hazırlığı
	local camera = viewportFrame:FindFirstChildOfClass("Camera")
	if not camera then
		camera = Instance.new("Camera")
		camera.Parent = viewportFrame
	end
	viewportFrame.CurrentCamera = camera

	-- Modeli Bul ve Kopyala
	local sourceModel = CharactersFolder:FindFirstChild(skinName or "Wendigo")
	if not sourceModel then
		warn("ResultsController: Model bulunamadı ->", skinName)
		return 
	end

	local model = sourceModel:Clone()
	model.Parent = worldModel

	-- Modeli Konumlandır (Pivot noktasına göre 0,0,0'a al)
	local cf = CFrame.new(0, 0, 0)
	model:PivotTo(cf)

	-- Kamerayı Modele Odakla
	-- Modelin kafasını veya ana parçasını bulmaya çalışır
	local head = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")

	if head then
		local lookAt = head.Position
		-- Kamerayı biraz öne (-6) ve hafif yukarı (+1.5) koyuyoruz. Modele göre ayarlayabilirsin.
		local camPos = lookAt + Vector3.new(-1.5, 1.5, -6) 
		camera.CFrame = CFrame.new(camPos, lookAt)
	end

	-- Varsa animasyon oynat (Idle)
	local humanoid = model:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")
	if animator then
		-- Eğer modelin içinde "Idle" animasyonu varsa oynat
		local idleAnim = model:FindFirstChild("Idle") -- Animasyon nesnesinin adı "Idle" olmalı
		if idleAnim and idleAnim:IsA("Animation") then
			local track = animator:LoadAnimation(idleAnim)
			track.Looped = true
			track:Play()
		end
	end
end

--// Arayüzü Göster
function ResultsController:ShowResults(data)
	local HUD = PlayerGui:WaitForChild("ResultsHUD")
	local Container = HUD:WaitForChild("ResultContainer")
	local uiScale = EnsureUIScale(Container)

	-- İçerik Referansları
	-- Hiyerarşi: ResultContainer -> Container (İçinde Render, MurdererName, SurvivorList var)
	local MainContent = Container:WaitForChild("Container") 
	local RenderFrame = MainContent:WaitForChild("Render")

	local TitleContainer = Container:WaitForChild("TitleContainer")
	local AwardedToken = Container:WaitForChild("AwardedToken")
	local AwardedXP = Container:WaitForChild("AwardedXP")

	-- 1. Kazanan Takım Yazısı
	local winnerText = (data.Winner == "Killer") and "MURDERER WON!" or "SURVIVORS WON!"
	local winnerColor = (data.Winner == "Killer") and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(50, 255, 50)

	TitleContainer.Title.Text = winnerText
	TitleContainer.Title.TextColor3 = winnerColor

	-- 2. Katil Bilgisi ve Modeli
	MainContent.MurdererName.Text = data.KillerName or "Unknown"

	-- [GÜNCEL] Skin ismine göre modeli yükle
	self:LoadKillerModel(data.KillerSkin, RenderFrame)

	-- 3. Survivor Listesi
	local listFrame = MainContent:WaitForChild("SurvivorList")

	-- Listeyi temizle
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Listeyi doldur
	for _, survivor in ipairs(data.Survivors) do
		local card = ResultAssets.SurvivorCard:Clone()

		local titleLabel = card:FindFirstChild("Title")
		local diedMark = card:FindFirstChild("DiedMark")

		if titleLabel then
			titleLabel.Text = survivor.Name
			-- Ölenlerin ismini grileştir
			if survivor.IsDead then
				titleLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
			else
				titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end

		if diedMark then
			diedMark.Visible = survivor.IsDead
		end

		card.Parent = listFrame
	end

	-- 4. Ödüller (GameService'den hesaplanıp gelen net kazanç)
	AwardedToken.Title.Text = string.format("Earned +%d tokens", data.MyRewards.Token)
	AwardedXP.Title.Text = string.format("Earned +%d XP", data.MyRewards.XP)

	-- 5. Animasyon ve Gösterim
	HUD.Enabled = true
	Container.Visible = true

	-- [SPR] Başlangıç: Küçük (0)
	uiScale.Scale = 0

	-- [SPR] Hedef: Normal (1) - Yaylanma efekti
	spr.target(uiScale, 0.6, 4, {Scale = 1})

	-- 10 Saniye sonra kapat
	self.UITrove:Add(task.delay(10, function()
		self:HideResults()
	end))
end

--// Arayüzü Gizle
function ResultsController:HideResults()
	local HUD = PlayerGui:WaitForChild("ResultsHUD")
	local Container = HUD:WaitForChild("ResultContainer")
	local uiScale = EnsureUIScale(Container)

	-- [SPR] Çıkış Animasyonu
	spr.target(uiScale, 0.8, 3, {Scale = 0})

	-- Animasyon bitince kapat
	task.delay(0.5, function()
		HUD.Enabled = false
		self.UITrove:Clean()
	end)
end

function ResultsController:OnStart()
	local HUD = PlayerGui:WaitForChild("ResultsHUD")
	HUD.Enabled = false

	-- Başlangıçta UIScale'i hazırla
	EnsureUIScale(HUD:WaitForChild("ResultContainer"))

	-- Server'dan gelen sinyali dinle
	Net:Connect("Results", function(data)
		self:ShowResults(data)
	end)
end

return ResultsController