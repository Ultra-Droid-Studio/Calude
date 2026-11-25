-- Widgets: ana menü bileşenleri (buton, ayar satırları, sekme çubuğu, ipucu rozetleri, logo).
-- Her bileşen Focus öğesi döndürür; ekranlar bunları sırayla Focus'a verir.
-- Görsel durumlar tween'lenir (kısa, ucuz). Hiçbir bileşen kendi ScreenGui'sini yaratmaz.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local C = Theme.Colors
local Widgets = {}

-- ===== Temel =====
local function new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
Widgets.new = new

local function tween(inst: Instance, props: { [string]: any }, info: TweenInfo?)
	TweenService:Create(inst, info or Theme.Tween.Fast, props):Play()
end
Widgets.tween = tween

function Widgets.Corner(radius: number?): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Size.Radius) })
end

function Widgets.Round(): UICorner
	return new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function Widgets.Stroke(color: Color3?, transparency: number?, thickness: number?): UIStroke
	return new("UIStroke", {
		Color = color or C.White,
		Transparency = transparency or Theme.Alpha.Stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.Gradient(sequence: ColorSequence, rotation: number?): UIGradient
	return new("UIGradient", { Color = sequence, Rotation = rotation or 0 })
end

function Widgets.Padding(left: number, right: number, top: number, bottom: number): UIPadding
	return new("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
	})
end

function Widgets.List(padding: number, horizontal: boolean?, align: Enum.HorizontalAlignment?): UIListLayout
	return new("UIListLayout", {
		Padding = UDim.new(0, padding),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
	})
end

function Widgets.Label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		FontFace = Theme.Fonts.Body,
		TextColor3 = C.Text,
		TextSize = Theme.Text.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		AutoLocalize = false, -- metinleri Strings modülü yerelleştirir
		Text = "",
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("TextLabel", defaults)
end

-- Koyu, yarı saydam panel
function Widgets.Panel(props: { [string]: any }): Frame
	local defaults = {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = Theme.Alpha.Panel,
		BorderSizePixel = 0,
	}
	for key, value in props do
		defaults[key] = value
	end
	local panel = new("Frame", defaults)
	Widgets.Corner(14).Parent = panel
	Widgets.Stroke(C.White, 0.9).Parent = panel
	return panel
end

-- Görünmez tıklama alanı (TextButton, Text = "")
local function hitButton(props: { [string]: any }): TextButton
	local defaults = {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		AutoLocalize = false,
	}
	for key, value in props do
		defaults[key] = value
	end
	return new("TextButton", defaults)
end
Widgets.HitButton = hitButton

-- ===== Logo: çizgili gün batımı güneşi (görsel varlık gerektirmez) =====
function Widgets.Sun(size: number, stripeColor: Color3): Frame
	local disc = new("Frame", {
		Name = "Sun",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, { Widgets.Round(), Widgets.Gradient(Theme.SunGradient, 90) })
	-- alt yarıda giderek kalınlaşan yatay boşluklar (ufka batan güneş)
	local stripes = { { 0.58, 0.035 }, { 0.68, 0.05 }, { 0.78, 0.065 }, { 0.89, 0.08 } }
	for i, s in stripes do
		new("Frame", {
			Name = "Stripe" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, s[1]),
			Size = UDim2.new(1.04, 0, s[2], 0),
			BackgroundColor3 = stripeColor,
			BorderSizePixel = 0,
			Parent = disc,
		})
	end
	return disc
end

-- ===== Ana menü butonu =====
-- opts: Index ("01"), Text, Sub, Primary, LayoutOrder, OnActivate, OnHover
function Widgets.MenuButton(parent: Instance, opts: { [string]: any })
	local button = hitButton({
		Name = "Button_" .. opts.Index,
		Size = UDim2.new(1, 0, 0, Theme.Size.MainButton),
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = parent,
	})
	local accentFill = new("Frame", {
		Name = "AccentFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		BackgroundTransparency = if opts.Primary then 0.62 else 1,
		BorderSizePixel = 0,
		Parent = button,
	}, { Widgets.Corner(8), Widgets.Gradient(Theme.AccentGradient, 0) })
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0.56, 0),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = button,
	}, { Widgets.Corner(2) })
	local content = new("Frame", {
		Name = "Content",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = button,
	})
	local index = Widgets.Label({
		Name = "Index",
		Text = opts.Index,
		FontFace = Theme.Fonts.Mono,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(0, 28, 1, 0),
		Parent = content,
	})
	local label = Widgets.Label({
		Name = "Label",
		Text = opts.Text,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.MainButton,
		Position = UDim2.fromOffset(58, 11),
		Size = UDim2.new(1, -110, 0, 26),
		Parent = content,
	})
	local sub = Widgets.Label({
		Name = "Sub",
		Text = opts.Sub or "",
		FontFace = Theme.Fonts.Light,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(58, 38),
		Size = UDim2.new(1, -110, 0, 16),
		Parent = content,
	})
	local chevron = Widgets.Label({
		Name = "Chevron",
		Text = "›",
		FontFace = Theme.Fonts.Title,
		TextSize = 34,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, -2),
		Size = UDim2.fromOffset(30, 40),
		TextTransparency = 1,
		Parent = content,
	})

	local busy = false
	local focused = false
	local function render(showHighlight: boolean)
		local on = focused and showHighlight
		tween(accentFill, {
			BackgroundTransparency = if on then 0.06 elseif opts.Primary then 0.62 else 1,
		})
		tween(bar, { BackgroundTransparency = if on then 0 else 1 })
		tween(chevron, { TextTransparency = if on then 0 else 1 })
		tween(content, { Position = UDim2.fromOffset(if on then 6 else 0, 0) })
		local dim = busy
		label.TextColor3 = if dim then C.TextMuted else C.Text
		index.TextColor3 = if on then C.Text else C.TextMuted
		sub.TextColor3 = if on then C.Text else C.TextMuted
	end

	local item
	item = {
		Gui = button,
		OnFocus = function(isFocused: boolean, showHighlight: boolean)
			focused = isFocused
			render(showHighlight)
		end,
		OnActivate = function()
			if not busy and opts.OnActivate then
				opts.OnActivate()
			end
		end,
	}
	button.Activated:Connect(function()
		item.OnActivate()
	end)
	button.MouseEnter:Connect(function()
		if opts.OnHover then
			opts.OnHover(item)
		end
	end)

	local api = {
		Item = item,
		Button = button,
		SetText = function(text: string, subText: string?)
			label.Text = text
			if subText then
				sub.Text = subText
			end
		end,
		SetBusy = function(value: boolean)
			busy = value
			render(true)
		end,
	}
	return api
