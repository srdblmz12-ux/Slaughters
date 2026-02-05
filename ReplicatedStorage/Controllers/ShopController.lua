-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Variables
local Controllers = ReplicatedStorage:WaitForChild("Controllers")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Interface = Common:WaitForChild("Interface")
local UIShopAssets = Interface:WaitForChild("ShopAssets")

local ShopAssets = Shared:WaitForChild("ShopAssets")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

local NotificationController = require(Controllers.NotificationController)

-- Module
local ShopController = {
	Name = script.Name,
	Pages = {},         -- { ["CategoryName"] = PageFrame }
	Buttons = {},       -- { ["CategoryName"] = CategoryButton }
	CachedData = nil    -- Oyuncu verisini geçici tutmak için
}

--// Helper: Kamera Ayarlama Fonksiyonu (İstediğin mantık)
local function SetupViewportCamera(viewportFrame, model)
	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	local head = model:FindFirstChild("Head")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Torso")

	if head then
		-- Kafa varsa: Yüze odaklan, hafif önden bak
		local headPos = head.Position
		local lookAt = headPos
		-- Kafanın biraz önü ve hafif yukarısı
		local camPos = headPos + (model.PrimaryPart.CFrame.LookVector * 2.5) + Vector3.new(0, 0.2, 0)

		camera.CFrame = CFrame.lookAt(camPos, lookAt)
	elseif root then
		-- Kafa yoksa: Vücuda odaklan, bacakları gösterme (Zoom yap)
		local rootPos = root.Position
		-- Gövdenin biraz yukarısına odaklan (UpperTorso gibi)
		local lookAt = rootPos + Vector3.new(0, 1, 0) 
		-- Daha yakından bak
		local camPos = rootPos + (root.CFrame.LookVector * 4) + Vector3.new(0, 1.5, 0)

		camera.CFrame = CFrame.lookAt(camPos, lookAt)
	else
		-- Hiçbir şey yoksa standart bounding box
		local cf, size = model:GetBoundingBox()
		camera.CFrame = CFrame.lookAt(cf.Position + (cf.LookVector * 5), cf.Position)
	end
end

--// Helper: Kategori Geçiş Görsellerini Güncelle
function ShopController:UpdateCategoryVisuals(selectedCategory)
	for name, button in pairs(self.Buttons) do
		local isSelected = (name == selectedCategory)
		-- Seçiliyse Yeşil, değilse Kırmızı (UIStroke)
		button.UIStroke.Color = isSelected and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
	end

	for name, page in pairs(self.Pages) do
		page.Visible = (name == selectedCategory)
	end
end

--// Helper: Kart Durumunu Güncelle (Satın alındı mı?)
local function UpdateCardState(card, itemPrice, isOwned)
	if isOwned then
		card.PurchaseButton.Title.Text = "Owned" -- Veya "Equip"
		card.PurchaseButton.UIStroke.Color = Color3.fromRGB(100, 100, 100) -- Gri yap
	else
		card.PurchaseButton.Title.Text = `Buy for {FormatKit.FormatComma(itemPrice)}`
		card.PurchaseButton.UIStroke.Color = Color3.fromRGB(0, 255, 0) -- Yeşil
	end
end

