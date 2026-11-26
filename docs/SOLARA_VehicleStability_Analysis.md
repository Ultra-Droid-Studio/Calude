# SOLARA — Araç fizik kararlılığı: analiz (kod değişmedi)

Kapsam: sadece oyuncunun kullandığı otomobil ve motosikletler. NPC trafiği, trafik yoğunluğu ve NPC sistemi bu
çalışmanın dışında. Analiz kod okuma, harita verisi üzerinde geometri hesabı ve fizik hesabıyla yapıldı.
**Roblox fiziği burada çalıştırılamıyor; Studio'da gözlem yapılmadı.**

## 1. Mevcut fizik yapısı
| Konu | Durum |
|---|---|
| Koltuk / kontrol | `Seat` (VehicleSeat değil). Sürüş tamamen kendi kodumuz: otomobil `CarPhysics` (her fizik adımından önce, `PreSimulation`), motosiklet `VehicleController.driveStep` (`Heartbeat`, Aşama 2 öncesi eski model). |
| Fizik nerede | Sürücü binince sunucu tüm fizik parçalarının ağ sahipliğini sürücüye verir → fizik **sürücünün istemcisinde**. Sürücü yokken sunucu: park freni, sabitleme (anchor). Aynı anda kuvvet yazan ikinci bir script bulunmadı. |
| Montaj kökü | Şasi (otomobilde `RootPriority = 10`). Tekerler ve mafsallar ayrı montajlar, şasiye kısıtlarla bağlı. |
| Kütle | Otomobil: şasi + balast (ağırlık dağılımı), görseller ve sürücü kütlesiz. Teker yoğunluğu 0.9, mafsal = teker × 0.4. |
| Ağırlık merkezi | Otomobilde alçak (statik devrilme oranı ~2, gerçek araçlarda 1.2–1.5): devrilme riski yok. Motosiklette aks yüksekliğinde. |
| Kısıtlar | Teker başına: `CylindricalConstraint` (süspansiyon kayıcısı + direksiyon servosu), `SpringConstraint` (yay + amortisör), `HingeConstraint` motor (çekiş/fren, `MotorMaxAcceleration = ∞`). |
| Kuvvetler | `VectorForce`: otomobilde şasi, teker ve mafsala yerçekimi telafisi (etkin yerçekimi 42) + hava direnci; `Torque`: savrulma denge yardımı; `AlignOrientation`: motosiklette sürekli (dik durma/yatış), otomobilde sadece havadayken. |
| Eski fizik nesneleri | `BodyVelocity`/`BodyGyro` vb. yok; `LinearVelocity`/`AngularVelocity` kısıtı yok. |
| Fizik adımlama | `Workspace.PhysicsSteppingMethod` yer dosyasında kayıtlı değil (varsayılan). |

## 2. Arabalar neden titriyor (kanıtla)
### A. Yolda tekerin çarptığı basamaklar (asıl neden)
Yolun kendisi pürüzsüz değil; fizik tekerleği sert bir silindir olduğu için her küçük basamak tekere dikey bir darbe
verir. Darbe hızla doğrusal büyür: dikey hız ≈ v·√(2h/R).

1. **Şerit çizgileri ve yaya geçidi şeritleri çarpışmalı parça ve yoldan 0.03 stud yüksek**
   (`RoadBuilder`: `LINE_T = 0.06`, `LINE_LIFT = 0.03`; `Kit.Box` varsayılanı `CanCollide = true`).
   Her kavşakta kol başına 2 enine yaya geçidi şeridi var (merkezde ~116 studda bir kavşak); şerit değiştirirken ve
   orta çizgiye yaklaşırken boyuna çizgilere tırmanılıyor (yan darbe → sağa sola sarsılma).
2. **Otoyol rampaları ve bazı kavşak platformları ile yol arasında 0.19–1.29 studluk basamak (49 birleşim):**
   eğimli yol kırpılıp düz platforma/tabliyeye bağlanırken yolun ucu kendi eğimiyle alçalıyor.
   16 rampa→otoyol tabliyesi (−0.53), 16 rampa→birleşim platformu (−0.66), 16 (+0.19), 1 otoyol platformu (1.29).
   Diğer 1678 birleşim düz (basamak < 0.02).
3. **Otoyol köşelerindeki disk platformlar yoldan 0.06 stud aşağıda** (30 birleşim, `Cylinder … − 0.06`).

