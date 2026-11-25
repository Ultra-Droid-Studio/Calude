-- Log: sistem adıyla etiketlenmiş çıktı. Output penceresinde hangi sistemin ne dediği belli olur.

local RunService = game:GetService("RunService")
local Config = require(script.Parent.Parent.Config)

local Log = {}

local side = if RunService:IsServer() then "S" else "C"

function Log.new(systemName: string)
	local prefix = string.format("[%s][%s]", side, systemName)
	local logger = {}
	function logger.Info(...: any)
		if Config.Debug.VerboseLogging then
			print(prefix, ...)
		end
	end
	function logger.Warn(...: any)
		warn(prefix, ...)
	end
	function logger.Error(...: any)
		-- error() fırlatmaz; sadece kırmızı olmadan görünür uyarı + traceback
		warn(prefix, "ERROR:", ...)
		warn(debug.traceback(nil, 2))
	end
	return table.freeze(logger)
end

return Log
