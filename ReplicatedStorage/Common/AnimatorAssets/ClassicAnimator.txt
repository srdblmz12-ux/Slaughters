local RunService = game:GetService("RunService")

local Animation = {}
Animation.__index = Animation

-- Yardımcı Sabitler
local JUMP_MAX_LIMB_VELOCITY = 0.75
local RUNNING_AMPLITUDE = 1
local RUNNING_FREQUENCY = 9
local CLIMB_FREQUENCY = 9

--[[
    Bu modül eski "Procedural Animation" mantığını modern bir yapıya taşır.
    NOT: Bu script sadece R6 Rig yapısı (Torso, HumanoidRootPart) ile çalışır.
]]

-- DÜZELTME: Parametre olarak Character eklendi
function Animation:OnStart(Character, Trove)
	local Figure = Character -- DÜZELTME: script.Parent yerine gelen Character kullanılıyor.

	-- Karakterin yüklenmesini bekle (Defensive Programming)
	local Humanoid = Figure:WaitForChild("Humanoid", 10)
	local Torso = Figure:WaitForChild("Torso", 10)

	if not Humanoid or not Torso then
		warn("ClassicAnimator: Humanoid veya Torso bulunamadı, R6 Rig olmayabilir.")
		return
	end

	-- Motorları Güvenli Şekilde Tanımla
	local Motors = {
		RightShoulder = Torso:WaitForChild("Right Shoulder", 5),
		LeftShoulder = Torso:WaitForChild("Left Shoulder", 5),
		RightHip = Torso:WaitForChild("Right Hip", 5),
		LeftHip = Torso:WaitForChild("Left Hip", 5),
		Neck = Torso:WaitForChild("Neck", 5)
	}

	-- Eğer motorlar eksikse çalışmayı durdur
	if not Motors.RightShoulder or not Motors.LeftShoulder then return end

	-- State Yönetimi
	local state = {
		Pose = "Standing",
		ToolAnim = "None",
		ToolAnimTime = 0,
		AccumulatedTime = 0 -- Sinüs dalgası için zaman sayacı
	}

	-- Tool Animasyon Fonksiyonları
	local function getTool()
		for _, kid in ipairs(Figure:GetChildren()) do
			if kid:IsA("Tool") then return kid end
		end
		return nil
	end

	local function getToolAnim(tool)
		local anim = tool:FindFirstChild("toolanim")
		if anim and anim:IsA("StringValue") then
			return anim
		end
		return nil
	end

	local function animateTool()
		if state.ToolAnim == "None" then
			Motors.RightShoulder:SetDesiredAngle(1.57)
			return
		end

		if state.ToolAnim == "Slash" then
			Motors.RightShoulder.MaxVelocity = 0.5
			Motors.RightShoulder:SetDesiredAngle(0)
			return
		end

		if state.ToolAnim == "Lunge" then
			Motors.RightShoulder.MaxVelocity = 0.5
			Motors.LeftShoulder.MaxVelocity = 0.5
			Motors.RightHip.MaxVelocity = 0.5
			Motors.LeftHip.MaxVelocity = 0.5

			Motors.RightShoulder:SetDesiredAngle(1.57)
			Motors.LeftShoulder:SetDesiredAngle(1.0)
			Motors.RightHip:SetDesiredAngle(1.57)
			Motors.LeftHip:SetDesiredAngle(1.0)
			return
		end
	end

	-- Hareket Mantığı (Move Logic)
	local function updateMovement(dt)
		state.AccumulatedTime = state.AccumulatedTime + dt
		local timeVal = state.AccumulatedTime

		local amplitude
		local frequency
		local climbFudge = 0
		local desiredAngle = 0

		-- Zıplama
		if state.Pose == "Jumping" or state.Pose == "FreeFall" then
			Motors.RightShoulder.MaxVelocity = JUMP_MAX_LIMB_VELOCITY
			Motors.LeftShoulder.MaxVelocity = JUMP_MAX_LIMB_VELOCITY
			Motors.RightShoulder:SetDesiredAngle(3.14)
			Motors.LeftShoulder:SetDesiredAngle(-3.14)
			Motors.RightHip:SetDesiredAngle(0)
			Motors.LeftHip:SetDesiredAngle(0)
			return
		end

		-- Oturma
		if state.Pose == "Seated" then
			Motors.RightShoulder.MaxVelocity = 0.15
			Motors.LeftShoulder.MaxVelocity = 0.15
			Motors.RightShoulder:SetDesiredAngle(3.14 / 2)
			Motors.LeftShoulder:SetDesiredAngle(-3.14 / 2)
			Motors.RightHip:SetDesiredAngle(3.14 / 2)
			Motors.LeftHip:SetDesiredAngle(-3.14 / 2)
			return
		end

		-- Koşma ve Tırmanma Mantığı
		if state.Pose == "Running" then
			-- Kol hareket yumuşatması
			if (Motors.RightShoulder.CurrentAngle > 1.5 or Motors.RightShoulder.CurrentAngle < -1.5) then
				Motors.RightShoulder.MaxVelocity = JUMP_MAX_LIMB_VELOCITY
			else
				Motors.RightShoulder.MaxVelocity = 0.15
			end

			if (Motors.LeftShoulder.CurrentAngle > 1.5 or Motors.LeftShoulder.CurrentAngle < -1.5) then
				Motors.LeftShoulder.MaxVelocity = JUMP_MAX_LIMB_VELOCITY
			else
				Motors.LeftShoulder.MaxVelocity = 0.15
			end

			amplitude = RUNNING_AMPLITUDE
			frequency = RUNNING_FREQUENCY

		elseif state.Pose == "Climbing" then
			Motors.RightShoulder.MaxVelocity = 0.5 
			Motors.LeftShoulder.MaxVelocity = 0.5
			amplitude = RUNNING_AMPLITUDE
			frequency = CLIMB_FREQUENCY
			climbFudge = 3.14

		else -- Standing / Idle
			amplitude = 0.1
			frequency = 1
		end

		-- Sinüs Dalgası Hesabı
		desiredAngle = amplitude * math.sin(timeVal * frequency)

		Motors.RightShoulder:SetDesiredAngle(desiredAngle - climbFudge)
		Motors.LeftShoulder:SetDesiredAngle(desiredAngle - climbFudge)
		Motors.RightHip:SetDesiredAngle(-desiredAngle)
		Motors.LeftHip:SetDesiredAngle(-desiredAngle)

		-- Tool Kontrolü
		local tool = getTool()
		if tool then
			local animStringValue = getToolAnim(tool)
			if animStringValue then
				state.ToolAnim = animStringValue.Value
				animStringValue.Parent = nil -- Mesaj alındı, sil
				state.ToolAnimTime = timeVal + 0.3
			end

			if timeVal > state.ToolAnimTime then
				state.ToolAnimTime = 0
				state.ToolAnim = "None"
			end

			animateTool()
		else
			state.ToolAnim = "None"
			state.ToolAnimTime = 0
		end
	end

	-- Event Bağlantıları (Trove Kullanarak)

	Trove:Connect(Humanoid.Died, function()
		state.Pose = "Dead"
	end)

	Trove:Connect(Humanoid.Running, function(speed)
		state.Pose = (speed > 0.1) and "Running" or "Standing"
	end)

	Trove:Connect(Humanoid.Jumping, function() state.Pose = "Jumping" end)
	Trove:Connect(Humanoid.Climbing, function() state.Pose = "Climbing" end)
	Trove:Connect(Humanoid.GettingUp, function() state.Pose = "GettingUp" end)
	Trove:Connect(Humanoid.FreeFalling, function() state.Pose = "FreeFall" end)
	Trove:Connect(Humanoid.FallingDown, function() state.Pose = "FallingDown" end)
	Trove:Connect(Humanoid.Seated, function() state.Pose = "Seated" end)
	Trove:Connect(Humanoid.PlatformStanding, function() state.Pose = "PlatformStanding" end)

	Trove:Connect(Humanoid.Swimming, function(speed)
		state.Pose = (speed > 0.1) and "Running" or "Standing"
	end)

	-- Ana Döngü (Heartbeat)
	Trove:Connect(RunService.Heartbeat, function(dt)
		updateMovement(dt)
	end)
end

return Animation