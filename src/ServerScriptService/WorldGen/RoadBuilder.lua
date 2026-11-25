-- RoadBuilder: yol yüzeyleri, kavşak platformları, kaldırımlar, şerit çizgileri, yaya geçitleri,
-- otoyol bariyerleri ve köprüler. Tüm geometri MapDefinitions'taki yol grafiğinden türetilir;
-- trafik/GPS sistemleri (Aşama 4/9) aynı düğüm ve kenarları kullanır.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapDefinitions = require(ReplicatedStorage.Shared.MapDefinitions)

local RoadBuilder = {}

local LINE_T = 0.06
local LINE_LIFT = 0.03

type Adj = { Edge: any, Dir: Vector2, Width: number, Sidewalk: boolean, Ramp: boolean }

local function flatDir(from: Vector3, to: Vector3): Vector2
	local d = Vector2.new(to.X - from.X, to.Z - from.Z)
	if d.Magnitude < 1e-6 then
		return Vector2.new(1, 0)
	end
	return d.Unit
end

local function axisOf(dir: Vector2): string?
	if dir.X > 0.99 then
		return "E"
	elseif dir.X < -0.99 then
		return "W"
	elseif dir.Y > 0.99 then
		return "S"
	elseif dir.Y < -0.99 then
		return "N"
	end
	return nil
end

-- Her (kenar, düğüm) çifti için yol ve kaldırım kırpma mesafeleri + kavşak geometrisi
local function planNodes(data)
	local roadTrim: { [number]: { [number]: number } } = {}
	local walkTrim: { [number]: { [number]: number } } = {}
	local pads = {} -- { Position, SizeX, SizeZ, Dir (Vector2?), Thickness, Disc, Sidewalk = {...} }
	local function setTrim(edgeId: number, nodeId: number, road: number, walk: number)
		roadTrim[edgeId] = roadTrim[edgeId] or {}
		walkTrim[edgeId] = walkTrim[edgeId] or {}
		roadTrim[edgeId][nodeId] = road
		walkTrim[edgeId][nodeId] = walk
	end

	local sidewalkW = data.Meta.Sidewalk
	for _, node in data.NodeList do
		local adj: { Adj } = {}
		for _, edgeId in node.Edges do
			local e = data.Edges[edgeId]
			local otherId = if e.A == node.Id then e.B else e.A
			local other = data.Nodes[otherId]
			table.insert(adj, {
				Edge = e,
				Dir = flatDir(node.Position, other.Position),
				Width = e.Width,
				Sidewalk = e.Sidewalk,
				Ramp = e.Kind == "ramp",
			})
		end
		local elevated = node.Position.Y > 2
		local thickness = if elevated then 2 else 1
		local allAxis = true
		for _, a in adj do
			if not axisOf(a.Dir) then
				allAxis = false
				break
			end
		end

		if #adj <= 1 then
			continue
		end

		if allAxis then
			local w = { E = 0, W = 0, N = 0, S = 0 }
			local anyWalk = false
			for _, a in adj do
				local ax = axisOf(a.Dir) :: string
				w[ax] = math.max(w[ax], a.Width)
				anyWalk = anyWalk or a.Sidewalk
			end
			local collinear = #adj == 2 and ((w.E > 0 and w.W > 0) or (w.N > 0 and w.S > 0))
			if collinear then
				continue -- düz devam: kırpma yok, platform yok
			end
			local wNS = math.max(w.N, w.S)
			local wEW = math.max(w.E, w.W)
			local sx = if wNS > 0 then wNS else wEW
			local sz = if wEW > 0 then wEW else wNS
			for _, a in adj do
				local ax = axisOf(a.Dir)
				local half = if ax == "E" or ax == "W" then sx / 2 else sz / 2
				setTrim(a.Edge.Id, node.Id, half, half + (if anyWalk then sidewalkW else 0))
			end
			table.insert(pads, {
				Position = node.Position, SizeX = sx, SizeZ = sz, Dir = nil, Thickness = thickness,
				Disc = false, Walk = anyWalk, Open = { E = w.E > 0, W = w.W > 0, N = w.N > 0, S = w.S > 0 },
				Crosswalk = node.Crosswalk, Adj = adj,
			})
		else
			local mains, ramps = {}, {}
			for _, a in adj do
				table.insert(if a.Ramp then ramps else mains, a)
			end
			local maxW = 0
			for _, a in mains do
				maxW = math.max(maxW, a.Width)
			end
			if #mains == 2 and mains[1].Dir:Dot(mains[2].Dir) < -0.98 then
				-- Düz ana yol + yan rampalar: rampa kenarı otoyol tabliyesinin kenarından başlar
				for _, r in ramps do
					local t = if elevated then maxW / 2 - 4 else maxW / 2
					setTrim(r.Edge.Id, node.Id, t, t)
				end
			elseif #mains == 2 and #ramps == 0 then
				-- Açılı dönüş (otoyol köşesi): disk dolgu
				table.insert(pads, { Position = node.Position, SizeX = maxW, SizeZ = maxW, Thickness = thickness, Disc = true })
			else
				local dir = if #mains > 0 then mains[1].Dir else adj[1].Dir
				local size = math.max(maxW, 16)
				for _, a in adj do
					setTrim(a.Edge.Id, node.Id, size / 2, size / 2)
				end
				table.insert(pads, { Position = node.Position, SizeX = size, SizeZ = size, Dir = dir, Thickness = thickness, Disc = false })
			end
		end
	end
	return roadTrim, walkTrim, pads
