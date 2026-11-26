-- Entrances: bina giriş/çıkış kayıt sistemi (Yaşayan Şehir). SAF Lua; Roblox API'si yok (tools/test_ambient.py
-- çalıştırır). Harita DEĞİŞMEZ: kapı noktaları arsa verisinden (MapData "L" satırları) ve BuildingBuilder'ın her stil
-- için kullandığı cephe geometrisinden hesaplanır.
--
-- Her giriş (BuildingEntrance = BuildingExit, aynı kapı):
--   { Id, LotId, Style, Use ("Home" | "Shop" | "Work" | "Hotel"), X, Y, Z (kapı düzleminin ortası, zemin),
--     NX, NZ (dışa bakan normal), Width, Height, OutX, OutZ (kapının 1.2 stud önü: yaya burada kapıya döner),
--     Node (PedGraph kapı düğümü = NPCDestination), Walk (kaldırım düğümü = PedestrianWaypoint), HasDoorPart }
-- Kapı yalnızca cephesi doğrulanmış stillerde üretilir (yanlış yerde, duvarın içinde kapı olmasın). Kapı ile kaldırım
-- arasında, cepheye dik, yoldan ve başka arsalardan geçmeyen düz bir yürüme bağlantısı kurulur; kurulamazsa kapı
-- kaydedilmez. Kaldırım bağlantısı kapı noktasında bölünür (yeni kaldırım düğümü), kapı düğümü çıkmaz uçtur: A* onu
-- kısa yol olarak kullanamaz, sadece hedef/çıkış noktasıdır.

local Entrances = {}

