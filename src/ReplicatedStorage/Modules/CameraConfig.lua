-- CameraConfig: her kamera modunun profili (Bölüm 19).
-- Ana kamera ThirdPerson: yakın, omuz üstü, aşırı yüksek DEĞİL.
-- ShoulderOffset.Y, avatarın GÖZ yüksekliğine göre eklenir; böylece kısa/uzun avatarlarda tutarlı.

local CameraConfig = {}

CameraConfig.Profiles = {
	ThirdPerson = {
		Distance = 6.5,
		MinDistance = 3,
		MaxDistance = 11,
		ShoulderOffset = Vector3.new(1.6, 0.35, 0),
		FieldOfView = 70,
		MinPitch = -65,
		MaxPitch = 55,
		FollowSharpness = 22,
		RotationSharpness = 30,
		CollisionRadius = 0.35,
		HideCharacter = false,
		SprintFovBoost = 7,
	},
	-- Alternatif üçüncü şahıs: ortalanmış, biraz daha geride ve yüksekte (klasik takip)
	ThirdPersonAlt = {
		Distance = 9.5,
		MinDistance = 4,
		MaxDistance = 16,
		ShoulderOffset = Vector3.new(0, 1.1, 0),
		FieldOfView = 70,
		MinPitch = -70,
		MaxPitch = 60,
		FollowSharpness = 16,
		RotationSharpness = 26,
		CollisionRadius = 0.4,
		HideCharacter = false,
		SprintFovBoost = 6,
	},
	FirstPerson = {
		Distance = 0,
		MinDistance = 0,
		MaxDistance = 0,
		ShoulderOffset = Vector3.new(0, 0.1, 0),
		FieldOfView = 78,
		MinPitch = -80,
		MaxPitch = 80,
		FollowSharpness = 60,
		RotationSharpness = 45,
		CollisionRadius = 0.2,
		HideCharacter = true,
		SprintFovBoost = 5,
	},
	-- Araç profilleri Aşama 3'te araç kontrolcüsüyle birlikte ince ayarlanacak (GEÇİCİ değerler)
	Vehicle = {
		Distance = 12,
		MinDistance = 7,
		MaxDistance = 20,
		ShoulderOffset = Vector3.new(0, 2.6, 0),
		FieldOfView = 72,
		MinPitch = -50,
		MaxPitch = 40,
		FollowSharpness = 12,
		RotationSharpness = 18,
		CollisionRadius = 0.5,
		HideCharacter = false,
		SprintFovBoost = 0,
	},
	Motorcycle = {
		Distance = 8,
		MinDistance = 5,
		MaxDistance = 14,
		ShoulderOffset = Vector3.new(0, 1.8, 0),
		FieldOfView = 74,
		MinPitch = -50,
		MaxPitch = 40,
		FollowSharpness = 14,
		RotationSharpness = 20,
		CollisionRadius = 0.45,
		HideCharacter = false,
		SprintFovBoost = 0,
	},
}

CameraConfig.DefaultMode = "ThirdPerson"

-- Hassasiyet (radyan / piksel). SettingsController çarpanı bunlarla çarpılır.
CameraConfig.MouseSensitivity = 0.0035
CameraConfig.TouchSensitivity = 0.006
CameraConfig.GamepadSensitivity = 3.2 -- radyan / sn (tam itişte)
CameraConfig.GamepadDeadzone = 0.15

CameraConfig.ZoomStep = 1.25 -- fare tekerleği adımı (stud)
CameraConfig.PinchZoomFactor = 0.04

-- Kameranın kafaya bu kadar yaklaşması durumunda karakter yarı saydamlaşır
CameraConfig.CharacterFadeDistance = 1.6

-- Kamera hatası güvenlik ağı: art arda bu kadar karede hata olursa varsayılan kameraya dön
CameraConfig.MaxConsecutiveErrors = 3

return CameraConfig
