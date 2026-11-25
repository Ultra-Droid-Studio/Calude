-- DebugHUDController: Aşama testleri için küçük bilgi paneli (sağ üst).
-- Her kare DEĞİL, 0.25 sn'de bir güncellenir (Bölüm 27.4). F3 ile açılır/kapanır.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Shared.Config)
local MapDefinitions = require(Shared.MapDefinitions)
local Lighting = game:GetService("Lighting")
local UIConfig = require(Modules.UIConfig)

local DebugHUDController = {
	Name = "DebugHUDController",
	Priority = 9,
}

local player = Players.LocalPlayer
local controllers
local gui: ScreenGui
local label: TextLabel
local sessionInfo = { GameMode = "?", Version = Config.Version }
local frameTimes = {}

function DebugHUDController:SetSessionInfo(info)
	sessionInfo = info
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "DebugHUD"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Enabled = RunService:IsStudio() and Config.Debug.ShowDebugHUDInStudio

	label = Instance.new("TextLabel")
	label.Name = "Info"
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.new(1, -10, 0, 10)
	label.Size = UDim2.fromOffset(270, 196)
	label.BackgroundColor3 = UIConfig.Colors.Background
	label.BackgroundTransparency = 0.35
	label.TextColor3 = UIConfig.Colors.Text
	label.FontFace = UIConfig.Fonts.Mono
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = label
	label.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function refresh()
	if not gui.Enabled then
		return
	end
	local sum = 0
	for _, t in frameTimes do
		sum += t
	end
	local fps = if #frameTimes > 0 and sum > 0 then #frameTimes / sum else 0
	table.clear(frameTimes)

	local cc = controllers.CharacterController
	local root = cc:GetRootPart()
	local speed = if root then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude else 0
	local pos = if root then root.Position else Vector3.zero
	local ping = math.floor(player:GetNetworkPing() * 2000) -- gidiş-dönüş ms

	label.Text = table.concat({
		string.format("%s  %s  [%s]", Config.GameName, sessionInfo.Version or "?", sessionInfo.GameMode or "?"),
		string.format("FPS %d   Ping %d ms   Bellek %d MB", math.floor(fps + 0.5), ping, math.floor(Stats:GetTotalMemoryUsageMb())),
		string.format("Cihaz: %s", controllers.InputController:GetDeviceType()),
		string.format("Kamera: %s", controllers.CameraController:GetMode()),
		string.format("Rig: %s   Göz: %.2f", cc:GetRigType(), cc:GetEyeHeight()),
		string.format("Hareket: %s   Hız: %.1f", cc:GetMovementState(), speed),
		string.format("Konum: %d, %d, %d", math.floor(pos.X), math.floor(pos.Y), math.floor(pos.Z)),
		string.format("Bölge: %s", (function()
			local d = MapDefinitions.GetDistrictAt(pos)
			return if d then d.Name else "—"
		end)()),
		string.format("Saat: %02d:%02d   Dünya: %s", math.floor(Lighting.ClockTime), math.floor((Lighting.ClockTime % 1) * 60),
			(function()
				local world = workspace:FindFirstChild("World")
				if not world then
					return "?"
				end
				if world:GetAttribute("Baked") then
					return "pişmiş"
				end
				local progress = world:GetAttribute("BuildProgress") or 0
				return if world:GetAttribute("WorldReady") then string.format("%d parça", world:GetAttribute("PartCount") or 0)
					else string.format("inşa %%%d", math.floor(progress * 100))
			end)()),
	}, "\n")
end

function DebugHUDController:Init(allControllers)
	controllers = allControllers
end

function DebugHUDController:Start()
	build()
	controllers.InputController.ActionBegan:Connect(function(action)
		if action == "ToggleDebug" then
			gui.Enabled = not gui.Enabled
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if gui.Enabled and #frameTimes < 240 then
			table.insert(frameTimes, dt)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			pcall(refresh)
		end
	end)
end

return DebugHUDController
