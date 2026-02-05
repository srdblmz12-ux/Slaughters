-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")
local SkillsFolder = Modules:WaitForChild("SurvivorSkills")

local Charm = require(Packages:WaitForChild("Charm"))
local Net = require(Packages:WaitForChild("Net"))

local GameService = require(Services:WaitForChild("GameService"))

local SurvivorService = {
	Name = script.Name,
	Client = {},

	IsSelectionOpen = false,
	AreSkillsActive = false, 

	SelectedSkills = {}, 
	OfferedSkills = {},  
	Cooldowns = {},      

	Network = {
		SelectSkill = Net:RemoteEvent("SelectSkill"), 
		SkillAssigned = Net:RemoteEvent("SkillAssigned"), 
		ActivateSkill = Net:RemoteEvent("ActivateSkill"), 
		CooldownUpdate = Net:RemoteEvent("CooldownUpdate"),
		SkillOptionsOffered = Net:RemoteEvent("SkillOptionsOffered"),
	}
}

-- [DÜZELTME 1] UserId ile Rol Kontrolü
function SurvivorService:IsSurvivor(player)
	local uid = tostring(player.UserId)
	local role = GameService.RunningPlayers[uid]
	return role == "Survivor"
end

function SurvivorService:_offerSkillsToPlayer(player)
	local allSkillsScripts = SkillsFolder:GetChildren()
	if #allSkillsScripts == 0 then return end

	local optionsDataToSend = {} 
	local validOptionNames = {}  
	local usedIndices = {}

	local countToSelect = math.min(3, #allSkillsScripts)

	while #validOptionNames < countToSelect do
		local index = math.random(1, #allSkillsScripts)
		if not usedIndices[index] then
			usedIndices[index] = true
			local skillScript = allSkillsScripts[index]
			local success, skillModule = pcall(require, skillScript)

			if success and skillModule then
				table.insert(validOptionNames, skillScript.Name)
				table.insert(optionsDataToSend, {
					Name = skillScript.Name,
					DisplayName = skillModule.Name or skillScript.Name,
					Description = skillModule.Description or "...",
					Image = skillModule.Image or "",
					Cooldown = skillModule.Cooldown or 20
				})
			end
		end
	end

	self.OfferedSkills[player] = validOptionNames
	local remainingTime = GameService.TimeLeft()
	self.Network.SkillOptionsOffered:FireClient(player, optionsDataToSend, remainingTime)
end

function SurvivorService:OfferRandomSkills()
	-- [DÜZELTME 2] Döngüde UserId -> Player dönüşümü
	for userIdStr, role in pairs(GameService.RunningPlayers) do
		if role == "Survivor" then
			local player = Players:GetPlayerByUserId(tonumber(userIdStr))
			if player then
				self:_offerSkillsToPlayer(player)
			end
		end
	end
end

function SurvivorService:SelectSkill(player, skillName)
	if not self.IsSelectionOpen then return end
	if not self:IsSurvivor(player) then return end
	if self.SelectedSkills[player] then return end 

	local offered = self.OfferedSkills[player]
	if not offered or not table.find(offered, skillName) then return end

	local skillModuleScript = SkillsFolder:FindFirstChild(skillName)
	if not skillModuleScript then return end

	self.SelectedSkills[player] = skillName

	local mod = require(skillModuleScript)
	self.Network.SkillAssigned:FireClient(player, skillName, mod.Cooldown or 20, mod.Keybind)
end

function SurvivorService:_finalizeSelections()
	self.IsSelectionOpen = false

	-- [DÜZELTME 3] Döngüde UserId -> Player dönüşümü
	for userIdStr, role in pairs(GameService.RunningPlayers) do
		local player = Players:GetPlayerByUserId(tonumber(userIdStr))

		if player and role == "Survivor" and not self.SelectedSkills[player] then
			local offered = self.OfferedSkills[player]
			local finalChoice = nil

			if offered and #offered > 0 then
				finalChoice = offered[math.random(1, #offered)]
			end

			if finalChoice then
				local scriptObj = SkillsFolder:FindFirstChild(finalChoice)
				if scriptObj then
					local mod = require(scriptObj)
					self.SelectedSkills[player] = finalChoice
					self.Network.SkillAssigned:FireClient(player, finalChoice, mod.Cooldown or 20, mod.Keybind)
				end
			end
		end
	end
end

function SurvivorService:ActivateSkill(player, skillName, mousePosition)
	if not self.AreSkillsActive then return end 
	if not self:IsSurvivor(player) then return end

	if self.SelectedSkills[player] ~= skillName then return end

	local currentTime = workspace:GetServerTimeNow()
	self.Cooldowns[player] = self.Cooldowns[player] or {}

	local atom = self.Cooldowns[player][skillName]
	if atom and atom() > currentTime then return end

	local scriptObj = SkillsFolder:FindFirstChild(skillName)
	if scriptObj then
		local mod = require(scriptObj)

		local targetPos = nil
		if typeof(mousePosition) == "CFrame" then targetPos = mousePosition.Position
		elseif typeof(mousePosition) == "Vector3" then targetPos = mousePosition end

		mod:Activate(player, GameService, targetPos)

		local cd = mod.Cooldown or 20
		local finish = currentTime + cd

		if not atom then
			self.Cooldowns[player][skillName] = Charm.atom(finish)
		else
			self.Cooldowns[player][skillName](finish)
		end

		self.Network.CooldownUpdate:FireClient(player, skillName, finish)
	end
end

function SurvivorService:OnStart()
	self.Network.SelectSkill.OnServerEvent:Connect(function(plr, name) self:SelectSkill(plr, name) end)
	self.Network.ActivateSkill.OnServerEvent:Connect(function(plr, name, pos) self:ActivateSkill(plr, name, pos) end)

	GameService.Signals.WarmupStarted:Connect(function()
		self.IsSelectionOpen = true
		self.AreSkillsActive = false
		self.SelectedSkills = {}
		self.OfferedSkills = {} 
		self.Cooldowns = {}
		self:OfferRandomSkills() 
	end)

	GameService.Signals.GameStarted:Connect(function()
		self:_finalizeSelections()
		self.AreSkillsActive = true
	end)

	GameService.Signals.GameEnded:Connect(function()
		self.IsSelectionOpen = false
		self.AreSkillsActive = false
		self.SelectedSkills = {}
		self.OfferedSkills = {}
		self.Cooldowns = {}
	end)

	Players.PlayerAdded:Connect(function(player)
		if GameService.GameStatus() == "Warmup" and self:IsSurvivor(player) then
			self:_offerSkillsToPlayer(player)
		end
	end)
end

return SurvivorService