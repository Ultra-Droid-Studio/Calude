-- AssetIds: Open Cloud ile Roblox'a yüklenen 3D modellerin asset numaraları (Studio gerekmez).
-- Yükleme: bash solara_models.sh (ya da python3 tools/roblox_upload_asset.py ... --set <Anahtar>; numarayı buraya
-- kendisi yazar). 0 = yüklenmedi → eski görünüm (oyun her durumda çalışır).
-- Sunucu açılışta InsertService:LoadAsset ile yükler; asset, oyunun sahibiyle (kullanıcı ya da grup) aynı hesaba
-- yüklenmiş olmalı.
return {
	StreetLights = 0, -- assets/streetlights/StreetLights.glb (KMB3D, CC BY 4.0)
	Cars = 0, -- assets/cars/SOLARA_Cars.glb (kullanıcının verdiği 12 low-poly araba)
	TrafficLights = 0, -- assets/trafficlights/SOLARA_TrafficLights.glb (Kenney, CC0)
	Pedestrians = 0, -- assets/pedestrians/SOLARA_Pedestrians.glb (Microsoft Rocketbox, MIT)
}
