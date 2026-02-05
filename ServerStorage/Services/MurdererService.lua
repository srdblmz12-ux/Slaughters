-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Services = ServerStorage:WaitForChild("Services")
local Modules = ServerStorage:WaitForChild("Modules")

local MurdererSkillsFolder = Modules:WaitForChild("MurdererSkills")
local MainAttackModule = MurdererSkillsFolder:WaitForChild("Attack") -- Ana Saldırı Scripti
local SecondarySkillsFolder = MurdererSkillsFolder:WaitForChild("Skills") -- Diğer Skillerin Klasörü

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

-- UserId ile Rol Kontrolü
function MurdererService:IsMurderer(player)
	local uid = tostring(player.UserId)
	local role = GameService.RunningPlayers[uid]
	return role == "Killer"
end

function MurdererService:_initializeMurdererSkill()
	for userIdStr, role in pairs(GameService.RunningPlayers) do
		if role == "Killer" then
			local player = Players:GetPlayerByUserId(tonumber(userIdStr))

			if player then
				-- 1. ADIM: Her zaman "Attack" (Ana Skill) yükle
				local attackModule = require(MainAttackModule)
				-- İstemciye "Attack" adıyla gönderiyoruz
				self.Network.SkillAssigned:FireClient(player, "Attack", attackModule.Cooldown or 2, attackModule.Keybind)

				-- 2. ADIM: Datadaki Yan Yeteneği (KillerSkill) yükle
				DataService:GetProfile(player):andThen(function(profile)
					-- [GÜNCELLEME] Yeni Data Yapısı: Equippeds.KillerSkill
					local equippedData = profile.Data.Equippeds
					local skillName = ""

					if equippedData and equippedData.KillerSkill then
						skillName = equippedData.KillerSkill
					end

					-- Eğer bir skill seçili değilse veya boşsa işlem yapma
					if skillName ~= "" then
						local skillModuleScript = SecondarySkillsFolder:FindFirstChild(skillName)

						if skillModuleScript then
							local skillModule = require(skillModuleScript)
							local cooldownTime = skillModule.Cooldown or 10
							local keybind = skillModule.Keybind 

							self.Network.SkillAssigned:FireClient(player, skillName, cooldownTime, keybind)
						end
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
	-- Bazı skiller mouse pozisyonu gerektirmeyebilir (örn: kendine hız basma), o yüzden targetPos kontrolünü skill içine bırakmak daha iyi olabilir ama şimdilik senin yapını koruyorum.
	if not targetPos then return end

	local skillModuleScript = nil

	-- [GÜNCELLEME] Skill Seçimi Mantığı
	if skillName == "Attack" then
		-- Eğer gelen istek "Attack" ise direkt ana modülü kullan
		skillModuleScript = MainAttackModule
	else
		-- Değilse, oyuncunun datasındaki yetenek mi diye kontrol et
		local profile = DataService:GetProfile(player):expect() -- Promise beklemesi gerekebilir ama burada direkt erişim varsayıyoruz ya da cache kullanıyordur.
		-- Not: DataService promise döndürüyorsa yukarıdaki gibi :andThen içinde olmalıydı. 
		-- Ancak pratiklik açısından burada mantığı kuruyorum:

		if profile and profile.Data.Equippeds and profile.Data.Equippeds.KillerSkill == skillName then
			skillModuleScript = SecondarySkillsFolder:FindFirstChild(skillName)
		end
	end

	-- Eğer geçerli bir modül bulunamadıysa (Hile koruması: Oyuncu sahip olmadığı veya Attack olmayan bir şey yolladıysa)
	if not skillModuleScript then return end

	-- COOLDOWN KONTROLÜ
	local currentTime = workspace:GetServerTimeNow()
	if not self.Cooldowns[player] then self.Cooldowns[player] = {} end

	local skillAtom = self.Cooldowns[player][skillName]
	if skillAtom and skillAtom() > currentTime then return end

	-- SKILL AKTİVASYONU
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