Tekerin aldığı dikey darbe (stud/sn), 0.03'lük çizgi için:

| Araç | 30 | 50 | 70 | 100 |
|---|---|---|---|---|
| Vela (sedan) | 6.1 | 10.2 | 14.2 | 20.3 |
| Rayo GT | 6.0 | 10.0 | 14.0 | 20.0 |
| Terra (SUV) | 5.6 | 9.3 | 13.0 | 18.5 |

Darbeyi alan teker, süspansiyonu yukarıda dibe vurana (sert sınır, `Restitution 0`) kadar yükselir; dibe vurunca
darbe doğrudan gövdeye geçer. Tahmini dibe vurma eşiği (süspansiyon sönümü / teker kütlesi / üst kurs payı):

| Araç | 0.03 çizgi | 0.06 disk | 0.53 rampa |
|---|---|---|---|
| Rayo GT | ~44 | ~31 | ~10 |
| Terra, Vela | ~48–49 | ~34–35 | ~11–12 |
| Mesa | ~53 | ~37 | ~12 |
| Pico, Porter, Brisa | ~63–64 | ~44–46 | ~15 |

(stud/sn ≈ göstergedeki km/s.) **Titreme yaklaşık 45–65 hızın üstünde başlar**; rampalarda neredeyse her hızda sert
vuruş olur. Bu, "belli bir hıza kadar normal, sonra titriyor" gözlemiyle uyumlu. Darbe sırasında teker yerden kesilir,
tutuş kaybolur; denge yardımı ve otomatik karşı direksiyon tepki verir → savrulma.

### B. Darbeyi büyüten değerler
* **Teker kütlesi çok yüksek:** yaysız kütle toplamın %31–40'ı (gerçek arabada ~%10–15). Ağır teker darbede daha çok
  momentum taşır, yere daha geç döner. (Mafsal kütlesi Hata düzeltme 3'te çözücü kararlılığı için artırılmıştı;
  bu yüzden bunu ilk adımda değiştirmeyi önermiyorum.)
* **Otomatik karşı direksiyon hız sınırını aşabiliyor:** yüksek hızda direksiyon ~5°'yle sınırlı, ama karşı direksiyon
  bunun üstüne MaxSteer'in yarısına (15–17°) kadar ekleniyor. Darbe sonrası kayma → büyük karşı direksiyon →
  ters yöne savrulma (`CarPhysics` adım 2).
* **Pikapta kayma eşiği = çekiş kontrolü payı (0.22 = 0.22):** tam gazda arka tekerler sürekli "kayıyor/tutuyor"
  arasında gidip geliyor; tutuş %18 iniyor, karşı direksiyon devreye giriyor.
* **Fizik adımlama sabit değil:** yer dosyasında ayarlı değil. Uyarlanır adımlamada hızlı ve kısıtlı montajlar daha
  seyrek hesaplanabilir; sert yay/servo/darbe durumunda kararsızlığı artırır. (Roblox'un bugünkü varsayılanını
  buradan doğrulayamıyorum.)

Sorunlu olmayanlar: yay frekansları (1.2–2.3 Hz) ve sönüm (ζ 0.33–0.5) gerçekçi; ağırlık merkezi alçak; denge torku
ve karşı direksiyon işaretleri doğru; motor/fren torkları tutuş sınırının altında; iki scriptin aynı anda kuvvet
yazması yok.

## 3. Motosikletin arka tekeri neden kalkıyor / denge bozuluyor
Motosiklet Aşama 2'deki otomobil düzeltmelerini hiç almadı (eski sürüş adımı). Bulunanlar:

1. **Aynı yol basamakları + daha küçük tekerler** (R 0.9–1.3): darbe daha büyük; 100 hızda ~22 stud/sn.
2. **Arka tekerde çekiş kontrolü yok:** motor hedefi her zaman *azami hız / R* (`driveVelocity = sign·MaxSpeed/R`)
   ve `MotorMaxAcceleration = ∞`. Arka teker bir an yükünü kaybedince (basamak, tümsek) motor onu anında azami
   hıza döndürür; yere bu fazla hızla değince boyuna patinaj yapar, Coulomb sürtünmesinde yanal tutuş kalmaz → arka
   kayar, motosiklet dengesini kaybeder. Yük kaybı ne kadar sık olursa (hız arttıkça) o kadar sık tekrarlar:
   "bir süre ilerledikten sonra" gözlemiyle uyumlu.
