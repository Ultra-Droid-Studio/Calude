-- WeatherService: gün-gece döngüsü, temel atmosfer ve sokak lambaları (Bölüm 22).
-- Aşama 2 kapsamı: zaman akışı + aydınlatma + lambalar. Hava durumu (bulut/yağmur) Aşama 10-11'de
-- Sandbox ayarlarıyla birlikte eklenecek; API şimdiden hazır.
--
-- Zaman sunucuda tutulur ve Lighting.ClockTime ile tüm istemcilere çoğalır.
-- Workspace attribute'ları: "IsNight" (bool) — NPC programları (Aşama 4) bunu dinleyecek.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Signal = require(Shared.Utilities.Signal)
local Log = require(Shared.Utilities.Log).new("WeatherService")

local WeatherService = {
	Name = "WeatherService",
	Priority = 30,
	NightChanged = Signal.new(), -- (isNight)
}

local paused = false
local clockTime = Config.Environment.StartClockTime
local lampsOn: boolean? = nil
local lampJob = 0

local LAMP_ON_COLOR = Color3.fromRGB(255, 220, 160)
local LAMP_OFF_COLOR = Color3.fromRGB(170, 170, 160)

local function ensure(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	return obj
end

local function setupLighting()
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(64, 64, 74)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 140)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	Lighting.GeographicLatitude = 26 -- subtropik kıyı ışığı

	local atmosphere = ensure("Atmosphere", "SolaraAtmosphere", Lighting) :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(199, 212, 226)
	atmosphere.Decay = Color3.fromRGB(110, 116, 132)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 1.3

	local color = ensure("ColorCorrectionEffect", "SolaraColor", Lighting) :: ColorCorrectionEffect
	color.Saturation = 0.08
	color.Contrast = 0.05
	color.Brightness = 0.01

	local bloom = ensure("BloomEffect", "SolaraBloom", Lighting) :: BloomEffect
	bloom.Intensity = 0.5
	bloom.Size = 22
	bloom.Threshold = 1.8

	local rays = ensure("SunRaysEffect", "SolaraSunRays", Lighting) :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.6
end

local function isNightAt(t: number): boolean
	local env = Config.Environment
	return t >= env.LampsOnAt or t < env.LampsOffAt
end

-- Lambaları parça parça değiştir (binlerce lamba tek karede değişmesin)
local function applyLamps(on: boolean)
	lampJob += 1
	local job = lampJob
	task.spawn(function()
		local lamps = CollectionService:GetTagged("StreetLamp")
		for index, lamp in lamps do
			if job ~= lampJob then
				return -- daha yeni bir istek geldi
			end
			if lamp:IsA("BasePart") then
				lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				lamp.Color = if on then LAMP_ON_COLOR else LAMP_OFF_COLOR
				local light = lamp:FindFirstChildWhichIsA("Light")
				if light then
					light.Enabled = on
				end
			end
			if index % 250 == 0 then
				task.wait()
			end
		end
	end)
end

local function refreshNightState(force: boolean?)
	local night = isNightAt(clockTime)
	if force or night ~= lampsOn then
		lampsOn = night
		workspace:SetAttribute("IsNight", night)
		applyLamps(night)
		WeatherService.NightChanged:Fire(night)
	end
end

-- ===== Genel API (Sandbox / yönetici araçları kullanacak) =====
function WeatherService:GetClockTime(): number
	return clockTime
end

function WeatherService:SetClockTime(t: number)
	if type(t) ~= "number" or t ~= t then
		return
	end
	clockTime = t % 24
	Lighting.ClockTime = clockTime
	refreshNightState()
end

function WeatherService:SetPaused(value: boolean)
	paused = value == true
end

function WeatherService:IsNight(): boolean
	return lampsOn == true
end

function WeatherService:Init()
	setupLighting()
	Lighting.ClockTime = clockTime
end

function WeatherService:Start()
	refreshNightState(true)
	-- Yeni yüklenen lambalar da doğru durumda olsun (dünya arka planda inşa edilirken)
	CollectionService:GetInstanceAddedSignal("StreetLamp"):Connect(function(lamp)
		if lampsOn and lamp:IsA("BasePart") then
			lamp.Material = Enum.Material.Neon
			lamp.Color = LAMP_ON_COLOR
			local light = lamp:FindFirstChildWhichIsA("Light")
			if light then
				light.Enabled = true
			end
		end
	end)

	local hoursPerSecond = 24 / (Config.Environment.DayLengthMinutes * 60)
	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		if paused then
			return
		end
		clockTime = (clockTime + dt * hoursPerSecond) % 24
		accumulator += dt
		-- Saniyede bir çoğalt (her kare ağ trafiği yaratmasın)
		if accumulator >= 1 then
			accumulator = 0
			Lighting.ClockTime = clockTime
			refreshNightState()
		end
	end)
	Log.Info(string.format("Gün-gece döngüsü: %d dk/gün, başlangıç %.1f", Config.Environment.DayLengthMinutes, clockTime))
end

return WeatherService
