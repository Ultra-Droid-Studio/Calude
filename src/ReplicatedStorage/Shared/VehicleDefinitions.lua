-- VehicleDefinitions: tüm araç ve motosiklet modellerinin veri tanımı (Bölüm 8 / 9).
-- Yeni araç eklemek = buraya bir tablo eklemek. Fizik değerleri birim olarak:
--   uzunluk: stud, hız: stud/sn (≈ km/s göstergesi için x1), ivme: stud/sn², açı: derece, kütle: Roblox kütle birimi.
-- İsimler ve tasarımlar özgündür.

local VehicleDefinitions = {}

-- Tekerlek motoru yön işareti: Hinge ekseni aracın sağına (+X) bakar; ileri sürüş için açısal hız negatif.
-- Studio testinde araç geri gidiyorsa bunu 1 yapmak yeterli.
VehicleDefinitions.DriveSign = -1

local rgb = Color3.fromRGB

-- ======================= OTOMOBİL FİZİK MODELİ (Aşama 2) =======================
-- Birim politikası: 1 stud = 0.28 m (HUD km/s göstergesiyle aynı). Karakterler Roblox'un 196.2 stud/sn²
-- yerçekimini kullanmaya devam eder; OTOMOBİLLER ise kendilerine uygulanan kaldırma kuvvetiyle
-- "EffectiveGravity" altında yaşar. Böylece yay frekansı, yük transferi, lastik tutuşu ve fren mesafesi
-- gerçek dünya değerleriyle aynı ölçekte tasarlanabilir. Motosikletler bu modelin DIŞINDADIR (eski fizik).
-- Ayrıntılı açıklama: docs/SOLARA_Phase2_CarPhysics.md
VehicleDefinitions.MetersPerStud = 0.28

VehicleDefinitions.CarPhysics = {
	-- Araçlara etkiyen yerçekimi (stud/sn²). Gerçek 1 g = 9.81 / 0.28 = 35.0 stud/sn².
	-- 42 = 1.2 g: biraz daha "tok" süspansiyon ve tutuş; atlamalar aşırı süzülmez.
	EffectiveGravity = 42,
	RollingResistance = 0.012, -- × g (asfalt). Zemin tablosu çarpar.
	MinSlipSpeed = 1.5, -- stud/sn: kalkışta tekerin zeminden hızlı dönebileceği en küçük fark
	AbsSlip = 0.10, -- ABS'in izin verdiği kayma oranı (tekerlek kilitlenmez → direksiyon çalışır)
	KineticGrip = 0.82, -- kayma başlayınca tutuş katsayısı (statik → kinetik)
	SlideEnterAngle = 9, -- derece: bu kayma açısından sonra teker "kayıyor" sayılır
	SlideExitAngle = 5, -- derece: altına inince tutuş geri gelir (histerezis)
	SlideEnterRatio = 0.22, -- boyuna kayma oranı (patinaj / kilit) eşiği
	SlideExitRatio = 0.10,
	LoadSensitivity = 0.12, -- yük arttıkça μ azalır (gerçek lastik davranışı; viraj dengesini yük transferine bağlar)
	AckermannFactor = 0.6, -- 0 = paralel teker, 1 = tam Ackermann
	BumpFraction = 0.6, -- süspansiyon kursunun sürüş yüksekliğinin ÜSTÜNDE kalan payı
	GearSpread = 0.7, -- vites üst hızları: üst × (i/N)^0.7 (alt vitesler kısa)
	BallastFraction = 0.35, -- şasi kütlesinin ağırlık dağılımı için kaydırılan kısmı
	HoldSpeed = 0.8, -- stud/sn: bunun altında gaz yoksa araç yerinde tutulur (yokuşta kaymaz)
	EngineBrakeG = 0.035, -- gaz kesilince motor freni
	ReverseSpeed = 0.9, -- tanımdaki ReverseSpeed çarpanı
	ReverseG = 0.28,
	ShiftCut = 0.2, -- vites değişimi sırasında kalan çekiş oranı
	SurfaceProbeInterval = 1, -- her karede bir teker; 4 tekerli araçta tekerlek başına ~15 Hz zemin okuması
}

