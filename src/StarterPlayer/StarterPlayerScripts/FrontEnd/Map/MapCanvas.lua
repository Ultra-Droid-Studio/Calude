-- MapCanvas: harita çizimi (minimap ve tam ekran harita ortak kullanır). Aşama 4.
--
-- Koordinat: MapDefinitions dünya stud'u. Tuval birimi = 1 stud; (0,0) haritanın kuzeybatı köşesi (-HalfSize).
-- Ekran = tuval × UIScale (piksel/stud). Kuzey yukarı (-Z ekranda yukarı).
--
-- Performans kuralları ("tüm haritayı yeniden çizme"):
--   * Yollar, su, bölgeler BİR KEZ çizilir. Kaydırma = Root.Position, yakınlaştırma = UIScale.Scale.
--   * Yollar 1024 stud'luk karolara bölünür; görüş alanı dışındaki karolar Visible=false (yerleşim/çizim yükü yok).
--     Karo görünürlüğü sadece görünen karo aralığı değişince güncellenir.
--   * Sabit piksel boyutlu öğeler (simgeler, rota kalınlığı) sadece yakınlaştırma değişince yeniden ölçeklenir.
--   * Rota sadece yeni rota geldiğinde yeniden çizilir.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapDefinitions"))
local FrontEnd = script.Parent.Parent
local Theme = require(FrontEnd:WaitForChild("Theme"))
local Strings = require(FrontEnd:WaitForChild("Strings"))

local MapCanvas = {}
MapCanvas.__index = MapCanvas

local TILE = 1024
local rgb = Color3.fromRGB

local COLORS = {
	Land = rgb(22, 25, 32),
	Water = rgb(14, 34, 56),
	District = rgb(30, 34, 44),
	freeway = rgb(118, 128, 150),
	highway = rgb(104, 112, 132),
	ramp = rgb(104, 112, 132),
	avenue = rgb(82, 88, 104),
	street = rgb(64, 70, 84),
	country = rgb(70, 78, 66),
	Route = Theme.Colors.AccentAlt,
	RouteOffroad = rgb(160, 230, 240),
}

MapCanvas.LandColor = COLORS.Land -- mini haritanın kabı bu renkle boyanır

