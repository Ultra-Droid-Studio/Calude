-- VehicleHUDController: sürüş göstergesi (Aşama 3).
--
-- Masaüstü / gamepad:  sağ alt yuvarlak gösterge (devir yayı, büyük hız, vites), solunda durum şeridi
--                      (sinyal ◀ ▶, far, el freni, ABS, TCS, ESC), sol altta HARİTA alanı (ileride minimap).
-- Dokunmatik:          üst ortada kompakt çubuk + sol üstte harita alanı. Yerleri DrivingLayout'tan gelir;
--                      mobil sürüş butonları aynı hesabı kullandığından üst üste binmezler.
--
-- Sadece araçtayken görünür. 20 Hz güncellenir; kare başına tablo yaratmaz. Görsel varlık kullanmaz
-- (oklar ve yay çizgileri düz Frame'lerden).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local DrivingLayout = require(Modules:WaitForChild("DrivingLayout"))

local FrontEnd = script.Parent.Parent:WaitForChild("FrontEnd")
local Theme = require(FrontEnd:WaitForChild("Theme"))
local Strings = require(FrontEnd:WaitForChild("Strings"))

local VehicleHUDController = {
	Name = "VehicleHUDController",
	Priority = 9,
}

local C = Theme.Colors
local player = Players.LocalPlayer
local controllers

local TICKS = 27 -- devir yayı çizgi sayısı (270°)
local UPDATE_INTERVAL = 0.05

local COLOR_LIGHTS = Color3.fromRGB(120, 200, 255)
local COLOR_SIGNAL = Color3.fromRGB(90, 220, 120)
local COLOR_ASSIST = Color3.fromRGB(255, 186, 60)

local gui: ScreenGui
local root: Frame
local views = {} -- Desktop / Touch: { Frame, Speed, Unit, Gear, Ticks/Segments, Icons, Status, Minimap }
local activeView = nil
local litCount = -1

-- ===== Yardımcılar =====
local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function round(parent: Instance, scale: number?)
	new("UICorner", { CornerRadius = UDim.new(scale or 0.5, 0), Parent = parent })
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = C.Text,
		FontFace = Theme.Fonts.Title,
		TextScaled = true,
		AutoLocalize = false,
		Text = "",
		Parent = parent,
	}
	for k, v in props do
		defaults[k] = v
	end
	return new("TextLabel", defaults)
end

-- İki çubuktan ok (sinyal); sola/sağa
local function chevron(parent: Instance, pointsLeft: boolean): { Frame }
	local bars = {}
	local halfX, halfY = 0.21 * math.cos(math.rad(40)), 0.21 * math.sin(math.rad(40))
	local apexX = if pointsLeft then 0.3 else 0.7
	for _, sign in { -1, 1 } do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(apexX + (if pointsLeft then halfX else -halfX), 0.5 + sign * halfY),
			Size = UDim2.new(0.42, 0, 0, 3),
			Rotation = (if pointsLeft then 1 else -1) * sign * 40,
			BackgroundColor3 = C.TextDim,
			BorderSizePixel = 0,
			Parent = parent,
		})
		round(bar)
		table.insert(bars, bar)
	end
	return bars
end

-- Durum rozeti (metin) ya da ok rozeti
local function badge(parent: Instance, name: string, textValue: string?, pointsLeft: boolean?, order: number)
	local holder = new("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local item = { Holder = holder, On = false, Color = C.Text }
	if textValue then
		holder.Size = UDim2.new(0, 0, 1, 0)
		holder.AutomaticSize = Enum.AutomaticSize.X
		holder.SizeConstraint = Enum.SizeConstraint.RelativeXY
		item.Label = label(holder, {
			Text = textValue,
			TextScaled = false,
			TextSize = 13,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			TextColor3 = C.TextDim,
		})
		new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), Parent = holder })
	else
		item.Bars = chevron(holder, pointsLeft == true)
	end
	return item
end

local function setBadge(item, on: boolean, color: Color3)
	if item.On == on and item.Color == color then
		return
	end
	item.On, item.Color = on, color
	local value = if on then color else C.TextDim
	if item.Label then
		item.Label.TextColor3 = value
		item.Label.TextTransparency = if on then 0 else 0.35
	elseif item.Bars then
		for _, bar in item.Bars do
			bar.BackgroundColor3 = value
			bar.BackgroundTransparency = if on then 0 else 0.35
		end
	end
end

