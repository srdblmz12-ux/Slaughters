local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Trove = require(Packages:WaitForChild("Trove"))

local Decoy = {}

--// AYARLAR
Decoy.Name = "Decoy"
Decoy.Cooldown = 80
Decoy.Duration = 30

--// GÖRSEL AYARLAR
Decoy.Description = "Deploys a realistic clone that roams and flees from the Killer."
Decoy.Image = "rbxassetid://0" -- İkon ID

-- AI Ayarları
local SIGHT_RANGE = 60
local HIDE_THRESHOLD = 30

-- Yardımcı Fonksiyon: En müsait kaçış yönünü bulur
local function GetSmartFleePosition(rootPart, killerPos)
	local origin = rootPart.Position
	local baseDir = (origin - killerPos).Unit 

	local anglesToCheck = {0, 45, -45, 90, -90}
	local bestPos = origin + (baseDir * 20)
	local maxDistanceFound = 0

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {rootPart.Parent} 
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	for _, angle in ipairs(anglesToCheck) do
		local rot = CFrame.Angles(0, math.rad(angle), 0)
		local checkDir = (rot * CFrame.new(baseDir)).Position
		local result = workspace:Raycast(origin, checkDir * 25, rayParams)

		if not result then
			return origin + (checkDir * 25)
		else
			if result.Distance > maxDistanceFound then
				maxDistanceFound = result.Distance
				bestPos = result.Position
			end
		end
	end
	return bestPos
end

function Decoy:Activate(player, gameService)
	local character = player.Character
	if not character then return false end

	character.Archivable = true
	local decoyModel = character:Clone()
	character.Archivable = false

	local trove = Trove.new()

	-- 1. NPC KURULUMU
	decoyModel.Name = player.Name .. " (Decoy)"

	local rootPart = decoyModel:FindFirstChild("HumanoidRootPart")
	local humanoid = decoyModel:FindFirstChild("Humanoid")

	if rootPart and humanoid then
		decoyModel.Parent = workspace
		rootPart.CFrame = character.HumanoidRootPart.CFrame * CFrame.new(3, 0, 0)

		rootPart:SetNetworkOwner(nil) -- Sunucu kontrolünde olsun

		-- İsim ve Can barını gizle
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

		CollectionService:AddTag(decoyModel, "Survivor") -- Katil bunu survivor sansın
		trove:Add(decoyModel)

		trove:Add(humanoid.Died:Connect(function()
			task.wait(2)
			trove:Destroy()
		end))
	else
		decoyModel:Destroy()
		return false
	end

	-- 2. AI DÖNGÜSÜ
	local aiLoop = task.spawn(function()
		while decoyModel and decoyModel.Parent and humanoid.Health > 0 do

			local targetKiller = nil
			local distToKiller = math.huge
			local canSeeKiller = false

			-- Katil Tespiti (RunningPlayers string olduğu için rahatça kontrol edebiliriz)
			for otherPlayer, role in pairs(gameService.RunningPlayers) do
				if role == "Killer" and otherPlayer.Character then
					local kRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
					if kRoot then
						local dist = (kRoot.Position - rootPart.Position).Magnitude

						if dist < SIGHT_RANGE then
							targetKiller = kRoot
							distToKiller = dist

							local params = RaycastParams.new()
							params.FilterDescendantsInstances = {decoyModel, otherPlayer.Character}
							params.FilterType = Enum.RaycastFilterType.Exclude
							local dir = (kRoot.Position - rootPart.Position).Unit * dist

							if not workspace:Raycast(rootPart.Position, dir, params) then
								canSeeKiller = true
							end
						end
						break -- İlk bulduğu katile odaklansın
					end
				end
			end

			-- >> DURUM MAKİNESİ <<
			if targetKiller and canSeeKiller then
				-- [KAÇIŞ]
				local safeFleePos = GetSmartFleePosition(rootPart, targetKiller.Position)
				humanoid:MoveTo(safeFleePos)

				if math.random() > 0.2 then humanoid.Jump = true end
				task.wait(0.25)

			elseif targetKiller and not canSeeKiller and distToKiller < HIDE_THRESHOLD then
				-- [PUSU]
				humanoid:MoveTo(rootPart.Position)
				task.wait(0.5)

			else
				-- [GEZİNME]
				local randX = math.random(-30, 30)
				local randZ = math.random(-30, 30)
				local targetPos = rootPart.Position + Vector3.new(randX, 0, randZ)

				self:MoveToPathfinding(humanoid, targetPos)
				humanoid.Jump = false

				if math.random() > 0.6 then
					rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(math.random(90, 180)), 0)
				end
				task.wait(math.random(3, 5))
			end
		end
	end)

	trove:Add(function() task.cancel(aiLoop) end)

	-- Süre dolunca yok et
	task.delay(Decoy.Duration, function() trove:Destroy() end)
end

-- Pathfinding (Sadece Gezinme Modu İçin)
function Decoy:MoveToPathfinding(humanoid, targetPos)
	if not humanoid.Parent then return end

	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentCanJump = false })

	local success = pcall(function()
		path:ComputeAsync(humanoid.Parent.HumanoidRootPart.Position, targetPos)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		-- İlk nokta olduğu yerdir, 2. noktaya git
		if waypoints[2] then humanoid:MoveTo(waypoints[2].Position) end
	else
		humanoid:MoveTo(targetPos)
	end
end

return Decoy