-- POI türü → kategori (simge rengi + kısa harf Strings'ten)
local POI_CATEGORY = {
	supermarket = "Shop", grocery = "Shop", convenience = "Shop", general = "Shop", mall = "Shop",
	restaurant = "Food", fastfood = "Food", cafe = "Food",
	gas = "Fuel", hospital = "Health", police = "Police",
	hotel = "Hotel",
	garage = "Vehicle", dealership_car = "Vehicle", dealership_moto = "Vehicle", parking = "Vehicle",
	cinema = "Leisure", arcade = "Leisure", park = "Leisure", golf = "Leisure", plaza = "Leisure", marina = "Leisure",
	airport = "Transport", airport_tower = "Transport", port = "Transport",
	lighthouse = "Landmark", observatory = "Landmark", construction = "Landmark",
	farm = "Rural", ranger = "Rural",
}
local CATEGORY_COLOR = {
	Shop = rgb(110, 210, 150), Food = rgb(242, 120, 160), Fuel = rgb(255, 170, 60), Health = rgb(235, 87, 87),
	Police = rgb(90, 150, 255), Hotel = rgb(180, 140, 255), Vehicle = rgb(64, 196, 214), Leisure = rgb(255, 214, 110),
	Transport = rgb(200, 200, 210), Landmark = rgb(255, 122, 69), Rural = rgb(150, 190, 110),
}
MapCanvas.POICategory = POI_CATEGORY
MapCanvas.CategoryColor = CATEGORY_COLOR

local function frame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		(f :: any)[k] = v
	end
	f.Parent = parent
	return f
end

local function corner(parent: Instance, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, 0)
	c.Parent = parent
end

-- opts: Detail = "Mini" | "Full"
function MapCanvas.new(parent: GuiObject, opts)
	local self = setmetatable({}, MapCanvas)
	local data = MapDefinitions.GetData()
	local half = data.Meta.HalfSize
	self.Half = half
	self.Detail = opts.Detail or "Mini"
	self.Scale = -1
	self.TileRange = ""
	self.Tiles = {}
	self.FixedIcons = {} -- { Gui, PixelSize } sabit piksel boyutlu öğeler
	self.RouteSegments = {}
	self.POIs = {}

	local root = frame(parent, {
		Name = "MapRoot",
		BackgroundColor3 = COLORS.Land,
		-- Mini haritada tuval saydam: zemin rengini kırpan kap verir. Böylece kırpma bir şekilde bozulsa bile
		-- 10240×10240'lık koyu bir kare ekranı kaplamaz (Hata düzeltme 4). Tam haritada opak kalır.
		BackgroundTransparency = if self.Detail == "Mini" then 1 else 0,
		Size = UDim2.fromOffset(half * 2, half * 2),
		ZIndex = 1,
	})
	root:SetAttribute("FaderSkip", true) -- menü geçişleri binlerce yol parçasını tek tek soldurmasın
	self.Root = root
	self.UIScale = Instance.new("UIScale")
	self.UIScale.Parent = root

	local function layer(name: string, z: number): Frame
		return frame(root, { Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z })
	end
	local waterLayer = layer("Water", 2)
	local districtLayer = layer("Districts", 3)
	local roadLayer = layer("Roads", 4)
	self.RouteLayer = layer("Route", 5)
	self.MarkerLayer = layer("Markers", 6)

	-- Su
	for _, w in data.Water do
		frame(waterLayer, {
			BackgroundColor3 = COLORS.Water,
			Position = UDim2.fromOffset(w.X0 + half, w.Z0 + half),
			Size = UDim2.fromOffset(w.X1 - w.X0, w.Z1 - w.Z0),
		})
	end
	-- Bölgeler (tam haritada isim)
	if self.Detail == "Full" then
		for _, d in data.Districts do
			local cx, cz = (d.Min.X + d.Max.X) / 2 + half, (d.Min.Y + d.Max.Y) / 2 + half
			local w = math.max(d.Max.X - d.Min.X, 200)
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromOffset(cx, cz)
			label.Size = UDim2.fromOffset(w * 0.8, math.min(w * 0.08, 90))
			label.TextScaled = true
			label.FontFace = Theme.Fonts.Title
			label.TextColor3 = Theme.Colors.TextMuted
			label.TextTransparency = 0.45
			label.AutoLocalize = false
			label.Text = string.upper(d.Name)
			label.ZIndex = 3
			label.Parent = districtLayer
		end
	end

	-- Yollar: karolara bölünmüş
	local function tileFor(x: number, z: number): Frame
		local tx, tz = math.floor((x + half) / TILE), math.floor((z + half) / TILE)
		local key = tx * 1000 + tz
		local tile = self.Tiles[key]
		if not tile then
			tile = frame(roadLayer, { Name = "Tile_" .. tx .. "_" .. tz, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 4 })
			self.Tiles[key] = tile
			tile:SetAttribute("TX", tx)
			tile:SetAttribute("TZ", tz)
		end
		return tile
	end
	local nodeWidth = {}
	for _, e in data.EdgeList do
		local a, b = data.Nodes[e.A], data.Nodes[e.B]
		if a and b then
			local ax, az, bx, bz = a.Position.X, a.Position.Z, b.Position.X, b.Position.Z
			local dx, dz = bx - ax, bz - az
			local length = math.sqrt(dx * dx + dz * dz)
			local width = math.max(e.Width, 16)
			local mx, mz = (ax + bx) / 2, (az + bz) / 2
			frame(tileFor(mx, mz), {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(mx + half, mz + half),
				Size = UDim2.fromOffset(length, width),
				Rotation = math.deg(math.atan2(dz, dx)),
				BackgroundColor3 = COLORS[e.Kind] or COLORS.street,
				ZIndex = if e.Kind == "freeway" or e.Kind == "ramp" then 5 else 4,
			})
			nodeWidth[e.A] = math.max(nodeWidth[e.A] or 0, width)
			nodeWidth[e.B] = math.max(nodeWidth[e.B] or 0, width)
		end
	end
	-- Kavşak yuvarlakları (yol uçlarındaki boşlukları kapatır)
	for id, w in nodeWidth do
		local n = data.Nodes[id]
		local dot = frame(tileFor(n.Position.X, n.Position.Z), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(n.Position.X + half, n.Position.Z + half),
			Size = UDim2.fromOffset(w, w),
			BackgroundColor3 = COLORS.street,
			ZIndex = 4,
		})
		corner(dot)
	end

	-- Önemli yerler (simge: kategori rengi + kısa harf)
	for _, poi in data.POIs do
		local category = POI_CATEGORY[poi.Type] or "Landmark"
		local icon = frame(self.MarkerLayer, {
			Name = "POI_" .. poi.Id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(poi.Entrance.X + half, poi.Entrance.Z + half),
			BackgroundColor3 = CATEGORY_COLOR[category],
			ZIndex = 7,
		})
		corner(icon)
		local stroke = Instance.new("UIStroke")
		stroke.Color = rgb(10, 12, 16)
		stroke.Thickness = 1.5
		stroke.Parent = icon
		local letter = Instance.new("TextLabel")
		letter.BackgroundTransparency = 1
		letter.Size = UDim2.fromScale(0.8, 0.8)
		letter.AnchorPoint = Vector2.new(0.5, 0.5)
		letter.Position = UDim2.fromScale(0.5, 0.5)
		letter.TextScaled = true
		letter.FontFace = Theme.Fonts.Title
		letter.TextColor3 = rgb(16, 18, 24)
		letter.AutoLocalize = false
		letter.Text = Strings.Get("POICat." .. category .. ".Short")
		letter.ZIndex = 8
		letter.Parent = icon
		table.insert(self.FixedIcons, { Gui = icon, Pixels = if self.Detail == "Full" then 20 else 13 })
		table.insert(self.POIs, { Poi = poi, Gui = icon, Category = category })
	end

	-- Hedef işareti (iğne)
	self.Pin = frame(self.MarkerLayer, {
		Name = "Destination",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.Accent,
		Visible = false,
		ZIndex = 9,
	})
	corner(self.Pin)
	local pinStroke = Instance.new("UIStroke")
	pinStroke.Color = rgb(255, 255, 255)
	pinStroke.Thickness = 2
	pinStroke.Parent = self.Pin
	table.insert(self.FixedIcons, { Gui = self.Pin, Pixels = if self.Detail == "Full" then 18 else 12 })

	-- Oyuncu işareti (tam haritada; minimapte sabit merkez oku kullanılır)
	if self.Detail == "Full" then
		self.Player = MapCanvas.MakeArrow(self.MarkerLayer, 10)
		table.insert(self.FixedIcons, { Gui = self.Player, Pixels = 26 })
	end
	return self
