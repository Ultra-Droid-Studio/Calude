-- MainScreen: logo + OYNA / GARAJ / AYARLAR + durum satırı + oyuncu kartı.
-- Ekran nesnesi sözleşmesi (FrontEndController kullanır):
--   Root: GuiObject, Focus: Focus, OnShow(), OnHide(), HandleTab(dir) -> boolean, SetCompact(bool)

local Players = game:GetService("Players")

local FrontEnd = script.Parent.Parent
local Theme = require(FrontEnd.Theme)
local Widgets = require(FrontEnd.Widgets)
local Strings = require(FrontEnd.Strings)
local Focus = require(FrontEnd.Focus)

local C = Theme.Colors
local new = Widgets.new

local MainScreen = {}
MainScreen.__index = MainScreen

-- ctx: Parent, GetScale, OnMove, Actions = { Play, Garage, Settings }
function MainScreen.new(ctx)
	local self = setmetatable({}, MainScreen)
	self.Focus = Focus.new(ctx.GetScale, ctx.OnMove)
	local hover = function(item)
		self.Focus:Hover(item)
	end

	self.Root = new("Frame", {
		Name = "MainScreen",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = ctx.Parent,
	})

	-- ===== Sol sütun =====
	local column = new("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 80, 0.5, 0),
		Size = UDim2.fromOffset(Theme.Size.ColumnWidth, 420),
		BackgroundTransparency = 1,
		Parent = self.Root,
	})
	self._column = column

	-- Logo: çizgili güneş + SOLARA yazısı + alt başlık
	local logo = new("Frame", {
		Name = "Logo",
		Size = UDim2.new(1, 0, 0, 124),
		BackgroundTransparency = 1,
		Parent = column,
	})
	local sun = Widgets.Sun(64, C.Panel)
	sun.Position = UDim2.fromOffset(0, 10)
	sun.Parent = logo
	local wordmark = Widgets.Label({
		Name = "Wordmark",
		Text = "SOLARA",
		FontFace = Theme.Fonts.Display,
		TextSize = Theme.Text.Logo,
		Position = UDim2.fromOffset(80, -2),
		Size = UDim2.new(1, -80, 0, 84),
		Parent = logo,
	})
	Widgets.Gradient(Theme.WordmarkGradient, 90).Parent = wordmark
	local subtitleRow = new("Frame", {
		Name = "SubtitleRow",
		Position = UDim2.fromOffset(84, 84),
		Size = UDim2.new(1, -84, 0, 20),
		BackgroundTransparency = 1,
		Parent = logo,
	})
	new("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(28, 2),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = subtitleRow,
	}, { Widgets.Gradient(Theme.AccentGradient, 0) })
	Widgets.Label({
		Text = Strings.Get("Main.Subtitle"),
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -38, 1, 0),
		Parent = subtitleRow,
	})

	-- Butonlar
	local list = new("Frame", {
		Name = "Buttons",
		Position = UDim2.fromOffset(0, 150),
		Size = UDim2.new(1, 0, 0, 3 * Theme.Size.MainButton + 16),
		BackgroundTransparency = 1,
		Parent = column,
	}, { Widgets.List(8) })
	self._play = Widgets.MenuButton(list, {
		Index = "01",
		Text = Strings.Get("Main.Play"),
		Sub = Strings.Get("Main.Play.Sub"),
		Primary = true,
		LayoutOrder = 1,
		OnActivate = ctx.Actions.Play,
		OnHover = hover,
	})
	self._garage = Widgets.MenuButton(list, {
		Index = "02",
		Text = Strings.Get("Main.Garage"),
		Sub = Strings.Get("Main.Garage.Sub"),
		LayoutOrder = 2,
		OnActivate = ctx.Actions.Garage,
		OnHover = hover,
	})
	self._settings = Widgets.MenuButton(list, {
		Index = "03",
		Text = Strings.Get("Main.Settings"),
		Sub = Strings.Get("Main.Settings.Sub"),
		LayoutOrder = 3,
		OnActivate = ctx.Actions.Settings,
		OnHover = hover,
	})

	-- Durum satırı (şehir hazır mı / bağlanılıyor / hata)
	local status = new("Frame", {
		Name = "Status",
		Position = UDim2.fromOffset(20, 150 + 3 * Theme.Size.MainButton + 16 + 22),
		Size = UDim2.new(1, -20, 0, 20),
		BackgroundTransparency = 1,
		Parent = column,
	})
	self._statusDot = new("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.TextMuted,
		BorderSizePixel = 0,
		Parent = status,
	}, { Widgets.Round() })
	self._statusText = Widgets.Label({
		Name = "Text",
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.Text.Small,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Parent = status,
	})

	-- ===== Oyuncu kartı (sağ üst) =====
	local player = Players.LocalPlayer
	local card = new("Frame", {
		Name = "PlayerCard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -32, 0, 20),
		Size = UDim2.fromOffset(260, 48),
		BackgroundTransparency = 1,
		Parent = self.Root,
	})
	local avatar = new("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.SurfaceHigh,
		BackgroundTransparency = 0.3,
		Image = "",
		Parent = card,
	}, { Widgets.Round(), Widgets.Stroke(C.White, 0.7, 1.5) })
	Widgets.Label({
		Name = "DisplayName",
		Text = player.DisplayName,
		FontFace = Theme.Fonts.Title,
		TextSize = Theme.Text.Body - 2,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.new(1, -56, 0, 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	Widgets.Label({
		Name = "UserName",
		Text = "@" .. player.Name,
		FontFace = Theme.Fonts.Light,
		TextSize = Theme.Text.Tiny + 1,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 25),
		Size = UDim2.new(1, -56, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and image and avatar.Parent then
			avatar.Image = image
		end
	end)

	self._items = { self._play.Item, self._garage.Item, self._settings.Item }
	self.Focus:SetItems(self._items, 1)
	return self
end

-- "Title" (henüz oyunda değil) | "Paused" (oyun içi menü)
function MainScreen:SetMode(mode: string)
	if mode == "Paused" then
		self._play.SetText(Strings.Get("Main.Resume"), Strings.Get("Main.Resume.Sub"))
	else
		self._play.SetText(Strings.Get("Main.Play"), Strings.Get("Main.Play.Sub"))
	end
end

function MainScreen:SetBusy(busy: boolean)
	self._play.SetBusy(busy)
end

-- kind: "ok" | "busy" | "error" | "info"
function MainScreen:SetStatus(text: string, kind: string)
	self._statusKind = kind
	self._statusText.Text = text
	local color = if kind == "ok" then C.Success elseif kind == "error" then C.Danger elseif kind == "busy" then C.Accent else C.TextMuted
	self._statusDot.BackgroundColor3 = color
	self._statusText.TextColor3 = if kind == "error" then C.Danger else C.TextMuted
end

-- Hata mesajı, oyuncu tekrar OYNA'ya basana kadar şehir durumu tarafından ezilmesin
function MainScreen:IsShowingError(): boolean
	return self._statusKind == "error"
end

function MainScreen:SetCompact(compact: boolean)
	self._column.Position = UDim2.new(0, if compact then 36 else 80, 0.5, 0)
end

function MainScreen:OnShow()
	self.Focus:Select(1, true)
	self.Focus:Refresh()
end

function MainScreen:OnHide() end

function MainScreen:HandleTab(_dir: number): boolean
	return false
end

return MainScreen
