-- SettingsScreen: sekmeli ayarlar paneli. Satırlar Shared/SettingsSchema'dan ÜRETİLİR;
-- yeni ayar eklemek için bu dosyaya dokunmak gerekmez (şema + Strings yeter).
-- Değişiklikler anında uygulanır (SettingsController.Changed → ilgili sistemler).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontEnd = script.Parent.Parent
local Theme = require(FrontEnd.Theme)
local Widgets = require(FrontEnd.Widgets)
local Strings = require(FrontEnd.Strings)
local Focus = require(FrontEnd.Focus)
local Maid = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Utilities"):WaitForChild("Maid"))

local C = Theme.Colors
local new = Widgets.new

local SettingsScreen = {}
SettingsScreen.__index = SettingsScreen

-- Sayısal ayarların gösterimi
local FORMAT = {
	CameraSensitivity = function(v)
		return string.format("%.1fx", v)
	end,
	FieldOfViewOffset = function(v)
		return (if v > 0 then "+" else "") .. tostring(math.floor(v + 0.5)) .. "°"
	end,
}
local function formatNumber(key: string, v: number): string
	local f = FORMAT[key]
	if f then
		return f(v)
	end
	return tostring(math.floor(v * 100 + 0.5)) .. "%" -- 0..1 hacimler
end

-- Kontroller sekmesindeki tuş listesi (salt okunur). Klavye | gamepad metinleri.
local BINDINGS = {
	{ "Bindings.Move", "W A S D", "LS" },
	{ "Bindings.Sprint", "Shift", "L3" },
	{ "Bindings.Walk", "Ctrl", "R3" },
	{ "Bindings.Camera", "V", "D-Pad Up" },
	{ "Bindings.Menu", "P", "D-Pad Left" },
	{ "Bindings.Enter", "F", "Y" },
	{ "Bindings.Drive", "W / S", "RT / LT" },
	{ "Bindings.Steer", "A / D", "LS" },
	{ "Bindings.Handbrake", "Space", "X" },
	{ "Bindings.Exit", "F", "Y" },
	{ "Bindings.Lights", "L", "D-Pad Down" },
	{ "Bindings.Indicators", "Q / E", "D-Pad Left / Right" },
	{ "Bindings.Horn", "H", "L3" },
	{ "Bindings.Flip", "R", "B" },
}

