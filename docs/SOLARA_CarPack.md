# SOLARA — 12 araba paketi: gerçekçileştirme ve araç içi sistemler

| Aşama | Durum |
|---|---|
| 1 — İnceleme ve envanter | bitti (aşağıda) |
| 2 — Gövde yumuşatma, lastik/jant | **kod hazır, çevrimdışı testler PASS; oyunda test EDİLMEDİ** (arabaların yeniden yüklenmesi gerekiyor) |
| 3–8 | başlamadı |

## Aşama 2 — Gövde ve tekerlekler

Araç: `tools/car_refine.py`. Girdi `assets/cars/SOLARA_Cars_base.glb`: modelin orijinal hâli, aynen saklanır, geri dönüş için.
Çıktı `assets/cars/SOLARA_Cars.glb` (oyunun yüklediği dosya) ve güncel `cars.json`.
Önce/sonra görseli: `docs/cars_refine_preview.png`. Yumuşak gölgelendirmeyle çizildi; arkası dönük yüzler Roblox'taki gibi çizilmez.

**Ne değişti**
* **Gövde gölgelendirmesi (boya parçaları):**
  * Köşe noktalarının **şekli aynı**: hiçbir nokta kıpırdamadı. Bu yüzden parçalar birbirine giremez ve aralarında boşluk açılamaz.
  * Değişen yüzey normalleri. Modelcinin düz bıraktığı yüzeyler, 50°'den az açıyla birleştikleri komşularıyla tek yüzey gibi yumuşak gölgelenir.
  * Daha keskin kenarlar keskin kalır: kutu tasarım (Bastion), cam çerçeveleri, tasarım çizgileri.
  * Modelcinin zaten yumuşattığı yerler **aynen** korundu. Yeni normal komşu yumuşak gruba yakınsa ona katılır, böylece yeni dikiş çizgisi oluşmaz.
  * 12 arabada 1010 köşe daha yumuşak gölgeleniyor (6473 → 7483). Kaporta geçişleri, tavan ile yan geçişi (özellikle Mula) ve çamurluk kıvrımları bu sayede yumuşadı.
* **Ters yüzler düzeltildi:** 166 yüzün sırası ters çevrilmişti. Roblox bu yüzleri dışarıdan çizmiyordu, küçük delikler gibi görünüyorlardı. Normalleri doğruydu, sadece üçgen sırası ters çevrildi.
  * Bastion: 60 (tavan rafı çıtalarının yanları)
  * Cresta: 40
  * Chispa: 34, jantlar dahil
  * Rossa: 14
  * Vortex: 8
  * Solano: 6 (çamurluk kenarları)
  * Strada: 4
* **Lastikler:**
  * 10 köşeden (Brava 12) **20 köşeye** çıktı. Her arabanın kendi lastik kesiti kullanıldı: aynı yarıçap, genişlik, renk ve teker merkezi.
  * Omuz yumuşak gölgeleniyor. Jant kollarının arasındaki koyu girintiler orijinal.
  * Lastiğin yüksekliği artık tam 2 × yarıçap. Eskiden çokgen olduğu için %5 eksik ölçülüyordu; araba yere 0.02 m daha doğru oturur.
* **Jantlar:** orijinal jant aynen duruyor. Dış yüzüne aynı renkte ince, yuvarlak bir çerçeve eklendi; 10 köşeli dış hattı örtüyor ve lastikle arasındaki çizgiyi kapatıyor.
* **Çamurluk içi:** 12 arabanın hepsinde lastiğin üstünde zaten tekerlek yuvası yüzeyi var. Ek astar gerekmedi; araç, yuva olmayan bir model gelirse astar ekler.

**Ne değişmedi (bayt bayt aynı):** far, stop, geri vites, sinyal ve tepe lambaları, camlar ve bütün Detail parçaları (egzozlar, ızgaralar, plakalar, ayna kolları, spoyler ayakları, siyah tamponlar). Parça adları, renkler ve teker merkezleri de aynı.
* Siyah plastik tamponlar Detail parçalarında olduğu için yumuşatılmadı: egzozlar da bu parçalarda.
* Detail parçalarında da 42 ters yüz var. Koruma kuralı gereği dokunmadım; istersen düzeltirim.
* Cresta'nın stepnesi (Detail) 10 köşeli kaldı.

**Bilerek yapılmayanlar**
* Siluet ve köşe noktaları değişmedi. Bölme (subdivision) ya da pah kırma, gövdeyle kaynaşık lambaların, ızgaraların ve aynaların çevresinde boşluk ya da iç içe geçme yapardı. Bu, görev kuralına aykırı.
* Low-poly tarz modelin karakteri; yüksek poligon yeniden modelleme yapılmadı.

