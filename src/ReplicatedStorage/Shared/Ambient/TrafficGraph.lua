-- TrafficGraph: MapDefinitions yol grafiğinden ŞERİT + KAVŞAK grafiği (trafik ve yaya yapay zekâsı).
--
-- SAF Lua: Roblox API'si kullanmaz. tools/test_ambient.py bu dosyayı gerçek harita verisiyle (lupa) çalıştırır.
-- Konumlar .X/.Y/.Z alanlarından okunur (Vector3 veya düz tablo); üretilen tüm koordinatlar düz sayıdır.
--
-- Geometri RoadBuilder ile AYNI kurallardan türetilir:
--   * Kavşak platformu (pad) boyutu ve yol kırpma mesafeleri  → RoadBuilder.planNodes
--   * Şerit merkezleri                                         → RoadBuilder şerit çizgileri (sarı orta çizgi,
--                                                                beyaz şerit çizgisi, otoyol refüjü)
--   * Sağdan trafik. Şerit 1 = en içteki (orta çizgiye en yakın), şerit N = kaldırım tarafı.
--
-- Çıktı:
--   graph.Lanes[i]        { Id, Edge, Kind, From, To, Index, Count, Offset, LaneWidth, X0,Y0,Z0, X1,Y1,Z1,
--                           Length, UX, UZ, Speed, StopS, Out = {conn}, In = {conn}, Group = {lane...}, Vehicles = {} }
--   graph.Connectors[i]   { Id, From = lane, To = lane, Node, Turn ("S"|"L"|"R"|"U"), PX/PY/PZ (dizi), Cum, Length,
--                           MaxSpeed, Phase, Vehicles = {} }
--   graph.Nodes[id]       { Id, X,Y,Z, Degree, Control ("Free"|"Signal"|"Stop"|"Yield"), Pad, ArmPhase, ArmEdge,
--                           Connectors = {}, Reserved = {}, Waiting = {} }

local TrafficGraph = {}

local sqrt, abs, floor, max, min = math.sqrt, math.abs, math.floor, math.max, math.min
local atan2 = math.atan2 or math.atan

local INNER = { street = 0.25, country = 0.25, avenue = 0.8, highway = 0.8, freeway = 1.2 } -- orta çizgi/refüj payı
local OUTER = { highway = 1.0, freeway = 1.2 } -- kenar çizgisi/bariyer payı
local CURVE_SAMPLES = 8
local GRID = 200

local function clamp(x, a, b)
	if x < a then
		return a
	elseif x > b then
		return b
	end
	return x
end

local function axisOf(dx, dz)
	if dx > 0.99 then
		return "E"
	elseif dx < -0.99 then
		return "W"
	elseif dz > 0.99 then
		return "S"
	elseif dz < -0.99 then
		return "N"
	end
	return nil
end
TrafficGraph.AxisOf = axisOf

local function flatDir(ax, az, bx, bz)
	local dx, dz = bx - ax, bz - az
	local l = sqrt(dx * dx + dz * dz)
	if l < 1e-6 then
		return 1, 0
	end
	return dx / l, dz / l
end

