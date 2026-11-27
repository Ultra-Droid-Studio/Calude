-- PropBuilder: sokak lambaları, ağaçlar, banklar, otobüs durakları, park metreleri, çeşme,
-- oyun parkı, palmiyeler, cankurtaran kuleleri, iskeleler, liman vinçleri, otoyol ayakları ve tabelaları.
-- Konumlar mapgen.py'de yol/arsa/su çakışmasına karşı doğrulanmıştır.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapDefinitions = require(ReplicatedStorage.Shared.MapDefinitions)
local Config = require(ReplicatedStorage.Shared.Config)
local StreetLights = require(script.Parent.StreetLights) -- 3D sokak lambaları (KMB3D, CC-BY-4.0), içe aktarıldıysa

local PropBuilder = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local LAMP_OFF = rgb(170, 170, 160)

local Props = {}

function Props.lamp(kit, folder, cf: CFrame, p, index: number)
	-- 3D model içe aktarıldıysa bölgeye uygun lamba tipi; yoksa aşağıdaki eski prosedürel lamba
	if StreetLights.Place(kit, folder, cf, p, index) then
		return
	end
	local C = kit.Colors
	kit:Cylinder(folder, 18, 0.7, cf * CFrame.new(0, 9, 0), rgb(60, 62, 66), M.Metal, { CastShadow = false })
	-- kol: yola doğru (-Z) uzanır, ucunda lamba başlığı
	local head = kit:Box(folder, Vector3.new(1.4, 0.6, 7), cf * CFrame.new(0, 18, -3.2), LAMP_OFF, M.SmoothPlastic, { CastShadow = false })
	head.Name = "LampHead"
	if index % Config.World.LampLightEvery == 0 then
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Bottom
		light.Range = 36
		light.Angle = 110
		light.Brightness = 2.2
		light.Color = rgb(255, 214, 160)
		light.Shadows = false
		light.Enabled = false
		light.Parent = head
	end
	kit:Tag(head, "StreetLamp") -- ışık eklendikten SONRA etiketle (WeatherService anında açabilsin)
	local _ = C
end

function Props.tree(kit, folder, cf: CFrame, p)
	local rng = Random.new(math.floor(p.X * 7 + p.Z * 13))
	if p.Extra == "pine" then
		local h = rng:NextNumber(14, 22)
		kit:Cylinder(folder, h * 0.4, 1.4, cf * CFrame.new(0, h * 0.2, 0), rgb(96, 70, 48), M.Wood, { CastShadow = false })
		kit:Cylinder(folder, h * 0.45, h * 0.55, cf * CFrame.new(0, h * 0.5, 0), kit.Colors.Pine, M.Grass)
		kit:Cylinder(folder, h * 0.35, h * 0.32, cf * CFrame.new(0, h * 0.82, 0), kit.Colors.Pine, M.Grass)
	else
		local h = rng:NextNumber(8, 12)
		kit:Cylinder(folder, h, 1.6, cf * CFrame.new(0, h / 2, 0), rgb(110, 80, 54), M.Wood, { CastShadow = false })
		local green = kit.Colors.Leaf:Lerp(rgb(120, 150, 60), rng:NextNumber(0, 0.4))
		kit:Ball(folder, rng:NextNumber(11, 17), cf * CFrame.new(0, h + 3, 0), green, M.Grass)
	end
end

function Props.palm(kit, folder, cf: CFrame, p)
	local rng = Random.new(math.floor(p.Z * 3))
	local h = rng:NextNumber(18, 26)
	local lean = math.rad(rng:NextNumber(4, 10))
	local trunk = cf * CFrame.Angles(lean, 0, 0)
	kit:Cylinder(folder, h, 1.3, trunk * CFrame.new(0, h / 2, 0), rgb(150, 116, 80), M.Wood, { CastShadow = false })
	local top = trunk * CFrame.new(0, h, 0)
	for k = 0, 4 do
		local a = k * (2 * math.pi / 5)
		kit:Box(folder, Vector3.new(1.8, 0.3, 11), top * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, -1, -5), rgb(70, 140, 60), M.Grass, { CastShadow = false })
	end
end

function Props.bench(kit, folder, cf: CFrame)
	kit:Box(folder, Vector3.new(6, 0.5, 2), cf * CFrame.new(0, 1.8, 0), kit.Colors.Wood, M.WoodPlanks, { CastShadow = false })
	kit:Box(folder, Vector3.new(6, 2, 0.4), cf * CFrame.new(0, 3, 0.8), kit.Colors.Wood, M.WoodPlanks, { CastShadow = false })
	kit:Box(folder, Vector3.new(5, 1.6, 1.2), cf * CFrame.new(0, 0.8, 0), rgb(60, 62, 66), M.Metal, { CastShadow = false })
end

function Props.trash(kit, folder, cf: CFrame)
	kit:Cylinder(folder, 3.2, 2, cf * CFrame.new(0, 1.6, 0), rgb(46, 90, 60), M.Metal, { CastShadow = false })
end

