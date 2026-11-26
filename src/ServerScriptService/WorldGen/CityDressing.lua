-- CityDressing: şehir cepheleri ve atmosferi (Şehir genişletme, aşama 3). BuildingBuilder stilleri bunu çağırır.
--
-- Kurallar:
--   * Binaların yeri, boyutu, gövdesi ve kapısı DEĞİŞMEZ; burada sadece cepheye/çatıya eklenen ayrıntı ve tabelalar var.
--     Ayrıntılar binanın kendi rastgele sayı üretecini KULLANMAZ (ayrı tohum) → mevcut renkler aynı kalır.
--   * Her parça bir ad taşır (Sign, Awning, Blade, Vitrine, AC, ...): Studio'da bulunur, çevrimdışı test tanır.
--   * Yere yakın (8 stud altı) parçalar arsanın içinde; yalnız arsayı tamamen kaplayan Centro binalarında zemin kat
--     vitrini/tabelası cephe camıyla aynı zarfta (en fazla 0.6 stud önde). 8 stud üstü (saçak, klima, neon kanat)
--     binanın mevcut cephe zarfını (ör. art deco saçakları 2.4 stud) aşmaz. Kapı önü ve yürüme yolu boş: yere yakın
--     parçalar kapı koridoruna girmez. Hepsini tools/test_city_facades.py denetler.
--   * Gece: "NightGlow" etiketli parçalar gece NightColor + Neon olur, yazıları parlar; "ShopWindow" camları gece sıcak
--     ışık verir. Geçişi istemci yapar (CityLightsController); sunucu her zaman gündüz hâlini üretir.
--
-- Yerel koordinat (BuildingBuilder ile aynı): bina önü −Z (yola), genişlik X, zemin y = 0.

local CityDressing = {}

local M = Enum.Material
local rgb = Color3.fromRGB

local DARK = rgb(34, 36, 40)
local METAL = rgb(120, 124, 130)
local WARM = rgb(255, 214, 150) -- vitrin gece ışığı
local GLASS = rgb(150, 190, 210)

local function c3(t): Color3
	return rgb(t[1], t[2], t[3])
end

-- Gündüz rengini gece için biraz canlandır (Neon zaten parlak; çok koyu renkler gece kaybolmasın)
local function nightOf(color: Color3): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.min(s * 1.05, 1), math.max(v, 0.55))
end

