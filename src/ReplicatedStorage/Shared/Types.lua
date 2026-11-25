-- Types: sistemler arası paylaşılan Luau tipleri.

export type GameMode = "Normal" | "Sandbox"
export type RigType = "R6" | "R15"
export type MovementState = "Walk" | "Run" | "Sprint"
export type DeviceType = "KeyboardMouse" | "Touch" | "Gamepad"

export type CameraProfile = {
	Distance: number,
	MinDistance: number,
	MaxDistance: number,
	ShoulderOffset: Vector3, -- X: sağ/sol omuz, Y: pivot üstü yükseklik
	FieldOfView: number,
	MinPitch: number, -- derece
	MaxPitch: number, -- derece
	FollowSharpness: number, -- pivot takibi (yüksek = daha sıkı)
	RotationSharpness: number,
	CollisionRadius: number,
	HideCharacter: boolean,
	SprintFovBoost: number,
	-- Sürüş kamerası (Aşama 3; sadece araç profillerinde)
	VerticalSharpness: number?,
	RoofClearance: number?,
	LengthFactor: number?,
	DistancePad: number?,
	AutoFollowSharpness: number?,
	AutoPitch: number?,
	PitchFollow: number?,
	RollFollow: number?,
	SpeedFovBoost: number?,
	SpeedDistanceBoost: number?,
}

export type SessionInfo = {
	GameMode: GameMode,
	Version: string,
	ServerTime: number,
}

-- ModuleScript tam olarak bir değer döndürmeli; tipler `Types.X` şeklinde kullanılır.
return {}
