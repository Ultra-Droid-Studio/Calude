-- VehicleFactory: VehicleDefinitions'tan fiziksel olarak sürülebilir araç modeli üretir (Bölüm 8 / 9).
--
-- Fizik yapısı (her tekerlek için):
--   Chassis ──CylindricalConstraint (dikey kayma = süspansiyon, dikey eksende dönme = direksiyon servo)──► Knuckle
--   Chassis ──SpringConstraint (yay + amortisör)──► Knuckle
--   Knuckle ──HingeConstraint (Motor: tork/fren)──► Wheel
-- Görsel gövde parçaları şasiye kaynaklı ve kütlesizdir → ağırlık merkezi alçak şasidedir.
-- Motosiklette ek olarak AlignOrientation (PrimaryAxisParallel) dik durmayı ve virajda yatışı sağlar.
--
-- Model attribute'ları istemci sürüş kontrolcüsüne gereken her şeyi taşır (tork, fren, yarıçap...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local VehicleDefinitions = require(ReplicatedStorage.Shared.VehicleDefinitions)
local VehiclePhysics = require(ReplicatedStorage.Shared.VehiclePhysics)
local CarModelKit = require(ReplicatedStorage.Shared.CarModelKit)
local AudioConfig = require(ReplicatedStorage.Modules.AudioConfig)

local VehicleFactory = {}

VehicleFactory.BodyGroup = "VehicleBody"
VehicleFactory.WheelGroup = "VehicleWheels"

local M = Enum.Material

-- Teker titremesi düzeltmesi (Hata düzeltme 3):
--   * Mafsal (şasi ↔ teker arasındaki ara parça) eskiden 0.6³ varsayılan yoğunlukta, kütlesi 0.15 idi: teker
--     20–80, şasi 120–520 kat ağırdı. Bu kütle farkı kısıt çözücüsünü titretiyor, tekerler kendi kendine
--     sağa sola oynuyordu. Mafsal artık tekerin bu oranında (göbek + fren grubu gibi).
--   * Direksiyon servosu eskiden "toplam ağırlık × 40" tork kullanıyordu; artık tekeri köşe yükü altında
--     durağanken çevirmeye yetecek tork × pay.
local KNUCKLE_MASS_RATIO = 0.4
local STEER_SERVO_MARGIN = 4

local function steerServoTorque(totalMass: number, gravity: number, wheelCount: number, mu: number, radius: number): number
	return totalMass * gravity / math.max(wheelCount, 1) * mu * radius * STEER_SERVO_MARGIN
end
local rgb = Color3.fromRGB
local DARK = rgb(34, 36, 40)
local GLASS = rgb(40, 56, 70)
local CHROME = rgb(196, 198, 202)
local LIGHT_OFF = rgb(220, 220, 210)
local TAIL_OFF = rgb(120, 20, 24)
local AMBER = rgb(255, 150, 30)

type Ctx = {
	Model: Model, Chassis: Part, Def: any, Color: Color3, Rng: Random,
	yW: number, yTop: number, Physical: { BasePart },
	Derived: any?, -- Aşama 2 otomobil fizik modeli (motosiklette nil → eski geometri)
	SeatDrop: number?, -- dış 3D modelde koltuk/direksiyon ne kadar alçaltıldı (başın tavandan çıkmaması için)
}

local function attachment(parent: Instance, name: string, position: Vector3, axis: Vector3?, secondary: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	if axis then
		a.Axis = axis
	end
	if secondary then
		a.SecondaryAxis = secondary
	end
	a.Parent = parent
	return a
end

-- Kütlesiz görsel parça; `weldTo` (varsayılan şasi) parçasına kaynaklanır
local function vis(ctx: Ctx, name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material?, opts: { [string]: any }?): BasePart
	local o = opts or {}
	local part: BasePart
	if o.Shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		if o.Shape == "Cylinder" then
			(part :: Part).Shape = Enum.PartType.Cylinder
		elseif o.Shape == "Ball" then
			(part :: Part).Shape = Enum.PartType.Ball
		end
	end
	part.Name = name
	part.Size = size
	local base = (o.WeldTo or ctx.Chassis) :: BasePart
	part.CFrame = base.CFrame * localCF
	part.Color = color
	part.Material = material or M.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Massless = true
	part.Anchored = false
	part.CanCollide = o.Collide == true
	part.CanTouch = false
	part.CastShadow = o.Shadow ~= false
	part.Transparency = o.Transparency or 0
	part.Reflectance = o.Reflectance or 0
	part.CollisionGroup = VehicleFactory.BodyGroup
	part.Parent = ctx.Model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = base
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function cylCF(x: number, y: number, z: number, axis: string): CFrame
	-- Silindirin ekseni varsayılan X; "Z" veya "Y" yönüne çevir
	if axis == "Z" then
		return CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0)
	elseif axis == "Y" then
		return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
	end
	return CFrame.new(x, y, z)
end

local function addLight(ctx: Ctx, part: BasePart, range: number, angle: number)
	local light = Instance.new("SpotLight")
	light.Name = "Beam"
	light.Face = Enum.NormalId.Front
	light.Range = range
	light.Angle = angle
	light.Brightness = 3
	light.Color = rgb(255, 244, 220)
	light.Shadows = false
	light.Enabled = false
	light.Parent = part
	local _ = ctx
end

