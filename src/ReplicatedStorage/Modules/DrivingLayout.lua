-- DrivingLayout: sürüş arayüzünün yerleşim hesabı (Aşama 3). SAF fonksiyon; Instance kullanmaz.
-- Dokunmatik sürüş kontrolleri (MobileControlsController) ve sürüş göstergesi (VehicleHUDController)
-- AYNI dikdörtgenleri buradan alır → birbirleriyle ve harita alanıyla çakışmazlar.
--
-- Koordinatlar: güvenli alanın (ScreenInsets = CoreUISafeInsets) sol üst köşesine göre piksel.
-- Dikdörtgen = { X, Y, W, H }.
--
-- Not: bu dosya bilerek "düz Lua" alt kümesiyle yazıldı (tip açıklaması, +=, if-ifadesi yok);
-- tools/test_driving_layout.py onu gerçek bir Lua yorumlayıcısında çalıştırıp çok sayıda ekran
-- boyutunda çakışma testi yapar.

local DrivingLayout = {}

local MIN_TOUCH = 44 -- en küçük dokunma hedefi (piksel); platform rehberleriyle uyumlu
DrivingLayout.MinTouch = MIN_TOUCH

local function clamp(x, lo, hi)
	if x < lo then
		return lo
	end
	if x > hi then
		return hi
	end
	return x
end

local function rect(x, y, w, h)
	return { X = math.floor(x), Y = math.floor(y), W = math.floor(w), H = math.floor(h) }
end

function DrivingLayout.Overlaps(a, b, pad)
	pad = pad or 0
	return a.X < b.X + b.W + pad and b.X < a.X + a.W + pad and a.Y < b.Y + b.H + pad and b.Y < a.Y + a.H + pad
end

-- Dokunmatik buton taban boyutu (piksel): kısa kenarın oranı, sınırlı, oyuncu ölçeğiyle
function DrivingLayout.ButtonSize(width, height, userScale)
	local minAxis = math.min(width, height)
	local base = clamp(math.floor(minAxis * 0.13), 56, 96)
	return math.floor(base * (userScale or 1))
end

