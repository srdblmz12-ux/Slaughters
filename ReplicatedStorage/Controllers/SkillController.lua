-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Common = ReplicatedStorage:WaitForChild("Common")

local Interface = Common:WaitForChild("Interface")
local SkillAssets = Interface:WaitForChild("SkillAssets")
local SurvivorSkills = Common:WaitForChild("SurvivorSkills")
local MurdererSkills = Common:WaitForChild("MurdererSkills")

local FormatKit = require(Packages:WaitForChild("FormatKit"))
local TimerKit = require(Packages:WaitForChild("TimerKit"))
local Trove = require(Packages:WaitForChild("Trove"))
local spr = require(Packages:WaitForChild("spr"))
local Net = require(Packages:WaitForChild("Net"))

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Mouse = LocalPlayer:GetMouse()

-- Cihaz Kontrolleri
local IS_MOBILE = UserInputService.TouchEnabled
local function IsGamepad()
	return UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1)
end

-- Klavye Varsayılanları
local DEFAULT_BINDS = {
	[1] = Enum.KeyCode.E,
	[2] = Enum.KeyCode.Q,
	[3] = Enum.KeyCode.R,
	[4] = Enum.KeyCode.F,
}

-- Kontrolcü Varsayılanları (A'yı zıplama olduğu için eledik)
local GAMEPAD_BINDS = {
	[1] = Enum.KeyCode.ButtonX,
	[2] = Enum.KeyCode.ButtonY,
	[3] = Enum.KeyCode.ButtonR1, -- RB
	[4] = Enum.KeyCode.ButtonL1, -- LB
}

-- Kontrolcü Tuş İsimleri
local GAMEPAD_DISPLAY_NAMES = {
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonR1] = "RB",
	[Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR2] = "RT",
	[Enum.KeyCode.ButtonL2] = "LT",
}

local SkillController = {
	Name = script.Name,
	UITrove = Trove.new(),
	Items = {}, 
}

--// Tuş İsmini Platforma Göre Getir
local function GetKeyDisplayName(inputEnum)
	-- Kontrolcü tuşu mu?
	if GAMEPAD_DISPLAY_NAMES[inputEnum] then
		return GAMEPAD_DISPLAY_NAMES[inputEnum]
	end

	-- Mouse/Mobil mi?
	if inputEnum == Enum.UserInputType.MouseButton1 then
		return IS_MOBILE and "TAP" or "M1"
	elseif inputEnum == Enum.UserInputType.MouseButton2 then
		return "M2"
	end

	-- Normal klavye tuşu
	return inputEnum.Name:gsub("Button", "")
end

function SkillController:GetSkillModule(skillName)
	return SurvivorSkills:FindFirstChild(skillName) or MurdererSkills:FindFirstChild(skillName)
end

function SkillController:Activate(data)
	local now = workspace:GetServerTimeNow()
	if data.FinishTime and now < data.FinishTime then return end

	Net:RemoteEvent("ActivateSkill"):FireServer(data.SkillName, Mouse.Hit)

	local moduleScript = self:GetSkillModule(data.SkillName) :: ModuleScript?
	if moduleScript then
		local skillModule = require(moduleScript)
		if skillModule.Activate then
			skillModule:Activate(self.UITrove) 
		end
	end
end

