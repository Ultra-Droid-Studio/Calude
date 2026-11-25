-- InputConfig: eylem → tuş eşlemesi. Tuşlar tek yerden değiştirilebilir (Bölüm 21).
-- Mobil karşılıkları MobileControls (InputController içinde) tarafından özel butonlarla sağlanır.

local InputConfig = {}

InputConfig.Actions = {
	Sprint = {
		Keys = { Enum.KeyCode.LeftShift },
		Gamepad = { Enum.KeyCode.ButtonL3 },
		Hold = true, -- basılı tutulunca aktif (mobilde toggle olarak davranır)
	},
	WalkToggle = {
		Keys = { Enum.KeyCode.LeftControl },
		Gamepad = { Enum.KeyCode.ButtonR3 },
		Hold = false,
	},
	CameraCycle = {
		Keys = { Enum.KeyCode.V },
		Gamepad = { Enum.KeyCode.DPadUp },
		Hold = false,
	},
	FreeCursor = {
		-- PC'de imleci geçici serbest bırakır (kamera kilidi açılır)
		Keys = { Enum.KeyCode.LeftAlt },
		Gamepad = {},
		Hold = true,
	},
	ToggleDebug = {
		Keys = { Enum.KeyCode.F3 },
		Gamepad = {},
		Hold = false,
	},
	-- ===== Araç bağlamı (sadece araçtayken bağlanır; yürürken WASD'yi engellemez) =====
	VehGas = { Context = "Vehicle", Keys = { Enum.KeyCode.W, Enum.KeyCode.Up }, Gamepad = { Enum.KeyCode.ButtonR2 }, Hold = true },
	VehBrake = { Context = "Vehicle", Keys = { Enum.KeyCode.S, Enum.KeyCode.Down }, Gamepad = { Enum.KeyCode.ButtonL2 }, Hold = true },
	VehLeft = { Context = "Vehicle", Keys = { Enum.KeyCode.A, Enum.KeyCode.Left }, Gamepad = {}, Hold = true },
	VehRight = { Context = "Vehicle", Keys = { Enum.KeyCode.D, Enum.KeyCode.Right }, Gamepad = {}, Hold = true },
	VehHandbrake = { Context = "Vehicle", Keys = { Enum.KeyCode.Space }, Gamepad = { Enum.KeyCode.ButtonX }, Hold = true },
	VehHorn = { Context = "Vehicle", Keys = { Enum.KeyCode.H }, Gamepad = { Enum.KeyCode.ButtonL3 }, Hold = true },
	VehExit = { Context = "Vehicle", Keys = { Enum.KeyCode.F }, Gamepad = { Enum.KeyCode.ButtonY }, Hold = false },
	VehLights = { Context = "Vehicle", Keys = { Enum.KeyCode.L }, Gamepad = { Enum.KeyCode.DPadDown }, Hold = false },
	VehIndLeft = { Context = "Vehicle", Keys = { Enum.KeyCode.Q }, Gamepad = { Enum.KeyCode.DPadLeft }, Hold = false },
	VehIndRight = { Context = "Vehicle", Keys = { Enum.KeyCode.E }, Gamepad = { Enum.KeyCode.DPadRight }, Hold = false },
	VehFlip = { Context = "Vehicle", Keys = { Enum.KeyCode.R }, Gamepad = { Enum.KeyCode.ButtonB }, Hold = false },
	-- İleride: Interact (E), Inventory (Tab), Map (M)...
}

return InputConfig
