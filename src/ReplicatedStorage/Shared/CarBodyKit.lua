-- CarBodyKit: Roblox parçalarından (Block / Wedge / Cylinder / Ball) ayrıntılı araba gövdesi tarifi.
-- Saf hesap: Instance oluşturmaz; parça tarifleri listesi döndürür. Oyuncu araçları (VehicleFactory) ve trafik
-- (TrafficRenderer) bu tariften parça kurar; tools/preview_carbody.py aynı tarifi çevrimdışı çizer.
--
-- Koordinat (aracın yerel çerçevesi): +X sağ, +Y yukarı, ön = −Z. y = 0 teker merkezleri yüksekliği, z = 0 iki dingilin
-- ortası. Zemin y = −R (teker yarıçapı). Ön tekerler z = −Wheelbase/2, arka z = +Wheelbase/2, x = ±Track/2.
--
-- Tarif: { Name, Shape ("Block" | "Wedge" | "Cylinder" | "Ball"), Size: Vector3, CF: CFrame (yerel), Color: Color3,
--          Material: string (Enum.Material adı), Transparency, Reflectance, Paint (gövde rengi mi), Light (ışık adı:
--          Headlight | TailLight | ReverseLight | IndicatorL | IndicatorR), Beam (far ışığı), Attach ("Body" |
--          "Wheel_FL" ... (tekerle döner) | "Knuckle_FL" ... (tekerle döner ama dönmez: fren kaliperi)) }
-- Roblox WedgePart: eğimli yüz öne (−Z) ve yukarı bakar, dik yüz arkada (+Z).
-- Detail: "Full" (oyuncu aracı) | "Traffic" (daha az parça).

local CarBodyKit = {}

local rgb = Color3.fromRGB
local PI = math.pi

local C = {
	Dark = rgb(24, 24, 27),
	Trim = rgb(16, 16, 18),
	Chrome = rgb(196, 199, 204),
	Glass = rgb(34, 46, 56),
	Lens = rgb(232, 232, 222),
	LensFrame = rgb(46, 48, 52),
	Tail = rgb(168, 22, 30),
	Amber = rgb(232, 150, 40),
	Rubber = rgb(24, 24, 24),
	Rim = rgb(176, 180, 186),
	Brake = rgb(90, 92, 96),
	Caliper = rgb(170, 28, 32),
	Interior = rgb(38, 38, 42),
	Seat = rgb(58, 52, 48),
	Plate = rgb(240, 240, 234),
	Liner = rgb(12, 12, 13),
}
CarBodyKit.Colors = C

-- ===== yardımcılar =====
local function new(list, detail)
	return { List = list, Detail = detail }
end

local function add(b, name: string, shape: string, size: Vector3, cf: CFrame, color: Color3, material: string?, opts)
	local o = opts or {}
	local spec = {
		Name = name, Shape = shape, Size = size, CF = cf, Color = color, Material = material or "SmoothPlastic",
		Transparency = o.Transparency or 0, Reflectance = o.Reflectance or 0, Paint = o.Paint == true,
		Light = o.Light, Beam = o.Beam, Attach = o.Attach or "Body", Shadow = o.Shadow,
	}
	table.insert(b.List, spec)
	return spec
end

local function block(b, name, sx, sy, sz, x, y, z, color, material, opts)
	return add(b, name, "Block", Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, material, opts)
end

-- Silindir: ekseni X (teker gibi). axis "Y" → dik, "Z" → boylamasına.
local function cyl(b, name, length, diameter, x, y, z, axis, color, material, opts)
	local cf = CFrame.new(x, y, z)
	if axis == "Y" then
		cf = cf * CFrame.Angles(0, 0, PI / 2)
	elseif axis == "Z" then
		cf = cf * CFrame.Angles(0, PI / 2, 0)
	end
	return add(b, name, "Cylinder", Vector3.new(length, diameter, diameter), cf, color, material, opts)
end