-- Durum satırı: ◀ FAR P ABS TCS ESC ▶ (masaüstü tek satır). twoRows: ◀ FAR P ▶ / ABS TCS ESC (dar çubuk)
local function statusRow(parent: Instance, textSize: number, twoRows: boolean?)
	local function makeRow(name: string, position: UDim2, size: UDim2): Frame
		local row = new("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Position = position,
			Size = size,
			Parent = parent,
		})
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, if twoRows then 2 else 4),
			Parent = row,
		})
		return row
	end
	local top, bottom
	if twoRows then
		top = makeRow("StatusTop", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.5))
		bottom = makeRow("StatusBottom", UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.5))
	else
		top = makeRow("Status", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
		bottom = top
	end
	local icons = {
		IndL = badge(top, "IndL", nil, true, 1),
		Lights = badge(top, "Lights", Strings.Get("HUD.Lights"), nil, 2),
		Hand = badge(top, "Hand", "P", nil, 3),
		Abs = badge(bottom, "Abs", "ABS", nil, 4),
		Tcs = badge(bottom, "Tcs", "TCS", nil, 5),
		Esc = badge(bottom, "Esc", "ESC", nil, 6),
		IndR = badge(top, "IndR", nil, false, 7),
	}
	for _, item in icons do
		if item.Label then
			item.Label.TextSize = textSize
		end
	end
	return top, icons
end

-- Harita alanı (ileride minimap buraya yerleşir). Şimdilik ince bir halka ve "yakında" etiketi.
local function minimapSlot(parent: Instance): Frame
	local slot = new("Frame", {
		Name = "MinimapSlot",
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.55,
		Parent = parent,
	})
	slot:SetAttribute("ReservedFor", "Minimap")
	round(slot)
	new("UIStroke", { Color = C.White, Transparency = 0.75, Thickness = 1.5, Parent = slot })
	label(slot, {
		Text = "N",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.05),
		Size = UDim2.fromScale(0.14, 0.12),
		TextColor3 = C.Accent,
	})
	label(slot, {
		Text = Strings.Get("HUD.Map"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.1),
		FontFace = Theme.Fonts.Body,
		TextColor3 = C.TextMuted,
		TextTransparency = 0.25,
	})
	return slot
end

