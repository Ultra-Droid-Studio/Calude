-- SettingsController: oyuncu ayarları (istemci tarafı).
--
-- Aşama 1 (ana menü): ayarlar artık Shared/SettingsSchema'dan gelir (tip, aralık, varsayılan, kategori).
-- Ayarlar ekranı şemayı okuyarak satırları kendisi üretir; doğrulama tek yerde.
--
-- Kalıcılık mimarisi (sonraki aşama için hazır):
--   Ayarlar bir "depo" (store) üzerinden yüklenir/kaydedilir:
--     store.Load() -> { Version, Values }?     (yield edebilir)
--     store.Save({ Version, Values })          (yield edebilir; burada task.spawn içinde çağrılır)
--   Bugünkü depo SessionStore'dur: değerler sadece bu oturum boyunca (yeniden doğmalar dahil) yaşar.
--   Veri aşamasında sunucudaki DataService'e giden bir depo SetStore() ile takılır; başka kod değişmez.
--
-- Genel API (geriye uyumlu): Get, Set, ResetToDefaults, Changed sinyali.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Utilities.Signal)
local SettingsSchema = require(Shared.SettingsSchema)
local Log = require(Shared.Utilities.Log).new("Settings")

local SettingsController = {
	Name = "SettingsController",
	Priority = 1,
	Changed = Signal.new(), -- (key, newValue, oldValue)
	Loaded = Signal.new(), -- () depodan değerler yüklendi
}

local SAVE_DEBOUNCE = 1.5

local values = SettingsSchema.Defaults()
local dirty = false
local saveScheduled = false

-- ===== Depolar =====
local SessionStore = {}
SessionStore.__index = SessionStore

function SessionStore.new()
	return setmetatable({ _data = nil }, SessionStore)
end

function SessionStore:Load()
	return self._data
end

function SessionStore:Save(payload)
	self._data = table.clone(payload)
end

local store = SessionStore.new()

-- ===== İç yardımcılar =====
local function scheduleSave()
	dirty = true
	if saveScheduled then
		return
	end
	saveScheduled = true
	task.delay(SAVE_DEBOUNCE, function()
		saveScheduled = false
		if not dirty then
			return
		end
		dirty = false
		local payload = SettingsController:Export()
		local ok, err = pcall(function()
			store:Save(payload)
		end)
		if not ok then
			Log.Warn("Ayarlar kaydedilemedi:", err)
		end
	end)
end

local function apply(key: string, value: any, save: boolean): boolean
	local normalized = SettingsSchema.Normalize(key, value)
	if normalized == nil then
		if SettingsSchema.Get(key) then
			Log.Warn("Geçersiz ayar değeri:", key, value)
		else
			Log.Warn("Bilinmeyen ayar:", key)
		end
		return false
	end
	local old = values[key]
	if old == normalized then
		return true
	end
	values[key] = normalized
	SettingsController.Changed:Fire(key, normalized, old)
	if save then
		scheduleSave()
	end
	return true
end

-- ===== Genel API =====
function SettingsController:Get(key: string): any
	return values[key]
end

function SettingsController:Set(key: string, value: any): boolean
	return apply(key, value, true)
end

-- category verilirse sadece o sekmenin ayarları sıfırlanır
function SettingsController:ResetToDefaults(category: string?)
	for _, def in SettingsSchema.Definitions do
		if category == nil or def.Category == category then
			apply(def.Key, def.Default, true)
		end
	end
end

function SettingsController:GetSchema()
	return SettingsSchema
end

function SettingsController:IsDefault(key: string): boolean
	local def = SettingsSchema.Get(key)
	return def ~= nil and values[key] == def.Default
end

function SettingsController:Export()
	return { Version = SettingsSchema.Version, Values = table.clone(values) }
end

-- Dışarıdan gelen veriyi (kayıt) şemaya göre temizleyip uygular. Kaydetmez (zaten kayıttan geldi).
function SettingsController:Import(payload: any)
	local data = if type(payload) == "table" then payload.Values else nil
	for key, value in SettingsSchema.Sanitize(data) do
		apply(key, value, false)
	end
end

-- Veri aşaması burayı kullanacak: SettingsController:SetStore(RemoteSettingsStore.new(...))
function SettingsController:SetStore(newStore)
	assert(type(newStore) == "table" and newStore.Load and newStore.Save, "Geçersiz ayar deposu")
	store = newStore
	task.spawn(function()
		local ok, payload = pcall(function()
			return store:Load()
		end)
		if ok and payload then
			SettingsController:Import(payload)
		elseif not ok then
			Log.Warn("Ayarlar yüklenemedi, varsayılanlar kullanılıyor:", payload)
		end
		SettingsController.Loaded:Fire()
	end)
end

function SettingsController:Init() end

function SettingsController:Start()
	local payload = store:Load()
	if payload then
		self:Import(payload)
	end
	SettingsController.Loaded:Fire()
end

return SettingsController
