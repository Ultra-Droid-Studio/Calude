-- MovementValidationService: sunucu tarafı temel hız doğrulaması (Bölüm 26).
-- Karakter fiziği istemcide çalıştığı için hız hilesi mümkündür; burada yakalanır.
-- Aşama 1 politikası: SADECE KAYIT (log). Ceza/geri çekme Aşama 12'de, gerçek testlerden
-- sonra eşikler kalibre edilince açılacak (meşru oyuncuları yanlışlıkla cezalandırmamak için).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Log = require(Shared.Utilities.Log).new("MovementValidation")

local MovementValidationService = {
	Name = "MovementValidationService",
	Priority = 40,
	Policy = "LogOnly", -- "LogOnly" | "Rubberband" (ileride)
}

local SAMPLE_INTERVAL = 0.5
local FLAG_WINDOW = 10 -- sn
local FLAG_THRESHOLD = 4 -- bu pencerede bu kadar ihlal → uyarı

type Sample = {
	Character: Model?,
	Position: Vector3?,
	Time: number,
	Flags: { number },
}

local samples: { [Player]: Sample } = {}

local function maxAllowedSpeed(): number
	local m = Config.Movement
	return m.SprintSpeed * m.ValidationSpeedMultiplier + m.ValidationTolerance
end

local function shouldSkip(character: Model, humanoid: Humanoid): boolean
	if humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return true -- araçtaki hız araç sistemi tarafından ayrıca doğrulanacak (Aşama 3)
	end
	local spawnedAt = character:GetAttribute(Constants.Attributes.SpawnedAt)
	if type(spawnedAt) ~= "number" then
		return true
	end
	if workspace:GetServerTimeNow() - spawnedAt < Config.Spawn.TeleportGraceSeconds then
		return true
	end
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.Physics then
		return true
	end
	-- Sunucu kendisi ışınladıysa bu attribute set edilir (ileride: GPS hızlı seyahat vb.)
	if character:GetAttribute("ServerTeleportAt") then
		local t = character:GetAttribute("ServerTeleportAt")
		if type(t) == "number" and workspace:GetServerTimeNow() - t < Config.Spawn.TeleportGraceSeconds then
			return true
		end
	end
	return false
end

local function check(player: Player, sample: Sample, now: number)
	local character = player.Character
	if not character then
		sample.Character = nil
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return
	end
	local position = root.Position
	if sample.Character ~= character or sample.Position == nil or shouldSkip(character, humanoid) then
		sample.Character = character
		sample.Position = position
		sample.Time = now
		return
	end

	local elapsed = now - sample.Time
	if elapsed <= 0 then
		return
	end
	local delta = position - sample.Position
	local horizontalSpeed = Vector3.new(delta.X, 0, delta.Z).Magnitude / elapsed
	sample.Position = position
	sample.Time = now

	if horizontalSpeed > maxAllowedSpeed() then
		table.insert(sample.Flags, now)
		-- Pencere dışındaki eski kayıtları at
		while #sample.Flags > 0 and now - sample.Flags[1] > FLAG_WINDOW do
			table.remove(sample.Flags, 1)
		end
		if #sample.Flags >= FLAG_THRESHOLD then
			Log.Warn(string.format("Şüpheli hız: %s %.1f stud/sn (izin %.1f), %d ihlal/%ds",
				player.Name, horizontalSpeed, maxAllowedSpeed(), #sample.Flags, FLAG_WINDOW))
			table.clear(sample.Flags)
		end
	end
end

function MovementValidationService:Init() end

function MovementValidationService:Start()
	Players.PlayerAdded:Connect(function(player)
		samples[player] = { Time = 0, Flags = {} }
	end)
	Players.PlayerRemoving:Connect(function(player)
		samples[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		samples[player] = { Time = 0, Flags = {} }
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < SAMPLE_INTERVAL then
			return
		end
		accumulator = 0
		local now = os.clock()
		for player, sample in samples do
			check(player, sample, now)
		end
	end)
end

return MovementValidationService
