# SOLARA — Aşama 6: Trafik ve yaya yapay zekâsı

Durum: **kod tamamlandı, Roblox Studio'da test edilmedi.** Çevrimdışı testler (gerçek modüller + gerçek harita verisi,
Lua 5.4/lupa; Roblox fiziği ve Luau değil) geçti. Studio testleri yapılmadan aşama tamamlanmış sayılmaz.

Derleme: `place/SOLARA_Phase6_TrafficAI.rbxlx` (Aşama 1–4 + Düzeltme 1–5 + bu aşama)

## Önce incelenenler (MapData / MapDefinitions / RoadBuilder)
* Yol grafiği: 549 düğüm, 919 yol. Sokak 1+1 şerit (50), cadde 2+2 (70), otoyol 2+2 (110), otoyol yolu 2+2 (95),
  kırsal 1+1 (70), rampa tek yön 1 şerit (60). Hız değerleri ≈ km/s ≈ stud/sn.
* Düğüm bayrakları: **211 ışıklı**, 181'i yaya geçitli, **235 dur levhalı** kavşak; 9 rampa birleşmesi; 94 serbest
  (düz devam / köşe) düğüm.
* `RoadBuilder`: kavşak platformu boyutu ve yol kırpması (`planNodes`), şerit çizgileri (sarı orta çizgi, beyaz şerit
  çizgisi, otoyol refüjü), kaldırım (yol kenarından 8 stud, üstü 0.8), köşe kareleri, yaya geçidi çizgileri.
  Trafik grafiği bu kuralların **aynısını** saf Lua'da yeniden kurar → araçlar boyalı şeritlerin ortasından gider,
  geçidin önünde durur.
* **Kaldırım ayrıştırma hatası düzeltildi (kullanıcı onayıyla):** `MapDefinitions` yol bayraklarını bir sütun kaymış
  okuyordu (`f[12]` yerine `f[11]`, köprü aralığı `f[13..14]` yerine `f[12..13]`) → `Edge.Sidewalk` hep false'tu,
  kaldırımlar ve köprü korkulukları hiç inşa edilmiyordu, lamba/bank/parkmetre gibi dekorlar 0.8 stud havada
  duruyordu. Artık 768 yolda kaldırım, kavşak köşe kareleri, yaya geçidi çizgileri ve 7 köprüde korkuluk/ayak oluşur
  (yaklaşık 4800 parça: 1536 kaldırım şeridi, 1804 köşe karesi, 206 kenar dolgusu, 1252 geçit çizgisi, köprü korkulukları). Yaya grafiği bu kaldırımlardan kurulur; kaldırım verisi olmazsa grafik boş kalır ve yaya
  doğmaz ("geçerli yürüyüş yolu olmadan NPC üretme" kuralı, testte doğrulanır).

## Mimari (modüler)
| Modül | Yer | Görev |
|---|---|---|
| `AmbientConfig` | ReplicatedStorage/Modules | **Tüm sınırlar ve ayarlar** (araç/yaya sayıları masaüstü/mobil, yarıçaplar, sürüş modeli, ışık süreleri, yaya saatleri) |
| `TrafficGraph` | ReplicatedStorage/Shared/Ambient | Şerit + kavşak grafiği, bağlantı eğrileri, çatışma haritası, ışık fazları (saf Lua) |
| `PedGraph` | ReplicatedStorage/Shared/Ambient | Kaldırım + geçit grafiği, mola noktaları, A* (saf Lua) |
| `TrafficSim` | ReplicatedStorage/Shared/Ambient | Araç yapay zekâsı (saf Lua) |
| `PedSim` | ReplicatedStorage/Shared/Ambient | Yaya yapay zekâsı (saf Lua) |
| `AmbientController` | StarterPlayerScripts/Controllers | İstemci döngüsü: 10 Hz simülasyon, her karede ara değer, doğurma görünürlüğü, engeller, kaza, LOD |
| `TrafficRenderer`, `PedRenderer`, `SignalRenderer` | StarterPlayerScripts/Ambient | Görseller + havuzlar |
| `AmbientDebug` | StarterPlayerScripts/Ambient | F7 hata ayıklama görünümü |