end

-- Yukarıyı gösteren ok (iki çubuk + nokta). Döndürmek için Rotation kullanılır (0 = kuzey).
function MapCanvas.MakeArrow(parent: Instance, zIndex: number): Frame
	local holder = frame(parent, { Name = "PlayerArrow", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = zIndex })
	local dot = frame(holder, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.42, 0.42),
		BackgroundColor3 = rgb(255, 255, 255),
		ZIndex = zIndex,
	})
	corner(dot)
	for _, sign in { -1, 1 } do
		local bar = frame(holder, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + sign * 0.15, 0.3),
			Size = UDim2.fromScale(0.16, 0.5),
			Rotation = sign * 30,
			BackgroundColor3 = Theme.Colors.AccentAlt,
			ZIndex = zIndex + 1,
		})
		corner(bar)
	end
	return holder
end

-- Görünüm: dünya merkezi (cx, cz), ölçek (piksel/stud), görüntü alanı (ebeveyn biriminde)
function MapCanvas:SetView(cx: number, cz: number, scale: number, viewport: Vector2)
	local half = self.Half
	if math.abs(scale - self.Scale) > self.Scale * 0.01 then
		self.Scale = scale
		self.UIScale.Scale = scale
		for _, item in self.FixedIcons do
			item.Gui.Size = UDim2.fromOffset(item.Pixels / scale, item.Pixels / scale)
		end
		local thickness = (if self.Detail == "Full" then 5 else 4) / scale
		for _, seg in self.RouteSegments do
			seg.Size = UDim2.fromOffset(seg.Size.X.Offset, thickness * (seg:GetAttribute("Weight") or 1))
		end
	end
	self.Root.Position = UDim2.fromOffset(viewport.X / 2 - (cx + half) * scale, viewport.Y / 2 - (cz + half) * scale)
	-- Karo görünürlüğü: sadece aralık değişince
	local halfW, halfH = viewport.X / 2 / scale + 200, viewport.Y / 2 / scale + 200
	local tx0, tx1 = math.floor((cx - halfW + half) / TILE), math.floor((cx + halfW + half) / TILE)
	local tz0, tz1 = math.floor((cz - halfH + half) / TILE), math.floor((cz + halfH + half) / TILE)
	local key = tx0 .. ":" .. tx1 .. ":" .. tz0 .. ":" .. tz1
	if key ~= self.TileRange then
		self.TileRange = key
		for _, tile in self.Tiles do
			local tx, tz = tile:GetAttribute("TX"), tile:GetAttribute("TZ")
			tile.Visible = tx >= tx0 and tx <= tx1 and tz >= tz0 and tz <= tz1
		end
	end