-- Y-Z düzleminde iki nokta arasında X kalınlığında levha (eğimli yüzeyler: cam, kaput, direk)
local function slab(b, name, xw, thick, y0, z0, y1, z1, x, color, material, opts)
	local dy, dz = y1 - y0, z1 - z0
	local len = math.sqrt(dy * dy + dz * dz)
	local angle = math.atan2(dy, dz) -- Z ekseninden yukarı dönüş
	local cf = CFrame.new(x, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(-angle, 0, 0)
	return add(b, name, "Block", Vector3.new(xw, thick, len), cf, color, material, opts)
end

-- Teker kemeri: (yc, zc) merkezli, r yarıçaplı yay (öndeki φ=0'dan arkadaki φ=π'ye üstten), X'te [x0, x1]
local function arch(b, name, x0, x1, yc, zc, r, thick, segments, color, material, opts)
	for i = 0, segments - 1 do
		local a0 = PI * i / segments
		local a1 = PI * (i + 1) / segments
		local am = (a0 + a1) / 2
		local seg = 2 * r * math.sin((a1 - a0) / 2) + 0.04
		local y = yc + r * math.sin(am)
		local z = zc - r * math.cos(am)
		local cf = CFrame.new((x0 + x1) / 2, y, z) * CFrame.Angles(am - PI / 2, 0, 0)
		add(b, name, "Block", Vector3.new(x1 - x0, thick, seg), cf, color, material, opts)
	end
end

-- Aynı parçanın sağ ve sol kopyası (x ve −x)
local function mirror(fn)
	fn(1)
	fn(-1)
end

-- ===== stil ölçüleri (def'ten türetilir) =====
local function profile(def, style)
	local R = def.WheelRadius
	local L, W = def.Length, def.Width
	local p = {
		R = R, L = L, W = W, WB = def.Wheelbase, Track = def.Track, WheelW = def.WheelWidth,
		Ground = -R,
		Sill = -R + math.max(def.Clearance * 0.45, 0.45), -- gövde alt kenarı (görsel; fizik kabuğundan bağımsız)
		-- pencere alt çizgisi: fizik kabuğunun üstünden biraz yukarıda (tekerlere göre gerçekçi oran; tavan aynı yerde,
		-- oturan karakterin başı tavanın altında kalır)
		Belt = -0.1 + def.LowerHeight + 0.5,
		Roof = -0.1 + def.LowerHeight + def.CabinHeight + 0.3,
		Front = -L / 2, Rear = L / 2,
	}
	-- kaput ortası çamurluklardan alçak (burunda en alçak, ön camda bel çizgisine çıkar)
	p.HoodDrop = if style == "sports" then 0.65 elseif style == "compact" then 0.4 else 0.5
	p.HoodFront = p.Belt - p.HoodDrop
	p.FenderFront = p.HoodFront + 0.25 -- çamurluk üstü burunda (ön camda bel çizgisine çıkar)
	p.Inner = math.min(def.Track - def.WheelWidth - 0.25, W - 1.4) -- tekerlerin arasındaki iç gövde genişliği
	p.Side = (W - p.Inner) / 2                                       -- yan panel kalınlığı
	p.ArchR = R + 0.28
	-- kabin (camlı bölüm) z sınırları ve eğimler
	if style == "sedan" then
		p.WsBase, p.RoofFront, p.RoofRear, p.RwBase = -L * 0.29, -L * 0.07, L * 0.15, L * 0.34
	elseif style == "compact" then
		p.WsBase, p.RoofFront, p.RoofRear, p.RwBase = -L * 0.3, -L * 0.09, L * 0.27, L * 0.43
	elseif style == "sports" then
		p.WsBase, p.RoofFront, p.RoofRear, p.RwBase = -L * 0.24, -L * 0.0, L * 0.1, L * 0.38
	else
		p.WsBase, p.RoofFront, p.RoofRear, p.RwBase = -L * 0.3, -L * 0.17, L * 0.4, L * 0.45
	end
	p.CabW = if style == "sports" then W - 1.5 else W - 0.9 -- üst gövde içe eğik (tumblehome)
	return p
end
CarBodyKit.Profile = profile

-- ===== alt gövde: iç gövde + kemerli yan paneller + uçlar =====
local function lowerBody(b, p, paint, full)
	-- (yarıçap ve uzunluk profilden: p.R, p.L)
	local zf, zr = -p.WB / 2, p.WB / 2
	local ar = p.ArchR
	local h = p.Belt - p.Sill
	local yMid = (p.Belt + p.Sill) / 2
	local endLen = 1.0 -- tampon yuvarlatma payı
	-- iç gövde (tekerler arasında): önde kaput hizasına kadar (üstünde eğimli kaput), arkada bel çizgisine kadar
	local hf = p.HoodFront - p.Sill
	local zfEnd = p.WsBase
	block(b, "BodyCore", p.Inner, hf, zfEnd - (p.Front + endLen), 0, p.Sill + hf / 2, (p.Front + endLen + zfEnd) / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	block(b, "BodyCore", p.Inner, h, (p.Rear - endLen) - zfEnd, 0, yMid, (zfEnd + p.Rear - endLen) / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	-- kaput: burundan ön camın dibine yükselen kama (Roblox kaması arkaya doğru yükselir)
	local hoodLen = p.WsBase - (p.Front + 0.25)
	add(b, "Hood", "Wedge", Vector3.new(p.Inner, p.HoodDrop, hoodLen), CFrame.new(0, p.HoodFront + p.HoodDrop / 2, p.Front + 0.25 + hoodLen / 2), paint, "SmoothPlastic", { Paint = true, Reflectance = 0.06 })
	if full then
		-- kaput derzleri: iki yanda ve ön kenarda ince koyu çizgi
		mirror(function(s)
			slab(b, "HoodSeam", 0.05, 0.03, p.HoodFront + 0.02, p.Front + 0.3, p.Belt + 0.02, p.WsBase - 0.05, s * (p.Inner / 2 - 0.04), C.Liner, "SmoothPlastic", { Shadow = false })
		end)
		block(b, "HoodSeam", p.Inner - 0.1, 0.05, 0.05, 0, p.HoodFront - 0.02, p.Front + 0.27, C.Liner, "SmoothPlastic", { Shadow = false })
		-- bagaj kapağı derzleri
		mirror(function(s)
			block(b, "TrunkSeam", 0.05, 0.03, p.Rear - 0.35 - p.RwBase, s * (p.Inner / 2 - 0.04), p.Belt + 0.015, (p.RwBase + p.Rear - 0.35) / 2, C.Liner, "SmoothPlastic", { Shadow = false })
		end)
	end
	-- yan paneller, kemer boşluklarıyla
	local sx = p.Inner / 2 + p.Side / 2
	local segs = {
		{ p.Front + endLen, zf - ar }, { zf + ar, zr - ar }, { zr + ar, p.Rear - endLen },
	}
	-- yan parça: [z0, z1] aralığında bottom'dan üst çizgiye; ön camın önünde üst çizgi çamurluk hizası, arkasında bel
	local function sidePiece(s, z0, z1, bottom)
		local cuts = { { z0, math.min(z1, p.WsBase), p.FenderFront }, { math.max(z0, p.WsBase), z1, p.Belt } }
		for _, c in cuts do
			local len, top = c[2] - c[1], c[3]
			if len > 0.05 and top - bottom > 0.05 then
				block(b, "BodySide", p.Side, top - bottom, len, s * sx, (top + bottom) / 2, (c[1] + c[2]) / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
			end
		end
	end
	mirror(function(s)
		for _, seg in segs do
			sidePiece(s, seg[1], seg[2], p.Sill)
		end
		-- çamurluk üstü: burundan ön cama yükselen kama
		local fl = p.WsBase - (p.Front + endLen)
		add(b, "FenderTop", "Wedge", Vector3.new(p.Side, p.Belt - p.FenderFront, fl), CFrame.new(s * sx, (p.Belt + p.FenderFront) / 2, p.Front + endLen + fl / 2), paint, "SmoothPlastic", { Paint = true, Reflectance = 0.05 })
		-- kemerin üstündeki panel (kemer tepesi → üst çizgi)
		for _, zc in { zf, zr } do
			sidePiece(s, zc - ar, zc + ar, ar)
			-- kemer: yay biçimli çamurluk kenarı + içte koyu davlumbaz
			arch(b, "Fender", s * (p.Inner / 2), s * (p.W / 2 + 0.06), 0, zc, ar + 0.12, 0.26, if full then 9 else 5, paint, "SmoothPlastic", { Paint = true })
			block(b, "WheelWell", 0.08, ar + 0.1, ar * 2 - 0.1, s * (p.Inner / 2 + 0.05), ar / 2 - 0.05, zc, C.Liner, "SmoothPlastic", { Shadow = false })
			if full then
				arch(b, "WellLiner", s * (p.Inner / 2 + 0.1), s * (p.W / 2 - 0.05), 0, zc, ar - 0.05, 0.12, 9, C.Liner, "SmoothPlastic", { Shadow = false })
			end
		end
		-- köşeler yuvarlak (dik silindir): önde çamurluk hizası, arkada bel çizgisi
		local fh = p.FenderFront - p.Sill
		cyl(b, "BodyCorner", fh, endLen * 2, s * (p.W / 2 - endLen), p.Sill + fh / 2, p.Front + endLen, "Y", paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
		cyl(b, "BodyCorner", h, endLen * 2, s * (p.W / 2 - endLen), yMid, p.Rear - endLen, "Y", paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	end)
	-- ön ve arka uç (köşeler arasındaki dolgu): önde kaput hizası, arkada bel çizgisi
	block(b, "BodyEnd", p.W - endLen * 2, hf, endLen, 0, p.Sill + hf / 2, p.Front + endLen / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	block(b, "BodyEnd", p.W - endLen * 2, h, endLen, 0, yMid, p.Rear - endLen / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	-- marşpiyel (koyu, kapı altı)
	if full then
		mirror(function(s)
			block(b, "SideSkirt", 0.16, 0.35, (zr - ar) - (zf + ar) - 0.1, s * (p.W / 2 + 0.02), p.Sill + 0.17, 0, C.Trim)
		end)
	end
end

-- ===== kaput, bagaj, üst gövde (camlar, direkler, tavan) =====
local function upperBody(b, p, paint, full, style)
	local cw = p.CabW
	-- kabin: ön cam, tavan, arka cam
	local roofY = p.Roof - 0.15
	slab(b, "Windshield", cw - 0.2, 0.12, p.Belt, p.WsBase, roofY, p.RoofFront, 0, C.Glass, "Glass", { Transparency = 0.35, Shadow = false })
	slab(b, "RearWindow", cw - 0.3, 0.12, roofY, p.RoofRear, p.Belt, p.RwBase, 0, C.Glass, "Glass", { Transparency = 0.35, Shadow = false })
	block(b, "Roof", cw, 0.3, p.RoofRear - p.RoofFront + 0.1, 0, roofY, (p.RoofFront + p.RoofRear) / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.06 })
	-- yan camlar (içe eğik): bel çizgisi ile tavan arası, ön ve arka cam arası
	local sideH = roofY - p.Belt - 0.15
	local yWin = p.Belt + sideH / 2 + 0.02
	mirror(function(s)
		-- cam yüzeyi: ön (üçgen bölümü dahil) ile arka cam arasında dikdörtgen + uçlarda eğik dolgu
		block(b, "SideWindow", 0.1, sideH, p.RoofRear - p.RoofFront, s * (cw / 2 - 0.05), yWin, (p.RoofFront + p.RoofRear) / 2, C.Glass, "Glass", { Transparency = 0.35, Shadow = false })
		-- ön üçgen cam ve arka üçgen cam: eğik ön/arka cam ile yan cam arasındaki boşluk (Wedge)
		local fl = p.RoofFront - p.WsBase
		add(b, "SideWindow", "Wedge", Vector3.new(0.1, sideH, fl), CFrame.new(s * (cw / 2 - 0.05), yWin, (p.WsBase + p.RoofFront) / 2), C.Glass, "Glass", { Transparency = 0.35, Shadow = false })
		local rl = p.RwBase - p.RoofRear
		add(b, "SideWindow", "Wedge", Vector3.new(0.1, sideH, rl), CFrame.new(s * (cw / 2 - 0.05), yWin, (p.RoofRear + p.RwBase) / 2) * CFrame.Angles(0, PI, 0), C.Glass, "Glass", { Transparency = 0.35, Shadow = false })
		-- direkler: A (ön cam kenarı), B (ön kapı arkası), C (arka cam kenarı) — gövde renginde / siyah
		slab(b, "PillarA", 0.32, 0.3, p.Belt, p.WsBase, roofY, p.RoofFront, s * (cw / 2 - 0.05), paint, "SmoothPlastic", { Paint = true })
		slab(b, "PillarC", 0.32, 0.36, roofY, p.RoofRear, p.Belt, p.RwBase, s * (cw / 2 - 0.05), paint, "SmoothPlastic", { Paint = true })
		local zB = (p.RoofFront + p.RoofRear) / 2 - 0.2
		block(b, "PillarB", 0.14, sideH + 0.1, 0.4, s * (cw / 2 + 0.02), yWin, zB, C.Trim)
		-- pencere alt krom çıtası
		if full then
			block(b, "BeltTrim", 0.12, 0.08, p.RwBase - p.WsBase - 0.4, s * (cw / 2 + 0.02), p.Belt + 0.04, (p.WsBase + p.RwBase) / 2, C.Chrome, "Metal", { Reflectance = 0.2 })
			-- yağmurluk / tavan kenar çıtası
			block(b, "RoofTrim", 0.1, 0.08, p.RoofRear - p.RoofFront, s * (cw / 2 + 0.01), roofY + 0.12, (p.RoofFront + p.RoofRear) / 2, C.Trim)
		end
		-- bel çizgisinden pencereye kadar üst panel (gövde ile kabin arasındaki omuz)
		block(b, "Shoulder", (p.W - cw) / 2 + 0.05, 0.22, p.RwBase - p.WsBase, s * (cw / 2 + (p.W - cw) / 4), p.Belt - 0.06, (p.WsBase + p.RwBase) / 2, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.05 })
	end)
	-- kabin içi (camdan görünür): taban/torpido/koltuklar
	if full then
		block(b, "Dashboard", cw - 0.4, 0.5, 1.0, 0, p.Belt - 0.1, p.WsBase + 0.7, C.Interior)
		mirror(function(s)
			local zs = (p.RoofFront + p.RoofRear) / 2 - 0.5
			block(b, "Seat", 1.5, 0.35, 1.5, s * 1.3, p.Belt - 0.45, zs, C.Seat)
			block(b, "SeatBack", 1.5, 1.6, 0.35, s * 1.3, p.Belt + 0.3, zs + 0.75, C.Seat)
			block(b, "Headrest", 0.8, 0.5, 0.3, s * 1.3, p.Belt + 1.3, zs + 0.8, C.Seat)
			if style ~= "sports" and p.RoofRear - p.RoofFront > 4 then
				block(b, "RearSeat", 1.6, 1.4, 0.35, s * 1.25, p.Belt + 0.2, p.RoofRear - 0.3, C.Seat)
			end
		end)
		-- direksiyon (sol koltuk önü) ve kolonu
		cyl(b, "SteeringWheel", 0.1, 0.8, -1.3, p.Belt + 0.35, p.WsBase + 1.45, "Z", C.Interior)
		cyl(b, "SteeringColumn", 0.7, 0.14, -1.3, p.Belt + 0.15, p.WsBase + 1.1, "Z", C.Trim)
	end
end

-- ===== ön yüz: tampon, ızgara, farlar =====
-- Yükseklikler: burun (HoodFront) altında far + ızgara bandı, altında gövde renginde tampon, içinde geniş hava girişi.
local function frontFace(b, p, paint, full)
	local z = p.Front
	local yH = p.HoodFront - 0.5           -- far / ızgara bandının ortası
	local yBumperTop = yH - 0.45
	local yIntake = (p.Sill + yBumperTop) / 2 + 0.05
	-- tampon: gövdeden biraz taşan, köşeleri gövdeyle aynı
	block(b, "BumperF", p.W - 1.6, yBumperTop - p.Sill, 0.4, 0, (yBumperTop + p.Sill) / 2, z - 0.05, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	block(b, "IntakeF", p.W * 0.55, 0.42, 0.12, 0, yIntake, z - 0.27, C.Trim)
	block(b, "BumperLipF", p.W - 1.8, 0.16, 0.5, 0, p.Sill + 0.05, z, C.Trim)
	-- ızgara: koyu panel + krom çerçeve + yatay çıtalar
	local gw, gh = p.W * 0.34, 0.62
	block(b, "Grille", gw, gh, 0.12, 0, yH, z - 0.02, C.Dark)
	if full then
		block(b, "GrilleFrame", gw + 0.14, gh + 0.14, 0.06, 0, yH, z + 0.03, C.Chrome, "Metal", { Reflectance = 0.25 })
		for i = 1, 3 do
			block(b, "GrilleBar", gw, 0.05, 0.05, 0, yH - gh / 2 + gh * i / 4, z - 0.09, C.Chrome, "Metal", { Reflectance = 0.25 })
		end
		block(b, "Badge", 0.45, 0.28, 0.05, 0, yH, z - 0.12, C.Chrome, "Metal", { Reflectance = 0.35 })
	end
	-- farlar: ızgaradan köşeye uzanan çerçeve + mercek (ışık) + projektör + gündüz farı + sinyal
	mirror(function(s)
		local hw = (p.W / 2 - 0.25) - (gw / 2 + 0.15)
		local hx = s * (gw / 2 + 0.15 + hw / 2)
		block(b, "HeadlightHousing", hw, 0.7, 0.12, hx, yH + 0.02, z + 0.04, C.LensFrame)
		local lens = block(b, "Headlight", hw - 0.2, 0.52, 0.1, hx, yH + 0.04, z - 0.04, C.Lens, "SmoothPlastic", { Light = "Headlight", Beam = true, Shadow = false })
		lens.Light = "Headlight"
		if full then
			cyl(b, "Projector", 0.12, 0.4, hx - s * hw * 0.2, yH + 0.06, z - 0.1, "Z", C.Chrome, "Metal", { Reflectance = 0.35 })
			cyl(b, "Projector", 0.12, 0.3, hx + s * hw * 0.15, yH + 0.06, z - 0.1, "Z", C.Chrome, "Metal", { Reflectance = 0.35 })
			block(b, "DRL", hw - 0.3, 0.07, 0.05, hx, yH - 0.18, z - 0.1, C.Lens, "Neon", { Shadow = false })
			local ind = block(b, s < 0 and "IndicatorL" or "IndicatorR", 0.28, 0.4, 0.08, s * (p.W / 2 - 0.35), yH + 0.02, z - 0.03, C.Amber, "SmoothPlastic", { Shadow = false })
			ind.Light = ind.Name
			cyl(b, "FogLight", 0.1, 0.34, s * (p.W / 2 - 1.15), yIntake, z - 0.3, "Z", C.Lens)
			block(b, "SideMarkerF", 0.04, 0.16, 0.45, s * (p.W / 2 + 0.02), yH, z + 0.7, C.Amber)
		end
	end)
	if full then
		block(b, "PlateF", 1.8, 0.42, 0.05, 0, yIntake + 0.02, z - 0.35, C.Plate)
	end
end

-- ===== arka yüz: stoplar, tampon, egzoz =====
local function rearFace(b, p, paint, full)
	local z = p.Rear
	local yBumper = p.Sill + 0.45
	local ty = p.Belt - 0.55
	block(b, "BumperR", p.W - 1.0, 0.7, 0.5, 0, yBumper, z - 0.15, paint, "SmoothPlastic", { Paint = true, Reflectance = 0.04 })
	block(b, "DiffuserR", p.W - 1.6, 0.3, 0.5, 0, p.Sill + 0.08, z - 0.25, C.Trim)
	mirror(function(s)
		local tx = s * (p.W / 2 - 1.05)
		block(b, "TailHousing", 1.9, 0.8, 0.12, tx, ty, z - 0.1, C.LensFrame)
		local tail = block(b, "TailLight", 1.7, 0.6, 0.1, tx, ty + 0.03, z - 0.02, C.Tail, "SmoothPlastic", { Shadow = false })
		tail.Light = "TailLight"
		if full then
			local rev = block(b, "ReverseLight", 0.45, 0.16, 0.08, tx - s * 0.35, ty - 0.2, z + 0.03, C.Lens, "SmoothPlastic", { Shadow = false })
			rev.Light = "ReverseLight"
			local ind = block(b, s < 0 and "IndicatorL" or "IndicatorR", 0.4, 0.16, 0.08, tx + s * 0.3, ty - 0.2, z + 0.03, C.Amber, "SmoothPlastic", { Shadow = false })
			ind.Light = ind.Name
			cyl(b, "Exhaust", 0.6, 0.32, s * (p.W / 2 - 1.4), p.Sill + 0.1, z + 0.05, "Z", C.Chrome, "Metal", { Reflectance = 0.3 })
		end
	end)
	-- arka panel krom şeridi ve plaka
	if full then
		block(b, "TrunkTrim", p.W - 3.6, 0.1, 0.06, 0, ty + 0.1, z + 0.02, C.Chrome, "Metal", { Reflectance = 0.25 })
		block(b, "PlateR", 1.8, 0.45, 0.06, 0, yBumper + 0.4, z + 0.1, C.Plate)
	end
end

-- ===== yan ayrıntılar: kapı derzleri, kollar, aynalar =====
local function sideDetails(b, p, paint, full, doors)
	local zf, zr = -p.WB / 2 + p.ArchR, p.WB / 2 - p.ArchR
	mirror(function(s)
		local x = s * (p.W / 2 + 0.01)
		-- ayna: gövde renginde kapak + siyah ayak + cam
		local mz = p.WsBase + 0.45
		block(b, "MirrorArm", 0.5, 0.12, 0.25, s * (p.CabW / 2 + 0.2), p.Belt + 0.25, mz, C.Trim)
		block(b, "Mirror", 0.6, 0.42, 0.32, s * (p.CabW / 2 + 0.55), p.Belt + 0.35, mz, paint, "SmoothPlastic", { Paint = true })
		if not full then
			return
		end
		block(b, "MirrorGlass", 0.5, 0.32, 0.04, s * (p.CabW / 2 + 0.55), p.Belt + 0.35, mz + 0.18, C.Chrome, "Glass", { Reflectance = 0.4 })
		-- kapı derzleri (ince koyu çizgiler) ve kollar
		local cuts = if doors == 4 then { zf + 0.1, (zf + zr) / 2 + 0.1, zr - 0.05 } else { zf + 0.1, zr - 0.6 }
		for _, zc in cuts do
			block(b, "DoorSeam", 0.04, p.Belt - p.Sill - 0.25, 0.05, x, (p.Belt + p.Sill) / 2 + 0.05, zc, C.Liner, "SmoothPlastic", { Shadow = false })
		end
		for i = 1, #cuts - 1 do
			block(b, "DoorHandle", 0.08, 0.12, 0.55, x + s * 0.03, p.Belt - 0.45, cuts[i + 1] - 0.55, C.Chrome, "Metal", { Reflectance = 0.25 })
		end
		-- yan çizgi (gövde çizgisi hafif gölge)
		block(b, "BodyLine", 0.03, 0.05, zr - zf + p.ArchR * 2 - 0.6, x, p.Belt - 0.7, 0, C.Dark, "SmoothPlastic", { Shadow = false, Transparency = 0.5 })
	end)
end

-- ===== tekerlek ayrıntıları (fizik tekerinin üstüne): jant yüzü, kollar, göbek, disk, kaliper =====
local WHEELS = { { "FL", -1, -1 }, { "FR", 1, -1 }, { "RL", -1, 1 }, { "RR", 1, 1 } } -- ad, sağ(+)/sol(−), arka(+)/ön(−)

local function wheelDetails(b, p, full)
	for _, w in WHEELS do
		local name, s, f = w[1], w[2], w[3]
		local x, z = s * p.Track / 2, f * p.WB / 2
		local outer = s * (p.WheelW / 2 + 0.01)
		local att = "Wheel_" .. name
		-- jant: lastiğin dış yüzünde gümüş disk ve koyu iç halka
		cyl(b, "RimBarrel", 0.06, p.R * 1.32, x + outer, 0, z, "X", C.Dark, "SmoothPlastic", { Attach = att, Shadow = false })
		cyl(b, "RimFace", 0.07, p.R * 1.2, x + outer + s * 0.02, 0, z, "X", C.Rim, "Metal", { Attach = att, Reflectance = 0.2, Shadow = false })
		if full then
			-- 5 kol (jantın üstünde, merkezden dışa)
			for k = 0, 4 do
				local a = k * 2 * PI / 5
				local rr = p.R * 0.33
				-- uzun kenar (Z) göbekten dışa: X etrafında −a dönüş Z eksenini (sin a, cos a) yönüne çevirir
				local cf = CFrame.new(x + outer + s * 0.06, rr * math.sin(a), z + rr * math.cos(a)) * CFrame.Angles(-a, 0, 0)
				add(b, "Spoke", "Block", Vector3.new(0.06, 0.22, p.R * 0.62), cf, C.Rim, "Metal", { Attach = att, Reflectance = 0.25, Shadow = false })
			end
			-- jant kolları arası koyu boşluk (derinlik hissi)
			cyl(b, "RimDepth", 0.04, p.R * 1.05, x + outer + s * 0.045, 0, z, "X", C.Brake, "SmoothPlastic", { Attach = att, Shadow = false })
			cyl(b, "Hub", 0.1, p.R * 0.34, x + outer + s * 0.08, 0, z, "X", C.Chrome, "Metal", { Attach = att, Reflectance = 0.3, Shadow = false })
			-- fren kaliperi: dönmez (mafsala bağlı), jantın arkasında görünür
			block(b, "Caliper", 0.25, p.R * 0.5, p.R * 0.35, x + outer - s * 0.12, p.R * 0.35, z + f * p.R * 0.25, C.Caliper, "SmoothPlastic", { Attach = "Knuckle_" .. name, Shadow = false })
		end
	end
end

-- ===== stile özel ekler =====
local function extras(b, p, paint, full, def, style)
	if style == "sports" then
		-- kaput hava girişi + arka kanat
		block(b, "HoodVent", 1.6, 0.12, 1.4, 0, p.Belt - 0.15, p.WsBase - 1.6, C.Dark)
		if def.Spoiler then
			block(b, "SpoilerWing", p.W - 0.8, 0.14, 1.1, 0, p.Belt + 0.75, p.Rear - 0.75, paint, "SmoothPlastic", { Paint = true })
			mirror(function(s)
				block(b, "SpoilerPost", 0.16, 0.7, 0.35, s * (p.W / 2 - 1.4), p.Belt + 0.35, p.Rear - 0.75, C.Trim)
				block(b, "SpoilerEnd", 0.1, 0.4, 1.1, s * (p.W / 2 - 0.4), p.Belt + 0.75, p.Rear - 0.75, C.Trim)
			end)
		end
		if full then
			mirror(function(s)
				block(b, "SideVent", 0.06, 0.4, 1.0, s * (p.W / 2 + 0.02), p.Belt - 0.6, p.WB / 2 - p.ArchR - 0.7, C.Dark)
			end)
		end
	elseif style == "sedan" then
		if full then
			cyl(b, "Antenna", 0.9, 0.05, 0, p.Roof + 0.3, p.RoofRear - 0.4, "Y", C.Trim)
		end
	end
end

-- ===== giriş =====
function CarBodyKit.Supports(style: string): boolean
	return style == "sedan" or style == "compact" or style == "sports"
end

-- def: VehicleDefinitions girdisi; paint: gövde rengi; detail: "Full" | "Traffic"
function CarBodyKit.Build(def, paint: Color3, detail: string?)
	local style = def.Style
	local full = detail ~= "Traffic"
	local b = new({}, detail or "Full")
	local p = profile(def, style)
	lowerBody(b, p, paint, full)
	upperBody(b, p, paint, full, style)
	frontFace(b, p, paint, full)
	rearFace(b, p, paint, full)
	sideDetails(b, p, paint, full, if style == "sports" then 2 elseif style == "compact" then 2 else 4)
	wheelDetails(b, p, full)
	extras(b, p, paint, full, def, style)
	return b.List, p
end

return CarBodyKit
