-- GarageScreen: garaj GİRİŞ NOKTASI. Araç sahipliği/satın alma henüz YOK; ekran bunu açıkça söyler.
-- Gerçek veriyi gösterir: VehicleDefinitions kataloğundaki araçlar ve değerleri (sahte fiyat/buton yok).
-- Garaj sistemi geldiğinde bu ekranın sağ panelindeki "yakında" kutusu gerçek eylemlerle değişecek.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontEnd = script.Parent.Parent
local Theme = require(FrontEnd.Theme)
local Widgets = require(FrontEnd.Widgets)
local Strings = require(FrontEnd.Strings)
local Focus = require(FrontEnd.Focus)
local VehicleDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VehicleDefinitions"))

local C = Theme.Colors
local new = Widgets.new
local tween = Widgets.tween

local GarageScreen = {}
GarageScreen.__index = GarageScreen

local LIST_WIDTH = 300

local function sortedCatalog()
	local list = {}
	for id, def in VehicleDefinitions.Catalog do
		table.insert(list, { Id = id, Def = def })
	end
	table.sort(list, function(a, b)
		if a.Def.Type ~= b.Def.Type then
			return a.Def.Type == "Car" -- önce otomobiller
		end
		return a.Def.DisplayName < b.Def.DisplayName
	end)
	return list
end

-- Katalog içindeki en yüksek değerlere göre 0..1
local function maxima(list)
	local m = { MaxSpeed = 1, Accel = 1, Grip = 1, Brake = 1 }
	for _, entry in list do
		for key in m do
			m[key] = math.max(m[key], entry.Def[key] or 0)
		end
	end
	return m
end

local function statBar(parent: Instance, labelKey: string, order: number)
	local holder = new("Frame", {
		Name = labelKey,
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Widgets.Label({
		Text = Strings.Get(labelKey),
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(0.5, 0, 0, 16),
		Parent = holder,
	})
	local value = Widgets.Label({
		Text = "",
		FontFace = Theme.Fonts.Mono,
		TextSize = Theme.Text.Small,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, 16),
		Parent = holder,
	})
	local rail = new("Frame", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = C.SurfaceHigh,
		BorderSizePixel = 0,
		Parent = holder,
	}, { Widgets.Round() })
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = rail,
	}, { Widgets.Round(), Widgets.Gradient(Theme.AccentGradient, 0) })
	return function(t: number, text: string)
		value.Text = text
		tween(fill, { Size = UDim2.fromScale(math.clamp(t, 0.04, 1), 1) }, Theme.Tween.Normal)
	end
end

