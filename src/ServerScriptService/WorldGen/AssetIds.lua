-- AssetIds: Open Cloud ile Roblox'a yüklenen 3D modellerin asset numaraları (Studio gerekmez).
-- Yükleme: Termux'ta bash solara_models.sh (numaraları derlenmiş .rbxlx'in içine kendisi yazar) ya da
-- python3 tools/roblox_upload_asset.py ... --set <Anahtar> (numarayı bu dosyaya yazar). 0 = yüklenmedi → eski görünüm
-- (oyun her durumda çalışır). "-- @asset <Anahtar>:" işaretleri betiklerin numarayı bulması içindir; silme.
-- Sunucu açılışta InsertService:LoadAsset ile yükler; asset, oyunun sahibiyle (kullanıcı ya da grup) aynı hesaba
-- yüklenmiş olmalı.
return {
	StreetLights = 114356071565868, -- @asset StreetLights: assets/streetlights/StreetLights.glb (KMB3D, CC BY 4.0)
	Cars = 124377195050272, -- @asset Cars: assets/cars/SOLARA_Cars.glb (kullanıcının verdiği 12 low-poly araba)
	TrafficLights = 112108028010572, -- @asset TrafficLights: assets/trafficlights/SOLARA_TrafficLights.glb (Kenney, CC0)
	Pedestrians = 135490682162696, -- @asset Pedestrians: assets/pedestrians/SOLARA_Pedestrians.glb (Microsoft Rocketbox, MIT)
}
