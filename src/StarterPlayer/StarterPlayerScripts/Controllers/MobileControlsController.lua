-- MobileControlsController: dokunmatik cihazlar için ÖZEL buton katmanı (Bölüm 21).
-- Aşama 1 içeriği: Depar (toggle) ve Kamera modu butonları.
-- Joystick ve zıplama butonu Roblox'un kendi dokunmatik kontrolleridir (avatarla uyumlu,
-- erişilebilirlik ayarlarını korur). Bizim butonlar zıplama butonunun SOLUNA ve ÜSTÜNE dizilir,
-- hiçbiri onunla çakışmaz. Araç/motosiklet düzenleri Aşama 3'te bu modüle eklenecek.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UIConfig = require(Modules.UIConfig)
local Log = require(Shared.Utilities.Log).new("MobileControls")

local MobileControlsController = {
	Name = "MobileControlsController",
	Priority = 8,
}

local player = Players.LocalPlayer
local controllers
local screenGui: ScreenGui? = nil
local buttons: { [string]: TextButton } = {}
local layoutName = "OnFoot"
local holdInputs: { [InputObject]: string } = {}

-- Araç düzeni butonları: { isim, etiket, eylem, basılı-tut?, hangi düzenlerde görünür }
-- Sol alt köşe Aşama 9'daki minimap için boş bırakılır → direksiyon butonları ekranın sol ortasında.
local VEHICLE_BUTTONS = {
	{ "SteerL", "◀", "VehLeft", true, { Car = true, Motorcycle = true } },
	{ "SteerR", "▶", "VehRight", true, { Car = true, Motorcycle = true } },
	{ "Gas", "GAZ", "VehGas", true, { Car = true, Motorcycle = true } },
	{ "Brake", "FREN", "VehBrake", true, { Car = true, Motorcycle = true } },
	{ "Handbrake", "EL FRENİ", "VehHandbrake", true, { Car = true } },
	{ "Horn", "KORNA", "VehHorn", true, { Car = true, Motorcycle = true } },
	{ "Exit", "İN", "VehExit", false, { Car = true, Motorcycle = true, Passenger = true } },
	{ "Lights", "FAR", "VehLights", false, { Car = true, Motorcycle = true } },
	{ "Flip", "ÇEVİR", "VehFlip", false, { Car = true } },
}
local vehicleButtons: { [string]: TextButton } = {}

local CAMERA_LABELS = {
	ThirdPerson = "OMUZ",
	ThirdPersonAlt = "TAKİP",
	FirstPerson = "GÖZ",
}

