-- Config: oyun genelindeki ayarlanabilir değerler.
-- Sadece veri içerir; hiçbir servis/kontrolcü burada durum tutmaz.

local Config = {}

Config.GameName = "SOLARA"
Config.Version = "0.3.0-phase3"

-- Oyun modu ayrımı: Sandbox ayrı bir Place olarak (aynı Universe içinde) çalışır.
-- Böylece veri ve yetkiler fiziksel olarak ayrılır (Bölüm 02 / 16).
Config.Modes = {
	Normal = "Normal",
	Sandbox = "Sandbox",
}
-- Sandbox place'in PlaceId'lerini buraya ekle (yayınladıktan sonra).
Config.SandboxPlaceIds = {} :: { number }

Config.Movement = {
	WalkSpeed = 8, -- yavaş yürüyüş (toggle)
	RunSpeed = 16, -- varsayılan koşu
	SprintSpeed = 25, -- basılı tutunca depar
	JumpPower = 50,
	-- Sunucu doğrulaması: izin verilen yatay hız = SprintSpeed * çarpan + tolerans
	ValidationSpeedMultiplier = 1.35,
	ValidationTolerance = 6,
}

Config.Spawn = {
	RespawnDelay = 4,
	-- Doğduktan sonra hareket doğrulamasının görmezden geldiği süre (sn)
	TeleportGraceSeconds = 3,
	FallbackPosition = Vector3.new(0, 12, 0),
}

Config.World = {
	-- Dünya inşası sırasında kaç parçada bir bekleme yapılacağı (sunucu donmasın)
	BuildYieldEvery = 350,
	-- Her N sokak lambasından birine gerçek ışık kaynağı (mobil performans için seyrek)
	LampLightEvery = 3,
	DefaultSpawnGroup = "Default",
}

Config.Environment = {
	DayLengthMinutes = 24, -- gerçek dakika cinsinden tam bir gün
	StartClockTime = 13.5,
	LampsOnAt = 18.25, -- saat
	LampsOffAt = 6.5,
}

Config.Debug = {
	-- Studio'da otomatik açılır; canlı sunucuda F3 ile açılır.
	ShowDebugHUDInStudio = true,
	VerboseLogging = true,
}

return table.freeze(Config)
