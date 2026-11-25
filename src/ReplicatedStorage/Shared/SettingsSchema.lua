-- SettingsSchema: oyuncu ayarlarının TEK tanımı (Aşama 1).
-- İstemci (SettingsController + ayarlar ekranı) bugün kullanır; kalıcı kayıt aşamasında sunucudaki
-- veri servisi AYNI şemayla doğrulayacak. Yeni ayar = buraya bir satır + Strings'te etiket.
--
-- Tipler:
--   boolean                          Default
--   number   Min, Max, Step          Default (Step'e yuvarlanır, aralığa sıkıştırılır)
--   enum     Options = { değerler }   Default (sadece listedeki değerler)

local Constants = require(script.Parent.Constants)

local SettingsSchema = {}

SettingsSchema.Version = 1

-- Ayarlar ekranındaki sekme sırası
SettingsSchema.Categories = { "Graphics", "Camera", "Audio", "Controls" }

SettingsSchema.Definitions = {
	-- ===== Grafik (yerel; Roblox'un kendi grafik kalitesi Esc menüsünden ayarlanır) =====
	{ Key = "VisualEffects", Category = "Graphics", Type = "boolean", Default = true },
	{ Key = "Shadows", Category = "Graphics", Type = "boolean", Default = true },
	{ Key = "ReduceMotion", Category = "Graphics", Type = "boolean", Default = false },

	-- ===== Kamera (CameraController her karede okur) =====
	{ Key = "CameraMode", Category = "Camera", Type = "enum", Options = Constants.PlayerSelectableCameraModes, Default = "ThirdPerson" },
	{ Key = "CameraSensitivity", Category = "Camera", Type = "number", Min = 0.2, Max = 3, Step = 0.1, Default = 1 },
	{ Key = "InvertY", Category = "Camera", Type = "boolean", Default = false },
	{ Key = "FieldOfViewOffset", Category = "Camera", Type = "number", Min = -10, Max = 15, Step = 1, Default = 0 },
	{ Key = "ShoulderSide", Category = "Camera", Type = "enum", Options = { 1, -1 }, Default = 1 },
	{ Key = "CameraSmoothing", Category = "Camera", Type = "boolean", Default = true },

	-- ===== Ses (SoundGroup hacimleri; AudioController uygular) =====
	{ Key = "MasterVolume", Category = "Audio", Type = "number", Min = 0, Max = 1, Step = 0.05, Default = 1 },
	{ Key = "VehicleVolume", Category = "Audio", Type = "number", Min = 0, Max = 1, Step = 0.05, Default = 1 },
	{ Key = "WorldVolume", Category = "Audio", Type = "number", Min = 0, Max = 1, Step = 0.05, Default = 1 },
	{ Key = "InterfaceVolume", Category = "Audio", Type = "number", Min = 0, Max = 1, Step = 0.05, Default = 0.8 },

	-- ===== Kontroller =====
	{ Key = "MobileButtonScale", Category = "Controls", Type = "enum", Options = { 0.85, 1, 1.2 }, Default = 1 },
	{ Key = "MobileSteering", Category = "Controls", Type = "enum", Options = { "Pad", "Buttons" }, Default = "Pad" },
}

local byKey = {}
for index, def in SettingsSchema.Definitions do
	def.Order = index
	byKey[def.Key] = def
end

function SettingsSchema.Get(key: string)
	return byKey[key]
end

function SettingsSchema.GetByCategory(category: string)
	local list = {}
	for _, def in SettingsSchema.Definitions do
		if def.Category == category then
			table.insert(list, def)
		end
	end
	return list
end

function SettingsSchema.Defaults(): { [string]: any }
	local values = {}
	for _, def in SettingsSchema.Definitions do
		values[def.Key] = def.Default
	end
	return values
end

-- Değeri şemaya uydurur. Geçersizse nil döner (çağıran reddeder).
function SettingsSchema.Normalize(key: string, value: any): any
	local def = byKey[key]
	if not def then
		return nil
	end
	if def.Type == "boolean" then
		return if type(value) == "boolean" then value else nil
	elseif def.Type == "number" then
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		local clamped = math.clamp(value, def.Min, def.Max)
		if def.Step then
			clamped = def.Min + math.floor((clamped - def.Min) / def.Step + 0.5) * def.Step
			clamped = math.clamp(clamped, def.Min, def.Max)
			-- kayan nokta gürültüsünü temizle (0.30000000004 → 0.3)
			clamped = math.floor(clamped * 1000 + 0.5) / 1000
		end
		return clamped
	elseif def.Type == "enum" then
		return if table.find(def.Options, value) then value else nil
	end
	return nil
end

function SettingsSchema.IsValid(key: string, value: any): boolean
	local normalized = SettingsSchema.Normalize(key, value)
	return normalized ~= nil and normalized == value
end

-- Dışarıdan gelen (ör. kayıttan okunan) tabloyu temizler: bilinmeyen/geçersiz alanlar atılır.
function SettingsSchema.Sanitize(data: any): { [string]: any }
	local clean = {}
	if type(data) ~= "table" then
		return clean
	end
	for key, value in data do
		if type(key) == "string" then
			local normalized = SettingsSchema.Normalize(key, value)
			if normalized ~= nil then
				clean[key] = normalized
			end
		end
	end
	return clean
end

return SettingsSchema
