-- CharacterService: OYUNCUNUN KENDİ ROBLOX AVATARI ile doğma.
--
-- Avatar kuralları (kullanıcının zorunlu şartı):
--   * Özel karakter modeli YOK. StarterPlayer.StarterCharacter bulunursa uyarılır.
--   * Karakter player:LoadCharacter() ile yüklenir → Roblox, hesabın HumanoidDescription'ını yükler
--     (kıyafet, aksesuar, vücut oranları, animasyon paketi korunur).
--
-- Doğma akışı (Aşama 1 — ana menü):
--   * Players.CharacterAutoLoads = false. Oyuncu ana menüdeyken karakteri YOKTUR.
--   * İstemci "OYNA" deyince PlayerRemotes.RequestSpawn gelir → sunucu doğrular, dünyanın zemini
--     hazır olana kadar bekler ve TEK karakter yükler (kilit + "zaten canlı mı" kontrolü).
--   * Menüdeyken akış odağı (ReplicationFocus) menü kamerasının baktığı bölgeye çevrilir;
--     doğarken karaktere geri verilir.
--   * Ölünce (veya karakter kaybolursa) RespawnDelay sonra sunucu yeniden doğurur.
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
local RateLimiter = require(Shared.Utilities.RateLimiter)
local RemoteRegistry = require(Shared.RemoteRegistry)
local FrontEndConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FrontEndConfig"))
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

-- Doğma durumu (oyuncu başına)
type SpawnState = { InGame: boolean, Spawning: boolean }
local spawnStates: { [Player]: SpawnState } = {}
local spawnLimiter = RateLimiter.new(3, 0.5)
local spawnStatusRemote: RemoteEvent? = nil
local menuFocus: BasePart? = nil

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
	-- Ana menü: karakteri sunucu, oyuncu "OYNA" dediğinde yükler.
	-- (Place dosyasında da false olmalı; aksi halde ilk oyuncu bu satırdan önce otomatik doğabilir.)
	if Players.CharacterAutoLoads then
		Log.Warn("Players.CharacterAutoLoads açıktı; ana menü akışı için kapatılıyor.")
		Players.CharacterAutoLoads = false
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
		CharacterService:_scheduleRespawnCheck(player)
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
	spawnStates[player] = { InGame = false, Spawning = false }
	player:SetAttribute(Constants.Attributes.InGame, false)
	maid:Give(player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end))
	-- Karakter ölmeden kaybolursa (ör. başka bir sistem sildi) oyundaki oyuncu yine geri gelir
	maid:Give(player.CharacterRemoving:Connect(function()
		CharacterService:_scheduleRespawnCheck(player)
	end))
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	elseif menuFocus then
		-- Menüdeyken içerik menü kamerasının çevresinde aksın
		player.ReplicationFocus = menuFocus
	end
end

local function onPlayerRemoving(player: Player)
	spawnStates[player] = nil
	spawnLimiter:Forget(player)
	local maid = playerMaids[player]
	if maid then
		playerMaids[player] = nil
		maid:Clean()
	end
end

-- ===== Doğma (ana menü → dünya) =====
local function isAlive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character.Parent ~= nil
end

local function worldReady(): boolean
	local world = services.WorldService
	return world ~= nil and world:IsReady()
end

local function groundReady(): boolean
	if worldReady() then
		return true
	end
	local folder = workspace:FindFirstChild("World")
	local progress = folder and folder:GetAttribute("BuildProgress")
	return type(progress) == "number" and progress >= FrontEndConfig.MinWorldProgress
end

-- Önce dünyanın tamamını, olmazsa en az zemini bekler. Sonsuza kadar beklemez.
local function waitForWorld(player: Player)
	local function waitUntil(check: () -> boolean, seconds: number)
		local deadline = os.clock() + seconds
		while not check() and os.clock() < deadline and player.Parent == Players do
			task.wait(0.25)
		end
	end
	if not worldReady() and spawnStatusRemote then
		spawnStatusRemote:FireClient(player, "Queued", "World")
	end
	waitUntil(worldReady, FrontEndConfig.ServerWorldWait)
	if not worldReady() then
		waitUntil(groundReady, FrontEndConfig.ServerGroundWait)
		Log.Warn("Dünya tam hazır olmadan doğuruluyor:", player.Name, "zemin hazır:", groundReady())
	end
