# SOLARA — Emeği geçenler / üçüncü taraf içerik

| İçerik | Yazar | Lisans | Kaynak | Değişiklik | Oyunda |
|---|---|---|---|---|---|
| Sokak lambaları ("Various Low-Poly Street Lights") | KMB3D | CC BY 4.0 | https://sketchfab.com/3d-models/various-low-poly-street-lights-1173b0c4d9b0400bbeaafbee0e94ca59 | 8 lambaya ayrıldı, ortalandı, kolu yola bakacak şekilde döndürüldü, malzemeler sadeleştirildi (`tools/streetlights_convert.py`) | `assets/streetlights/StreetLights.glb` → Studio'da `ServerStorage.StreetLightModels` |
| Araba "Patrol" ("Police car") | Mateusz Woliński | CC BY 4.0 | https://sketchfab.com/3d-models/police-car-9166b13b6ae341f4bfc093edb71d74f4 | Üçgenler azaltıldı (dokular korunarak), ızgaradaki amblem dokuda kapatıldı, tekerlekler ayrı (`tools/car_prepare.py`) | `assets/cars/Patrol.glb` → `ReplicatedStorage.VehicleModels.Patrol` |
| Araba "Vento" ("(FREE) Porsche 911 Carrera 4S") | Karol Miklas | CC BY-SA 4.0 (değiştirilmiş hali de CC BY-SA 4.0) | https://sketchfab.com/3d-models/free-porsche-911-carrera-4s-d01b254483794de3819786d93e0e1ebf | Üçgenler azaltıldı (dokular korunarak), arma / yazılar / plakalar, vernik kabuğu ve gölge düzlemi çıkarıldı, tekerlekler sağ-sol ayrıldı (`tools/car_prepare.py`) | `assets/cars/Vento.glb` → `ReplicatedStorage.VehicleModels.Vento` |

CC BY 4.0 atıf şartı: oyunda Ayarlar ekranının alt satırında ve oyunun Roblox açıklamasında yazar adı + lisans
yazılmalı. Oyunun Roblox sayfası açıklamasına şu satırı ekle:

> Street lights: "Various Low-Poly Street Lights" by KMB3D (Sketchfab), CC BY 4.0, modified.
> Cars: "Police car" by Mateusz Woliński (Sketchfab), CC BY 4.0, modified; "(FREE) Porsche 911 Carrera 4S" by
> Karol Miklas (Sketchfab), CC BY-SA 4.0, modified (the modified model is CC BY-SA 4.0).

Eski Quaternius "LowPoly Cars" paketi (CC0) kullanıcının isteğiyle oyundan kaldırıldı.

Kullanılmayan yüklemeler: Ford Shelby GT500, Ducati XDiavel, Lightning LS-218, Aston Martin DB11 (büyük ihtimalle
başka kaynaktan kopyalanmış), GMC Yukon (malzeme adları GTA V araç dosyalarıyla aynı: oyundan çıkarılmış), iki
motosiklet (marka logosu / kaynağı belirsiz), insan gövdesi modelleri (iskelet, yüz, saç ve kıyafet yok).
