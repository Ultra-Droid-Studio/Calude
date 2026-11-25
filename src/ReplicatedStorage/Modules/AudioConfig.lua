-- AudioConfig: tüm ses varlıkları tek yerde (Bölüm 23).
--
-- ÖNEMLİ: Spec gereği sadece ÖZGÜN veya LİSANSLI ses kullanılmalı. Bu yüzden ID'ler boş bırakıldı.
-- Roblox Creator Store'da (Studio → Toolbox → Audio) "car engine loop", "car horn", "motorcycle engine"
-- aratıp kullanım iznini kontrol ettiğin sesin ID'sini buraya yaz ("rbxassetid://123..." veya sadece sayı).
-- ID boşsa sistem sessizce çalışır; hiçbir şey bozulmaz.

local AudioConfig = {}

AudioConfig.Vehicle = {
	EngineCar = "",
	EngineMotorcycle = "",
	HornCar = "",
	HornMotorcycle = "",
	EngineBasePitch = 0.7, -- rölanti
	EngineMaxPitch = 1.9, -- en yüksek hızda
	EngineVolume = 0.55,
	HornVolume = 0.8,
	RollOffMin = 10,
	RollOffMax = 140, -- uzaktaki araçlar gereksiz yüksek ses çıkarmasın
}

function AudioConfig.Resolve(id: string?): string?
	if id == nil or id == "" then
		return nil
	end
	if string.find(id, "rbxasset", 1, true) then
		return id
	end
	return "rbxassetid://" .. id
end

return AudioConfig
