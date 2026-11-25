-- CharacterService: OYUNCUNUN KENDİ ROBLOX AVATARI ile doğma.
--
-- Avatar kuralları (kullanıcının zorunlu şartı):
--   * Özel karakter modeli YOK. StarterPlayer.StarterCharacter bulunursa uyarılır.
--   * Players.CharacterAutoLoads = true → Roblox, hesabın HumanoidDescription'ını yükler
--     (kıyafet, aksesuar, vücut oranları, animasyon paketi korunur).
--   * Görünümü değiştiren hiçbir ApplyDescription çağrısı yapılmaz.
--   * R6 ve R15 ikisi de desteklenir; rig tipi ve göz yüksekliği attribute olarak yazılır,
--     böylece kamera/araç/animasyon sistemleri farklı boylardaki avatarlara uyum sağlar.

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Constants = require(Shared.Constants)
local Signal = require(Shared.Utilities.Signal)
local Maid = require(Shared.Utilities.Maid)
local Log = require(Shared.Utilities.Log).new("CharacterService")

local CharacterService = {
	Name = "CharacterService",
	Priority = 20,
	CharacterReady = Signal.new(), -- (player, character, info)
}

local services
local playerMaids: { [Player]: any } = {}
local random = Random.new()

local APPEARANCE_TIMEOUT = 8

local function checkAvatarPolicy()
	if StarterPlayer:FindFirstChild("StarterCharacter") then
		Log.Warn("StarterPlayer.StarterCharacter bulundu! Bu, oyuncu avatarlarını EZER. Kaldırılmalı.")
	end
	if not StarterPlayer.LoadCharacterAppearance then
		Log.Warn("StarterPlayer.LoadCharacterAppearance kapalıydı; avatar görünümü için açılıyor.")
		pcall(function()
			StarterPlayer.LoadCharacterAppearance = true
		end)
	end
	if not Players.CharacterAutoLoads then
		Log.Warn("Players.CharacterAutoLoads kapalıydı; açılıyor.")
		Players.CharacterAutoLoads = true
	end
	Players.RespawnTime = Config.Spawn.RespawnDelay
end

local function getRigType(humanoid: Humanoid): string
	return if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
end

-- Kökten (HumanoidRootPart merkezi) yere olan mesafe. Avatar ölçeğine göre değişir.
local function getRootHeight(humanoid: Humanoid, root: BasePart): number
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	-- R6: bacaklar 2 stud, HipHeight genelde 0
	return 2 + root.Size.Y / 2 + humanoid.HipHeight
end

-- Kökten göz hizasına olan yükseklik. Kamera bunu pivot olarak kullanır.
local function measureEyeHeight(character: Model, root: BasePart): number
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		-- Kafanın merkezinden biraz yukarısı ≈ göz hizası
		return (head.Position.Y - root.Position.Y) + head.Size.Y * 0.1
	end
	return 1.5
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

-- Doğma noktasının altındaki gerçek zemini bul (plaza, kaldırım, blok yüksekliği farklı olabilir)
local function groundYAt(position: Vector3): number
	local characters = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(characters, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = characters
	local hit = workspace:Raycast(Vector3.new(position.X, position.Y + 60, position.Z), Vector3.new(0, -160, 0), groundParams)
	return if hit then hit.Position.Y else position.Y
end

local function pickSpawnCFrame(): CFrame
	local points = services.WorldService and services.WorldService:GetSpawnPoints() or {}
	if #points == 0 then
		return CFrame.new(Config.Spawn.FallbackPosition)
	end
	local point = points[random:NextInteger(1, #points)]
	local position = point.Position
	local y = groundYAt(position)
	-- Doğma noktasının kendi yönünü kullan (harita verisinde tanımlı)
	return CFrame.new(position.X, y, position.Z) * point.CFrame.Rotation
end

local function onCharacterAdded(player: Player, character: Model)
	local maid = playerMaids[player]
	if not maid then
		return
	end
	maid:Set("Character", nil)
	local charMaid = Maid.new()
	maid:Set("Character", charMaid)

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		Log.Warn("Karakter parçaları eksik:", player.Name)
		return
	end
	if character.Parent == nil or player.Character ~= character then
		return -- bu arada tekrar doğmuş
	end

	-- Konumlandırma: avatarın gerçek boyuna göre ayaklar yere değecek şekilde
	local spawnCFrame = pickSpawnCFrame()
	local rootHeight = getRootHeight(humanoid, root)
	task.wait() -- Roblox kendi doğma konumunu uyguladıktan sonra
	if player.Character ~= character then
		return
	end
	character:PivotTo(spawnCFrame + Vector3.new(0, rootHeight + 0.1, 0))
	character:SetAttribute(Constants.Attributes.SpawnedAt, workspace:GetServerTimeNow())

	-- Hareket değerleri (görünüme dokunmaz)
	humanoid.UseJumpPower = true
	humanoid.JumpPower = Config.Movement.JumpPower
	humanoid.WalkSpeed = Config.Movement.RunSpeed

	local rigType = getRigType(humanoid)
	character:SetAttribute(Constants.Attributes.RigType, rigType)

	-- Görünüm (aksesuar/ölçek) yüklenene kadar bekle, sonra göz yüksekliğini ölç
	if not player:HasAppearanceLoaded() then
		local loaded = false
		local conn = player.CharacterAppearanceLoaded:Connect(function()
			loaded = true
		end)
		local start = os.clock()
		while not loaded and os.clock() - start < APPEARANCE_TIMEOUT and player.Character == character do
			task.wait(0.1)
		end
		conn:Disconnect()
	end
	if player.Character ~= character then
		return
	end

	local function updateEyeHeight()
		character:SetAttribute(Constants.Attributes.EyeHeight, measureEyeHeight(character, root))
	end
	updateEyeHeight()
	-- Avatar ölçek değerleri değişirse (ör. ileride ayar menüsü) tekrar ölç
	for _, scaleName in { "BodyHeightScale", "HeadScale" } do
		local value = humanoid:FindFirstChild(scaleName)
		if value and value:IsA("NumberValue") then
			charMaid:Give(value.Changed:Connect(function()
				task.wait()
				updateEyeHeight()
			end))
		end
	end

	charMaid:Give(humanoid.Died:Connect(function()
		Log.Info("Öldü:", player.Name, "(", Config.Spawn.RespawnDelay, "sn sonra yeniden doğar )")
	end))

	local info = {
		RigType = rigType,
		EyeHeight = character:GetAttribute(Constants.Attributes.EyeHeight),
		RootHeight = rootHeight,
	}
	Log.Info("Avatar hazır:", player.Name, rigType, string.format("göz=%.2f", info.EyeHeight))
	CharacterService.CharacterReady:Fire(player, character, info)
end

local function onPlayerAdded(player: Player)
	if playerMaids[player] then
		return
	end
	local maid = Maid.new()
	playerMaids[player] = maid
	maid:Give(player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local maid = playerMaids[player]
	if maid then
		playerMaids[player] = nil
		maid:Clean()
	end
end

function CharacterService:Init(allServices)
	services = allServices
	checkAvatarPolicy()
end

function CharacterService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return CharacterService
