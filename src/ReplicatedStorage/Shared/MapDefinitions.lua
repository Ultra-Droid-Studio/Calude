-- MapDefinitions: dünyanın TEK koordinat kaynağı (Bölüm 3.3).
-- Dünya inşacısı, minimap, tam ekran harita, GPS, trafik ve yaya sistemleri bu modülü okur.
-- Veri tools/mapgen.py tarafından üretilen MapData'dan bir kez ayrıştırılır ve önbelleğe alınır.

local MapData = require(script.Parent.MapData)

local MapDefinitions = {}

export type District = {
	Id: string, Name: string, Type: string,
	Min: Vector2, Max: Vector2, -- (x, z)
	DayDensity: number, NightDensity: number,
}
export type Node = {
	Id: number, Position: Vector3,
	Signal: boolean, Stop: boolean, Crosswalk: boolean, Elevated: boolean,
	Edges: { number },
}
export type Edge = {
	Id: number, A: number, B: number, Kind: string, Width: number,
	LanesForward: number, LanesBackward: number, Speed: number, Name: string,
	Bridge: boolean, Sidewalk: boolean, Length: number,
	BridgeSpan: { number }?, -- köprünün su üstündeki bölümü (0..1 kenar oranı)
}
export type Lot = {
	Id: number, District: string, Style: string, Use: string,
	Center: Vector3, Width: number, Depth: number, Rotation: number, Height: number,
	Seed: number, PoiId: string?, BaseY: number,
}
export type POI = {
	Id: string, Type: string, Name: string, Position: Vector3, Entrance: Vector3,
	District: string, LotId: number,
}

local parsed = nil

local function num(s: string): number
	return tonumber(s) or 0
end

