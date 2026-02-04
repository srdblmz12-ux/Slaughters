local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Spr = require(Packages:WaitForChild("spr")) 

local Magic = {}

Magic.Name = "Magic"
Magic.Cooldown = 30 
Magic.Duration = 10 
Magic.TransitionTime = 1 

Magic.Description = "Kısa süreliğine neredeyse tamamen görünmez olursun."
Magic.Image = "rbxassetid://0" 

local DAMPING = 1
local FREQUENCY = 2

function Magic:Activate(player, gameService)
	local character = player.Character
	if not character then return end

	local head = character:FindFirstChild("Head")
	local hiddenGuis = {}
	if head then
		for _, gui in ipairs(head:GetChildren()) do
			if gui:IsA("BillboardGui") and gui.Enabled then
				gui.Enabled = false
				table.insert(hiddenGuis, gui)
			end
		end
	end

	-- Görünmezlik Başlat
	local affectedObjects = {}
	for _, obj in ipairs(character:GetDescendants()) do
		if obj.Name == "HumanoidRootPart" then continue end

		-- DÜZELTME: Parça zaten yenmişse, Magic bunu tamamen görmezden gelmeli.
		if obj:GetAttribute("IsEaten") then continue end

		if obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture") then
			table.insert(affectedObjects, obj)
			Spr.target(obj, DAMPING, FREQUENCY, {Transparency = 0.98})
		end
	end

	-- Bitiş Zamanlayıcısı
	task.delay(Magic.Duration, function()
		if not character or not character.Parent then return end

		for _, gui in ipairs(hiddenGuis) do
			if gui.Parent then gui.Enabled = true end
		end

		for _, obj in ipairs(affectedObjects) do
			if obj and obj.Parent then
				-- Çift Kontrol: Süre esnasında yenmiş olabilir
				if obj:GetAttribute("IsEaten") then continue end

				Spr.target(obj, DAMPING, FREQUENCY, {Transparency = 0})
			end
		end

		task.delay(Magic.TransitionTime + 0.5, function()
			if not character then return end
			for _, obj in ipairs(affectedObjects) do
				if obj then
					Spr.stop(obj)
					-- Son Kontrol: Manuel düzeltme
					if obj:GetAttribute("IsEaten") then
						-- Eğer Spr çalışırken yenmişse, transparan kaldığından emin ol
						if obj:IsA("BasePart") then obj.Transparency = 1 end
					elseif obj:IsA("BasePart") or obj:IsA("Decal") or obj:IsA("Texture") then
						obj.Transparency = 0
					end
				end
			end
		end)
	end)
end

return Magic