-- ===== Masaüstü görünümü =====
local function buildDesktop()
	local frame = new("Frame", { Name = "Desktop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root })
	local cluster = new("Frame", {
		Name = "Cluster",
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.2,
		Parent = frame,
	})
	round(cluster)
	new("UIStroke", { Color = C.White, Transparency = 0.8, Thickness = 1.5, Parent = cluster })
	-- devir yayı: 135° (sol alt) → 405° (sağ alt), saat yönünde üstten geçer
	local ticks = {}
	for i = 0, TICKS - 1 do
		local t = i / (TICKS - 1)
		local angle = math.rad(135 + 270 * t)
		local major = i % 3 == 0
		local tick = new("Frame", {
			Name = "Tick" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.42, 0.5 + math.sin(angle) * 0.42),
			Size = UDim2.new(0, if major then 3 else 2, if major then 0.09 else 0.06, 0),
			Rotation = math.deg(angle) + 90,
			BackgroundColor3 = C.TextDim,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = cluster,
		})
		ticks[i + 1] = tick
	end
	local speed = label(cluster, {
		Name = "Speed",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.62, 0.3),
		FontFace = Theme.Fonts.Display,
		Text = "0",
	})
	local unit = label(cluster, {
		Name = "Unit",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.3, 0.07),
		FontFace = Theme.Fonts.Body,
		TextColor3 = C.TextMuted,
		Text = Strings.Get("HUD.Unit"),
	})
	local gearBox = new("Frame", {
		Name = "GearBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.79),
		Size = UDim2.fromScale(0.17, 0.17),
		BackgroundTransparency = 1,
		Parent = cluster,
	})
	round(gearBox)
	local gearStroke = new("UIStroke", { Color = C.Accent, Thickness = 2, Parent = gearBox })
	local gear = label(gearBox, { Name = "Gear", Size = UDim2.fromScale(0.8, 0.8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Text = "N" })

	local strip = new("Frame", {
		Name = "Strip",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromOffset(250, 32),
		Parent = frame,
	})
	round(strip)
	local _, icons = statusRow(strip, 13)
	local status = label(frame, {
		Name = "Vehicle",
		AnchorPoint = Vector2.new(1, 1),
		Size = UDim2.fromOffset(250, 18),
		FontFace = Theme.Fonts.Body,
		TextScaled = false,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.TextMuted,
	})
	return {
		Frame = frame, Cluster = cluster, Speed = speed, Unit = unit, Gear = gear, GearStroke = gearStroke,
		Ticks = ticks, Strip = strip, Icons = icons, Status = status, Minimap = minimapSlot(frame),
	}
end

-- ===== Dokunmatik görünüm =====
local function buildTouch()
	local frame = new("Frame", { Name = "Touch", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root })
	local bar = new("Frame", { Name = "Bar", BackgroundColor3 = C.Background, BackgroundTransparency = 0.2, Parent = frame })
	round(bar, 0.3)
	new("UIStroke", { Color = C.White, Transparency = 0.82, Thickness = 1, Parent = bar })
	local speed = label(bar, {
		Name = "Speed",
		Position = UDim2.fromScale(0.03, 0.08),
		Size = UDim2.fromScale(0.27, 0.6),
		FontFace = Theme.Fonts.Display,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0",
	})
	local unit = label(bar, {
		Name = "Unit",
		Position = UDim2.fromScale(0.31, 0.4),
		Size = UDim2.fromScale(0.14, 0.24),
		FontFace = Theme.Fonts.Body,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = Strings.Get("HUD.Unit"),
	})
	local gearBox = new("Frame", {
		Name = "GearBox",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.6, 0.6),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundTransparency = 1,
		Parent = bar,
	})
	round(gearBox)
	local gearStroke = new("UIStroke", { Color = C.Accent, Thickness = 2, Parent = gearBox })
	local gear = label(gearBox, { Name = "Gear", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.75, 0.75), Text = "N" })
	local iconsHolder = new("Frame", {
		Name = "Icons",
		Position = UDim2.fromScale(0.58, 0.06),
		Size = UDim2.fromScale(0.4, 0.68),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	local _, icons = statusRow(iconsHolder, 10, true)
	-- devir: alt kenarda segmentli çubuk
	local rpm = new("Frame", {
		Name = "Rpm",
		Position = UDim2.fromScale(0.05, 0.8),
		Size = UDim2.fromScale(0.9, 0.1),
		BackgroundTransparency = 1,
		Parent = bar,
	})
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.01, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = rpm })
	local segments = {}
	for i = 1, 16 do
		segments[i] = new("Frame", {
			Size = UDim2.fromScale(1 / 16 - 0.01, 1),
			BackgroundColor3 = C.TextDim,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = rpm,
		})
	end
	return {
		Frame = frame, Bar = bar, Speed = speed, Unit = unit, Gear = gear, GearStroke = gearStroke,
		Ticks = segments, Icons = icons, Minimap = minimapSlot(frame),
	}
end

-- ===== Yerleşim =====
local function applyLayout()
	if not root then
		return
	end
	local area = root.AbsoluteSize
	if area.X < 10 then
		return
	end
	local touch = controllers.InputController:IsTouch()
	local d = views.Desktop
	local t = views.Touch
	if touch then
		local scale = controllers.SettingsController:Get("MobileButtonScale") or 1
		local base = DrivingLayout.ButtonSize(area.X, area.Y, scale)
		local rects = DrivingLayout.Touch(area.X, area.Y, base, { Kind = "Car" })
		t.Bar.Position = UDim2.fromOffset(rects.Hud.X, rects.Hud.Y)
		t.Bar.Size = UDim2.fromOffset(rects.Hud.W, rects.Hud.H)
		t.Minimap.Position = UDim2.fromOffset(rects.Minimap.X, rects.Minimap.Y)
		t.Minimap.Size = UDim2.fromOffset(rects.Minimap.W, rects.Minimap.H)
		activeView = t
	else
		local rects = DrivingLayout.Desktop(area.X, area.Y)
		local c = rects.Cluster
		d.Cluster.Position = UDim2.fromOffset(c.X, c.Y)
		d.Cluster.Size = UDim2.fromOffset(c.W, c.H)
		d.Strip.Position = UDim2.fromOffset(c.X - 12, c.Y + c.H - math.floor(c.H * 0.08))
		d.Status.Position = UDim2.fromOffset(c.X - 14, c.Y + c.H - math.floor(c.H * 0.08) - 38)
		d.Minimap.Position = UDim2.fromOffset(rects.Minimap.X, rects.Minimap.Y)
		d.Minimap.Size = UDim2.fromOffset(rects.Minimap.W, rects.Minimap.H)
		activeView = d
	end
	d.Frame.Visible = not touch
	t.Frame.Visible = touch
	litCount = -1