end

-- ===== Küçük ikincil buton (GERİ, sıfırla) =====
function Widgets.SmallButton(parent: Instance, opts: { [string]: any })
	local button = hitButton({
		Name = opts.Name or "SmallButton",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		BackgroundColor3 = C.SurfaceHigh,
		BackgroundTransparency = 0.5,
		LayoutOrder = opts.LayoutOrder or 0,
		Position = opts.Position or UDim2.new(),
		AnchorPoint = opts.AnchorPoint or Vector2.zero,
		Parent = parent,
	})
	Widgets.Corner(8).Parent = button
	local stroke = Widgets.Stroke(C.White, Theme.Alpha.Stroke)
	stroke.Parent = button
	Widgets.Padding(14, 14, 0, 0).Parent = button
	local label = Widgets.Label({
		Text = opts.Text,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Small,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = button,
	})
	local item
	item = {
		Gui = button,
		OnFocus = function(isFocused: boolean, showHighlight: boolean)
			local on = isFocused and showHighlight
			tween(stroke, { Transparency = if on then Theme.Alpha.StrokeFocus else Theme.Alpha.Stroke, Color = if on then C.Accent else C.White })
			tween(button, { BackgroundTransparency = if on then 0.25 else 0.5 })
		end,
		OnActivate = opts.OnActivate,
	}
	button.Activated:Connect(function()
		if opts.OnActivate then
			opts.OnActivate()
		end
	end)
	button.MouseEnter:Connect(function()
		if opts.OnHover then
			opts.OnHover(item)
		end
	end)
	return { Item = item, Button = button, Label = label }
end