local function parse()
	local data = {
		Meta = {},
		Districts = {} :: { District },
		DistrictById = {} :: { [string]: District },
		Nodes = {} :: { [number]: Node },
		NodeList = {} :: { Node },
		Edges = {} :: { [number]: Edge },
		EdgeList = {} :: { Edge },
		Blocks = {},
		Lots = {} :: { Lot },
		POIs = {} :: { POI },
		POIById = {} :: { [string]: POI },
		Props = {},
		Hills = {},
		Ground = {},
		Water = {},
		Spawns = {},
		Coast = {},
		VehicleSpots = {},
	}

	for line in string.gmatch(MapData, "[^\n]+") do
		local f = string.split(line, "|")
		local t = f[1]
		if t == "N" then
			local flags = f[6] or ""
			local n: Node = {
				Id = num(f[2]),
				Position = Vector3.new(num(f[3]), num(f[4]), num(f[5])),
				Signal = string.find(flags, "s", 1, true) ~= nil,
				Stop = string.find(flags, "t", 1, true) ~= nil,
				Crosswalk = string.find(flags, "c", 1, true) ~= nil,
				Elevated = string.find(flags, "f", 1, true) ~= nil,
				Edges = {},
			}
			data.Nodes[n.Id] = n
			table.insert(data.NodeList, n)
		elseif t == "E" then
			-- Satır biçimi: E|id|a|b|tür|genişlik|ileri|geri|hız|ad|bayraklar|köprü0|köprü1
			-- (Düzeltme, kullanıcı onayıyla: bayraklar eskiden f[12], köprü aralığı f[13..14] okunuyordu →
			-- kaldırımlar ve köprü korkulukları hiç üretilmiyordu.)
			local flags = f[11] or ""
			local e: Edge = {
				Id = num(f[2]), A = num(f[3]), B = num(f[4]), Kind = f[5], Width = num(f[6]),
				LanesForward = num(f[7]), LanesBackward = num(f[8]), Speed = num(f[9]), Name = f[10] or "",
				Bridge = string.find(flags, "b", 1, true) ~= nil,
				Sidewalk = string.find(flags, "w", 1, true) ~= nil,
				Length = 0,
				BridgeSpan = if f[12] and f[12] ~= "" then { num(f[12]), num(f[13]) } else nil,
			}
			data.Edges[e.Id] = e
			table.insert(data.EdgeList, e)
		elseif t == "L" then
			table.insert(data.Lots, {
				Id = num(f[2]), District = f[3], Style = f[4], Use = f[5],
				Center = Vector3.new(num(f[6]), 0, num(f[7])), Width = num(f[8]), Depth = num(f[9]),
				Rotation = num(f[10]), Height = num(f[11]), Seed = num(f[12]),
				PoiId = if f[13] ~= nil and f[13] ~= "" then f[13] else nil,
				BaseY = num(f[14]),
			})
		elseif t == "P" then
			local p: POI = {
				Id = f[2], Type = f[3], Name = f[4],
				Position = Vector3.new(num(f[5]), 0, num(f[6])),
				Entrance = Vector3.new(num(f[7]), 0, num(f[8])),
				District = f[9], LotId = num(f[10]),
			}
			table.insert(data.POIs, p)
			data.POIById[p.Id] = p
		elseif t == "X" then
			table.insert(data.Props, { Kind = f[2], X = num(f[3]), Z = num(f[4]), Yaw = num(f[5]), Y = num(f[6]), Extra = f[7] or "", Extra2 = f[8] })
		elseif t == "B" then
			table.insert(data.Blocks, { District = f[2], X0 = num(f[3]), Z0 = num(f[4]), X1 = num(f[5]), Z1 = num(f[6]), Material = f[7] })
		elseif t == "D" then
			local d: District = {
				Id = f[2], Name = f[3], Type = f[4],
				Min = Vector2.new(num(f[5]), num(f[6])), Max = Vector2.new(num(f[7]), num(f[8])),
				DayDensity = num(f[9]), NightDensity = num(f[10]),
			}
			table.insert(data.Districts, d)
			data.DistrictById[d.Id] = d
		elseif t == "H" then
			table.insert(data.Hills, { X = num(f[2]), Z = num(f[3]), Radius = num(f[4]), CenterY = num(f[5]) })
		elseif t == "G" then
			table.insert(data.Ground, { X0 = num(f[2]), Z0 = num(f[3]), X1 = num(f[4]), Z1 = num(f[5]) })
		elseif t == "W" then
			table.insert(data.Water, { Kind = f[2], X0 = num(f[3]), Z0 = num(f[4]), X1 = num(f[5]), Z1 = num(f[6]) })
		elseif t == "V" then
			table.insert(data.VehicleSpots, { DefId = f[2], Position = Vector3.new(num(f[3]), 0, num(f[4])), Yaw = num(f[5]) })
		elseif t == "Q" then
			table.insert(data.Coast, { Kind = f[2], X0 = num(f[3]), Z0 = num(f[4]), X1 = num(f[5]), Z1 = num(f[6]), Dir = f[7] or "" })
		elseif t == "S" then
			table.insert(data.Spawns, { Group = f[2], Position = Vector3.new(num(f[3]), 0, num(f[4])), Yaw = num(f[5]) })
		elseif t == "M" then
			data.Meta = {
				HalfSize = num(f[2]), RoadTop = num(f[3]), BlockTop = num(f[4]), Sidewalk = num(f[5]),
				FreewayHeight = num(f[6]), CoastX = num(f[7]), BeachZ0 = num(f[8]), BeachZ1 = num(f[9]),
				RiverX0 = num(f[10]), RiverX1 = num(f[11]), BayX = num(f[12]), BayZ = num(f[13]),
			}
		end
	end

	-- Komşuluk ve uzunluklar
	for _, e in data.EdgeList do
		local a, b = data.Nodes[e.A], data.Nodes[e.B]
		if a and b then
			e.Length = (b.Position - a.Position).Magnitude
			table.insert(a.Edges, e.Id)
			table.insert(b.Edges, e.Id)
		end
	end
	return data
end

local function get()
	if not parsed then
		parsed = parse()
	end
	return parsed
end

