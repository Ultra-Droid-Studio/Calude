# SOLARA — 3D sokak lambaları

Durum: **kod ve model hazır; çevrimdışı test PASS. Model henüz Roblox'a yüklenmedi, oyunda test EDİLMEDİ.**
Model: "Various Low-Poly Street Lights" — KMB3D (Sketchfab), **CC BY 4.0** (atıf zorunlu; bkz. `docs/CREDITS.md`).
Derleme: `place/SOLARA_StreetLights.rbxlx` (önceki her şey + bu değişiklik).

## Kurulum — Studio GEREKMEZ (Open Cloud)
**Kısa yol:** `bash solara_models.sh` (Termux; bütün modellerle birlikte — bkz. `docs/SOLARA_Models.md`). Aşağıdaki
adımları elle yapmak istersen:

Oyun `.rbxlx` olarak Open Cloud ile yayınlandığı için 3D model de Open Cloud ile yüklenir; sunucu açılışta modeli
numarasıyla kendisi indirir (`InsertService:LoadAsset`).
1. Open Cloud API anahtarına **Assets API** izni (asset:read + asset:write) ver
   (https://create.roblox.com/dashboard/credentials). Anahtar, oyunun sahibi olan hesaba/gruba ait olmalı.
2. Modeli yükle (anahtar ortam değişkeninden okunur, komutta yazılmaz):
   ```
   export ROBLOX_API_KEY=...        # PowerShell: $env:ROBLOX_API_KEY="..."
   python3 tools/roblox_upload_asset.py assets/streetlights/StreetLights.glb --user-id <oyun sahibinin kullanıcı no> \
       --name "SOLARA Street Lights" --set StreetLights
   ```
   (Oyun bir grubunsa `--user-id` yerine `--group-id <grup no>`.) Betik asset numarasını
   `WorldGen/AssetIds.lua`'ya yazar.
3. Yeri yeniden derle (`tools/build_place.py`) ve her zamanki gibi Open Cloud ile yayınla.
4. Oyunda sunucu çıktısında `[StreetLights] 3D lambalar kullanılıyor: ...` görünür. Numara 0 ise, model
   yüklenemezse ya da eksenleri beklenenden farklıysa (uyarı yazılır) eski lambalar kurulur; oyun bozulmaz.
(Studio'su olan biri modeli elle içe aktarıp ServerStorage'a `StreetLightModels` adıyla da koyabilir; o öncelikli.)

## Ne değişti
| Dosya | Değişiklik |
|---|---|
| `tools/roblox_upload_asset.py` (yeni) | Open Cloud ile model yükleme, numarayı AssetIds.lua'ya yazma |
| `tools/streetlights_convert.py` (yeni) | 8 lambaya ayırma, direk tabanına ortalama, kolu yola döndürme → `assets/streetlights/StreetLights.glb` + `StreetLightData.lua` + `preview.png` |
| `WorldGen/StreetLights.lua` (yeni), `WorldGen/AssetIds.lua` (yeni) | modeli asset numarasıyla yükler (ya da elle konmuş şablonu kullanır), şablonları bulur ve ölçer (içe aktarma ölçeğinden bağımsız), lambayı yerleştirir: 3.5 stud/metre (16–18 stud, eski lamba 18), direk koyu metal, lamba camı `StreetLamp` etiketi + her 3 lambada bir SpotLight (eskisi gibi) |
| `WorldGen/PropBuilder.lua` | lamba: 3D model varsa onu, yoksa eski prosedürel lamba |
| Ayarlar ekranı | alt satırda model atıfları (CC BY şartı) |

Gece yakma/söndürme değişmedi: WeatherService `StreetLamp` etiketli lamba camını yakar.

## Bölgeye göre lamba tipi
| Bölge | Tip | Adet |
|---|---|---|
| Solara Centro, Ironside, kırsal yollar | Arm (modern tek kol) | 682 |
| Costa Verano, Isla Coral, Mirador | Globe (küre başlık — sahil havası) | 457 |
| Vista Norte, Dry Creek, Pinebrook | Lantern (kolda asılı fener) | 447 |
| Palm Heights | Crook (süslü üçlü) | 325 |
| Old Riverside | Classic (klasik fener) | 228 |
| Bayview | Twin (çift fener) | 228 |
Double ve TwinBar şablonları da içe aktarılır, şu an bir bölgeye atanmadı (istenirse tek satırla atanır).

## Test (çevrimdışı) — `python3 -I tools/test_streetlights.py <lupa>`
Gerçek `StreetLights.lua`, haritadaki 2367 lambanın hepsi; Import 3D'nin üreteceği parçalar 3 farklı ölçek
(1 / 3.57 / 0.01 stud/metre) ve başlangıç noktasıyla taklit edildi:
* sonuç içe aktarma ölçeğinden ve konumundan bağımsız — PASS
* direk tabanı tam lamba noktasında (kaldırım yüksekliği), yükseklik 16.3–18.4 stud — PASS
* kollu lambalarda başlık yol tarafında 4.3–6.0 stud ileride (eski lamba 3.2); diğerleri direğin üstünde — PASS
* lamba camı `StreetLamp` etiketli, her 3. lambada ışık (789) — PASS
* asset numarasıyla yükleme yolu (InsertService taklidi) aynı lambayı verir — PASS
* model yoksa eski lambaya dönüş — PASS
* Lint: önceki durum (1 hata + 3 uyarı, eski dosyalarda).

## Sınırlamalar / performans
* Toplam ~2.9 milyon üçgen (2367 lamba × 800–2400); StreamingEnabled sadece yakındakileri yükler ve Roblox aynı
  modelin kopyalarını toplu çizer. Telefonda Palm Heights (Crook, 2410 üçgen) en ağır bölge — FPS düşerse oraya daha
  hafif tip (Twin/Globe) atanır.
* Roblox'un .glb işleme davranışı (ölçek, eksen) oyunda doğrulanmalı; kod ölçeği kendisi ölçer, eksen farklıysa
  uyarı verip eski lambaya döner. Open Cloud'un .glb'yi Model olarak kabul ettiği varsayıldı (kabul etmezse betik
  hatayı yazar).
* Oyunun Roblox açıklamasına atıf satırı eklenmeli (`docs/CREDITS.md`).
