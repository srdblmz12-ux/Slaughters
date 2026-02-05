-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local LightingImporter = require(Packages:WaitForChild("LightingImporter")) -- İsmi kontrol et: 'LighingImporter' yazmışsın, 'LightingImporter' olabilir.
local Net = require(Packages:WaitForChild("Net"))

local DefaultLighting = require(Shared:WaitForChild("DefaultLighting"))

-- Module
local LightingController = {
	Name = script.Name
}

--// Lighting Verisini İşle ve Uygula
function LightingController:ApplyLighting(lightingData)
	if not lightingData then
		warn("LightingController: Data is empty")
		return
	end

	LightingImporter.ImportJSON(lightingData, true)
end

function LightingController:OnStart()
	-- 1. GameService'den gelen özel Lighting yükleme isteği
	Net:Connect("LoadLighting", function(lightingData)
		self:ApplyLighting(lightingData)
	end)

	-- 2. MapService'den gelen harita yüklenme sinyali (Burada da lighting verisi var)
	Net:Connect("MapLoaded", function(mapName, lightingData)
		if lightingData then
			self:ApplyLighting(lightingData)
		end
	end)

	-- Opsiyonel: Oyun bittiğinde veya harita silindiğinde varsayılan lighting'e dönmek istersen:
	Net:Connect("MapUnloaded", function()
		LightingImporter.ImportJSON(DefaultLighting, true)
	end)
end

return LightingController