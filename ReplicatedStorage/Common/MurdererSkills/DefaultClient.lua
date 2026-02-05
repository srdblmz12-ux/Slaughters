local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local DefaultSkill = {}

-- Renk Paleti (Lerp için)
local COLOR_START = Color3.fromRGB(255, 170, 0) -- Turuncu
local COLOR_END = Color3.fromRGB(255, 0, 0)     -- Kırmızı

-- Helper: Parçanın tam türü
local function getDetailedPartType(part)
	local name = part.Name
	if name == "Handle" then return nil end

	if string.find(name, "Arm") or string.find(name, "Hand") then return "Arm" end
	if string.find(name, "Leg") or string.find(name, "Foot") then return "Leg" end
	if name == "Head" then return "Head" end
	if string.find(name, "Torso") or name == "HumanoidRootPart" then return "Torso" end

	return nil
end

local function findClosestPartByType(character, typeName, mousePos)
	local closest = nil
	local minDist = math.huge

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("BasePart") and getDetailedPartType(child) == typeName then
			local dist = (child.Position - mousePos).Magnitude
			if dist < minDist then
				minDist = dist
				closest = child
			end
		end
	end
	return closest
end

function DefaultSkill:Activate(Trove)
	local box = LocalPlayer.PlayerGui:FindFirstChild("MurdererSkillBox")
	if box and box.Adornee then
		local tween = TweenService:Create(box, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {Color3 = Color3.new(1, 1, 1)})
		tween:Play()
	end
end

function DefaultSkill:OnStart(Trove)
	local selectionBox = Instance.new("SelectionBox")
	selectionBox.Name = "MurdererSkillBox"
	selectionBox.LineThickness = 0.05
	selectionBox.Parent = LocalPlayer:WaitForChild("PlayerGui")
	Trove:Add(selectionBox)

	Trove:Connect(RunService.RenderStepped, function()
		local character = LocalPlayer.Character
		if not character then 
			selectionBox.Adornee = nil 
			return 
		end

		local head = character:FindFirstChild("Head")
		local mousePos = Mouse.Hit.Position

		if not head then 
			selectionBox.Adornee = nil
			return 
		end

		local origin = head.Position
		local direction = (mousePos - origin).Unit * 15

		-- Raycast (Boşa bakma kontrolü)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {character}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local result = workspace:Raycast(origin, direction, raycastParams)
		if not result then
			selectionBox.Adornee = nil
			return
		end

		local hitPart = result.Instance
		local victimChar = hitPart.Parent
		local victimHum = victimChar:FindFirstChild("Humanoid")

		if not victimHum and hitPart.Parent:IsA("Accessory") then
			victimChar = hitPart.Parent.Parent
			victimHum = victimChar:FindFirstChild("Humanoid")
		end

		if not victimHum then
			selectionBox.Adornee = nil
			return
		end

		-- >>> KATI GÖRSEL HİYERARŞİ <<<
		local finalTarget = nil
		local targetType = nil

		-- 1. Kollar var mı?
		local anyArm = findClosestPartByType(victimChar, "Arm", mousePos)
		if anyArm then
			finalTarget = anyArm
			targetType = "Limb"
		else
			-- 2. Bacaklar var mı?
			local anyLeg = findClosestPartByType(victimChar, "Leg", mousePos)
			if anyLeg then
				finalTarget = anyLeg
				targetType = "Limb"
			else
				-- 3. Kafa
				local vHead = victimChar:FindFirstChild("Head")
				if vHead then
					finalTarget = vHead
					targetType = "Head"
				end
			end
		end

		if not finalTarget then
			selectionBox.Adornee = nil
			return
		end

		local limbsEaten = victimChar:GetAttribute("LimbsEaten") or 0
		local isDead = victimHum.Health <= 0

		selectionBox.Adornee = finalTarget

		if targetType == "Limb" then
			-- Renk Geçişi (Lerp): Kollar yenince kırmızıya yaklaş
			local ratio = math.clamp(limbsEaten / 4, 0, 1)
			selectionBox.Color3 = COLOR_START:Lerp(COLOR_END, ratio)

		elseif targetType == "Head" then
			if limbsEaten >= 4 then
				selectionBox.Color3 = Color3.fromRGB(255, 0, 0) -- Tam Kırmızı
			else
				selectionBox.Adornee = nil -- Kafa henüz yenemiyorsa kutu gösterme
			end

		elseif targetType == "Torso" then
			-- Torso sadece kafa yoksa ve ölüyse hedef alınır ama yukarıdaki hiyerarşi zaten bunu kapsıyor
			-- Yine de görsel olarak ekleyelim
			if isDead then
				selectionBox.Color3 = COLOR_START
			else
				selectionBox.Adornee = nil
			end
		else
			selectionBox.Adornee = nil
		end
	end)
end

return DefaultSkill