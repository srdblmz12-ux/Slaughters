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

		-- [SPR ANIMATION] Bar Filling
		-- Damping: 0.8 (Controlled, less bouncy)
		-- Frequency: 2 (Heavier feel)
		spr.target(fillBar, 0.8, 2, {Size = UDim2.fromScale(percent, 1)})
	end
end

function IngameController:OnStart()
	-- Listen for server signals
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
	
	local Data = Net:Invoke("DataService/GetData")
	self:UpdateCurrency(Data.CurrencyData)
	self:UpdateLevel(Data.LevelData)
end

return IngameController