-- options: Steering ("Pad" | "Buttons"), Kind ("Car" | "Motorcycle" | "Passenger")
-- Döndürür: rects (isim → dikdörtgen), order (çizim/kontrol sırası)
function DrivingLayout.Touch(width, height, base, options)
	options = options or {}
	local kind = options.Kind or "Car"
	local steering = options.Steering or "Pad"
	local minAxis = math.min(width, height)
	local m = math.max(12, math.floor(base * 0.3)) -- kenar boşluğu
	local gap = math.max(8, math.floor(base * 0.18))
	local small = math.max(MIN_TOUCH, math.floor(base * 0.8)) -- ikincil butonlar da 44 px'den küçük olmaz
	local r = {}

	-- Ayrılmış alanlar: harita (sol üst) ve hız çubuğu (üst orta)
	local map = clamp(math.floor(minAxis * 0.26), 84, 180)
	r.Minimap = rect(m, m, map, map)
	local hudW = clamp(math.floor(width * 0.3), 220, 340)
	local hudH = clamp(math.floor(base * 0.95), 48, 80)
	-- Ortada yer yoksa (dar/dikey ekran) haritanın sağına; o da sığmazsa haritanın altına
	local hudX = (width - hudW) / 2
	local hudY = m
	local mapRight = r.Minimap.X + r.Minimap.W + gap
	if hudX < mapRight then
		hudX = mapRight
		if hudX + hudW > width - m then
			hudW = math.max(width - m - hudX, 0)
			if hudW < 200 then
				hudW = math.min(clamp(math.floor(width * 0.3), 220, 340), width - 2 * m)
				hudX = m
				hudY = r.Minimap.Y + r.Minimap.H + gap
			end
		end
	end
	r.Hud = rect(hudX, hudY, hudW, hudH)

	-- Üst sağ satır: in, far, çevir (sağdan sola)
	local topRow = { "Exit" }
	if kind ~= "Passenger" then
		table.insert(topRow, "Lights")
		if kind == "Car" then
			table.insert(topRow, "Flip")
		end
	end
	local x = width - m - small
	local rowY = m
	-- Satır HUD'a değecekse HUD'un altına in
	local rowLeft = width - m - (#topRow * small + (#topRow - 1) * gap)
	if rowLeft < r.Hud.X + r.Hud.W + gap and r.Hud.Y < m + small + gap then
		rowY = r.Hud.Y + r.Hud.H + gap
	end
	for _, name in ipairs(topRow) do
		r[name] = rect(x, rowY, small, small)
		x = x - small - gap
	end

	if kind == "Passenger" then
		return r
	end

	-- Sağ alt: gaz (en büyük, başparmağın doğal yeri), solunda fren, frenin üstünde el freni, gazın üstünde korna
	local gasW, gasH = math.floor(base * 1.25), math.floor(base * 1.7)
	r.Gas = rect(width - m - gasW, height - m - gasH, gasW, gasH)
	local brakeW, brakeH = math.floor(base * 1.15), math.floor(base * 1.3)
	r.Brake = rect(r.Gas.X - gap - brakeW, height - m - brakeH, brakeW, brakeH)
	if kind == "Car" then
		local hb = math.floor(base * 0.95)
		r.Handbrake = rect(r.Brake.X + (brakeW - hb) / 2, r.Brake.Y - gap - hb, hb, hb)
	end
	r.Horn = rect(r.Gas.X + (gasW - small) / 2, r.Gas.Y - gap - small, small, small)

	-- Sol alt: direksiyon (ped ya da iki buton); üstünde sinyaller
	local available = r.Brake.X - gap * 2 - m
	if steering == "Buttons" then
		-- Fren butonuna değmeyecek kadar küçült (dar ekran), ama dokunma sınırının altına inme
		local b = math.max(math.min(math.floor(base * 1.3), math.floor((available - gap) / 2)), MIN_TOUCH)
		r.SteerL = rect(m, height - m - b, b, b)
		r.SteerR = rect(m + b + gap, height - m - b, b, b)
		r.IndL = rect(r.SteerL.X + (b - small) / 2, r.SteerL.Y - gap - small, small, small)
		r.IndR = rect(r.SteerR.X + (b - small) / 2, r.SteerR.Y - gap - small, small, small)
	else
		local padH = math.floor(base * 1.3)
		local padW = clamp(math.floor(width * 0.34), math.floor(base * 2.4), math.floor(base * 5))
		padW = math.max(math.min(padW, available), math.floor(base * 1.8))
		r.Pad = rect(m, height - m - padH, padW, padH)
		r.IndL = rect(m, r.Pad.Y - gap - small, small, small)
		r.IndR = rect(m + padW - small, r.Pad.Y - gap - small, small, small)
	end
	return r
end

-- Masaüstü/gamepad göstergesi: hız saati sağ alt, harita alanı sol alt
function DrivingLayout.Desktop(width, height)
	local minAxis = math.min(width, height)
	local m = clamp(math.floor(minAxis * 0.03), 16, 40)
	local cluster = clamp(math.floor(minAxis * 0.27), 170, 270)
	local map = clamp(math.floor(minAxis * 0.24), 150, 240)
	return {
		Cluster = rect(width - m - cluster, height - m - cluster, cluster, cluster),
		Minimap = rect(m, height - m - map, map, map),
		Margin = m,
	}
end

-- Görünür dikdörtgenlerin birbirine değip değmediğini listeler (geliştirme kontrolü)
function DrivingLayout.FindOverlaps(rects, pad)
	local names = {}
	for name in pairs(rects) do
		table.insert(names, name)
	end
	table.sort(names)
	local problems = {}
	for i = 1, #names do
		for j = i + 1, #names do
			local a, b = rects[names[i]], rects[names[j]]
			if DrivingLayout.Overlaps(a, b, pad or 0) then
				table.insert(problems, names[i] .. "~" .. names[j])
			end
		end
	end
	return problems
end

-- Ekran dışına taşan dikdörtgenler
function DrivingLayout.FindOutOfBounds(rects, width, height)
	local problems = {}
	for name, a in pairs(rects) do
		if a.X < 0 or a.Y < 0 or a.X + a.W > width or a.Y + a.H > height then
			table.insert(problems, name)
		end
	end
	return problems
end

return DrivingLayout