local sqrt, abs, max, min, floor, cos, sin, rad = math.sqrt, math.abs, math.max, math.min, math.floor, math.cos, math.sin, math.rad
local GRID = 96
local clampN = function(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

-- Stil → kapılar (yerel koordinat: genişlik X, bina önü −Z; z = kapı düzlemi). BuildingBuilder ile birebir aynı
-- formüller (orada değişirse burası da değişmeli; test her kapının cephede olduğunu denetler).
-- Dönüş: { { x, z, floorY, width, height, doorPart }, ... }, kullanım
local STYLES = {}

STYLES.house_b = function(w, d)
	local hw = max(min(w - 8, 32), 10)
	return { { hw * 0.3, -d / 2 + 9, 0, 4, 7, false } }, "Home"
end

STYLES.house_a = function(w, d)
	local hw, hd = min(w - 8, 34), min(d - 16, 28)
	if hw < 12 or hd < 10 then
		return STYLES.house_b(w, d) -- BuildingBuilder da house_b'ye düşer
	end
	-- ahşap kapı parçası: genişlik 4, x = −hw·0.15, cephe z = −d/2 + 10 (ön bahçe 10 stud)
	return { { -hw * 0.15, -d / 2 + 10 - 0.4, 0, 4, 7, true } }, "Home"
end

STYLES.townhouse = function(w, d)
	local n = clampN(floor(w / 16), 2, 4)
	local uw = w / n
	local list = {}
	for i = 1, n do
		-- kapı 1.5 stud yüksekte (önünde 1.5 yüksek basamak): kapı düzlemi −d·0.3 − 0.4
		list[#list + 1] = { -w / 2 + (i - 0.5) * uw, -d * 0.3 - 0.4, 1.5, 3.5, 7, true }
	end
	return list, "Home"
end

local function storefront(_w, d)
	local depth = d * 0.85
	local front = (d / 2 - depth / 2) - depth / 2
	return { { 0, front - 0.7, 0, 5, 7.5, true } }, "Shop" -- metal kapı parçası
end
STYLES.storefront = storefront
STYLES.storefront_plain = storefront

STYLES.apartment_brick = function(_w, d)
	return { { 0, -d / 2 - 1, 0, 6, 8, true } }, "Home" -- ahşap giriş parçası
end

STYLES.apartment_modern = function(_w, d)
	return { { 0, -d / 2 - 0.45, 0, 6, 8, false } }, "Home" -- cam lobi cephesi
end

STYLES.office = function(_w, d)
	return { { 0, -d / 2, 0, 6, 8, false } }, "Work"
end

STYLES.glass_tower = function(_w, d)
	return { { 0, -d / 2, 0, 8, 9, false } }, "Work" -- giriş saçağının altı
end

STYLES.setback_tower = function(_w, d)
	return { { 0, -d * 0.48, 0, 8, 9, false } }, "Work"
end

STYLES.hotel = function(_w, d)
	return { { 0, -d * 0.3 - 2, 0, 8, 9, false } }, "Hotel" -- cam giriş kolonunun önü
end

STYLES.deco_lowrise = function(w, d)
	if w < 28 then
		return {}, "Home" -- dar cephe: pencere bandına denk gelmeyen kapı yeri yok
	end
	return { { w * 0.43, -d / 2, 0, 4, 7, false } }, "Home"
end

STYLES.mall = function(_w, d)
	return { { 0, -d / 2 - 5, 0, 10, 9, false } }, "Shop" -- cam giriş kutusunun önü
end

Entrances.Styles = STYLES

-- Yerel (x, z) → dünya (Roblox CFrame.Angles(0, θ, 0) ile aynı dönüş)
local function toWorld(lot, x, z)
	local th = rad(lot.Rotation or 0)
	local c, s = cos(th), sin(th)
	return lot.Center.X + x * c + z * s, lot.Center.Z - x * s + z * c
end
Entrances.ToWorld = toWorld

-- (px, pz) bir arsanın dikdörtgeninin içinde mi? (pay kadar küçültülmüş)
local function inLot(lot, px, pz, pad)
	local th = rad(lot.Rotation or 0)
	local c, s = cos(th), sin(th)
	local dx, dz = px - lot.Center.X, pz - lot.Center.Z
	-- dünyadan yerele: tersi dönüş
	local lx = dx * c - dz * s
	local lz = dx * s + dz * c
	return abs(lx) < lot.Width / 2 - pad and abs(lz) < lot.Depth / 2 - pad
end
Entrances.InLot = inLot

local function segIntersect(ax, az, bx, bz, cx, cz, dx, dz)
	local rx, rz = bx - ax, bz - az
	local sx, sz = dx - cx, dz - cz
	local den = rx * sz - rz * sx
	if abs(den) < 1e-9 then
		return nil
	end
	local t = ((cx - ax) * sz - (cz - az) * sx) / den
	local u = ((cx - ax) * rz - (cz - az) * rx) / den
	if t >= 0 and t <= 1 and u >= 0 and u <= 1 then
		return t, u
	end
	return nil
end

-- data: MapDefinitions verisi; pg: PedGraph (değiştirilir: kaldırım bölünür, kapı düğümleri eklenir)
-- PG: PedGraph modülü (OnRoad, RebuildGrid); tg: TrafficGraph (OnRoad için)
function Entrances.Build(data, pg, PG, tg, opts)
	opts = opts or {}
	local reach = opts.Reach or 32 -- kapıdan kaldırıma en fazla bu kadar
	local reg = { List = {}, Grid = {}, Rejected = { NoSidewalk = 0, Road = 0, OtherLot = 0, Narrow = 0 } }
	if #pg.Links == 0 then
		return reg
	end
	local top = pg.Top

	-- yol ızgarası (PedGraph.OnRoad ile aynı kural, ama sadece yakındaki yollar: kurulum hızlı)
	local edgeGrid = {}
	for _, e in ipairs(data.EdgeList) do
		local pa, pb = data.Nodes[e.A].Position, data.Nodes[e.B].Position
		local L = sqrt((pb.X - pa.X) ^ 2 + (pb.Z - pa.Z) ^ 2)
		local steps = max(1, floor(L / (GRID / 2)))
		local seen = {}
		for i = 0, steps do
			local f = i / steps
			local x, z = pa.X + (pb.X - pa.X) * f, pa.Z + (pb.Z - pa.Z) * f
			local k = floor(x / GRID) .. ":" .. floor(z / GRID)
			if not seen[k] then
				seen[k] = true
				edgeGrid[k] = edgeGrid[k] or {}
				table.insert(edgeGrid[k], e)
			end
		end
	end
	local padList = {}
	for _, pad in pairs(tg and tg.Pads or {}) do
		if pad.Kind == "Box" then
			padList[#padList + 1] = pad
		end
	end
	local function onRoad(x, z, y)
		local cx, cz = floor(x / GRID), floor(z / GRID)
		for i = cx - 1, cx + 1 do
			for j = cz - 1, cz + 1 do
				for _, e in ipairs(edgeGrid[i .. ":" .. j] or {}) do
					local pa, pb = data.Nodes[e.A].Position, data.Nodes[e.B].Position
					local dx, dz = pb.X - pa.X, pb.Z - pa.Z
					local L2 = dx * dx + dz * dz
					if L2 > 1 then
						local t = ((x - pa.X) * dx + (z - pa.Z) * dz) / L2
						local ry = pa.Y + (pb.Y - pa.Y) * t
						if t > 0 and t < 1 and abs(ry - y) < 4 then
							local px, pz = pa.X + dx * t, pa.Z + dz * t
							if (x - px) ^ 2 + (z - pz) ^ 2 < (e.Width / 2 - 0.2) ^ 2 then
								return true
							end
						end
					end
				end
			end
		end
		for _, pad in ipairs(padList) do
			if abs(x - pad.X) < pad.SX / 2 - 0.2 and abs(z - pad.Z) < pad.SZ / 2 - 0.2 and abs(pad.Y - y) < 4 then
				return true
			end
		end
		return false
	end
	Entrances._onRoad = onRoad

	-- arsa ızgarası (başka arsadan geçme denetimi)
	local lotGrid = {}
	for _, lot in ipairs(data.Lots or {}) do
		local k = floor(lot.Center.X / GRID) .. ":" .. floor(lot.Center.Z / GRID)
		lotGrid[k] = lotGrid[k] or {}
		table.insert(lotGrid[k], lot)
	end
	local function lotsNear(x, z)
		local out = {}
		local cx, cz = floor(x / GRID), floor(z / GRID)
		for i = cx - 1, cx + 1 do
			for j = cz - 1, cz + 1 do
				for _, l in ipairs(lotGrid[i .. ":" .. j] or {}) do
					out[#out + 1] = l
				end
			end
		end
		return out
	end

	local function newNode(x, z, y, comp)
		local n = { Id = #pg.Nodes + 1, X = x, Y = y or top, Z = z, Links = {}, Comp = comp }
		pg.Nodes[n.Id] = n
		return n
	end
	local function newLink(a, b, info)
		local dx, dz = b.X - a.X, b.Z - a.Z
		local l = { Id = #pg.Links + 1, A = a, B = b, Length = sqrt(dx * dx + dz * dz), Crossing = false }
		for k, v in pairs(info or {}) do
			l[k] = v
		end
		pg.Links[l.Id] = l
		a.Links[#a.Links + 1] = l
		b.Links[#b.Links + 1] = l
		return l
	end
	-- l'yi (A, B) → (A, S) + (S, B) olarak böl. Bağlantı dizisi boşluksuz kalır (eski kayıt yeniden kullanılır).
	local function split(l, x, z)
		local a, b = l.A, l.B
		local s = newNode(x, z, top, a.Comp)
		local nl = newLink(s, b, { Edge = l.Edge })
		-- b'nin listesinde l → nl
		for i, bl in ipairs(b.Links) do
			if bl == l then
				table.remove(b.Links, i)
				break
			end
		end
		l.B = s
		local dx, dz = s.X - a.X, s.Z - a.Z
		l.Length = sqrt(dx * dx + dz * dz)
		s.Links[#s.Links + 1] = l
		return s, nl
	end

	local linksNear = function(x, z, r)
		local out, seen = {}, {}
		for i = floor((x - r) / GRID), floor((x + r) / GRID) do
			for j = floor((z - r) / GRID), floor((z + r) / GRID) do
				for _, l in ipairs(pg.Grid[i .. ":" .. j] or {}) do
					if not seen[l] then
						seen[l] = true
						out[#out + 1] = l
					end
				end
			end
		end
		return out
	end
	local pending = {} -- bölünen bağlantılar ızgarada henüz yok: aynı kenarda ikinci kapı için ek liste

	for lotIndex, lot in ipairs(data.Lots or {}) do
		local fn = STYLES[lot.Style]
		if opts.Yield and lotIndex % 60 == 0 then
			opts.Yield() -- kurulumu karelere yay
		end
		if fn then
			local doors, use = fn(lot.Width, lot.Depth)
			for di, door in ipairs(doors) do
				local lx, lz, floorY, width, height, hasPart = door[1], door[2], door[3], door[4], door[5], door[6]
				local th = rad(lot.Rotation or 0)
				local nx, nz = -sin(th), -cos(th) -- yerel −Z (cephe dışı)
				local x, z = toWorld(lot, lx, lz)
				local ox, oz = x + nx * 1.2, z + nz * 1.2
				-- cepheye dik ışın: en yakın kaldırım bağlantısı (geçit değil)
				local best, bestT = nil, math.huge
				local ex, ez = ox + nx * reach, oz + nz * reach
				local cands = linksNear(ox, oz, reach + 10)
				for _, l in ipairs(pending) do
					cands[#cands + 1] = l
				end
				for _, l in ipairs(cands) do
					if not l.Crossing and not l.Door then
						local t = segIntersect(ox, oz, ex, ez, l.A.X, l.A.Z, l.B.X, l.B.Z)
						if t and t < bestT then
							best, bestT = l, t
						end
					end
				end
				if not best then
					reg.Rejected.NoSidewalk = reg.Rejected.NoSidewalk + 1
				else
					local sx, sz = ox + (ex - ox) * bestT, oz + (ez - oz) * bestT
					-- yürüme çizgisi yoldan ve başka arsalardan geçmesin
					local ok = true
					local len = bestT * reach
					local steps = max(2, floor(len / 1.5))
					for i = 0, steps do
						local f = i / steps
						local px, pz = ox + (sx - ox) * f, oz + (sz - oz) * f
						if onRoad(px, pz, top) then
							ok = false
							reg.Rejected.Road = reg.Rejected.Road + 1
							break
						end
						for _, other in ipairs(lotsNear(px, pz)) do
							if other ~= lot and inLot(other, px, pz, 0.5) then
								ok = false
								break
							end
						end
						if not ok then
							reg.Rejected.OtherLot = reg.Rejected.OtherLot + 1
							break
						end
					end
					-- bölünen parça çok kısa olmasın (köşe düğümüne yapışık kapı → mevcut düğümü kullan)
					local walk
					if ok then
						local la, lb = best.A, best.B
						local da = (la.X - sx) ^ 2 + (la.Z - sz) ^ 2
						local db = (lb.X - sx) ^ 2 + (lb.Z - sz) ^ 2
						if da < 2.25 then
							walk = la
						elseif db < 2.25 then
							walk = lb
						else
							local nl
							walk, nl = split(best, sx, sz)
							pending[#pending + 1] = nl
						end
						local dn = newNode(ox, oz, (lot.BaseY or top) + floorY, walk.Comp)
						local e = {
							Id = #reg.List + 1, LotId = lot.Id, Style = lot.Style, Use = use, Index = di,
							X = x, Y = (lot.BaseY or top) + floorY, Z = z, NX = nx, NZ = nz, Width = width, Height = height,
							OutX = ox, OutZ = oz, Walk = walk, Node = dn, HasDoorPart = hasPart, Poi = lot.PoiId,
							ActiveUntil = 0,
						}
						dn.Door = e
						newLink(walk, dn, { DoorLink = e, Door = true })
						reg.List[#reg.List + 1] = e
						local k = floor(x / GRID) .. ":" .. floor(z / GRID)
						reg.Grid[k] = reg.Grid[k] or {}
						table.insert(reg.Grid[k], e)
					end
				end
			end
		end
	end
	if PG.RebuildGrid then
		PG.RebuildGrid(pg)
	end
	return reg
end

function Entrances.Near(reg, x, z, radius)
	local out = {}
	local r2 = radius * radius
	for i = floor((x - radius) / GRID), floor((x + radius) / GRID) do
		for j = floor((z - radius) / GRID), floor((z + radius) / GRID) do
			for _, e in ipairs(reg.Grid[i .. ":" .. j] or {}) do
				if (e.X - x) ^ 2 + (e.Z - z) ^ 2 < r2 then
					out[#out + 1] = e
				end
			end
		end
	end
	return out
end

return Entrances