end

local function markInGame(player: Player, state: SpawnState)
	state.InGame = true
	player:SetAttribute(Constants.Attributes.InGame, true)
	player.ReplicationFocus = nil -- akış tekrar karakteri takip eder
end

-- Oyuncuyu dünyaya sokar. Karakter zaten canlıysa yenisini YARATMAZ (sadece etkinleştirir).
-- Aynı anda tek doğma işlemi yürür (Spawning kilidi). true → oyuncunun canlı karakteri var.
function CharacterService:SpawnPlayer(player: Player, reason: string?): boolean
	local state = spawnStates[player]
	if not state or player.Parent ~= Players then
		return false
	end
	if isAlive(player) then
		markInGame(player, state)
		return true
	end
	if state.Spawning then
		return false -- zaten sürüyor; ikinci karakter yaratma
	end
	state.Spawning = true
	waitForWorld(player)
	if player.Parent ~= Players or spawnStates[player] ~= state then
		state.Spawning = false
		return false
	end
	if isAlive(player) then
		state.Spawning = false
		markInGame(player, state)
		return true
	end
	-- Akış odağını doğmadan ÖNCE karaktere bırak (yeni karakterin çevresi hemen yüklensin)
	player.ReplicationFocus = nil
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	state.Spawning = false
	if not ok then
		Log.Error("LoadCharacter başarısız:", player.Name, err)
		return false
	end
	markInGame(player, state)
	Log.Info("Doğdu:", player.Name, "sebep:", reason or "?")
	return true
end

function CharacterService:IsInGame(player: Player): boolean
	local state = spawnStates[player]
	return state ~= nil and state.InGame
end

-- Ölüm/kaybolma sonrası: gecikmeden sonra oyuncu hâlâ oyundaysa ve canlı karakteri yoksa yeniden doğur.
-- Aynı karakter için birden çok çağrı güvenlidir (SpawnPlayer kilidi + canlılık kontrolü).
function CharacterService:_scheduleRespawnCheck(player: Player)
	task.delay(Config.Spawn.RespawnDelay, function()
		local state = spawnStates[player]
		if state and state.InGame and not state.Spawning and not isAlive(player) then
			CharacterService:SpawnPlayer(player, "Respawn")
		end
	end)
end

local function onSpawnRequest(player: Player)
	if not spawnLimiter:Check(player) then
		return
	end
	local session = services.PlayerService and services.PlayerService:GetSession(player)
	if not session or not spawnStates[player] then
		if spawnStatusRemote then
			spawnStatusRemote:FireClient(player, "Rejected", "NoSession")
		end
		return
	end
	if spawnStates[player].Spawning then
		return -- istemci tekrar bastı; süren işlem sonucu bildirecek
	end
	local ok = CharacterService:SpawnPlayer(player, "Menu")
	if spawnStatusRemote and player.Parent == Players then
		spawnStatusRemote:FireClient(player, if ok then "Spawned" else "Rejected", if ok then nil else "Error")
	end
end

function CharacterService:Init(allServices)
	services = allServices
	checkAvatarPolicy()
end

function CharacterService:Start()
	-- Menüdeki oyuncuların akış odağı (görünmez, çarpışmasız sabit parça)
	local focus = Instance.new("Part")
	focus.Name = "SolaraMenuFocus"
	focus.Anchored = true
	focus.CanCollide = false
	focus.CanQuery = false
	focus.CanTouch = false
	focus.Transparency = 1
	focus.Size = Vector3.new(1, 1, 1)
	focus.Position = FrontEndConfig.StreamFocus
	focus.Parent = workspace
	menuFocus = focus

	spawnStatusRemote = RemoteRegistry.Get("PlayerRemotes", "SpawnStatus") :: RemoteEvent
	local requestSpawn = RemoteRegistry.Get("PlayerRemotes", "RequestSpawn") :: RemoteEvent
	requestSpawn.OnServerEvent:Connect(function(player: Player)
		task.spawn(onSpawnRequest, player)
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return CharacterService