-- ===== Ayar satırı iskeleti =====
-- opts: Label, Desc, LayoutOrder, Scroller, OnHover
local function settingRow(parent: Instance, opts: { [string]: any })
	local row = hitButton({
		Name = "Row_" .. (opts.Key or "Info"),
		Size = UDim2.new(1, 0, 0, Theme.Size.Row),
		BackgroundColor3 = C.SurfaceHigh,
		BackgroundTransparency = 1,
		LayoutOrder = opts.LayoutOrder or 0,
		Parent = parent,
	})
	Widgets.Corner(8).Parent = row
	local bar = new("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = row,
	}, { Widgets.Corner(2) })
	Widgets.Label({
		Name = "Label",
		Text = opts.Label,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Body,
		Position = UDim2.fromOffset(18, if opts.Desc then 11 else 0),
		Size = UDim2.new(1, -330, 0, if opts.Desc then 22 else Theme.Size.Row),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	if opts.Desc then
		Widgets.Label({
			Name = "Desc",
			Text = opts.Desc,
			FontFace = Theme.Fonts.Light,
			TextSize = Theme.Text.Tiny + 1,
			TextColor3 = C.TextMuted,
			Position = UDim2.fromOffset(18, 35),
			Size = UDim2.new(1, -330, 0, 16),
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
	end
	local control = new("Frame", {
		Name = "Control",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(290, 40),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local function setFocused(on: boolean)
		tween(row, { BackgroundTransparency = if on then Theme.Alpha.RowFocus else 1 })
		tween(bar, { BackgroundTransparency = if on then 0 else 1 })
	end
	return row, control, setFocused
end

local function makeItem(row: GuiObject, setFocused: (boolean) -> (), opts: { [string]: any })
	local item = {
		Gui = row,
		Scroller = opts.Scroller,
		OnFocus = function(isFocused: boolean, showHighlight: boolean)
			setFocused(isFocused and showHighlight)
		end,
		OnActivate = opts.OnActivate,
		OnAdjust = opts.OnAdjust,
	}
	row.MouseEnter:Connect(function()
		if opts.OnHover then
			opts.OnHover(item)
		end
	end)
	return item
end

-- Aç/kapa anahtarı. opts: Get() -> bool, Set(bool), OnText, OffText
function Widgets.ToggleRow(parent: Instance, opts: { [string]: any })
	local row, control, setFocused = settingRow(parent, opts)
	local pill = new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(54, 28),
		BackgroundColor3 = C.SurfaceHigh,
		BorderSizePixel = 0,
		Parent = control,
	}, { Widgets.Round() })
	local knob = new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = pill,
	}, { Widgets.Round() })
	local state = Widgets.Label({
		Name = "State",
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -66, 0.5, 0),
		Size = UDim2.fromOffset(90, 20),
		Parent = control,
	})
	local function refresh()
		local on = opts.Get() == true
		tween(pill, { BackgroundColor3 = if on then C.Accent else C.SurfaceHigh })
		tween(knob, { Position = if on then UDim2.new(1, -24, 0.5, 0) else UDim2.new(0, 4, 0.5, 0) })
		state.Text = if on then opts.OnText else opts.OffText
		state.TextColor3 = if on then C.Text else C.TextMuted
	end
	local function toggle()
		opts.Set(not (opts.Get() == true))
	end
	opts.OnActivate = toggle
	opts.OnAdjust = function(dir: number)
		opts.Set(dir > 0)
	end
	local item = makeItem(row, setFocused, opts)
	row.Activated:Connect(toggle)
	refresh()
	return { Item = item, Refresh = refresh, Row = row }
end

-- Seçenekler arasında ‹ değer › gezinme. opts: Options, Get(), Set(v), Format(v) -> string
function Widgets.StepperRow(parent: Instance, opts: { [string]: any })
	local row, control, setFocused = settingRow(parent, opts)
	local left = hitButton({
		Name = "Prev",
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 70, 0.5, 0),
		Parent = control,
	})
	local right = hitButton({
		Name = "Next",
		Size = UDim2.fromOffset(36, 36),
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Parent = control,
	})
	for _, b in { left, right } do
		Widgets.Label({
			Text = if b == left then "‹" else "›",
			FontFace = Theme.Fonts.Title,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromOffset(0, -2),
			TextColor3 = C.TextMuted,
			Parent = b,
		})
	end
	local value = Widgets.Label({
		Name = "Value",
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Body - 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(106, 0),
		Size = UDim2.new(1, -142, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = control,
	})
	local dots = new("Frame", {
		Name = "Dots",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 35, 1, 2),
		Size = UDim2.fromOffset(120, 4),
		BackgroundTransparency = 1,
		Parent = control,
	}, { Widgets.List(4, true, Enum.HorizontalAlignment.Center) })
	local dotFrames = {}
	for i = 1, #opts.Options do
		dotFrames[i] = new("Frame", {
			Size = UDim2.fromOffset(14, 3),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = dots,
		}, { Widgets.Corner(2) })
	end
	local function currentIndex(): number
		return table.find(opts.Options, opts.Get()) or 1
	end
	local function refresh()
		local i = currentIndex()
		value.Text = opts.Format(opts.Options[i])
		for k, dot in dotFrames do
			dot.BackgroundTransparency = if k == i then 0 else 0.75
			dot.BackgroundColor3 = if k == i then C.Accent else C.White
		end
	end
	local function step(dir: number)
		local count = #opts.Options
		local i = ((currentIndex() - 1 + dir) % count) + 1
		opts.Set(opts.Options[i])
	end
	opts.OnActivate = function()
		step(1)
	end
	opts.OnAdjust = step
	local item = makeItem(row, setFocused, opts)
	left.Activated:Connect(function()
		step(-1)
	end)
	right.Activated:Connect(function()
		step(1)
	end)
	row.Activated:Connect(function()
		step(1)
	end)
	refresh()
	return { Item = item, Refresh = refresh, Row = row }