-- ===================== ARABA GÖVDELERİ =====================
local function carCommon(ctx: Ctx, cabZ: number, cabL: number, cabW: number?)
	local d = ctx.Def
	local W, L = d.Width, d.Length
	local yB = ctx.yW - 0.1
	local yT = yB + d.LowerHeight
	ctx.yTop = yT
	-- alt gövde (oyuncuların üstüne çıkabileceği, çarpışan kabuk)
	vis(ctx, "Body", Vector3.new(W, d.LowerHeight, L), CFrame.new(0, yB + d.LowerHeight / 2, 0), ctx.Color, M.SmoothPlastic, { Collide = true, Reflectance = 0.05 })
	-- kabin (camlı çekirdek + tavan + ön/arka cam kamaları)
	local cw = cabW or (W - 0.8)
	local ch = d.CabinHeight
	vis(ctx, "Cabin", Vector3.new(cw, ch, cabL), CFrame.new(0, yT + ch / 2, cabZ), GLASS, M.Glass, { Collide = true, Transparency = 0.25 })
	vis(ctx, "Roof", Vector3.new(cw + 0.2, 0.3, cabL - 0.6), CFrame.new(0, yT + ch + 0.15, cabZ), ctx.Color, M.SmoothPlastic)
	vis(ctx, "Windshield", Vector3.new(cw, ch, 2), CFrame.new(0, yT + ch / 2, cabZ - cabL / 2 - 1), GLASS, M.Glass, { Shape = "Wedge", Transparency = 0.25, Shadow = false })
	vis(ctx, "RearWindow", Vector3.new(cw, ch, 1.6), CFrame.new(0, yT + ch / 2, cabZ + cabL / 2 + 0.8) * CFrame.Angles(0, math.pi, 0), GLASS, M.Glass, { Shape = "Wedge", Transparency = 0.25, Shadow = false })
	-- tamponlar, ızgara
	vis(ctx, "BumperF", Vector3.new(W + 0.1, 0.7, 0.5), CFrame.new(0, yB + 0.35, -L / 2 - 0.2), DARK, M.SmoothPlastic, { Shadow = false })
	vis(ctx, "BumperR", Vector3.new(W + 0.1, 0.7, 0.5), CFrame.new(0, yB + 0.35, L / 2 + 0.2), DARK, M.SmoothPlastic, { Shadow = false })
	vis(ctx, "Grille", Vector3.new(W * 0.45, 0.6, 0.2), CFrame.new(0, yB + 1.1, -L / 2 - 0.05), DARK, M.Metal, { Shadow = false })
	-- farlar, stoplar, sinyaller
	for _, sx in { -1, 1 } do
		local hl = vis(ctx, "Headlight", Vector3.new(1.3, 0.5, 0.2), CFrame.new(sx * (W / 2 - 1), yB + 1.3, -L / 2 - 0.05), LIGHT_OFF, M.SmoothPlastic, { Shadow = false })
		addLight(ctx, hl, 70, 60)
		vis(ctx, "TailLight", Vector3.new(1.3, 0.5, 0.2), CFrame.new(sx * (W / 2 - 1), yB + 1.3, L / 2 + 0.05), TAIL_OFF, M.SmoothPlastic, { Shadow = false })
		vis(ctx, "ReverseLight", Vector3.new(0.5, 0.35, 0.2), CFrame.new(sx * (W / 2 - 2.1), yB + 1.3, L / 2 + 0.05), LIGHT_OFF, M.SmoothPlastic, { Shadow = false })
		local name = if sx < 0 then "IndicatorL" else "IndicatorR"
		vis(ctx, name, Vector3.new(0.5, 0.35, 0.2), CFrame.new(sx * (W / 2 - 0.2), yB + 1.3, -L / 2 - 0.06), AMBER, M.SmoothPlastic, { Shadow = false })
		vis(ctx, name, Vector3.new(0.5, 0.35, 0.2), CFrame.new(sx * (W / 2 - 0.2), yB + 1.3, L / 2 + 0.06), AMBER, M.SmoothPlastic, { Shadow = false })
		vis(ctx, "Mirror", Vector3.new(0.6, 0.4, 0.3), CFrame.new(sx * (cw / 2 + 0.35), yT + 0.4, cabZ - cabL / 2), ctx.Color, M.SmoothPlastic, { Shadow = false })
	end
	-- plaka
	local plate = vis(ctx, "Plate", Vector3.new(1.8, 0.6, 0.1), CFrame.new(0, yB + 0.9, L / 2 + 0.46), rgb(245, 245, 240), M.SmoothPlastic, { Shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(180, 60)
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
	label.TextColor3 = rgb(30, 60, 120)
	label.Text = string.format("SC %03d", ctx.Rng:NextInteger(100, 999))
	label.Parent = gui
	gui.Parent = plate
	return yT
end

local CarStyles = {}

function CarStyles.compact(ctx: Ctx)
	carCommon(ctx, 0.6, 5.4)
end

function CarStyles.sedan(ctx: Ctx)
	carCommon(ctx, 1.0, 6.4)
	-- bagaj kapağı çizgisi
	vis(ctx, "TrunkLine", Vector3.new(ctx.Def.Width + 0.02, 0.1, 0.1), CFrame.new(0, ctx.yTop - 0.05, ctx.Def.Length / 2 - 2.6), DARK, M.SmoothPlastic, { Shadow = false })
end

function CarStyles.sports(ctx: Ctx)
	local d = ctx.Def
	carCommon(ctx, 1.2, 5.0, d.Width - 1.2)
	-- kaput hava girişi ve rüzgarlık
	vis(ctx, "HoodScoop", Vector3.new(1.6, 0.3, 2), CFrame.new(0, ctx.yTop + 0.15, -d.Length / 2 + 3), DARK, M.SmoothPlastic, { Shadow = false })
	if d.Spoiler then
		vis(ctx, "SpoilerWing", Vector3.new(d.Width - 0.4, 0.2, 1.4), CFrame.new(0, ctx.yTop + 1.1, d.Length / 2 - 0.8), DARK, M.SmoothPlastic)
		for _, sx in { -1, 1 } do
			vis(ctx, "SpoilerPost", Vector3.new(0.2, 1, 0.4), CFrame.new(sx * (d.Width / 2 - 1.2), ctx.yTop + 0.5, d.Length / 2 - 0.8), DARK, M.SmoothPlastic, { Shadow = false })
		end
	end
	-- yan şerit
	vis(ctx, "Stripe", Vector3.new(0.8, 0.05, d.Length * 0.9), CFrame.new(0, ctx.yTop + 0.03, 0), rgb(250, 250, 250), M.SmoothPlastic, { Shadow = false })
end

function CarStyles.suv(ctx: Ctx)
	local d = ctx.Def
	carCommon(ctx, 1.4, 8.4)
	if d.RoofRack then
		local top = ctx.yTop + d.CabinHeight + 0.3
		for _, sx in { -1, 1 } do
			vis(ctx, "RackRail", Vector3.new(0.2, 0.3, 7), CFrame.new(sx * (d.Width / 2 - 1), top + 0.15, 1.4), DARK, M.Metal, { Shadow = false })
		end
	end
	vis(ctx, "SpareWheel", Vector3.new(0.8, 2.6, 2.6), cylCF(0, ctx.yTop - 0.6, d.Length / 2 + 0.6, "Z"), DARK, M.SmoothPlastic)
end

function CarStyles.pickup(ctx: Ctx)
	local d = ctx.Def
	carCommon(ctx, -2.0, 5.2)
	-- kasa: yan duvarlar + arka kapak
	local bedL = d.Length / 2 - 0.5
	local bedZ = d.Length / 2 - bedL / 2 - 0.2
	for _, sx in { -1, 1 } do
		vis(ctx, "BedSide", Vector3.new(0.3, 1.4, bedL), CFrame.new(sx * (d.Width / 2 - 0.15), ctx.yTop + 0.7, bedZ), ctx.Color, M.SmoothPlastic, { Collide = true })
	end
	vis(ctx, "Tailgate", Vector3.new(d.Width, 1.4, 0.3), CFrame.new(0, ctx.yTop + 0.7, d.Length / 2 - 0.15), ctx.Color, M.SmoothPlastic, { Collide = true })
	vis(ctx, "BedFloor", Vector3.new(d.Width - 0.6, 0.1, bedL), CFrame.new(0, ctx.yTop + 0.05, bedZ), DARK, M.DiamondPlate, { Shadow = false })
end

function CarStyles.van(ctx: Ctx)
	local d = ctx.Def
	-- uzun yük bölümü: kabin neredeyse tüm boy
	carCommon(ctx, 0.6, d.Length - 4.6, d.Width - 0.2)
	local yT = ctx.yTop
	-- yük bölümünü opak yap (sadece ön kısım cam)
	vis(ctx, "CargoBox", Vector3.new(d.Width - 0.1, d.CabinHeight, d.Length - 8), CFrame.new(0, yT + d.CabinHeight / 2, 2.4), ctx.Color, M.SmoothPlastic, { Collide = true })
	vis(ctx, "SideStripe", Vector3.new(d.Width, 0.4, d.Length - 8), CFrame.new(0, yT + d.CabinHeight * 0.4, 2.4), rgb(255, 122, 69), M.SmoothPlastic, { Shadow = false })
end

function CarStyles.utility(ctx: Ctx)
	local d = ctx.Def
	carCommon(ctx, -2.4, 5.0)
	local bedL = d.Length / 2 - 0.2
	local bedZ = d.Length / 2 - bedL / 2
	vis(ctx, "Flatbed", Vector3.new(d.Width, 0.4, bedL), CFrame.new(0, ctx.yTop + 0.2, bedZ), DARK, M.DiamondPlate, { Collide = true })
	vis(ctx, "Toolbox", Vector3.new(d.Width - 0.6, 1.4, 1.6), CFrame.new(0, ctx.yTop + 1.1, bedZ - bedL / 2 + 1), rgb(200, 200, 196), M.DiamondPlate, { Collide = true })
	if d.LightBar then
		vis(ctx, "LightBar", Vector3.new(d.Width - 1.6, 0.35, 0.6), CFrame.new(0, ctx.yTop + d.CabinHeight + 0.5, -2.4), AMBER, M.Neon, { Shadow = false })
	end
end

-- ===================== MOTOSİKLET GÖVDELERİ =====================
local function bikeCommon(ctx: Ctx, frontKnuckle: BasePart)
	local d = ctx.Def
	local yW = ctx.yW
	local half = d.Wheelbase / 2
	vis(ctx, "Frame", Vector3.new(0.7, 1, d.Wheelbase * 0.6), CFrame.new(0, yW + 0.6, 0), DARK, M.Metal, { Collide = true })
	vis(ctx, "Engine", Vector3.new(1.2, 1.2, 1.6), CFrame.new(0, yW + 0.25, 0.2), rgb(70, 72, 78), M.Metal)
	vis(ctx, "Exhaust", Vector3.new(2.6, 0.4, 0.4), cylCF(0.55, yW + 0.1, 1.6, "Z"), CHROME, M.Metal, { Shape = "Cylinder", Shadow = false })
	vis(ctx, "RearFender", Vector3.new(0.9, 0.3, 1.8), CFrame.new(0, yW + d.WheelRadius + 0.25, half - 0.3), ctx.Color, M.SmoothPlastic, { Shadow = false })
	local tail = vis(ctx, "TailLight", Vector3.new(0.7, 0.3, 0.15), CFrame.new(0, yW + d.WheelRadius + 0.4, half + 0.6), TAIL_OFF, M.SmoothPlastic, { Shadow = false })
	local _ = tail
	for _, sx in { -1, 1 } do
		vis(ctx, if sx < 0 then "IndicatorL" else "IndicatorR", Vector3.new(0.3, 0.2, 0.2), CFrame.new(sx * 0.5, yW + d.WheelRadius + 0.4, half + 0.55), AMBER, M.SmoothPlastic, { Shadow = false })
	end
	-- Ön çatal + gidon + far: ön aks mafsalına kaynaklı → direksiyonla birlikte döner
	local fk = frontKnuckle
	for _, sx in { -1, 1 } do
		vis(ctx, "Fork", Vector3.new(0.2, 2.4, 0.2), CFrame.new(sx * 0.45, 1.2, 0.35) * CFrame.Angles(math.rad(-12), 0, 0), CHROME, M.Metal, { WeldTo = fk, Shadow = false })
	end
	local bar = vis(ctx, "Handlebar", Vector3.new(2.6, 0.2, 0.2), CFrame.new(0, 2.25, 0.9), DARK, M.Metal, { WeldTo = fk, Shadow = false })
	attachment(bar, "HandL", Vector3.new(-1.1, 0, 0))
	attachment(bar, "HandR", Vector3.new(1.1, 0, 0))
	local head = vis(ctx, "Headlight", Vector3.new(0.6, 0.5, 0.2), CFrame.new(0, 1.8, 0.2), LIGHT_OFF, M.SmoothPlastic, { WeldTo = fk, Shadow = false })
	addLight(ctx, head, 60, 55)
	for _, sx in { -1, 1 } do
		vis(ctx, if sx < 0 then "IndicatorL" else "IndicatorR", Vector3.new(0.25, 0.2, 0.2), CFrame.new(sx * 0.6, 1.8, 0.25), AMBER, M.SmoothPlastic, { WeldTo = fk, Shadow = false })
	end
	vis(ctx, "FrontFender", Vector3.new(0.8, 0.25, 1.6), CFrame.new(0, d.WheelRadius + 0.2, 0), ctx.Color, M.SmoothPlastic, { WeldTo = fk, Shadow = false })
end

local BikeStyles = {}

function BikeStyles.sport(ctx: Ctx, fk: BasePart)
	bikeCommon(ctx, fk)
	local yW = ctx.yW
	vis(ctx, "Tank", Vector3.new(1.4, 0.9, 2), CFrame.new(0, yW + 1.45, -0.9), ctx.Color, M.SmoothPlastic)
	vis(ctx, "Fairing", Vector3.new(1.6, 1.4, 1.6), CFrame.new(0, yW + 1.4, -2.2), ctx.Color, M.SmoothPlastic, { Shape = "Wedge" })
	vis(ctx, "Windscreen", Vector3.new(1.2, 0.8, 0.8), CFrame.new(0, yW + 2.4, -2.1), GLASS, M.Glass, { Shape = "Wedge", Transparency = 0.3, Shadow = false })
	vis(ctx, "TailCowl", Vector3.new(1, 0.6, 1.6), CFrame.new(0, yW + 1.5, 1.6) * CFrame.Angles(0, math.pi, 0), ctx.Color, M.SmoothPlastic, { Shape = "Wedge" })
end

function BikeStyles.street(ctx: Ctx, fk: BasePart)
	bikeCommon(ctx, fk)
	local yW = ctx.yW
	vis(ctx, "Tank", Vector3.new(1.3, 0.9, 2), CFrame.new(0, yW + 1.4, -0.8), ctx.Color, M.SmoothPlastic)
	vis(ctx, "SideCover", Vector3.new(1.1, 0.6, 1.2), CFrame.new(0, yW + 1.1, 0.8), ctx.Color, M.SmoothPlastic, { Shadow = false })
end

function BikeStyles.cruiser(ctx: Ctx, fk: BasePart)
	bikeCommon(ctx, fk)
	local yW = ctx.yW
	vis(ctx, "Tank", Vector3.new(1.5, 1, 2.4), CFrame.new(0, yW + 1.3, -1), ctx.Color, M.SmoothPlastic, { Reflectance = 0.1 })
	vis(ctx, "Backrest", Vector3.new(0.9, 1.4, 0.3), CFrame.new(0, yW + 2.1, 3), DARK, M.Leather, { Shadow = false })
	for _, sx in { -1, 1 } do
		vis(ctx, "Saddlebag", Vector3.new(0.6, 1, 1.6), CFrame.new(sx * 0.9, yW + 1, 2), DARK, M.Leather, { Shadow = false })
	end
	vis(ctx, "WideBar", Vector3.new(3, 0.2, 0.2), CFrame.new(0, 2.6, 0.6), CHROME, M.Metal, { WeldTo = fk, Shadow = false })
end

function BikeStyles.scooter(ctx: Ctx, fk: BasePart)
	bikeCommon(ctx, fk)
	local yW = ctx.yW
	vis(ctx, "Floorboard", Vector3.new(1.2, 0.3, 1.8), CFrame.new(0, yW + 0.35, -0.5), DARK, M.SmoothPlastic, { Collide = true })
	vis(ctx, "BodyRear", Vector3.new(1.4, 1.2, 2.2), CFrame.new(0, yW + 0.9, 1.1), ctx.Color, M.SmoothPlastic)
	vis(ctx, "LegShield", Vector3.new(1.4, 1.8, 0.4), CFrame.new(0, 1.0, 0.6), ctx.Color, M.SmoothPlastic, { WeldTo = fk })
end

function BikeStyles.standard(ctx: Ctx, fk: BasePart)
	bikeCommon(ctx, fk)
	local yW = ctx.yW
	vis(ctx, "Tank", Vector3.new(1.4, 0.95, 2.1), CFrame.new(0, yW + 1.4, -0.85), ctx.Color, M.SmoothPlastic)
	vis(ctx, "RoundLamp", Vector3.new(0.3, 0.9, 0.9), cylCF(0, 1.8, 0.05, "Z"), CHROME, M.Metal, { WeldTo = fk, Shape = "Cylinder", Shadow = false })
end

-- ===================== TEKERLEK + SÜSPANSİYON =====================
local function buildWheel(ctx: Ctx, name: string, x: number, z: number, steer: boolean, driven: boolean, rear: boolean)
	local d = ctx.Def
	local chassis = ctx.Chassis
	local R, travel = d.WheelRadius, d.Travel
	local center = Vector3.new(x, ctx.yW, z)
	-- Kayıcının üst sınırı sürüş konumunun ne kadar üstünde: otomobilde BumpRoom (kursun %60'ı yukarıda,
	-- tümsekler için), motosiklette eskisi gibi kursun yarısı.
	local strutTop = if ctx.Derived then ctx.Derived.BumpRoom else travel / 2

	local knuckle = Instance.new("Part")
	knuckle.Name = "Knuckle_" .. name
	knuckle.Size = Vector3.new(0.6, 0.6, 0.6)
	knuckle.CFrame = chassis.CFrame * CFrame.new(center)
	knuckle.Transparency = 1
	knuckle.CanCollide = false
	knuckle.CanTouch = false
	knuckle.CanQuery = false
	knuckle.CollisionGroup = VehicleFactory.WheelGroup
	knuckle.Parent = ctx.Model
	table.insert(ctx.Physical, knuckle)

	local wheel = Instance.new("Part")
	wheel.Name = "Wheel_" .. name
	wheel.Shape = Enum.PartType.Cylinder
	wheel.Size = Vector3.new(d.WheelWidth, R * 2, R * 2)
	wheel.CFrame = chassis.CFrame * CFrame.new(center)
	wheel.Color = rgb(28, 28, 30)
	wheel.Material = M.SmoothPlastic
	wheel.CustomPhysicalProperties = PhysicalProperties.new(0.9, d.Grip, 0, 100, 1)
	wheel.CollisionGroup = VehicleFactory.WheelGroup
	wheel.CanTouch = false
	wheel.TopSurface = Enum.SurfaceType.Smooth
	wheel.BottomSurface = Enum.SurfaceType.Smooth
	wheel:SetAttribute("Wheel", name)
	wheel:SetAttribute("Rear", rear)
	wheel.Parent = ctx.Model
	table.insert(ctx.Physical, wheel)
	local knuckleVolume = knuckle.Size.X * knuckle.Size.Y * knuckle.Size.Z
	knuckle.CustomPhysicalProperties = PhysicalProperties.new(
		math.clamp(wheel:GetMass() * KNUCKLE_MASS_RATIO / knuckleVolume, 0.05, 100), 0.3, 0, 1, 1)
	vis(ctx, "Rim", Vector3.new(d.WheelWidth + 0.06, R * 1.25, R * 1.25), CFrame.new(), CHROME, M.Metal, { Shape = "Cylinder", WeldTo = wheel, Shadow = false })

	-- Süspansiyon kayıcısı + direksiyon servosu
	local strutA = attachment(chassis, "Strut_" .. name, center + Vector3.new(0, strutTop, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, -1))
	local strutK = attachment(knuckle, "Strut", Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, -1))
	local cyl = Instance.new("CylindricalConstraint")
	cyl.Name = "Suspension_" .. name
	cyl.Attachment0 = strutA
	cyl.Attachment1 = strutK
	cyl.LimitsEnabled = true
	cyl.LowerLimit = -travel
	cyl.UpperLimit = 0
	cyl.Restitution = 0
	cyl.AngularActuatorType = Enum.ActuatorType.Servo
	cyl.AngularSpeed = 8
	cyl.TargetAngle = 0
	cyl:SetAttribute("Wheel", name)
	cyl:SetAttribute("Steer", steer)
	cyl:SetAttribute("Rear", rear)
	cyl.Parent = knuckle

	-- Yay + amortisör (sertlik kütle hesabından sonra ayarlanır)
	local springTop = attachment(chassis, "SpringTop_" .. name, center + Vector3.new(0, strutTop + 2, 0))
	local spring = Instance.new("SpringConstraint")
	spring.Name = "Spring_" .. name
	spring.Attachment0 = springTop
	spring.Attachment1 = strutK
	spring.Visible = false
	spring:SetAttribute("Rear", rear)
	spring.Parent = knuckle

	-- Tahrik/fren motoru
	local axleK = attachment(knuckle, "Axle", Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0))
	local axleW = attachment(wheel, "Axle", Vector3.zero, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0))
	local hinge = Instance.new("HingeConstraint")
	hinge.Name = "Motor_" .. name
	hinge.Attachment0 = axleK
	hinge.Attachment1 = axleW
	hinge.ActuatorType = Enum.ActuatorType.Motor
	hinge.AngularVelocity = 0
	hinge.MotorMaxAcceleration = math.huge
	hinge:SetAttribute("Wheel", name)
	hinge:SetAttribute("Driven", driven)
	hinge:SetAttribute("Rear", rear)
	hinge.Parent = knuckle

	return knuckle, wheel, cyl, spring, hinge