-- ===== İlkel yardımcılar =====
local function part(ctx, name: string, size: Vector3, x: number, bottom: number, z: number, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	local p = props or {}
	p.Name = name
	if p.CastShadow == nil then
		p.CastShadow = false
	end
	return ctx.Kit:Box(ctx.Model, size, ctx.Base * CFrame.new(x, bottom + size.Y / 2, z), color, material, p)
end

local function cylinder(ctx, name: string, height: number, diameter: number, x: number, bottom: number, z: number, color: Color3, material: Enum.Material?, props: { [string]: any }?)
	local p = props or {}
	p.Name = name
	return ctx.Kit:Cylinder(ctx.Model, height, diameter, ctx.Base * CFrame.new(x, bottom + height / 2, z), color, material, p)
end

-- Gece parlayan parça (tabela yüzü, neon şerit, reklam panosu)
local function glow(ctx, p: BasePart, nightColor: Color3): BasePart
	p:SetAttribute("NightColor", nightColor)
	ctx.Kit:Tag(p, "NightGlow")
	return p
end

-- Gece parlayınca güzel duran (yeterince açık / doygun) renk mi? Koyu ya da gri yüzey parlatılırsa gri bir leke olur
-- ve üstündeki yazı okunmaz; o tabelalarda yüzey karanlık kalır, yazı parlar.
local function glowsWell(color: Color3): boolean
	local _, s, v = color:ToHSV()
	return v >= 0.5 and (s >= 0.3 or v >= 0.85)
end

-- Yazının gece rengi: aynı ton, tam parlaklık (koyu yazı gece karanlıkta kaybolmasın)
local function lightOf(color: Color3): Color3
	local h, s, _ = color:ToHSV()
	return Color3.fromHSV(h, s * 0.55, 1)
end

-- Yazı: gündüz ışıktan etkilenir (normal boya), gece parlar (CityLightsController LightInfluence = 0 yapar).
-- nightColor: gece yazı rengi (verilmezse gündüzkü renk).
local function text(ctx, p: BasePart, face: Enum.NormalId, value: string, color: Color3, font: string?, nightColor: Color3?)
	ctx.Kit:Label(p, face, value, color, false, font)
	ctx.Kit:Tag(p, "NightText")
	if nightColor then
		p:SetAttribute("NightTextColor", nightColor)
	end
end

-- Tabela yüzü: rengi gece parlamaya uygunsa parlar; değilse karanlık kalır ve yazı açık renkte parlar
local function signFace(ctx, p: BasePart, face: Enum.NormalId, value: string, bg: Color3, fg: Color3, font: string?)
	if glowsWell(bg) then
		glow(ctx, p, nightOf(bg))
		text(ctx, p, face, value, fg, font)
	else
		text(ctx, p, face, value, fg, font, lightOf(fg))
	end
end

-- Ayrıntılar için ayrı üreteç (binanın kendi üretecini ilerletmez)
function CityDressing.Rng(ctx): Random
	return Random.new((ctx.Lot.Seed or 0) * 7 + 13)
end

-- İşletme kaydı yoksa eski görünüme yakın varsayılan marka
function CityDressing.Brand(business, fallbackName: string, accent: Color3)
	if business then
		return {
			Name = business.Name, Font = business.Font, Sign = business.Sign or "Box",
			Primary = c3(business.Primary), Secondary = c3(business.Secondary),
		}
	end
	return { Name = fallbackName, Font = nil, Sign = "Box", Primary = accent, Secondary = rgb(255, 255, 255) }
end

-- ===== Dükkân cephesi (storefront / storefront_plain) =====
-- front: cephe düzlemi (yerel z), h: dükkân gövdesi yüksekliği, w: cephe genişliği. Cam + kapı BuildingBuilder'da.
-- Tabela biçimleri: Box (ışıklı kutu), Letters (ray üstünde tek tek harf etkisi), Blade (bayrak tabela + küçük alın
-- tabelası), Awning (çizgili tente, isim saçakta).
function CityDressing.ShopFront(ctx, brand, front: number, h: number, w: number)
	local glassTop = 0.5 + h * 0.5
	local canopyY = math.max(glassTop + 0.6, 7.7) -- saçaklar kapı yüksekliğinin (7.5) üstünde: kapı önü boş
	local signY = h * 0.5 + 2.6
	local sw = math.min(w * 0.8, 40)
	local style = brand.Sign
	if style == "Letters" then
		-- ince ray + saydam plaka üstünde marka renginde yazı; altta koyu metal saçak
		part(ctx, "SignRail", Vector3.new(sw * 0.9, 0.35, 0.3), 0, signY + 1.4, front - 0.15, brand.Secondary, M.Metal)
		local plate = part(ctx, "Sign", Vector3.new(sw, 3.6, 0.2), 0, signY - 0.2, front - 0.45, brand.Primary, M.SmoothPlastic,
			{ Transparency = 1, CanCollide = false })
		text(ctx, plate, Enum.NormalId.Front, brand.Name, brand.Primary, brand.Font, lightOf(brand.Primary))
		part(ctx, "Canopy", Vector3.new(w * 0.86, 0.4, 3), 0, canopyY, front - 1.5, DARK, M.Metal)
	elseif style == "Blade" then
		-- alın tabelası (küçük) + kapının yanından sokağa dik bayrak tabela (baş hizasının üstünde)
		local fw = math.min(w * 0.55, 22)
		local fascia = part(ctx, "Sign", Vector3.new(fw, 2.4, 0.3), 0, signY + 0.4, front - 0.3, brand.Primary, M.SmoothPlastic, { CanCollide = false })
		signFace(ctx, fascia, Enum.NormalId.Front, brand.Name, brand.Primary, brand.Secondary, brand.Font)
		local bx = math.clamp(w * 0.32, 4.5, w / 2 - 3)
		local by = math.max(8.6, glassTop - 1)
		part(ctx, "BladeArm", Vector3.new(0.3, 0.3, 4.4), bx, by + 4, front - 2.2, DARK, M.Metal, { CanCollide = false })
		local blade = part(ctx, "Blade", Vector3.new(0.3, 3.6, 3.6), bx, by, front - 2.4, brand.Primary, M.SmoothPlastic, { CanCollide = false })
		signFace(ctx, blade, Enum.NormalId.Left, brand.Name, brand.Primary, brand.Secondary, brand.Font)
		ctx.Kit:Label(blade, Enum.NormalId.Right, brand.Name, brand.Secondary, false, brand.Font) -- öbür yüz: aynı yazı (gece ayarı parçaya bağlı, iki yüze de uygulanır)
		part(ctx, "Canopy", Vector3.new(w * 0.86, 0.4, 2.4), 0, canopyY, front - 1.2, brand.Secondary, M.Metal)
	elseif style == "Awning" then
		-- marka renklerinde çizgili tente; isim tentenin saçağında
		local aw = math.min(w * 0.86, 40)
		local n = math.clamp(math.floor(aw / 3), 4, 12)
		local stripe = aw / n
		local ay = math.max(h * 0.5 + 1.5, 7.7)
		for i = 1, n do
			local x = -aw / 2 + (i - 0.5) * stripe
			part(ctx, "Awning", Vector3.new(stripe, 0.5, 5), x, ay, front - 2.5, if i % 2 == 0 then brand.Secondary else brand.Primary, M.Fabric)
		end
		local valance = part(ctx, "Sign", Vector3.new(aw, 1.8, 0.25), 0, ay - 1.3, front - 5.1, brand.Primary, M.Fabric, { CanCollide = false })
		text(ctx, valance, Enum.NormalId.Front, brand.Name, brand.Secondary, brand.Font, lightOf(brand.Secondary))
		-- cephede de küçük isim (tente kapalı görünse bile okunur)
		local plate = part(ctx, "SignSmall", Vector3.new(math.min(w * 0.5, 18), 2, 0.25), 0, signY + 0.6, front - 0.3, brand.Secondary, M.SmoothPlastic, { CanCollide = false })
		signFace(ctx, plate, Enum.NormalId.Front, brand.Name, brand.Secondary, brand.Primary, brand.Font)
	else
		-- Box: çerçeveli ışıklı kutu, gece marka renginde parlar; altında ince saçak
		part(ctx, "SignFrame", Vector3.new(sw + 0.5, 3.7, 0.4), 0, signY - 0.25, front - 0.2, DARK, M.Metal)
		local face = part(ctx, "Sign", Vector3.new(sw, 3.2, 0.25), 0, signY, front - 0.52, brand.Primary, M.SmoothPlastic, { CanCollide = false })
		signFace(ctx, face, Enum.NormalId.Front, brand.Name, brand.Primary, brand.Secondary, brand.Font)
		part(ctx, "Canopy", Vector3.new(w * 0.86, 0.4, 3), 0, canopyY, front - 1.5, brand.Secondary, M.Metal)
	end
	-- kapının iki yanında saksılar (kapı koridorunun dışında)
	local rng = CityDressing.Rng(ctx)
	if w >= 24 and rng:NextNumber() < 0.7 then
		local green = rgb(78, 132, 64)
		for _, sx in { -1, 1 } do
			local x = sx * math.min(w * 0.4, 12)
			part(ctx, "Planter", Vector3.new(2.4, 1.6, 1.6), x, 0, front - 1.2, rgb(170, 150, 130), M.Concrete)
			part(ctx, "Plant", Vector3.new(2, 1.4, 1.2), x, 1.6, front - 1.2, green, M.Grass)
		end
	end
end

-- Dükkân camı: gece sıcak ışık (içerisi aydınlık görünür); yakındaki birkaç tanesi gerçek ışık da alır
function CityDressing.ShopWindow(ctx, glass: BasePart)
	glass:SetAttribute("NightColor", WARM)
	ctx.Kit:Tag(glass, "ShopWindow")
end

-- ===== Solara Centro zemin kat dükkânı (arsayı tamamen kaplayan ofis / modern apartman) =====
-- Cephe düzlemi z = −d/2 (arsa kenarı). Vitrin ve tabela cephe camı zarfında: en fazla 0.6 stud önde.
-- Bina kapısı ortada (x = 0, genişlik 6) boş kalır; dükkân sağda, büyük binalarda iki yanda vitrin.
CityDressing.RETAIL_TOP = 9.8 -- bu yüksekliğin altındaki cephe camı bu binalarda zemin kata bırakılır

function CityDressing.RetailBand(ctx, brand, w: number, d: number)
	local fz = -d / 2
	local unitW = math.min(w / 2 - 5, 26)
	if unitW < 6 then
		return
	end
	-- alın bandı (koyu taş): bütün cephe boyunca, vitrinlerin üstünde
	part(ctx, "Fascia", Vector3.new(w, 2.2, 0.4), 0, 7.6, fz - 0.2, DARK, M.Concrete) -- kapı yüksekliğinin (7.5) üstünde
	local sides = if w >= 34 then { -1, 1 } else { 1 }
	for _, side in sides do
		local xc = side * (4.5 + unitW / 2)
		local glass = part(ctx, "Vitrine", Vector3.new(unitW, 6.6, 0.3), xc, 0.6, fz - 0.35, GLASS, M.Glass, { Transparency = 0.3 })
		CityDressing.ShopWindow(ctx, glass)
		part(ctx, "VitrineSill", Vector3.new(unitW + 0.6, 0.6, 0.5), xc, 0, fz - 0.3, DARK, M.Concrete)
		if side == 1 or #sides == 1 then
			local sign = part(ctx, "Sign", Vector3.new(math.min(unitW * 0.9, 20), 1.8, 0.2), xc, 7.8, fz - 0.5, brand.Primary, M.SmoothPlastic, { CanCollide = false })
			signFace(ctx, sign, Enum.NormalId.Front, brand.Name, brand.Primary, brand.Secondary, brand.Font)
		else
			-- karşı vitrinde aynı dükkânın küçük adı (büyük mağaza)
			local sign = part(ctx, "SignSmall", Vector3.new(math.min(unitW * 0.6, 12), 1.4, 0.2), xc, 8, fz - 0.5, brand.Secondary, M.SmoothPlastic, { CanCollide = false })
			signFace(ctx, sign, Enum.NormalId.Front, brand.Name, brand.Secondary, brand.Primary, brand.Font)
		end
	end
	-- giriş çerçevesi (kapı açıklığının üstü)
	part(ctx, "EntranceFrame", Vector3.new(7, 0.6, 0.5), 0, 7.6, fz - 0.35, METAL, M.Metal)
end

-- ===== Çatı ayrıntıları =====
-- top: çatı yüksekliği; area: çatının yerel genişlik/derinliği ve merkezi
function CityDressing.RoofUnits(ctx, top: number, rw: number, rd: number, cz: number, count: number?)
	local rng = CityDressing.Rng(ctx)
	local n = count or rng:NextInteger(1, 3)
	for _ = 1, n do
		local x = (rng:NextNumber() - 0.5) * math.max(rw - 8, 0)
		local z = cz + (rng:NextNumber() - 0.5) * math.max(rd - 8, 0)
		local size = if rng:NextNumber() < 0.5 then Vector3.new(4, 2.6, 3) else Vector3.new(3, 2, 3)
		part(ctx, "AC", size, x, top, z, rgb(196, 198, 200), M.Metal)
		part(ctx, "ACFan", Vector3.new(size.X * 0.6, 0.2, size.Z * 0.6), x, top + size.Y, z, rgb(90, 92, 96), M.DiamondPlate)
	end
end

function CityDressing.WaterTank(ctx, top: number, x: number, z: number)
	part(ctx, "TankBase", Vector3.new(5, 2, 5), x, top, z, rgb(90, 80, 70), M.Wood)
	cylinder(ctx, "Tank", 6, 5, x, top + 2, z, rgb(130, 96, 70), M.WoodPlanks)
	cylinder(ctx, "TankRoof", 1, 5.4, x, top + 8, z, rgb(70, 72, 76), M.Metal)
end

-- ===== Bölge karakteri =====
-- Art deco (Costa Verano, Isla Coral, Vista): yuvarlak köşe kolonları, basamaklı taç, gece seçili neon kanat
function CityDressing.DecoDetails(ctx, w: number, d: number, h: number, body: Color3, neon: Color3)
	local rng = CityDressing.Rng(ctx)
	local trim = rgb(255, 255, 255)
	local light = body:Lerp(trim, 0.45)
	for _, sx in { -1, 1 } do
		cylinder(ctx, "DecoCorner", h + 1.5, 3, sx * (w / 2 - 1.5), 0, -d / 2 + 1.5, light, M.SmoothPlastic)
	end
	if w >= 24 then
		part(ctx, "Crown", Vector3.new(w * 0.42, 3, 2), 0, h, -d / 2 + 1.2, light, M.SmoothPlastic)
		part(ctx, "Crown", Vector3.new(w * 0.22, 2.4, 2), 0, h + 3, -d / 2 + 1.2, trim, M.SmoothPlastic)
	end
	if rng:NextNumber() < 0.35 then
		-- ortadaki beyaz pilastrın önünde dikey neon kanat (gündüz beyaz şerit, gece neon)
		local fin = part(ctx, "NeonFin", Vector3.new(0.5, math.max(h - 3, 4), 0.3), 0, 9, -d / 2 - 2.15, trim, M.SmoothPlastic, { CanCollide = false })
		glow(ctx, fin, neon)
	end
	CityDressing.RoofUnits(ctx, h, w * 0.8, d * 0.8, 0, rng:NextInteger(1, 2))
end

-- Eski mahalle tuğla apartmanı (Old Riverside, Centro arka sokakları): pencere altı klimalar, çatıda su deposu
function CityDressing.BrickDetails(ctx, w: number, d: number, h: number, floors: number)
	local rng = CityDressing.Rng(ctx)
	for f = 1, floors - 1 do -- zemin katta yok (baş hizası)
		if rng:NextNumber() < 0.55 then
			local x = (rng:NextNumber() - 0.5) * w * 0.7
			-- cephe zarfı içinde (giriş kapısı/çatı saçağı kadar, 1 stud) dışarı taşar
			part(ctx, "AC", Vector3.new(2.2, 1.6, 1), x, 3 + f * 9 - 1.8, -d / 2 - 0.5, rgb(210, 212, 214), M.Metal)
		end
	end
	if rng:NextNumber() < 0.6 then
		local tx = (rng:NextNumber() - 0.5) * math.max(w - 10, 0)
		CityDressing.WaterTank(ctx, h + 2, tx, d * 0.15)
	else
		CityDressing.RoofUnits(ctx, h + 2, w * 0.8, d * 0.8, 0)
	end
	-- giriş üstünde küçük saçak ve lamba
	part(ctx, "EntryHood", Vector3.new(8, 0.5, 1), 0, 8.4, -d / 2 - 0.5, rgb(60, 60, 64), M.Metal, { CanCollide = false })
	local lamp = part(ctx, "EntryLamp", Vector3.new(0.8, 0.8, 0.4), 4.4, 8.2, -d / 2 - 0.2, rgb(240, 230, 200), M.SmoothPlastic, { CanCollide = false })
	glow(ctx, lamp, WARM)
end

local FLOWERS = { rgb(230, 80, 110), rgb(250, 200, 70), rgb(240, 120, 60), rgb(180, 110, 220) }

-- Sıra evler: bacalar ve pencere çiçeklikleri
function CityDressing.TownhouseDetails(ctx, _w: number, d: number, units: { { x: number, h: number } })
	local rng = CityDressing.Rng(ctx)
	for _, u in units do
		if rng:NextNumber() < 0.55 then
			part(ctx, "Chimney", Vector3.new(2, 4, 2), u.x + (rng:NextNumber() - 0.5) * 4, u.h + 1.4, d * 0.1 + d * 0.25, rgb(120, 70, 56), M.Brick)
		end
		if rng:NextNumber() < 0.5 then
			part(ctx, "FlowerBox", Vector3.new(3.2, 0.8, 0.9), u.x, 11, -d * 0.3 - 0.45, rgb(90, 60, 44), M.Wood)
			part(ctx, "Flowers", Vector3.new(3, 0.6, 0.7), u.x, 11.8, -d * 0.3 - 0.45, FLOWERS[rng:NextInteger(1, #FLOWERS)], M.Grass)
		end
	end
end

-- Modern apartman: balkon döşemelerine cam korkuluk
function CityDressing.BalconyRails(ctx, w: number, d: number, floors: number)
	for f = 1, floors - 1 do
		part(ctx, "Railing", Vector3.new(w * 0.78, 2.4, 0.2), 0, f * 10 + 0.8, -d / 2 - 3.9, rgb(170, 200, 214), M.Glass, { Transparency = 0.5 })
	end
end

-- ===== Reklam panoları (özgün markalar; şehrin kendi işletmeleri) =====
CityDressing.ADS = {
	{ "SOLARA FM 98.7 · SUN ALL DAY", { 255, 122, 69 }, { 255, 255, 255 }, "LuckiestGuy" },
	{ "FLAMINGO BURGER · OPEN LATE", { 255, 92, 150 }, { 255, 230, 90 }, "Bangers" },
	{ "VISIT ISLA CORAL", { 40, 160, 190 }, { 255, 255, 255 }, "Fondamento" },
	{ "BYTE HARBOR · 24H GAMING", { 40, 30, 80 }, { 80, 230, 255 }, "Arcade" },
	{ "SOLMART · FRESH EVERY DAY", { 230, 70, 50 }, { 255, 255, 255 }, "GothamBlack" },
	{ "COSTA VERANO SURF WEEK", { 250, 200, 70 }, { 30, 80, 130 }, "PermanentMarker" },
	{ "SOLARA MOTORS · DRIVE THE COAST", { 30, 40, 60 }, { 230, 190, 110 }, "Michroma" },
	{ "LUMEN CINEMA · NOW SHOWING", { 90, 40, 120 }, { 255, 214, 110 }, "Bodoni" },
	{ "FARMACIA BRISA · ALWAYS OPEN", { 30, 160, 110 }, { 255, 255, 255 }, "Nunito" },
	{ "TWIN PEAK MOTO", { 20, 20, 24 }, { 255, 140, 40 }, "Sarpanch" },
}

-- Çatının ön kenarında, sokağa bakan pano (iki ayak + ışıklı yüz)
function CityDressing.Billboard(ctx, top: number, w: number, d: number, index: number)
	local ad = CityDressing.ADS[(index - 1) % #CityDressing.ADS + 1]
	local bw = math.min(w * 0.7, 28)
	local z = -d / 2 + 2
	for _, sx in { -1, 1 } do
		part(ctx, "BillboardLeg", Vector3.new(0.6, 6, 0.6), sx * bw * 0.35, top, z + 0.6, METAL, M.Metal)
	end
	part(ctx, "BillboardFrame", Vector3.new(bw + 0.6, 10.6, 0.4), 0, top + 5.7, z + 0.2, DARK, M.Metal)
	local face = part(ctx, "Billboard", Vector3.new(bw, 10, 0.3), 0, top + 6, z - 0.15, c3(ad[2]), M.SmoothPlastic, { CanCollide = false })
	signFace(ctx, face, Enum.NormalId.Front, ad[1], c3(ad[2]), c3(ad[3]), ad[4])
end

return CityDressing