**Maliyet**
* Araba başına +640 üçgen (Brava +384, Furia +480). Hepsi tekerleklerden; gövdeye üçgen eklenmedi.
* 2450 üçgenlik araba 3090 oldu. En büyüğü Cresta: 3636.
* Parça sayısı aynı (yeni parça yok). Mobilde en fazla 34 trafik aracı ile yaklaşık +22 bin üçgen.

**Testler** (`tools/test_car_refine.py`, 10 kontrol; hepsi PASS):
1. Lambalar, camlar ve Detail parçaları aynı.
2. Gövde noktaları aynı; yeni normaller doğru yönde ve sınır içinde; modelcinin yumuşattığı köşeler aynı.
3. 55°'den keskin kenarlarda yeni yumuşatma yok.
4. Her arabada yumuşak köşe sayısı arttı ya da aynı kaldı.
5. Lastikler aynı yarıçap, genişlik ve merkezde, 20 köşeli, girinti orijinal.
6. Jant ile lastik arasında ve yanakta delik yok: tekerlek başına 648 ışın.
7. Üçgen sırası normallerle uyumlu.
8. Üçgen bütçesi içinde.
9. `cars.json` dosyayla uyumlu.
10. Ters yüzler düzeldi.

Eski testler de yeniden PASS:
* `test_cars`: oyun kodunun teker kalibrasyonu, ölçüler, roller, renkler, ışık adları, dönen tekerler.
* `test_hijack`: sürücü koltuğu.

**Yükleme:** arabalar değiştiği için oyun dosyasında arabaların numarası **0** yapıldı. `solara_models.sh` sadece arabaları yükler; diğer üç modelin numaraları aynen kalır. Eski numara: 124377195050272.

---

## Aşama 1 — İnceleme ve envanter

Tarih: 28.11.2026. Bu aşamada **oyunda hiçbir şey değişmedi**: sadece modeller ve sürüş kodu incelendi.

