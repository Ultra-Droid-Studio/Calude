-- VehicleDefinitions: tüm araç ve motosiklet modellerinin veri tanımı (Bölüm 8 / 9).
-- Yeni araç eklemek = buraya bir tablo eklemek. Fizik değerleri birim olarak:
--   uzunluk: stud, hız: stud/sn (≈ km/s göstergesi için x1), ivme: stud/sn², açı: derece, kütle: Roblox kütle birimi.
-- İsimler ve tasarımlar özgündür.

local VehicleDefinitions = {}

-- Tekerlek motoru yön işareti: Hinge ekseni aracın sağına (+X) bakar; ileri sürüş için açısal hız negatif.
-- Studio testinde araç geri gidiyorsa bunu 1 yapmak yeterli.
VehicleDefinitions.DriveSign = -1

local rgb = Color3.fromRGB

VehicleDefinitions.Catalog = {
	-- ======================= OTOMOBİLLER =======================
	compact_pico = {
		Type = "Car", Category = "Civilian", DisplayName = "Pico", Style = "compact",
		Width = 6.2, Length = 12, CabinHeight = 2.2, LowerHeight = 1.9,
		WheelRadius = 1.35, WheelWidth = 1.1, Wheelbase = 7.6, Track = 5.6, Clearance = 0.9, Travel = 1.2,
		Mass = 60, MaxSpeed = 95, ReverseSpeed = 25, Accel = 34, Brake = 72, MaxSteer = 34, MinSteer = 9, Grip = 1.25,
		Drive = "FWD",
		Seats = { { X = -1.3, Z = 0.6, Driver = true }, { X = 1.3, Z = 0.6 } },
		Colors = { rgb(236, 90, 70), rgb(90, 160, 220), rgb(250, 210, 80), rgb(240, 240, 236), rgb(110, 190, 120) },
	},
	sedan_vela = {
		Type = "Car", Category = "Sedan", DisplayName = "Vela", Style = "sedan",
		Width = 6.6, Length = 14, CabinHeight = 2.3, LowerHeight = 2.0,
		WheelRadius = 1.45, WheelWidth = 1.2, Wheelbase = 8.6, Track = 6.0, Clearance = 1.0, Travel = 1.2,
		Mass = 80, MaxSpeed = 110, ReverseSpeed = 28, Accel = 36, Brake = 76, MaxSteer = 32, MinSteer = 8, Grip = 1.3,
		Drive = "RWD",
		Seats = { { X = -1.4, Z = 0, Driver = true }, { X = 1.4, Z = 0 }, { X = -1.4, Z = 2.6 }, { X = 1.4, Z = 2.6 } },
		Colors = { rgb(40, 44, 52), rgb(230, 230, 226), rgb(150, 30, 40), rgb(70, 90, 130), rgb(160, 160, 164) },
	},
	sports_rayo = {
		Type = "Car", Category = "Sports", DisplayName = "Rayo GT", Style = "sports",
		Width = 6.8, Length = 14.4, CabinHeight = 1.8, LowerHeight = 1.6,
		WheelRadius = 1.5, WheelWidth = 1.4, Wheelbase = 8.8, Track = 6.2, Clearance = 0.7, Travel = 0.8,
		Mass = 75, MaxSpeed = 150, ReverseSpeed = 30, Accel = 56, Brake = 98, MaxSteer = 30, MinSteer = 6, Grip = 1.6,
		Drive = "AWD", Spoiler = true,
		Seats = { { X = -1.4, Z = 0.8, Driver = true }, { X = 1.4, Z = 0.8 } },
		Colors = { rgb(255, 122, 69), rgb(230, 30, 50), rgb(250, 220, 40), rgb(30, 30, 34), rgb(64, 196, 214) },
	},
	suv_terra = {
		Type = "Car", Category = "SUV", DisplayName = "Terra", Style = "suv",
		Width = 7.2, Length = 15, CabinHeight = 2.6, LowerHeight = 2.6,
		WheelRadius = 1.75, WheelWidth = 1.4, Wheelbase = 9.2, Track = 6.4, Clearance = 1.4, Travel = 1.6,
		Mass = 105, MaxSpeed = 105, ReverseSpeed = 26, Accel = 34, Brake = 70, MaxSteer = 32, MinSteer = 8, Grip = 1.35,
		Drive = "AWD", RoofRack = true,
		Seats = { { X = -1.5, Z = 0, Driver = true }, { X = 1.5, Z = 0 }, { X = -1.5, Z = 2.8 }, { X = 1.5, Z = 2.8 } },
		Colors = { rgb(60, 70, 60), rgb(240, 240, 236), rgb(30, 34, 40), rgb(140, 110, 80), rgb(90, 110, 140) },
	},
	pickup_mesa = {
		Type = "Car", Category = "Pickup", DisplayName = "Mesa", Style = "pickup",
		Width = 7.2, Length = 16.5, CabinHeight = 2.6, LowerHeight = 2.5,
		WheelRadius = 1.75, WheelWidth = 1.4, Wheelbase = 10.4, Track = 6.4, Clearance = 1.4, Travel = 1.6,
		Mass = 110, MaxSpeed = 100, ReverseSpeed = 26, Accel = 32, Brake = 68, MaxSteer = 32, MinSteer = 8, Grip = 1.3,
		Drive = "RWD",
		Seats = { { X = -1.5, Z = -2.2, Driver = true }, { X = 1.5, Z = -2.2 } },
		Colors = { rgb(180, 40, 40), rgb(230, 230, 226), rgb(40, 60, 90), rgb(120, 120, 124), rgb(200, 170, 110) },
	},
	van_porter = {
		Type = "Car", Category = "Van", DisplayName = "Porter", Style = "van",
		Width = 7.2, Length = 16, CabinHeight = 3.6, LowerHeight = 2.4,
		WheelRadius = 1.6, WheelWidth = 1.3, Wheelbase = 10, Track = 6.4, Clearance = 1.2, Travel = 1.4,
		Mass = 115, MaxSpeed = 90, ReverseSpeed = 24, Accel = 26, Brake = 62, MaxSteer = 33, MinSteer = 9, Grip = 1.25,
		Drive = "FWD",
		Seats = { { X = -1.5, Z = -4, Driver = true }, { X = 1.5, Z = -4 } },
		Colors = { rgb(240, 240, 236), rgb(220, 200, 90), rgb(90, 140, 190), rgb(70, 72, 76) },
	},
	utility_brisa = {
		Type = "Car", Category = "Utility", DisplayName = "Brisa Works", Style = "utility",
		Width = 7.2, Length = 17, CabinHeight = 2.6, LowerHeight = 2.5,
		WheelRadius = 1.75, WheelWidth = 1.4, Wheelbase = 10.8, Track = 6.4, Clearance = 1.4, Travel = 1.6,
		Mass = 120, MaxSpeed = 90, ReverseSpeed = 24, Accel = 27, Brake = 62, MaxSteer = 32, MinSteer = 9, Grip = 1.3,
		Drive = "RWD", LightBar = true,
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

-- Hıza bağlı direksiyon açısı (derece): düşük hızda tam açı, yüksek hızda dar açı
function VehicleDefinitions.SteerAngleAt(def, speed: number): number
	local t = math.clamp(math.abs(speed) / def.MaxSpeed, 0, 1)
	return def.MaxSteer + (def.MinSteer - def.MaxSteer) * t
end

-- Stud/sn → gösterge km/s (1 stud ≈ 0.28 m varsayımı)
function VehicleDefinitions.ToKmh(studsPerSecond: number): number
	return studsPerSecond * 0.28 * 3.6
end

return VehicleDefinitions
