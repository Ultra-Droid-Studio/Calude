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
	-- ===== Sürüş kameraları (Aşama 3 — sürüş arayüzü) =====
	-- Araç modlarında Distance/ShoulderOffset.Y TABAN değerlerdir; CameraController bunları aracın boyutuna göre
	-- büyütür (framing): yükseklik ≥ tavan + RoofClearance, mesafe ≥ uzunluk × LengthFactor + DistancePad,
	-- en yakın mesafe ≥ uzunluk/2 + 3 (kamera kendi aracının içine giremez).
	--   FollowSharpness      yatay takip (hız ileri beslemeli → hızda geride kalma yok)
	--   VerticalSharpness    dikey takip (düşük = tümsekleri yutar)
	--   AutoFollowSharpness  bakış girişi yokken aracın arkasına dönme hızı (hızla artar)
	--   AutoPitch, PitchFollow  otomatik bakış açısı (derece) ve aracın yokuş eğiminin izlenme oranı
	--   RollFollow           motosiklet yatışının kameraya aktarılan oranı (otomobil 0)
	--   SpeedFovBoost        azami hızda eklenen görüş açısı (derece); SpeedDistanceBoost azami hızda eklenen mesafe
	Vehicle = {
		Distance = 11,
		MinDistance = 7,
		MaxDistance = 22,
		ShoulderOffset = Vector3.new(0, 2.4, 0),
		FieldOfView = 70,
		MinPitch = -50,
		MaxPitch = 35,
		FollowSharpness = 14,
		VerticalSharpness = 6,
		RotationSharpness = 14,
		CollisionRadius = 0.6,
		HideCharacter = false,
		SprintFovBoost = 0,
		RoofClearance = 1.4,
		LengthFactor = 0.7,
		DistancePad = 3,
		AutoFollowSharpness = 2.4,
		AutoPitch = -11,
		PitchFollow = 0.5,
		RollFollow = 0,
		SpeedFovBoost = 9,
		SpeedDistanceBoost = 3,
	},
	Motorcycle = {
		Distance = 8,
		MinDistance = 4.5,
		MaxDistance = 16,
		ShoulderOffset = Vector3.new(0, 2.2, 0),
		FieldOfView = 72,
		MinPitch = -50,
		MaxPitch = 35,
		FollowSharpness = 16,
		VerticalSharpness = 8,
		RotationSharpness = 16,
		CollisionRadius = 0.45,
		HideCharacter = false,
		SprintFovBoost = 0,
		RoofClearance = 0.8,
		LengthFactor = 0.8,
		DistancePad = 2.5,
		AutoFollowSharpness = 3,
		AutoPitch = -10,
		PitchFollow = 0.6,
		RollFollow = 0.3,
		SpeedFovBoost = 10,
		SpeedDistanceBoost = 2.5,
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