end

-- Sürükleme (fare/dokunmatik): tek global bağlantı çifti, tüm kaydırıcılar paylaşır
local activeDrag: { Input: InputObject, Update: (number) -> (), Stop: () -> () }? = nil
local dragConnected = false
local function connectDrag()
	if dragConnected then
		return
	end
	dragConnected = true
	UserInputService.InputChanged:Connect(function(input)
		local drag = activeDrag
		if not drag then
			return
		end
		local isMouse = drag.Input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement
		if isMouse or input == drag.Input then
			drag.Update(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local drag = activeDrag
		if drag and (input == drag.Input or (drag.Input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseButton1)) then
			activeDrag = nil
			drag.Stop()
		end
	end)
end

-- Kaydırıcı. opts: Min, Max, Step, Get(), Set(v), Format(v), Scroller
function Widgets.SliderRow(parent: Instance, opts: { [string]: any })
	connectDrag()
	local row, control, setFocused = settingRow(parent, opts)
	local hit = hitButton({
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 40, 0.5, 0),
		Size = UDim2.fromOffset(176, 36),
		Parent = control,
	})
	local track = new("Frame", {
		Name = "Rail",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = C.SurfaceHigh,
		BorderSizePixel = 0,
		Parent = hit,
	}, { Widgets.Round() })
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = track,
	}, { Widgets.Round(), Widgets.Gradient(Theme.AccentGradient, 0) })
	local knob = new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = track,
	}, { Widgets.Round() })
	local value = Widgets.Label({
		Name = "Value",
		FontFace = Theme.Fonts.Mono,
		TextSize = Theme.Text.Small + 1,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(62, 20),
		Parent = control,
	})
	local function refresh()
		local v = opts.Get()
		local t = math.clamp((v - opts.Min) / (opts.Max - opts.Min), 0, 1)
		fill.Size = UDim2.fromScale(t, 1)
		knob.Position = UDim2.fromScale(t, 0.5)
		value.Text = opts.Format(v)
	end
	local function setFromX(x: number)
		local width = math.max(track.AbsoluteSize.X, 1)
		local t = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		opts.Set(opts.Min + t * (opts.Max - opts.Min))
	end
	opts.OnAdjust = function(dir: number)
		opts.Set(opts.Get() + dir * opts.Step)
	end
	local item = makeItem(row, setFocused, opts)
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if opts.Scroller then
				opts.Scroller.ScrollingEnabled = false
			end
			activeDrag = {
				Input = input,
				Update = setFromX,
				Stop = function()
					if opts.Scroller then
						opts.Scroller.ScrollingEnabled = true
					end
				end,
			}
			setFromX(input.Position.X)
			if opts.OnHover then
				opts.OnHover(item)
			end
		end
	end)
	refresh()
	return { Item = item, Refresh = refresh, Row = row }
end

-- Salt okunur bilgi satırı (tuş listesi). Odaklanabilir: gamepad ile kaydırılabilsin diye.
function Widgets.InfoRow(parent: Instance, opts: { [string]: any })
	local row, control, setFocused = settingRow(parent, opts)
	Widgets.Label({
		Name = "Value",
		Text = opts.Value,
		FontFace = Theme.Fonts.Mono,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(1, 1),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = control,
	})
	local item = makeItem(row, setFocused, opts)
	return { Item = item, Row = row }
