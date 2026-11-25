-- AudioController: istemci tarafı ses yönetimi (Bölüm 23).
-- Aşama 3: yakındaki araçların motor sesi perdesi hıza göre ayarlanır (yerel; ağ trafiği yok).
-- Ses kaynakları AudioConfig'tedir; ID verilmemişse araçlarda Sound nesnesi olmaz ve bu döngü boşa çalışmaz.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Modules.AudioConfig)
local VehicleDefinitions = require(Shared.VehicleDefinitions)

local AudioController = {
	Name = "AudioController",
	Priority = 10,
}

local HEAR_DISTANCE = 160

function AudioController:Init() end

function AudioController:Start()
	local cfg = AudioConfig.Vehicle
	task.spawn(function()
		while true do
			task.wait(0.15)
			local camera = workspace.CurrentCamera
			if not camera then
				continue
			end
			local listener = camera.CFrame.Position
			for _, model in CollectionService:GetTagged("Vehicle") do
				local chassis = model.PrimaryPart
				local engine = chassis and chassis:FindFirstChild("Engine")
				if engine and engine:IsA("Sound") and engine.IsPlaying and (chassis.Position - listener).Magnitude < HEAR_DISTANCE then
					local def = VehicleDefinitions.Get(model:GetAttribute("DefId"))
					local maxSpeed = if def then def.MaxSpeed else 100
					local t = math.clamp(chassis.AssemblyLinearVelocity.Magnitude / maxSpeed, 0, 1)
					engine.PlaybackSpeed = cfg.EngineBasePitch + (cfg.EngineMaxPitch - cfg.EngineBasePitch) * t
				end
			end
		end
	end)
end

return AudioController
