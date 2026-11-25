-- BuildingBuilder: arsa verisinden bina üretir. Her stil farklı mimari dil kullanır
-- (Bölüm 3.1: "aynı bina modelini her yerde tekrarlama"). Boyut, kat, renk ve detaylar
-- arsanın tohumuna (seed) göre değişir; aynı tohum her zaman aynı binayı üretir.
--
-- Yerel koordinat: bina önü -Z yönüne (yola) bakar, genişlik X, derinlik Z, zemin y = 0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapDefinitions = require(ReplicatedStorage.Shared.MapDefinitions)

local BuildingBuilder = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local PALETTES = {
	glass = { rgb(92, 140, 168), rgb(70, 108, 132), rgb(120, 158, 170), rgb(84, 120, 110), rgb(60, 72, 96) },
	stone = { rgb(214, 208, 196), rgb(186, 180, 170), rgb(160, 156, 150), rgb(228, 224, 214), rgb(120, 116, 112) },
	brick = { rgb(150, 72, 54), rgb(128, 64, 50), rgb(170, 98, 70), rgb(112, 76, 62), rgb(160, 120, 92) },
	pastel = { rgb(244, 196, 196), rgb(176, 222, 214), rgb(250, 230, 170), rgb(196, 210, 240), rgb(240, 214, 236), rgb(255, 255, 248) },
	house = { rgb(236, 228, 210), rgb(208, 220, 228), rgb(232, 210, 184), rgb(196, 214, 190), rgb(250, 250, 246), rgb(214, 196, 176) },
	roof = { rgb(96, 70, 60), rgb(70, 74, 82), rgb(130, 76, 58), rgb(84, 92, 74) },
	industrial = { rgb(164, 150, 120), rgb(110, 128, 140), rgb(150, 150, 146), rgb(126, 108, 92), rgb(88, 108, 96) },
	container = { rgb(176, 64, 50), rgb(46, 98, 150), rgb(212, 160, 50), rgb(70, 130, 84), rgb(150, 150, 150), rgb(230, 230, 226) },
	neon = { rgb(255, 92, 168), rgb(64, 220, 255), rgb(255, 196, 64), rgb(150, 110, 255) },
}

local DECOR_SHOP_NAMES = { "Boutique Sol", "Bakery", "Florist", "Books & Co.", "Pharmacy", "Barber", "Laundry", "Tailor",
	"Surf Shop", "Gallery", "Hardware", "Bike Shop", "Deli", "Optics", "Phone Repair", "Gelato" }

type Ctx = {
	Kit: any, Model: Model, Base: CFrame, W: number, D: number, H: number,
	Rng: Random, Lot: any, Poi: any?,
}

