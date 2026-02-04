-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Common = ReplicatedStorage:WaitForChild("Common")
local Interface = Common:WaitForChild("Interface")

local MapVotingAssets = Interface:WaitForChild("MapVotingAssets")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Trove = require(Packages:WaitForChild("Trove"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui

-- Module
local VotingController = {
	Name = script.Name,
	UITrove = Trove.new(),
	Items = {},
}

function VotingController:OnStart()
	local VotingHUD = PlayerGui:WaitForChild("MapVotingHUD")
	local MapPopup = VotingHUD:WaitForChild("MapPopup")
	local CardsPage = MapPopup:WaitForChild("Cards")

	--// UI Temizleme Fonksiyonu
	local function CleanUI()
		-- 1. Önce UI'ı gizle (Hata çıkarsa bile gizlenmiş olsun)
		CardsPage.Visible = false 

		-- 2. Tabloyu sıfırla
		self.Items = {} 

		-- 3. Trove'u temizle (Timer hatası verirse script durmasın diye pcall ile)
		local success, err = pcall(function()
			self.UITrove:Clean()
		end)

		if not success then
			warn("Trove temizlenirken hata oluştu (Önemsiz):", err)
		end
	end

	Net:Connect("GameEnded", CleanUI)
	Net:Connect("WarmupStarted", CleanUI)

	Net:Connect("VoteOptions", function(Options, ServerTime)
		-- Yeni oylama başlarken de eskileri temizle
		CleanUI() 

		-- Timer Oluştur
		local NewTimer = TimerKit.NewTimer(ServerTime)
		NewTimer:Start()

		--// DÜZELTME: Timer'ı Trove'a "Güvenli" ekle
		-- TimerKit'in Destroy fonksiyonu bazen hata verdiği için, onu manuel bir fonksiyonla sarıyoruz.
		self.UITrove:Add(function()
			pcall(function()
				NewTimer:Destroy()
			end)
		end)

		self.UITrove:Connect(NewTimer.OnTick, function(_, Remaining)
			CardsPage.Timer.Description.Text = `Vote a map! {math.floor(Remaining)}s later voting ends`
		end)

		CardsPage.Visible = true

		for _, Details in ipairs(Options) do
			local NewCard = MapVotingAssets:WaitForChild("VoteCard"):Clone()
			NewCard.Parent = CardsPage.Container
			NewCard.Title.Text = Details.Name
			NewCard.Icon.Image = Details.Image
			NewCard.Description.Text = Details.Description

			self.Items[Details.Id] = NewCard
			self.UITrove:Add(NewCard)

			self.UITrove:Connect(NewCard.Activated, function()
				Net:RemoteEvent("CastVote"):FireServer(Details.Id)

				for _, OtherCard in pairs(self.Items) do
					if OtherCard:FindFirstChild("UIStroke") then
						OtherCard.UIStroke.Color = Color3.new(1, 0, 0)
					end
				end
				if NewCard:FindFirstChild("UIStroke") then
					NewCard.UIStroke.Color = Color3.new(0, 1, 0)
				end
			end)
		end
	end)

	Net:Connect("VoteUpdate", function(VoteCounts)
		for MapId, Count in pairs(VoteCounts) do
			local Item = self.Items[MapId]
			if (Item) then
				Item.VoteCount.Text = `{FormatKit.FormatComma(Count)} Vote`
			end
		end
	end)
end

return VotingController