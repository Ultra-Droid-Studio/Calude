-- PedGraph: kaldırım yürüyüş grafiği (Aşama 6). SAF Lua; Roblox API'si yok (tools/test_ambient.py çalıştırır).
--
-- RoadBuilder'ın kaldırım geometrisini izler:
--   * Kaldırımlı yolun (Edge.Sidewalk) iki yanında, yol kenarından sw/2 içeride bir yürüyüş çizgisi
--     (yol kırpma + kaldırım kırpma mesafeleriyle aynı uçlar).
--   * Kaldırımlı dik kavşaklarda dört köşe karesi; kapalı kenarlarda kaldırım dolgusu (yürünür bağlantı).
--   * KARŞIYA GEÇİŞ yalnızca kavşak platformlarının açık kenarlarında, yaya geçidi çizgilerinin olduğu yerde
--     (kol başından sw/2 dışarıda). Bunun dışında yaya yola inmez.
-- Kaldırım bayrağı olmayan haritada grafik boş kalır → yaya doğmaz (geçersiz yolda NPC üretilmez).
--
-- graph.Nodes[id]  { Id, X, Y, Z, Links = {link}, Spot = {Kind, FaceX, FaceZ}? , Comp }
-- graph.Links[id]  { Id, A, B (düğüm), Length, Crossing, Node (kavşak), ArmEdge, ArmPhase }

local PedGraph = {}

local sqrt, floor, max, abs = math.sqrt, math.floor, math.max, math.abs
local GRID = 96

local function keyOf(x, z)
	return floor(x * 2 + 0.5) .. ":" .. floor(z * 2 + 0.5)
end