local function pick(rng: Random, list)
	return list[rng:NextInteger(1, #list)]
end

-- Yerel kutu: merkez (x, alt-y, z) ve boyut. bottom = kutunun alt yüzü
local function box(ctx: Ctx, size: Vector3, x: number, bottom: number, z: number, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	return ctx.Kit:Box(ctx.Model, size, ctx.Base * CFrame.new(x, bottom + size.Y / 2, z), color, material, props)
end

local function cyl(ctx: Ctx, height: number, diameter: number, x: number, bottom: number, z: number, color: Color3, material: Enum.Material?)
	return ctx.Kit:Cylinder(ctx.Model, height, diameter, ctx.Base * CFrame.new(x, bottom + height / 2, z), color, material)
end

local function wedge(ctx: Ctx, size: Vector3, x: number, bottom: number, z: number, yaw: number, color: Color3, material: Enum.Material?)
	return ctx.Kit:Wedge(ctx.Model, size, ctx.Base * CFrame.new(x, bottom + size.Y / 2, z) * CFrame.Angles(0, yaw, 0), color, material)
end

-- Ön cepheye tabela; metni okunur boyuta göre ölçeklenir
local function signBoard(ctx: Ctx, text: string, width: number, height: number, bottom: number, z: number, bg: Color3, fg: Color3?, glow: boolean?)
	local board = box(ctx, Vector3.new(width, height, 0.6), 0, bottom, z, bg, if glow then M.Neon else M.SmoothPlastic)
	ctx.Kit:Label(board, Enum.NormalId.Front, text, fg or Color3.new(1, 1, 1), glow)
	return board
end

local function poiName(ctx: Ctx, fallback: string): string
	return if ctx.Poi then ctx.Poi.Name else fallback
end

local function gableRoof(ctx: Ctx, width: number, depth: number, height: number, bottom: number, zCenter: number, color: Color3)
	-- İki kama sırt sırta: çatı mahyası X ekseni boyunca
	local half = depth / 2
	wedge(ctx, Vector3.new(width, height, half), 0, bottom, zCenter - half / 2, 0, color, M.Slate)
	wedge(ctx, Vector3.new(width, height, half), 0, bottom, zCenter + half / 2, math.pi, color, M.Slate)
end

local function tree(ctx: Ctx, x: number, z: number, bottom: number)
	local h = ctx.Rng:NextNumber(7, 10)
	cyl(ctx, h, 1.4, x, bottom, z, rgb(110, 80, 54), M.Wood)
	ctx.Kit:Ball(ctx.Model, ctx.Rng:NextNumber(9, 13), ctx.Base * CFrame.new(x, bottom + h + 3, z), rgb(78, 132, 64), M.Grass, { CastShadow = true })
end

-- ===================== STİLLER =====================
local Styles = {}

function Styles.glass_tower(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 60), ctx.Rng
	local stone = pick(rng, PALETTES.stone)
	local glass = pick(rng, PALETTES.glass)
	box(ctx, Vector3.new(w, 14, d), 0, 0, 0, stone, M.Concrete)
	local tw, td = w * rng:NextNumber(0.62, 0.78), d * rng:NextNumber(0.62, 0.78)
	box(ctx, Vector3.new(tw, h - 14, td), 0, 14, 0, glass, M.Glass, { Reflectance = 0.18 })
	local bandEvery = pick(rng, { 16, 20, 24 })
	local y = 14 + bandEvery
	while y < h - 4 do
		box(ctx, Vector3.new(tw + 1.2, 1.2, td + 1.2), 0, y, 0, stone, M.Concrete, { CastShadow = false })
		y += bandEvery
	end
	box(ctx, Vector3.new(tw * 0.6, 10, td * 0.6), 0, h, 0, stone, M.Concrete)
	cyl(ctx, 24, 1, 0, h + 10, 0, rgb(200, 200, 200), M.Metal)
	box(ctx, Vector3.new(w * 0.35, 1, 10), 0, 11, -d / 2 - 4, stone, M.Concrete) -- giriş saçağı
end

function Styles.setback_tower(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 60), ctx.Rng
	local stone = pick(rng, PALETTES.stone)
	local glass = pick(rng, PALETTES.glass)
	local tiers = { { 0.96, 0.45 }, { 0.76, 0.32 }, { 0.54, 0.23 } }
	local bottom = 0
	for i, t in tiers do
		local th = h * t[2]
		local tw, td = w * t[1], d * t[1]
		local isGlass = (i % 2 == 0) ~= (rng:NextNumber() < 0.5)
		box(ctx, Vector3.new(tw, th, td), 0, bottom, 0, if isGlass then glass else stone, if isGlass then M.Glass else M.Concrete, { Reflectance = if isGlass then 0.15 else 0 })
		box(ctx, Vector3.new(tw + 1.5, 2, td + 1.5), 0, bottom + th - 1, 0, stone, M.Concrete, { CastShadow = false })
		if i == 1 then
			-- Ön cephede dikey nervürler
			for _, x in { -tw / 4, tw / 4 } do
				box(ctx, Vector3.new(2, th - 4, 1.2), x, 2, -td / 2 - 0.6, stone, M.Concrete, { CastShadow = false })
			end
		end
		bottom += th
	end
	cyl(ctx, 30, 1.6, 0, bottom, 0, rgb(210, 210, 210), M.Metal)
end

function Styles.office(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 24), ctx.Rng
	local stone = pick(rng, PALETTES.stone)
	local glass = pick(rng, PALETTES.glass)
	box(ctx, Vector3.new(w, h, d), 0, 0, 0, stone, M.Concrete)
	local n = math.clamp(math.floor(w / 12), 2, 6)
	local sw = (w / n) * 0.55
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * (w / n)
		box(ctx, Vector3.new(sw, h - 8, 0.6), x, 5, -d / 2 - 0.25, glass, M.Glass, { CastShadow = false, Reflectance = 0.1 })
		box(ctx, Vector3.new(sw, h - 8, 0.6), x, 5, d / 2 + 0.25, glass, M.Glass, { CastShadow = false, Reflectance = 0.1 })
	end
	box(ctx, Vector3.new(w * 0.3, 5, d * 0.3), w * 0.15, h, 0, rgb(140, 140, 140), M.Metal) -- çatı üniteleri
end

function Styles.apartment_modern(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 20), ctx.Rng
	local body = pick(rng, { rgb(240, 238, 232), rgb(220, 224, 228), rgb(70, 72, 78), rgb(200, 186, 170) })
	local glass = pick(rng, PALETTES.glass)
	box(ctx, Vector3.new(w, h, d), 0, 0, 0, body, M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.7, h - 6, 0.5), 0, 3, -d / 2 - 0.2, glass, M.Glass, { CastShadow = false })
	local floors = math.floor(h / 10)
	for f = 1, floors - 1 do
		box(ctx, Vector3.new(w * 0.78, 0.8, 4), 0, f * 10, -d / 2 - 2, body, M.Concrete)
	end
	box(ctx, Vector3.new(w + 1, 1.5, d + 1), 0, h, 0, body, M.Concrete, { CastShadow = false })
end

function Styles.apartment_brick(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 18), ctx.Rng
	local brick = pick(rng, PALETTES.brick)
	local trim = pick(rng, { rgb(230, 224, 210), rgb(60, 60, 64) })
	box(ctx, Vector3.new(w, h, d), 0, 0, 0, brick, M.Brick)
	local floors = math.min(math.floor(h / 9), 7)
	for f = 0, floors - 1 do
		local y = 3 + f * 9
		box(ctx, Vector3.new(w * 0.82, 3.6, 0.5), 0, y, -d / 2 - 0.2, rgb(60, 80, 96), M.Glass, { CastShadow = false })
		box(ctx, Vector3.new(w * 0.82, 3.6, 0.5), 0, y, d / 2 + 0.2, rgb(60, 80, 96), M.Glass, { CastShadow = false })
	end
	box(ctx, Vector3.new(w + 2, 2, d + 2), 0, h, 0, trim, M.Concrete)
	box(ctx, Vector3.new(6, 8, 1), 0, 0, -d / 2 - 0.5, trim, M.Wood) -- giriş
end

function Styles.hotel(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 40), ctx.Rng
	local body = pick(rng, { rgb(250, 250, 246), rgb(244, 236, 220), rgb(232, 242, 244) })
	local accent = pick(rng, { rgb(64, 196, 214), rgb(255, 160, 120), rgb(110, 170, 220) })
	box(ctx, Vector3.new(w, h, d * 0.8), 0, 0, d * 0.1, body, M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.22, h + 6, 2), 0, 0, -d * 0.3 - 1, accent, M.Glass, { Reflectance = 0.2 })
	local floors = math.floor(h / 10)
	for f = 1, floors - 1, 2 do
		box(ctx, Vector3.new(w * 0.32, 0.8, 4), -w * 0.33, f * 10, -d * 0.3 - 2, body, M.Concrete, { CastShadow = false })
		box(ctx, Vector3.new(w * 0.32, 0.8, 4), w * 0.33, f * 10, -d * 0.3 - 2, body, M.Concrete, { CastShadow = false })
	end
	box(ctx, Vector3.new(w * 0.6, 1.2, 12), 0, 12, -d * 0.3 - 6, accent, M.SmoothPlastic) -- giriş saçağı
	signBoard(ctx, poiName(ctx, "HOTEL"), math.min(w * 0.8, 50), 6, h + 1, -d * 0.3 + 1, rgb(30, 30, 36), rgb(255, 255, 255), true)
end

function Styles.deco_lowrise(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.clamp(ctx.H, 14, 40), ctx.Rng
	local body = pick(rng, PALETTES.pastel)
	local neon = pick(rng, PALETTES.neon)
	box(ctx, Vector3.new(w, h, d), 0, 0, 0, body, M.SmoothPlastic)
	local floors = math.floor(h / 9)
	for f = 1, floors do
		box(ctx, Vector3.new(w + 1, 0.6, 2.4), 0, f * 9 - 2, -d / 2 - 1.2, rgb(255, 255, 255), M.SmoothPlastic, { CastShadow = false })
		box(ctx, Vector3.new(w * 0.7, 3, 0.4), 0, f * 9 - 6, -d / 2 - 0.2, rgb(80, 130, 150), M.Glass, { CastShadow = false })
	end
	box(ctx, Vector3.new(3, h + 6, 2), 0, 0, -d / 2 - 1, rgb(255, 255, 255), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.9, 0.6, 0.4), 0, h - 1.5, -d / 2 - 0.3, neon, M.Neon, { CastShadow = false })
end

function Styles.house_a(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	local hw, hd = math.min(w - 8, 34), math.min(d - 16, 28)
	if hw < 12 or hd < 10 then
		return Styles.house_b(ctx)
	end
	local zc = -d / 2 + 10 + hd / 2 -- ön bahçe 10 stud
	local wall = pick(rng, PALETTES.house)
	local roof = pick(rng, PALETTES.roof)
	box(ctx, Vector3.new(hw, 10, hd), 0, 0, zc, wall, M.Plaster)
	gableRoof(ctx, hw + 2, hd + 2, rng:NextNumber(5, 8), 10, zc, roof)
	box(ctx, Vector3.new(4, 7, 0.4), -hw * 0.15, 0, zc - hd / 2 - 0.2, rgb(110, 76, 52), M.Wood)
	for _, x in { -hw * 0.38, hw * 0.25 } do
		box(ctx, Vector3.new(5, 4, 0.4), x, 3.5, zc - hd / 2 - 0.2, rgb(130, 170, 190), M.Glass, { CastShadow = false })
	end
	-- garaj + araba yolu
	if w - hw > 16 then
		local gx = hw / 2 + 7
		box(ctx, Vector3.new(12, 9, 14), gx, 0, zc - hd / 2 + 7, wall, M.Plaster)
		box(ctx, Vector3.new(10, 7, 0.4), gx, 0, zc - hd / 2 - 0.2, rgb(240, 240, 240), M.SmoothPlastic)
		box(ctx, Vector3.new(10, 0.1, 10), gx, 0, -d / 2 + 5, rgb(120, 120, 118), M.Concrete, { CastShadow = false })
	else
		box(ctx, Vector3.new(4, 0.1, 10), -hw * 0.15, 0, -d / 2 + 5, rgb(200, 196, 188), M.Concrete, { CastShadow = false })
	end
	if rng:NextNumber() < 0.6 then
		tree(ctx, -w / 2 + 5, -d / 2 + 5, 0)
	end
end

function Styles.house_b(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	local hw, hd = math.max(math.min(w - 8, 32), 10), math.max(math.min(d - 14, 26), 10)
	local zc = -d / 2 + 9 + hd / 2
	local wall = pick(rng, { rgb(244, 244, 240), rgb(60, 62, 66), rgb(214, 200, 180), rgb(196, 210, 214) })
	local wood = rgb(150, 108, 72)
	box(ctx, Vector3.new(hw, 9, hd), 0, 0, zc, wall, M.SmoothPlastic)
	box(ctx, Vector3.new(hw * 0.62, 8, hd * 0.7), hw * 0.16, 9, zc + hd * 0.1, if rng:NextNumber() < 0.5 then wood else wall, if rng:NextNumber() < 0.5 then M.WoodPlanks else M.SmoothPlastic)
	box(ctx, Vector3.new(hw * 0.5, 6, 0.4), -hw * 0.18, 1.5, zc - hd / 2 - 0.2, rgb(110, 150, 170), M.Glass, { CastShadow = false })
	box(ctx, Vector3.new(hw + 1, 0.8, hd + 1), 0, 9, zc, rgb(50, 50, 54), M.SmoothPlastic, { CastShadow = false })
	box(ctx, Vector3.new(8, 0.1, 9), hw * 0.3, 0, -d / 2 + 4.5, rgb(120, 120, 118), M.Concrete, { CastShadow = false })
	if rng:NextNumber() < 0.4 then
		tree(ctx, w / 2 - 5, -d / 2 + 4, 0)
	end
end

function Styles.townhouse(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.clamp(ctx.H, 18, 32), ctx.Rng
	local n = math.clamp(math.floor(w / 16), 2, 4)
	local uw = w / n
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * uw
		local color = pick(rng, PALETTES.brick)
		local uh = h + rng:NextNumber(-3, 3)
		box(ctx, Vector3.new(uw - 0.3, uh, d * 0.8), x, 0, d * 0.1, color, M.Brick)
		box(ctx, Vector3.new(uw, 1.4, d * 0.8 + 1), x, uh, d * 0.1, rgb(226, 220, 206), M.Concrete, { CastShadow = false })
		box(ctx, Vector3.new(3.5, 7, 0.4), x, 1.5, -d * 0.3 - 0.2, rgb(40, 48, 60), M.Wood)
		box(ctx, Vector3.new(5, 1.5, 3), x, 0, -d * 0.3 - 1.5, rgb(200, 196, 188), M.Concrete, { CastShadow = false })
	end
end

local function storefrontBase(ctx: Ctx, name: string, accent: Color3, bodyColor: Color3?)
	local w, d, h, rng = ctx.W, ctx.D, math.clamp(ctx.H, 10, 22), ctx.Rng
	local body = bodyColor or pick(rng, PALETTES.stone)
	local depth = d * 0.85
	local z = d / 2 - depth / 2
	box(ctx, Vector3.new(w, h, depth), 0, 0, z, body, M.Concrete)
	local front = z - depth / 2
	box(ctx, Vector3.new(w * 0.82, h * 0.5, 0.5), 0, 0.5, front - 0.2, rgb(150, 190, 210), M.Glass, { CastShadow = false, Transparency = 0.25 })
	box(ctx, Vector3.new(5, 7.5, 0.6), 0, 0, front - 0.4, rgb(60, 60, 64), M.Metal, { CastShadow = false })
	box(ctx, Vector3.new(w * 0.9, 0.5, 5), 0, h * 0.5 + 1.5, front - 2.5, accent, M.Fabric)
	signBoard(ctx, name, math.min(w * 0.8, 40), 3.2, h * 0.5 + 2.6, front - 0.6, rgb(28, 28, 32), accent, true)
	return front, h
end

local POI_ACCENT = {
	supermarket = rgb(80, 180, 90), convenience = rgb(255, 140, 40), grocery = rgb(120, 190, 80),
	restaurant = rgb(200, 60, 60), fastfood = rgb(250, 190, 40), cafe = rgb(150, 100, 70),
	general = rgb(80, 140, 220), garage = rgb(250, 200, 40), marina = rgb(40, 140, 200),
}

function Styles.storefront(ctx: Ctx)
	local accent = if ctx.Poi then POI_ACCENT[ctx.Poi.Type] or rgb(255, 122, 69) else rgb(255, 122, 69)
	if ctx.Poi and ctx.Poi.Type == "supermarket" then
		-- Süpermarket: daha geniş cephe, sepet/el arabası köşesi
		storefrontBase(ctx, poiName(ctx, "MARKET"), accent, rgb(236, 236, 230))
		box(ctx, Vector3.new(8, 3, 4), ctx.W / 2 - 6, 0, -ctx.D / 2 + 3, rgb(160, 160, 166), M.Metal)
	else
		storefrontBase(ctx, poiName(ctx, "SHOP"), accent)
	end
end

function Styles.storefront_plain(ctx: Ctx)
	local rng = ctx.Rng
	local accent = pick(rng, { rgb(200, 70, 80), rgb(60, 140, 120), rgb(70, 100, 180), rgb(220, 160, 50), rgb(130, 80, 160) })
	local front, h = storefrontBase(ctx, pick(rng, DECOR_SHOP_NAMES), accent, pick(rng, PALETTES.pastel))
	if ctx.H > 24 then
		-- üstte daire katları
		box(ctx, Vector3.new(ctx.W * 0.96, ctx.H - h, ctx.D * 0.8), 0, h, ctx.D * 0.1, pick(rng, PALETTES.stone), M.Concrete)
	end
	local _ = front
end

function Styles.mall(ctx: Ctx)
	local w, d, h = ctx.W, ctx.D, math.max(ctx.H, 24)
	box(ctx, Vector3.new(w, h, d), 0, 0, 0, rgb(232, 228, 220), M.Concrete)
	box(ctx, Vector3.new(w * 0.45, h * 0.85, 6), 0, 0, -d / 2 - 2, rgb(120, 170, 200), M.Glass, { Reflectance = 0.2, Transparency = 0.15 })
	box(ctx, Vector3.new(w * 0.6, 1.4, 14), 0, 13, -d / 2 - 7, rgb(255, 122, 69), M.SmoothPlastic)
	signBoard(ctx, poiName(ctx, "MALL"), math.min(w * 0.6, 60), 7, h - 9, -d / 2 - 0.4, rgb(30, 30, 34), rgb(255, 255, 255), true)
	box(ctx, Vector3.new(w * 0.4, 6, d * 0.4), -w * 0.2, h, d * 0.1, rgb(200, 196, 190), M.Concrete)
end

function Styles.parking_garage(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	local levels, lh = 4, 9
	local concrete = rgb(176, 172, 166)
	for i = 0, levels do
		box(ctx, Vector3.new(w, 1, d), 0, i * lh, 0, concrete, M.Concrete)
		if i > 0 then
			box(ctx, Vector3.new(w, 3, 0.8), 0, i * lh + 1, -d / 2 + 0.4, concrete, M.Concrete, { CastShadow = false })
			box(ctx, Vector3.new(w, 3, 0.8), 0, i * lh + 1, d / 2 - 0.4, concrete, M.Concrete, { CastShadow = false })
		end
	end
	for _, x in { -w / 2 + 2, 0, w / 2 - 2 } do
		for _, z in { -d / 2 + 2, 0, d / 2 - 2 } do
			box(ctx, Vector3.new(2, levels * lh, 2), x, 1, z, concrete, M.Concrete, { CastShadow = false })
		end
	end
	local sign = box(ctx, Vector3.new(8, 8, 1), w / 2 - 6, levels * lh + 1, -d / 2, rgb(30, 90, 180), M.SmoothPlastic)
	ctx.Kit:Label(sign, Enum.NormalId.Front, "P", rgb(255, 255, 255), true)
end

function Styles.hospital(ctx: Ctx)
	local w, d, h = ctx.W, ctx.D, math.max(ctx.H, 30)
	box(ctx, Vector3.new(w * 0.92, h, d * 0.55), 0, 0, -d * 0.18, rgb(244, 246, 248), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.5, h * 0.55, d * 0.36), -w * 0.2, 0, d * 0.28, rgb(230, 234, 238), M.SmoothPlastic)
	for f = 1, math.floor(h / 10) - 1 do
		box(ctx, Vector3.new(w * 0.86, 3.5, 0.5), 0, f * 10 - 6, -d * 0.18 - d * 0.275 - 0.2, rgb(110, 160, 190), M.Glass, { CastShadow = false })
	end
	local fz = -d * 0.18 - d * 0.275 - 0.6
	box(ctx, Vector3.new(10, 3, 0.6), 0, h - 9, fz, rgb(220, 40, 50), M.Neon)
	box(ctx, Vector3.new(3, 10, 0.6), 0, h - 12.5, fz, rgb(220, 40, 50), M.Neon)
	box(ctx, Vector3.new(24, 1, 12), w * 0.25, 10, fz - 6, rgb(220, 40, 50), M.SmoothPlastic) -- acil saçağı
	cyl(ctx, 0.6, 22, w * 0.2, h, -d * 0.18, rgb(70, 74, 80), M.Concrete) -- helipad
	signBoard(ctx, poiName(ctx, "HOSPITAL"), math.min(w * 0.6, 50), 5, h - 18, fz, rgb(255, 255, 255), rgb(200, 30, 40), false)
end

function Styles.police(ctx: Ctx)
	local w, d, h = ctx.W, ctx.D, math.max(ctx.H, 16)
	box(ctx, Vector3.new(w * 0.9, h, d * 0.75), 0, 0, d * 0.1, rgb(210, 214, 220), M.Concrete)
	local fz = d * 0.1 - d * 0.375
	box(ctx, Vector3.new(w * 0.9 + 0.4, 2, 0.6), 0, h - 4, fz - 0.3, rgb(30, 70, 160), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.6, 4, 0.5), 0, 2, fz - 0.2, rgb(110, 150, 180), M.Glass, { CastShadow = false })
	signBoard(ctx, poiName(ctx, "POLICE"), math.min(w * 0.6, 36), 3.5, h - 9, fz - 0.4, rgb(30, 70, 160), rgb(255, 255, 255), false)
	cyl(ctx, 30, 0.6, -w * 0.4, 0, fz - 6, rgb(220, 220, 220), M.Metal)
	box(ctx, Vector3.new(0.2, 5, 8), -w * 0.4, 24, fz - 10, rgb(30, 70, 160), M.Fabric)
end

function Styles.cinema(ctx: Ctx)
	local w, d, h = ctx.W, ctx.D, math.max(ctx.H, 20)
	box(ctx, Vector3.new(w, h, d * 0.85), 0, 0, d * 0.075, rgb(60, 40, 60), M.Concrete)
	local fz = d * 0.075 - d * 0.425
	box(ctx, Vector3.new(w * 0.9, 6, 4), 0, 10, fz - 2, rgb(30, 20, 30), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.9, 0.5, 4.2), 0, 16, fz - 2, rgb(255, 210, 90), M.Neon, { CastShadow = false })
	signBoard(ctx, poiName(ctx, "CINEMA"), math.min(w * 0.8, 40), 5, h - 7, fz - 0.4, rgb(120, 20, 40), rgb(255, 230, 160), true)
	box(ctx, Vector3.new(w * 0.5, 8, 0.5), 0, 0.5, fz - 0.2, rgb(40, 40, 50), M.Glass, { CastShadow = false })
end

function Styles.arcade(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 14), ctx.Rng
	box(ctx, Vector3.new(w, h, d * 0.85), 0, 0, d * 0.075, rgb(24, 24, 36), M.SmoothPlastic)
	local fz = d * 0.075 - d * 0.425
	for i, c in PALETTES.neon do
		box(ctx, Vector3.new(w * 0.9, 0.5, 0.4), 0, 3 + i * 2.2, fz - 0.3, c, M.Neon, { CastShadow = false })
	end
	signBoard(ctx, poiName(ctx, "ARCADE"), math.min(w * 0.8, 36), 4, h - 6, fz - 0.6, rgb(10, 10, 20), pick(rng, PALETTES.neon), true)
end

function Styles.dealership(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w * 0.9, 14, d * 0.55), 0, 0, d * 0.15, rgb(150, 190, 210), M.Glass, { Transparency = 0.3, Reflectance = 0.2 })
	box(ctx, Vector3.new(w * 0.95, 1.2, d * 0.62), 0, 14, d * 0.15, rgb(240, 240, 240), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.9, 0.12, d * 0.35), 0, 0, -d * 0.3, rgb(90, 90, 96), M.Asphalt, { CastShadow = false }) -- sergi alanı
	local pylon = box(ctx, Vector3.new(14, 20, 1.5), w * 0.4, 0, -d / 2 + 2, rgb(30, 30, 36), M.SmoothPlastic)
	ctx.Kit:Label(pylon, Enum.NormalId.Front, poiName(ctx, "MOTORS"), rgb(255, 122, 69), true)
