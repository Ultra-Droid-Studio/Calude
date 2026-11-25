-- MenuInput: menü gezinme girişleri (klavye, gamepad tuşları ve sol çubuk).
-- InputController'ın "Menu" bağlamı eylemlerini dinler; yön tuşları basılı tutulunca tekrar eder.
-- Hangi ekranın neyi yapacağına karar vermez, sadece niyeti iletir (handlers).
--
-- handlers:
--   IsActive  () -> boolean          menü açık ve giriş kabul ediyor mu
--   Navigate  (kind: "Move"|"Adjust", dir: -1|1) -> ()
--   Accept    () -> ()
--   Back      () -> ()
--   Tab       (dir: -1|1) -> ()
--   Close     () -> ()
--   Open      () -> ()               oyun içinde "OpenMenu" eylemi

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrontEndConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FrontEndConfig"))

local MenuInput = {}

local NAV = {
	MenuUp = { "Move", -1 },
	MenuDown = { "Move", 1 },
	MenuLeft = { "Adjust", -1 },
	MenuRight = { "Adjust", 1 },
}

function MenuInput.connect(inputController, handlers)
	local held: string? = nil -- tekrar edilen gezinme eylemi (ör. "MenuDown")
	local nextAt = 0
	local stickV, stickH = 0, 0

	local function perform(action: string)
		local nav = NAV[action]
		if nav then
			handlers.Navigate(nav[1], nav[2])
		end
	end

	local function startHold(action: string)
		perform(action)
		held = action
		nextAt = os.clock() + FrontEndConfig.NavRepeatDelay
	end

	inputController.ActionBegan:Connect(function(action: string)
		if action == "OpenMenu" then
			handlers.Open()
			return
		end
		if not handlers.IsActive() then
			return
		end
		if NAV[action] then
			startHold(action)
		elseif action == "MenuAccept" then
			handlers.Accept()
		elseif action == "MenuBack" then
			handlers.Back()
		elseif action == "MenuTabPrev" then
			handlers.Tab(-1)
		elseif action == "MenuTabNext" then
			handlers.Tab(1)
		elseif action == "MenuClose" then
			handlers.Close()
		end
	end)

	inputController.ActionEnded:Connect(function(action: string)
		if held == action then
			held = nil
		end
	end)

	-- Sol çubuk: eşik aşılınca bir adım, tutulursa tekrar
	local function onStick(position: Vector3)
		if not handlers.IsActive() then
			stickV, stickH, held = 0, 0, nil
			return
		end
		local threshold = FrontEndConfig.StickThreshold
		local v = if position.Y > threshold then -1 elseif position.Y < -threshold then 1 else 0
		local h = if position.X > threshold then 1 elseif position.X < -threshold then -1 else 0
		if v ~= stickV then
			stickV = v
			if v ~= 0 then
				startHold(if v < 0 then "MenuUp" else "MenuDown")
			elseif held == "MenuUp" or held == "MenuDown" then
				held = nil
			end
		end
		if h ~= stickH then
			stickH = h
			if h ~= 0 then
				startHold(if h < 0 then "MenuLeft" else "MenuRight")
			elseif held == "MenuLeft" or held == "MenuRight" then
				held = nil
			end
		end
	end

	UserInputService.InputChanged:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			onStick(io.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(io)
		if io.KeyCode == Enum.KeyCode.Thumbstick1 then
			onStick(Vector3.zero)
		end
	end)

	RunService.Heartbeat:Connect(function()
		if not held then
			return
		end
		if not handlers.IsActive() then
			held = nil
			return
		end
		local now = os.clock()
		if now >= nextAt then
			nextAt = now + FrontEndConfig.NavRepeatRate
			perform(held)
		end
	end)
end

return MenuInput
