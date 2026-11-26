-- Businesses: şehirdeki işletmelerin kaydı (Şehir genişletme, aşama 2). Saf Lua (tools/test_businesses.py çalıştırır).
--
-- Veri: BusinessData (tools/plan_businesses.py üretir, elle düzenlenebilir). Harita (MapData) DEĞİŞMEZ: işletmeler
-- zaten dükkân olan arsalara bağlanır.
-- MapDefinitions ayrıştırırken Apply çağrılır:
--   * her arsaya lot.Business (işletme kaydı) yazılır — BuildingBuilder tabela adı/rengi/yazı tipi için okur;
--   * haritada görünecek YENİ işletmeler POI olarak eklenir (Id "biz_<arsa>"): tam harita, minimap, GPS hedefi,
--     yerler listesi, yaya bekleme noktaları ve WorldBuilder dükkân bölgeleri mevcut POI yoluyla bunları görür;
--   * mevcut POI'lere .Business alanı eklenir (adı ve türü değişmez).
-- POI giriş noktası MapData ile aynı kural: arsa merkezi + yerel (0, -(Derinlik/2 + 2)) — kapının önü, kaldırım tarafı.

local Businesses = {}

-- Tür kataloğu. Category: harita simgesi (MapCanvas). Shop: WorldBuilder "Shops" klasörüne girer (ileride alışveriş).
-- Label: oyuncuya gösterilen tür adı (TR / EN). Not: silah dükkânı şimdilik yalnızca bir yer; satın alma sistemi yok.
Businesses.Types = {
	bakery = { Category = "Food", Shop = true, TR = "Fırın", EN = "Bakery" },
	bakkal = { Category = "Shop", Shop = true, TR = "Bakkal", EN = "Corner shop" },
	minimarket = { Category = "Shop", Shop = true, TR = "Market", EN = "Mini market" },
	supermarket = { Category = "Shop", Shop = true, TR = "Süpermarket", EN = "Supermarket" },
	greengrocer = { Category = "Shop", Shop = true, TR = "Manav", EN = "Greengrocer" },
	pharmacy = { Category = "Health", Shop = true, TR = "Eczane", EN = "Pharmacy" },
	restaurant = { Category = "Food", Shop = true, TR = "Restoran", EN = "Restaurant" },
	fastfood = { Category = "Food", Shop = true, TR = "Fast food", EN = "Fast food" },
	diner = { Category = "Food", Shop = true, TR = "Lokanta", EN = "Diner" },
	cafe = { Category = "Food", Shop = true, TR = "Kafe", EN = "Café" },
	internetcafe = { Category = "Leisure", Shop = true, TR = "İnternet kafe", EN = "Internet café" },
	dollarstore = { Category = "Shop", Shop = true, TR = "Milyoncu", EN = "Variety store" },
	gunshop = { Category = "Armory", Shop = true, TR = "Silah dükkânı", EN = "Gun shop" },
	general = { Category = "Shop", Shop = true, TR = "Mağaza", EN = "Store" },
}

local data = nil
local byLot = nil

local function load()
	if data then
		return
	end
	local source = Businesses._Data
	if not source then
		source = require(script.Parent:WaitForChild("BusinessData"))
	end
	data = source
	byLot = {}
	for _, b in ipairs(data) do
		byLot[b.Lot] = b
	end
end

function Businesses.All()
	load()
	return data
end

function Businesses.ByLot(lotId)
	load()
	return byLot[lotId]
end

-- Haritadaki işletme türleri ve dükkân sayılan türler (MapCanvas / WorldBuilder için)
function Businesses.Category(poiType)
	local t = Businesses.Types[poiType]
	return t and t.Category or nil
end

function Businesses.IsShopType(poiType)
	local t = Businesses.Types[poiType]
	return t ~= nil and t.Shop == true
end

-- Arsanın önündeki giriş noktası (MapData POI kuralı)
function Businesses.EntrancePoint(lot)
	local r = math.rad(lot.Rotation)
	local lz = -(lot.Depth / 2 + 2)
	return lot.Center.X + lz * math.sin(r), lot.Center.Z + lz * math.cos(r)
end

-- MapDefinitions.parse sonunda çağrılır. vec: Vector3 kurucu (çevrimdışı testte sahte). İdempotent değildir: bir kez.
function Businesses.Apply(mapData, vec)
	load()
	vec = vec or Vector3.new
	local lotById = {}
	for _, lot in ipairs(mapData.Lots) do
		lotById[lot.Id] = lot
	end
	if not mapData.POIById then
		mapData.POIById = {}
		for _, poi in ipairs(mapData.POIs) do
			mapData.POIById[poi.Id] = poi
		end
	end
	local added = 0
	for _, b in ipairs(data) do
		local lot = lotById[b.Lot]
		if lot then
			lot.Business = b
			if b.Poi then
				local poi = mapData.POIById[b.Poi]
				if poi then
					poi.Business = b
				end
			elseif b.Map then
				local ex, ez = Businesses.EntrancePoint(lot)
				local id = "biz_" .. tostring(b.Lot)
				local poi = {
					Id = id, Type = b.Type, Name = b.Name,
					Position = vec(lot.Center.X, 0, lot.Center.Z),
					Entrance = vec(ex, 0, ez),
					District = lot.District, LotId = lot.Id, Business = b,
				}
				table.insert(mapData.POIs, poi)
				mapData.POIById[id] = poi
				lot.PoiId = id
				added = added + 1
			end
		end
	end
	return added
end

return Businesses
