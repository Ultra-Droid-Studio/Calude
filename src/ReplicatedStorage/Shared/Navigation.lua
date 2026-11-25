-- Navigation: yol ağı üzerinde rota hesabı ve rota takibi (GPS). SAF modül; Instance kullanmaz.
--
-- TEK koordinat kaynağı: MapDefinitions (MapData'nın düğüm ve yolları). Burada yeni bir koordinat sistemi
-- yoktur; noktalar dünya stud'udur (X, Y, Z alanları olan her şey: Vector3 ya da { X=, Y=, Z= }).
--
--   nav = Navigation.new(MapDefinitions.GetData())
--   route, reason = nav:FindRoute(fromPos, toPos)      -- reason: "NoRoadNearStart" | "Unreachable"
--   progress = Navigation.Progress(route, position, hintIndex)
--
-- Kurallar:
--   * Rotalar sadece yollardan geçer; tek yönlü yollarda (rampa) yön kurallarına uyulur (LanesForward/Backward).
--   * Başlangıç/hedef en yakın yol parçasına "oturtulur" (yükseklik farkı cezalı: otoyolun altındaki sokak seçilir).
--   * Hedef yoldan uzaksa rota en yakın yol noktasına gider ve "Offroad" işaretlenir (son kısım düz çizgi).
--   * Ulaşılamayan hedefte nil + sebep döner; çağıran oyuncuya bildirir, çökmez.
--
-- Bu dosya bilerek "düz Lua" alt kümesiyle yazıldı; tools/test_navigation.py onu gerçek MapData ile
-- bir Lua yorumlayıcısında test eder.

local Navigation = {}
Navigation.__index = Navigation

local CELL = 256 -- uzamsal ızgara hücresi (stud)
local VERTICAL_PENALTY = 1.5 -- yükseklik farkının yatay mesafeye çarpanı (köprü/otoyol ayrımı)
local ABOVE_PENALTY = 6 -- oyuncunun çok ÜSTÜNDEKİ yol (otoyol tabliyesi) oradan erişilemez: ağır ceza
local ABOVE_MARGIN = 6 -- stud: bu kadardan fazla yukarıdaki yol "üstte" sayılır
local MAX_SNAP_RINGS = 10 -- en fazla ~2.5 km uzaktaki yola oturtulur
Navigation.OffroadDistance = 120 -- hedef yola bundan uzaksa "Offroad"

-- Luau: math.atan2(y, x). Lua 5.3+: math.atan(y, x). İkisinde de çalışsın (test yorumlayıcısı).
local atan2 = math.atan2 or math.atan

local function sqrt(x)
	return math.sqrt(x)
end

local function cellKey(cx, cz)
	return cx * 100000 + cz
end

-- ===== Kurulum =====
function Navigation.new(data)
	local self = setmetatable({}, Navigation)
	self.Nodes = {}
	self.Edges = {}
	self.Grid = {}
	self.Stamp = 0
	self.MaxSpeed = 1
	for id, n in pairs(data.Nodes) do
		local p = n.Position
		self.Nodes[id] = { Id = id, X = p.X, Y = p.Y, Z = p.Z, Out = {} }
	end
	for _, e in ipairs(data.EdgeList) do
		local a, b = self.Nodes[e.A], self.Nodes[e.B]
		if a and b then
			local dx, dy, dz = b.X - a.X, b.Y - a.Y, b.Z - a.Z
			local length = sqrt(dx * dx + dy * dy + dz * dz)
			local speed = math.max(e.Speed or 50, 20)
			if speed > self.MaxSpeed then
				self.MaxSpeed = speed
			end
			local rec = {
				Id = e.Id, A = a, B = b, Length = length, Speed = speed, Name = e.Name or "",
				Forward = (e.LanesForward or 1) > 0, Backward = (e.LanesBackward or 1) > 0,
				Width = e.Width or 20, Kind = e.Kind, Stamp = 0,
			}
			table.insert(self.Edges, rec)
			-- maliyet = süre (uzunluk / hız): ana yollar tercih edilir
			if rec.Forward then
				table.insert(a.Out, { To = b, Edge = rec, Cost = length / speed })
			end
			if rec.Backward then
				table.insert(b.Out, { To = a, Edge = rec, Cost = length / speed })
			end
			-- ızgaraya ekle (kenarın kapsadığı tüm hücreler)
			local pad = rec.Width / 2
			local x0 = math.floor((math.min(a.X, b.X) - pad) / CELL)
			local x1 = math.floor((math.max(a.X, b.X) + pad) / CELL)
			local z0 = math.floor((math.min(a.Z, b.Z) - pad) / CELL)
			local z1 = math.floor((math.max(a.Z, b.Z) + pad) / CELL)
			for cx = x0, x1 do
				for cz = z0, z1 do
					local key = cellKey(cx, cz)
					local list = self.Grid[key]
					if not list then
						list = {}
						self.Grid[key] = list
					end
					table.insert(list, rec)
				end
			end
		end
	end
	return self
end

-- ===== En yakın yol noktası =====
local function projectOnEdge(e, x, y, z)
	local ax, az = e.A.X, e.A.Z
	local dx, dz = e.B.X - ax, e.B.Z - az
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-6 then
		t = ((x - ax) * dx + (z - az) * dz) / len2
		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
	end
	local px, pz = ax + dx * t, az + dz * t
	local py = e.A.Y + (e.B.Y - e.A.Y) * t
	local hx, hz = x - px, z - pz
	local horizontal = sqrt(hx * hx + hz * hz)
	local rise = py - y
	local penalty = VERTICAL_PENALTY
	if rise > ABOVE_MARGIN then
		penalty = ABOVE_PENALTY
	end
	return t, px, py, pz, horizontal + math.abs(rise) * penalty, horizontal
end

-- Döndürür: { Edge, T, X, Y, Z, Distance (cezalı), Horizontal } ya da nil
function Navigation:Snap(position)
	local x, y, z = position.X, position.Y, position.Z
	local cx, cz = math.floor(x / CELL), math.floor(z / CELL)
	self.Stamp = self.Stamp + 1
	local stamp = self.Stamp
	local best = nil
	for ring = 0, MAX_SNAP_RINGS do
		for ix = cx - ring, cx + ring do
			for iz = cz - ring, cz + ring do
				if math.abs(ix - cx) == ring or math.abs(iz - cz) == ring then
					local list = self.Grid[cellKey(ix, iz)]
					if list then
						for _, e in ipairs(list) do
							if e.Stamp ~= stamp then
								e.Stamp = stamp
								local t, px, py, pz, d, h = projectOnEdge(e, x, y, z)
								if not best or d < best.Distance then
									best = { Edge = e, T = t, X = px, Y = py, Z = pz, Distance = d, Horizontal = h }
								end
							end
						end
					end
				end
			end
		end
		-- Bu halkadaki en kötü durumdaki nokta bile daha uzaksa aramayı bitir
		if best and best.Distance < ring * CELL then
			break
		end
	end
	return best
end

-- ===== İkili yığın (A* açık liste) =====
local function heapPush(heap, item, priority)
	local n = #heap + 1
	heap[n] = { Item = item, P = priority }
	while n > 1 do
		local parent = math.floor(n / 2)
		if heap[parent].P <= heap[n].P then
			break
		end
		heap[parent], heap[n] = heap[n], heap[parent]
		n = parent
	end
end

local function heapPop(heap)
	local count = #heap
	if count == 0 then
		return nil
	end
	local top = heap[1]
	heap[1] = heap[count]
	heap[count] = nil
	count = count - 1
	local n = 1
	while true do
		local l, r = n * 2, n * 2 + 1
		local smallest = n
		if l <= count and heap[l].P < heap[smallest].P then
			smallest = l
		end
		if r <= count and heap[r].P < heap[smallest].P then
			smallest = r
		end
		if smallest == n then
			break
		end
		heap[smallest], heap[n] = heap[n], heap[smallest]
		n = smallest
	end
	return top.Item, top.P
end

-- ===== Rota =====
local function point(x, y, z)
	return { X = x, Y = y, Z = z }
end

-- Başlangıç noktasından kenar uçlarına çıkış seçenekleri (tek yön kuralına uyarak)
local function exitsFrom(snap)
	local e, list = snap.Edge, {}
	if e.Forward then
		table.insert(list, { Node = e.B, Cost = (1 - snap.T) * e.Length / e.Speed })
	end
	if e.Backward then
		table.insert(list, { Node = e.A, Cost = snap.T * e.Length / e.Speed })
	end
	return list
end

-- Hedef kenara hangi uçtan girilebilir: düğüm → (kalan maliyet)
local function entriesTo(snap)
	local e, map = snap.Edge, {}
	if e.Forward then
		map[e.A] = snap.T * e.Length / e.Speed -- A'dan B yönüne gidip hedefte dur
	end
	if e.Backward then
		map[e.B] = (1 - snap.T) * e.Length / e.Speed
	end
	return map
end

function Navigation:FindRoute(from, to)
	local s = self:Snap(from)
	if not s then
		return nil, "NoRoadNearStart"
	end
	local g = self:Snap(to)
	if not g then
		return nil, "Unreachable"
	end
	local offroad = g.Horizontal > Navigation.OffroadDistance

	-- Aynı yol parçası ve izin verilen yönde → doğrudan
	if s.Edge == g.Edge then
		local e = s.Edge
		if (g.T >= s.T and e.Forward) or (g.T <= s.T and e.Backward) then
			return self:_build({ point(s.X, s.Y, s.Z), point(g.X, g.Y, g.Z) }, { e.Name }, to, offroad)
		end
	end

	local targets = entriesTo(g)
	local maxSpeed = self.MaxSpeed
	local function h(node)
		local dx, dz = g.X - node.X, g.Z - node.Z
		return sqrt(dx * dx + dz * dz) / maxSpeed
	end
	local cost, came, closed = {}, {}, {}
	local heap = {}
	for _, exit in ipairs(exitsFrom(s)) do
		if not cost[exit.Node] or exit.Cost < cost[exit.Node] then
			cost[exit.Node] = exit.Cost
			came[exit.Node] = { Edge = s.Edge }
			heapPush(heap, exit.Node, exit.Cost + h(exit.Node))
		end
	end
	local bestGoal, bestTotal = nil, math.huge
	while true do
		local node = heapPop(heap)
		if not node then
			break
		end
		if not closed[node] then
			closed[node] = true
			local base = cost[node]
			if base + h(node) >= bestTotal then
				break -- daha iyi bir çözüm kalmadı
			end
			local finish = targets[node]
			if finish and base + finish < bestTotal then
				bestTotal = base + finish
				bestGoal = node
			end
			for _, arc in ipairs(node.Out) do
				local next = arc.To
				local c = base + arc.Cost
				if not closed[next] and (not cost[next] or c < cost[next]) then
					cost[next] = c
					came[next] = { From = node, Edge = arc.Edge }
					heapPush(heap, next, c + h(next))
				end
			end
		end
	end
	if not bestGoal then
		return nil, "Unreachable"
	end

	-- Geri izle
	local nodes, names = {}, {}
	local n = bestGoal
	while n do
		table.insert(nodes, 1, n)
		local c = came[n]
		table.insert(names, 1, c and c.Edge.Name or "")
		n = c and c.From or nil
	end
	local points = { point(s.X, s.Y, s.Z) }
	local segmentNames = {}
	for i, node in ipairs(nodes) do
		table.insert(points, point(node.X, node.Y, node.Z))
		table.insert(segmentNames, names[i])
	end
	table.insert(points, point(g.X, g.Y, g.Z))
	table.insert(segmentNames, g.Edge.Name)
	return self:_build(points, segmentNames, to, offroad)
end

-- Lua 5.1 uyumlu üçlü seçim (Luau if-ifadesi düz Lua'da yok)
local function choose(condition, a, b)
	if condition then
		return a
	end
	return b
end

-- ===== Rota nesnesi + yönlendirme =====
-- segmentNames[i]: points[i] → points[i+1] parçasının sokak adı
function Navigation:_build(points, segmentNames, destination, offroad)
	-- art arda çok yakın noktaları birleştir (titrek yönlendirme olmasın)
	local clean, cleanNames = { points[1] }, {}
	for i = 2, #points do
		local p, q = clean[#clean], points[i]
		local dx, dz = q.X - p.X, q.Z - p.Z
		if dx * dx + dz * dz > 1 or i == #points then
			table.insert(clean, q)
			table.insert(cleanNames, segmentNames[i - 1] or "")
		end
	end
	if #clean < 2 then
		table.insert(clean, points[#points])
		table.insert(cleanNames, segmentNames[#segmentNames] or "")
	end
	local cum = { 0 }
	for i = 2, #clean do
		local p, q = clean[i - 1], clean[i]
		local dx, dy, dz = q.X - p.X, q.Y - p.Y, q.Z - p.Z
		cum[i] = cum[i - 1] + sqrt(dx * dx + dy * dy + dz * dz)
	end
	local route = {
		Points = clean,
		Names = cleanNames,
		Cum = cum,
		Length = cum[#cum],
		Offroad = offroad == true,
		Destination = point(destination.X, destination.Y, destination.Z),
		Maneuvers = {},
	}
	-- Dönüşler: (y ekseni ekranda aşağı) çapraz çarpım > 0 → saat yönü → SAĞ
	for i = 2, #clean - 1 do
		local a, b, c = clean[i - 1], clean[i], clean[i + 1]
		local ux, uz = b.X - a.X, b.Z - a.Z
		local vx, vz = c.X - b.X, c.Z - b.Z
		local lu, lv = sqrt(ux * ux + uz * uz), sqrt(vx * vx + vz * vz)
		if lu > 0.5 and lv > 0.5 then
			local cross = (ux * vz - uz * vx) / (lu * lv)
			local dot = (ux * vx + uz * vz) / (lu * lv)
			local angle = math.deg(atan2(cross, dot)) -- + sağ, - sol
			local abs = math.abs(angle)
			local kind = nil
			if abs >= 150 then
				kind = "UTurn"
			elseif abs >= 60 then
				kind = choose(angle > 0, "Right", "Left")
			elseif abs >= 25 then
				kind = choose(angle > 0, "SlightRight", "SlightLeft")
			elseif cleanNames[i] ~= cleanNames[i - 1] and cleanNames[i] ~= "" then
				kind = "Continue" -- yön aynı, yol adı değişiyor
			end
			if kind then
				table.insert(route.Maneuvers, { Index = i, Type = kind, Angle = angle, Street = cleanNames[i] or "", Distance = cum[i] })
			end
		end
	end
	table.insert(route.Maneuvers, { Index = #clean, Type = "Arrive", Angle = 0, Street = "", Distance = route.Length })
	return route
end

-- ===== Takip =====
-- Döndürür: { Segment, Along (rota başından mesafe), Remaining, Deviation (rotadan sapma), Next (sonraki
-- manevra), NextDistance, NextIndex }. hint: önceki Segment (aramayı yakın çevreyle sınırlar)
function Navigation.Progress(route, position, hint)
	local points, cum = route.Points, route.Cum
	local x, y, z = position.X, position.Y, position.Z
	local first, last = 1, #points - 1
	if hint then
		first = math.max(1, hint - 2)
		last = math.min(#points - 1, hint + 12)
	end
	local bestSeg, bestD, bestAlong = nil, math.huge, 0
	for i = first, last do
		local a, b = points[i], points[i + 1]
		local dx, dz = b.X - a.X, b.Z - a.Z
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 1e-6 then
			t = ((x - a.X) * dx + (z - a.Z) * dz) / len2
			if t < 0 then
				t = 0
			elseif t > 1 then
				t = 1
			end
		end
		local px, pz = a.X + dx * t, a.Z + dz * t
		local py = a.Y + (b.Y - a.Y) * t
		local hx, hz = x - px, z - pz
		local d = sqrt(hx * hx + hz * hz) + math.abs(y - py) * VERTICAL_PENALTY * 0.5
		if d < bestD then
			bestD = d
			bestSeg = i
			bestAlong = cum[i] + (cum[i + 1] - cum[i]) * t
		end
	end
	if hint and bestD > 60 then
		-- yakın pencerede bulunamadı (ışınlanma vb.): tüm rotada ara
		return Navigation.Progress(route, position, nil)
	end
	local nextManeuver = nil
	for _, m in ipairs(route.Maneuvers) do
		if m.Distance > bestAlong + 1 then
			nextManeuver = m
			break
		end
	end
	if not nextManeuver then
		nextManeuver = route.Maneuvers[#route.Maneuvers]
	end
	return {
		Segment = bestSeg or 1,
		Along = bestAlong,
		Remaining = math.max(route.Length - bestAlong, 0),
		Deviation = bestD,
		Next = nextManeuver,
		NextDistance = math.max(nextManeuver.Distance - bestAlong, 0),
	}
end

return Navigation