function ShopController:CreatePage(CategoryName : string, Enabled : boolean, Children : {})
	local CategoryButton = UIShopAssets.Category:Clone()
	local Page = UIShopAssets.Page:Clone()

	CategoryButton.Title.Text = CategoryName
	CategoryButton.Name = CategoryName
	Page.Name = CategoryName
	Page.Visible = Enabled

	-- Buton ve Sayfayı listeye kaydet
	self.Buttons[CategoryName] = CategoryButton
	self.Pages[CategoryName] = Page

	-- İlk renk ayarı
	CategoryButton.UIStroke.Color = Enabled and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)

	-- Kategori Değiştirme Mantığı
	CategoryButton.Activated:Connect(function()
		self:UpdateCategoryVisuals(CategoryName)
	end)

	-- Kartları Oluştur
	for itemName, Details in pairs(Children or {}) do
		local NewCard = UIShopAssets.Card:Clone()
		-- HATA DÜZELTİLDİ: NewCard.Parent = NewCard yerine Page olmalı
		NewCard.Parent = Page 
		NewCard.Name = Details.Name -- Veya itemName
		NewCard.Title.Text = Details.Name

		-- Model Render İşlemleri
		local Viewport = NewCard:WaitForChild("Render") -- UI yapına göre değişebilir
		local ModelTemplate = Details.Model or Details.Character -- Modül yapına göre

		if ModelTemplate then
			local NewModel = ModelTemplate:Clone()
			NewModel.Parent = Viewport.WorldModel -- WorldModel içine atıyoruz

			-- Kamerayı Ayarla
			SetupViewportCamera(Viewport, NewModel)
		end

		-- İlk Yüklemede Sahiplik Kontrolü
		-- Not: Veriyi OnStart'ta çekip self.CachedData'ya atabiliriz performans için
		local isOwned = false
		if self.CachedData and self.CachedData[Details.DataCategory] then
			if self.CachedData[Details.DataCategory][Details.Name] then
				isOwned = true
			end
		end

		UpdateCardState(NewCard, Details.Price, isOwned)

		-- Satın Alma Mantığı
		NewCard.PurchaseButton.Activated:Connect(function()
			-- Tekrar veriyi kontrol et (Sunucu en son otorite ama client güncel olmalı)
			local currentData = Net:Invoke("DataService/GetData")
			local alreadyOwned = false
			if currentData and currentData[Details.DataCategory] and currentData[Details.DataCategory][Details.Name] then
				alreadyOwned = true
			end

			if alreadyOwned then
				-- Zaten sahipse belki kuşanma (Equip) işlemi yapılır
				NotificationController.Signals.SendNotification:Fire("You already own this item!", 3)
				return
			end

			-- Satın Almayı Dene
			local State, Response = Net:Invoke("ShopService/Purchase", Details.Name) -- ID yerine Name kullandık çünkü ShopService öyle bekliyor

			if State then
				-- Başarılı
				NotificationController.Signals.SendNotification:Fire("Successfully purchased!", 5)
				UpdateCardState(NewCard, Details.Price, true)

				-- Veriyi güncelle (UI için)
				self.CachedData = Net:Invoke("DataService/GetData")
			else
				-- Başarısız (Yetersiz bakiye vb.)
				NotificationController.Signals.SendNotification:Fire(Response, 5)
			end
		end)
	end

	return CategoryButton, Page
end

function ShopController:OnStart()
	local IngameHUD = PlayerGui:WaitForChild("IngameHUD")
	local ShopContainer = IngameHUD:WaitForChild("ShopContainer")
	local SidebarContainer = IngameHUD:WaitForChild("SidebarContainer")

	-- Başlarken veriyi bir kere çekelim ki kartları "Owned" olarak işaretleyebilelim
	self.CachedData = Net:Invoke("DataService/GetData")

	-- ShopAssets Klasörünü Tara
	local firstCategory = true
	for Index, Category in ipairs(ShopAssets:GetChildren()) do
		local Cards = {}

		-- Modülleri Require et
		for _, Item in ipairs(Category:GetChildren()) do
			if (Item:IsA("ModuleScript")) then
				local Success, ModuleData = pcall(require, Item)
				if (Success) then
					-- Modüle Model veya Character eklemeyi unutma (Server tarafında konuştuğumuz gibi)
					-- Eğer modülde Model yoksa, Assets'ten bulmayı deneyebiliriz:
					if not ModuleData.Model and ModuleData.Character then
						ModuleData.Model = ModuleData.Character
					end

					Cards[Item.Name] = ModuleData
				else
					warn("ShopController: Failed to load " .. Item.Name)
				end
			end
		end

		-- Sayfayı Oluştur (İlk kategoriyi otomatik aç)
		local CategoryButton, Page = self:CreatePage(Category.Name, firstCategory, Cards)

		CategoryButton.Parent = ShopContainer.Categories
		Page.Parent = ShopContainer.Pages

		firstCategory = false
	end
	
	SidebarContainer.Shop.ShopButton.Activated:Connect(function()
		local State = not ShopContainer.Visible
		ShopContainer.Visible = State
		ShopContainer.Interactable = State
	end)
end

return ShopController