end

-- ===================== DIŞ 3D MODEL (CarModelConfig) =====================
-- Sadece görünüm: fizik parçaları (şasi, balast, mafsallar, fizik tekerleri), çarpışma kabuğu (Body/Cabin) ve ışık
-- kaynakları aynen kalır, görünmez olur. Model fizikteki dingil mesafesine ölçeklenir; görünür tekerlekler modelin kendi
-- oranındadır ve yere değecek kadar alçakta durur (fizik tekerleği modelinkinden büyük). Teker görselleri mafsala
-- Motor6D ile bağlıdır: direksiyon ve süspansiyonla hareket eder, dönüşü istemci oynatır (VehicleVisualsController).
local function dressWithModel(ctx: Ctx, name: string, colorGiven: boolean): boolean
	local info = CarModelKit.Get(name)
	if not info then
		return false
	end
	local d, model, chassis = ctx.Def, ctx.Model, ctx.Chassis
	local physical = {}
	for _, p in ctx.Physical do
		physical[p] = true
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and not p:IsA("Seat") and p ~= chassis and p.Name ~= "Ballast" and not physical[p] then
			p.Transparency = 1 -- eski kutu görseller: çarpışma kabuğu ve ışık kaynağı olarak kalır, görünmez
			p.CastShadow = false
		end
	end
	chassis.Transparency = 1
	local knuckles = {}
	for _, w in { "FL", "FR", "RL", "RR" } do
		local wheel = model:FindFirstChild("Wheel_" .. w)
		if wheel and wheel:IsA("BasePart") then
			wheel.Transparency = 1
			wheel.CastShadow = false
		end
		knuckles[w] = model:FindFirstChild("Knuckle_" .. w)
	end
	local s = d.Wheelbase / info.Wheelbase
	local visualRadius = info.WheelRadius * s
	local drop = math.max(d.WheelRadius - visualRadius, 0)
	local frame = chassis.CFrame * CFrame.new(0, ctx.yW - drop, 0)
	-- renk verilmediyse bazen modelin kendi rengi (CarModelConfig.OriginalPaintChance)
	local paint = if colorGiven then ctx.Color else CarModelKit.RandomPaint({ ctx.Color }, ctx.Rng)
	CarModelKit.Build(info, { Frame = frame, Scale = s, Parent = model, Body = chassis, Wheels = knuckles, Paint = paint })
	-- Koltuk: oturan karakterin başı (~3.4 stud) tavanın altında kalsın
	local roof = ctx.yW - drop + info.RoofY * s
	ctx.SeatDrop = math.max((ctx.yTop - 1.0) - (roof - 3.4), 0)
	model:SetAttribute("BodyModel", name)
	return true