function Props.meter(kit, folder, cf: CFrame)
	kit:Cylinder(folder, 3.4, 0.3, cf * CFrame.new(0, 1.7, 0), rgb(80, 80, 84), M.Metal, { CastShadow = false })
	kit:Box(folder, Vector3.new(0.7, 1.1, 0.5), cf * CFrame.new(0, 3.8, 0), rgb(60, 70, 90), M.Metal, { CastShadow = false })
end

function Props.busstop(kit, folder, cf: CFrame)
	local glass = rgb(160, 200, 220)
	kit:Box(folder, Vector3.new(12, 0.5, 5), cf * CFrame.new(0, 8.5, 0.5), rgb(60, 62, 66), M.Metal)
	kit:Box(folder, Vector3.new(12, 7.5, 0.3), cf * CFrame.new(0, 4.6, 2.8), glass, M.Glass, { Transparency = 0.4, CastShadow = false })
	kit:Box(folder, Vector3.new(0.5, 8, 0.5), cf * CFrame.new(-5.8, 4.4, -1.5), rgb(60, 62, 66), M.Metal, { CastShadow = false })
	kit:Box(folder, Vector3.new(0.5, 8, 0.5), cf * CFrame.new(5.8, 4.4, -1.5), rgb(60, 62, 66), M.Metal, { CastShadow = false })
	kit:Box(folder, Vector3.new(8, 0.5, 1.6), cf * CFrame.new(0, 1.8, 2), kit.Colors.Wood, M.WoodPlanks, { CastShadow = false })
	local sign = kit:Box(folder, Vector3.new(2.4, 2.4, 0.3), cf * CFrame.new(7.5, 8, -1.5), rgb(30, 90, 180), M.SmoothPlastic, { CastShadow = false })
	kit:Label(sign, Enum.NormalId.Front, "BUS", rgb(255, 255, 255), false)
	kit:Cylinder(folder, 7, 0.3, cf * CFrame.new(7.5, 3.5, -1.5), rgb(60, 62, 66), M.Metal, { CastShadow = false })
end

function Props.fountain(kit, folder, cf: CFrame)
	kit:Cylinder(folder, 2, 26, cf * CFrame.new(0, 1, 0), rgb(200, 196, 188), M.Marble)
	kit:Cylinder(folder, 0.3, 24, cf * CFrame.new(0, 1.9, 0), rgb(80, 160, 200), M.Glass, { Transparency = 0.3, CastShadow = false })
	kit:Cylinder(folder, 8, 3, cf * CFrame.new(0, 4, 0), rgb(200, 196, 188), M.Marble)
	kit:Cylinder(folder, 1, 9, cf * CFrame.new(0, 8, 0), rgb(200, 196, 188), M.Marble)
	local spray = kit:Box(folder, Vector3.new(1, 1, 1), cf * CFrame.new(0, 8.8, 0), rgb(200, 230, 255), M.Glass, { Transparency = 1, CanCollide = false, CanQuery = false })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 30
	emitter.Lifetime = NumberRange.new(1, 1.4)
	emitter.Speed = NumberRange.new(10, 12)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Acceleration = Vector3.new(0, -24, 0)
	emitter.Size = NumberSequence.new(0.6, 0.2)
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Color = ColorSequence.new(rgb(220, 240, 255))
	emitter.Parent = spray
end

function Props.playground(kit, folder, cf: CFrame)
	local red, blue, yellow = rgb(220, 70, 60), rgb(60, 120, 210), rgb(250, 200, 50)
	local base = cf * CFrame.new(30, 0, 30)
	kit:Box(folder, Vector3.new(24, 0.2, 20), base * CFrame.new(0, 0.1, 0), rgb(200, 160, 110), M.Sand, { CastShadow = false })
	kit:Box(folder, Vector3.new(6, 0.6, 6), base * CFrame.new(-6, 5, 0), blue, M.SmoothPlastic)
	for _, o in { Vector3.new(-8.5, 0, -2.5), Vector3.new(-3.5, 0, -2.5), Vector3.new(-8.5, 0, 2.5), Vector3.new(-3.5, 0, 2.5) } do
		kit:Box(folder, Vector3.new(0.6, 5, 0.6), base * CFrame.new(o + Vector3.new(0, 2.5, 0)), yellow, M.SmoothPlastic, { CastShadow = false })
	end
	kit:Wedge(folder, Vector3.new(3, 5, 9), base * CFrame.new(1.5, 2.5, 0) * CFrame.Angles(0, math.rad(-90), 0), red, M.SmoothPlastic)
	kit:Box(folder, Vector3.new(10, 0.5, 0.5), base * CFrame.new(5, 7, -7), blue, M.Metal, { CastShadow = false })
	kit:Box(folder, Vector3.new(0.5, 7, 0.5), base * CFrame.new(0.2, 3.5, -7), blue, M.Metal, { CastShadow = false })
	kit:Box(folder, Vector3.new(0.5, 7, 0.5), base * CFrame.new(9.8, 3.5, -7), blue, M.Metal, { CastShadow = false })
end

