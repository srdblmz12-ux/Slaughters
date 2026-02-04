local Regenerate = {}

Regenerate.Name = "Regenerate"
Regenerate.Cooldown = 60
Regenerate.Duration = 1

local HEAL_AMOUNT = 2 

local function RestoreLimb(part)
	if not part then return end
	part:SetAttribute("IsEaten", nil)
	part.Transparency = 0
	part.CanCollide = false
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 0 end
	end
end

local function updateLegState(humanoid, character)
	local lLeg = character:FindFirstChild("Left Leg")
	local rLeg = character:FindFirstChild("Right Leg")
	if (lLeg and not lLeg:GetAttribute("IsEaten")) or (rLeg and not rLeg:GetAttribute("IsEaten")) then
		humanoid.HipHeight = 0
	else
		humanoid.HipHeight = -2
	end
end

function Regenerate:Activate(player, gameService)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local eatenLegs = {}
	local eatenArms = {}

	for _, name in ipairs({"Left Leg", "Right Leg", "Left Arm", "Right Arm"}) do
		local part = character:FindFirstChild(name)
		if part and part:GetAttribute("IsEaten") then
			if string.find(name, "Leg") then table.insert(eatenLegs, part)
			else table.insert(eatenArms, part) end
		end
	end

	local limbsEatenCount = character:GetAttribute("LimbsEaten") or 0
	if #eatenLegs == 0 and #eatenArms == 0 then return end

	local healedThisTime = 0

	-- Önce Bacaklar
	for i = 1, #eatenLegs do
		if healedThisTime < HEAL_AMOUNT then
			RestoreLimb(eatenLegs[i])
			healedThisTime += 1
		end
	end

	-- Sonra Kollar
	if healedThisTime < HEAL_AMOUNT then
		for i = 1, #eatenArms do
			if healedThisTime < HEAL_AMOUNT then
				RestoreLimb(eatenArms[i])
				healedThisTime += 1
			end
		end
	end

	character:SetAttribute("LimbsEaten", math.max(0, limbsEatenCount - healedThisTime))
	updateLegState(humanoid, character)
	humanoid.Health = math.min(humanoid.Health + 20, humanoid.MaxHealth)
end

return Regenerate