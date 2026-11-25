-- ClientBootstrap: istemcideki TEK giriş noktası.
-- Kontrolcü sözleşmesi sunucudakiyle aynı: Name, Priority, Init(controllers), Start().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Log = require(Shared.Utilities.Log).new("ClientBootstrap")
local RemoteRegistry = require(Shared.RemoteRegistry)

local controllersFolder = script.Parent:WaitForChild("Controllers")
local controllers = {}
local ordered = {}

for _, moduleScript in controllersFolder:GetChildren() do
	if moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript)
		if ok and type(result) == "table" then
			controllers[result.Name or moduleScript.Name] = result
			table.insert(ordered, result)
		else
			Log.Error("Kontrolcü yüklenemedi:", moduleScript.Name, result)
		end
	end
end

table.sort(ordered, function(a, b)
	return (a.Priority or 100) < (b.Priority or 100)
end)

for _, controller in ordered do
	if type(controller.Init) == "function" then
		local ok, err = pcall(controller.Init, controller, controllers)
		if not ok then
			Log.Error("Init hatası:", controller.Name, err)
			controller._failed = true
		end
	end
end

for _, controller in ordered do
	if not controller._failed and type(controller.Start) == "function" then
		local ok, err = pcall(controller.Start, controller)
		if not ok then
			Log.Error("Start hatası:", controller.Name, err)
		end
	end
end

-- Sunucuya hazır olduğumuzu bildir
local sessionInfo = RemoteRegistry.Get("PlayerRemotes", "SessionInfo") :: RemoteEvent
sessionInfo.OnClientEvent:Connect(function(info)
	if type(info) == "table" then
		Log.Info("Oturum:", info.GameMode, "sürüm", info.Version)
		if controllers.DebugHUDController then
			controllers.DebugHUDController:SetSessionInfo(info)
		end
	end
end)

local clientReady = RemoteRegistry.Get("PlayerRemotes", "ClientReady") :: RemoteEvent
local device = controllers.InputController and controllers.InputController:GetDeviceType() or "Unknown"
clientReady:FireServer(device)
Log.Info("İstemci hazır. Cihaz:", device)
