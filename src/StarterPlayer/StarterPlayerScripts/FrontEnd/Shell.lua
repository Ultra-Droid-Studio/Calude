-- Shell: ön yüzün TEK ScreenGui'si ve kalıcı katmanları.
--
--   SolaraFrontEnd (ScreenGui, ResetOnSpawn = false, ScreenInsets = None)
--     Backdrop      arka plan (yedek sahne + vignette)            — sadece menü açıkken görünür
--     Safe          Roblox üst çubuğu/çentik dışındaki alan          — sadece menü açıkken görünür
--       Canvas      UIScale ile ölçeklenen tasarım tuvali (ekranlar + alt bilgi)
--     MenuButton    dokunmatik ☰ (oyun içi menü)                    — küçük, tek başına
--     Toast         kısa bildirim                                   — Active değil
--     Veil          geçiş perdesi                                   — saydamken gizli
--
-- Menü kapalıyken ekranı kaplayan hiçbir çerçeve görünür değildir; böylece oyunun dokunmatik
-- kamera sürüklemesi ve butonları etkilenmez.

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontEndConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FrontEndConfig"))
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)
local Strings = require(script.Parent.Strings)
local Fader = require(script.Parent.Fader)
local Backdrop = require(script.Parent.Backdrop)

local C = Theme.Colors
local new = Widgets.new

local Shell = {}
Shell.__index = Shell

local GUI_NAME = "SolaraFrontEnd"

-- opts: OnPauseButton () -> (), OnLayout (compact: boolean) -> ()
function Shell.new(opts)
	local self = setmetatable({}, Shell)
	self._opts = opts
	self.Compact = false
	self._veilToken = 0
	self._toastToken = 0

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing then
		existing:Destroy() -- olası eski kopya; ikinci bir ScreenGui asla tutulmaz
	end

	self.Gui = new("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ScreenInsets = Enum.ScreenInsets.None,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = FrontEndConfig.DisplayOrder,
		AutoLocalize = false,
	})

	self.Backdrop = Backdrop.new(self.Gui)

	self.Safe = new("Frame", {
		Name = "Safe",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = self.Gui,
	})
	self.Canvas = new("Frame", {
		Name = "Canvas",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = self.Safe,
	})
	self.Scale = new("UIScale", { Parent = self.Canvas })

	-- Alt bilgi: sürüm (sol) + tuş ipuçları (sağ)
	self.Footer = new("Frame", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -18),
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 3,
		Parent = self.Canvas,
	}, { Widgets.Padding(32, 32, 0, 0) })
	self._version = Widgets.Label({
		Name = "Version",
		FontFace = Theme.Fonts.Light,
		TextSize = Theme.Text.Tiny,
		TextColor3 = C.TextDim,
		Size = UDim2.new(0.4, 0, 1, 0),
		Parent = self.Footer,
	})
	self._hints = new("Frame", {
		Name = "Hints",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.6, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = self.Footer,
	}, { Widgets.List(18, true, Enum.HorizontalAlignment.Right) })

	-- Bildirim (ölçek elle; Safe gizliyken de görünmeli)
	self._toast = new("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 40),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 5,
		Parent = self.Gui,
	}, { Widgets.Round(), Widgets.Stroke(C.Accent, 0.5), Widgets.Padding(20, 20, 0, 0) })
	self._toastLabel = Widgets.Label({
		FontFace = Theme.Fonts.Body,
		TextSize = Theme.Text.Small + 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromScale(0, 1),
		Parent = self._toast,
	})

	-- Dokunmatik ☰: oyun içinde menüyü açar
	self.PauseButton = Widgets.HitButton({
		Name = "MenuButton",
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 3,
		Parent = self.Gui,
	})
	self._pauseScale = new("UIScale", { Parent = self.PauseButton })
	Widgets.Round().Parent = self.PauseButton
	Widgets.Stroke(C.White, 0.7).Parent = self.PauseButton
	for i = -1, 1 do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, i * 7),
			Size = UDim2.fromOffset(18, 2),
			BackgroundColor3 = C.Text,
			BorderSizePixel = 0,
			Parent = self.PauseButton,
		}, { Widgets.Corner(1) })
	end
	self.PauseButton.Activated:Connect(function()
		opts.OnPauseButton()
	end)

	-- Perde: başlangıçta opak (menü kurulurken boş dünya görünmesin)
	self._veil = new("Frame", {
		Name = "Veil",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 20,
		Parent = self.Gui,
	})

	self.Gui.Parent = playerGui
	self:UpdateLayout()
	self.Safe:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:UpdateLayout()
	end)
	pcall(function()
		GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
			self:UpdateLayout()
		end)
	end)
	return self