-- data: MapDefinitions verisi; tg: TrafficGraph.Build sonucu (pad + kırpma bilgisi ve kol fazları)
function PedGraph.Build(data, tg)
	local meta = data.Meta
	local sw = meta.Sidewalk or 8
	local top = meta.BlockTop or 0.8
	local graph = { Nodes = {}, Links = {}, Grid = {}, Top = top, RoadTop = meta.RoadTop or 0.3, Spots = {} }
	local byKey = {}

	local function node(x, z)
		local k = keyOf(x, z)
		local n = byKey[k]
		if not n then
			n = { Id = #graph.Nodes + 1, X = x, Y = top, Z = z, Links = {} }
			graph.Nodes[n.Id] = n
			byKey[k] = n
		end
		return n
	end
	local function link(a, b, crossing, info)
		if a == b then
			return nil
		end
		for _, l in ipairs(a.Links) do
			if (l.A == a and l.B == b) or (l.A == b and l.B == a) then
				return l
			end
		end
		local dx, dz = b.X - a.X, b.Z - a.Z
		local l = { Id = #graph.Links + 1, A = a, B = b, Length = sqrt(dx * dx + dz * dz), Crossing = crossing }
		if info then
			for k, v in pairs(info) do
				l[k] = v
			end
		end
		graph.Links[l.Id] = l
		a.Links[#a.Links + 1] = l
		b.Links[#b.Links + 1] = l
		return l
	end

	local endpoints = {} -- [nodeId] = { pedNode... }
	local walkTrim = tg.WalkTrim
	for _, e in ipairs(data.EdgeList) do
		if e.Sidewalk then
			local pa, pb = data.Nodes[e.A].Position, data.Nodes[e.B].Position
			local dx, dz = pb.X - pa.X, pb.Z - pa.Z
			local L = sqrt(dx * dx + dz * dz)
			if L > 2 then
				local ux, uz = dx / L, dz / L
				local rx, rz = -uz, ux
				local trims = walkTrim[e.Id]
				local ta = trims and trims[e.A] or 0
				local tb = trims and trims[e.B] or 0
				ta, tb = math.min(ta, L * 0.49), math.min(tb, L * 0.49)
				local off = e.Width / 2 + sw / 2
				for _, side in ipairs({ 1, -1 }) do
					local ax = pa.X + ux * ta + rx * off * side
					local az = pa.Z + uz * ta + rz * off * side
					local bx = pb.X - ux * tb + rx * off * side
					local bz = pb.Z - uz * tb + rz * off * side
					local na, nb = node(ax, az), node(bx, bz)
					link(na, nb, false, { Edge = e.Id })
					endpoints[e.A] = endpoints[e.A] or {}
					endpoints[e.B] = endpoints[e.B] or {}
					table.insert(endpoints[e.A], na)
					table.insert(endpoints[e.B], nb)
				end
			end
		end
	end

	-- Kavşak köşeleri, kenar dolguları ve geçitler
	local SIDES = {
		N = { { -1, -1 }, { 1, -1 } },
		S = { { -1, 1 }, { 1, 1 } },
		W = { { -1, -1 }, { -1, 1 } },
		E = { { 1, -1 }, { 1, 1 } },
	}
	for nodeId, pad in pairs(tg.Pads) do
		if pad.Kind == "Box" and pad.Walk then
			local tnode = tg.Nodes[nodeId]
			local hx, hz = pad.SX / 2, pad.SZ / 2
			local corners = {}
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					corners[sx .. ":" .. sz] = node(pad.X + sx * (hx + sw / 2), pad.Z + sz * (hz + sw / 2))
				end
			end
			-- kaldırım uçlarını en yakın köşeye bağla
			for _, en in ipairs(endpoints[nodeId] or {}) do
				local best, bestD = nil, math.huge
				for _, c in pairs(corners) do
					local d = (c.X - en.X) ^ 2 + (c.Z - en.Z) ^ 2
					if d < bestD then
						best, bestD = c, d
					end
				end
				if best and bestD < (sw * 3) ^ 2 then
					link(en, best, false)
				end
			end
			for side, pair in pairs(SIDES) do
				local a = corners[pair[1][1] .. ":" .. pair[1][2]]
				local b = corners[pair[2][1] .. ":" .. pair[2][2]]
				if pad.Open[side] then
					local armEdge = tnode and tnode.ArmEdge[side]
					link(a, b, true, {
						Node = nodeId, ArmEdge = armEdge, ArmPhase = (tnode and armEdge and tnode.ArmPhase[armEdge]) or 1,
						Signal = tnode and tnode.Control == "Signal",
					})
				else
					link(a, b, false) -- kapalı kenar: kaldırım dolgusu
				end
			end
		end
	end

	-- Bileşenler (çok küçük adacıklarda doğma yok)
	local comp = 0
	local sizes = {}
	for _, n in ipairs(graph.Nodes) do
		if not n.Comp then
			comp = comp + 1
			local stack, size = { n }, 0
			n.Comp = comp
			while #stack > 0 do
				local cur = table.remove(stack)
				size = size + 1
				for _, l in ipairs(cur.Links) do
					local o = (l.A == cur) and l.B or l.A
					if not o.Comp then
						o.Comp = comp
						stack[#stack + 1] = o
					end
				end
			end
			sizes[comp] = size
		end
	end
	graph.ComponentSizes = sizes

	-- Doğma ızgarası: geçit olmayan bağlantılar
	for _, l in ipairs(graph.Links) do
		if not l.Crossing and sizes[l.A.Comp] >= 6 then
			local steps = max(1, floor(l.Length / 40))
			local seen = {}
			for i = 0, steps do
				local t = i / steps
				local x, z = l.A.X + (l.B.X - l.A.X) * t, l.A.Z + (l.B.Z - l.A.Z) * t
				local k = floor(x / GRID) .. ":" .. floor(z / GRID)
				if not seen[k] then
					seen[k] = true
					local cell = graph.Grid[k]
					if not cell then
						cell = {}
						graph.Grid[k] = cell
					end
					cell[#cell + 1] = l
				end
			end
		end
	end

	-- Mola noktaları: dükkân girişleri, banklar, otobüs durakları → en yakın kaldırım düğümü
	local nodeGrid = {}
	for _, n in ipairs(graph.Nodes) do
		local k = floor(n.X / GRID) .. ":" .. floor(n.Z / GRID)
		nodeGrid[k] = nodeGrid[k] or {}
		table.insert(nodeGrid[k], n)
	end
	local function nearestNode(x, z, radius)
		local best, bestD = nil, radius * radius
		local cx, cz = floor(x / GRID), floor(z / GRID)
		for i = cx - 1, cx + 1 do
			for j = cz - 1, cz + 1 do
				for _, n in ipairs(nodeGrid[i .. ":" .. j] or {}) do
					local d = (n.X - x) ^ 2 + (n.Z - z) ^ 2
					if d < bestD then
						best, bestD = n, d
					end
				end
			end
		end
		return best
	end
	local function addSpot(kind, x, z)
		-- düğüm yerine en yakın bağlantı üzerindeki noktaya da bakılabilir; basit: en yakın düğüm (40 stud içinde)
		local n = nearestNode(x, z, 40)
		if n and not n.Spot then
			local fx, fz = x - n.X, z - n.Z
			local fl = sqrt(fx * fx + fz * fz)
			n.Spot = { Kind = kind, FaceX = fl > 0.1 and fx / fl or 0, FaceZ = fl > 0.1 and fz / fl or 1 }
			graph.Spots[#graph.Spots + 1] = n
		end
	end
	for _, p in ipairs(data.POIs or {}) do
		addSpot("Shop", p.Entrance.X, p.Entrance.Z)
	end
	for _, prop in ipairs(data.Props or {}) do
		if prop.Kind == "bench" or prop.Kind == "busstop" then
			addSpot(prop.Kind == "bench" and "Bench" or "Bus", prop.X, prop.Z)
		end
	end
	return graph
end

function PedGraph.LinksNear(graph, x, z, radius)
	local out, seen = {}, {}
	for i = floor((x - radius) / GRID), floor((x + radius) / GRID) do
		for j = floor((z - radius) / GRID), floor((z + radius) / GRID) do
			for _, l in ipairs(graph.Grid[i .. ":" .. j] or {}) do
				if not seen[l] then
					seen[l] = true
					out[#out + 1] = l
				end
			end
		end
	end
	return out
end

-- Basit A* (sınırlı): from → to düğüm listesi (from hariç). Bulamazsa nil.
function PedGraph.Path(_graph, from, to, maxNodes)
	if from == to then
		return {}
	end
	maxNodes = maxNodes or 600
	local open, came, g = { from }, {}, { [from] = 0 }
	local f = { [from] = sqrt((from.X - to.X) ^ 2 + (from.Z - to.Z) ^ 2) }
	local closed = {}
	local expanded = 0
	while #open > 0 do
		local bi, best = 1, open[1]
		for i = 2, #open do
			if f[open[i]] < f[best] then
				bi, best = i, open[i]
			end
		end
		table.remove(open, bi)
		if best == to then
			local path = {}
			local cur = to
			while cur ~= from do
				table.insert(path, 1, { Node = cur, Link = came[cur].Link })
				cur = came[cur].Node
			end
			return path
		end
		closed[best] = true
		expanded = expanded + 1
		if expanded > maxNodes then
			return nil
		end
		for _, l in ipairs(best.Links) do
			local o = (l.A == best) and l.B or l.A
			if not closed[o] then
				local cost = g[best] + l.Length + (l.Crossing and 12 or 0) -- gereksiz karşıya geçmeyi az tercih et
				if not g[o] or cost < g[o] then
					if not g[o] then
						open[#open + 1] = o
					end
					g[o] = cost
					f[o] = cost + sqrt((o.X - to.X) ^ 2 + (o.Z - to.Z) ^ 2)
					came[o] = { Node = best, Link = l }
				end
			end
		end
	end
	return nil
end

-- Bir noktanın bir yol yüzeyinin üstünde olup olmadığı (test ve hata ayıklama için)
-- y verilirse (yaya yüksekliği) üstten geçen köprü/otoyol yüzeyleri sayılmaz.
function PedGraph.OnRoad(data, tg, x, z, y)
	for _, e in ipairs(data.EdgeList) do
		local pa, pb = data.Nodes[e.A].Position, data.Nodes[e.B].Position
		local dx, dz = pb.X - pa.X, pb.Z - pa.Z
		local L2 = dx * dx + dz * dz
		if L2 > 1 then
			local t = ((x - pa.X) * dx + (z - pa.Z) * dz) / L2
			local ry = pa.Y + (pb.Y - pa.Y) * t
			if t > 0 and t < 1 and (not y or abs(ry - y) < 4) then
				local px, pz = pa.X + dx * t, pa.Z + dz * t
				if (x - px) ^ 2 + (z - pz) ^ 2 < (e.Width / 2 - 0.2) ^ 2 then
					return true, e.Id
				end
			end
		end
	end
	for _, pad in pairs(tg.Pads) do
		if pad.Kind == "Box" and abs(x - pad.X) < pad.SX / 2 - 0.2 and abs(z - pad.Z) < pad.SZ / 2 - 0.2
			and (not y or abs(pad.Y - y) < 4) then
			return true, "pad"
		end
	end
	return false
end

return PedGraph