end

-- Bölüm başlığı / açıklama notu (odaklanmaz)
function Widgets.SectionLabel(parent: Instance, text: string, layoutOrder: number, muted: boolean?)
	return Widgets.Label({
		Name = "Section",
		Text = text,
		FontFace = if muted then Theme.Fonts.Light else Theme.Fonts.Title,
		TextSize = if muted then Theme.Text.Small else Theme.Text.Small,
		TextColor3 = if muted then C.TextMuted else C.Accent,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -18, 0, 20),
		Position = UDim2.fromOffset(18, 0),
		LayoutOrder = layoutOrder,
		Parent = parent,
	})
end

-- ===== Sekme çubuğu =====
-- opts: Labels { string }, OnSelect(index), OnHover
function Widgets.TabBar(parent: Instance, opts: { [string]: any })
	local bar = new("Frame", {
		Name = "Tabs",
		Size = UDim2.new(1, 0, 0, Theme.Size.Tab),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local holder = new("Frame", {
		Name = "Holder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = bar,
	}, { Widgets.List(6, true) })
	local underlineBase = new("Frame", {
		Name = "Base",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = bar,
	})
	local _ = underlineBase
	local tabs = {}
	local selected = 1
	local focused = false
	local highlight = true
	local function render()
		for i, t in tabs do
			local on = i == selected
			t.Label.TextColor3 = if on then C.Text else C.TextMuted
			tween(t.Line, { BackgroundTransparency = if on then 0 else 1 })
			tween(t.Button, { BackgroundTransparency = if on and focused and highlight then 0.55 else 1 })
		end
	end
	for i, text in opts.Labels do
		local button = hitButton({
			Name = "Tab" .. i,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = C.SurfaceHigh,
			LayoutOrder = i,
			Parent = holder,
		})
		Widgets.Corner(8).Parent = button
		Widgets.Padding(16, 16, 0, 0).Parent = button
		local label = Widgets.Label({
			Text = text,
			FontFace = Theme.Fonts.Title,
			TextSize = Theme.Text.Small + 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			Parent = button,
		})
		local line = new("Frame", {
			Name = "Line",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, 3),
			BackgroundColor3 = C.White,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = button,
		}, { Widgets.Corner(2), Widgets.Gradient(Theme.AccentGradient, 0) })
		tabs[i] = { Button = button, Label = label, Line = line }
		button.Activated:Connect(function()
			opts.OnSelect(i)
		end)
	end
	local item
	item = {
		Gui = bar,
		OnFocus = function(isFocused: boolean, showHighlight: boolean)
			focused = isFocused
			highlight = showHighlight
			render()
		end,
		OnAdjust = function(dir: number)
			local i = math.clamp(selected + dir, 1, #tabs)
			if i ~= selected then
				opts.OnSelect(i)
			end
		end,
	}
	for _, t in tabs do
		t.Button.MouseEnter:Connect(function()
			if opts.OnHover then
				opts.OnHover(item)
			end
		end)
	end
	render()
	return {
		Item = item,
		Frame = bar,
		SetSelected = function(index: number)
			selected = index
			render()
		end,
	}
end

-- ===== Tuş ipucu: [rozet] Açıklama =====
function Widgets.KeyHint(parent: Instance, key: string, text: string, layoutOrder: number, round: boolean?)
	local holder = new("Frame", {
		Name = "Hint",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = layoutOrder,
		Parent = parent,
	}, { Widgets.List(8, true) })
	local badge = new("Frame", {
		Name = "Badge",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(if round then 26 else 0, 26),
		BackgroundColor3 = C.White,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = holder,
	}, { if round then Widgets.Round() else Widgets.Corner(6), Widgets.Stroke(C.White, 0.7) })
	if not round then
		Widgets.Padding(8, 8, 0, 0).Parent = badge
	end
	Widgets.Label({
		Text = key,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Tiny,
		TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = if round then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		Size = if round then UDim2.fromScale(1, 1) else UDim2.fromScale(0, 1),
		Parent = badge,
	})
	Widgets.Label({
		Text = text,
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = 2,
		Parent = holder,
	})
	return holder
end

return Widgets
