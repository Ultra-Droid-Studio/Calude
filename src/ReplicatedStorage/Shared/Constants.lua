-- Constants: isimler, attribute anahtarları ve enum benzeri string sabitleri.
-- Sihirli string'ler kodun içine dağılmasın diye hepsi burada.

local Constants = {}

Constants.Attributes = {
	-- Player
	GameMode = "GameMode",
	SessionReady = "SessionReady",
	InGame = "InGame", -- oyuncu ana menüden çıkıp dünyaya girdi mi (sunucu yazar)
	-- Character
	RigType = "RigType", -- "R6" | "R15"
	EyeHeight = "EyeHeight", -- HumanoidRootPart -> göz yüksekliği (avatar oranına göre)
	SpawnedAt = "SpawnedAt", -- os.clock() değil, workspace:GetServerTimeNow()
	MovementState = "MovementState", -- "Walk" | "Run" | "Sprint"
	-- Workspace (Studio testleri için)
	ForceGameMode = "ForceGameMode",
}

Constants.CameraModes = {
	Menu = "Menu",
	Cinematic = "Cinematic",
	ThirdPerson = "ThirdPerson",
	ThirdPersonAlt = "ThirdPersonAlt",
	FirstPerson = "FirstPerson",
	Vehicle = "Vehicle",
	Motorcycle = "Motorcycle",
}

-- Oyuncunun ayarlardan seçebileceği "temel" kamera modları (sırasıyla V tuşu ile döner)
Constants.PlayerSelectableCameraModes = { "ThirdPerson", "ThirdPersonAlt", "FirstPerson" }

Constants.MovementStates = {
	Walk = "Walk",
	Run = "Run",
	Sprint = "Sprint",
}

Constants.DeviceTypes = {
	KeyboardMouse = "KeyboardMouse",
	Touch = "Touch",
	Gamepad = "Gamepad",
}

Constants.WorldFolders = {
	"Districts",
	"Roads",
	"Buildings",
	"Sidewalks",
	"TrafficNodes",
	"PedestrianNodes",
	"Shops",
	"InteractiveLocations",
	"SpawnPoints",
}

return table.freeze(Constants)
