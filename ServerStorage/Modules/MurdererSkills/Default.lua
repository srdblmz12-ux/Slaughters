local DefaultSkill = {}

DefaultSkill.Cooldown = 3
DefaultSkill.Keybind = Enum.UserInputType.MouseButton1

local function getDetailedPartType(part)
	local name = part.Name
	if string.find(name, "Arm") then return "Arm" end
	if string.find(name, "Leg") then return "Leg" end
	if name == "Head" then return "Head" end
	if name == "Torso" then return "Torso" end
	return nil
end

local function findClosestPartByType(character, typeName, mousePos)
	local closest = nil
	local minDist = math.huge
	for _, child in ipairs(character:GetChildren()) do
		-- DÜZELTME: IsEaten ise veya görünmezse hedef alma
		if child:IsA("BasePart") and getDetailedPartType(child) == typeName then
			if child:GetAttribute("IsEaten") or child.Transparency >= 1 then
				continue
			end

			local dist = (child.Position - mousePos).Magnitude
			if dist < minDist then
				minDist = dist
				closest = child
			end
		end
	end
	return closest
end

local function updateLegState(humanoid, character)
	local lLeg = character:FindFirstChild("Left Leg")
	local rLeg = character:FindFirstChild("Right Leg")
	-- İki bacak da yenmişse yere çök
	if (lLeg and lLeg:GetAttribute("IsEaten")) and (rLeg and rLeg:GetAttribute("IsEaten")) then
		humanoid.HipHeight = -2
	else
		humanoid.HipHeight = 0
	end
end

local function HideLimb(part)
	if not part then return end
	part:SetAttribute("IsEaten", true) 
	part.Transparency = 1
	part.CanCollide = false
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") or child:IsA("Texture") then child.Transparency = 1 end
	end
end

function DefaultSkill:Activate(player, GameService, mousePosition)
	local character = player.Character
	if not character then return false end
	local humanoid = character:FindFirstChild("Humanoid")
	local head = character:FindFirstChild("Head")
	if not mousePosition or not head or not humanoid then return false end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(head.Position, (mousePosition - head.Position).Unit * 15, raycastParams)

	-- DÜZELTME: Tıklanan parça yenmişse iptal et
	if not result or result.Instance:GetAttribute("IsEaten") then return false end

	local hitPart = result.Instance
	local victimChar = hitPart.Parent
	local victimHum = victimChar:FindFirstChild("Humanoid")
	if not victimHum and hitPart.Parent:IsA("Accessory") then
		victimChar = hitPart.Parent.Parent
		victimHum = victimChar:FindFirstChild("Humanoid")
	end
	if not victimHum then return false end

	local finalTarget = nil
	local finalType = nil

	-- HİYERARŞİ: Kollar -> Bacaklar -> Kafa
	local anyArm = findClosestPartByType(victimChar, "Arm", mousePosition)
	if anyArm then
		finalTarget = anyArm
		finalType = "Limb"
	else
		local anyLeg = findClosestPartByType(victimChar, "Leg", mousePosition)
		if anyLeg then
			finalTarget = anyLeg
			finalType = "Limb"
		else
			local vHead = victimChar:FindFirstChild("Head")
			if vHead and not vHead:GetAttribute("IsEaten") then
				finalTarget = vHead
				finalType = "Head"
			end
		end
	end

	if not finalTarget then return false end

	local limbsEaten = victimChar:GetAttribute("LimbsEaten") or 0

	if finalType == "Limb" then
		HideLimb(finalTarget)
		victimChar:SetAttribute("LimbsEaten", limbsEaten + 1)
		updateLegState(victimHum, victimChar)
		return true
	elseif finalType == "Head" and limbsEaten >= 4 then
		HideLimb(finalTarget)
		victimHum.Health = 0
		return true
	end

	return false
end

return DefaultSkill