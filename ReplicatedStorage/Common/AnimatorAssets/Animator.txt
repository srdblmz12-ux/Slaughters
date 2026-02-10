-- ReplicatedStorage/Common/AnimationRunner.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Trove = require(Packages:WaitForChild("Trove"))

local AnimationRunner = {}
AnimationRunner.__index = AnimationRunner

-- Constants
local FADE_TIME = 0.2

-- Döngüye girmesi gerekenler
local LOOPED_ANIMS = {
	idle = true,
	walk = true,
	run = true,
	swim = true,
	swimidle = true,
	climb = true,
	sit = true,
	fall = true
}

-- Animasyon Öncelikleri
local PRIORITIES = {
	idle = Enum.AnimationPriority.Idle,
	walk = Enum.AnimationPriority.Movement,
	run = Enum.AnimationPriority.Movement,
	swim = Enum.AnimationPriority.Movement,
	climb = Enum.AnimationPriority.Movement,
	jump = Enum.AnimationPriority.Action,
	fall = Enum.AnimationPriority.Action,
}

function AnimationRunner.new(humanoid: Humanoid, animationData: {})
	local self = setmetatable({}, AnimationRunner)

	self._trove = Trove.new()
	self._humanoid = humanoid
	self._animator = humanoid:WaitForChild("Animator")
	self._rootPart = humanoid.Parent:WaitForChild("HumanoidRootPart", 5)

	self._animTable = animationData or {}
	self._loadedTracks = {} -- Cache: { [id] = track }
	self._currentAnim = nil
	self._currentTrack = nil

	self:_setupEvents()

	task.defer(function()
		self:_updateMovementState() 
	end)

	return self
end

function AnimationRunner:_getAnimation(animName)
	local animSet = self._animTable[animName]
	if not animSet then return nil end

	local totalWeight = 0
	for _, entry in ipairs(animSet) do
		totalWeight += entry.weight
	end

	local randomWeight = math.random() * totalWeight
	local currentWeight = 0

	for _, entry in ipairs(animSet) do
		currentWeight += entry.weight
		if randomWeight <= currentWeight then
			return entry
		end
	end

	return animSet[1]
end

function AnimationRunner:_loadTrack(animName)
	local entry = self:_getAnimation(animName)
	if not entry then return nil end

	-- Cache'den getir
	if self._loadedTracks[entry.id] then
		return self._loadedTracks[entry.id]
	end

	-- Yoksa yeni oluştur
	local animation = Instance.new("Animation")
	animation.AnimationId = entry.id

	local track = self._animator:LoadAnimation(animation)

	-- Ayarlar
	if PRIORITIES[animName] then
		track.Priority = PRIORITIES[animName]
	else
		track.Priority = Enum.AnimationPriority.Core
	end

	if LOOPED_ANIMS[animName] then
		track.Looped = true
	end

	self._trove:Add(track) 
	self._loadedTracks[entry.id] = track

	return track
end

function AnimationRunner:Play(animName, fadeTime)
	if self._currentAnim == animName then return end -- Zaten bu animasyon modundaysak çık

	local track = self:_loadTrack(animName)
	if not track then return end

	local oldTrack = self._currentTrack

	-- !!! KRİTİK DÜZELTME BURASI !!!
	-- Eğer yeni animasyon ile eski animasyon AYNI TRACK ise (örneğin Walk ve Run aynı ID ise)
	-- durdurup yeniden başlatma. Sadece ismini güncelle ve devam et.
	if oldTrack == track then
		self._currentAnim = animName
		-- Hız ayarını güncellemek için adjust çağır
		if animName == "walk" or animName == "run" then
			self:_adjustSpeed(self._humanoid.WalkSpeed)
		end
		return
	end

	-- Farklı bir animasyon ise eskisini durdur, yenisini başlat
	track:Play(fadeTime or FADE_TIME)
	self._currentTrack = track
	self._currentAnim = animName

	if oldTrack then
		oldTrack:Stop(fadeTime or FADE_TIME)
	end

	if animName == "walk" or animName == "run" then
		self:_adjustSpeed(self._humanoid.WalkSpeed)
	end
end

function AnimationRunner:_adjustSpeed(speed)
	if not self._currentTrack then return end

	if self._currentAnim == "walk" or self._currentAnim == "run" then
		local scale = 16.0
		local playbackSpeed = speed / scale
		if playbackSpeed < 0.01 then playbackSpeed = 0.1 end
		self._currentTrack:AdjustSpeed(playbackSpeed)
	end
end

function AnimationRunner:_updateMovementState()
	local state = self._humanoid:GetState()
	local speed = 0
	if self._rootPart then
		speed = Vector3.new(self._rootPart.AssemblyLinearVelocity.X, 0, self._rootPart.AssemblyLinearVelocity.Z).Magnitude
	end

	-- Öncelik Kontrolleri
	if state == Enum.HumanoidStateType.Jumping then
		self:Play("jump", 0.1)
		return
	elseif state == Enum.HumanoidStateType.Freefall then
		self:Play("fall", 0.3)
		return
	elseif state == Enum.HumanoidStateType.Climbing then
		self:Play("climb", 0.2)
		return
	elseif state == Enum.HumanoidStateType.Swimming then
		self:Play(speed > 0.5 and "swim" or "swimidle")
		return
	elseif state == Enum.HumanoidStateType.Seated then
		self:Play("sit")
		return
	elseif state == Enum.HumanoidStateType.Dead then
		return
	end

	-- Yer Hareketleri (Running/Landed)
	if speed > 0.5 then
		if speed > 14 then
			self:Play("run")
		else
			self:Play("walk")
		end
		self:_adjustSpeed(speed)
	else
		self:Play("idle")
	end
end

function AnimationRunner:_setupEvents()
	-- Running eventini sadeleştirdik, direkt genel update'i çağırıyoruz ki çakışma olmasın
	self._trove:Connect(self._humanoid.Running, function(speed)
		self:_updateMovementState()
	end)

	self._trove:Connect(self._humanoid.StateChanged, function(old, new)
		self:_updateMovementState()
	end)

	self._trove:Connect(self._humanoid.Climbing, function(speed)
		self:_updateMovementState()
		if self._currentTrack and self._currentAnim == "climb" then
			local climbSpeed = speed / 5
			if climbSpeed < 0.1 then climbSpeed = 0.1 end
			self._currentTrack:AdjustSpeed(climbSpeed)
		end
	end)

	self._trove:Connect(self._humanoid.Died, function()
		self:Destroy()
	end)
end

function AnimationRunner:Destroy()
	self._trove:Destroy()
end

return AnimationRunner