-- ctx: Parent, GetScale, OnMove, Back
function GarageScreen.new(ctx)
	local self = setmetatable({}, GarageScreen)
	self.Focus = Focus.new(ctx.GetScale, ctx.OnMove)
	self._catalog = sortedCatalog()
	self._max = maxima(self._catalog)

	self.Root = new("Frame", {
		Name = "GarageScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = ctx.Parent,
	})
	local panel = Widgets.Panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -64, 1, -48),
		Parent = self.Root,
	})
	new("UISizeConstraint", { MaxSize = Vector2.new(980, 660) }).Parent = panel
	Widgets.Padding(28, 28, 20, 20).Parent = panel

	-- Başlık + YAKINDA rozeti + geri
	local title = Widgets.Label({
		Name = "Title",
		Text = Strings.Get("Garage.Title"),
		FontFace = Theme.Fonts.Display,
		TextSize = Theme.Text.Heading,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		Parent = panel,
	})
	local badge = new("Frame", {
		Name = "Badge",
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.fromOffset(0, 24),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0.82,
		BorderSizePixel = 0,
		Parent = panel,
	}, { Widgets.Round(), Widgets.Stroke(C.Accent, 0.3), Widgets.Padding(10, 10, 0, 0) })
	Widgets.Label({
		Text = Strings.Get("Garage.Badge"),
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Tiny,
		TextColor3 = C.Accent,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = badge,
	})
	-- rozet başlığın hemen sağında
	local function placeBadge()
		badge.Position = UDim2.fromOffset(title.AbsoluteSize.X / math.max(ctx.GetScale(), 0.01) + 14, 20)
	end
	title:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeBadge)
	task.defer(placeBadge)

	Widgets.SmallButton(panel, {
		Name = "Back",
		Text = "‹  " .. Strings.Get("Settings.Back"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		OnActivate = ctx.Back,
	})
	Widgets.Label({
		Name = "Intro",
		Text = Strings.Get("Garage.Intro"),
		FontFace = Theme.Fonts.Light,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = panel,
	})

	-- Sol: araç listesi
	self._list = new("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromOffset(0, 100),
		Size = UDim2.new(0, LIST_WIDTH, 1, -100),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.White,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		Parent = panel,
	}, { Widgets.List(6), Widgets.Padding(0, 8, 2, 8) })

	-- Sağ: ayrıntı
	local detail = new("Frame", {
		Name = "Detail",
		Position = UDim2.fromOffset(LIST_WIDTH + 24, 100),
		Size = UDim2.new(1, -(LIST_WIDTH + 24), 1, -100),
		BackgroundColor3 = C.Surface,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = panel,
	}, { Widgets.Corner(12), Widgets.Padding(22, 22, 18, 18) })
	local detailBody = new("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Selectable = false,
		Parent = detail,
	}, { Widgets.List(10) })
	self._name = Widgets.Label({
		Name = "Name",
		FontFace = Theme.Fonts.Display,
		TextSize = 34,
		Size = UDim2.new(1, -8, 0, 38),
		LayoutOrder = 1,
		Parent = detailBody,
	})
	self._meta = Widgets.Label({
		Name = "Meta",
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, -8, 0, 18),
		LayoutOrder = 2,
		Parent = detailBody,
	})
	local stats = new("Frame", {
		Name = "Stats",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -8, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = detailBody,
	}, { Widgets.List(6) })
	self._bars = {
		TopSpeed = statBar(stats, "Garage.TopSpeed", 1),
		Acceleration = statBar(stats, "Garage.Acceleration", 2),
		Handling = statBar(stats, "Garage.Handling", 3),
		Braking = statBar(stats, "Garage.Braking", 4),
	}
	Widgets.Label({
		Text = Strings.Get("Garage.Colors"),
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Size = UDim2.new(1, -8, 0, 16),
		LayoutOrder = 4,
		Parent = detailBody,
	})
	self._swatches = new("Frame", {
		Name = "Swatches",
		Size = UDim2.new(1, -8, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = 5,
		Parent = detailBody,
	}, { Widgets.List(8, true) })
	-- "Yakında" kutusu: dürüst bilgi + şimdilik nasıl araç kullanılır
	local soon = new("Frame", {
		Name = "ComingSoon",
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -8, 0, 0),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		LayoutOrder = 6,
		Parent = detailBody,
	}, { Widgets.Corner(10), Widgets.Stroke(C.White, 0.88), Widgets.Padding(14, 14, 12, 12), Widgets.List(6) })
	Widgets.Label({
		Text = Strings.Get("Garage.Unavailable"),
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Small,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 1,
		Parent = soon,
	})
	Widgets.Label({
		Text = Strings.Get("Garage.HowTo"),
		FontFace = Theme.Fonts.Light,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = soon,
	})

	-- Liste öğeleri
	local items = {}
	for index, entry in self._catalog do
		local def = entry.Def
		local row = Widgets.HitButton({
			Name = "Vehicle_" .. entry.Id,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = C.SurfaceHigh,
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = self._list,
		})
		Widgets.Corner(8).Parent = row
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = row,
		}, { Widgets.Corner(2) })
		new("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 16, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = def.Colors[1],
			BorderSizePixel = 0,
			Parent = row,
		}, { Widgets.Round() })
		Widgets.Label({
			Text = def.DisplayName,
			FontFace = Theme.Fonts.Title,
			TextSize = Theme.Text.Body - 1,
			Position = UDim2.fromOffset(40, 8),
			Size = UDim2.new(1, -110, 0, 22),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
		Widgets.Label({
			Text = Strings.Get("VehicleCategory." .. def.Category) .. "  ·  " .. Strings.Get("Type." .. def.Type),
			FontFace = Theme.Fonts.Light,
			TextSize = Theme.Text.Tiny,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(40, 31),
			Size = UDim2.new(1, -110, 0, 16),
			Parent = row,
		})
		Widgets.Label({
			Text = tostring(math.floor(VehicleDefinitions.ToKmh(def.MaxSpeed) + 0.5)),
			FontFace = Theme.Fonts.Mono,
			TextSize = Theme.Text.Small,
			TextColor3 = C.TextMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(60, 20),
			Parent = row,
		})
		local item
		item = {
			Gui = row,
			Scroller = self._list,
			OnFocus = function(isFocused: boolean, showHighlight: boolean)
				local on = isFocused and showHighlight
				tween(row, { BackgroundTransparency = if isFocused then (if on then 0.45 else 0.7) else 1 })
				tween(bar, { BackgroundTransparency = if isFocused then 0 else 1 })
				if isFocused then
					self:_showDetail(entry)
				end
			end,
		}
		row.Activated:Connect(function()
			self.Focus:Hover(item)
		end)
		row.MouseEnter:Connect(function()
			self.Focus:Hover(item)
		end)
		table.insert(items, item)
	end
	self.Focus:SetItems(items, 1)
	return self
end

function GarageScreen:_showDetail(entry)
	local def, m = entry.Def, self._max
	self._name.Text = def.DisplayName
	local parts = {
		Strings.Get("VehicleCategory." .. def.Category),
		Strings.Get("Type." .. def.Type),
		Strings.Get("Garage.Seats", #def.Seats),
		Strings.Get("Garage.Drive", def.Drive or "?"),
	}
	self._meta.Text = table.concat(parts, "  ·  ")
	local kmh = math.floor(VehicleDefinitions.ToKmh(def.MaxSpeed) + 0.5)
	self._bars.TopSpeed(def.MaxSpeed / m.MaxSpeed, kmh .. " " .. Strings.Get("Unit.Kmh"))
	self._bars.Acceleration(def.Accel / m.Accel, string.format("%d", math.floor(def.Accel / m.Accel * 100 + 0.5)))
	self._bars.Handling(def.Grip / m.Grip, string.format("%d", math.floor(def.Grip / m.Grip * 100 + 0.5)))
	self._bars.Braking(def.Brake / m.Brake, string.format("%d", math.floor(def.Brake / m.Brake * 100 + 0.5)))
	for _, child in self._swatches:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, color in def.Colors do
		new("Frame", {
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = self._swatches,
		}, { Widgets.Round(), Widgets.Stroke(C.White, 0.6) })
	end
end

function GarageScreen:SetCompact(_compact: boolean) end

function GarageScreen:OnShow()
	self.Focus:Refresh()
end

function GarageScreen:OnHide() end

function GarageScreen:HandleTab(_dir: number): boolean
	return false
end

return GarageScreen
