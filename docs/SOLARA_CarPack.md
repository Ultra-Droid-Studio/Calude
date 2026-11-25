# SOLARA — 3D araba paketi (Quaternius LowPoly Cars)

Durum: **dönüştürme ve kod hazır; modeller henüz Roblox'a yüklenmedi, Studio'da test edilmedi.**
Derleme: `place/SOLARA_Cars.rbxlx` (Aşama 1–6 + düzeltmeler + bu entegrasyon). Modeller içe aktarılana kadar oyun
eski kutu görünümle çalışır.

## Lisans
`assets/carpack/LICENSE.txt`: **CC0 1.0 Universal (kamu malı)** — Quaternius. Oyunda ticari dahil serbestçe
kullanılabilir, değiştirilebilir, atıf zorunlu değil (jenerikte "Araba modelleri: Quaternius" yazılması önerilir; metin
`CarModelConfig.Credit`'te hazır). Pakette marka logosu/ismi yok.

## Paket
7 araba: NormalCar1, NormalCar2, SUV, SportsCar, SportsCar2, Taxi, Cop. Her biri ~2950–3300 üçgen (Roblox'un parça başına
~20 000 sınırının çok altında), düz renkli malzemeler (doku dosyası yok), ayrı ön tekerler + tek parça arka teker çifti.

## Dönüştürme (`python3 tools/carpack_convert.py <FBX klasörü>`)
* FBX'ler projedeki `tools/fbx_reader.py` ile okunur (dış program yok; sadece veri okunur).
* Roblox eksenleri (yukarı +Y, ön −Z, sağ +X), metre; kök = dört teker merkezinin ortası.
* Her malzeme ayrı parça: `Paint` (boyanabilir gövde), `Paint2` (ikinci renk), `Glass`, `Dark`, `Trim`, `Headlight`,
  `TailLight`, `SirenWhite`, `SirenBlue`; her teker `Wheel_XX_Tire` + `Wheel_XX_Rim` (arka çift sol/sağ ayrıldı,
  NormalCar2'nin kaymış teker pivotu düzeltildi). Düz gölgeleme için yüz normalleri.
* Çıktı: `assets/carpack/<Ad>.glb`, ölçüler `assets/carpack/carpack.json`, önizleme `docs/carpack_preview.png`
  (.glb'lerden geri okunarak çizildi; yön/renk doğrulaması). Dönüştürücü kendi kendini denetler: üçgen sayısı,
  ön tekerler −Z, sol −X, tekerler gövdenin altında.

| Model | Uzunluk | Genişlik | Yükseklik | Dingil | İz | Teker r |
|---|---|---|---|---|---|---|
| NormalCar1 | 4.22 m | 1.81 | 1.18 | 2.44 | 1.38 | 0.262 |
| NormalCar2 | 3.31 | 1.64 | 1.15 | 2.00 | 1.32 | 0.248 |
| SUV | 4.21 | 2.11 | 1.53 | 2.57 | 1.53 | 0.327 |
| SportsCar | 3.97 | 1.80 | 1.16 | 2.44 | 1.43 | 0.260 |
| SportsCar2 | 3.93 | 1.87 | 1.20 | 2.51 | 1.45 | 0.280 |
| Taxi | 4.22 | 1.81 | 1.31 | 2.44 | 1.38 | 0.262 |
| Cop | 3.73 | 1.78 | 1.24 | 2.30 | 1.42 | 0.275 |

## Oyundaki eşleme (`CarModelConfig`)
| Araç tanımı | Model |
|---|---|
| compact_pico (Pico) | NormalCar2 |
| sedan_vela (Vela) | NormalCar1; trafikte %15 Taxi (sarı, boyası sabit) |
| sports_rayo (Rayo GT) | SportsCar veya SportsCar2 (rastgele) |
| suv_terra (Terra) | SUV |
| pickup_mesa, van_porter, utility_brisa | pakette karşılığı yok → kutu görünüm |
| — | Cop: ileride polis aşaması için hazır (şimdilik kullanılmıyor) |

## Nasıl giydirilir (kod)
* `CarModelKit` modeli **kendi tekerlerinden kalibre eder** (ön/sağ/yukarı ve orijin tekerlerden hesaplanır) →
  Studio'nun içe aktarıcısı yönü ya da birimi farklı yorumlasa da doğru oturur.
* **Oyuncu araçları (VehicleFactory):** fizik hiç değişmez (şasi, balast, yaylar, fizik tekerleri, çarpışma kabuğu
  aynen; görünmez olur). Model fizikteki dingil mesafesine ölçeklenir. Modelin tekerleri fizik tekerlerinden ~%35
  küçük olduğundan görünür araç tekerleri yere değecek kadar alçakta durur; görünür tekerler dönmeyen mafsala bağlıdır
  (direksiyon ve süspansiyonla hareket eder), dönüşü `VehicleVisualsController` her istemcide fizik tekerinin hızından
  oynatır. Far/stop modeldeki `Headlight`/`TailLight` parçalarında yanar (far ışık kaynakları korunur). Oturan
  karakterin başı tavandan çıkmasın diye koltuk ve direksiyon gerektiği kadar alçaltılır. Boya: aracın renk listesinden.
* **NPC trafik (TrafficRenderer):** aynı modeller, tek kutu çarpışma gövdesi, rastgele boya, yakındaki araçlarda teker
  dönüşü, fren/far lambaları, havuzdan yeniden kullanım.
* Model yoksa ya da parça adları bulunamazsa uyarı yazılır ve kutu görünüm kullanılır (oyun bozulmaz).

## Studio'da içe aktarma (senin yapman gereken — modeller senin Roblox hesabına yüklenir)
1. `place/SOLARA_Cars.rbxlx`'i Studio'da aç (Roblox hesabınla giriş yapmış ol).
2. **Home** (veya **Avatar**) sekmesi → **Import 3D** → `NormalCar1.glb`'yi seç.
3. İçe aktarma penceresinde: dosya ağacında 14–16 parça görünmeli. Parçaları birleştiren bir seçenek (Merge Meshes
   vb.) varsa **kapalı** olsun; diğer ayarlar varsayılan. **Import**.
4. Kalan 6 dosya için tekrarla (Cop dahil). Hepsi Workspace'e `NormalCar1`, `NormalCar2`, `SUV`, `SportsCar`,
   `SportsCar2`, `Taxi`, `Cop` adlı Model olarak gelir. (Ad farklıysa bu adlara çevir.)
5. Explorer'da **ReplicatedStorage**'a sağ tık → Insert Object → **Folder**, adı `VehicleModels`. 7 modeli içine sürükle.
6. (Önerilir) Her modelin içindeki MeshPart'ları seç → Properties → **CollisionFidelity = Box** (performans).
7. Play: park etmiş Pico/Vela/Rayo/Terra ve yoldaki trafik yeni görünümde olmalı. Output'ta `[CarModelKit]` uyarısı
   olmamalı.
8. **File → Save to File As…** ile `.rbxlx` olarak kaydet ve **bana gönder**: bundan sonraki derlemeleri bu dosyanın
   üstüne yaparım, modeller her sürümde kalır. (Göndermezsen benim sonraki dosyalarımda modeller olmaz; her seferinde
   5. adımı tekrar etmen gerekir.)

## Studio test senaryoları
1. Park etmiş araçlar: gövde tekerlerin üstünde düzgün oturuyor mu (havada/gömülü değil), tekerler kemerlerde mi?
2. Sür: tekerler dönüyor mu, direksiyonla ön tekerler dönüyor mu, süspansiyonla iniyor mu?
3. Far (L) ve fren: modeldeki farlar/stoplar yanıyor mu?
4. Sürücü ve yolcu: baş tavandan çıkıyor mu?
5. Trafik: NPC araçlar yeni görünümde, rastgele renkli, ara sıra taksi; çarpınca savruluyor mu?
6. Mobil: FPS (araç başına ~15 MeshPart).

## Bilinen sınırlamalar
* Modelde sinyal lambası yok: bu araçlarda sinyaller görünmez (sistem çalışır).
* Görünür tekerlek fizik tekerinden küçük; çarpışma kabuğu (görünmez) eski kutu ölçülerinde — çarpışmalar gövdeden
  birkaç santim farklı hissedilebilir.
* İçe aktarıcının adlandırması bilinmiyor: parça adları değişirse `[CarModelKit]` uyarısı çıkar → bana yaz.