-- ctx: Parent, GetScale, OnMove, Settings (SettingsController), Back
function SettingsScreen.new(ctx)
	local self = setmetatable({}, SettingsScreen)
	self._ctx = ctx
	self._settings = ctx.Settings
	self._schema = ctx.Settings:GetSchema()
	self._categories = self._schema.Categories
	self._category = 1
	self._rowMaid = Maid.new()
	self._refreshers = {} :: { [string]: () -> () }
	self.Focus = Focus.new(ctx.GetScale, ctx.OnMove)

	self.Root = new("Frame", {
		Name = "SettingsScreen",
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
	new("UISizeConstraint", { MaxSize = Vector2.new(920, 660) }).Parent = panel
	Widgets.Padding(28, 28, 20, 18).Parent = panel

	-- Başlık + geri
	Widgets.Label({
		Name = "Title",
		Text = Strings.Get("Settings.Title"),
		FontFace = Theme.Fonts.Display,
		TextSize = Theme.Text.Heading,
		Size = UDim2.new(1, -140, 0, 40),
		Parent = panel,
	})
	self._back = Widgets.SmallButton(panel, {
		Name = "Back",
		Text = "‹  " .. Strings.Get("Settings.Back"),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 2),
		OnActivate = ctx.Back,
	})

	-- Sekmeler
	local tabsHolder = new("Frame", {
		Name = "TabsHolder",
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, Theme.Size.Tab),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local labels = {}
	for i, category in self._categories do
		labels[i] = Strings.Get("Category." .. category)
	end
	self._tabs = Widgets.TabBar(tabsHolder, {
		Labels = labels,
		OnSelect = function(index)
			self:SelectCategory(index, true)
		end,
		OnHover = function(item)
			self.Focus:Hover(item)
		end,
	})

	-- Satır listesi
	self._scroller = new("ScrollingFrame", {
		Name = "Rows",
		Position = UDim2.fromOffset(0, 52 + Theme.Size.Tab + 12),
		Size = UDim2.new(1, 0, 1, -(52 + Theme.Size.Tab + 12 + 46)),
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
	}, { Widgets.List(6), Widgets.Padding(0, 10, 2, 8) })

	-- Alt bilgi: sıfırla + kalıcılık notu
	local footer = new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	self._reset = Widgets.SmallButton(footer, {
		Name = "Reset",
		Text = Strings.Get("Settings.Reset"),
		OnActivate = function()
			self._settings:ResetToDefaults(self._categories[self._category])
		end,
		OnHover = function(item)
			self.Focus:Hover(item)
		end,
	})
	local persistNote = Widgets.Label({
		Name = "PersistNote",
		Text = Strings.Get("Settings.PersistNote") .. "\n" .. Strings.Get("Settings.Credits"), -- model atıfları (CC BY)
		FontFace = Theme.Fonts.Light,
		TextSize = Theme.Text.Tiny,
		TextColor3 = C.TextDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(1, -240, 1, 0),
		Parent = footer,
	})
	-- iki satır (not + model atıfları): dar ekranda alt bilgiye sığsın diye küçülebilir
	persistNote.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = Theme.Text.Tiny
	fit.MinTextSize = 7
	fit.Parent = persistNote

	-- Başka yerden değişen ayar (ör. V tuşu, sıfırlama) satıra yansısın
	self._changedConn = self._settings.Changed:Connect(function(key)
		local refresh = self._refreshers[key]
		if refresh then
			refresh()
		end
	end)

	self:SelectCategory(1, false)
	return self
end

function SettingsScreen:_buildRows()
	self._rowMaid:Clean()
	table.clear(self._refreshers)
	local settings = self._settings
	local category = self._categories[self._category]
	local hover = function(item)
		self.Focus:Hover(item)
	end
	local items = { self._tabs.Item }
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local note = Strings.Get("Note." .. category)
	if note ~= "Note." .. category then
		self._rowMaid:Give(Widgets.SectionLabel(self._scroller, note, nextOrder(), true))
	end

	for _, def in self._schema.GetByCategory(category) do
		local opts = {
			Key = def.Key,
			Label = Strings.Get("Setting." .. def.Key),
			Desc = Strings.Get("Setting." .. def.Key .. ".Desc"),
			LayoutOrder = nextOrder(),
			Scroller = self._scroller,
			OnHover = hover,
			Get = function()
				return settings:Get(def.Key)
			end,
			Set = function(value)
				settings:Set(def.Key, value)
			end,
		}
		local widget
		if def.Type == "boolean" then
			opts.OnText = Strings.Get("Option.On")
			opts.OffText = Strings.Get("Option.Off")
			widget = Widgets.ToggleRow(self._scroller, opts)
		elseif def.Type == "enum" then
			opts.Options = def.Options
			opts.Format = function(value)
				return Strings.Option(def.Key, value)
			end
			widget = Widgets.StepperRow(self._scroller, opts)
		elseif def.Type == "number" then
			opts.Min, opts.Max, opts.Step = def.Min, def.Max, def.Step
			opts.Format = function(value)
				return formatNumber(def.Key, value)
			end
			widget = Widgets.SliderRow(self._scroller, opts)
		end
		if widget then
			self._rowMaid:Give(widget.Row)
			self._refreshers[def.Key] = widget.Refresh
			table.insert(items, widget.Item)
		end
	end

	if category == "Controls" then
		self._rowMaid:Give(Widgets.SectionLabel(self._scroller, Strings.Get("Bindings.Title"), nextOrder(), false))
		for _, b in BINDINGS do
			local info = Widgets.InfoRow(self._scroller, {
				Key = b[1],
				Label = Strings.Get(b[1]),
				Value = b[2] .. "   ·   " .. b[3],
				LayoutOrder = nextOrder(),
				Scroller = self._scroller,
				OnHover = hover,
			})
			self._rowMaid:Give(info.Row)
			table.insert(items, info.Item)
		end
	end

	table.insert(items, self._reset.Item)
	return items
end

-- keepTabFocus: sekme çubuğundan geçildiyse odak sekmede kalsın
function SettingsScreen:SelectCategory(index: number, keepTabFocus: boolean)
	index = math.clamp(index, 1, #self._categories)
	local changed = index ~= self._category or self._items == nil
	self._category = index
	self._tabs.SetSelected(index)
	if changed then
		self._items = self:_buildRows()
		self._scroller.CanvasPosition = Vector2.zero
		self.Focus:SetItems(self._items, if keepTabFocus then 1 else 2)
		if self._ctx.OnMove and keepTabFocus then
			self._ctx.OnMove()
		end
	end
end

function SettingsScreen:HandleTab(dir: number): boolean
	local index = self._category + dir
	if index >= 1 and index <= #self._categories then
		self:SelectCategory(index, self.Focus:GetIndex() == 1)
	end
	return true
end

function SettingsScreen:SetCompact(_compact: boolean) end

function SettingsScreen:OnShow()
	for _, refresh in self._refreshers do
		refresh()
	end
	self.Focus:Refresh()
end

function SettingsScreen:OnHide() end

return SettingsScreen
