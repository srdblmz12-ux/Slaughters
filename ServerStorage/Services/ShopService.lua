-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Services = ServerStorage:WaitForChild("Services")

local ShopAssets = Shared:WaitForChild("ShopAssets")

-- DataService'i dahil ediyoruz
local DataService = require(Services:WaitForChild("DataService"))

-- Module
local ShopService = {
	Name = script.Name,
	Client = {},
	ItemList = {} -- Yüklenen eşya modüllerini tutar: { ["ItemName"] = {Price = 100, Category = "KillerSkins"} }
}

--// Helper Functions (Yardımcı Fonksiyonlar)

-- Bu fonksiyon satın alma işlemini sunucu tarafında işler
function ShopService:ProcessPurchase(player, itemName)
	local itemData = self.ItemList[itemName]

	-- 1. Eşya oyunda tanımlı mı?
	if not itemData then
		warn("ShopService: Tanımsız eşya istendi -> " .. tostring(itemName))
		return false, "Item not found"
	end

	-- 2. Oyuncu profili yüklü mü?
	local profileData = DataService:GetData(player)
	if not profileData then
		return false, "Data not loaded"
	end

	-- 3. Eşyanın kaydedileceği kategori veride var mı? (Örn: KillerSkins)
	local categoryName = itemData.DataCategory or itemData.Category -- Modülde "DataCategory" veya "Category" tanımlı olmalı
	local playerInventory = profileData[categoryName]

	if not playerInventory then
		warn("ShopService: Geçersiz kategori -> " .. tostring(categoryName))
		return false, "Invalid Category"
	end

	-- 4. Oyuncu buna zaten sahip mi?
	if self:UserHas(player, categoryName, itemName) then
		return false, "Already owned"
	end

	-- 5. Parası yetiyor mu?
	local price = itemData.Price
	if profileData.CurrencyData.Value >= price then
		-- :: İŞLEM BAŞARILI ::

		-- A) Parayı düş (DataService'in kendi fonksiyonunu kullanıyoruz ki UI güncellensin)
		DataService:AddCurrency(player, -price)

		-- B) Eşyayı envantere ekle
		playerInventory[itemName] = true

		print(player.Name .. " satın aldı: " .. itemName)
		return true, "Purchase successful"
	else
		return false, "Not enough Money"
	end
end

--// Client Functions (Client'tan çağrılanlar)

function ShopService.Client:Purchase(player, itemName)
	-- Client doğrudan ShopService tablosuna erişemez, bu yüzden ana tablo (ShopService) üzerinden fonksiyonu çağırıyoruz.
	return ShopService:ProcessPurchase(player, itemName)
end

function ShopService.Client:GetItemData(player, itemName)
	-- Client bir eşyanın fiyatını vb. sormak isterse
	return ShopService.ItemList[itemName]
end

--// Server Functions

function ShopService:UserHas(player, category, itemName)
	local profileData = DataService:GetData(player)
	if not profileData then return false end

	-- DataService yapına göre: profile.Data.KillerSkins["Wendigo"] = true
	if profileData[category] and profileData[category][itemName] then
		return true
	end

	return false
end

function ShopService:OnStart()
	-- Assets klasöründeki eşyaları yükle
	for _, CategoryFolder in ipairs(ShopAssets:GetChildren()) do
		for _, Item in ipairs(CategoryFolder:GetChildren()) do
			if (Item:IsA("ModuleScript")) then
				local Success, ModuleData = pcall(require, Item)
				if (Success) then
					-- Modül verisini tabloya kaydet
					-- ÖNEMLİ: Modüllerin içinde Price ve Category/DataCategory olduğundan emin ol.
					self.ItemList[Item.Name] = ModuleData

					-- Eğer modülde kategori yazmıyorsa, klasör adını varsayılan yapabiliriz (Opsiyonel)
					if not ModuleData.Category and not ModuleData.DataCategory then
						ModuleData.Category = CategoryFolder.Name
					end
				else
					warn(`ShopService: Failed to load module {Item.Name}: {ModuleData}`)
				end
			end
		end
	end
end

return ShopService