end

local function trimmedEnds(data, e, trims): (Vector3, Vector3)
	local a = data.Nodes[e.A].Position
	local b = data.Nodes[e.B].Position
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = flat.Magnitude
	if len < 1e-3 then
		return a, b
	end
	local ta = trims and trims[e.A] or 0
	local tb = trims and trims[e.B] or 0
	local fa = math.clamp(ta / len, 0, 0.49)
	local fb = math.clamp(tb / len, 0, 0.49)
	return a:Lerp(b, fa), a:Lerp(b, 1 - fb)
end

function RoadBuilder.Build(kit, world: Instance)
	local data = MapDefinitions.GetData()
	local meta = data.Meta
	local C = kit.Colors
	local roads = kit:Folder(world, "Roads")
	local surfaces = kit:Folder(roads, "Surfaces")
	local markings = kit:Folder(roads, "Markings")
	local sidewalksFolder = kit:Folder(world, "Sidewalks")
	local junctions = kit:Folder(roads, "Intersections")
	local sw = meta.Sidewalk
	local lift = Vector3.new(0, LINE_LIFT, 0)

	local roadTrim, walkTrim, pads = planNodes(data)

	local function strip(parent: Instance, a: Vector3, b: Vector3, width: number, thickness: number, lateral: number, color: Color3, material: Enum.Material, props)
		local cf, length = kit.StripCFrame(a, b, thickness, lateral)
		if length < 0.3 then
			return nil
		end
		return kit:Box(parent, Vector3.new(width, thickness, length), cf, color, material, props)
	end

	-- ===== Yol kenarları =====
	for _, e in data.EdgeList do
		local a, b = trimmedEnds(data, e, roadTrim[e.Id])
		local elevated = math.min(a.Y, b.Y) > 2
		local sloped = math.abs(a.Y - b.Y) > 0.5
		local thickness = if elevated then 2 elseif sloped then 1.5 else 1
		local surfaceColor = if e.Kind == "freeway" or e.Kind == "ramp" then C.AsphaltLight else C.Asphalt
		local road = strip(surfaces, a, b, e.Width, thickness, 0, surfaceColor, Enum.Material.Asphalt, { CastShadow = elevated or sloped })
		if road then
			road.Name = "Road_" .. e.Id
			road:SetAttribute("EdgeId", e.Id)
		end

		-- Şerit çizgileri
		local la, lb = a + lift, b + lift
		if e.Kind == "street" or e.Kind == "country" then
			strip(markings, la, lb, 0.5, LINE_T, 0, C.LineYellow, Enum.Material.SmoothPlastic, { CastShadow = false })
		elseif e.Kind == "avenue" or e.Kind == "highway" then
			local lane = e.Width / 4
			strip(markings, la, lb, 0.35, LINE_T, 0.6, C.LineYellow, Enum.Material.SmoothPlastic, { CastShadow = false })
			strip(markings, la, lb, 0.35, LINE_T, -0.6, C.LineYellow, Enum.Material.SmoothPlastic, { CastShadow = false })
			strip(markings, la, lb, 0.35, LINE_T, lane, C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
			strip(markings, la, lb, 0.35, LINE_T, -lane, C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
			if e.Kind == "highway" then
				-- kenar çizgileri
				strip(markings, la, lb, 0.35, LINE_T, e.Width / 2 - 1, C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
				strip(markings, la, lb, 0.35, LINE_T, -(e.Width / 2 - 1), C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
			end
		elseif e.Kind == "freeway" then
			strip(markings, la, lb, 0.35, LINE_T, 13, C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
			strip(markings, la, lb, 0.35, LINE_T, -13, C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
			-- Orta refüj ve kenar bariyerleri (jersey duvar)
			local up = Vector3.new(0, 1.25, 0)
			strip(markings, a + up * 2, b + up * 2, 1.6, 2.5, 0, C.Barrier, Enum.Material.Concrete)
			if elevated or sloped then
				strip(markings, a + up * 2, b + up * 2, 1.2, 2.5, e.Width / 2 - 0.6, C.Barrier, Enum.Material.Concrete)
				strip(markings, a + up * 2, b + up * 2, 1.2, 2.5, -(e.Width / 2 - 0.6), C.Barrier, Enum.Material.Concrete)
			end
		elseif e.Kind == "ramp" then
			if math.max(a.Y, b.Y) > 4 then
				local up = Vector3.new(0, 2.5, 0)
				strip(markings, a + up, b + up, 1, 2.5, e.Width / 2 - 0.5, C.Barrier, Enum.Material.Concrete)
				strip(markings, a + up, b + up, 1, 2.5, -(e.Width / 2 - 0.5), C.Barrier, Enum.Material.Concrete)
			end
		end

		-- Kaldırımlar
		if e.Sidewalk then
			local wa, wb = trimmedEnds(data, e, walkTrim[e.Id])
			local top = Vector3.new(0, meta.BlockTop, 0)
			wa = Vector3.new(wa.X, 0, wa.Z) + top
			wb = Vector3.new(wb.X, 0, wb.Z) + top
			local off = e.Width / 2 + sw / 2
			strip(sidewalksFolder, wa, wb, sw, 1, off, C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
			strip(sidewalksFolder, wa, wb, sw, 1, -off, C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
		end

		-- Köprü: su üzerindeki bölümde korkuluk ve ayaklar (bölüm sınırları mapgen.py'de hesaplandı)
		if e.Bridge and e.BridgeSpan then
			local pa, pb = data.Nodes[e.A].Position, data.Nodes[e.B].Position
			local ra, rb = pa:Lerp(pb, e.BridgeSpan[1]), pa:Lerp(pb, e.BridgeSpan[2])
			local up = Vector3.new(0, 3, 0)
			strip(markings, ra + up, rb + up, 0.8, 3, e.Width / 2 + 0.4, C.Metal, Enum.Material.Metal)
			strip(markings, ra + up, rb + up, 0.8, 3, -(e.Width / 2 + 0.4), C.Metal, Enum.Material.Metal)
			local spanLength = (rb - ra).Magnitude
			local count = math.max(1, math.floor(spanLength / 70))
			local dir = Vector3.new(pb.X - pa.X, 0, pb.Z - pa.Z)
			for k = 1, count do
				local pc = ra:Lerp(rb, k / (count + 1))
				local cf = CFrame.lookAt(Vector3.new(pc.X, -8, pc.Z), Vector3.new(pc.X, -8, pc.Z) + dir)
				kit:Box(markings, Vector3.new(e.Width * 0.7, 16, 5), cf, C.Concrete, Enum.Material.Concrete)
			end
		end
	end

	-- ===== Kavşaklar =====
	for _, pad in pads do
		local pos = pad.Position
		if pad.Disc then
			kit:Cylinder(junctions, pad.Thickness, pad.SizeX, CFrame.new(pos - Vector3.new(0, pad.Thickness / 2 + 0.06, 0)), C.AsphaltLight, Enum.Material.Asphalt)
		elseif pad.Dir then
			local d = pad.Dir
			local cf = CFrame.lookAt(pos, pos + Vector3.new(d.X, 0, d.Y)) * CFrame.new(0, -pad.Thickness / 2, 0)
			kit:Box(junctions, Vector3.new(pad.SizeX, pad.Thickness, pad.SizeZ), cf, C.AsphaltLight, Enum.Material.Asphalt)
		else
			kit:Box(junctions, Vector3.new(pad.SizeX, pad.Thickness, pad.SizeZ), CFrame.new(pos - Vector3.new(0, pad.Thickness / 2, 0)), C.Asphalt, Enum.Material.Asphalt, { CastShadow = false })

			-- Kaldırım köşeleri ve kapalı kenar dolguları
			if pad.Walk then
				local hx, hz = pad.SizeX / 2, pad.SizeZ / 2
				local y = meta.BlockTop - 0.5
				for _, sxs in { -1, 1 } do
					for _, szs in { -1, 1 } do
						kit:Box(sidewalksFolder, Vector3.new(sw, 1, sw), CFrame.new(pos.X + sxs * (hx + sw / 2), y, pos.Z + szs * (hz + sw / 2)), C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
					end
				end
				if not pad.Open.N then
					kit:Box(sidewalksFolder, Vector3.new(pad.SizeX, 1, sw), CFrame.new(pos.X, y, pos.Z - hz - sw / 2), C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
				end
				if not pad.Open.S then
					kit:Box(sidewalksFolder, Vector3.new(pad.SizeX, 1, sw), CFrame.new(pos.X, y, pos.Z + hz + sw / 2), C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
				end
				if not pad.Open.W then
					kit:Box(sidewalksFolder, Vector3.new(sw, 1, pad.SizeZ), CFrame.new(pos.X - hx - sw / 2, y, pos.Z), C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
				end
				if not pad.Open.E then
					kit:Box(sidewalksFolder, Vector3.new(sw, 1, pad.SizeZ), CFrame.new(pos.X + hx + sw / 2, y, pos.Z), C.Sidewalk, Enum.Material.Concrete, { CastShadow = false })
				end
			end

			-- Yaya geçitleri: her kaldırımlı kolda iki enine beyaz çizgi
			if pad.Crosswalk and pad.Adj then
				for _, a in pad.Adj do
					if a.Sidewalk then
						local axis = axisOf(a.Dir)
						local half = if axis == "E" or axis == "W" then pad.SizeX / 2 else pad.SizeZ / 2
						local dir3 = Vector3.new(a.Dir.X, 0, a.Dir.Y)
						for _, dist in { half + 1, half + 7 } do
							local p = pos + dir3 * dist + Vector3.new(0, LINE_LIFT - LINE_T / 2, 0)
							local cf = CFrame.lookAt(p, p + dir3)
							kit:Box(markings, Vector3.new(a.Width - 1, LINE_T, 0.7), cf, C.LineWhite, Enum.Material.SmoothPlastic, { CastShadow = false })
						end
					end
				end
			end
		end
	end
end

return RoadBuilder