end

function MapCanvas:SetPlayer(x: number, z: number, headingDeg: number)
	if self.Player then
		self.Player.Position = UDim2.fromOffset(x + self.Half, z + self.Half)
		self.Player.Rotation = headingDeg
	end
end

function MapCanvas:SetDestination(position: Vector3?)
	if position then
		self.Pin.Position = UDim2.fromOffset(position.X + self.Half, position.Z + self.Half)
		self.Pin.Visible = true
	else
		self.Pin.Visible = false
	end
end

-- route: Navigation rota nesnesi ya da nil
function MapCanvas:SetRoute(route)
	for _, seg in self.RouteSegments do
		seg:Destroy()
	end
	table.clear(self.RouteSegments)
	if not route then
		return
	end
	local half = self.Half
	local scale = math.max(self.Scale, 0.01)
	local thickness = (if self.Detail == "Full" then 5 else 4) / scale
	local function segment(a, b, color: Color3, weight: number, transparency: number)
		local dx, dz = b.X - a.X, b.Z - a.Z
		local length = math.sqrt(dx * dx + dz * dz)
		if length < 0.5 then
			return
		end
		local seg = frame(self.RouteLayer, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((a.X + b.X) / 2 + half, (a.Z + b.Z) / 2 + half),
			Size = UDim2.fromOffset(length + thickness * weight, thickness * weight),
			Rotation = math.deg(math.atan2(dz, dx)),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			ZIndex = 6,
		})
		seg:SetAttribute("Weight", weight)
		corner(seg)
		table.insert(self.RouteSegments, seg)
	end
	local points = route.Points
	for i = 1, #points - 1 do
		segment(points[i], points[i + 1], COLORS.Route, 1, 0)
	end
	if route.Offroad then
		-- son kısım yol dışında: ince, yarı saydam düz çizgi
		segment(points[#points], route.Destination, COLORS.RouteOffroad, 0.5, 0.35)
	end
end

-- Ekran noktası (ebeveyn biriminde, görüntü alanının sol üstüne göre) → dünya
function MapCanvas:ViewToWorld(local2: Vector2, cx: number, cz: number, viewport: Vector2): (number, number)
	local scale = math.max(self.Scale, 0.0001)
	return cx + (local2.X - viewport.X / 2) / scale, cz + (local2.Y - viewport.Y / 2) / scale
end

-- Dünya noktasına en yakın POI (piksel yarıçapı içinde)
function MapCanvas:POINear(x: number, z: number, radiusPixels: number)
	local limit = radiusPixels / math.max(self.Scale, 0.0001)
	local best, bestD = nil, limit
	for _, item in self.POIs do
		local p = item.Poi.Entrance
		local d = math.sqrt((p.X - x) ^ 2 + (p.Z - z) ^ 2)
		if d < bestD then
			best, bestD = item.Poi, d
		end
	end
	return best
end

function MapCanvas:Destroy()
	self.Root:Destroy()
end

return MapCanvas