Kaynak: `assets/cars/SOLARA_Cars.glb` (Aşama 2'den beri orijinali `SOLARA_Cars_base.glb`) ve `assets/cars/cars.json`.
Ölçümler `tools/car_inventory/` betikleriyle modelin kendi üçgenlerinden yapıldı.
Görseller:
* `docs/car_inventory_cutaway.png`: her araba yandan, tavanı ve camları kesilmiş, üstten.
* `docs/car_inventory_parts.png`: otomatik bulunan aynalar (camgöbeği) ve egzoz bölgesi (mor). Bu tespit yaklaşık.

## Bütün arabalarda ortak durum

| Konu | Bulgu |
|---|---|
| Model yapısı | Parçalar **renge göre** gruplu, araba bölümlerine göre değil. "Paint" parçası tek bir parçadır: kaput, tavan, kapılar, çamurluklar ve bagaj kapağı birlikte. "Detail" parçaları: tampon altı, ızgara, plaka, ayna kolu, egzoz, spoyler ayağı ve trim. |
| Kapı / kaput / bagaj | **Ayrı parça değil**: gövdeyle kaynaşık. Açılır kapı için modelin kapı bölgesini kesip ayırmak gerekir. Bu görevde istenmedi. |
| Lambalar | Ayrı parçalar (Headlight, TailLight, ReverseLight, IndicatorL/R, polis tepe lambası). Işık sistemi bunlara bağlı. Yumuşatma bunlara dokunmayacak. |
| Tekerlekler | Her köşede ayrı lastik ve jant var, dönüyorlar. **Lastikler 10 köşeli** (Brava 12): yakından bakınca çokgen görünüyorlar. Jant dış hattı da 10 köşe. |
| Gölgelendirme | Yüzey normallerinin sadece %24–59'u yumuşak. Kalanı düz yüzey, gövde faset faset görünüyor (low-poly tarzı). |
| Camlar | Gerçek pencere açıklığı var (camın arkası boş). Oyunda cam %25 saydam. |
| **İç mekân** | **12 arabanın hiçbirinde yok**: koltuk, direksiyon, gösterge, konsol, taban ve iç kapı paneli yok. Araç içi boş bir kabuk. Kabuk yüzeyleri sadece dışa bakıyor, bu yüzden **içeriden bakınca kapılar, taban ve tavan görünmüyor**: iç kamerada dışarısı ve yol görünür. İç kamera için iç paneller şart. |
| Fizik bağlantısı | Model **sadece görünüm**. Parçalar kütlesiz, çarpışmasız ve ışın sorgularına kapalı, şasiye kaynaklı. Tekerlek görselleri direksiyon mafsalına Motor6D ile bağlı; direksiyon ve süspansiyonla hareket ediyorlar. Fizik ayrı ve görünmez: şasi, balast, 4 silindir teker, yay ve servo kısıtları, eski kutu gövde (çarpışma kabuğu). |

## Araba araba

Tüm sayılar modelin kendi ölçüsü. Oyunda model, aracın tanımındaki dingil mesafesine ölçeklenir (1 m ≈ 2.4–3.9 stud).

| Araba (kaynak) | Tür / oyundaki tanımlar | Boy × en × yük. (m), üçgen | Lambalar | Ayna | Egzoz (otomatik) | Yumuşak normal | Notlar |
|---|---|---|---|---|---|---|---|
| **Bastion** (armor) | zırhlı SUV; suv_terra, pickup_mesa | 5.15 × 2.47 × 1.97, 2450 | far, stop, geri, sinyal | var | tek, sağ arka | %26 | kutu tasarım (bilerek köşeli), tavan rafı, ön koruma |
| **Solano** (coupe) | 4 kapılı coupe; compact_pico, sedan_vela | 5.14 × 2.35 × 1.74, 2290 | far, stop | var | çift (difüzörde) | %40 | bagaj spoyleri |
| **Vortex** (fenyr) | süper spor; sports_rayo | 4.88 × 2.22 × 1.30, 2188 | far, stop | var | çift + difüzör | %40 | çok alçak tavan |
| **Strada** (ghini) | spor, büyük kanat; sports_rayo | 4.79 × 1.97 × 1.38, 2226 | far (2 üçgen), stop | var | orta, 3 uç | %32 | kanat Detail parçası |
| **Rossa** (italia) | süper spor; sports_rayo | 5.24 × 2.50 × 1.34, 2258 | far, stop | var | çift yuvarlak + difüzör kanatçıkları | %59 | en yumuşak model |
| **Cresta** (jeep) | arazi aracı; suv_terra, pickup_mesa | 4.45 × 2.28 × 2.04, 2996 | far (yuvarlak), stop, geri | var | belirsiz | %54 | stepne arkada, açık çamurluklar. **pickup_mesa'da sürücü koltuğu ön camın önüne düşüyor** (koltuk yerleşimi düzeltilmeli) |
| **Brava** (kamaro) | muscle car; sports_rayo | 4.87 × 2.01 × 1.36, 2444 | far, stop | var | bulunamadı | %51 | şeritli boya, 12 köşeli lastik |
| **Furia** (lamb) | süper spor, kanatlı; sports_rayo | 4.62 × 2.07 × 1.33, 1924 | **sadece far** | var | dörtlü | %26 | **stop lambası ayrı parça değil: fren / gece yanmıyor** |
| **Marlin** (mobil) | 50'ler sedanı, kanatçıklı; sedan_vela | 5.34 × 2.16 × 1.51, 2440 | far, stop | var | bulunamadı | %29 | arka teker etekliği (tasarım gereği tekeri örter) |
| **Patrulla** (police) | polis; sadece trafikte (sedan_vela) | 5.72 × 2.25 × 1.67, 2382 | far, stop, sinyal, tepe lambası | var | bulunamadı | %24 | sabit siyah-beyaz boya |
| **Chispa** (rally) | ralli hatchback; compact_pico | 4.02 × 1.97 × 1.62, 2197 | far, stop | var | çift yuvarlak | %49 | kanat, tavan hava girişi, anten |
| **Mula** (van) | panel van; van_porter, utility_brisa | 4.98 × 2.12 × 1.96, 2110 | far, stop | var | tek, sağ arka | %41 | sadece ön yan camlar (yük bölümü kapalı) |

Koltuk ile kabin uyumu (oyundaki koltuk yerleri araç tanımından geliyor, modelden değil):
* 15 tanım–model eşleşmesinin 14'ünde koltuklar camların altındaki kabin aralığında.
* Cresta + pickup_mesa eşleşmesinde koltuk kabinin önünde kalıyor.
* İç mekân eklenince koltuk yerleri her modelin kendi iç düzeninden alınmalı.

## Mevcut sistemler (korunacak)

| Sistem | Nasıl çalışıyor | Bu görevle ilişkisi |
|---|---|---|
| Araç doğurma | `VehicleService`: haritadaki park yerlerinde araçlar; F ile binme; boşta kalan araç yerine döner. Trafikteki araç F ile çalınabilir. | dokunulmayacak |
| Garaj / satın alma / sahiplik | **Yok.** Garaj ekranı sadece katalog gösteriyor ("yakında"). | yok |
| Araç seçme / değiştirme | Ayrı sistem yok: inip başka araca binmek | iç kamera ve gösterge yeni araca bağlanmalı |
| Sürüş fiziği | `CarPhysics` (istemci). Direksiyon girdisi: klavye A/D, gamepad çubuğu, mobil direksiyon pedi → yumuşatılmış `Telemetry.Steer` (−1…1) → ön mafsal servoları. | direksiyon simidi bu değere bağlanacak (başka oyuncuların araçlarında mafsal açısından okunur) |
| Hız / devir / vites | `CarPhysics.Telemetry`: Speed (stud/sn, gerçek fizik hızı), ForwardSpeed, Gear (R/N/1..), RpmNorm. `VehicleDefinitions.ToKmh` var. | gösterge paneli bunları kullanacak |
| Ekran göstergesi | `VehicleHUDController`: hız, devir yayı, vites, sinyal, far, el freni, ABS, TCS, ESC (20 Hz) | aynen kalır. Paneldeki uyarı ışıkları aynı bilgileri kullanabilir |
| Yakıt | **Yok** | yakıt göstergesi eklenmeyecek (görev kuralı) |
| Kamera | `CameraController`. Araçta "Vehicle" kamerası öncelikli. V tuşu (CameraCycle) yürürken OMUZ / TAKİP / GÖZ arasında döner. **Araçta iç kamera yok.** | iç kamera yeni mod olarak eklenecek |
| Mobil arayüz | `MobileControlsController` + `DrivingLayout` (`tools/test_driving_layout.py` 10 ekran boyutunda çakışma denetler). Kamera düğmesi sadece yürürken görünür. | araç düzenine kamera düğmesi eklenecek ve aynı testle denetlenecek |
| Direksiyon simidi (eski) | `VehicleFactory` şasiye basit bir silindir koyuyor (dönmüyor). El hedefleri (HandL/HandR) kullanılmıyor. | modelin iç mekânındaki dönen direksiyonla değiştirilecek |
| NPC trafik | Aynı 12 model istemcide (`TrafficRenderer`, havuzlu). Mobilde onlarca araç olabilir. | iç mekân trafikte daha ucuz olmalı (performans) |

## Sonraki aşamalar için teknik notlar

* **Model değişikliği yeniden yükleme ister.** Yumuşatma ve iç mekân modelin dosyasında yapılır (`SOLARA_Cars.glb`). Sonra `solara_models.sh` arabaları yeniden yükler: soruya **E**. Eski dosya git'te durur.
* **Aşama 2 (yumuşatma):**
  * Gövde boyasında (Paint / Paint2) açı sınırlı normal yumuşatma: belirli bir açının altındaki geçişler yumuşar, bilinçli keskin kenarlar kalır. Üçgen sayısı artmaz.
  * Lastikler 24 köşeli olarak yeniden üretilir: aynı yarıçap, genişlik ve renk, yuvarlatılmış omuz. Jant dış halkası yuvarlanır, kollar korunur.
  * Detail parçalarına (egzoz, ızgara, plaka) ve lamba parçalarına hiç dokunulmaz. Böylece egzozlar ve ışıklar korunur.
  * Siluet low-poly tarzında kalır. Modelin karakteri bu tarz; yüksek poligon yeniden modelleme bu görevin kuralına aykırı.
* **Aşama 3 (iç mekân):**
  * Her araca kendi ölçüsünden üretilen iç mekân: taban, iç kapı panelleri, tavan içi, ön konsol, gösterge paneli, koltuklar, direksiyon, pedallar, vites, ayna.
  * Renkler modelin paletinden; spor, SUV, van ve klasik için farklı düzen.
  * Dönen parçalar (direksiyon, ibreler) ayrı olacak.
  * Hedef: araba başına birkaç parça ve yaklaşık 600–900 üçgen.
* **Aşama 4–6:**
  * Direksiyon simidi Motor6D ile `Telemetry.Steer` değerine bağlanacak.
  * Gösterge ibreleri gerçek hız ve devirle çalışacak (sadece kendi aracında, 20 Hz).
  * İç kamera V tuşu ve mobil düğme ile açılacak.
* Studio yok. Testler önceki gibi çevrimdışı (gerçek kod + Roblox taklitleri) ve sen yayınlayıp oyunda deneyerek.

## Yeniden üretmek
```
python3 -I tools/car_inventory/inventory.py . /tmp/inv.json      # ölçümler
python3 -I tools/car_inventory/classify.py /tmp/inv.json /tmp/cls.json
python3 -I tools/car_inventory/cutaway.py . /tmp/inv.json docs/car_inventory_cutaway.png
python3 -I tools/car_inventory/highlight.py . /tmp/cls.json docs/car_inventory_parts.png
```
