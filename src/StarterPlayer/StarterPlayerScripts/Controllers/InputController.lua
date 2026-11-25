-- InputController: cihaz algılama + eylem tabanlı giriş.
-- Diğer sistemler tuşlarla değil EYLEMLERLE çalışır ("Sprint", "CameraCycle"...).
-- Klavye, gamepad ve mobil butonlar aynı eylem hattından geçer (Bölüm 21).

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Signal = require(Shared.Utilities.Signal)
local Constants = require(Shared.Constants)
local InputConfig = require(Modules.InputConfig)
local Log = require(Shared.Utilities.Log).new("Input")

local InputController = {
	Name = "InputController",
	Priority = 2,
	ActionBegan = Signal.new(), -- (actionName)
	ActionEnded = Signal.new(), -- (actionName)
	DeviceChanged = Signal.new(), -- (deviceType)
}

local activeActions: { [string]: boolean } = {}
local deviceType = Constants.DeviceTypes.KeyboardMouse

local function classify(inputType: Enum.UserInputType): string?
	if inputType == Enum.UserInputType.Touch then
		return Constants.DeviceTypes.Touch
	end
	if inputType.Name:find("Gamepad") then
		return Constants.DeviceTypes.Gamepad
	end
	if inputType == Enum.UserInputType.Keyboard or inputType.Name:find("Mouse") then
		return Constants.DeviceTypes.KeyboardMouse
	end
	return nil
end

local function setDevice(newType: string?)
	if newType and newType ~= deviceType then
		deviceType = newType
		Log.Info("Cihaz değişti:", newType)
		InputController.DeviceChanged:Fire(newType)
	end
end

function InputController:GetDeviceType(): string
	return deviceType
end

function InputController:IsTouch(): boolean
	return deviceType == Constants.DeviceTypes.Touch
end

function InputController:IsActionActive(actionName: string): boolean
	return activeActions[actionName] == true
end

-- Mobil butonlar ve testler bu fonksiyonla eylem tetikler
function InputController:Trigger(actionName: string, began: boolean)
	if began then
		if activeActions[actionName] then
			return
		end
		activeActions[actionName] = true
		InputController.ActionBegan:Fire(actionName)
	else
		if not activeActions[actionName] then
			return
		end
		activeActions[actionName] = nil
		InputController.ActionEnded:Fire(actionName)
	end
end

local function bindAction(actionName: string, def)
	local inputs = {}
	for _, key in def.Keys do
		table.insert(inputs, key)
	end
	for _, key in def.Gamepad do
		table.insert(inputs, key)
	end
	if #inputs == 0 then
		return
	end
	-- Bağlam eylemleri (Vehicle, Menu) yürürken varsayılan kontrollerin önüne geçmeli
	local priority = if def.Context and def.Context ~= "OnFoot" then Enum.ContextActionPriority.High.Value else Enum.ContextActionPriority.Default.Value
	ContextActionService:BindActionAtPriority("OW_" .. actionName, function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController:Trigger(actionName, true)
			if not def.Hold then
				-- Tek seferlik eylem: hemen bitir
				InputController:Trigger(actionName, false)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			if def.Hold then
				InputController:Trigger(actionName, false)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, priority, table.unpack(inputs))
end

local activeContexts: { [string]: boolean } = { OnFoot = true }

-- Bağlam aç/kapat: o bağlamdaki eylemler bağlanır veya çözülür (basılı kalanlar bırakılır)
function InputController:SetContext(contextName: string, enabled: boolean)
	if (activeContexts[contextName] == true) == enabled then
		return
	end
	activeContexts[contextName] = if enabled then true else nil
	for actionName, def in InputConfig.Actions do
		if (def.Context or "OnFoot") == contextName then
			if enabled then
				bindAction(actionName, def)
			else
				ContextActionService:UnbindAction("OW_" .. actionName)
				InputController:Trigger(actionName, false)
			end
		end
	end
end

function InputController:IsContextActive(contextName: string): boolean
	return activeContexts[contextName] == true
end

function InputController:Init()
	-- İlk cihaz tahmini
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		deviceType = Constants.DeviceTypes.Touch
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		deviceType = Constants.DeviceTypes.Gamepad
	end
	local last = classify(UserInputService:GetLastInputType())
	if last then
		deviceType = last
	end
end

function InputController:Start()
	for actionName, def in InputConfig.Actions do
		if (def.Context or "OnFoot") == "OnFoot" then
			bindAction(actionName, def)
		end
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		setDevice(classify(inputType))
	end)
	-- Pencere odağı kaybolursa basılı eylemleri bırak (takılı kalan depar vb. olmasın)
	UserInputService.WindowFocusReleased:Connect(function()
		for actionName in table.clone(activeActions) do
			InputController:Trigger(actionName, false)
		end
	end)
end

return InputController