end

-- ===== Güncelleme =====
local function setRpm(view, rpm: number)
	local count = #view.Ticks
	local lit = math.clamp(math.floor(rpm * count + 0.5), 0, count)
	if lit == litCount then
		return
	end
	litCount = lit
	for i, tick in view.Ticks do
		local t = i / count
		local on = i <= lit
		tick.BackgroundColor3 = if not on then C.TextDim elseif t > 0.9 then C.Danger elseif t > 0.75 then C.Accent else C.Text
		tick.BackgroundTransparency = if on then 0 else 0.35
	end
end

local function refresh()
	local vehicle = controllers.VehicleController
	local c = vehicle:GetCurrent()
	if not c then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	local view = activeView
	if not view then
		return
	end
	local chassis = c.Chassis
	-- Sürücüde araç modelinin hesapladığı hız; yolcuda şasi hızı
	local speed = 0
	if chassis and chassis.Parent then
		speed = if c.IsDriver and c.Speed then c.Speed else chassis.AssemblyLinearVelocity.Magnitude
	end
	view.Speed.Text = tostring(math.floor(VehicleDefinitions.ToKmh(speed) + 0.5))

	local car = c.Car
	local telemetry = car and car.Telemetry
	local gear = if c.IsDriver then tostring(c.Gear or "N") else "—"
	view.Gear.Text = gear
	view.Gear.TextColor3 = if gear == "R" then C.Accent else C.Text

	local rpm
	if telemetry then
		rpm = telemetry.RpmNorm
	else
		rpm = math.clamp(speed / math.max(c.Def.MaxSpeed, 1), 0, 1)
	end
	setRpm(view, if c.IsDriver then rpm else 0)

	local model = c.Model
	local indicator = model:GetAttribute("Indicator") or ""
	local blink = (os.clock() * 2.5) % 1 < 0.5
	local icons = view.Icons
	setBadge(icons.IndL, blink and (indicator == "L" or indicator == "H"), COLOR_SIGNAL)
	setBadge(icons.IndR, blink and (indicator == "R" or indicator == "H"), COLOR_SIGNAL)
	setBadge(icons.Lights, model:GetAttribute("Lights") == true, COLOR_LIGHTS)
	local hand = if telemetry then telemetry.Handbrake > 0.5 else (c.IsDriver and controllers.InputController:IsActionActive("VehHandbrake"))
	setBadge(icons.Hand, hand == true, C.Danger)
	setBadge(icons.Abs, telemetry ~= nil and telemetry.AbsActive, COLOR_ASSIST)
	setBadge(icons.Tcs, telemetry ~= nil and telemetry.TcActive, COLOR_ASSIST)
	setBadge(icons.Esc, telemetry ~= nil and telemetry.EscActive, COLOR_ASSIST)
	if view.Status then
		view.Status.Text = c.Def.DisplayName .. "  ·  " .. Strings.Get(if c.IsDriver then "HUD.Driver" else "HUD.Passenger")
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "VehicleHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- mobil butonlarla aynı koordinat alanı
	gui.Enabled = false
	root = new("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	views.Desktop = buildDesktop()
	views.Touch = buildTouch()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function VehicleHUDController:Init(allControllers)
	controllers = allControllers
end

function VehicleHUDController:Start()
	build()
	applyLayout()
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
	controllers.InputController.DeviceChanged:Connect(applyLayout)
	controllers.SettingsController.Changed:Connect(function(key)
		if key == "MobileButtonScale" then
			applyLayout()
		end
	end)
	controllers.VehicleController.Entered:Connect(function()
		applyLayout()
		pcall(refresh)
	end)
	controllers.VehicleController.Exited:Connect(function()
		gui.Enabled = false
	end)
	local accumulator = 0
	RunService.RenderStepped:Connect(function(dt)
		accumulator += dt
		if accumulator < UPDATE_INTERVAL then
			return
		end
		accumulator = 0
		if controllers.VehicleController:IsInVehicle() then
			local ok, err = pcall(refresh)
			if not ok then
				warn("[VehicleHUD]", err)
			end
		elseif gui.Enabled then
			gui.Enabled = false
		end
	end)
end

return VehicleHUDController