-- Otomobil "Physics" alanları (her biri tek bir fiziksel anlam taşır; hepsi VehiclePhysics.Derive'da kullanılır):
--   MassKg, PowerKW      Güç/ağırlık oranı → güçle sınırlı ivme a = P / (m·v). Kütlenin Roblox değeri "Mass"tır;
--                        kg sadece oranı ifade eder. Azami hız SABİT KALIR (MaxSpeed): sürtünme katsayısı,
--                        motor gücü tam MaxSpeed×1.03'te tükenecek şekilde türetilir (hız tavanı doğal oluşur).
--   LaunchG              Kalkışta tekerlere verilen en büyük çekiş ivmesi (g). Düşük hızda gücü sınırlar.
--   Gears, ShiftTime     Sanal vites sayısı ve vites değişim süresi (sn). Değişimde çekiş ShiftCut'a düşer.
--   WeightFront          Ön aksa düşen statik ağırlık oranı. Balast parçasıyla gerçekten kütle merkezi kaydırılır.
--   CoGOffset            Balastın şasi tabanına göre yüksekliği (stud). Büyük → ağırlık merkezi yüksek → daha çok yatış.
--   TireGrip             Lastik sürtünme katsayısı μ (EffectiveGravity altında gerçek değerle aynı anlamda).
--   GripFront/GripRear   Aks başına μ çarpanı: viraj dengesinin (önden/arkadan kayma) ince ayarı.
--   SpringHzFront/Rear   Yay doğal frekansı (Hz). Sertlik k = m_köşe·(2πf)²; çökme = g/(2πf)².
--   Damping              Sönüm oranı ζ (0.3 yumuşak … 0.5 sıkı). Sönüm c = 2ζ·√(k·m_köşe).
--   BrakeG, BrakeBiasFront  Azami fren ivmesi (g) ve ön akstaki fren payı. ABS kilitlenmeyi önler.
--   HandbrakeG, HandbrakeGrip  El freni kuvveti (g, sadece arka) ve el freni çekiliyken arka μ çarpanı (drift).
--   TractionSlip         Çekiş kontrolünün izin verdiği patinaj oranı. KineticGrip eşiğini aşarsa güçle kayma olur.
--   DriveSplitFront      Çekişin ön aksa düşen payı (FWD 1, RWD 0, AWD arası).
--   ThrottleRise/Fall    Gaz pedalı tepki hızı (1/sn). Dijital klavye girişini yumuşatır.
--   SteerRateLow/High    Direksiyon dönüş hızı (1/sn) düşük/yüksek hızda. Ani direksiyon sıçramasını önler.
--   LatLimitScale        Hıza bağlı direksiyon sınırı: tam direksiyon ≈ yanal tutuş sınırı × bu değer.
--   SlipAllowanceDeg     Yüksek hızda sınırın üstüne eklenen pay (lastik kayma açısı).
--   CounterSteer         Arka kayarken (oyuncu direksiyonu bırakınca) kendiliğinden karşı direksiyon oranı.
--   StabilityGain        Savrulma (yaw) denge yardımı kazancı (1/sn). Spor araçta düşük = daha fazla serbestlik.
--   DownforceAt100       100 stud/sn'de yere basma kuvveti (g). Hızın karesiyle artar.
VehicleDefinitions.Catalog = {
	-- ======================= OTOMOBİLLER =======================
	compact_pico = {
		Type = "Car", Category = "Civilian", DisplayName = "Pico", Style = "compact",
		Width = 6.2, Length = 12, CabinHeight = 2.2, LowerHeight = 1.9,
		WheelRadius = 1.35, WheelWidth = 1.1, Wheelbase = 7.6, Track = 5.6, Clearance = 0.9, Travel = 1.2,
		Mass = 60, MaxSpeed = 95, ReverseSpeed = 25, Accel = 34, Brake = 72, MaxSteer = 34, MinSteer = 9, Grip = 1.25,
		Drive = "FWD",
		-- Hafif, çevik şehir aracı. Önde motor + önden çekiş → sınırda hafif önden kayma (güvenli).
		Physics = {
			MassKg = 1050, PowerKW = 70, LaunchG = 0.38, Gears = 4, ShiftTime = 0.22,
			WeightFront = 0.62, CoGOffset = 0, TireGrip = 0.95, GripFront = 1.0, GripRear = 1.02,
			SpringHzFront = 1.6, SpringHzRear = 1.75, Damping = 0.4,
			BrakeG = 0.95, BrakeBiasFront = 0.68, HandbrakeG = 0.6, HandbrakeGrip = 0.55,
			TractionSlip = 0.08, DriveSplitFront = 1,
			ThrottleRise = 4.5, ThrottleFall = 8, SteerRateLow = 5.5, SteerRateHigh = 2.6,
			LatLimitScale = 1.05, SlipAllowanceDeg = 3.5, CounterSteer = 0.35, StabilityGain = 6, DownforceAt100 = 0,
		},
		Seats = { { X = -1.3, Z = 0.6, Driver = true }, { X = 1.3, Z = 0.6 } },
		Colors = { rgb(236, 90, 70), rgb(90, 160, 220), rgb(250, 210, 80), rgb(240, 240, 236), rgb(110, 190, 120) },
	},
	sedan_vela = {
		Type = "Car", Category = "Sedan", DisplayName = "Vela", Style = "sedan",
		Width = 6.6, Length = 14, CabinHeight = 2.3, LowerHeight = 2.0,
		WheelRadius = 1.45, WheelWidth = 1.2, Wheelbase = 8.6, Track = 6.0, Clearance = 1.0, Travel = 1.2,
		Mass = 80, MaxSpeed = 110, ReverseSpeed = 28, Accel = 36, Brake = 76, MaxSteer = 32, MinSteer = 8, Grip = 1.3,
		Drive = "RWD",
		-- Dengeli, konforlu arkadan itişli sedan. Yumuşak süspansiyon, öngörülebilir sınır davranışı.
		Physics = {
			MassKg = 1450, PowerKW = 125, LaunchG = 0.45, Gears = 5, ShiftTime = 0.25,
			WeightFront = 0.54, CoGOffset = 0, TireGrip = 1.0, GripFront = 1.0, GripRear = 1.0,
			SpringHzFront = 1.35, SpringHzRear = 1.5, Damping = 0.38,
			BrakeG = 1.0, BrakeBiasFront = 0.64, HandbrakeG = 0.6, HandbrakeGrip = 0.5,
			TractionSlip = 0.1, DriveSplitFront = 0,
			ThrottleRise = 3.8, ThrottleFall = 7, SteerRateLow = 4.6, SteerRateHigh = 2.2,
			LatLimitScale = 1.05, SlipAllowanceDeg = 3, CounterSteer = 0.3, StabilityGain = 6, DownforceAt100 = 0,
		},
		Seats = { { X = -1.4, Z = 0, Driver = true }, { X = 1.4, Z = 0 }, { X = -1.4, Z = 2.6 }, { X = 1.4, Z = 2.6 } },
		Colors = { rgb(40, 44, 52), rgb(230, 230, 226), rgb(150, 30, 40), rgb(70, 90, 130), rgb(160, 160, 164) },
	},
	sports_rayo = {
		Type = "Car", Category = "Sports", DisplayName = "Rayo GT", Style = "sports",
		Width = 6.8, Length = 14.4, CabinHeight = 1.8, LowerHeight = 1.6,
		WheelRadius = 1.5, WheelWidth = 1.4, Wheelbase = 8.8, Track = 6.2, Clearance = 0.7, Travel = 0.8,
		Mass = 75, MaxSpeed = 150, ReverseSpeed = 30, Accel = 56, Brake = 98, MaxSteer = 30, MinSteer = 6, Grip = 1.6,
		Drive = "AWD", Spoiler = true,
		-- Sert, alçak, keskin GT. Arka ağırlıklı dört çeker; yüksek tutuş + hafif yere basma kuvveti.
		Physics = {
			MassKg = 1350, PowerKW = 270, LaunchG = 0.7, Gears = 6, ShiftTime = 0.1,
			WeightFront = 0.46, CoGOffset = -0.15, TireGrip = 1.2, GripFront = 1.0, GripRear = 1.0,
			SpringHzFront = 2.1, SpringHzRear = 2.3, Damping = 0.5,
			BrakeG = 1.2, BrakeBiasFront = 0.6, HandbrakeG = 0.7, HandbrakeGrip = 0.45,
			TractionSlip = 0.14, DriveSplitFront = 0.35,
			ThrottleRise = 7, ThrottleFall = 10, SteerRateLow = 6.5, SteerRateHigh = 3.0,
			LatLimitScale = 1.12, SlipAllowanceDeg = 4, CounterSteer = 0.25, StabilityGain = 3.5, DownforceAt100 = 0.12,
		},
		Seats = { { X = -1.4, Z = 0.8, Driver = true }, { X = 1.4, Z = 0.8 } },
		Colors = { rgb(255, 122, 69), rgb(230, 30, 50), rgb(250, 220, 40), rgb(30, 30, 34), rgb(64, 196, 214) },
	},
	suv_terra = {
		Type = "Car", Category = "SUV", DisplayName = "Terra", Style = "suv",
		Width = 7.2, Length = 15, CabinHeight = 2.6, LowerHeight = 2.6,
		WheelRadius = 1.75, WheelWidth = 1.4, Wheelbase = 9.2, Track = 6.4, Clearance = 1.4, Travel = 1.6,
		Mass = 105, MaxSpeed = 105, ReverseSpeed = 26, Accel = 34, Brake = 70, MaxSteer = 32, MinSteer = 8, Grip = 1.35,
		Drive = "AWD", RoofRack = true,
		-- Ağır, yüksek ağırlık merkezli SUV. Yumuşak, gövde yatar, uzun fren, sınırda belirgin önden kayma.
		Physics = {
			MassKg = 2050, PowerKW = 175, LaunchG = 0.45, Gears = 5, ShiftTime = 0.3,
			WeightFront = 0.55, CoGOffset = 0.45, TireGrip = 0.88, GripFront = 0.97, GripRear = 1.03,
			SpringHzFront = 1.2, SpringHzRear = 1.35, Damping = 0.36,
			BrakeG = 0.88, BrakeBiasFront = 0.66, HandbrakeG = 0.5, HandbrakeGrip = 0.6,
			TractionSlip = 0.08, DriveSplitFront = 0.45,
			ThrottleRise = 3.2, ThrottleFall = 6, SteerRateLow = 4.0, SteerRateHigh = 1.8,
			LatLimitScale = 0.98, SlipAllowanceDeg = 2.5, CounterSteer = 0.35, StabilityGain = 8, DownforceAt100 = 0,
		},
		Seats = { { X = -1.5, Z = 0, Driver = true }, { X = 1.5, Z = 0 }, { X = -1.5, Z = 2.8 }, { X = 1.5, Z = 2.8 } },
		Colors = { rgb(60, 70, 60), rgb(240, 240, 236), rgb(30, 34, 40), rgb(140, 110, 80), rgb(90, 110, 140) },
	},
	pickup_mesa = {
		Type = "Car", Category = "Pickup", DisplayName = "Mesa", Style = "pickup",
		Width = 7.2, Length = 16.5, CabinHeight = 2.6, LowerHeight = 2.5,
		WheelRadius = 1.75, WheelWidth = 1.4, Wheelbase = 10.4, Track = 6.4, Clearance = 1.4, Travel = 1.6,
		Mass = 110, MaxSpeed = 100, ReverseSpeed = 26, Accel = 32, Brake = 68, MaxSteer = 32, MinSteer = 8, Grip = 1.3,
		Drive = "RWD",
		-- Boş kasalı arkadan itişli pikap: hafif arka aks, sert arka yay → gazla arkası kolay kayar.
		Physics = {
			MassKg = 1950, PowerKW = 165, LaunchG = 0.42, Gears = 4, ShiftTime = 0.3,
			WeightFront = 0.58, CoGOffset = 0.3, TireGrip = 0.9, GripFront = 1.0, GripRear = 0.95,
			SpringHzFront = 1.3, SpringHzRear = 1.7, Damping = 0.33,
			BrakeG = 0.88, BrakeBiasFront = 0.7, HandbrakeG = 0.6, HandbrakeGrip = 0.5,
			TractionSlip = 0.22, DriveSplitFront = 0,
			ThrottleRise = 4.0, ThrottleFall = 7, SteerRateLow = 4.2, SteerRateHigh = 2.0,
			LatLimitScale = 1.0, SlipAllowanceDeg = 3, CounterSteer = 0.3, StabilityGain = 5, DownforceAt100 = 0,
		},
		Seats = { { X = -1.5, Z = -2.2, Driver = true }, { X = 1.5, Z = -2.2 } },
		Colors = { rgb(180, 40, 40), rgb(230, 230, 226), rgb(40, 60, 90), rgb(120, 120, 124), rgb(200, 170, 110) },
	},
	van_porter = {
		Type = "Car", Category = "Van", DisplayName = "Porter", Style = "van",
		Width = 7.2, Length = 16, CabinHeight = 3.6, LowerHeight = 2.4,
		WheelRadius = 1.6, WheelWidth = 1.3, Wheelbase = 10, Track = 6.4, Clearance = 1.2, Travel = 1.4,
		Mass = 115, MaxSpeed = 90, ReverseSpeed = 24, Accel = 26, Brake = 62, MaxSteer = 33, MinSteer = 9, Grip = 1.25,
		Drive = "FWD",
		-- Uzun, ağır, yüksek panelvan. Yavaş tepki, en uzun fren, rüzgâr direnci yüksek, güvenli önden çekiş.
		Physics = {
			MassKg = 2250, PowerKW = 105, LaunchG = 0.32, Gears = 4, ShiftTime = 0.35,
			WeightFront = 0.6, CoGOffset = 0.5, TireGrip = 0.85, GripFront = 0.98, GripRear = 1.03,
			SpringHzFront = 1.25, SpringHzRear = 1.5, Damping = 0.36,
			BrakeG = 0.82, BrakeBiasFront = 0.68, HandbrakeG = 0.45, HandbrakeGrip = 0.65,
			TractionSlip = 0.06, DriveSplitFront = 1,
			ThrottleRise = 2.6, ThrottleFall = 5, SteerRateLow = 3.6, SteerRateHigh = 1.6,
			LatLimitScale = 0.95, SlipAllowanceDeg = 2.5, CounterSteer = 0.35, StabilityGain = 9, DownforceAt100 = 0,
		},
		Seats = { { X = -1.5, Z = -4, Driver = true }, { X = 1.5, Z = -4 } },
		Colors = { rgb(240, 240, 236), rgb(220, 200, 90), rgb(90, 140, 190), rgb(70, 72, 76) },
	},
	utility_brisa = {
		Type = "Car", Category = "Utility", DisplayName = "Brisa Works", Style = "utility",
		Width = 7.2, Length = 17, CabinHeight = 2.6, LowerHeight = 2.5,
		WheelRadius = 1.75, WheelWidth = 1.4, Wheelbase = 10.8, Track = 6.4, Clearance = 1.4, Travel = 1.6,
		Mass = 120, MaxSpeed = 90, ReverseSpeed = 24, Accel = 27, Brake = 62, MaxSteer = 32, MinSteer = 9, Grip = 1.3,
		Drive = "RWD", LightBar = true,
		-- En ağır araç: düz kasalı hizmet aracı. Ağır ama dengeli; yavaş direksiyon, sakin arka.
		Physics = {
			MassKg = 2400, PowerKW = 140, LaunchG = 0.36, Gears = 4, ShiftTime = 0.35,
			WeightFront = 0.55, CoGOffset = 0.35, TireGrip = 0.88, GripFront = 1.0, GripRear = 1.0,
			SpringHzFront = 1.3, SpringHzRear = 1.6, Damping = 0.38,
			BrakeG = 0.85, BrakeBiasFront = 0.66, HandbrakeG = 0.45, HandbrakeGrip = 0.6,
			TractionSlip = 0.1, DriveSplitFront = 0,
			ThrottleRise = 2.8, ThrottleFall = 5, SteerRateLow = 3.5, SteerRateHigh = 1.6,
			LatLimitScale = 0.97, SlipAllowanceDeg = 2.5, CounterSteer = 0.3, StabilityGain = 8, DownforceAt100 = 0,
		},
		Seats = { { X = -1.5, Z = -2.6, Driver = true }, { X = 1.5, Z = -2.6 } },
		Colors = { rgb(250, 160, 40), rgb(240, 240, 236), rgb(60, 120, 80) },
	},

	-- ======================= MOTOSİKLETLER =======================
	bike_sport_veloz = {
		Type = "Motorcycle", Category = "Sport", DisplayName = "Veloz R", Style = "sport",
		Width = 1.6, Length = 7, WheelRadius = 1.25, WheelWidth = 0.7, Wheelbase = 5.4, Clearance = 0.6, Travel = 0.8,
		Mass = 26, MaxSpeed = 160, ReverseSpeed = 8, Accel = 60, Brake = 95, MaxSteer = 24, MinSteer = 4, Grip = 1.6,
		MaxLean = 40, Drive = "RWD",
		Seats = { { X = 0, Z = 0.4, Driver = true }, { X = 0, Z = 2 } },
		Colors = { rgb(230, 30, 50), rgb(255, 122, 69), rgb(30, 30, 34), rgb(64, 196, 214) },
	},
	bike_street_tango = {
		Type = "Motorcycle", Category = "Street", DisplayName = "Tango", Style = "street",
		Width = 1.6, Length = 6.8, WheelRadius = 1.2, WheelWidth = 0.7, Wheelbase = 5.2, Clearance = 0.6, Travel = 0.9,
		Mass = 24, MaxSpeed = 130, ReverseSpeed = 8, Accel = 48, Brake = 88, MaxSteer = 26, MinSteer = 5, Grip = 1.5,
		MaxLean = 35, Drive = "RWD",
		Seats = { { X = 0, Z = 0.3, Driver = true }, { X = 0, Z = 1.9 } },
		Colors = { rgb(40, 44, 52), rgb(90, 160, 220), rgb(240, 240, 236), rgb(110, 190, 120) },
	},
	bike_cruiser_dune = {
		Type = "Motorcycle", Category = "Cruiser", DisplayName = "Dune Cruiser", Style = "cruiser",
		Width = 2, Length = 7.6, WheelRadius = 1.3, WheelWidth = 0.9, Wheelbase = 6, Clearance = 0.5, Travel = 0.9,
		Mass = 30, MaxSpeed = 120, ReverseSpeed = 8, Accel = 40, Brake = 80, MaxSteer = 26, MinSteer = 5, Grip = 1.45,
		MaxLean = 28, Drive = "RWD",
		Seats = { { X = 0, Z = 0.8, Driver = true }, { X = 0, Z = 2.4 } },
		Colors = { rgb(20, 20, 24), rgb(120, 30, 40), rgb(200, 170, 110), rgb(60, 70, 60) },
	},
	scooter_zip = {
		Type = "Motorcycle", Category = "Scooter", DisplayName = "Zip", Style = "scooter",
		Width = 1.6, Length = 5.4, WheelRadius = 0.9, WheelWidth = 0.6, Wheelbase = 4.2, Clearance = 0.45, Travel = 0.7,
		Mass = 18, MaxSpeed = 75, ReverseSpeed = 6, Accel = 30, Brake = 70, MaxSteer = 30, MinSteer = 8, Grip = 1.35,
		MaxLean = 30, Drive = "RWD",
		Seats = { { X = 0, Z = 0.6, Driver = true } },
		Colors = { rgb(170, 220, 210), rgb(250, 210, 80), rgb(240, 160, 180), rgb(240, 240, 236) },
	},
	bike_standard_ruta = {
		Type = "Motorcycle", Category = "Standard", DisplayName = "Ruta", Style = "standard",
		Width = 1.7, Length = 6.9, WheelRadius = 1.25, WheelWidth = 0.75, Wheelbase = 5.2, Clearance = 0.6, Travel = 1,
		Mass = 25, MaxSpeed = 120, ReverseSpeed = 8, Accel = 44, Brake = 84, MaxSteer = 26, MinSteer = 5, Grip = 1.45,
		MaxLean = 33, Drive = "RWD",
		Seats = { { X = 0, Z = 0.4, Driver = true }, { X = 0, Z = 2 } },
		Colors = { rgb(60, 70, 60), rgb(140, 110, 80), rgb(40, 44, 52), rgb(150, 30, 40) },
	},
}

function VehicleDefinitions.Get(id: string)
	return VehicleDefinitions.Catalog[id]
end

function VehicleDefinitions.IsMotorcycle(def): boolean
	return def ~= nil and def.Type == "Motorcycle"
end

-- Aşama 2 otomobil fizik modelini kullanan araç mı? (Physics tablosu olan otomobiller)
function VehicleDefinitions.UsesCarPhysics(def): boolean
	return def ~= nil and def.Type == "Car" and def.Physics ~= nil
end

-- Hıza bağlı direksiyon açısı (derece): düşük hızda tam açı, yüksek hızda dar açı
function VehicleDefinitions.SteerAngleAt(def, speed: number): number
	local t = math.clamp(math.abs(speed) / def.MaxSpeed, 0, 1)
	return def.MaxSteer + (def.MinSteer - def.MaxSteer) * t
end

-- Stud/sn → gösterge km/s (1 stud ≈ 0.28 m varsayımı)
function VehicleDefinitions.ToKmh(studsPerSecond: number): number
	return studsPerSecond * VehicleDefinitions.MetersPerStud * 3.6
end

return VehicleDefinitions
