-- SettingsController: oyuncu ayarları (istemci tarafı).
-- Aşama 1: oturum içinde tutulur. Aşama 11'de Settings UI + DataService ile kalıcı hale gelecek.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Utilities.Signal)
local Constants = require(Shared.Constants)
local Log = require(Shared.Utilities.Log).new("Settings")

local SettingsController = {
	Name = "SettingsController",
	Priority = 1,
	Changed = Signal.new(), -- (key, newValue, oldValue)
}

local DEFAULTS = {
	CameraMode = "ThirdPerson", -- ThirdPerson | ThirdPersonAlt | FirstPerson
	CameraSensitivity = 1.0, -- 0.2 .. 3.0
	InvertY = false,
	FieldOfViewOffset = 0, -- -10 .. +15
	ShoulderSide = 1, -- 1 = sağ omuz, -1 = sol omuz
	CameraSmoothing = true,
}

-- Her ayar için doğrulayıcı: geçersiz değer reddedilir (UI hatası oyunu bozmasın)
local VALIDATORS = {
	CameraMode = function(v)
		return table.find(Constants.PlayerSelectableCameraModes, v) ~= nil
	end,
	CameraSensitivity = function(v)
		return type(v) == "number" and v >= 0.2 and v <= 3
	end,
	InvertY = function(v)
		return type(v) == "boolean"
	end,
	FieldOfViewOffset = function(v)
		return type(v) == "number" and v >= -10 and v <= 15
	end,
	ShoulderSide = function(v)
		return v == 1 or v == -1
	end,
	CameraSmoothing = function(v)
		return type(v) == "boolean"
	end,
}

local values = table.clone(DEFAULTS)

function SettingsController:Get(key: string): any
	return values[key]
end

function SettingsController:Set(key: string, value: any): boolean
	local validator = VALIDATORS[key]
	if not validator then
		Log.Warn("Bilinmeyen ayar:", key)
		return false
	end
	if not validator(value) then
		Log.Warn("Geçersiz ayar değeri:", key, value)
		return false
	end
	local old = values[key]
	if old == value then
		return true
	end
	values[key] = value
	SettingsController.Changed:Fire(key, value, old)
	return true
end

function SettingsController:ResetToDefaults()
	for key, value in DEFAULTS do
		self:Set(key, value)
	end
end

function SettingsController:Init() end
function SettingsController:Start() end

return SettingsController
