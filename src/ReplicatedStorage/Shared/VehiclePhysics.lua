-- VehiclePhysics: otomobil fizik modelinin formülleri (Aşama 2). Saf hesap; Instance yaratmaz.
-- Sunucu (VehicleFactory: yay, balast, kaldırma kuvvetleri) ve istemci (CarPhysics: motor, fren, lastik)
-- AYNI formülleri buradan kullanır. tools/car_model.py bu dosyanın çevrimdışı aynasıdır.

local VehicleDefinitions = require(script.Parent.VehicleDefinitions)

local VehiclePhysics = {}

local C = VehicleDefinitions.CarPhysics
local MPS = VehicleDefinitions.MetersPerStud

VehiclePhysics.Constants = C

-- Bir otomobil tanımından türetilen sabitler (önbelleğe alınır; her araç için bir kez)
local cache: { [any]: any } = {}

function VehiclePhysics.Derive(def)
	local cached = cache[def]
	if cached then
		return cached
	end
	local p = def.Physics
	local g = C.EffectiveGravity
	local hz = def.Wheelbase / 2
	local wf = p.WeightFront
	local d = {}

	-- Süspansiyon (kütleye ORANSAL değerler; gerçek sertlik = oran × yaylı kütle)
	local omegaF = 2 * math.pi * p.SpringHzFront
	local omegaR = 2 * math.pi * p.SpringHzRear
	d.CornerFracFront = wf / 2
	d.CornerFracRear = (1 - wf) / 2
	d.SagFront = g / (omegaF * omegaF) -- statik çökme (stud)
	d.SagRear = g / (omegaR * omegaR)
	d.StiffnessPerMassFront = d.CornerFracFront * omegaF * omegaF
	d.StiffnessPerMassRear = d.CornerFracRear * omegaR * omegaR
	-- c = 2ζ√(k·m) = 2ζ·m_köşe·ω
	d.DampingPerMassFront = 2 * p.Damping * d.CornerFracFront * omegaF
	d.DampingPerMassRear = 2 * p.Damping * d.CornerFracRear * omegaR
	d.BumpRoom = C.BumpFraction * def.Travel -- sürüş yüksekliğinin üstündeki kurs
	d.DroopRoom = def.Travel - d.BumpRoom

	-- Ağırlık dağılımı: kütle merkezinin Z konumu (ön = -Z) ve balastın yeri
	local comZ = hz * (1 - 2 * wf)
	d.BallastZ = math.clamp(comZ / C.BallastFraction, -hz * 0.95, hz * 0.95)

	-- Motor: özgül güç (stud²/sn³), hız tavanı, sürtünme
	d.SpecificPower = p.PowerKW * 1000 / p.MassKg / (MPS * MPS)
	d.TopSpeed = def.MaxSpeed * 1.03
	d.RollingAccel = C.RollingResistance * g
	d.DragPerSpeed2 = math.max((d.SpecificPower / d.TopSpeed - d.RollingAccel) / (d.TopSpeed * d.TopSpeed), 0)
	d.LaunchAccel = p.LaunchG * g
	d.BrakeAccel = p.BrakeG * g
	d.HandbrakeAccel = p.HandbrakeG * g
	d.EngineBrakeAccel = C.EngineBrakeG * g
	d.ReverseAccel = C.ReverseG * g
	d.ReverseSpeed = def.ReverseSpeed * C.ReverseSpeed
	d.DownforcePerSpeed2 = p.DownforceAt100 * g / (100 * 100)
	d.GearTops = table.create(p.Gears)
	for i = 1, p.Gears do
		d.GearTops[i] = d.TopSpeed * (i / p.Gears) ^ C.GearSpread
	end

	-- Yanal sınır (direksiyon sınırı ve denge yardımı hedefi)
	d.LateralLimit = p.TireGrip * g * p.LatLimitScale

	cache[def] = d
	return d
end

-- Vites içindeki devir oranına (0..1) göre güç çarpanı: düşük devirde ~0.78, kırmızı çizgide 1.0
function VehiclePhysics.PowerFactor(rpmNorm: number): number
	local r = math.clamp(rpmNorm, 0.25, 1)
	return 0.55 + 0.9 * r - 0.45 * r * r
end

-- Tam gazda tekerlere ulaşan çekiş ivmesi (stud/sn²): kalkışta LaunchAccel, sonra güçle sınırlı
function VehiclePhysics.DriveAccel(d, speed: number, gear: number): number
	local top = d.GearTops[gear]
	local powerLimited = d.SpecificPower * VehiclePhysics.PowerFactor(speed / top) / math.max(speed, 1)
	return math.min(d.LaunchAccel, powerLimited)
end

-- Hıza bağlı azami direksiyon açısı (derece): yanal tutuş sınırını aşmayacak geometri + kayma payı
function VehiclePhysics.SteerLimit(def, d, speed: number): number
	local v = math.max(speed, 1)
	local geometric = math.deg(math.atan(def.Wheelbase * d.LateralLimit / (v * v)))
	return math.min(def.MaxSteer, geometric + def.Physics.SlipAllowanceDeg)
end

-- Zemin malzemesi → tutuş ve yuvarlanma direnci çarpanı
local SURFACE = {
	[Enum.Material.Asphalt] = { 1.0, 1.0 },
	[Enum.Material.Concrete] = { 0.97, 1.0 },
	[Enum.Material.Pavement] = { 0.95, 1.1 },
	[Enum.Material.Brick] = { 0.9, 1.2 },
	[Enum.Material.Cobblestone] = { 0.85, 1.5 },
	[Enum.Material.SmoothPlastic] = { 0.92, 1.0 },
	[Enum.Material.Plastic] = { 0.92, 1.0 },
	[Enum.Material.Metal] = { 0.8, 1.0 },
	[Enum.Material.DiamondPlate] = { 0.85, 1.1 },
	[Enum.Material.WoodPlanks] = { 0.85, 1.3 },
	[Enum.Material.Wood] = { 0.85, 1.3 },
	[Enum.Material.Marble] = { 0.8, 1.0 },
	[Enum.Material.Granite] = { 0.88, 1.1 },
	[Enum.Material.Slate] = { 0.86, 1.2 },
	[Enum.Material.Rock] = { 0.82, 1.6 },
	[Enum.Material.Basalt] = { 0.84, 1.5 },
	[Enum.Material.Grass] = { 0.62, 3.0 },
	[Enum.Material.LeafyGrass] = { 0.6, 3.2 },
	[Enum.Material.Ground] = { 0.6, 3.0 },
	[Enum.Material.Mud] = { 0.42, 5.0 },
	[Enum.Material.Sand] = { 0.5, 6.0 },
	[Enum.Material.Snow] = { 0.35, 4.0 },
	[Enum.Material.Ice] = { 0.15, 1.0 },
	[Enum.Material.Glacier] = { 0.2, 1.0 },
}
local DEFAULT_SURFACE = { 0.9, 1.2 }

function VehiclePhysics.Surface(material: Enum.Material?): ({ number })
	return material and SURFACE[material] or DEFAULT_SURFACE
end

-- Otomobilin yere oturduğunda şasi merkezinin zeminden yüksekliği (doğurma için)
function VehiclePhysics.CarRideHeight(def): number
	return 1 / 2 + def.Clearance
end

return VehiclePhysics
