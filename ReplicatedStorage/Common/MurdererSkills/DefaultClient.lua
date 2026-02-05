local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local DefaultSkill = {}

local COLOR_START = Color3.fromRGB(255, 170, 0) -- Turuncu
local COLOR_END = Color3.fromRGB(255, 0, 0)     -- Kırmızı
local MAX_DISTANCE = 15 -- Maksimum yeme mesafesi
local HITBOX_RADIUS = 1.5 -- Işının kalınlığı (TPS'de ıskalamayı önler)

local function getDetailedPartType(part)
	local name = part.Name
	if string.find(name, "Arm") then return "Arm" end
	if string.find(name, "Leg") then return "Leg" end
	if name == "Head" then return "Head" end
	return nil
end

-- Bir parçadan yola çıkarak Humanoid içeren Karakter Modelini bulur (Daha güvenli yöntem)
local function findCharacterModel(part)
	local current = part
	while current and current ~= workspace do
		if current:FindFirstChild("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Hedef hiyerarşisine göre yenecek parçayı seç
local function getPriorityTarget(victimChar)
	local limbsEaten = victimChar:GetAttribute("LimbsEaten") or 0

	-- 1. Kollar (Eğer hala varsa)
	for _, name in ipairs({"Left Arm", "Right Arm"}) do
		local p = victimChar:FindFirstChild(name)
		if p and not p:GetAttribute("IsEaten") then
			return p, "Limb"
		end
	end

	-- 2. Bacaklar
	for _, name in ipairs({"Left Leg", "Right Leg"}) do
		local p = victimChar:FindFirstChild(name)
		if p and not p:GetAttribute("IsEaten") then
			return p, "Limb"
		end
	end

	-- 3. Kafa
	local head = victimChar:FindFirstChild("Head")
	if head and not head:GetAttribute("IsEaten") and limbsEaten >= 4 then
		return head, "Head"
	end

	return nil, nil
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
	selectionBox.LineThickness = 0.04
	selectionBox.SurfaceTransparency = 0.8
	selectionBox.Parent = LocalPlayer:WaitForChild("PlayerGui")
	Trove:Add(selectionBox)

	Trove:Connect(RunService.RenderStepped, function()
		local myChar = LocalPlayer.Character
		if not myChar then selectionBox.Adornee = nil return end
		local myRoot = myChar:FindFirstChild("HumanoidRootPart")
		if not myRoot then selectionBox.Adornee = nil return end

		-- 1. ADIM: Spherecast (Kalın Işın) Hazırlığı
		-- Mouse pozisyonuna giden ışın yönünü alıyoruz
		local mouseRay = Camera:ScreenPointToRay(Mouse.X, Mouse.Y)

		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {myChar}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		-- Spherecast: Normal Raycast yerine kalın bir küre fırlatır.
		-- Bu, TPS'de nişan almayı çok daha affedici yapar.
		local result = workspace:Spherecast(mouseRay.Origin, HITBOX_RADIUS, mouseRay.Direction * 100, raycastParams)

		if not result then 
			selectionBox.Adornee = nil 
			return 
		end

		local hitPart = result.Instance
		-- Mesafe kontrolünü "Hit Position" yerine köke olan uzaklıktan yapmak daha güvenlidir
		-- Ancak Spherecast'in vurduğu nokta ile kök arasındaki mesafeyi alıyoruz
		local dist = (myRoot.Position - result.Position).Magnitude

		-- 2. ADIM: Mesafe ve IsEaten Kontrolü
		if dist > MAX_DISTANCE or hitPart:GetAttribute("IsEaten") then
			selectionBox.Adornee = nil
			return
		end

		-- 3. ADIM: Karakter Tespiti (Geliştirilmiş)
		local victimChar = findCharacterModel(hitPart)

		if not victimChar then
			selectionBox.Adornee = nil
			return
		end

		local humanoid = victimChar:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			selectionBox.Adornee = nil
			return
		end

		-- 4. ADIM: Hiyerarşiye Göre Hedef Belirleme
		local finalTarget, targetType = getPriorityTarget(victimChar)

		if finalTarget then
			selectionBox.Adornee = finalTarget

			-- Renk ayarı
			local limbsEaten = victimChar:GetAttribute("LimbsEaten") or 0
			if targetType == "Limb" then
				local ratio = math.clamp(limbsEaten / 4, 0, 1)
				selectionBox.Color3 = COLOR_START:Lerp(COLOR_END, ratio)
			else
				selectionBox.Color3 = COLOR_END
			end
		else
			selectionBox.Adornee = nil
		end
	end)
end

return DefaultSkill