3. **Fren kilitler (ABS yok):** fren motorları hedefi 0 rad/sn; frende ağırlık öne geçince arka teker kilitlenip kayar.
4. **Zorla yatırma çok sert:** `AlignOrientation` torku toplam ağırlık × 196 × 60 (gerekenin ~85 katı),
   `Responsiveness 30`; yatış hedefi klavyede ~0.3 sn'de ±40°'ye sıçrıyor. Gövde çok hızlı yuvarlanınca dar silindir
   tekerler kenarına basar ve yanal sürtünür, tekerleri yerden kaldırabilir.
5. **Motosiklet telemetrisi yok:** F4 paneli sadece otomobil gösteriyor; Studio'da neyin olduğunu ölçecek araç yok.

Kesin kanıtlanamayan: "arka teker havaya kalkıyor" anının tam mekanizması (2 ve 4'ün payı). Bunu ancak Studio'da
telemetriyle görebiliriz; bu yüzden plana motosiklet telemetrisi ekledim.

## 4. Sorumlu dosyalar
* `ServerScriptService/WorldGen/RoadBuilder.lua`: çarpışmalı çizgiler, rampa/platform basamakları, disk platform
  çukuru.
* `StarterPlayer/StarterPlayerScripts/Controllers/VehicleController.lua` (`driveStep`): motosiklet motor/fren hedefleri
  ve yatış.
* `ServerScriptService/Vehicles/VehicleFactory.lua`: motosiklet `AlignOrientation` torku, teker/mafsal kütleleri.
* `StarterPlayer/StarterPlayerScripts/Vehicles/CarPhysics.lua`: karşı direksiyon sınırı, kayma eşiği.
* Yer dosyası (`tools/place_patches.json`): fizik adımlama yöntemi.

## 5. Önerilen düzeltme (en güvenli sıra; onaydan sonra)
**Yol (dünya üretimi; yol düzeni ve görünüm aynı kalır):**
* R1. Şerit çizgileri ve yaya geçidi şeritleri `CanCollide = false` (bariyerler çarpışmalı kalır).
* R2. Kırpılan yol ucunun yüksekliği bağlandığı platform/tabliye yüzeyine eşitlenir → 49 basamak kalkar (diğer
  birleşimler zaten düz, değişmez).
* R3. Disk platform yolla aynı seviyeye alınır (−0.06 → 0; Studio'da görsel titreşim kontrolü gerekir).
* Not: NPC trafiğinin şerit yükseklikleri değiştirilmez (trafik sistemine dokunulmaz). Bu 49 birleşimde NPC araçlar
  birkaç stud boyunca yolun ~0.5 stud altında/üstünde görünebilir; istersen sadece bu yükseklikleri hizalarım
  (davranış değişmez).

**Araba:**
* C1. Fizik adımlama sabit (`PhysicsSteppingMethod = Fixed`, 240 Hz).
* C2. Otomatik karşı direksiyon hız sınırını en fazla ölçülen kayma açısı kadar aşabilir.
* C3. Kayma algılama eşiği her araçta çekiş kontrolü payının üstünde (sadece pikapı etkiler).
* Yay, sönüm, ağırlık merkezi, azami hız, ivme, fren: **değişmez** (sorunlu bulunmadı; sürüş hissi korunur).
  Teker kütlesi: yol düzeltmesinden sonra Studio'da hâlâ sıçrama görülürse ikinci adımda.

**Motosiklet:**
* M1. Arka tekere çekiş kontrolü: hedef = yer hızı + izinli patinaj (otomobildeki mantık); tork değişmez.
* M2. ABS: frenlenen teker yer hızının %90'ının altına inmez.
* M3. Yatış hedefi saniyede en fazla ~85° değişir; `AlignOrientation` torku gerekenin ~12 katına, tepkisi 30 → 18
  (yatış ve dik durma korunur, yeni bir dengeleme eklenmez).
* M4. F4'e motosiklet telemetrisi: ön/arka temas, arka teker yüzey hızı ↔ yer hızı, burun açısı, yatış hedefi/gerçek.

**Test:** yol basamakları çevrimdışı ölçülür (düzeltmeden sonra 0 olmalı) ve testlere eklenir. İstenen 10 sürüş
testini Roblox fiziği gerektirdiği için ancak sen Studio'da yapabilirsin (F4 telemetrisiyle); başarılı diye
raporlamayacağım.
