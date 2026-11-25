-- Backdrop: menünün arka plan katmanı.
--   * Vignette: metnin okunması için soldan ve alttan koyulaşan geçişler (her zaman, menü açıkken).
--   * Fallback: şehir henüz hazır/akmış değilken gösterilen hafif, varlıksız gün batımı sahnesi
--     (gökyüzü geçişi, çizgili güneş, deniz yansıması, silüet). ~60 düz Frame; doku/görüntü yok.

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Fader = require(script.Parent.Fader)

local C = Theme.Colors
local new = Widgets.new

local Backdrop = {}
Backdrop.__index = Backdrop

local HORIZON = 0.64

-- (x merkezi, genişlik, yükseklik) — ekran oranı cinsinden; deterministik silüet
local SKYLINE = {
	{ 0.05, 0.045, 0.07 }, { 0.09, 0.03, 0.11 }, { 0.13, 0.05, 0.06 }, { 0.48, 0.03, 0.13 },
	{ 0.52, 0.026, 0.2 }, { 0.555, 0.034, 0.27 }, { 0.59, 0.024, 0.16 }, { 0.62, 0.04, 0.31 },
	{ 0.655, 0.028, 0.22 }, { 0.685, 0.036, 0.36 }, { 0.72, 0.03, 0.24 }, { 0.75, 0.042, 0.29 },
	{ 0.785, 0.026, 0.17 }, { 0.815, 0.034, 0.21 }, { 0.85, 0.05, 0.12 }, { 0.9, 0.04, 0.09 },
	{ 0.94, 0.05, 0.06 },
}

local function vertical(sequence: ColorSequence, transparency: NumberSequence?): UIGradient
	return new("UIGradient", { Color = sequence, Rotation = 90, Transparency = transparency or NumberSequence.new(0) })
end

local function buildFallback(parent: Instance): Frame
	local root = new("Frame", {
		Name = "Fallback",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.White,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		vertical(ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.SkyTop),
			ColorSequenceKeypoint.new(0.42, C.SkyMid),
			ColorSequenceKeypoint.new(HORIZON, C.SkyLow),
			ColorSequenceKeypoint.new(HORIZON + 0.001, C.Sea),
			ColorSequenceKeypoint.new(1, C.Background),
		})),
	})
	-- güneş: ufkun hemen üstünde, sağ yarıda (soldaki menü sütunundan uzak)
	local sunHolder = new("Frame", {
		Name = "SunHolder",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.68, HORIZON),
		Size = UDim2.fromScale(0.3, 0.3),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = root,
	}, { new("UIAspectRatioConstraint", { AspectRatio = 2, DominantAxis = Enum.DominantAxis.Width }) })
	local sun = Widgets.Sun(10, C.SkyLow)
	sun.AnchorPoint = Vector2.new(0.5, 0)
	sun.Position = UDim2.fromScale(0.5, 0.1)
	sun.Size = UDim2.fromScale(0.55, 1.1)
	new("UIAspectRatioConstraint", { AspectRatio = 1 }).Parent = sun
	sun.Parent = sunHolder
	-- ufuk parıltısı
	new("Frame", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.68, HORIZON),
		Size = UDim2.new(0.6, 0, 0, 3),
		BackgroundColor3 = C.SunTop,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	-- silüet
	local skyline = new("Frame", {
		Name = "Skyline",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, HORIZON),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundTransparency = 1,
		Parent = root,
	})
	for i, b in SKYLINE do
		local building = new("Frame", {
			Name = "B" .. i,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(b[1], 1),
			Size = UDim2.fromScale(b[2], b[3] / 0.4),
			BackgroundColor3 = C.Skyline,
			BorderSizePixel = 0,
			Parent = skyline,
		})
		if b[3] > 0.15 then
			-- birkaç yanan pencere şeridi
			for k = 1, 2 do
				new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0.18 + k * 0.22),
					Size = UDim2.new(0.5, 0, 0, 2),
					BackgroundColor3 = C.SunTop,
					BackgroundTransparency = 0.55,
					BorderSizePixel = 0,
					Parent = building,
				})
			end
		end
	end
	-- denizdeki güneş yansıması
	for i = 1, 6 do
		new("Frame", {
			Name = "Reflection" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.68, HORIZON + 0.025 * i),
			Size = UDim2.new(0.18 - i * 0.022, 0, 0, 3),
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = 0.35 + i * 0.09,
			BorderSizePixel = 0,
			Parent = root,
		}, { Widgets.Round() })
	end
	return root
end

local function buildVignette(parent: Instance): Frame
	local root = new("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local left = new("Frame", {
		Name = "Left",
		Size = UDim2.fromScale(0.62, 1),
		BackgroundColor3 = C.Black,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.22),
				NumberSequenceKeypoint.new(0.55, 0.62),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local bottom = new("Frame", {
		Name = "Bottom",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.22),
		BackgroundColor3 = C.Black,
		BorderSizePixel = 0,
		Parent = root,
	}, {
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.35),
			}),
		}),
	})
	-- Ayarlar/garaj panelleri için tüm ekranı hafif karartan katman (varsayılan kapalı)
	local dim = new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = root,
	})
	return root, left, bottom, dim
end

function Backdrop.new(parent: Instance)
	local self = setmetatable({}, Backdrop)
	self.Root = new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		-- Menü açıkken arka plana yapılan dokunuş/tıklamalar oyuna (kamera kaydırma) geçmesin
		Active = true,
		Parent = parent,
	})
	self.Fallback = buildFallback(self.Root)
	self.Vignette, self._left, self._bottom, self._dim = buildVignette(self.Root)
	self._fallbackShown = true
	return self
end

-- Şehir görünür hale gelince yedek sahne yumuşakça kaybolur (ve gerekirse geri gelir)
function Backdrop:SetFallbackVisible(visible: boolean, duration: number)
	if self._fallbackShown == visible then
		return
	end
	self._fallbackShown = visible
	Fader.Fade(self.Fallback, visible, duration, 0)
end

function Backdrop:IsFallbackVisible(): boolean
	return self._fallbackShown
end

-- "Title": koyu sol geçiş; "Paused": oyun görünür kalsın diye daha hafif; panel: arka plan karartılır
function Backdrop:SetStyle(style: string, panelOpen: boolean, duration: number)
	local paused = style == "Paused"
	Fader.Tween(self._left, { Size = UDim2.fromScale(if paused then 0.5 else 0.62, 1) }, duration)
	Fader.Tween(self._dim, { BackgroundTransparency = if panelOpen then 0.45 elseif paused then 0.72 else 1 }, duration)
end

return Backdrop