-- Roblox zıplama butonunun kapladığı alan (TouchGui'deki resmi yerleşimle aynı mantık)
local function getJumpButtonRect(viewport: Vector2): (number, number, number)
	local minAxis = math.min(viewport.X, viewport.Y)
	if minAxis <= 500 then
		return 70, 25, 20 -- boyut, sağ boşluk, alt boşluk
	end
	return 120, 50, 90
end

local function getButtonSize(viewport: Vector2): number
	local m = UIConfig.Mobile
	local minAxis = math.min(viewport.X, viewport.Y)
	-- Oyuncu tercihi (Ayarlar → Kontroller → Mobil buton boyutu): 0.85 / 1 / 1.2
	local userScale = controllers and controllers.SettingsController and controllers.SettingsController:Get("MobileButtonScale") or 1
	local base = math.clamp(math.floor(minAxis * m.ButtonSizeScale), m.ButtonMinPx, m.ButtonMaxPx)
	return math.floor(base * userScale)
end

local function makeButton(name: string, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.Text = text
	button.TextScaled = true
	button.FontFace = UIConfig.Fonts.Title
	button.TextColor3 = UIConfig.Colors.Text
	button.BackgroundColor3 = UIConfig.Colors.Background
	button.BackgroundTransparency = UIConfig.Mobile.BackgroundTransparency
	button.AnchorPoint = Vector2.new(1, 1)

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Thickness = 2
	stroke.Color = UIConfig.Colors.TextMuted
	stroke.Transparency = 0.3
	stroke.Parent = button

	local padding = Instance.new("UIPadding")
	local p = UDim.new(0.22, 0)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = p, p, p, p
	padding.Parent = button

	-- Basma geri bildirimi
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(button, UIConfig.Tween.Fast, { BackgroundTransparency = 0.1 }):Play()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(button, UIConfig.Tween.Normal, { BackgroundTransparency = UIConfig.Mobile.BackgroundTransparency }):Play()
		end
	end)
	return button
end

local function setActiveLook(button: TextButton, active: boolean)
	local stroke = button:FindFirstChild("Stroke") :: UIStroke?
	if stroke then
		stroke.Color = if active then UIConfig.Colors.Accent else UIConfig.Colors.TextMuted
		stroke.Thickness = if active then 3 else 2
	end
	button.TextColor3 = if active then UIConfig.Colors.Accent else UIConfig.Colors.Text
end

local function layout()
	if not screenGui then
		return
	end
	local viewport = workspace.CurrentCamera.ViewportSize
	local size = getButtonSize(viewport)
	local jumpSize, jumpRight, jumpBottom = getJumpButtonRect(viewport)
	local gap = UIConfig.Mobile.Spacing

	local sprint = buttons.Sprint
	if sprint then
		sprint.Size = UDim2.fromOffset(size, size)
		-- Zıplamanın solunda, alt kenarları hizalı
		sprint.Position = UDim2.new(1, -(jumpRight + jumpSize + gap), 1, -jumpBottom)
	end
	local cam = buttons.Camera
	if cam then
		local small = math.floor(size * 0.8)
		cam.Size = UDim2.fromOffset(small, small)
		-- Zıplamanın üstünde
		cam.Position = UDim2.new(1, -jumpRight, 1, -(jumpBottom + jumpSize + gap))
	end

	-- Araç düzeni (Roblox joystick/zıplama araçtayken kapalıdır, bu yüzden tüm alan bizim)
	local margin = 24
	local big = math.floor(size * 1.35)
	local mid = math.floor(size * 1.1)
	local small = math.floor(size * 0.8)
	local function place(name: string, anchor: Vector2, position: UDim2, px: number)
		local b = vehicleButtons[name]
		if b then
			b.AnchorPoint = anchor
			b.Position = position
			b.Size = UDim2.fromOffset(px, px)
		end
	end
	place("SteerL", Vector2.new(0, 0.5), UDim2.new(0, margin, 0.55, 0), big)
	place("SteerR", Vector2.new(0, 0.5), UDim2.new(0, margin + big + gap, 0.55, 0), big)
	place("Gas", Vector2.new(1, 1), UDim2.new(1, -margin, 1, -margin), big)
	place("Brake", Vector2.new(1, 1), UDim2.new(1, -(margin + big + gap), 1, -margin), mid)
	place("Handbrake", Vector2.new(1, 1), UDim2.new(1, -(margin + big + gap), 1, -(margin + mid + gap)), mid)
	place("Horn", Vector2.new(1, 1), UDim2.new(1, -margin, 1, -(margin + big + gap)), small)
	place("Exit", Vector2.new(1, 0), UDim2.new(1, -margin, 0, 96), small)
	place("Lights", Vector2.new(1, 0), UDim2.new(1, -(margin + small + gap), 0, 96), small)
	place("Flip", Vector2.new(1, 0), UDim2.new(1, -(margin + (small + gap) * 2), 0, 96), small)
end

local function applyLayoutVisibility()
	if buttons.Sprint then
		buttons.Sprint.Visible = layoutName == "OnFoot"
	end
	if buttons.Camera then
		buttons.Camera.Visible = layoutName == "OnFoot"
	end
	for _, def in VEHICLE_BUTTONS do
		local b = vehicleButtons[def[1]]
		if b then
			b.Visible = def[5][layoutName] == true
		end
	end
end

local function build()
	if screenGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "MobileControls"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local sprint = makeButton("Sprint", "DEPAR")
	sprint.Activated:Connect(function()
		local input = controllers.InputController
		input:Trigger("Sprint", not input:IsActionActive("Sprint"))
	end)
	sprint.Parent = gui
	buttons.Sprint = sprint

	local cam = makeButton("Camera", CAMERA_LABELS[controllers.CameraController:GetMode()] or "KAMERA")
	cam.Activated:Connect(function()
		controllers.InputController:Trigger("CameraCycle", true)
		controllers.InputController:Trigger("CameraCycle", false)
	end)
	cam.Parent = gui
	buttons.Camera = cam

	for _, def in VEHICLE_BUTTONS do
		local name, label, action, hold = def[1], def[2], def[3], def[4]
		local b = makeButton(name, label)
		b.Visible = false
		if hold then
			b.InputBegan:Connect(function(io)
				if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
					holdInputs[io] = action
					controllers.InputController:Trigger(action, true)
					setActiveLook(b, true)
				end
			end)
		else
			b.Activated:Connect(function()
				controllers.InputController:Trigger(action, true)
				controllers.InputController:Trigger(action, false)
			end)
		end
		b.Parent = gui
		vehicleButtons[name] = b
	end
	-- Parmak butondan kayarak kalksa bile basılı eylem bırakılır
	UserInputService.InputEnded:Connect(function(io)
		local action = holdInputs[io]
		if action then
			holdInputs[io] = nil
			controllers.InputController:Trigger(action, false)
			for _, def in VEHICLE_BUTTONS do
				if def[3] == action and vehicleButtons[def[1]] then
					setActiveLook(vehicleButtons[def[1]], false)
				end
			end
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	screenGui = gui
	layout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	Log.Info("Mobil kontroller oluşturuldu")
end

local function refreshVisibility()
	local isTouch = controllers.InputController:IsTouch()
	if isTouch and not screenGui then
		build()
	end
	if screenGui then
		screenGui.Enabled = isTouch and layoutName ~= "Hidden"
		applyLayoutVisibility()
	end
end

-- "OnFoot" | "Car" | "Motorcycle" | "Passenger" | "Hidden" (diyalog, menü)
function MobileControlsController:SetLayout(name: string)
	layoutName = name
	-- düzen değişince basılı kalan araç eylemlerini bırak
	for io, action in holdInputs do
		holdInputs[io] = nil
		controllers.InputController:Trigger(action, false)
	end
	refreshVisibility()
end

function MobileControlsController:GetLayout(): string
	return layoutName
end

function MobileControlsController:Init(allControllers)
	controllers = allControllers
end

function MobileControlsController:Start()
	local input = controllers.InputController
	input.DeviceChanged:Connect(refreshVisibility)
	input.ActionBegan:Connect(function(action)
		if action == "Sprint" and buttons.Sprint then
			setActiveLook(buttons.Sprint, true)
		end
	end)
	input.ActionEnded:Connect(function(action)
		if action == "Sprint" and buttons.Sprint then
			setActiveLook(buttons.Sprint, false)
		end
	end)
	controllers.SettingsController.Changed:Connect(function(key)
		if key == "MobileButtonScale" then
			layout()
		end
	end)
	controllers.CameraController.ModeChanged:Connect(function(mode)
		if buttons.Camera and CAMERA_LABELS[mode] then
			buttons.Camera.Text = CAMERA_LABELS[mode]
		end
	end)
	-- Ölünce depar toggle'ı kapat
	controllers.CharacterController.CharacterChanged:Connect(function()
		if input:IsActionActive("Sprint") and input:IsTouch() then
			input:Trigger("Sprint", false)
		end
	end)
	refreshVisibility()
end

return MobileControlsController