end

function Styles.garage(ctx: Ctx)
	local w, d, h = ctx.W, ctx.D, math.max(ctx.H, 12)
	box(ctx, Vector3.new(w * 0.92, h, d * 0.8), 0, 0, d * 0.1, rgb(150, 154, 160), M.CorrodedMetal)
	local fz = d * 0.1 - d * 0.4
	for _, x in { -w * 0.22, w * 0.22 } do
		box(ctx, Vector3.new(w * 0.3, 9, 0.4), x, 0, fz - 0.2, rgb(200, 200, 196), M.DiamondPlate)
	end
	signBoard(ctx, poiName(ctx, "GARAGE"), math.min(w * 0.7, 30), 3, 10, fz - 0.4, rgb(250, 200, 40), rgb(20, 20, 20), false)
end

function Styles.gas_station(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	local accent = rgb(220, 60, 50)
	local cw, cd = math.min(w * 0.6, 70), math.min(d * 0.45, 40)
	local cz = -d / 2 + cd / 2 + 6
	box(ctx, Vector3.new(cw, 1.6, cd), 0, 14, cz, rgb(245, 245, 245), M.SmoothPlastic)
	box(ctx, Vector3.new(cw + 0.2, 0.8, cd + 0.2), 0, 14.4, cz, accent, M.Neon, { CastShadow = false })
	for _, x in { -cw / 2 + 2, cw / 2 - 2 } do
		for _, z in { cz - cd / 2 + 2, cz + cd / 2 - 2 } do
			box(ctx, Vector3.new(1.5, 14, 1.5), x, 0, z, rgb(230, 230, 230), M.Metal, { CastShadow = false })
		end
	end
	for _, x in { -cw / 4, cw / 4 } do
		box(ctx, Vector3.new(4, 0.6, cd * 0.6), x, 0, cz, rgb(200, 200, 200), M.Concrete, { CastShadow = false })
		box(ctx, Vector3.new(2.4, 5.5, 3), x, 0.6, cz, accent, M.SmoothPlastic)
	end
	-- market binası
	local sw, sd = math.min(w * 0.45, 40), math.min(d * 0.3, 24)
	local sz = d / 2 - sd / 2 - 3
	box(ctx, Vector3.new(sw, 12, sd), w / 2 - sw / 2 - 3, 0, sz, rgb(240, 238, 232), M.SmoothPlastic)
	box(ctx, Vector3.new(sw * 0.7, 6, 0.5), w / 2 - sw / 2 - 3, 0.5, sz - sd / 2 - 0.2, rgb(150, 190, 210), M.Glass, { CastShadow = false })
	local pylon = box(ctx, Vector3.new(10, 22, 1.2), -w / 2 + 7, 0, -d / 2 + 4, rgb(30, 30, 36), M.SmoothPlastic)
	ctx.Kit:Label(pylon, Enum.NormalId.Front, poiName(ctx, "FUEL"), rgb(255, 255, 255), true)
end

function Styles.warehouse(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 16), ctx.Rng
	local color = pick(rng, PALETTES.industrial)
	box(ctx, Vector3.new(w, h, d * 0.85), 0, 0, d * 0.075, color, M.CorrodedMetal)
	box(ctx, Vector3.new(w + 1, 1, d * 0.85 + 1), 0, h, d * 0.075, rgb(90, 92, 96), M.Metal, { CastShadow = false })
	local fz = d * 0.075 - d * 0.425
	local doors = math.clamp(math.floor(w / 20), 2, 5)
	for i = 1, doors do
		local x = -w / 2 + (i - 0.5) * (w / doors)
		box(ctx, Vector3.new(10, 11, 0.4), x, 0, fz - 0.2, rgb(70, 72, 76), M.DiamondPlate, { CastShadow = false })
	end
	box(ctx, Vector3.new(w * 0.9, 1.4, 6), 0, 0, fz - 3, rgb(150, 150, 146), M.Concrete, { CastShadow = false })
end

function Styles.factory(ctx: Ctx)
	local w, d, h, rng = ctx.W, ctx.D, math.max(ctx.H, 20), ctx.Rng
	local color = pick(rng, PALETTES.industrial)
	box(ctx, Vector3.new(w * 0.62, h, d * 0.7), -w * 0.17, 0, 0, color, M.CorrodedMetal)
	box(ctx, Vector3.new(w * 0.3, h * 0.6, d * 0.45), w * 0.3, 0, -d * 0.1, rgb(160, 156, 150), M.Concrete)
	for i, x in { -w * 0.35, -w * 0.1 } do
		cyl(ctx, h * 2 + i * 6, 5, x, 0, d * 0.25, rgb(150, 70, 56), M.Brick)
	end
	cyl(ctx, 18, 14, w * 0.32, 0, d * 0.3, rgb(210, 210, 206), M.Metal)
	box(ctx, Vector3.new(w * 0.3, 1.6, 1.6), w * 0.1, h * 0.7, d * 0.3, rgb(140, 140, 140), M.Metal, { CastShadow = false })
end

function Styles.construction(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	box(ctx, Vector3.new(w, 0.3, d), 0, 0, 0, rgb(150, 118, 84), M.Ground, { CastShadow = false })
	local floors = 4
	local fw, fd = w * 0.5, d * 0.5
	for f = 0, floors - 1 do
		box(ctx, Vector3.new(fw, 1, fd), 0, f * 10 + 0.3, 0, rgb(170, 168, 160), M.Concrete)
	end
	for _, x in { -fw / 2 + 1, fw / 2 - 1 } do
		for _, z in { -fd / 2 + 1, fd / 2 - 1 } do
			box(ctx, Vector3.new(1.5, floors * 10 + 4, 1.5), x, 0.3, z, rgb(170, 168, 160), M.Concrete, { CastShadow = false })
		end
	end
	-- kule vinç
	local mx, mz = w * 0.36, -d * 0.3
	local mast = 90
	box(ctx, Vector3.new(3, mast, 3), mx, 0, mz, rgb(250, 200, 40), M.Metal)
	box(ctx, Vector3.new(70, 2.5, 2.5), mx - 25, mast, mz, rgb(250, 200, 40), M.Metal)
	box(ctx, Vector3.new(6, 4, 6), mx + 12, mast - 4, mz, rgb(110, 110, 110), M.Concrete)
	box(ctx, Vector3.new(4, 4, 4), mx, mast - 6, mz - 3, rgb(240, 240, 240), M.SmoothPlastic)
	-- çit
	box(ctx, Vector3.new(w, 6, 0.4), 0, 0, -d / 2, rgb(80, 120, 90), M.Fabric, { Transparency = 0.2 })
	local _ = rng
end

function Styles.port_yard(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	box(ctx, Vector3.new(w, 0.2, d), 0, 0, 0, rgb(120, 118, 112), M.Concrete, { CastShadow = false })
	-- konteyner yığınları (8.5 x 9 x 40 benzeri)
	local rows = math.max(1, math.floor(d / 12))
	for r = 0, rows - 1 do
		local z = -d / 2 + 6 + r * 12
		local stack = rng:NextInteger(1, 3)
		for s = 0, stack - 1 do
			box(ctx, Vector3.new(math.min(w * 0.8, 40), 8.5, 8), rng:NextNumber(-3, 3), s * 8.5 + 0.2, z, pick(rng, PALETTES.container), M.CorrodedMetal)
		end
	end
end

function Styles.farm(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	-- tarlalar: ekin sıraları
	local fieldW, fieldD = w * 0.62, d * 0.9
	local fx = w / 2 - fieldW / 2 - 4
	local crop = pick(rng, { { rgb(196, 176, 80), rgb(150, 120, 70) }, { rgb(110, 160, 70), rgb(120, 96, 64) }, { rgb(220, 190, 90), rgb(170, 140, 90) } })
	local rows = 10
	local rowD = fieldD / rows
	for r = 0, rows - 1 do
		local z = -fieldD / 2 + (r + 0.5) * rowD
		box(ctx, Vector3.new(fieldW, if r % 2 == 0 then 1.4 else 0.3, rowD), fx, 0, z, crop[(r % 2) + 1], if r % 2 == 0 then M.Grass else M.Ground, { CastShadow = false })
	end
	-- çiftlik evi
	local hx, hz = -w / 2 + 30, -d / 2 + 30
	box(ctx, Vector3.new(30, 12, 22), hx, 0, hz, rgb(240, 236, 224), M.WoodPlanks)
	gableRoof(ctx, 32, 24, 7, 12, hz, rgb(96, 70, 60))
	-- ahır
	local bx, bz = -w / 2 + 34, -d / 2 + 90
	box(ctx, Vector3.new(36, 18, 28), bx, 0, bz, rgb(170, 52, 44), M.WoodPlanks)
	gableRoof(ctx, 38, 30, 10, 18, bz, rgb(70, 74, 82))
	box(ctx, Vector3.new(12, 14, 0.5), bx, 0, bz - 14.2, rgb(240, 236, 224), M.WoodPlanks)
	-- silolar
	for i = 0, 1 do
		local sx = -w / 2 + 64 + i * 14
		cyl(ctx, 34, 11, sx, 0, bz, rgb(200, 204, 208), M.Metal)
		ctx.Kit:Ball(ctx.Model, 11, ctx.Base * CFrame.new(sx, 34, bz), rgb(200, 204, 208), M.Metal)
	end
	-- çit (ön)
	box(ctx, Vector3.new(w, 0.5, 0.5), 0, 2.5, -d / 2 + 1, rgb(150, 116, 80), M.Wood, { CastShadow = false })
	box(ctx, Vector3.new(w, 0.5, 0.5), 0, 4.5, -d / 2 + 1, rgb(150, 116, 80), M.Wood, { CastShadow = false })
	-- traktör izi / toprak yol
	box(ctx, Vector3.new(8, 0.15, d * 0.8), -w / 2 + 60, 0, 0, rgb(150, 120, 84), M.Ground, { CastShadow = false })
end

function Styles.lighthouse(ctx: Ctx)
	local h = math.max(ctx.H, 50)
	cyl(ctx, 6, 26, 0, 0, 0, rgb(200, 196, 188), M.Concrete)
	local seg = (h - 6) / 4
	for i = 0, 3 do
		cyl(ctx, seg, 14 - i * 1.2, 0, 6 + i * seg, 0, if i % 2 == 0 then rgb(245, 245, 245) else rgb(200, 50, 50), M.SmoothPlastic)
	end
	local lamp = cyl(ctx, 6, 9, 0, h, 0, rgb(255, 240, 180), M.Neon)
	ctx.Kit:Ball(ctx.Model, 9, ctx.Base * CFrame.new(0, h + 7, 0), rgb(200, 50, 50), M.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 3
	light.Color = rgb(255, 230, 170)
	light.Shadows = false
	light.Parent = lamp
	ctx.Kit:Tag(lamp, "StreetLamp")
	box(ctx, Vector3.new(16, 10, 12), 18, 0, 0, rgb(245, 245, 245), M.SmoothPlastic) -- bekçi evi
end

function Styles.marina_club(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w * 0.8, 12, d * 0.6), 0, 0, -d * 0.1, rgb(250, 250, 248), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.86, 1, d * 0.68), 0, 12, -d * 0.1, rgb(40, 140, 200), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.8, 0.6, d * 0.3), 0, 0, d * 0.34, rgb(150, 112, 76), M.WoodPlanks, { CastShadow = false })
	signBoard(ctx, poiName(ctx, "MARINA"), math.min(w * 0.6, 40), 4, 13, -d * 0.4 - 0.4, rgb(40, 140, 200), rgb(255, 255, 255), true)
end

function Styles.park(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w, 0.1, d), 0, 0, 0, rgb(98, 150, 76), M.Grass, { CastShadow = false })
	box(ctx, Vector3.new(6, 0.12, d), 0, 0, 0, rgb(206, 196, 176), M.Pavement, { CastShadow = false })
	box(ctx, Vector3.new(w, 0.12, 6), 0, 0, 0, rgb(206, 196, 176), M.Pavement, { CastShadow = false })
end

function Styles.plaza(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w, 0.1, d), 0, 0, 0, rgb(226, 218, 200), M.Slate, { CastShadow = false })
	ctx.Kit:Cylinder(ctx.Model, 0.12, math.min(w, d) * 0.8, ctx.Base * CFrame.new(0, 0.06, 0), rgb(196, 160, 130), M.Pavement, { CastShadow = false })
