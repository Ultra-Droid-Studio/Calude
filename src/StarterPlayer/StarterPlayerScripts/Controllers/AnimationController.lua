-- AnimationController: ÖZEL eylem animasyonları için merkezi yönetim (Bölüm 20).
-- * Avatarın kendi hareket animasyonlarına (Animate scripti) DOKUNMAZ.
-- * Rig tipine (R6/R15) göre doğru animasyon ID'sini seçer.
-- * Aynı animasyonu üst üste başlatmaz (tekrar oynatma koruması).
-- * Karakter değişince tüm track'leri durdurur ve temizler (bellek sızıntısı yok).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Shared.Utilities.Maid)
local AnimationConfig = require(Modules.AnimationConfig)
local Log = require(Shared.Utilities.Log).new("Animation")

local AnimationController = {
	Name = "AnimationController",
	Priority = 4,
}

local controllers
local charMaid = Maid.new()
local animator: Animator? = nil
local rigType = "R15"
local tracks: { [string]: AnimationTrack } = {}
local warnedMissing: { [string]: boolean } = {}

local function resolveId(actionName: string): string?
	local def = AnimationConfig.Actions[actionName]
	if not def then
		return nil
	end
	local id = def[rigType]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	if not id:find("rbxassetid://") then
		id = "rbxassetid://" .. id
	end
	return id
end

local function getTrack(actionName: string): AnimationTrack?
	local cached = tracks[actionName]
	if cached then
		return cached
	end
	if not animator then
		return nil
	end
	local id = resolveId(actionName)
	if not id then
		if not warnedMissing[actionName .. rigType] then
			warnedMissing[actionName .. rigType] = true
			Log.Info("Animasyon ID'si yok, atlanıyor:", actionName, rigType)
		end
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		Log.Warn("Animasyon yüklenemedi:", actionName, track)
		return nil
	end
	local def = AnimationConfig.Actions[actionName]
	track.Looped = def.Looped
	track.Priority = def.Priority
	tracks[actionName] = track
	return track
end

-- Oynatır; animasyon yoksa nil döner (çağıran taraf buna hazırlıklı olmalı)
function AnimationController:Play(actionName: string, fadeTime: number?, speed: number?): AnimationTrack?
	local track = getTrack(actionName)
	if not track then
		return nil
	end
	if track.IsPlaying then
		if speed then
			track:AdjustSpeed(speed)
		end
		return track -- tekrar başlatma
	end
	track:Play(fadeTime or AnimationConfig.DefaultFadeTime, 1, speed or 1)
	return track
end

function AnimationController:Stop(actionName: string, fadeTime: number?)
	local track = tracks[actionName]
	if track and track.IsPlaying then
		track:Stop(fadeTime or AnimationConfig.DefaultFadeTime)
	end
end

function AnimationController:StopAll(fadeTime: number?)
	for _, track in tracks do
		if track.IsPlaying then
			track:Stop(fadeTime or AnimationConfig.DefaultFadeTime)
		end
	end
end

function AnimationController:IsPlaying(actionName: string): boolean
	local track = tracks[actionName]
	return track ~= nil and track.IsPlaying
end

local function clearTracks()
	for _, track in tracks do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(tracks)
end

local function onCharacterChanged(character: Model?)
	charMaid:Clean()
	clearTracks()
	animator = nil
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	rigType = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 5) :: Animator?
	if not animator then
		Log.Warn("Animator bulunamadı")
	end
	charMaid:Give(clearTracks)
end

function AnimationController:Init(allControllers)
	controllers = allControllers
end

function AnimationController:Start()
	controllers.CharacterController.CharacterChanged:Connect(onCharacterChanged)
	local current = controllers.CharacterController:GetCharacter()
	if current then
		task.spawn(onCharacterChanged, current)
	end
end

return AnimationController
