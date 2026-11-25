-- UIConfig: ortak görsel dil. Varsayılan Roblox görünümünden kaçınmak için (Bölüm 18.3 / 21).

local UIConfig = {}

UIConfig.Colors = {
	Background = Color3.fromRGB(14, 16, 22),
	Surface = Color3.fromRGB(26, 29, 38),
	Accent = Color3.fromRGB(255, 122, 69), -- gün batımı turuncusu (oyunun kimlik rengi)
	AccentAlt = Color3.fromRGB(64, 196, 214), -- sahil turkuazı
	Text = Color3.fromRGB(240, 242, 247),
	TextMuted = Color3.fromRGB(150, 156, 170),
	Danger = Color3.fromRGB(235, 87, 87),
}

UIConfig.Fonts = {
	Title = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
	Body = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Regular),
}

UIConfig.Mobile = {
	-- Butonlar ekran kısa kenarına oranla boyutlanır → farklı ekranlarda aynı his
	ButtonSizeScale = 0.13, -- kısa kenarın oranı
	ButtonMinPx = 56,
	ButtonMaxPx = 96,
	Spacing = 12,
	BackgroundTransparency = 0.35,
	-- Sağ alt köşede Roblox'un zıplama butonu bulunur; bizim butonlar onun ÜSTÜNE ve SOLUNA dizilir.
	-- Sol alt köşe: joystick. (Minimap Aşama 9'da joystick'in ÜSTÜNE yerleşecek.)
}

UIConfig.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

return UIConfig
