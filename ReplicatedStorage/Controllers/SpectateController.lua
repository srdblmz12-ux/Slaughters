-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Variables
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Trove = require(Packages:WaitForChild("Trove"))

local Net = require(Packages:WaitForChild("Net"))

-- References
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = Workspace.CurrentCamera

-- Controller
local SpectateController = {
	Name = script.Name,
	IsSpectating = false,
	CurrentTargetIndex = 1,
	ValidTargets = {},
	Trove = Trove.new(),
}

--// YARDIMCI FONKSİYONLAR

-- Canlı oyuncuları bul
function SpectateController:GetValidTargets()
	local targets = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player == LocalPlayer then continue end

		-- Karakteri, Humanoid'i ve HumanoidRootPart'ı var mı? Canlı mı?
		local char = player.Character
		if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") and char.Humanoid.Health > 0 then
			table.insert(targets, player)
		end
	end
	return targets
end

-- Arayüz ve Kamerayı Güncelle
function SpectateController:UpdateView(Container)
	-- Listeyi tazele
	self.ValidTargets = self:GetValidTargets()

	-- Kimse kalmadıysa kapat
	if #self.ValidTargets == 0 then
		self:StopSpectating(Container)
		return
	end

	-- Index sınırlarını düzelt
	if self.CurrentTargetIndex > #self.ValidTargets then self.CurrentTargetIndex = 1 end
	if self.CurrentTargetIndex < 1 then self.CurrentTargetIndex = #self.ValidTargets end

	local targetPlayer = self.ValidTargets[self.CurrentTargetIndex]
	local Controllers = Container.Controllers

	-- 1. UI Bilgilerini Güncelle
	Controllers.Username.Text = targetPlayer.DisplayName .. " (@" .. targetPlayer.Name .. ")"
	Controllers.Role.Text = "Loading..."

	-- 2. Rol Bilgisini Çek (Server'dan)
	task.spawn(function()
		-- Hata olursa patlamasın diye pcall veya güvenli çağrı yapıyoruz
		local success, data = pcall(function() 
			return Net:Invoke("GameService/GetPlayerData", targetPlayer.Name) 
		end)

		if success and data and self.IsSpectating and self.ValidTargets[self.CurrentTargetIndex] == targetPlayer then
			Controllers.Role.Text = data.Role or "Unknown"

			-- Rol Rengi
			if data.Role == "Killer" then
				Controllers.Role.TextColor3 = Color3.fromRGB(255, 50, 50)
			elseif data.Role == "Survivor" then
				Controllers.Role.TextColor3 = Color3.fromRGB(50, 255, 50)
			else
				Controllers.Role.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end)
end

-- Spectate Başlat
function SpectateController:StartSpectating(Container)
	if self.IsSpectating then return end

	self.ValidTargets = self:GetValidTargets()

	if #self.ValidTargets == 0 then
		-- Kimse yoksa başlamadan dön
		return 
	end

	self.IsSpectating = true
	self.CurrentTargetIndex = 1

	-- UI Düzenlemesi
	Container.SpectateButton.Title.Text = "Lobby"
	Container.Controllers.Visible = true

	self:UpdateView(Container)

	RunService:BindToRenderStep("SpectateCam", Enum.RenderPriority.Camera.Value + 1, function()
		if not self.IsSpectating then 
			RunService:UnbindFromRenderStep("SpectateCam")
			return 
		end

		local targetPlayer = self.ValidTargets[self.CurrentTargetIndex]

		-- Hedef Geçersizse (Öldü/Çıktı) -> Değiştir
		if not targetPlayer or not targetPlayer.Parent or 
			not targetPlayer.Character or 
			not targetPlayer.Character:FindFirstChild("Humanoid") or 
			targetPlayer.Character.Humanoid.Health <= 0 then

			self:NextTarget(Container)
			return
		end

		-- Kamerayı Hedefe Kilitle
		local hum = targetPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			Camera.CameraType = Enum.CameraType.Custom
			Camera.CameraSubject = hum
		end
	end)
end

-- Spectate Bitir
function SpectateController:StopSpectating(Container)
	self.IsSpectating = false
	RunService:UnbindFromRenderStep("SpectateCam") -- Kamera döngüsünü durdur

	-- Kamerayı kendine döndür
	task.wait(0.1) -- Ufak bir gecikme ile çakışmayı önle
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
		Camera.CameraType = Enum.CameraType.Custom
		Camera.CameraSubject = LocalPlayer.Character.Humanoid
	end

	-- UI Eski haline
	Container.SpectateButton.Title.Text = "Spectate"
	Container.Controllers.Visible = false
end

function SpectateController:NextTarget(Container)
	self.CurrentTargetIndex = self.CurrentTargetIndex + 1
	self:UpdateView(Container)
end

function SpectateController:PrevTarget(Container)
	self.CurrentTargetIndex = self.CurrentTargetIndex - 1
	self:UpdateView(Container)
end

function SpectateController:OnStart()
	local HUD = PlayerGui:WaitForChild("GameStatusHUD")
	local Container = HUD:WaitForChild("SpectateContainer")
	local SpectateBtn = Container:WaitForChild("SpectateButton")
	local Controllers = Container:WaitForChild("Controllers")

	Container.Visible = false
	Controllers.Visible = false

	-- [YENİ] Oyun Durumunu Takip Etmek İçin Değişken
	local CurrentGameStatus = "Intermission"

	-- Butonlar
	SpectateBtn.Activated:Connect(function()
		if self.IsSpectating then
			self:StopSpectating(Container)
		else
			self:StartSpectating(Container)
		end
	end)

	Controllers.LeftButton.Activated:Connect(function()
		self:PrevTarget(Container)
	end)

	Controllers.RightButton.Activated:Connect(function()
		self:NextTarget(Container)
	end)

	-- Görünürlük Kontrolü
	local function CheckVisibility(isDeathEvent)
		-- [ÖNEMLİ EKLEME] Eğer oyun aktif değilse (Intermission, Voting, Loading) butonu asla gösterme!
		if CurrentGameStatus ~= "GameRunning" and CurrentGameStatus ~= "Warmup" then
			Container.Visible = false

			-- Eğer oyun bittiyse ve hala izliyorsak izlemeyi durdur
			if self.IsSpectating then
				self:StopSpectating(Container)
			end
			return
		end

		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChild("Humanoid")

		-- 1. Eğer ölüm olayından geldiysek, bekleme süresi koy (Ölüm animasyonu ve farkındalık için)
		if isDeathEvent then
			task.wait(3.5) -- 3.5 Saniye bekle (Oyuncu öldüğünü anlasın)
		end

		-- 2. Tekrar kontrol et (Belki bu sürede respawn oldu?)
		char = LocalPlayer.Character
		hum = char and char:FindFirstChild("Humanoid")

		-- 3. Karakter yoksa veya hala ölüyse -> GÖSTER (Ama sadece oyun devam ediyorsa)
		if not hum or hum.Health <= 0 then
			Container.Visible = true
			return
		end

		-- 4. Yaşıyorsak Rol Kontrolü Yap (Lobi mi, Oyun mu?)
		task.spawn(function()
			local success, myData = pcall(function()
				return Net:Invoke("GameService/GetPlayerData", LocalPlayer.Name)
			end)

			if success and myData and myData.Role == "Lobby" then
				-- Lobideyiz (Elendik ve oyun hala devam ediyor) -> GÖSTER
				Container.Visible = true
			else
				-- Oyundayız (Survivor/Killer) -> GİZLE
				Container.Visible = false

				-- Eğer yanlışlıkla spectate açıksa kapat
				if self.IsSpectating then
					self:StopSpectating(Container)
				end
			end
		end)
	end

	-- [YENİ] StateUpdate Listener: Oyun durumunu takip et
	Net:Connect("StateUpdate", function(State, Data)
		if State == "GameStatus" then
			CurrentGameStatus = Data
			CheckVisibility(false) -- Durum değiştiğinde görünürlüğü tekrar kontrol et
		end
	end)

	-- Karakter Olayları
	LocalPlayer.CharacterAdded:Connect(function(char)
		CheckVisibility(false) -- Normal spawn, bekleme yok

		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Died:Connect(function()
				CheckVisibility(true) -- Ölüm gerçekleşti, bekleme süresi uygula
			end)
		end
	end)

	-- İlk Giriş Kontrolü
	if LocalPlayer.Character then
		CheckVisibility(false)
		local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
		if hum then
			hum.Died:Connect(function()
				CheckVisibility(true)
			end)
		end
	else
		CheckVisibility(false)
	end
end

return SpectateController