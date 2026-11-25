-- PlayerService: oyuncu oturumlarının yaşam döngüsü ve oyun modu ayrımı.
-- Veri kalıcılığı (DataStore) Aşama 7'de DataService ile buraya bağlanacak.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local RemoteRegistry = require(Shared.RemoteRegistry)
local Signal = require(Shared.Utilities.Signal)
local RateLimiter = require(Shared.Utilities.RateLimiter)
local Log = require(Shared.Utilities.Log).new("PlayerService")

local PlayerService = {
	Name = "PlayerService",
	Priority = 5,
	SessionStarted = Signal.new(), -- (player, session)
	SessionEnded = Signal.new(), -- (player)
}

type Session = {
	Player: Player,
	JoinedAt: number,
	ClientReady: boolean,
	DeviceHint: string?,
}

local sessions: { [Player]: Session } = {}
local readyLimiter = RateLimiter.new(3, 0.2)
local serverGameMode = Config.Modes.Normal

local function resolveGameMode(): string
	if table.find(Config.SandboxPlaceIds, game.PlaceId) then
		return Config.Modes.Sandbox
	end
	-- Sadece Studio'da: Workspace'e "ForceGameMode" = "Sandbox" attribute'u ekleyerek test edebilirsin
	if RunService:IsStudio() then
		local forced = workspace:GetAttribute(Constants.Attributes.ForceGameMode)
		if forced == Config.Modes.Sandbox or forced == Config.Modes.Normal then
			return forced
		end
	end
	return Config.Modes.Normal
end

function PlayerService:GetGameMode(): string
	return serverGameMode
end

function PlayerService:GetSession(player: Player): Session?
	return sessions[player]
end

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	-- Avatar kuralı: oyuncunun gerçek görünümü yüklenmeli
	player.CanLoadCharacterAppearance = true

	local session: Session = {
		Player = player,
		JoinedAt = workspace:GetServerTimeNow(),
		ClientReady = false,
		DeviceHint = nil,
	}
	sessions[player] = session
	player:SetAttribute(Constants.Attributes.GameMode, serverGameMode)
	player:SetAttribute(Constants.Attributes.SessionReady, false)
	Log.Info("Katıldı:", player.Name, "mod:", serverGameMode)
	PlayerService.SessionStarted:Fire(player, session)
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	readyLimiter:Forget(player)
	Log.Info("Ayrıldı:", player.Name)
	PlayerService.SessionEnded:Fire(player)
end

function PlayerService:Init()
	serverGameMode = resolveGameMode()
	workspace:SetAttribute(Constants.Attributes.GameMode, serverGameMode)
end

function PlayerService:Start()
	local clientReady = RemoteRegistry.Get("PlayerRemotes", "ClientReady") :: RemoteEvent
	local sessionInfo = RemoteRegistry.Get("PlayerRemotes", "SessionInfo") :: RemoteEvent

	clientReady.OnServerEvent:Connect(function(player: Player, deviceHint: any)
		if not readyLimiter:Check(player) then
			return
		end
		local session = sessions[player]
		if not session then
			return
		end
		-- Gelen veri sadece bilgi amaçlı; yine de tipini ve uzunluğunu doğrula
		if type(deviceHint) == "string" and #deviceHint <= 24 then
			session.DeviceHint = deviceHint
		end
		if not session.ClientReady then
			session.ClientReady = true
			player:SetAttribute(Constants.Attributes.SessionReady, true)
		end
		sessionInfo:FireClient(player, {
			GameMode = serverGameMode,
			Version = Config.Version,
			ServerTime = workspace:GetServerTimeNow(),
		})
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Bootstrap'tan önce girmiş oyuncular (Studio'da sık olur)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerService
