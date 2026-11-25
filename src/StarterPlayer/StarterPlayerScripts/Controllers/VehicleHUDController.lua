-- VehicleHUDController: hız göstergesi, vites, far/sinyal/el freni göstergeleri (Bölüm 8 / 21).
-- PC'de alt orta, dokunmatikte üst orta (alttaki butonlarla çakışmasın). 10 Hz güncellenir.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local VehicleDefinitions = require(Shared.VehicleDefinitions)
local UIConfig = require(Modules.UIConfig)

local VehicleHUDController = {
	Name = "VehicleHUDController",
	Priority = 9,
}

local player = Players.LocalPlayer
local controllers
local gui: ScreenGui
local panel: Frame
local speedLabel: TextLabel
local unitLabel: TextLabel
local gearLabel: TextLabel
local nameLabel: TextLabel
local icons: { [string]: TextLabel } = {}

local function makeLabel(parent: Instance, text: string, font: Font, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "VehicleHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Enabled = false

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(250, 92)
	panel.BackgroundColor3 = UIConfig.Colors.Background
	panel.BackgroundTransparency = 0.25
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = UIConfig.Colors.Accent
	stroke.Transparency = 0.5
	stroke.Thickness = 1.5
	stroke.Parent = panel
	panel.Parent = gui

	speedLabel = makeLabel(panel, "0", UIConfig.Fonts.Title, 44, UIConfig.Colors.Text)
	speedLabel.Size = UDim2.fromOffset(120, 50)
	speedLabel.Position = UDim2.fromOffset(14, 8)
	speedLabel.TextXAlignment = Enum.TextXAlignment.Right
	unitLabel = makeLabel(panel, "km/sa", UIConfig.Fonts.Body, 14, UIConfig.Colors.TextMuted)
	unitLabel.Size = UDim2.fromOffset(50, 20)
	unitLabel.Position = UDim2.fromOffset(138, 34)
	unitLabel.TextXAlignment = Enum.TextXAlignment.Left
	gearLabel = makeLabel(panel, "N", UIConfig.Fonts.Title, 30, UIConfig.Colors.Accent)
	gearLabel.Size = UDim2.fromOffset(44, 44)
	gearLabel.Position = UDim2.fromOffset(194, 10)
	nameLabel = makeLabel(panel, "", UIConfig.Fonts.Body, 13, UIConfig.Colors.TextMuted)
	nameLabel.Size = UDim2.fromOffset(230, 18)
	nameLabel.Position = UDim2.fromOffset(10, 66)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local iconDefs = { { "IndL", "◀" }, { "Lights", "FAR" }, { "Hand", "P" }, { "IndR", "▶" } }
	for i, d in iconDefs do
		local l = makeLabel(panel, d[2], UIConfig.Fonts.Title, 14, UIConfig.Colors.TextMuted)
		l.Size = UDim2.fromOffset(34, 18)
		l.Position = UDim2.fromOffset(100 + (i - 1) * 36, 66)
		l.TextTransparency = 0.6
		icons[d[1]] = l
	end
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function position()
	local touch = controllers.InputController:IsTouch()
	if touch then
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, 12)
	else
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Position = UDim2.new(0.5, 0, 1, -24)
	end
end

local function setIcon(name: string, on: boolean, color: Color3?)
	local l = icons[name]
	if l then
		l.TextTransparency = if on then 0 else 0.65
		l.TextColor3 = if on then (color or UIConfig.Colors.Accent) else UIConfig.Colors.TextMuted
	end
end

local function refresh(blink: boolean)
	local c = controllers.VehicleController:GetCurrent()
	if not c then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	local chassis = c.Chassis
	local speed = if chassis and chassis.Parent then chassis.AssemblyLinearVelocity.Magnitude else 0
	speedLabel.Text = tostring(math.floor(VehicleDefinitions.ToKmh(speed) + 0.5))
	gearLabel.Text = if c.IsDriver then c.Gear else "—"
	nameLabel.Text = c.Def.DisplayName .. (if c.IsDriver then "" else "  (yolcu)")
	local model = c.Model
	local indicator = model:GetAttribute("Indicator") or ""
	setIcon("IndL", blink and (indicator == "L" or indicator == "H"), Color3.fromRGB(255, 170, 40))
	setIcon("IndR", blink and (indicator == "R" or indicator == "H"), Color3.fromRGB(255, 170, 40))
	setIcon("Lights", model:GetAttribute("Lights") == true, Color3.fromRGB(120, 200, 255))
	setIcon("Hand", c.IsDriver and controllers.InputController:IsActionActive("VehHandbrake"), Color3.fromRGB(235, 87, 87))
end

function VehicleHUDController:Init(allControllers)
	controllers = allControllers
end

function VehicleHUDController:Start()
	build()
	position()
	controllers.InputController.DeviceChanged:Connect(position)
	controllers.VehicleController.Entered:Connect(function()
		position()
		refresh(true)
	end)
	controllers.VehicleController.Exited:Connect(function()
		gui.Enabled = false
	end)
	task.spawn(function()
		local tick = 0
		while true do
			task.wait(0.1)
			tick += 1
			if controllers.VehicleController:IsInVehicle() then
				pcall(refresh, (tick // 4) % 2 == 0)
			elseif gui.Enabled then
				gui.Enabled = false
			end
		end
	end)
end

return VehicleHUDController
