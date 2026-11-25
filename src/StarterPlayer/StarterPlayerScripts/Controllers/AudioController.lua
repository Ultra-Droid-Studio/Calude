-- AudioController: istemci tarafı ses yönetimi (Bölüm 23).
-- Aşama 3: yakındaki araçların motor sesi perdesi hıza göre ayarlanır (yerel; ağ trafiği yok).
-- Ses kaynakları AudioConfig'tedir; ID verilmemişse araçlarda Sound nesnesi olmaz ve bu döngü boşa çalışmaz.
--
-- Aşama 1 (ana menü): yerel ses mikseri.
--   SoundService/SolaraMaster (SoundGroup)
--     ├─ SolaraVehicles   (araç motoru, korna)
--     ├─ SolaraWorld      (ileride: ortam, NPC, hava)
--     └─ SolaraInterface  (menü sesleri)
--   Hacimler SettingsController'daki MasterVolume / VehicleVolume / WorldVolume / InterfaceVolume ayarlarından gelir.
--   Gruplar istemcide oluşturulur (yerel), diğer oyuncuları etkilemez.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Modules.AudioConfig)
local VehicleDefinitions = require(Shared.VehicleDefinitions)

local AudioController = {
	Name = "AudioController",
	Priority = 10,
}

local HEAR_DISTANCE = 160

local controllers
local groups: { [string]: SoundGroup } = {}
local interfaceSounds: { [string]: Sound } = {}

local GROUP_SETTINGS = {
	Master = "MasterVolume",
	Vehicles = "VehicleVolume",
	World = "WorldVolume",
	Interface = "InterfaceVolume",
}

local function ensureGroup(name: string, parent: Instance): SoundGroup
	local fullName = "Solara" .. name
	local existing = parent:FindFirstChild(fullName)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local group = Instance.new("SoundGroup")
	group.Name = fullName
	group.Parent = parent
	return group
end

local function applyVolumes()
	local settings = controllers.SettingsController
	for name, key in GROUP_SETTINGS do
		local group = groups[name]
		local value = settings:Get(key)
		if group and type(value) == "number" then
			group.Volume = value
		end
	end
end

-- Araç seslerini (sunucuda yaratılır) yerelde Vehicles grubuna bağla → hacim ayarı etkili olur
local function routeVehicleSound(sound: Instance?)
	if sound and sound:IsA("Sound") and sound.SoundGroup ~= groups.Vehicles then
		sound.SoundGroup = groups.Vehicles
	end
end

function AudioController:GetGroup(name: string): SoundGroup?
	return groups[name]
end

-- Arayüz sesi çal ("Move" | "Select" | "Back"). ID yoksa sessizce hiçbir şey yapmaz.
function AudioController:PlayInterface(kind: string)
	local id = AudioConfig.Resolve(AudioConfig.Interface[kind])
	if not id then
		return
	end
	local sound = interfaceSounds[kind]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "UI_" .. kind
		sound.SoundId = id
		sound.Volume = AudioConfig.Interface.Volume
		sound.SoundGroup = groups.Interface
		sound.Parent = SoundService
		interfaceSounds[kind] = sound
	end
	sound.TimePosition = 0
	sound:Play()
end

function AudioController:Init(allControllers)
	controllers = allControllers
end

function AudioController:Start()
	groups.Master = ensureGroup("Master", SoundService)
	for _, name in { "Vehicles", "World", "Interface" } do
		groups[name] = ensureGroup(name, groups.Master)
	end
	applyVolumes()
	controllers.SettingsController.Changed:Connect(function(key)
		for _, settingKey in GROUP_SETTINGS do
			if settingKey == key then
				applyVolumes()
				return
			end
		end
	end)

	local cfg = AudioConfig.Vehicle
	task.spawn(function()
		while true do
			task.wait(0.15)
			local camera = workspace.CurrentCamera
			if not camera then
				continue
			end
			local listener = camera.CFrame.Position
			for _, model in CollectionService:GetTagged("Vehicle") do
				local chassis = model.PrimaryPart
				local engine = chassis and chassis:FindFirstChild("Engine")
				if chassis and (chassis.Position - listener).Magnitude < HEAR_DISTANCE then
					routeVehicleSound(engine)
					routeVehicleSound(chassis:FindFirstChild("Horn"))
				end
				if engine and engine:IsA("Sound") and engine.IsPlaying and (chassis.Position - listener).Magnitude < HEAR_DISTANCE then
					local def = VehicleDefinitions.Get(model:GetAttribute("DefId"))
					local maxSpeed = if def then def.MaxSpeed else 100
					local t = math.clamp(chassis.AssemblyLinearVelocity.Magnitude / maxSpeed, 0, 1)
					engine.PlaybackSpeed = cfg.EngineBasePitch + (cfg.EngineMaxPitch - cfg.EngineBasePitch) * t
				end
			end
		end
	end)
end

return AudioController