**Neden istemcide:** NPC'ler her oyuncunun cihazında, oyuncunun çevresinde simüle edilir. Ağ trafiği yok, hareket
akıcı, sınırlar cihaza göre (mobilde daha az). Işıklar sunucu saatine (`GetServerTimeNow`) bağlı → **tüm oyuncular aynı
ışığı görür**; diğer oyuncular ve araçları engel olarak algılanır. Bedeli: her oyuncunun gördüğü NPC araç/yaya farklıdır.

## Trafik
* **Şerit takibi:** sağdan trafik; şerit 1 = içteki, N = kaldırım tarafı. Kavşakta ikinci derece Bezier eğrisi.
  Şerit kuralları: sağa dönüş kaldırım şeridinden, sola dönüş iç şeritten, düz aynı şerit; rampa → otoyolun dış şeridi.
  Her şeridin en az bir çıkışı var (test).
* **Hız:** yol hız sınırı × sürücü çarpanı (0.85–1.05); virajda √(yanal ivme × yarıçap); kavşağa yaklaşırken frene.
* **Sürüş modeli (IDM):** öndeki araç, durma çizgisi, engel ve viraj kısıtlarından en sıkısı → yumuşak hızlanma,
  güvenli duruş (konfor 3 m/s², acil ~0.9 g).
* **Kavşak:** ışık (yeşil/sarı/kırmızı; sarıda duramayacaksa geçer; sola dönüş karşıdan gelene yol verir), dur levhası
  (tam duruş 0.8 sn + geliş sırası), yol ver (rampa ana yola). İzin alan araç bağlantısını **rezerve eder**; kesişen ya
  da aynı şeride birleşen bağlantılar boşalana kadar kimse giremez. Çıkış şeridinde yer yoksa kavşağa girilmez.
* **Engel algılama:** öndeki araç (aynı şerit, sonraki bağlantı/şerit, kavşaktaki komşu eğriler), oyuncular, oyuncu
  araçları (park etmiş dahil), karşıya geçen yayalar — yol eğrisi boyunca ölçülür.
* **Tıkalı yol:** 2.5 sn engel arkasında kalan araç çok şeritli yolda yan şeride geçer; 45 sn hiç ilerleyemeyen araç
  oyuncudan uzaktaysa kaldırılır.
* **Doğurma/kaldırma:** oyuncudan 150–420 stud arasında, geçerli bir şeritte; kameranın gördüğü yerde 320 studdan yakına
  doğmaz (bina arkası serbest); arkadan gelenin fren mesafesi kadar boşluk şartı; 520 studda kaldırılır. Bölge yoğunluğu
  (MapData gündüz/gece) ve saat (gece %45) sayıyı belirler.
* **Görsel:** VehicleDefinitions ailelerinden ~11 parçalı hafif model, havuzdan; fren lambası, gece farlar.
* **Kaza:** oyuncunun aracı NPC araca hızla çarpacaksa NPC fiziğe geçer (bu istemcide savrulur), sonra havuza döner.
* **Işık direkleri:** ışıklı kavşaklarda her yaklaşımın sağ köşesine (320 stud içinde, havuzdan).

## Yayalar
* **Kaldırımda yürüme:** kaldırım ortası ±2.6 stud; köşe kareleri ve kapalı kenar dolguları üzerinden blok çevresi.
* **Karşıya geçiş:** sadece kavşak platformunun açık kenarlarında (yaya geçidi çizgilerinin yeri). Işıklıda yaya yeşili
  (kolun trafiği kırmızı, diğer faz yeşil ve süre yetiyor); ışıksızda kolda yaklaşan araç yokken; geçit üstünde/yanında
  araç varken başlamaz; 25 sn bekleyen vazgeçer.
* **Gün içi davranış:** saate göre yoğunluk ve mola (sabah işe gidiş, öğle yoğun, gece seyrek); hedef = dükkân girişi,
  bank, otobüs durağı ya da rastgele kaldırım noktası (A*); varınca mola.