function Props.lifeguard(kit, folder, cf: CFrame)
	kit:Box(folder, Vector3.new(5, 6, 5), cf * CFrame.new(0, 3, 0), rgb(250, 250, 250), M.WoodPlanks, { Transparency = 0, CastShadow = false })
	kit:Box(folder, Vector3.new(6, 5, 6), cf * CFrame.new(0, 8.5, 0), rgb(240, 80, 70), M.WoodPlanks)
	kit:Box(folder, Vector3.new(7, 0.6, 7), cf * CFrame.new(0, 11.3, 0), rgb(250, 250, 250), M.WoodPlanks)
	kit:Wedge(folder, Vector3.new(2, 6, 5), cf * CFrame.new(0, 3, -5), rgb(220, 210, 190), M.WoodPlanks)
end

function Props.pier(kit, folder, _cf: CFrame, p)
	local length = tonumber(p.Extra) or 100
	local meta = MapDefinitions.GetMeta()
	local z0 = meta.BayZ
	local cf = CFrame.new(p.X, 0.4, z0 + length / 2)
	kit:Box(folder, Vector3.new(8, 0.8, length), cf, rgb(150, 112, 76), M.WoodPlanks)
	for k = 0, math.floor(length / 20) do
		local z = z0 + k * 20
		kit:Cylinder(folder, 16, 1.2, CFrame.new(p.X - 4, -7, z), rgb(110, 84, 60), M.Wood, { CastShadow = false })
		kit:Cylinder(folder, 16, 1.2, CFrame.new(p.X + 4, -7, z), rgb(110, 84, 60), M.Wood, { CastShadow = false })
	end
end

function Props.crane(kit, folder, cf: CFrame)
	local color = rgb(60, 140, 200)
	for _, z in { -10, 10 } do
		kit:Box(folder, Vector3.new(2, 50, 2), cf * CFrame.new(-10, 25, z), color, M.Metal)
		kit:Box(folder, Vector3.new(2, 50, 2), cf * CFrame.new(10, 25, z), color, M.Metal)
	end
	kit:Box(folder, Vector3.new(24, 4, 24), cf * CFrame.new(0, 50, 0), color, M.Metal)
	-- bom: suya doğru (-Z yerel = yaw'a göre)
	kit:Box(folder, Vector3.new(3, 3, 70), cf * CFrame.new(0, 54, -30), color, M.Metal)
	kit:Box(folder, Vector3.new(6, 5, 6), cf * CFrame.new(0, 47, -16), rgb(240, 240, 240), M.SmoothPlastic)
end

function Props.pillar(kit, folder, cf: CFrame, p)
	local h = tonumber(p.Extra) or 16
	local w = tonumber(p.Extra2) or 54
	kit:Box(folder, Vector3.new(5, h, 5), cf * CFrame.new(0, h / 2, 0), kit.Colors.Concrete, M.Concrete)
	kit:Box(folder, Vector3.new(w * 0.7, 2, 5), cf * CFrame.new(0, h - 1, 0) * CFrame.Angles(0, math.rad(90), 0), kit.Colors.Concrete, M.Concrete)
end

function Props.fwysign(kit, folder, cf: CFrame, p)
	local green = kit.Colors.SignGreen
	-- Yükseltilmiş otoyolun dışında yerden yükselen direkler; tabela bariyerin üstünde kalır
	kit:Box(folder, Vector3.new(1, 30, 1), cf * CFrame.new(-6, 15, 0), rgb(150, 150, 150), M.Metal, { CastShadow = false })
	kit:Box(folder, Vector3.new(1, 30, 1), cf * CFrame.new(6, 15, 0), rgb(150, 150, 150), M.Metal, { CastShadow = false })
	local board = kit:Box(folder, Vector3.new(16, 5, 0.5), cf * CFrame.new(0, 28, 0), green, M.SmoothPlastic)
	kit:Label(board, Enum.NormalId.Front, p.Extra, rgb(255, 255, 255), false)
	kit:Label(board, Enum.NormalId.Back, p.Extra, rgb(255, 255, 255), false)
end

PropBuilder.Props = Props

function PropBuilder.Build(kit, world: Instance)
	local data = MapDefinitions.GetData()
	local folder = kit:Folder(world, "Props")
	local sub = {}
	local lampIndex = 0
	local failures = 0
	for _, p in data.Props do
		local fn = Props[p.Kind]
		if not fn then
			continue
		end
		local target = sub[p.Kind]
		if not target then
			target = kit:Folder(folder, p.Kind)
			sub[p.Kind] = target
		end
		local y = p.Y -- taban yüksekliği mapgen.py tarafından hesaplandı (kaldırım 0.8, zemin 0)
		local cf = CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, math.rad(p.Yaw), 0)
		if p.Kind == "lamp" then
			lampIndex += 1
		end
		local ok, err = pcall(fn, kit, target, cf, p, lampIndex)
		if not ok then
			failures += 1
			if failures <= 5 then
				warn("[WorldGen] Dekor hatası:", p.Kind, err)
			end
		end
	end
	return failures
end

return PropBuilder
