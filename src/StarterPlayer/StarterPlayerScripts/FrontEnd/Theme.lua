-- Theme: ana menü görsel dili (UIConfig'in kimlik renkleri üzerine kurulu).
-- Tasarım ölçüleri "tasarım pikseli"dir; FrontEndController ekran boyutuna göre UIScale uygular.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))

local rgb = Color3.fromRGB
local GOTHAM = "rbxasset://fonts/families/GothamSSm.json"

local Theme = {}

Theme.Colors = {
	Background = UIConfig.Colors.Background,
	Panel = rgb(12, 14, 20),
	Surface = UIConfig.Colors.Surface,
	SurfaceHigh = rgb(40, 44, 58),
	Text = UIConfig.Colors.Text,
	TextMuted = UIConfig.Colors.TextMuted,
	TextDim = rgb(104, 110, 126),
	Accent = UIConfig.Colors.Accent, -- gün batımı turuncusu
	AccentHot = rgb(242, 72, 120), -- mercan pembesi
	AccentAlt = UIConfig.Colors.AccentAlt, -- sahil turkuazı
	SunTop = rgb(255, 214, 110),
	Danger = UIConfig.Colors.Danger,
	Success = rgb(110, 210, 150),
	-- yedek arka plan (şehir henüz hazır değilken)
	SkyTop = rgb(16, 14, 36),
	SkyMid = rgb(74, 34, 92),
	SkyLow = rgb(232, 112, 86),
	Sea = rgb(14, 24, 44),
	Skyline = rgb(20, 18, 38),
	White = rgb(255, 255, 255),
	Black = rgb(0, 0, 0),
}

Theme.Fonts = {
	Display = Font.new(GOTHAM, Enum.FontWeight.Heavy),
	Title = Font.new(GOTHAM, Enum.FontWeight.Bold),
	Body = Font.new(GOTHAM, Enum.FontWeight.Medium),
	Light = Font.new(GOTHAM, Enum.FontWeight.Regular),
	Mono = UIConfig.Fonts.Mono,
}

Theme.Text = {
	Logo = 76,
	Heading = 30,
	MainButton = 24,
	Body = 18,
	Small = 14,
	Tiny = 12,
}

Theme.Size = {
	Gap = 10,
	Pad = 24,
	Radius = 10,
	MainButton = 64,
	Row = 64,
	Tab = 44,
	ColumnWidth = 440,
}

-- Saydamlık (0 = opak)
Theme.Alpha = {
	Panel = 0.22,
	PanelSoft = 0.4,
	Row = 1,
	RowFocus = 0.45,
	Stroke = 0.82,
	StrokeFocus = 0.1,
}

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

Theme.AccentGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Colors.Accent),
	ColorSequenceKeypoint.new(1, Theme.Colors.AccentHot),
})

Theme.SunGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Colors.SunTop),
	ColorSequenceKeypoint.new(0.55, Theme.Colors.Accent),
	ColorSequenceKeypoint.new(1, Theme.Colors.AccentHot),
})

Theme.WordmarkGradient = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(255, 255, 255)),
	ColorSequenceKeypoint.new(0.6, rgb(255, 236, 220)),
	ColorSequenceKeypoint.new(1, rgb(255, 196, 170)),
})

return Theme