function SkillController:OnStart()
	local SkillHUD = PlayerGui:WaitForChild("SkillHUD")
	local UsageContainer = SkillHUD:WaitForChild("UsageContainer")
	local SkillPopup = SkillHUD:WaitForChild("SkillPopup")
	local CardsPage = SkillPopup:WaitForChild("Cards")
	local CardsContainer = CardsPage:WaitForChild("Container")

	Net:Connect("GameEnded", function()
		self.UITrove:Clean()
		self.Items = {}
		CardsPage.Visible = false
	end)

	Net:Connect("SkillOptionsOffered", function(Options, ServerTime)
		local NewTimer = TimerKit.NewTimer(ServerTime)
		NewTimer:Start()

		self.UITrove:Connect(NewTimer.OnTick, function(_, RemainingTime : number)
			CardsPage.Timer.Description.Text = `Select a skill. ({math.floor(RemainingTime)}s)`
		end)
		self.UITrove:Add(NewTimer)

		CardsPage.Visible = true
		for _,SkillData in ipairs(Options) do
			local SkillCard = SkillAssets.SkillCard:Clone()
			SkillCard.Parent = CardsContainer
			SkillCard.Icon.Image = SkillData.Image
			SkillCard.Title.Text = SkillData.Name
			SkillCard.Description.Text = SkillData.Description

			self.UITrove:Add(SkillCard)
			self.UITrove:Connect(SkillCard.Activated, function()
				Net:RemoteEvent("SelectSkill"):FireServer(SkillData.Name)
				CardsPage.Visible = false
			end)
		end
	end)

	Net:Connect("SkillAssigned", function(SkillName: string, Cooldown: number, Keybind: EnumItem?)
		CardsPage.Visible = false

		local assignedKey = Keybind
		if not assignedKey then
			local count = 0
			for _ in pairs(self.Items) do count += 1 end
			local nextIndex = count + 1

			-- Kontrolcü varsa kontrolcü bind'ını al
			if IsGamepad() then
				assignedKey = GAMEPAD_BINDS[nextIndex] or Enum.KeyCode.ButtonX
			else
				assignedKey = DEFAULT_BINDS[nextIndex] or Enum.KeyCode.E
			end
		end

		local Data = {
			SkillName = SkillName,
			Cooldown = Cooldown, 
			InputEnum = assignedKey,
			FinishTime = 0,
			Item = SkillAssets.SkillButton:Clone()
		}

		Data.Item.SkillName.Text = SkillName
		Data.Item.Keycode.Text = GetKeyDisplayName(assignedKey)
		Data.Item.Fade.Size = UDim2.fromScale(0, 1) 
		Data.Item.Parent = UsageContainer

		-- Mobilde tuş ismini gizle (sadece buton kalsın)
		if IS_MOBILE and not IsGamepad() then
			Data.Item.Keycode.Visible = false
			Data.Item.SkillName.UIPadding.PaddingLeft = Data.Item.SkillName.UIPadding.PaddingRight
		end

		self.UITrove:Add(Data.Item)
		self.UITrove:Connect(Data.Item.Activated, function()
			self:Activate(Data)
		end)

		self.Items[assignedKey] = Data

		local moduleScript = self:GetSkillModule(SkillName) :: ModuleScript?
		if moduleScript then
			local skillModule = require(moduleScript)
			if skillModule.OnStart then
				skillModule:OnStart(self.UITrove) 
			end
		end
	end)

	Net:Connect("CooldownUpdate", function(SkillName: string)
		for _, data in pairs(self.Items) do
			if data.SkillName == SkillName then
				data.FinishTime = workspace:GetServerTimeNow() + data.Cooldown
				data.Item.Fade.Size = UDim2.fromScale(1, 1)

				local Tween = TweenService:Create(data.Item.Fade, TweenInfo.new(data.Cooldown, Enum.EasingStyle.Linear), {
					Size = UDim2.fromScale(0, 1)
				})
				Tween:Play()
				Tween.Completed:Once(function()
					Tween:Destroy()
				end)
				break
			end
		end
	end)

	-- Girdi Takibi
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		-- KeyCode kontrol (Klavye + Kontrolcü)
		local data = self.Items[input.KeyCode]

		-- Alternatif kontroller (Mouse + Mobil Touch)
		if not data then
			if IS_MOBILE and input.UserInputType == Enum.UserInputType.Touch then
				data = self.Items[Enum.UserInputType.MouseButton1]
			else
				data = self.Items[input.UserInputType]
			end
		end

		if data then
			self:Activate(data)
		end
	end)
end

return SkillController