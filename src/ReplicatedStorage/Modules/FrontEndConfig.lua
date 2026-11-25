-- FrontEndConfig: ana menü / ön yüz ayarları (Aşama 1).
-- Hem sunucu (akış odağı, doğma bekleme süreleri) hem istemci (menü kamerası, zaman aşımları) okur.
-- Sadece veri içerir.

local FrontEndConfig = {}

-- ===== Menü kamerası: şehir merkezinin kulelerine bakan yavaş hava çekimi =====
-- Konumlar MapData'dan seçildi: kuleler (184–324 stud) orijin çevresinde (±220) kümelenir,
-- varsayılan doğma meydanı (80, -80) ve deniz x≈1446'dan itibaren başlar.
FrontEndConfig.MenuShot = {
	Target = Vector3.new(0, 150, 0), -- kameranın baktığı nokta (kule kümesi)
	Pivot = Vector3.new(0, 0, 0), -- yörünge merkezi (yatay)
	Radius = 760,
	Height = 230,
	StartAngle = 200, -- derece (+X ekseninden, XZ düzleminde)
	EndAngle = 250,
	Period = 70, -- sn: bir uçtan diğerine (sonra geri döner)
	FieldOfView = 58,
}

-- Menü yeniden açıldığında (oyun içi): oyuncunun etrafında yavaş dönen çekim
FrontEndConfig.PauseShot = {
	Radius = 24,
	Height = 9,
	LookHeight = 2,
	DegreesPerSecond = 5,
	FieldOfView = 62,
	CollisionRadius = 0.8,
}

-- Oyuncu henüz doğmamışken içerik bu noktanın çevresinde akar (StreamingEnabled).
-- Hem menü çekimine (≈500 stud) hem doğma meydanına (≈400 stud) yakın seçildi.
FrontEndConfig.StreamFocus = Vector3.new(-270, 20, -270)
FrontEndConfig.StreamRequestTimeout = 12 -- sn (istemci RequestStreamAroundAsync)
-- Menü arka planındaki uzak şehir için EK akış odakları (sunucu: Player:AddReplicationFocus).
-- Tek odak (1024 stud) menü kamerasının gördüğü binaların ~%30'unu yüklüyordu (uzak kısım hiç gelmiyordu).
-- Bu iki nokta ile ~%76'sı (ekranda kapladıkları alanın ~%97'si) yüklenir. Sadece menüdeyken etkindir;
-- oyuncu doğarken kaldırılır. Hesap: harita verisi + MenuShot görüş alanı (Hata düzeltme 2 dokümanı).
FrontEndConfig.MenuExtraStreamFoci = {
	Vector3.new(1900, 20, 0),
	Vector3.new(400, 20, 1200),
}

-- Şehir menü arka planında "hazır" sayılmadan önce yedek arka plan gösterilir.
FrontEndConfig.CityProbeInterval = 1 -- sn
FrontEndConfig.BackdropFadeTime = 0.9

-- ===== Doğma =====
FrontEndConfig.ServerWorldWait = 30 -- sn: sunucu, dünya tam hazır olsun diye en fazla bu kadar bekler
FrontEndConfig.ServerGroundWait = 15 -- sn: sonra en az zemin adımının bitmesini bu kadar daha bekler
FrontEndConfig.MinWorldProgress = 0.25 -- WorldBuilder adım 2/8 (doğma noktaları + zemin/bloklar) tamam
FrontEndConfig.ClientSpawnTimeout = 60 -- sn: istemci bu sürede karakter alamazsa hata gösterir
FrontEndConfig.ClientCharacterReadyTimeout = 8 -- sn: karakter geldikten sonra sunucunun konumlamasını bekleme

-- ===== Arayüz =====
FrontEndConfig.DisplayOrder = 50 -- araç HUD'u (6) ve mobil kontrollerin (5) üstünde, DebugHUD'un (100) altında
FrontEndConfig.NavRepeatDelay = 0.35 -- sn: yön tuşu basılı tutulunca tekrar başlama gecikmesi
FrontEndConfig.NavRepeatRate = 0.09 -- sn
FrontEndConfig.StickThreshold = 0.6

return table.freeze(FrontEndConfig)