end

function Shell:GetScale(): number
	return self.Scale.Scale
end

-- Güvenli alan + tasarım ölçeği. Masaüstü tasarımı 1280×720, kompakt (telefon) 900×500.
function Shell:UpdateLayout()
	local topLeft, bottomRight = GuiService:GetGuiInset()
	self.Safe.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
	self.Safe.Size = UDim2.new(1, -(topLeft.X + bottomRight.X), 1, -(topLeft.Y + bottomRight.Y))
	local size = self.Safe.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local compact = size.Y < 560 or size.X < 900
	local s = if compact then math.min(size.X / 900, size.Y / 500) else math.min(size.X / 1280, size.Y / 720)
	s = math.clamp(s, 0.5, 1.6)
	self.Scale.Scale = s
	self.Canvas.Size = UDim2.fromScale(1 / s, 1 / s)
	self.PauseButton.Position = UDim2.fromOffset(topLeft.X + math.floor(16 * s), topLeft.Y + math.floor(10 * s))
	self._pauseScale.Scale = s
	self._toast.Position = UDim2.new(0.5, 0, 1, -(bottomRight.Y + math.floor(90 * s)))
	self._toast.Size = UDim2.fromOffset(0, math.floor(40 * s))
	self._toastLabel.TextSize = math.max(12, math.floor((Theme.Text.Small + 1) * s))
	if compact ~= self.Compact then
		self.Compact = compact
	end
	self._opts.OnLayout(compact)
end

-- Menü katmanlarını göster/gizle (Safe gizliyken tam ekran çerçeve kalmaz)
function Shell:SetMenuShown(shown: boolean, seconds: number)
	self._menuShown = shown
	if shown then
		self.Safe.Visible = true
		Fader.Fade(self.Backdrop.Root, true, seconds, 0)
		Fader.Fade(self.Footer, true, seconds, 0)
	else
		Fader.Fade(self.Footer, false, seconds, 0)
		Fader.Fade(self.Backdrop.Root, false, seconds, 0)
		task.delay(seconds, function()
			if not self._menuShown then
				self.Safe.Visible = false
			end
		end)
	end
end

-- Perde: geçişlerde ekranı karartır; tamamen saydamken gizlenir
function Shell:SetVeil(opaque: boolean, seconds: number)
	self._veilToken += 1
	local token = self._veilToken
	self._veil.Visible = true
	Fader.Tween(self._veil, { BackgroundTransparency = if opaque then 0 else 1 }, seconds)
	if not opaque then
		task.delay(seconds, function()
			if token == self._veilToken then
				self._veil.Visible = false
			end
		end)
	end
end

function Shell:Toast(text: string, fadeSeconds: number)
	self._toastToken += 1
	local token = self._toastToken
	self._toastLabel.Text = text
	Fader.Fade(self._toast, true, fadeSeconds, 0)
	task.delay(2.6, function()
		if token == self._toastToken then
			Fader.Fade(self._toast, false, fadeSeconds, 0)
		end
	end)
end

function Shell:SetVersion(text: string)
	self._version.Text = text
end

function Shell:SetPauseButtonVisible(visible: boolean)
	self.PauseButton.Visible = visible
end

-- device: "KeyboardMouse" | "Gamepad" | "Touch"; screen: "Main" | "Settings" | "Garage"
function Shell:SetHints(device: string, screen: string?, paused: boolean)
	for _, child in self._hints:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if device == "Touch" or screen == nil then
		return
	end
	local pad = device == "Gamepad"
	local order = 0
	local function hint(key: string, labelKey: string)
		order += 1
		Widgets.KeyHint(self._hints, key, Strings.Get(labelKey), order, pad and #key == 1)
	end
	if screen == "Settings" then
		hint(if pad then "LB RB" else "Q E", "Hint.Tabs")
		hint(if pad then "D-Pad" else "A D", "Hint.Adjust")
	end
	hint(if pad then "A" else "Enter", "Hint.Select")
	if screen ~= "Main" then
		hint(if pad then "B" else "Backspace", "Hint.Back")
	elseif paused then
		hint(if pad then "B" else "P", "Hint.Close")
	end
end

return Shell
