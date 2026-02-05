-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")
local SkillsFolder = Modules:WaitForChild("MurdererSkills")

local Charm = require(Packages:WaitForChild("Charm"))
local Net = require(Packages:WaitForChild("Net"))
local Promise = require(Packages:WaitForChild("Promise"))

local GameService = require(Services:WaitForChild("GameService"))
local DataService = require(Services:WaitForChild("DataService"))

local MurdererService = {
	Name = script.Name,
	Client = {},

	Cooldowns = {}, 

	Network = {
		ActivateSkill = Net:RemoteEvent("ActivateSkill"),
		CooldownUpdate = Net:RemoteEvent("CooldownUpdate"),
		SkillAssigned = Net:RemoteEvent("SkillAssigned"), 
	}
}

-- [DÜZELTME 1] UserId ile Rol Kontrolü
function MurdererService:IsMurderer(player)
	local uid = tostring(player.UserId)
	local role = GameService.RunningPlayers[uid]
	return role == "Killer"
end

function MurdererService:_initializeMurdererSkill()
	-- [DÜZELTME 2] Döngüde UserId -> Player dönüşümü
	for userIdStr, role in pairs(GameService.RunningPlayers) do
		if role == "Killer" then
			local player = Players:GetPlayerByUserId(tonumber(userIdStr))

			if player then
				DataService:GetProfile(player):andThen(function(profile)
					local skillName = profile.Data.MurdererSkill or "Default"
					local skillModuleScript = SkillsFolder:FindFirstChild(skillName) or SkillsFolder:FindFirstChild("Default")

					if skillModuleScript then
						local skillModule = require(skillModuleScript)
						local cooldownTime = skillModule.Cooldown or 10
						local keybind = skillModule.Keybind 

						self.Network.SkillAssigned:FireClient(player, skillName, cooldownTime, keybind)
					end
				end)
			end
		end
	end
end

function MurdererService:ActivateSkill(player, skillName, mousePosition)
	if not self:IsMurderer(player) then return end
	if GameService.Gamemode() == "Waiting" then return end
	if typeof(skillName) ~= "string" then return end

	local targetPos = nil
	if mousePosition then
		if typeof(mousePosition) == "CFrame" then
			targetPos = mousePosition.Position
		elseif typeof(mousePosition) == "Vector3" then
			targetPos = mousePosition
		end
	end
	if not targetPos then return end

	DataService:GetProfile(player):andThen(function(profile)
		local equippedSkill = profile.Data.MurdererSkill or "Default"
		if skillName ~= equippedSkill then return end

		local currentTime = workspace:GetServerTimeNow()
		if not self.Cooldowns[player] then self.Cooldowns[player] = {} end
		local skillAtom = self.Cooldowns[player][skillName]
		if skillAtom and skillAtom() > currentTime then return end

		local skillModuleScript = SkillsFolder:FindFirstChild(skillName) or SkillsFolder:FindFirstChild("Default")
		if skillModuleScript then
			local skillModule = require(skillModuleScript)

			local success = skillModule:Activate(player, GameService, targetPos)

			if success == true then
				local cd = skillModule.Cooldown or 10
				local finish = currentTime + cd

				if not self.Cooldowns[player][skillName] then
					self.Cooldowns[player][skillName] = Charm.atom(finish)
				else
					self.Cooldowns[player][skillName](finish)
				end
				self.Network.CooldownUpdate:FireClient(player, skillName, finish)
			end
		end
	end):catch(warn)
end

function MurdererService:OnStart()
	self.Network.ActivateSkill.OnServerEvent:Connect(function(player, skillName, mousePosition)
		self:ActivateSkill(player, skillName, mousePosition)
	end)

	GameService.Signals.GameStarted:Connect(function()
		self:_initializeMurdererSkill()
	end)

	GameService.Signals.GameEnded:Connect(function()
		self.Cooldowns = {}
	end)
end

return MurdererService