* **Kaçınma:** karşılaşınca sağa kayma, öndekine yetişince yavaşlama, oyuncuya yol verme, kaldırıma hızla gelen oyuncu
  aracından uzaklaşma, araç gövdesine yürümeme.
* **Görsel:** 7 parçalı model (Humanoid yok), Motor6D ile ucuz yürüme salınımı; 90 studdan uzakta animasyon kapalı.

## Performans
* Sınırlar (AmbientConfig): araç 24 / mobil 12, yaya 32 / mobil 14; simülasyon 10 Hz; görüntü ara değerli.
* Uzaktaki (yarıçap dışı) NPC simüle edilmez, kaldırılır ve modeli havuza döner (yeniden kullanılır).
* Grafik kurulumu karelere yayılır (yaklaşık 40 ms, Lua 5.4'te ölçüldü).
* Çevrimdışı ölçüm (Lua 5.4, Luau değil): 24 araç + 32 yaya, adım başına trafik ~0.12 ms, yaya ~0.3 ms.
* Studio'da yapılması gereken: MicroProfiler'da `Heartbeat` süresi, mobilde FPS.

Çalışma anında sınır değiştirme (Studio testi için Workspace attribute'u): `AmbientEnabled` (false = kapalı),
`AmbientMaxVehicles`, `AmbientMaxPedestrians`.

## Hata ayıklama (F7)
Şerit merkezleri (mavi), kavşak eğrileri (yeşil), durma çizgileri (ışık rengi / dur beyaz / yol ver turuncu),
kaldırım çizgileri (beyaz), geçitler (yaya yeşilinde yeşil), araç etiketi `#id durum hız` (Sür / Kırmızı / Sarı / Dur /
Sıra / Çakışma / Dolu / Engel / SolDönüş / YolVer / Yol sonu), yaya etiketi (Yürü / Bekle / Geç / Mola) ve istatistik
paneli (sayılar, havuzlar, adım süresi, doğan/kalkan/reddedilen, kavşak geçişi, şerit değiştirme, tıkalı araç, yaya
geçişi, ışık direği, saat, yoğunluk, en yakın kavşağın faz durumu).

## Çevrimdışı test (`python3 tools/test_ambient.py <lupa>`)
Gerçek modüller + gerçek MapData. Sonuçlar raporda (bkz. "Sonuçlar"). Kapsam: şerit grafiği, kaldırım grafiği,
oyundaki bugünkü veri (yaya 0), şehir merkezi 10 dk, 5 ek rastgele tohum, tıkalı şerit, yoldan geçen oyuncu,
hareket eden oyuncu, iki oyuncu, gece/öğle.

## Sonuçlar (çevrimdışı, `tools/test_ambient.py`: RESULT: PASS)
| Senaryo | Sonuç |
|---|---|
| Şerit grafiği | 2276 şerit, 4991 kavşak bağlantısı; çıkışsız şerit 0; ışık 211 / dur 235 / yol ver 9; kurulum ~40 ms |
| Kaldırım grafiği | 4874 düğüm, 6406 bağlantı, 1598 geçit (hepsi kavşak platformunda); yol üstünde yürüme örneği 0; 9 semt ağı; 63 mola noktası |
| Kaldırım verisi yoksa | yaya grafiği boş, doğan yaya 0 |
| Şehir merkezi, öğle, 10 dk | 24 araç / 32 yaya; 1208 kavşak geçişi, 409 yaya geçişi; araç-araç çakışma 0, yayaya çarpma 0, kırmızıda giriş 0, yaya kırmızıda geçiş 0, yol üstünde yaya 0, rezervasyon sızıntısı 0, 90 sn'den uzun takılan 0 |
| 5 ek rastgele tohum × 4 dk (+10 tohum ayrı denemede) | hepsi 0 çakışma / 0 çarpma / 0 kırmızı / 0 takılma |
| Tıkalı şerit (park etmiş araç 2 dk) | araçlar arkasında durdu, yan şeride geçti; içinden geçen 0 |
| Yoldan geçen oyuncu | oyuncuya çarpan 0 |
| Hareket eden oyuncu (~2 km tur) | doğma/kaldırma çevrimi sorunsuz, çakışma 0 |
| İki uzak oyuncu | iki oyuncunun çevresinde de araç (son anda 7 / 17), çakışma 0 |
| Gece 02:00 / öğle | en fazla yaya 3 / 32 |
| Adım maliyeti (Lua 5.4) | trafik ~0.12–0.16 ms, yaya ~0.25–0.30 ms (10 Hz) |

Geliştirme sırasında testlerin yakaladığı ve düzeltilen hatalar: düz birleşimde sıfır uzunluklu kavşak eğrisinde yönün
(0,0) olması; araç boyundan kısa şeride hiç girilememesi (kilitlenme); aynı şeritten ayrılan eğrilerde arkadakinin
öndekini görmemesi; hızlı gelen aracın önüne doğma; yayanın duran araca yürümesi; karşılıklı sola dönenlerin kavşak
ortasında birbirini beklemesi (kilitlenme); karşılıklı sola dönüş eğrilerinin gövde sürtecek kadar yakın geçmesi;
şerit değiştirirken hedef şeritteki engel ve arkadan gelenin görülmemesi; şerit sayısı azalan serbest düğümlerde
birleşmenin korumasız olması.

## Studio test senaryoları (zorunlu)
1. **Kavşaklar:** ışıklı bir caddede bekle (F7 açık): kırmızıda duran, yeşilde geçen, sarıda duramayacaksa geçen
   araçlar; sola dönenlerin karşıdan gelene yol vermesi; dur levhalı kavşakta tam duruş ve sıra.
2. **Tıkalı yol:** aracını bir caddenin sağ şeridine park et, in → arkadakiler durmalı, iki şeritli yolda yan şeride
   geçmeli; tek şeritli sokakta beklemeli (45 sn sonra uzaktakiler kaldırılır).
3. **Oyuncu yakınlığı:** yürüyerek yola çık → araçlar durmalı; araçla NPC araca çarp → NPC savrulmalı.
4. **Birden çok oyuncu:** Studio "Local Server + 2 oyuncu": iki oyuncu farklı yerlerde; her birinin çevresinde trafik;
   ışıklar iki ekranda aynı anda aynı renk; diğer oyuncunun arabasının önünde NPC'ler durmalı.
5. **Doğurma:** ekranın ortasında araç "belirmemeli"; uzaklaşan araçlar görüş dışında kaybolmalı.
6. **Gece:** saat 20:00 sonrası daha az trafik, farlar açık.
7. **Mobil (Device Emulator + gerçek cihaz):** 12 araç sınırı, FPS.
8. **Yayalar:** kaldırımlar oluşmuş olmalı (merkezde sokak kenarları); yayalar kaldırımda yürümeli, geçitte yaya
   yeşilini beklemeli (F7: geçit yeşil/turuncu), dükkân/bank/durak önünde mola vermeli, oyuncuya yol vermeli,
   kaldırıma çıkan oyuncu aracından kaçmalı.
9. **Dünya değişikliği (kaldırım düzeltmesi):** sokak kenarlarında kaldırım ve 0.5 stud bordür; köprülerde korkuluk;
   lamba/bank/parkmetre kaldırıma oturmuş; sunucu çıktısındaki `[WorldGen] Dünya hazır: … parça` sayısı ~4800 artmış.

## Bilinen sınırlamalar
* 108 park noktasından 12'si yeni kaldırımın üstüne denk geliyor: o oyuncu araçları kaldırımda park etmiş görünür
  ve yayalar oradan geçerken araca yaklaşır (harita verisi; ayrı düzeltme gerekir).
* NPC'ler oyuncuya özel (çok oyunculu oyunda herkes farklı NPC görür; ışıklar ortak).
* NPC araçlar sabit (Anchored) hareket eder: oyuncu çok yavaş itince NPC araç itilmez (hızlı çarpışmada fiziğe geçer).
* Semtler arası çevre yollarında haritada kaldırım yok → yayalar kendi semtinin kaldırım ağında kalır (9 ayrı ağ).
* Şerit değiştirme sadece tıkanınca; sollama yok. Sinyal lambası, korna, park eden NPC yok.