-- ===== Genel API =====
function MapDefinitions.GetData()
	return get()
end

function MapDefinitions.GetMeta()
	return get().Meta
end

function MapDefinitions.GetBounds(): (Vector2, Vector2)
	local h = get().Meta.HalfSize
	return Vector2.new(-h, -h), Vector2.new(h, h)
end

-- Dünya konumu → harita koordinatı (0..1). Minimap ve tam harita bunu kullanır.
function MapDefinitions.WorldToMap(position: Vector3): Vector2
	local h = get().Meta.HalfSize
	return Vector2.new((position.X + h) / (2 * h), (position.Z + h) / (2 * h))
end

function MapDefinitions.MapToWorld(uv: Vector2): Vector3
	local h = get().Meta.HalfSize
	return Vector3.new(uv.X * 2 * h - h, 0, uv.Y * 2 * h - h)
end

function MapDefinitions.GetDistricts(): { District }
	return get().Districts
end

function MapDefinitions.GetDistrict(id: string): District?
	return get().DistrictById[id]
end

-- Önce kentsel bölgeler (listede önce gelir), sonra kırsal
function MapDefinitions.GetDistrictAt(position: Vector3): District?
	for _, d in get().Districts do
		if position.X >= d.Min.X and position.X <= d.Max.X and position.Z >= d.Min.Y and position.Z <= d.Max.Y then
			return d
		end
	end
	return nil
end

function MapDefinitions.GetNode(id: number): Node?
	return get().Nodes[id]
end

function MapDefinitions.GetEdge(id: number): Edge?
	return get().Edges[id]
end

function MapDefinitions.GetNodes(): { Node }
	return get().NodeList
end

function MapDefinitions.GetEdges(): { Edge }
	return get().EdgeList
end

-- Bir düğümün komşuları: { { Node = id, Edge = id, CanTravel = bool } }
-- CanTravel: tek yönlü yollarda (rampalar) bu yönde gidilebilir mi
function MapDefinitions.GetNeighbors(nodeId: number)
	local data = get()
	local node = data.Nodes[nodeId]
	local list = {}
	if not node then
		return list
	end
	for _, edgeId in node.Edges do
		local e = data.Edges[edgeId]
		local forward = e.A == nodeId
		local other = if forward then e.B else e.A
		local canTravel = if forward then e.LanesForward > 0 else e.LanesBackward > 0
		table.insert(list, { Node = other, Edge = edgeId, CanTravel = canTravel })
	end
	return list
end

function MapDefinitions.GetNearestNode(position: Vector3, filter: ((Node) -> boolean)?): Node?
	local best, bestDist = nil, math.huge
	for _, n in get().NodeList do
		if not filter or filter(n) then
			local d = (n.Position - position).Magnitude
			if d < bestDist then
				best, bestDist = n, d
			end
		end
	end
	return best
end

function MapDefinitions.GetLots(): { Lot }
	return get().Lots
end

function MapDefinitions.GetPOIs(): { POI }
	return get().POIs
end

function MapDefinitions.GetPOI(id: string): POI?
	return get().POIById[id]
end

function MapDefinitions.GetPOIsByType(poiType: string): { POI }
	local list = {}
	for _, p in get().POIs do
		if p.Type == poiType then
			table.insert(list, p)
		end
	end
	return list
end

function MapDefinitions.GetSpawns(group: string?)
	local list = {}
	for _, s in get().Spawns do
		if group == nil or s.Group == group then
			table.insert(list, s)
		end
	end
	return list
end

-- Park halindeki araç noktaları (Aşama 3 VehicleService)
function MapDefinitions.GetVehicleSpots()
	return get().VehicleSpots
end

-- Dükkân tipleri (Aşama 7 ShopService bunları kullanacak)
MapDefinitions.ShopTypes = table.freeze({
	supermarket = true, convenience = true, grocery = true, restaurant = true,
	fastfood = true, cafe = true, gas = true, general = true,
})

return MapDefinitions
