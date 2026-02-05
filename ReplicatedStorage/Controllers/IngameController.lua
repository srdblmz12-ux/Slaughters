-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local FormatKit = require(Packages:WaitForChild("FormatKit")) 
local spr = require(Packages:WaitForChild("spr"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local IngameController = {
	Name = script.Name,
}

-- Update Token (Currency) Interface (Pop Effect with spr)
function IngameController:UpdateCurrency(amount)
	-- Güvenlik: Gelen veri sayı mı? Değilse 0 yap.
	if typeof(amount) ~= "number" then amount = 0 end

	local IngameHUD = PlayerGui:WaitForChild("IngameHUD", 5)
	if not IngameHUD then return end

	local Sidebar = IngameHUD:WaitForChild("SidebarContainer")
	local ShopFrame = Sidebar:WaitForChild("Shop")
	local TokenLabel = ShopFrame:WaitForChild("TokenValue")

	TokenLabel.Text = "Tokens: " .. FormatKit.FormatComma(amount)
end

-- Update Killer Chance Interface
function IngameController:UpdateChance(amount)
	local IngameHUD = PlayerGui:WaitForChild("IngameHUD", 5)
	if not IngameHUD then return end

	local Sidebar = IngameHUD:WaitForChild("SidebarContainer")
	local LuckFrame = Sidebar:WaitForChild("LuckRatio")
	local LuckLabel = LuckFrame:FindFirstChild("LuckRatio") or LuckFrame:FindFirstChild("Title")

	if LuckLabel then
		LuckLabel.Text = "Chance to be killer: " .. tostring(amount) .. "%"
	end
end

-- Update Level Interface (Bar Fill with spr)
function IngameController:UpdateLevel(levelData)
	local LevelHUD = PlayerGui:WaitForChild("LevelHUD", 5)
	if not LevelHUD then return end

	local Container = LevelHUD:WaitForChild("LevelContainer")
	local ValueCont = Container:WaitForChild("ValueContainer")
	local LevelBar = Container:WaitForChild("LevelBar")

	ValueCont.Level.Text = "Level " .. tostring(levelData.Level)
	ValueCont.CurrentXP.Text = string.format("%d/%d", levelData.ValueXP, levelData.TargetXP)

	local fillBar = LevelBar:FindFirstChild("FillBar")
	if fillBar then
		local percent = math.clamp(levelData.ValueXP / levelData.TargetXP, 0, 1)
		spr.target(fillBar, 0.8, 2, {Size = UDim2.fromScale(percent, 1)})
	end
end

-- [YENİ] Tüm Verileri Yenileme Yardımcısı
function IngameController:RefreshAllData()
	-- 1. Profil Verilerini Çek (Para ve Level)
	local Data = Net:Invoke("DataService/GetData")
	if Data then
		-- Data.CurrencyData bir tablodur, .Value diyerek sayıyı alıyoruz
		self:UpdateCurrency(Data.CurrencyData.Value)
		self:UpdateLevel(Data.LevelData)
	end

	-- 2. Şans Verisini Çek (PlayerService üzerinden)
	local success, chance = pcall(function()
		return Net:Invoke("PlayerService/GetChance")
	end)
	if success and chance then
		self:UpdateChance(chance)
	end
end

function IngameController:OnStart()
	-- [DİNLEYİCİLER] Sunucudan gelen anlık değişimleri yakala
	Net:Connect("DataUpdate", function(Type, Data)
		if Type == "Currency" then
			self:UpdateCurrency(Data)
		elseif Type == "Level" then
			self:UpdateLevel(Data)
		end
	end)

	Net:Connect("ChanceUpdate", function(NewChance)
		self:UpdateChance(NewChance)
	end)

	-- [İLK YÜKLEME] Oyuna girince verileri çek
	self:RefreshAllData()

	-- [KRİTİK DÜZELTME] Karakter Doğunca Verileri Tekrar Çek
	-- Lobiye dönüşte (Respawn olunca) ResetOnSpawn yüzünden UI sıfırlanıyor.
	-- Bu yüzden karakter her geldiğinde verileri tekrar yerine koyuyoruz.
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5) -- UI'ın yüklenmesi için minik bir bekleme
		self:RefreshAllData()
	end)
end

return IngameController