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
		-- Aynı anda en fazla araç: cihaz sınıfı × Şehir yoğunluğu ayarı (Ayarlar → Grafik). Tablet = dokunmatik ve
		-- ekranın kısa kenarı ≥ 700 px; Mobile = telefon. Gerçek sayı ayrıca saat/bölge yoğunluğu ve kare süresine
		-- göre (uyarlanır kalite) azalır. Workspace.AmbientMaxVehicles bunların hepsini geçersiz kılar (test).
		MaxVehicles = {
			Desktop = { Low = 36, Normal = 64, High = 90 },
			Tablet = { Low = 22, Normal = 38, High = 50 },
			Mobile = { Low = 14, Normal = 26, High = 34 },
		},
		SpawnMin = 90, -- oyuncuya bundan yakın doğmaz (bu yakınlıkta sadece görünmeyen yerde: kamera arkası/bina arkası)
		SpawnMax = 420, -- bundan uzakta doğmaz
		SpawnVisibleMin = 300, -- kameranın gördüğü yerde bundan yakın doğmaz
		DespawnRadius = 480, -- bundan uzaklaşan araç GÖRÜNMÜYORSA havuza döner
		HardDespawnRadius = 680, -- görünse bile bundan uzaktaysa kaldırılır (ufukta küçük nokta)
		SpawnsPerTick = 2, -- hedefin %60'ının altındaysa 3 katı
		SpawnSpeedFactor = 0.75, -- doğan araç yol hızının bu oranıyla başlar (görünmeyen yerde doğar)
		DensityFloor = 0.2, -- bölge/saat yoğunluğu ne kadar düşerse düşsün en az bu oran
		NightFactor = 0.45, -- gece trafiği (gündüz = 1)
		-- Yol sınıfı ağırlığı: doğma olasılığı (şerit uzunluğu × ağırlık) ve dönüş tercihi. Caddeler yoğun, ara
		-- sokaklar seyrek. TurnClassBias: 0 = dönüşte sınıf önemsiz, 1 = tamamen sınıfa göre.
		ClassWeight = { avenue = 1, freeway = 0.8, highway = 0.8, ramp = 0.35, street = 0.2, country = 0.3 },
		TurnClassBias = 0.9,

		-- Sürücü modeli (Intelligent Driver Model). Yaşayan Şehir: daha çevik şehir sürüşü
		MaxAccel = 13, -- stud/sn²  (~3.6 m/s²)
		ComfortDecel = 14, -- stud/sn² (~3.9 m/s²)
		MaxDecel = 36, -- acil fren
		Jerk = 45, -- stud/sn³: ivme artışı sınırı (sarsıntısız kalkış; fren sınırsız)
		StartThreshold = 1.2, -- duran araç bundan küçük ivme için kıpırdamaz (dur-kalk titremesi yok)
		MinGap = 4.5, -- duruşta öndeki araçla mesafe
		Anticipation = 0.35, -- sn: öndeki kalkınca boşluğun açılacağını öngör (kuyruk hızlı çözülür)
		Headway = 1.0, -- sn: takip süresi
		SpeedFactor = { 0.92, 1.08 }, -- sürücüden sürücüye istenen hız / yol hız sınırı
		TurnLateralAccel = 12, -- virajda güvenli hız: v = √(a·r)
		LookAhead = 90, -- öndeki araç/engel arama mesafesi
		ApproachDistance = 30, -- kavşağa bu kadar kala geçiş izni istenir (ve fren mesafesi)
		StopSignWait = 0.6, -- dur levhasında tam duruş süresi
		YieldLookAhead = 45, -- sol dönüş / rampa: karşıdan gelen önceliklilere bakma mesafesi
		LaneChangeAfter = 1.5, -- sn engel arkasında bekleyince yan şeride geç (çok şeritli yolda)
		LaneChangeTime = 1.4,
		RerouteAfter = 4, -- sn çıkış dolu/engelli diye bekleyen araç kavşakta başka yöne döner
		BlockedDespawnAfter = 40, -- sn hiç ilerleyemeyen araç (oyuncudan uzak ve görünmüyorsa) kaldırılır
		LockedAfter = 25, -- sn kavşak izni olup ilerleyemeyen araç (kilit; uzak ve görünmüyorsa) kaldırılır
		IdleWatchdog = 75, -- sn hiç kıpırdamayan araç (uzak ve görünmüyorsa) kaldırılır: son güvenlik ağı
		ObstacleRadius = { Player = 2.5, Vehicle = 4.5, Pedestrian = 1.4 },

		-- Işık: ana yol (cadde/otoyol) fazı MainGreen, kesişen ara sokak SideGreen; eşit sınıfta Green.
		-- WaveSpeed > 0: ana yol boyunca "yeşil dalga" (bu hızla giden araç art arda yeşile denk gelir); 0 = rastgele.
		-- PedClearFactor: yaya, karşı trafiğe yeşil yanana kadar kalan süre geçiş süresinin bu katından uzunsa başlar.
		Signal = { Green = 14, MainGreen = 20, SideGreen = 11, Yellow = 3, AllRed = 1.5, WaveSpeed = 55, PedClearFactor = 0.7 },

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
		-- Bölge türüne göre araç karışımı (ağırlık çarpanı; yazılmayan = 1). Ticari: van_porter, utility_brisa.
		-- Taxi: sedan_vela'nın taksi görünüm olasılığı çarpanı (CarModelConfig.TrafficVariants).
		DistrictMix = {
			downtown = { sedan_vela = 1.4, compact_pico = 1.2, van_porter = 1.2, pickup_mesa = 0.4, utility_brisa = 0.8, Taxi = 2.2 },
			industrial = { van_porter = 2.5, utility_brisa = 2.5, pickup_mesa = 2, sedan_vela = 0.6, sports_rayo = 0.3, Taxi = 0.3 },
			residential = { suv_terra = 1.4, compact_pico = 1.3, van_porter = 0.6, utility_brisa = 0.5, Taxi = 0.5 },
			town = { pickup_mesa = 1.4, suv_terra = 1.2, Taxi = 0.5 },
			rural = { pickup_mesa = 3, suv_terra = 1.5, utility_brisa = 1.2, compact_pico = 0.6, sports_rayo = 0.4, Taxi = 0.1 },
			coastal = { sports_rayo = 2.2, suv_terra = 1.2, Taxi = 0.8 },
			resort = { sports_rayo = 2.5, suv_terra = 1.2, van_porter = 0.8, Taxi = 1.5 },
			airport = { van_porter = 1.6, Taxi = 3 },
		},
	},

	Pedestrians = {
		Enabled = true,
		-- cihaz sınıfı × Şehir yoğunluğu (Traffic.MaxVehicles ile aynı kurallar)
		MaxPedestrians = {
			Desktop = { Low = 45, Normal = 80, High = 110 },
			Tablet = { Low = 25, Normal = 45, High = 60 },
			Mobile = { Low = 18, Normal = 30, High = 40 },
		},
		SpawnMin = 45, -- bu yakınlıkta sadece görünmeyen yerde doğar
		SpawnMax = 190,
		SpawnVisibleMin = 140,
		DespawnRadius = 230, -- bundan uzaklaşan yaya GÖRÜNMÜYORSA kaldırılır
		HardDespawnRadius = 320, -- görünse bile bundan uzaktaysa kaldırılır
		FullUpdateRadius = 140, -- bundan uzaktaki (kaldırımdaki) yayada komşu/engel taraması yok (maliyet LOD)
		SpawnsPerTick = 2, -- hedefin %60'ının altındaysa 3 katı
		DensityFloor = 0.1,
		WalkSpeed = { 4.2, 5.8 }, -- stud/sn (~1.2–1.6 m/s)
		WalkAccel = 6, -- stud/sn²: kalkış (≈0.8 sn'de tam hız)
		WalkDecel = 8, -- stud/sn²: yavaşlama (geçit başında / hedefte yumuşak duruş)
		TurnRate = 6, -- rad/sn (~340°/sn): köşede ani dönme yerine kısa bir dönüş
		GoalMinDistance = 70, -- rastgele hedef en az bu kadar uzakta (olduğu yerde dönüp durma)
		CrossPenalty = 30, -- rota: gereksiz karşıya geçme cezası (stud eşdeğeri)
		CrossSpeedFactor = 1.15, -- karşıya geçerken biraz hızlanır
		SidewalkSpread = 2.6, -- kaldırım ortasından en fazla yanal kayma
		PersonalSpace = 2.2, -- yayalar arası en az mesafe
		PlayerAvoidRadius = 4,
		VehicleFleeRadius = 9, -- kaldırıma yaklaşan hızlı araçtan kaçma
		CrossGapRadius = 45, -- ışıksız geçitte bu mesafede araç varken geçme
		CrossWaitGiveUp = 25, -- sn: ışıksız geçitte bekleyip vazgeçme
		GoalRadius = 220, -- hedef seçimi yarıçapı
		-- Bina giriş/çıkış (Shared/Ambient/Entrances: kapı noktaları arsa verisinden; harita değişmez)
		Doors = {
			Enabled = true,
			PauseTime = { 0.5, 1.1 }, -- sn: kapıya dönüp bekleme (DoorApproach), kapı açılır
			EnterTime = 1.5, -- sn: eşikten geçip içeride kaybolma (EnterBuilding)
			ExitTime = 1.5, -- sn: içeriden belirip dışarı çıkma (ExitBuilding)
			Depth = 1.8, -- stud: kapı düzleminin içinde kaybolma/belirme noktası
			GoalMinDistance = 30, -- kapı hedefi en az bu kadar uzakta
			SpawnMinDistance = 15, -- oyuncunun dibindeki kapıdan doğma yok
			-- saat → Goal: yeni hedefin kapı olma olasılığı, Spawn: kapıdan çıkarak doğma olasılığı,
			-- Enter/Exit: kullanım ağırlıkları (Home ev, Work ofis/kule, Shop dükkân/AVM, Hotel otel)
			Schedule = {
				{ From = 0, To = 6, Goal = 0.6, Spawn = 0.2, Enter = { Home = 1, Hotel = 0.6, Shop = 0.05, Work = 0.1 }, Exit = { Home = 0.3, Work = 0.4, Shop = 0.1, Hotel = 0.3 } },
				{ From = 6, To = 9, Goal = 0.45, Spawn = 0.55, Enter = { Work = 1, Shop = 0.4, Home = 0.2, Hotel = 0.2 }, Exit = { Home = 1, Hotel = 0.5, Shop = 0.1, Work = 0.1 } }, -- işe gidiş
				{ From = 9, To = 17, Goal = 0.35, Spawn = 0.45, Enter = { Shop = 1, Work = 0.6, Home = 0.3, Hotel = 0.3 }, Exit = { Shop = 1, Work = 0.6, Home = 0.4, Hotel = 0.3 } },
				{ From = 17, To = 21, Goal = 0.45, Spawn = 0.45, Enter = { Home = 1, Shop = 0.6, Hotel = 0.5, Work = 0.1 }, Exit = { Work = 1, Shop = 0.6, Home = 0.3, Hotel = 0.3 } }, -- eve dönüş
				{ From = 21, To = 24, Goal = 0.6, Spawn = 0.25, Enter = { Home = 1, Hotel = 0.6, Shop = 0.2, Work = 0.05 }, Exit = { Shop = 0.4, Work = 0.3, Home = 0.2, Hotel = 0.3 } },
			},
		},
		AnimateRadius = 90, -- bu mesafeden uzakta uzuv animasyonu yok (ayakta duruş pozu)
		FullAnimateRadius = 45, -- bu mesafe içinde her kare animasyon; 45–90 arası iki karede bir
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