end

-- ===================== İNŞA =====================
local function newVehicleId(): string
	return string.sub(HttpService:GenerateGUID(false), 1, 8)
end

function VehicleFactory.Build(defId: string, cframe: CFrame, options: { Color: Color3?, Seed: number? }?): Model?
	local def = VehicleDefinitions.Get(defId)
	if not def then
		warn("[VehicleFactory] Bilinmeyen araç:", defId)
		return nil
	end
	local opts = options or {}
	local rng = Random.new(opts.Seed or os.clock() * 1000)
	local isBike = def.Type == "Motorcycle"

	local model = Instance.new("Model")
	model.Name = def.DisplayName

	local chassisSize = if isBike
		then Vector3.new(0.9, 0.9, def.Wheelbase * 0.7)
		else Vector3.new(def.Track - def.WheelWidth - 0.5, 1, def.Length - 1.2)
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = chassisSize
	chassis.CFrame = cframe
	chassis.Color = DARK
	chassis.Material = M.Metal
	chassis.Transparency = if isBike then 1 else 0
	chassis.CanTouch = false
	chassis.CollisionGroup = VehicleFactory.BodyGroup
	local volume = chassisSize.X * chassisSize.Y * chassisSize.Z
	local carPhysics = VehicleDefinitions.UsesCarPhysics(def)
	local derived = if carPhysics then VehiclePhysics.Derive(def) else nil
	-- Otomobilde kütlenin BallastFraction kadarı balast parçasına gider (ağırlık dağılımı / ağırlık merkezi)
	local chassisMass = if carPhysics then def.Mass * (1 - VehiclePhysics.Constants.BallastFraction) else def.Mass
	chassis.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(chassisMass / volume, 0.05, 100), 0.3, 0, 1, 1)
	chassis.Parent = model
	model.PrimaryPart = chassis

	local ballast: Part? = nil
	if carPhysics and derived then
		chassis.RootPriority = 10 -- montajın kökü şasi kalsın (balast ağır ama küçük)
		local b = Instance.new("Part")
		b.Name = "Ballast"
		b.Size = Vector3.new(math.max(chassisSize.X * 0.5, 1), 0.4, 1.2)
		local ballastVolume = b.Size.X * b.Size.Y * b.Size.Z
		b.CustomPhysicalProperties = PhysicalProperties.new(
			math.clamp(def.Mass * VehiclePhysics.Constants.BallastFraction / ballastVolume, 0.05, 100), 0.3, 0, 1, 1)
		-- Şasi tabanında, ağırlık dağılımı için Z'de kaydırılmış; CoGOffset ile yükseltilir
		b.CFrame = cframe * CFrame.new(0, -chassisSize.Y / 2 + 0.2 + def.Physics.CoGOffset, derived.BallastZ)
		b.Transparency = 1
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CollisionGroup = VehicleFactory.BodyGroup
		b.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = b
		weld.Parent = b
		ballast = b
	end

	local ctx: Ctx = {
		Model = model, Chassis = chassis, Def = def,
		Color = opts.Color or def.Colors[rng:NextInteger(1, #def.Colors)],
		Rng = rng,
		yW = -(chassisSize.Y / 2 + def.Clearance) + def.WheelRadius,
		yTop = 0,
		Physical = { chassis },
		Derived = derived,
	}

	-- Tekerlekler
	local wheels = {}
	if isBike then
		local fk = buildWheel(ctx, "F", 0, -def.Wheelbase / 2, true, false, false)
		buildWheel(ctx, "R", 0, def.Wheelbase / 2, false, true, true)
		local styleFn = BikeStyles[def.Style] or BikeStyles.standard
		styleFn(ctx, fk)
		wheels = { "F", "R" }
	else
		local hx, hz = def.Track / 2, def.Wheelbase / 2
		local frontDriven = def.Drive == "FWD" or def.Drive == "AWD"
		local rearDriven = def.Drive == "RWD" or def.Drive == "AWD"
		buildWheel(ctx, "FL", -hx, -hz, true, frontDriven, false)
		buildWheel(ctx, "FR", hx, -hz, true, frontDriven, false)
		buildWheel(ctx, "RL", -hx, hz, false, rearDriven, true)
		buildWheel(ctx, "RR", hx, hz, false, rearDriven, true)
		local styleFn = CarStyles[def.Style] or CarStyles.sedan
		styleFn(ctx)
		local bodyModel = CarModelKit.Pick(defId, rng, false)
		if bodyModel then
			dressWithModel(ctx, bodyModel, opts.Color ~= nil)
		end
		wheels = { "FL", "FR", "RL", "RR" }
		-- direksiyon simidi + IK el hedefleri
		local driver = def.Seats[1]
		local wheelPos = Vector3.new(driver.X, ctx.yTop + 0.25 - (ctx.SeatDrop or 0), driver.Z - 1.9)
		vis(ctx, "SteeringWheel", Vector3.new(0.15, 1.5, 1.5), cylCF(wheelPos.X, wheelPos.Y, wheelPos.Z, "Z") * CFrame.Angles(0, 0, math.rad(-25)), DARK, M.SmoothPlastic, { Shape = "Cylinder", Shadow = false })
		attachment(chassis, "HandL", wheelPos + Vector3.new(-0.62, 0, 0))
		attachment(chassis, "HandR", wheelPos + Vector3.new(0.62, 0, 0))
	end

	-- Koltuklar (sürücü + yolcular)
	for index, s in def.Seats do
		local seat = Instance.new("Seat")
		seat.Name = if s.Driver then "DriverSeat" else "PassengerSeat" .. index
		seat.Size = if isBike then Vector3.new(1.1, 0.4, 1.8) else Vector3.new(1.8, 0.4, 1.8)
		local seatY = if isBike then ctx.yW + 1.55 else ctx.yTop - 1.0 - (ctx.SeatDrop or 0)
		seat.CFrame = chassis.CFrame * CFrame.new(s.X, seatY, s.Z)
		seat.Color = DARK
		seat.Material = if isBike then M.Leather else M.Fabric
		seat.Transparency = if isBike then 0 else 1
		seat.Massless = true
		seat.CanCollide = false
		seat.CollisionGroup = VehicleFactory.BodyGroup
		seat:SetAttribute("VehicleSeat", true)
		seat:SetAttribute("DriverSeat", s.Driver == true)
		seat.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chassis
		weld.Part1 = seat
		weld.Parent = seat

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EnterPrompt"
		prompt.ActionText = if s.Driver then "Sür" else "Bin"
		prompt.ObjectText = def.DisplayName
		prompt.KeyboardKeyCode = Enum.KeyCode.F
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
		prompt.MaxActivationDistance = if s.Driver then 10 else 8
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.UIOffset = Vector2.new(0, if s.Driver then 0 else 40)
		prompt.Parent = seat
	end

	-- Motosiklet: dik durma / yatış
	local upright = attachment(chassis, "Upright", Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, -1))
	local align = Instance.new("AlignOrientation")
	align.Name = "Upright"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.AlignType = Enum.AlignType.PrimaryAxisParallel
	align.Attachment0 = upright
	align.PrimaryAxis = Vector3.new(0, 1, 0)
	-- Araç fizik kararlılığı: motosiklette tepki 30 → 18 (gövdeyi bir anda yuvarlayıp dar tekerleri kenarına
	-- bastırmasın); tork aşağıda gerekenin ~12 katına indirildi.
	align.Responsiveness = if isBike then 18 else 8
	align.RigidityEnabled = false
	align.Enabled = isBike -- arabada sadece "ters dönme yardımı" için geçici açılır
	align.Parent = chassis

	-- Sesler (ID verilmişse)
	local audio = AudioConfig.Vehicle
	local engineId = AudioConfig.Resolve(if isBike then audio.EngineMotorcycle else audio.EngineCar)
	if engineId then
		local engine = Instance.new("Sound")
		engine.Name = "Engine"
		engine.SoundId = engineId
		engine.Looped = true
		engine.Volume = audio.EngineVolume
		engine.RollOffMinDistance = audio.RollOffMin
		engine.RollOffMaxDistance = audio.RollOffMax
		engine.Parent = chassis
	end
	local hornId = AudioConfig.Resolve(if isBike then audio.HornMotorcycle else audio.HornCar)
	if hornId then
		local horn = Instance.new("Sound")
		horn.Name = "Horn"
		horn.SoundId = hornId
		horn.Looped = true
		horn.Volume = audio.HornVolume
		horn.RollOffMinDistance = audio.RollOffMin
		horn.RollOffMaxDistance = audio.RollOffMax * 1.5
		horn.Parent = chassis
	end

	-- ===== Kütleye bağlı ayarlar =====
	if carPhysics and derived and ballast then
		VehicleFactory._tuneCar(model, defId, def, derived, chassis, ballast, ctx, align)
		CollectionService:AddTag(model, "Vehicle")
		return model
	end
	local sprung = chassis:GetMass()
	local total = 0
	for _, p in ctx.Physical do
		total += p:GetMass()
	end
	local n = #wheels
	local g = workspace.Gravity
	local cornerWeight = sprung * g / n
	local stiffness = cornerWeight / (0.6 * def.Travel)
	local damping = 2 * 0.45 * math.sqrt(stiffness * sprung / n)
	local nDriven = 0
	for _, d in model:GetDescendants() do
		if d:IsA("HingeConstraint") and d:GetAttribute("Driven") then
			nDriven += 1
		end
	end
	local R = def.WheelRadius
	local driveTorque = total * def.Accel * R / math.max(nDriven, 1)
	local brakeTorque = total * def.Brake * R / n
	local coastTorque = total * 4 * R / n
	for _, d in model:GetDescendants() do
		if d:IsA("SpringConstraint") then
			d.Stiffness = stiffness
			d.Damping = damping
			d.FreeLength = (2 + def.Travel / 2) + 0.6 * def.Travel
		elseif d:IsA("CylindricalConstraint") then
			d.ServoMaxTorque = steerServoTorque(total, g, n, def.Grip, R)
		elseif d:IsA("HingeConstraint") then
			d.MotorMaxTorque = brakeTorque -- park freni
		end
	end
	-- (motosiklette eskiden ×60: 40° yatışta dik tutmak için gerekenin ~85 katı)
	align.MaxTorque = total * g * (if isBike then 12 else 30)

	model:SetAttribute("VehicleId", newVehicleId())
	model:SetAttribute("DefId", defId)
	model:SetAttribute("VehicleType", def.Type)
	model:SetAttribute("DriveTorque", driveTorque)
	model:SetAttribute("BrakeTorque", brakeTorque)
	model:SetAttribute("CoastTorque", coastTorque)
	model:SetAttribute("TotalMass", total)
	model:SetAttribute("Lights", false)
	model:SetAttribute("Indicator", "")
	model:SetAttribute("Braking", false)
	model:SetAttribute("Reversing", false)
	-- yerden şasi merkezine yükseklik (doğurma/ışınlama için)
	model:SetAttribute("RideHeight", chassisSize.Y / 2 + def.Clearance + 0.25 * def.Travel)

	for _, p in ctx.Physical do
		p:SetAttribute("Physical", true)
	end
	CollectionService:AddTag(model, "Vehicle")
	return model
end

-- ===== Aşama 2: otomobil fizik modeli kurulumu =====
-- Yaylar ve sönüm aks başına yaylı kütleden; kaldırma kuvvetleri EffectiveGravity'den hesaplanır.
-- İstemcideki CarPhysics her karede sadece motor/fren/direksiyon/aero değerlerini yazar.
function VehicleFactory._tuneCar(model: Model, defId: string, def, derived, chassis: BasePart, ballast: BasePart, ctx: Ctx, align: AlignOrientation)
	local C = VehiclePhysics.Constants
	local p = def.Physics
	local G = workspace.Gravity
	local lift = G - C.EffectiveGravity -- araca uygulanan yerçekimi farkı (yukarı)
	local sprung = chassis:GetMass() + ballast:GetMass()
	local unsprung = 0

	for _, d in model:GetDescendants() do
		if d:IsA("SpringConstraint") then
			local rear = d:GetAttribute("Rear") == true
			d.Stiffness = sprung * (if rear then derived.StiffnessPerMassRear else derived.StiffnessPerMassFront)
			d.Damping = sprung * (if rear then derived.DampingPerMassRear else derived.DampingPerMassFront)
			-- Sürüş konumunda yay boyu = BumpRoom + 2; statik çökme kadar sıkışmış olmalı
			d.FreeLength = derived.BumpRoom + 2 + (if rear then derived.SagRear else derived.SagFront)
		elseif d:IsA("BasePart") and d:GetAttribute("Wheel") then
			local rear = d:GetAttribute("Rear") == true
			local mu = p.TireGrip * (if rear then p.GripRear else p.GripFront)
			d.CustomPhysicalProperties = PhysicalProperties.new(0.9, mu, 0, 100, 1)
			local knuckle = model:FindFirstChild("Knuckle_" .. d:GetAttribute("Wheel"))
			-- Tekerlek ve mafsal ayrı montajlardır: her birine KENDİ kütlesi kadar kaldırma kuvveti
			-- (mafsal artık ağır; kuvvet tekere toplanırsa menteşe üzerinden gereksiz iç kuvvet taşınırdı)
			for _, part in { d, knuckle } do
				if part then
					unsprung += part:GetMass()
					local a = attachment(part, "AntiGravity", Vector3.zero)
					local force = Instance.new("VectorForce")
					force.Name = "AntiGravity"
					force.Attachment0 = a
					force.RelativeTo = Enum.ActuatorRelativeTo.World
					force.ApplyAtCenterOfMass = true
					force.Force = Vector3.new(0, part:GetMass() * lift, 0)
					force.Parent = part
				end
			end
		end
	end
	local total = sprung + unsprung

	-- Şasi kuvvetleri: kaldırma (sabit, sunucuda) + aero/yuvarlanma (istemci her karede ekler)
	local core = attachment(chassis, "Core", Vector3.zero)
	local forces = Instance.new("VectorForce")
	forces.Name = "Forces"
	forces.Attachment0 = core
	forces.RelativeTo = Enum.ActuatorRelativeTo.World
	forces.ApplyAtCenterOfMass = true
	forces.Force = Vector3.new(0, sprung * lift, 0)
	forces.Parent = chassis
	forces:SetAttribute("BaseLift", sprung * lift)
	-- Savrulma denge yardımı (istemci yazar; sunucuda sıfır)
	local stability = Instance.new("Torque")
	stability.Name = "Stability"
	stability.Attachment0 = core
	stability.RelativeTo = Enum.ActuatorRelativeTo.World
	stability.Torque = Vector3.zero
	stability.Parent = chassis

	-- Park freni / yerinde tutma: %12 eğimde güvenle durduracak tork (sürtünme sınırını aşmaz)
	local R = def.WheelRadius
	local holdTorque = total * C.EffectiveGravity * 0.3 / 4 * R
	for _, d in model:GetDescendants() do
		if d:IsA("CylindricalConstraint") then
			d.ServoMaxTorque = steerServoTorque(total, C.EffectiveGravity, 4, p.TireGrip * math.max(p.GripFront, p.GripRear), R)
		elseif d:IsA("HingeConstraint") then
			d.MotorMaxTorque = holdTorque
		end
	end
	-- Havada dengeleme (istemci açar; yerdeyken kapalı)
	align.MaxTorque = total * C.EffectiveGravity * 30
	align.Responsiveness = 6

	model:SetAttribute("VehicleId", newVehicleId())
	model:SetAttribute("DefId", defId)
	model:SetAttribute("VehicleType", def.Type)
	model:SetAttribute("PhysicsModel", "Car2")
	model:SetAttribute("SprungMass", sprung)
	model:SetAttribute("TotalMass", total)
	model:SetAttribute("BrakeTorque", holdTorque) -- sunucu park freni bunu kullanır
	model:SetAttribute("DriveTorque", 0)
	model:SetAttribute("CoastTorque", 0)
	model:SetAttribute("Lights", false)
	model:SetAttribute("Indicator", "")
	model:SetAttribute("Braking", false)
	model:SetAttribute("Reversing", false)
	model:SetAttribute("RideHeight", VehiclePhysics.CarRideHeight(def))
	for _, part in ctx.Physical do
		part:SetAttribute("Physical", true)
	end
end

-- Doğurma yüksekliği (şasi merkezi ↔ zemin). Otomobil yeni modelde; motosiklet eski formülde.
function VehicleFactory.ComputeRideHeight(def): number
	if VehicleDefinitions.UsesCarPhysics(def) then
		return VehiclePhysics.CarRideHeight(def)
	end
	local chassisH = if def.Type == "Motorcycle" then 0.9 else 1
	return chassisH / 2 + def.Clearance + 0.25 * def.Travel
end

-- Uzak/park araçlarda fizik maliyetini sıfırlamak için (Bölüm 27.2)
function VehicleFactory.SetAnchored(model: Model, anchored: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Physical") then
			d.Anchored = anchored
		end
	end
end

function VehicleFactory.SetNetworkOwner(model: Model, player: Player?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Physical") and not d.Anchored then
			pcall(function()
				d:SetNetworkOwner(player)
			end)
		end
	end
end

return VehicleFactory