end

function Styles.parking(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w, 0.1, d), 0, 0, 0, rgb(70, 72, 76), M.Asphalt, { CastShadow = false })
	local n = math.clamp(math.floor(w / 10), 2, 10)
	for i = 1, n - 1 do
		box(ctx, Vector3.new(0.3, 0.12, d * 0.35), -w / 2 + i * (w / n), 0, -d * 0.25, rgb(230, 230, 226), M.SmoothPlastic, { CastShadow = false })
		box(ctx, Vector3.new(0.3, 0.12, d * 0.35), -w / 2 + i * (w / n), 0, d * 0.25, rgb(230, 230, 226), M.SmoothPlastic, { CastShadow = false })
	end
end

-- ===================== GENİŞLETİLMİŞ HARİTA STİLLERİ (Aşama 3) =====================

-- Çok uzun kutuları Roblox'un 2048 stud parça sınırına göre X ekseninde böler
local function longBox(ctx: Ctx, size: Vector3, x: number, bottom: number, z: number, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	local maxLen = 1900
	if size.X <= maxLen then
		return box(ctx, size, x, bottom, z, color, material, props)
	end
	local pieces = math.ceil(size.X / maxLen)
	local len = size.X / pieces
	for i = 0, pieces - 1 do
		box(ctx, Vector3.new(len, size.Y, size.Z), x - size.X / 2 + len * (i + 0.5), bottom, z, color, material, props)
	end
	return nil
end

function Styles.runway(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	local white = rgb(236, 236, 230)
	longBox(ctx, Vector3.new(w, 0.3, d), 0, 0, 0, rgb(64, 66, 70), M.Asphalt, { CastShadow = false })
	-- orta çizgi kesikleri
	local x = -w / 2 + 80
	while x < w / 2 - 80 do
		box(ctx, Vector3.new(30, 0.08, 1), x, 0.3, 0, white, M.SmoothPlastic, { CastShadow = false })
		x += 70
	end
	-- eşik çizgileri (iki uç)
	for _, sx in { -1, 1 } do
		for k = -3, 3 do
			box(ctx, Vector3.new(40, 0.08, 2.5), sx * (w / 2 - 30), 0.3, k * (d / 8), white, M.SmoothPlastic, { CastShadow = false })
		end
	end
	longBox(ctx, Vector3.new(w, 0.08, 0.8), 0, 0.3, d / 2 - 2, white, M.SmoothPlastic, { CastShadow = false })
	longBox(ctx, Vector3.new(w, 0.08, 0.8), 0, 0.3, -d / 2 + 2, white, M.SmoothPlastic, { CastShadow = false })
end

function Styles.taxiway(ctx: Ctx)
	longBox(ctx, Vector3.new(ctx.W, 0.3, ctx.D), 0, 0, 0, rgb(72, 74, 78), M.Asphalt, { CastShadow = false })
	longBox(ctx, Vector3.new(ctx.W, 0.08, 0.6), 0, 0.3, 0, rgb(240, 200, 60), M.SmoothPlastic, { CastShadow = false })
end

function Styles.apron(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w, 0.3, d), 0, 0, 0, rgb(176, 174, 168), M.Concrete, { CastShadow = false })
	for i = 1, 4 do
		local x = -w / 2 + i * (w / 5)
		box(ctx, Vector3.new(0.6, 0.08, d * 0.7), x, 0.3, 0, rgb(240, 200, 60), M.SmoothPlastic, { CastShadow = false })
	end
end

function Styles.terminal(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	box(ctx, Vector3.new(w, 26, d * 0.7), 0, 0, d * 0.1, rgb(226, 228, 232), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.9, 18, 1), 0, 2, d * 0.1 - d * 0.35 - 0.5, rgb(110, 160, 190), M.Glass, { Reflectance = 0.25, Transparency = 0.2 })
	box(ctx, Vector3.new(w + 8, 2, d * 0.85), 0, 26, d * 0.05, rgb(250, 250, 250), M.SmoothPlastic)
	box(ctx, Vector3.new(w * 0.7, 1.2, 16), 0, 12, -d / 2 + 4, rgb(255, 122, 69), M.SmoothPlastic) -- bırakma saçağı
	signBoard(ctx, poiName(ctx, "AIRPORT"), math.min(w * 0.6, 120), 8, 18, -d / 2 + 11.5, rgb(30, 30, 34), rgb(255, 255, 255), true)
	-- yolcu köprüleri (arka taraf, apron yönü)
	for _, x in { -w * 0.3, 0, w * 0.3 } do
		box(ctx, Vector3.new(6, 6, 40), x, 10, d * 0.45 + 20, rgb(200, 202, 206), M.Metal)
	end
end

function Styles.hangar(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	local color = pick(ctx.Rng, { rgb(200, 204, 210), rgb(170, 176, 186), rgb(214, 210, 196) })
	box(ctx, Vector3.new(w, 30, d), 0, 0, 0, color, M.CorrodedMetal)
	gableRoof(ctx, w + 2, d + 2, 10, 30, 0, rgb(120, 124, 130))
	box(ctx, Vector3.new(w * 0.85, 26, 0.6), 0, 0, -d / 2 - 0.3, rgb(90, 94, 100), M.DiamondPlate)
	local sign = box(ctx, Vector3.new(12, 8, 0.5), 0, 31, -d / 2 - 0.6, rgb(30, 90, 180), M.SmoothPlastic)
	ctx.Kit:Label(sign, Enum.NormalId.Front, "H" .. ctx.Lot.Id % 10, rgb(255, 255, 255), false)
end

function Styles.control_tower(ctx: Ctx)
	cyl(ctx, 70, 10, 0, 0, 0, rgb(226, 228, 232), M.Concrete)
	cyl(ctx, 12, 22, 0, 70, 0, rgb(80, 130, 160), M.Glass)
	cyl(ctx, 2, 26, 0, 82, 0, rgb(240, 240, 240), M.SmoothPlastic)
	cyl(ctx, 16, 0.8, 0, 84, 0, rgb(200, 60, 60), M.Metal)
	box(ctx, Vector3.new(30, 12, 24), 0, 0, 16, rgb(214, 216, 220), M.SmoothPlastic)
end

function Styles.motel(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	local body = pick(rng, PALETTES.pastel)
	local depth = math.min(d * 0.4, 30)
	local z = d / 2 - depth / 2 - 4
	box(ctx, Vector3.new(w * 0.92, 20, depth), 0, 0, z, body, M.Plaster)
	box(ctx, Vector3.new(w * 0.92, 0.8, 5), 0, 10, z - depth / 2 - 2.5, rgb(240, 240, 236), M.Concrete) -- üst kat geçidi
	local rooms = math.clamp(math.floor(w / 12), 4, 10)
	for i = 1, rooms do
		local x = -w * 0.46 + (i - 0.5) * (w * 0.92 / rooms)
		box(ctx, Vector3.new(3.5, 7, 0.4), x, 0, z - depth / 2 - 0.2, rgb(70, 100, 140), M.Wood, { CastShadow = false })
		box(ctx, Vector3.new(3.5, 7, 0.4), x, 10.8, z - depth / 2 - 0.2, rgb(70, 100, 140), M.Wood, { CastShadow = false })
	end
	box(ctx, Vector3.new(w * 0.8, 0.12, d * 0.4), 0, 0, -d * 0.18, rgb(70, 72, 76), M.Asphalt, { CastShadow = false })
	local pylon = box(ctx, Vector3.new(12, 26, 1.2), -w / 2 + 8, 0, -d / 2 + 3, rgb(30, 30, 36), M.SmoothPlastic)
	ctx.Kit:Label(pylon, Enum.NormalId.Front, poiName(ctx, "MOTEL"), pick(rng, PALETTES.neon), true)
end

function Styles.golf(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	box(ctx, Vector3.new(w, 0.12, d), 0, 0, 0, rgb(96, 160, 80), M.Grass, { CastShadow = false })
	for k = 0, 3 do
		local x = -w / 2 + (k + 0.5) * (w / 4)
		box(ctx, Vector3.new(w / 5, 0.16, d * 0.7), x, 0, 0, rgb(124, 186, 96), M.Grass, { CastShadow = false })
		cyl(ctx, 0.2, 18, x, 0.12, -d * 0.28, rgb(140, 200, 110), M.Grass)
		cyl(ctx, 10, 0.3, x, 0.12, -d * 0.28, rgb(240, 240, 240), M.Metal)
		box(ctx, Vector3.new(0.1, 1.6, 2.4), x, 8.5, -d * 0.28 + 1.2, rgb(220, 40, 50), M.Fabric, { CastShadow = false })
		cyl(ctx, 0.2, rng:NextNumber(10, 16), x + w / 14, 0.12, d * 0.1, rgb(226, 206, 156), M.Sand)
	end
	box(ctx, Vector3.new(40, 12, 24), w / 2 - 30, 0, d / 2 - 20, rgb(250, 250, 246), M.SmoothPlastic) -- kulüp binası
	box(ctx, Vector3.new(44, 1, 28), w / 2 - 30, 12, d / 2 - 20, rgb(40, 120, 80), M.SmoothPlastic)
end

function Styles.villa(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	local hw, hd = math.min(w * 0.7, 46), math.min(d * 0.45, 40)
	local zc = d / 2 - hd / 2 - 6
	box(ctx, Vector3.new(hw, 11, hd), 0, 0, zc, rgb(252, 250, 244), M.Plaster)
	box(ctx, Vector3.new(hw * 0.6, 9, hd * 0.6), hw * 0.15, 11, zc + hd * 0.1, rgb(252, 250, 244), M.Plaster)
	box(ctx, Vector3.new(hw + 2, 0.8, hd + 2), 0, 11, zc, pick(rng, { rgb(200, 120, 80), rgb(60, 140, 160) }), M.SmoothPlastic)
	box(ctx, Vector3.new(hw * 0.7, 6, 0.4), 0, 2, zc - hd / 2 - 0.2, rgb(130, 180, 200), M.Glass, { CastShadow = false })
	-- havuz
	box(ctx, Vector3.new(hw * 0.6, 0.2, 14), 0, 0, zc - hd / 2 - 12, rgb(240, 240, 236), M.Concrete, { CastShadow = false })
	box(ctx, Vector3.new(hw * 0.55, 0.25, 12), 0, 0.05, zc - hd / 2 - 12, rgb(60, 180, 220), M.Glass, { Transparency = 0.2, CastShadow = false })
end

function Styles.stilt_house(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	local hw, hd = math.min(w * 0.6, 34), math.min(d * 0.5, 28)
	local wood = pick(rng, { rgb(130, 96, 66), rgb(110, 86, 64), rgb(150, 120, 88) })
	for _, x in { -hw / 2 + 1, hw / 2 - 1 } do
		for _, z in { -hd / 2 + 1, hd / 2 - 1 } do
			box(ctx, Vector3.new(1.2, 8, 1.2), x, -2, z, rgb(90, 70, 50), M.Wood, { CastShadow = false })
		end
	end
	box(ctx, Vector3.new(hw + 6, 0.8, hd + 6), 0, 6, 0, wood, M.WoodPlanks)
	box(ctx, Vector3.new(hw, 9, hd), 0, 6.8, 0, pick(rng, { rgb(200, 210, 200), rgb(226, 214, 190), rgb(180, 200, 210) }), M.WoodPlanks)
	gableRoof(ctx, hw + 2, hd + 2, 5, 15.8, 0, rgb(80, 90, 96))
	box(ctx, Vector3.new(4, 0.6, d / 2), 0, 3, -d / 4 - hd / 4, wood, M.WoodPlanks, { CastShadow = false }) -- iskele/rampa
end

function Styles.cabin(ctx: Ctx)
	local w, d, rng = ctx.W, ctx.D, ctx.Rng
	local hw, hd = math.min(w * 0.6, 30), math.min(d * 0.5, 24)
	local zc = d * 0.05
	box(ctx, Vector3.new(hw, 10, hd), 0, 0, zc, pick(rng, { rgb(122, 86, 56), rgb(140, 100, 66) }), M.WoodPlanks)
	gableRoof(ctx, hw + 3, hd + 3, 7, 10, zc, rgb(70, 74, 70))
	box(ctx, Vector3.new(3, 14, 3), hw / 2 - 3, 4, zc + hd / 4, rgb(120, 116, 110), M.Cobblestone)
	box(ctx, Vector3.new(hw, 0.6, 6), 0, 0.8, zc - hd / 2 - 3, rgb(110, 80, 54), M.WoodPlanks, { CastShadow = false })
	box(ctx, Vector3.new(4, 7, 0.4), 0, 1, zc - hd / 2 - 0.2, rgb(80, 56, 40), M.Wood)
	if ctx.Poi then
		signBoard(ctx, poiName(ctx, "RANGER"), 14, 2.5, 7.5, zc - hd / 2 - 0.6, rgb(40, 90, 60), rgb(255, 255, 255), false)
	end
end

function Styles.lodge(ctx: Ctx)
	local w, d = ctx.W, ctx.D
	local hw, hd = math.min(w * 0.8, 70), math.min(d * 0.6, 40)
	box(ctx, Vector3.new(hw, 18, hd), 0, 0, 0, rgb(130, 94, 62), M.WoodPlanks)
	gableRoof(ctx, hw + 4, hd + 4, 10, 18, 0, rgb(64, 70, 66))
	box(ctx, Vector3.new(hw * 0.6, 7, 0.4), 0, 2, -hd / 2 - 0.2, rgb(150, 190, 200), M.Glass, { CastShadow = false })
	box(ctx, Vector3.new(4, 24, 4), -hw / 2 + 4, 0, hd / 4, rgb(120, 116, 110), M.Cobblestone)
	signBoard(ctx, poiName(ctx, "LODGE"), math.min(hw * 0.6, 34), 4, 11, -hd / 2 - 0.6, rgb(50, 40, 30), rgb(255, 230, 180), false)
end

function Styles.observatory(ctx: Ctx)
	cyl(ctx, 16, 30, 0, 0, 0, rgb(226, 226, 222), M.Concrete)
	ctx.Kit:Ball(ctx.Model, 30, ctx.Base * CFrame.new(0, 16, 0), rgb(240, 240, 244), M.Metal)
	box(ctx, Vector3.new(4, 14, 16), 0, 16, -6, rgb(40, 44, 54), M.SmoothPlastic, { CastShadow = false })
	box(ctx, Vector3.new(26, 10, 18), 26, 0, 0, rgb(214, 214, 210), M.Concrete)
	signBoard(ctx, poiName(ctx, "OBSERVATORY"), 22, 3, 6, -15.4, rgb(30, 40, 70), rgb(255, 255, 255), false)
end

BuildingBuilder.Styles = Styles

-- ===================== İNŞA =====================
function BuildingBuilder.Build(kit, world: Instance)
	local data = MapDefinitions.GetData()
	local buildings = kit:Folder(world, "Buildings")
	local districtFolders = {}
	local built, failed = 0, 0

	for _, lot in data.Lots do
		local styleFn = Styles[lot.Style]
		if not styleFn then
			warn("[WorldGen] Bilinmeyen bina stili:", lot.Style)
			failed += 1
			continue
		end
		local folder = districtFolders[lot.District]
		if not folder then
			folder = kit:Folder(buildings, lot.District)
			districtFolders[lot.District] = folder
		end
		local model = Instance.new("Model")
		model.Name = string.format("%s_%d", lot.Style, lot.Id)
		model:SetAttribute("LotId", lot.Id)
		model:SetAttribute("Style", lot.Style)
		if lot.PoiId then
			model:SetAttribute("PoiId", lot.PoiId)
		end
		local ctx: Ctx = {
			Kit = kit,
			Model = model,
			Base = CFrame.new(lot.Center.X, lot.BaseY, lot.Center.Z) * CFrame.Angles(0, math.rad(lot.Rotation), 0),
			W = lot.Width,
			D = lot.Depth,
			H = lot.Height,
			Rng = Random.new(lot.Seed),
			Lot = lot,
			Poi = if lot.PoiId then data.POIById[lot.PoiId] else nil,
		}
		local ok, err = pcall(styleFn, ctx)
		if ok then
			built += 1
			model.Parent = folder
		else
			failed += 1
			warn("[WorldGen] Bina üretilemedi:", lot.Style, lot.Id, err)
			model:Destroy()
		end
	end
	return built, failed
end

return BuildingBuilder
