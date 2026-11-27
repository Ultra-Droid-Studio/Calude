# SOLARA — Kullanıcının modelleri: arabalar, trafik ışıkları, sokak lambaları, yayalar

Durum: **kod, modeller ve yükleme betiği hazır; çevrimdışı testler PASS. Modeller henüz Roblox'a yüklenmedi; oyunda
(Studio'da ya da yayında) test EDİLMEDİ.**
Derleme: `place/SOLARA_Models.rbxlx` (önceki her şey + bu değişiklikler; model numaraları 0, betik doldurur).

## Ne geldi
| | Model (kullanıcının zip'inden) | Oyunda |
|---|---|---|
| **Arabalar** | 12 low-poly araba (cosmo-art) → `assets/cars/SOLARA_Cars.glb` | Oyuncunun sürdüğü araçlar **ve** NPC trafiği. Görünüm kaynakla aynı (aynı üçgenler, aynı renkler). Tekerlekler döner; farlar gece, stoplar gece ve frende, geri vites lambası geri giderken, sinyaller sinyalde yanar (araç ışık sistemine bağlı). Trafikte %35 modelin kendi rengi, kalanı aracın renk listesinden; polis (Patrulla) sabit siyah-beyaz, sedan trafiğinin ~%12'si. |
| **Trafik ışıkları** | Kenney trafik ışıkları A / B / C → `assets/trafficlights/SOLARA_TrafficLights.glb` | Her ışıklı kavşak kolunda: çok şeritli yolda yola uzanan kollu **C**, diğerlerinde **A** ya da **B** (B'nin sokak lambası gece yanar). Kırmızı / sarı / yeşil cam, NPC'lerin uyduğu sinyal durumuyla birlikte yanar (diğer camlar kendi koyu renginde). |
| **Sokak lambaları** | KMB3D sokak lambaları (önceden verdiğin) → `assets/streetlights/StreetLights.glb` | Bölgeye göre 6 tip, gece yanar (WeatherService). Değişmedi; artık aynı betikle yüklenir. |
| **Yayalar** | 10 Rocketbox insan (4 kadın, 6 erkek; `Business_Male_04 (1)` aynı dosya, atlandı) → `assets/pedestrians/SOLARA_Pedestrians.glb` | Yüz, saç, kıyafet dokuları modelin kendisi. Yürüme, duruş, dönüş, kapı itme: oyunun ters kinematikli yürüme sistemi (PedAnim) kemiklere uygulanır — basan ayak kaymaz, kollar karşı bacakla sallanır, kalça iner kalkar. Boy 5.4–5.9 stud. |

Arabaların oyundaki adları (gerçek marka yok): Bastion, Cresta (SUV/kamyonet), Solano, Marlin (sedan), Chispa
(kompakt), Vortex, Strada, Rossa, Brava, Furia (spor), Mula (minibüs / iş aracı), Patrulla (polis, sadece trafik).
Önizlemeler: `docs/cars_preview.png`, `docs/trafficlights_preview.png`, `docs/pedestrians_preview.png`,
`docs/pedestrians_walk_preview.png` (oyunun kendi kodunun ürettiği yürüme kareleri).

## Kurulum — Termux, tek komut (Studio, Python, repo GEREKMEZ)
1. Paketteki 7 dosyayı telefonun **İndirilenler** klasörüne koy: `solara_models.sh`, `SOLARA_Models.rbxlx`,
   `StreetLights.glb`, `SOLARA_Cars.glb`, `SOLARA_TrafficLights.glb`, `SOLARA_Pedestrians.glb`, `OKU_BENI.txt`.
2. API anahtarında şu izinler olsun (https://create.roblox.com/dashboard/credentials): **Assets API** (asset:read +
   asset:write) ve yayınlama izni (zaten kullanıyorsun). Anahtar oyunun sahibinin hesabında / grubunda olmalı.
3. Termux: `bash /storage/emulated/0/Download/solara_models.sh`
   (ilk kezse önce `termux-setup-storage`; curl yoksa `pkg install curl`).
4. Betik sorar: oyunun sahibi (kullanıcı / grup no), API anahtarı (gizli). 4 modeli yükler, Roblox'un işlemesini
   bekler, numaraları `SOLARA_Models.rbxlx`'in içine yazar (yedek: `.rbxlx.yedek`), `solara_asset_ids.txt`'ye
   kaydeder, istersen yayınlar (Universe ID + Place ID).
5. **`solara_asset_ids.txt`'deki 4 numarayı bana gönder** (gizli değiller): `AssetIds.lua`'ya yazarım, sonraki
   derlemelerde modeller kalır. Göndermezsen bir sonraki derlemem numaraları 0'a döndürür.

Betik ikinci kez çalışınca yüklü olanları atlar (istersen yeniden yükler). Anahtar sadece istek başlığında, standart
girişten gider (komut satırında / işlem listesinde görünmez), dosyaya yazılmaz.

## Oyunda nasıl doğrulanır
Sunucu çıktısı (Roblox Creator Hub'da sunucu günlüğü ya da Studio Output):
* `[ModelAssetService] arabalar hazır: Bastion, Solano, ...`
* `[ModelAssetService] trafik ışıkları hazır: 30 parça`
* `[ModelAssetService] yayalar hazır: F01, F02, ...`
* `[StreetLights] 3D lambalar kullanılıyor: ...`
Bir model yüklenemezse (numara 0, Roblox reddetti, dosya biçimi beklenmedik) o kısım **eski görünümle** çalışır
(kutu arabalar / eski ışık direği / R15 yayalar); oyun bozulmaz, çıktıda `[ModelAssetService]`, `[CarModelKit]`,
`[SignalRenderer]` ya da `[PedMeshRig]` uyarısı görünür — o satırı bana gönder.

Bakılacaklar: arabaya bin, sür (tekerler dönüyor mu, araç yerde mi, gece farlar, frende stop); trafikte farklı
renkler ve polis; kavşakta ışıkların sırayla yanması; yayaların yürümesi (ayak kayıyor mu, kollar doğal mı).

## Değişen / yeni dosyalar
| Dosya | Ne yapar |
|---|---|
| `tools/cosmo_cars_convert.py` | 12 FBX + palet → `SOLARA_Cars.glb`, `cars.json`, önizleme (renk grupları, roller, tekerlek adları, ön/arka) |
| `tools/gltf_decode.py` | meshopt + WebP sıkıştırmalı .glb okuyucu (Kenney, Rocketbox) |
| `tools/trafficlights_convert.py` | Kenney A/B/C → `SOLARA_TrafficLights.glb`, `TrafficLightData.lua`, önizleme |
| `tools/peds_convert.py` | Rocketbox → `SOLARA_Pedestrians.glb` (deri/skinned, 20 kemik, doku atlası), `PedModelData.lua`, önizleme |
| `Services/ModelAssetService.lua` (yeni) | Sunucu açılışında modelleri numarasıyla indirir: `ReplicatedStorage.VehicleModels`, `TrafficLightModels`, `PedestrianModels` (hazır olunca `Ready`) |
| `Shared/CarModelKit.lua`, `Modules/CarModelConfig.lua` | Rengi parça adından okur; lamba rolleri; teker yarıçapı lastik yüksekliğinden; model rengi seçeneği; yeni eşleme |
| `VehicleFactory.lua`, `TrafficRenderer.lua` | Model rengi / rastgele renk |
| `Ambient/SignalRenderer.lua` | 3D trafik ışığı (kalibrasyon, tip seçimi, cam yakma); model yoksa eski direk |
| `Ambient/PedMeshRig.lua` (yeni), `Ambient/PedRenderer.lua` | Gerçekçi yaya kurulumu ve kemik pozları; model yoksa R15 |
| `WorldGen/AssetIds.lua` | 4 numara (`-- @asset` işaretli; betik bunları bulur) |
| `solara_models.sh` (yeni; eski `solara_streetlights.sh` yerine) | Termux tek komut: yükle, numaraları yaz, yayınla |
| Ayarlar ekranı atıf satırı, `docs/CREDITS.md`, `assets/*/LICENSE.txt` | Atıflar / lisanslar |
| Silinen | Vento / Patrol dosyaları, `car_prepare.py`, `carpack_convert.py`, `CarBodyKit.lua`, `preview_carbody.py`, eski önizlemeler |

## Testler (çevrimdışı; oyunun GERÇEK Luau modülleri Lua 5.4'te, Roblox taklitleriyle — `tools/roblox_mock.py`)
* `tools/test_cars.py` — PASS: 12 arabanın hepsi yüklenir; içe aktarma ölçeği (1 / 3.57 / 3 / 0.5 / 2), dönüşü
  (döndürülmüş, dönüş meshe gömülü ya da değil) ve konumu ne olursa olsun aynı araba çıkar; tekerler akslarda
  (ön −Z, sol −X), farlar önde, stoplar arkada; roller, lamba adları (ışık sistemi), renkler; boya / model rengi /
  polisin sabit boyası; trafik seçimi (polis ~%12.5); model yoksa ya da klasör hazır değilse kutu araba.
* `tools/test_trafficlights.py` — PASS: aynı şekilde 5 içe aktarma biçimi; direk tam kaldırım noktasında, trafiğe
  bakıyor, camlar önde ve kırmızı > sarı > yeşil sırasında, C'nin kolu yolun üstüne uzanıyor; sadece aktif cam
  yanıyor; B'nin lambası gece etiketi alıyor; model yoksa eski direk.
* `tools/test_peds.py` — PASS: 10 karakter, 5 içe aktarma biçimi ve 3 kemik yerleşimi (kemikler meshin altında / kendi
  parçasında / yabancı bir parçada); ayaklar yerde, boy 5.4–5.9 stud, yüz −Z; kollar A-pozundan yanlara iniyor (~7°);
  PedAnim'in kalça/diz açıları ayak bileğini istenen noktaya koyuyor; tam yürüme döngüsünde mesh bütün kalıyor ve
  basan ayak kaymıyor (en fazla 0.006 stud/kare); PedRenderer model varken gerçekçi, yokken R15 yaya kuruyor.
* `solara_models.sh` — sahte `curl` ile uçtan uca: 4 yükleme, işlem bekleme, numaraların `.rbxlx`'e yazılması,
  yayınlanan dosyada numaralar, anahtarın komut satırında hiç görünmemesi, ikinci çalıştırmada atlama, 403'te durma
  — PASS. Gerçek Roblox'a karşı çalıştırılmadı.
* Mevcut testler: `test_streetlights.py` PASS; lint: önceki durum (1 hata + 3 uyarı, eski dosyalarda).

## Bilinmeyenler / riskler (oyunda görülecek)
* **Roblox'un .glb işlemesi:** Open Cloud'un "Model" yüklemesi .glb'yi MeshPart'lara çevirir (resmî belge); kod
  ölçeği, konumu ve dönüşü kendisi ölçer. Yayaların **deri (skinned) mesh + kemik + doku** olarak gelip gelmediği
  burada denenemedi. Kemikler gelmezse yayalar R15'e döner (uyarı yazar); doku gelmezse yayalar gri görünür — o
  durumda haber ver (çözüm: dokuları ayrı görsel olarak yüklemek ya da Studio'da içe aktarmak).
* `Model:ScaleTo` ile kemiklerin ölçeklenmesi taklitte doğrulandı, Roblox'ta doğrulanmadı.
* Yeni yüklenen modeller Roblox incelemesinden geçene kadar (genelde dakikalar) oyunda açılmayabilir.
* Yaya modeli dosyası 11.5 MB (sınır 20 MB); işlenmesi birkaç dakika sürebilir.
* **Performans:** yaya başına 7–9 bin üçgen. Bilgisayarda sorun beklenmez; telefonda çok kalabalık yerde FPS düşerse
  yaya sayısı (AmbientConfig) telefon için azaltılır.
* Furia'nın kaynak modelinde stop lambası yok (frende yanan bir şey yok). Furia oyunda diğer spor arabalardan biraz
  uzun (16.8 stud; tanım 14.4).
* Arabaların lisansı: cosmo-art sayfası buradan açılamadı. Paketi nasıl edindiğini ve lisans satırını kontrol et
  (satın alma / ücretsiz, ticari kullanım, atıf şartı).
* Oyunun Roblox açıklamasına `docs/CREDITS.md`'deki atıf satırlarını ekle.