-- ===== RoadBuilder.planNodes ile aynı kırpma/platform kuralları =====
local function planNodes(data)
	local roadTrim, walkTrim, pads = {}, {}, {}
	local sidewalkW = data.Meta.Sidewalk or 8
	local function setTrim(edgeId, nodeId, road, walk)
		roadTrim[edgeId] = roadTrim[edgeId] or {}
		walkTrim[edgeId] = walkTrim[edgeId] or {}
		roadTrim[edgeId][nodeId] = road
		walkTrim[edgeId][nodeId] = walk
	end
	for _, node in ipairs(data.NodeList) do
		local p = node.Position
		local adj = {}
		for _, edgeId in ipairs(node.Edges) do
			local e = data.Edges[edgeId]
			local otherId = (e.A == node.Id) and e.B or e.A
			local o = data.Nodes[otherId].Position
			local dx, dz = flatDir(p.X, p.Z, o.X, o.Z)
			adj[#adj + 1] = { Edge = e, DX = dx, DZ = dz, Width = e.Width, Sidewalk = e.Sidewalk, Ramp = e.Kind == "ramp" }
		end
		local elevated = p.Y > 2
		if #adj > 1 then
			local allAxis = true
			for _, a in ipairs(adj) do
				if not axisOf(a.DX, a.DZ) then
					allAxis = false
					break
				end
			end
			if allAxis then
				local w = { E = 0, W = 0, N = 0, S = 0 }
				local anyWalk = false
				for _, a in ipairs(adj) do
					local ax = axisOf(a.DX, a.DZ)
					w[ax] = max(w[ax], a.Width)
					anyWalk = anyWalk or a.Sidewalk
				end
				local collinear = #adj == 2 and ((w.E > 0 and w.W > 0) or (w.N > 0 and w.S > 0))
				if not collinear then
					local wNS, wEW = max(w.N, w.S), max(w.E, w.W)
					local sx = (wNS > 0) and wNS or wEW
					local sz = (wEW > 0) and wEW or wNS
					for _, a in ipairs(adj) do
						local ax = axisOf(a.DX, a.DZ)
						local half = (ax == "E" or ax == "W") and sx / 2 or sz / 2
						setTrim(a.Edge.Id, node.Id, half, half + (anyWalk and sidewalkW or 0))
					end
					pads[node.Id] = {
						Kind = "Box", X = p.X, Y = p.Y, Z = p.Z, SX = sx, SZ = sz, Walk = anyWalk,
						Open = { E = w.E > 0, W = w.W > 0, N = w.N > 0, S = w.S > 0 },
					}
				end
			else
				local mains, ramps = {}, {}
				for _, a in ipairs(adj) do
					if a.Ramp then
						ramps[#ramps + 1] = a
					else
						mains[#mains + 1] = a
					end
				end
				local maxW = 0
				for _, a in ipairs(mains) do
					maxW = max(maxW, a.Width)
				end
				if #mains == 2 and (mains[1].DX * mains[2].DX + mains[1].DZ * mains[2].DZ) < -0.98 then
					for _, r in ipairs(ramps) do
						local t = elevated and (maxW / 2 - 4) or (maxW / 2)
						setTrim(r.Edge.Id, node.Id, t, t)
					end
				elseif #mains == 2 and #ramps == 0 then
					pads[node.Id] = { Kind = "Disc", X = p.X, Y = p.Y, Z = p.Z, SX = maxW, SZ = maxW }
				else
					local size = max(maxW, 16)
					for _, a in ipairs(adj) do
						setTrim(a.Edge.Id, node.Id, size / 2, size / 2)
					end
					pads[node.Id] = { Kind = "Dir", X = p.X, Y = p.Y, Z = p.Z, SX = size, SZ = size }
				end
			end
		end
	end
	return roadTrim, walkTrim, pads
end

local function laneOffsets(kind, width, n, otherN)
	local offs = {}
	local outer = OUTER[kind] or 0
	local lw
	if otherN > 0 then
		local inner = INNER[kind] or 0.3
		lw = (width / 2 - inner - outer) / n
		for k = 1, n do
			offs[k] = inner + lw * (k - 0.5)
		end
	else
		lw = (width - 2 * outer) / n
		for k = 1, n do
			offs[k] = -width / 2 + outer + lw * (k - 0.5)
		end
	end
	return offs, lw
end

-- ===== Kavşak bağlantı eğrisi (ikinci derece Bezier) =====
local function makeCurve(conn, l, o)
	local x0, y0, z0 = l.X1, l.Y1, l.Z1
	local x2, y2, z2 = o.X0, o.Y0, o.Z0
	local ix, iz, ox, oz = l.UX, l.UZ, o.UX, o.UZ
	local dx, dz = x2 - x0, z2 - z0
	local chord = sqrt(dx * dx + dz * dz)
	local cx, cz = (x0 + x2) / 2, (z0 + z2) / 2
	if conn.Turn == "U" then
		local w = max(chord, 4)
		cx, cz = (x0 + x2) / 2 + ix * w, (z0 + z2) / 2 + iz * w
	else
		local det = ix * oz - ox * iz
		if abs(det) > 0.05 then
			local t = (dx * oz - ox * dz) / det
			local u = (ix * dz - dx * iz) / det
			if t > 0 and u > 0 and t < 4 * chord + 10 then
				cx, cz = x0 + ix * t, z0 + iz * t
			end
		end
	end
	local PX, PY, PZ, Cum = {}, {}, {}, {}
	local total = 0
	for s = 0, CURVE_SAMPLES do
		local t = s / CURVE_SAMPLES
		local a, b, c = (1 - t) * (1 - t), 2 * (1 - t) * t, t * t
		local x = a * x0 + b * cx + c * x2
		local z = a * z0 + b * cz + c * z2
		local y = y0 + (y2 - y0) * t
		local n = s + 1
		if n > 1 then
			local ddx, ddy, ddz = x - PX[n - 1], y - PY[n - 1], z - PZ[n - 1]
			total = total + sqrt(ddx * ddx + ddy * ddy + ddz * ddz)
		end
		PX[n], PY[n], PZ[n], Cum[n] = x, y, z, total
	end
	conn.PX, conn.PY, conn.PZ, conn.Cum = PX, PY, PZ, Cum
	conn.Length = max(total, 0.5)
	-- Dönüş yarıçapı → güvenli hız (yanal ivme sınırı)
	local cross = ix * oz - iz * ox
	local dot = ix * ox + iz * oz
	local theta = abs(atan2(cross, dot))
	if theta < 0.2 then
		conn.Radius = 1e6
	else
		conn.Radius = max(chord / (2 * math.sin(theta / 2)), 3)
	end
end

local function classify(l, o)
	local cross = l.UX * o.UZ - l.UZ * o.UX
	local dot = l.UX * o.UX + l.UZ * o.UZ
	local angle = math.deg(atan2(cross, dot)) -- + sağ, - sol (ekranda z aşağı)
	if abs(angle) > 150 then
		return "U", angle
	elseif abs(angle) <= 35 then
		return "S", angle
	elseif angle > 0 then
		return "R", angle
	end
	return "L", angle
end

-- in-şerit l → out-şerit o geçerli mi (şerit kuralları)
local function laneRule(turn, l, o, free)
	if free or turn == "S" then
		-- kaldırım tarafına hizalı eşleme: 2→2 aynı şerit, rampa(1)→otoyol(2) kaldırım şeridi, otoyol→rampa sadece dış şerit
		return o.Index == o.Count - (l.Count - l.Index)
	elseif turn == "R" then
		return l.Index == l.Count and o.Index == o.Count
	end
	return l.Index == 1 and o.Index == 1 -- L ve U
end

-- data: MapDefinitions.GetData() biçiminde (Nodes, NodeList, Edges, EdgeList, Meta)
-- cfg:  AmbientConfig.Traffic. opts.Yield: (fonksiyon) uzun kurulumda ara sıra çağrılır.
function TrafficGraph.Build(data, cfg, opts)
	opts = opts or {}
	local yieldFn = opts.Yield
	local roadTrim, walkTrim, pads = planNodes(data)
	local graph = {
		Lanes = {}, Connectors = {}, Nodes = {}, Grid = {}, Pads = pads, RoadTrim = roadTrim, WalkTrim = walkTrim,
		Meta = data.Meta, Cfg = cfg,
	}
	local signal = cfg.Signal

	-- Düğümler
	for _, n in ipairs(data.NodeList) do
		local p = n.Position
		graph.Nodes[n.Id] = {
			Id = n.Id, X = p.X, Y = p.Y, Z = p.Z, Degree = #n.Edges, Pad = pads[n.Id],
			Signal = n.Signal, Stop = n.Stop, Crosswalk = n.Crosswalk,
			Connectors = {}, InLanes = {}, OutLanes = {}, ArmPhase = {}, ArmEdge = {}, ArmEdges = {},
			Reserved = {}, Waiting = {}, Offset = (n.Id * 7.31) % (2 * (signal.Green + signal.Yellow + signal.AllRed)),
		}
	end

	-- Şeritler
	local function trimOf(edgeId, nodeId)
		local t = roadTrim[edgeId]
		return t and t[nodeId] or 0
	end
	local count = 0
	for _, e in ipairs(data.EdgeList) do
		local nA, nB = data.Nodes[e.A], data.Nodes[e.B]
		if nA and nB then
			for pass = 1, 2 do
				local from, to, n, other
				if pass == 1 then
					from, to, n, other = nA, nB, e.LanesForward, e.LanesBackward
				else
					from, to, n, other = nB, nA, e.LanesBackward, e.LanesForward
				end
				if n and n > 0 then
					local P, Q = from.Position, to.Position
					local dx, dz = Q.X - P.X, Q.Z - P.Z
					local L = sqrt(dx * dx + dz * dz)
					if L > 1 then
						local ux, uz = dx / L, dz / L
						local rx, rz = -uz, ux -- sağ
						local tP = min(trimOf(e.Id, from.Id), L * 0.45)
						local tQ = min(trimOf(e.Id, to.Id), L * 0.45)
						local offs, lw = laneOffsets(e.Kind, e.Width, n, other or 0)
						local group = {}
						for k = 1, n do
							local off = offs[k]
							local lane = {
								Id = #graph.Lanes + 1, Edge = e.Id, Kind = e.Kind, From = from.Id, To = to.Id,
								Index = k, Count = n, Offset = off, LaneWidth = lw,
								X0 = P.X + ux * tP + rx * off, Y0 = P.Y + (Q.Y - P.Y) * tP / L, Z0 = P.Z + uz * tP + rz * off,
								X1 = Q.X - ux * tQ + rx * off, Y1 = Q.Y + (P.Y - Q.Y) * tQ / L, Z1 = Q.Z - uz * tQ + rz * off,
								UX = ux, UZ = uz, RX = rx, RZ = rz, Speed = e.Speed, Out = {}, In = {}, Group = group, Vehicles = {},
							}
							local lx, ly, lz = lane.X1 - lane.X0, lane.Y1 - lane.Y0, lane.Z1 - lane.Z0
							lane.Length = sqrt(lx * lx + ly * ly + lz * lz)
							group[k] = lane
							graph.Lanes[#graph.Lanes + 1] = lane
							local gTo, gFrom = graph.Nodes[to.Id], graph.Nodes[from.Id]
							gTo.InLanes[#gTo.InLanes + 1] = lane
							gFrom.OutLanes[#gFrom.OutLanes + 1] = lane
						end
					end
				end
			end
		end
		count = count + 1
		if yieldFn and count % 60 == 0 then
			yieldFn()
		end
	end

	-- Kavşak kontrolü, kol fazları, durma çizgileri
	for _, node in pairs(graph.Nodes) do
		local refX, refZ = nil, nil
		local arms = {}
		for _, lane in ipairs(node.InLanes) do
			arms[lane.Edge] = { -lane.UX, -lane.UZ } -- düğümden dışarı
		end
		for _, lane in ipairs(node.OutLanes) do
			arms[lane.Edge] = { lane.UX, lane.UZ }
		end
		local edgeIds = {}
		for edgeId in pairs(arms) do
			edgeIds[#edgeIds + 1] = edgeId
		end
		table.sort(edgeIds)
		for _, edgeId in ipairs(edgeIds) do
			local d = arms[edgeId]
			if not refX then
				refX, refZ = d[1], d[2]
			end
			local phase = (abs(d[1] * refX + d[2] * refZ) > 0.7) and 1 or 2
			node.ArmPhase[edgeId] = phase
			local axis = axisOf(d[1], d[2])
			if axis then
				node.ArmEdge[axis] = edgeId
			end
			node.ArmEdges[#node.ArmEdges + 1] = edgeId
		end
		if node.Degree <= 2 then
			node.Control = "Free"
		elseif node.Signal then
			node.Control = "Signal"
		elseif node.Stop then
			node.Control = "Stop"
		else
			node.Control = "Yield"
		end
		local back = 1.5
		if node.Control ~= "Free" and node.Crosswalk and node.Pad and node.Pad.Kind == "Box" then
			back = 9 -- yaya geçidinin önünde dur (çizgiler kol başından 1..7 stud içeride)
		end
		for _, lane in ipairs(node.InLanes) do
			lane.StopS = max(lane.Length - back, lane.Length * 0.5)
		end
	end

	-- Bağlantılar
	count = 0
	for _, node in pairs(graph.Nodes) do
		local free = node.Degree <= 2
		for _, l in ipairs(node.InLanes) do
			for _, o in ipairs(node.OutLanes) do
				if o.Edge ~= l.Edge or node.Degree == 1 then
					local turn = classify(l, o)
					if laneRule(turn, l, o, free) then
						TrafficGraph._connect(graph, node, l, o, turn)
					end
				end
			end
		end
		-- Hiç çıkışı olmayan şerit kalmasın: her hedef kola en uygun şeritten bağla
		for _, l in ipairs(node.InLanes) do
			if #l.Out == 0 then
				local byEdge = {}
				for _, o in ipairs(node.OutLanes) do
					if o.Edge ~= l.Edge or node.Degree == 1 then
						local best = byEdge[o.Edge]
						local score = abs((o.Count - o.Index) - (l.Count - l.Index))
						if not best or score < best.Score then
							byEdge[o.Edge] = { Lane = o, Score = score }
						end
					end
				end
				for _, b in pairs(byEdge) do
					TrafficGraph._connect(graph, node, l, b.Lane, (classify(l, b.Lane)))
				end
			end
		end
		count = count + 1
		if yieldFn and count % 40 == 0 then
			yieldFn()
		end
	end

	-- Yumurtlama ızgarası: şerit üzerindeki örnek noktalar
	for _, lane in ipairs(graph.Lanes) do
		local steps = max(1, floor(lane.Length / 80))
		local seen = {}
		for i = 0, steps do
			local t = i / steps
			local x = lane.X0 + (lane.X1 - lane.X0) * t
			local z = lane.Z0 + (lane.Z1 - lane.Z0) * t
			local key = floor(x / GRID) .. ":" .. floor(z / GRID)
			if not seen[key] then
				seen[key] = true
				local cell = graph.Grid[key]
				if not cell then
					cell = {}
					graph.Grid[key] = cell
				end
				cell[#cell + 1] = lane
			end
		end
	end
	return graph
end

function TrafficGraph._connect(graph, node, l, o, turn)
	local conn = {
		Id = #graph.Connectors + 1, From = l, To = o, Node = node.Id, Turn = turn,
		Phase = node.ArmPhase[l.Edge] or 1, Vehicles = {},
	}
	makeCurve(conn, l, o)
	local cfg = graph.Cfg
	local speedLimit = min(l.Speed, o.Speed)
	if conn.Radius < 1e5 then
		speedLimit = min(speedLimit, sqrt(cfg.TurnLateralAccel * conn.Radius))
	end
	conn.MaxSpeed = max(speedLimit, 6)
	graph.Connectors[conn.Id] = conn
	l.Out[#l.Out + 1] = conn
	o.In[#o.In + 1] = conn
	node.Connectors[#node.Connectors + 1] = conn
	return conn
end

-- ===== Sorgular =====
function TrafficGraph.LanesNear(graph, x, z, radius)
	local out, seen = {}, {}
	local c0x, c1x = floor((x - radius) / GRID), floor((x + radius) / GRID)
	local c0z, c1z = floor((z - radius) / GRID), floor((z + radius) / GRID)
	for cx = c0x, c1x do
		for cz = c0z, c1z do
			local cell = graph.Grid[cx .. ":" .. cz]
			if cell then
				for _, lane in ipairs(cell) do
					if not seen[lane] then
						seen[lane] = true
						out[#out + 1] = lane
					end
				end
			end
		end
	end
	return out
end

function TrafficGraph.LanePoint(lane, s)
	local t = (lane.Length > 0) and clamp(s / lane.Length, 0, 1) or 0
	return lane.X0 + (lane.X1 - lane.X0) * t, lane.Y0 + (lane.Y1 - lane.Y0) * t, lane.Z0 + (lane.Z1 - lane.Z0) * t, lane.UX, lane.UZ
end

-- Yön: eğri parçasının yönü; parça sıfır uzunluktaysa (düz birleşimde şerit ucu = sonraki şerit başı)
-- giriş şeridinin yönü kullanılır — yön asla (0, 0) olmaz.
local function headingOf(conn, hx, hz)
	local hl = sqrt(hx * hx + hz * hz)
	if hl < 1e-4 then
		return conn.From.UX, conn.From.UZ
	end
	return hx / hl, hz / hl
end

function TrafficGraph.ConnPoint(conn, s)
	local cum = conn.Cum
	local n = #cum
	if s <= 0 then
		local hx, hz = headingOf(conn, conn.PX[2] - conn.PX[1], conn.PZ[2] - conn.PZ[1])
		return conn.PX[1], conn.PY[1], conn.PZ[1], hx, hz
	end
	for i = 2, n do
		if cum[i] >= s or i == n then
			local seg = max(cum[i] - cum[i - 1], 1e-6)
			local t = clamp((s - cum[i - 1]) / seg, 0, 1)
			local dx, dz = conn.PX[i] - conn.PX[i - 1], conn.PZ[i] - conn.PZ[i - 1]
			local hx, hz = headingOf(conn, dx, dz)
			return conn.PX[i - 1] + dx * t, conn.PY[i - 1] + (conn.PY[i] - conn.PY[i - 1]) * t, conn.PZ[i - 1] + dz * t, hx, hz
		end
	end
	local hx, hz = headingOf(conn, 0, 0)
	return conn.PX[n], conn.PY[n], conn.PZ[n], hx, hz
end

-- Işık durumu: "G" | "Y" | "R" ve bu durumun kalan süresi. time: sunucu zamanı (tüm oyuncularda aynı)
function TrafficGraph.SignalState(graph, node, phase, time)
	local s = graph.Cfg.Signal
	local half = s.Green + s.Yellow + s.AllRed
	local cycle = 2 * half
	local t = (time + node.Offset) % cycle
	local tp = (t - (phase - 1) * half) % cycle
	if tp < s.Green then
		return "G", s.Green - tp
	elseif tp < s.Green + s.Yellow then
		return "Y", s.Green + s.Yellow - tp
	end
	return "R", cycle - tp
end

-- Yaya: kolu (o kolun trafiği kırmızıyken) geçebilir mi? Diğer faz yeşil ve kalan süre yetiyorsa.
function TrafficGraph.WalkAllowed(graph, node, armPhase, time, crossSeconds)
	local other = (armPhase == 1) and 2 or 1
	local state, remaining = TrafficGraph.SignalState(graph, node, other, time)
	return state == "G" and remaining > crossSeconds, state, remaining
end

-- ===== Çatışma haritası (tembel; düğüm başına bir kez) =====
local function segCross(ax, az, bx, bz, cx, cz, dx, dz)
	local d1x, d1z, d2x, d2z = bx - ax, bz - az, dx - cx, dz - cz
	local den = d1x * d2z - d1z * d2x
	if abs(den) < 1e-9 then
		return false
	end
	local t = ((cx - ax) * d2z - (cz - az) * d2x) / den
	local u = ((cx - ax) * d1z - (cz - az) * d1x) / den
	return t > 0.02 and t < 0.98 and u > 0.02 and u < 0.98
end

local CLEARANCE = 7.5 -- iki eğri bu kadar yaklaşıyorsa (araç gövdeleri sürtünür) çakışma say

local function pathsCross(a, b)
	for i = 1, #a.PX - 1 do
		for j = 1, #b.PX - 1 do
			if segCross(a.PX[i], a.PZ[i], a.PX[i + 1], a.PZ[i + 1], b.PX[j], b.PZ[j], b.PX[j + 1], b.PZ[j + 1]) then
				return true
			end
		end
	end
	-- kesişmese de gövdeler sürtünecek kadar yakın geçiyorsa (karşılıklı sola dönüşler gibi)
	local c2 = CLEARANCE * CLEARANCE
	for i = 2, #a.PX - 1 do
		for j = 2, #b.PX - 1 do
			local dx, dz = a.PX[i] - b.PX[j], a.PZ[i] - b.PZ[j]
			if dx * dx + dz * dz < c2 then
				return true
			end
		end
	end
	return false
end

function TrafficGraph.Conflicts(_graph, node)
	if node.ConflictMap then
		return node.ConflictMap
	end
	local map = {}
	local list = node.Connectors
	for i = 1, #list do
		map[list[i]] = map[list[i]] or {}
	end
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			local conflict = false
			if a.To == b.To then
				conflict = a.From ~= b.From -- aynı şeride birleşme
			elseif a.From.Group ~= b.From.Group then
				conflict = pathsCross(a, b)
			end
			if conflict then
				map[a][b] = true
				map[b][a] = true
			end
		end
	end
	node.ConflictMap = map
	return map
end

return TrafficGraph
