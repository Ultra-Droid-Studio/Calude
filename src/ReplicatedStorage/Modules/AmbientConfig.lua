-- AmbientConfig: trafik ve yaya yapay zekâsının TÜM ayarları ve sınırları (Aşama 6).
-- Saf Lua tablosu (Roblox türü yok): tools/test_ambient.py aynı dosyayı yükler.
-- Birimler: stud, saniye, stud/sn. 1 stud ≈ 0.28 m; hız değerleri ≈ km/s ile aynı ölçektedir.

return {
	Enabled = true,

	-- Simülasyon her oyuncunun KENDİ cihazında, oyuncunun çevresinde çalışır (ağ trafiği yok).
	-- Trafik ışıkları sunucu saatine bağlıdır: tüm oyuncular aynı ışığı görür.
	SimRate = 10, -- Hz: karar/fizik adımı; görüntü her karede ara değerlenir (interpolate)

	Traffic = {
		Enabled = true,
		MaxVehicles = { Desktop = 24, Mobile = 12 }, -- aynı anda en fazla araç (cihaz başına)
		SpawnMin = 150, -- oyuncuya bundan yakın doğmaz
		SpawnMax = 420, -- bundan uzakta doğmaz
		SpawnVisibleMin = 320, -- kameranın gördüğü yerde bundan yakın doğmaz
		DespawnRadius = 520, -- bundan uzaklaşan araç havuza döner
		SpawnsPerTick = 2,
		DensityFloor = 0.2, -- bölge/saat yoğunluğu ne kadar düşerse düşsün en az bu oran
		NightFactor = 0.45, -- gece trafiği (gündüz = 1)

		-- Sürücü modeli (Intelligent Driver Model)
		MaxAccel = 9, -- stud/sn²  (~2.5 m/s²)
		ComfortDecel = 11, -- stud/sn² (~3 m/s²)
		MaxDecel = 32, -- acil fren
		MinGap = 6, -- duruşta öndeki araçla mesafe
		Headway = 1.3, -- sn: takip süresi
		SpeedFactor = { 0.85, 1.05 }, -- sürücüden sürücüye istenen hız / yol hız sınırı
		TurnLateralAccel = 9, -- virajda güvenli hız: v = √(a·r)
		LookAhead = 90, -- öndeki araç/engel arama mesafesi
		ApproachDistance = 30, -- kavşağa bu kadar kala geçiş izni istenir (ve fren mesafesi)
		StopSignWait = 0.8, -- dur levhasında tam duruş süresi
		YieldLookAhead = 45, -- sol dönüş / rampa: karşıdan gelen önceliklilere bakma mesafesi
		LaneChangeAfter = 2.5, -- sn engel arkasında bekleyince yan şeride geç (çok şeritli yolda)
		LaneChangeTime = 1.6,
		BlockedDespawnAfter = 45, -- sn hiç ilerleyemeyen araç (oyuncudan uzaksa) kaldırılır
		ObstacleRadius = { Player = 2.5, Vehicle = 4.5, Pedestrian = 1.4 },

		Signal = { Green = 14, Yellow = 3, AllRed = 1.5 },

		-- Trafikte kullanılacak otomobil modelleri (VehicleDefinitions kimlikleri) ve sıklıkları
		Kinds = {
			{ Id = "sedan_vela", Weight = 5 },
			{ Id = "compact_pico", Weight = 4 },
			{ Id = "suv_terra", Weight = 3 },
			{ Id = "van_porter", Weight = 2 },
			{ Id = "pickup_mesa", Weight = 2 },
			{ Id = "utility_brisa", Weight = 1 },
			{ Id = "sports_rayo", Weight = 1 },
		},
	},

	Pedestrians = {
		Enabled = true,
		MaxPedestrians = { Desktop = 32, Mobile = 14 },
		SpawnMin = 45,
		SpawnMax = 190,
		SpawnVisibleMin = 140,
		DespawnRadius = 230,
		SpawnsPerTick = 2,
		DensityFloor = 0.1,
		WalkSpeed = { 4.2, 5.8 }, -- stud/sn (~1.2–1.6 m/s)
		CrossSpeedFactor = 1.15, -- karşıya geçerken biraz hızlanır
		SidewalkSpread = 2.6, -- kaldırım ortasından en fazla yanal kayma
		PersonalSpace = 2.2, -- yayalar arası en az mesafe
		PlayerAvoidRadius = 4,
		VehicleFleeRadius = 9, -- kaldırıma yaklaşan hızlı araçtan kaçma
		CrossGapRadius = 45, -- ışıksız geçitte bu mesafede araç varken geçme
		CrossWaitGiveUp = 25, -- sn: ışıksız geçitte bekleyip vazgeçme
		GoalRadius = 220, -- hedef seçimi yarıçapı
		AnimateRadius = 90, -- bu mesafeden uzakta uzuv animasyonu yok
		-- Gün içi davranış: saat → { yoğunluk, mola olasılığı, mola süresi aralığı }
		Schedule = {
			{ From = 0, To = 5, Density = 0.08, Idle = 0.05, IdleTime = { 3, 6 } },
			{ From = 5, To = 7, Density = 0.3, Idle = 0.1, IdleTime = { 3, 8 } },
			{ From = 7, To = 9, Density = 0.85, Idle = 0.15, IdleTime = { 3, 8 } }, -- sabah işe gidiş
			{ From = 9, To = 12, Density = 0.7, Idle = 0.45, IdleTime = { 8, 20 } }, -- işler, alışveriş
			{ From = 12, To = 14, Density = 1, Idle = 0.6, IdleTime = { 10, 25 } }, -- öğle
			{ From = 14, To = 17, Density = 0.75, Idle = 0.45, IdleTime = { 8, 20 } },
			{ From = 17, To = 20, Density = 0.95, Idle = 0.35, IdleTime = { 6, 18 } }, -- akşam
			{ From = 20, To = 23, Density = 0.45, Idle = 0.25, IdleTime = { 5, 12 } },
			{ From = 23, To = 24, Density = 0.15, Idle = 0.1, IdleTime = { 3, 6 } },
		},
	},

	Debug = {
		DrawRadius = 220, -- hata ayıklama çizimi bu yarıçapta
		RefreshInterval = 0.5,
	},
}
