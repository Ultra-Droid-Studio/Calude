-- AssetIds: Open Cloud ile Roblox'a yüklenen 3D modellerin asset numaraları (Studio gerekmez).
-- Yükleme: python3 tools/roblox_upload_asset.py ... (numarayı buraya kendisi yazar). 0 = yüklenmedi → eski görünüm.
-- Sunucu açılışta InsertService:LoadAsset ile yükler; asset, oyunun sahibiyle (kullanıcı ya da grup) aynı hesaba
-- yüklenmiş olmalı.
return {
	StreetLights = 0, -- assets/streetlights/StreetLights.glb (KMB3D, CC BY 4.0)
}
