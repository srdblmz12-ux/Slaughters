-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local UserService = game:GetService("UserService")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")

local Signal = require(Packages:WaitForChild("Signal"))
local Charm = require(Packages:WaitForChild("Charm"))
local Net = require(Packages:WaitForChild("Net"))
local Promise = require(Packages:WaitForChild("Promise"))

-- Constants
local Shared = ReplicatedStorage:WaitForChild("Shared")
local MapsFolder = Shared:WaitForChild("Maps")

local MapService = {
	Name = script.Name,
	Client = {},

	CurrentMapInstance = nil,
	CurrentMapData = Charm.atom(nil),

	Signals = {
		MapLoaded = Signal.new(),
		MapUnloaded = Signal.new()
	},

	Network = {
		MapLoaded = Net:RemoteEvent("MapLoaded"),
		MapUnloaded = Net:RemoteEvent("MapUnloaded")
	}
}

--// SERVER: Mevcut haritayı döndür
function MapService:GetMap()
	return self.CurrentMapInstance, self.CurrentMapData()
end

--// CLIENT: Client erişimi
function MapService.Client:GetMap(player)
	return self.Server:GetMap()
end

--// YARDIMCI: İsimden Modül Bulma
function MapService:FindMapModule(mapName)
	for _, moduleInstance in ipairs(MapsFolder:GetChildren()) do
		if moduleInstance.Name == mapName then
			return moduleInstance
		end
	end
	return nil
end

--// Oylama Verisi Getir
function MapService:GetProcessedVoteOptions(count)
	local allMaps = MapsFolder:GetChildren()
	local selectedModules = {}
	local usedIndices = {}

	local amountToSelect = math.min(count, #allMaps)
	while #selectedModules < amountToSelect do
		local randomIndex = math.random(1, #allMaps)
		if not usedIndices[randomIndex] then
			usedIndices[randomIndex] = true
			table.insert(selectedModules, allMaps[randomIndex])
		end
	end

	local promises = {}

	for _, mapModule in ipairs(selectedModules) do
		table.insert(promises, Promise.new(function(resolve)
			local success, moduleData = pcall(require, mapModule)

			local processedData = {
				Id = mapModule.Name,
				Name = mapModule.Name,
				Description = "No description available.",
				Image = "",
				Authors = {}
			}

			if success and moduleData then
				processedData.Name = moduleData.Name or processedData.Name
				processedData.Description = moduleData.Description or processedData.Description
				processedData.Image = moduleData.Image or processedData.Image

				if moduleData.Authors and #moduleData.Authors > 0 then
					local pcallSuccess, userInfos = pcall(function()
						return UserService:GetUserInfosByUserIdsAsync(moduleData.Authors)
					end)

					if pcallSuccess and userInfos then
						for _, userInfo in ipairs(userInfos) do
							table.insert(processedData.Authors, userInfo.DisplayName)
						end
					end
				end
			else
				warn("MapService: Modül require edilemedi ->", mapModule.Name)
			end

			resolve(processedData)
		end))
	end

	local success, results = Promise.all(promises):await()

	if success then
		return results
	else
		warn("MapService: Oylama verileri hazırlanırken hata oluştu.")
		return {}
	end
end

--// ÇEKİRDEK: Haritayı Yükle (GÜNCELLENDİ: INSTANCE SAYISI KONTROLÜ)
function MapService:LoadMap(mapModule)
	self:Cleanup() 

	local success, mapData = pcall(require, mapModule)
	if not success or not mapData or not mapData.Map then
		warn("Map Yükleme Hatası:", mapModule.Name)
		return nil
	end

	local sourceMap = mapData.Map
	-- 1. Hedef Sayıyı Al: Orijinal haritada kaç tane nesne (Part, Script vs.) var?
	local expectedDescendantCount = #sourceMap:GetDescendants()

	-- 2. Haritayı Kopyala
	local newMapInstance = sourceMap:Clone()
	newMapInstance.Name = "CurrentMap"
	newMapInstance.Parent = Workspace
	self.CurrentMapInstance = newMapInstance

	-- 3. [KONTROL DÖNGÜSÜ] Tüm instanceler Workspace'e geçti mi?
	-- Kopyalanan haritanın içindeki nesne sayısı, orijinalle aynı olana kadar bekle.
	local startTime = os.clock()
	local isFullyLoaded = false

	repeat
		local currentCount = #newMapInstance:GetDescendants()

		if currentCount >= expectedDescendantCount then
			isFullyLoaded = true
		else
			-- Henüz tüm parçalar oluşmadıysa bekle
			task.wait()
		end

		-- Sonsuz döngüye girmemesi için 5 saniyelik güvenlik timeout'u
	until isFullyLoaded or (os.clock() - startTime > 5)

	if not isFullyLoaded then
		warn("MapService UYARI: Harita kopyalandı ama parça sayıları eşleşmedi! (Beklenen: " .. expectedDescendantCount .. ", Bulunan: " .. #newMapInstance:GetDescendants() .. ")")
	end

	-- 4. Varsa Init Fonksiyonu
	if type(mapData.Init) == "function" then
		pcall(function() mapData.Init(newMapInstance) end)
	end

	-- 5. Yazarları Yükle
	local displayAuthors = {"Loading..."}
	task.spawn(function()
		if mapData.Authors then
			local pcallSuccess, userInfos = pcall(function() 
				return UserService:GetUserInfosByUserIdsAsync(mapData.Authors) 
			end)

			if pcallSuccess and userInfos then
				local authorNames = {}
				for _, userInfo in ipairs(userInfos) do 
					table.insert(authorNames, userInfo.DisplayName) 
				end

				self.CurrentMapData(function(currentData) 
					if currentData and currentData.Module == mapModule then 
						local newData = table.clone(currentData)
						newData.Authors = authorNames
						return newData 
					end 
					return currentData 
				end)
			end
		end
	end)

	-- 6. State Güncelle
	self.CurrentMapData({
		Name = mapData.Name,
		Authors = displayAuthors, 
		Module = mapModule
	})

	-- 7. Sinyalleri Ateşle (Tamamlandı)
	self.Signals.MapLoaded:Fire(newMapInstance, mapData)
	self.Network.MapLoaded:FireAllClients(mapData.Name, mapData.Lighting)

	return {
		Spawns = self:GetSpawns(),
		Lighting = mapData.Lighting
	}
end

--// Temizlik
function MapService:Cleanup()
	self.Signals.MapUnloaded:Fire()
	self.Network.MapUnloaded:FireAllClients()

	if self.CurrentMapInstance then
		self.CurrentMapInstance:Destroy()
		self.CurrentMapInstance = nil
	end
	self.CurrentMapData(nil)
end

function MapService:GetSpawns()
	if not self.CurrentMapInstance then return {} end

	local spawnsFolder = self.CurrentMapInstance:FindFirstChild("Spawns")
	if spawnsFolder then return spawnsFolder:GetChildren() end

	local spawns = {}
	for _, descendant in ipairs(self.CurrentMapInstance:GetDescendants()) do
		if descendant:IsA("SpawnLocation") then 
			table.insert(spawns, descendant) 
		end
	end
	return spawns
end

function MapService:OnStart() end

return MapService