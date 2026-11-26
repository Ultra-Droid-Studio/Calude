# SOLARA — Yaşayan Şehir: mevcut sistem analizi ve uygulama planı (Bölüm 1)

Durum: **sadece analiz; oyun kodu değiştirilmedi.** Sayılar, mevcut modüllerin gerçek harita verisiyle çevrimdışı
çalıştırılmasından (tools/test_ambient.py altyapısı, Lua 5.4) ve kod incelemesinden gelir; Roblox Studio'da ölçülmedi.

## 1. Mevcut sistem (Aşama 6 + araba paketi)
| Konu | Bugünkü durum | Dosya |
|---|---|---|
| Görev dağılımı | Trafik ve yayalar **tamamen istemcide**, oyuncunun çevresinde; sunucuda NPC yok, ağ trafiği yok. Işıklar sunucu saatine bağlı (herkes aynı ışığı görür). | Controllers/AmbientController |
| Trafik yolları | MapDefinitions yol grafiğinden şerit + kavşak grafiği (2276 şerit, 4991 kavşak eğrisi), RoadBuilder ile aynı geometri | Shared/Ambient/TrafficGraph |
| Araç hareketi | IDM takip modeli, 10 Hz karar adımı + her karede ara değer; ışık/dur/yol ver, rezervasyon, engel, şerit değiştirme | Shared/Ambient/TrafficSim |
| Araç modelleri | Quaternius CC0 modelleri (Studio'da içe aktarılınca) yoksa ~11 parçalı kutu model; havuzlu | Ambient/TrafficRenderer, Shared/CarModelKit |
| Yaya yolları | Kaldırım grafiği (4874 düğüm, 6406 bağlantı, 1598 geçit), A* (PathfindingService kullanılmıyor) | Shared/Ambient/PedGraph |
| Yaya davranışı | Hedefli yürüyüş (mola noktası ya da rastgele kaldırım düğümü), geçitte ışık/boşluk bekleme, kaçınma | Shared/Ambient/PedSim |
| Yaya modeli | 7 parçalı kutu insan (Humanoid yok), Motor6D ile kol/bacak salınımı | Ambient/PedRenderer |
| Doğurma/kaldırma | Araç: 150–420 stud halkasında rastgele şerit (yol türüne göre ağırlık yok), 520'de kaldırma. Yaya: 45–190 halkasında rastgele kaldırım, 230'da kaldırma. Kaldırma **görünürlüğe bakmaz**. | TrafficSim / PedSim |
| Sınırlar | Araç 24 (mobil 12), yaya 32 (mobil 14) | Modules/AmbientConfig |

## 2. Sorulara cevaplar (ölçümle)
### Trafikte neden az araç var?
* Üst sınır 24 araç, 150–420 studluk halkada yaklaşık 16 200 stud şerit var → **100 stud şerit başına 0.15 araç**
  (≈ her 660 studda bir araç). Gerçek şehir trafiği 100 studda 3–6 araç civarıdır.
* Yol türüne göre ağırlık yok: ana cadde ile ara sokak aynı olasılıkla seçiliyor.
* Gece katsayısı 0.45, bölge yoğunluğu çarpanı (yerleşim alanlarında 0.5–0.6) sayıyı daha da düşürüyor.

### Araçlar neden yavaş?
* Ortalama hız **11 stud/sn** (~11 km/s), ortanca 7, en hızlı %10: 30. Hız sınırları 50 (sokak) / 70 (cadde).
* Araç zamanının **%34'ü duruşta**; duruşların **%76'sı kırmızı ışıkta**, %10 engel (karşıya geçen yaya), %9 kavşak
  çakışma beklemesi.
* Şehir merkezinde neredeyse her kavşak ışıklı ve bloklar kısa (~100–150 stud). Işık döngüsü 37 sn, her yön ~23 sn
  kırmızı; kavşaklar arasında **eşgüdüm (yeşil dalga) yok**.
* İvme 9 stud/sn² (~2.5 m/s²): 50'ye çıkmak ~155 stud sürüyor → araç blok içinde hıza ulaşamadan frene geçiyor.

### Tepki süresi uzun mu?
* Karar adımı 10 Hz (100 ms); öndeki araç kalkınca arkadakinin kalkması ortalama **0.64 sn**. Takip süresi 1.3 sn,
  duruş mesafesi 6 stud. Konforlu ama "ağır" bir sürüş.

### Yaya sayısı neden az?
* Sınır 32 (mobil 14) ve 45–190 halkasında; yayaların **%30'u geçitlerde bekliyor** (rotalar sık sık karşıya geçiyor),
  yalnızca %55'i yürüyor, mola %1.

### Yayalar nerede doğuyor, rastgele mi yürüyor?
* Görüş dışındaki rastgele bir kaldırım noktasında doğuyor; bina kapısından çıkmıyor.
* Rastgele değil: her yayanın bir hedefi var (mola noktası ya da kaldırım düğümü, A* rota). Ama **binaya giren/çıkan
  yok**, ev/iş gibi bir amaç yok.

### Animasyonlar doğru mu?
* Gerçek animasyon yok: kol/bacak sinüs salınımı. Dönüş/durma/kalkış geçişi yok.
* Köşelerde yön **tek adımda** değişiyor: 100 ms'de 180°'ye kadar dönüş ölçüldü (köşe başına ani dönüş = istenmeyen
  "90 derece dönüp kayma").
* Model kutulardan; yüz/el/ayak/saç/kıyafet yok, herkes aynı kalıp.

### Bina kapıları belirlenebiliyor mu?
* **Evet.** 1333 arsanın her biri merkez, boyut ve dönüşle tanımlı; bina önü (yerel −Z) sokağa bakıyor ve ön cephe
  kaldırıma yaklaşık 3 stud uzakta. Bahçeli evlerde kapı cephesi stile göre hesaplanabiliyor. 90 önemli yerin haritada
  hazır giriş noktası var.
* Fiziksel kapı parçası sadece 1 stilde var (tuğla apartman); diğerlerinde cephe düz.

### Mobilde ne kadar kaynak?
* Simülasyon hesabı küçük (Lua 5.4'te adım başına trafik ~0.12 ms, yaya ~0.3 ms; 10 Hz).
* Asıl maliyet çizim: 24 araç × ~15 MeshPart + 32 yaya × 7 parça, her karede ~56 kök CFrame + uzuv yazımı.
* Cihazda ölçülmedi.

### Ani kaybolma riski
* Yaya tam 230 studda, araç 520 studda kaldırılıyor; ikisinde de görünürlük kontrolü yok → uzun düz caddede ekranda
  kaybolabilir.

## 3. Uygulama planı (mevcut sistem korunarak, modül modül)
### A. Trafik yoğunluğu (2.1)
* **Yoğunluk profili:** Düşük / Normal / Yüksek; varsayılan Normal–Yüksek arası. Hedef = şerit uzunluğu × yol türü
  katsayısı × bölge/saat yoğunluğu (cadde 1.0, otoyol 0.8, sokak 0.45, kırsal 0.2); cihaz bütçesiyle sınırlı.
* **İki kademeli simülasyon (LOD):**
  * Yakın (≤ 250 stud): tam davranış, 20 Hz.
  * Uzak (250–600 stud): aynı kurallar, 4 Hz ve sade model (havuzdan).
  * Böylece görünen araç sayısı 3–4 kat artar, maliyet sınırlı kalır.
* **Bütçeler (öneri):** Masaüstü ~70 araç (Yüksek 100), tablet ~40, telefon ~28.
  * Kare süresi bütçeyi aşarsa sayı otomatik azalır (uyarlanır kalite).
* **Doğurma:** cadde ağırlıklı; görüş dışında ya da şehir ufkunda; ilk girişte perde arkasında şehir doldurulur.
* **Kaldırma:** sadece görüş dışında, ekranda kaybolma olmaz.
* **Ayarlar menüsü:** "Şehir yoğunluğu" seçeneği (Düşük/Normal/Yüksek).

### B. Hız ve dur-kalk (2.2, 2.3)
* İvme 9 → ~13, konfor freni 11 → ~14, takip süresi 1.3 → 1.0 sn, duruş mesafesi 6 → 4.5, karar 10 → 20 Hz (yakında).
* Ani ivme değişimi sınırı (jerk limit) eklenecek: titreme ve ileri-geri zıplama olmaz. Hafif gövde eğilmesi (fren/kalkış) eklenecek.
* **Işık eşgüdümü:**
  * Cadde fazına daha uzun yeşil (ör. 22/12 sn).
  * Caddeler boyunca ofsetli "yeşil dalga": aynı yönde giden araçlar art arda yeşile denk gelir.
* Viraj güvenli hızı 9 → 12.
* Sebepsiz bekleme bekçisi: görünür nedeni olmadan bekleyen araç yeniden değerlendirilir.
* **Hedef metrikler (çevrimdışı test):**
  * Hareket halindeyken cadde ortalaması ≥ 35, genel ortalama ≥ 20.
  * Duruş payı ≤ %25, kalkış gecikmesi ≤ 0.35 sn.
  * Çakışma, çarpma ve kırmızıda geçiş 0.

### C. Kavşak (2.4)
* Mevcut rezervasyon/çakışma sistemi korunur.
* Tıkalı yol varsa bir sonraki kavşakta başka çıkış seçme eklenecek.
* Çakışma eşiğinin (7.5) gereksiz beklemeye yol açtığı yerler ölçülüp ayarlanacak (şu an duruşların %9'u).

### D. Araç çeşitliliği (2.5)
* Quaternius modelleri (sedan, hatchback/kompakt, SUV, spor, taksi) + ticari için kutu pikap/van/servis.
* Bölgeye göre karışım: merkezde taksi, sanayide pikap/van.
* Model başına kontrollü renk paletleri.
* Ticari araç modeli pakette yok → istersen ikinci bir CC0 paket.

### E. Yaya yoğunluğu ve davranışı (3.1, 3.2)
* Bütçeler (öneri): masaüstü ~90 (Yüksek 130), tablet ~50, telefon ~35. LOD:
  * ≤ 60 stud: tam animasyon.
  * 60–150 stud: seyrek güncellenen animasyon.
  * 150–260 stud: animasyonsuz sade model.
* **Doğma/kaybolma:** çoğunlukla bina kapılarından çıkarak ve kapılara girerek; görüş dışı kaldırma. Ani belirme/kaybolma azalır.
* **Amaçlı yaşam döngüsü (saate göre):** ev → iş/dükkân → ev; meydan, bank ve durakta mola. Geçit beklemesini azaltmak için rota maliyetine bekleme payı eklenecek.
* **Doğal hareket:**
  * Köşeler yuvarlanarak dönülür; dönüş hızı sınırlı (~270°/sn).
  * Duruş ve kalkış ivmeli.
  * Hız-animasyon senkronu.
  * Yayalar arası kaçınma iyileştirilecek (hıza göre öngörülü).

### F. Animasyon ve modeller (3.3, 5) — karar gerekiyor
| Seçenek | Ne | Artı | Eksi |
|---|---|---|---|
| **1 (öneri)** | Kodla kurulan **R15 uyumlu** insan + Roblox'un hazır varsayılan R15 animasyonları (idle/walk/run) | Hemen çalışır, yükleme gerekmez; insan oranları, el/ayak/yüz; saç, şapka, kapüşon, ceket, çanta çeşitleri (renkli düşük poligon parçalar) | Roblox tarzı, "gerçekçi" değil; özel animasyon yok |
| 2 | Dış **CC0 riglenmiş/animasyonlu** insan paketi (ör. Quaternius karakter paketleri) | Daha gerçekçi model ve özel animasyonlar | Senin Studio'da içe aktarıp animasyonları Roblox'a yüklemen gerekir |
| 3 | Roblox avatar kataloğu (HumanoidDescription) | En "Roblox" görünüm, çok çeşit | Katalog kimliklerini sen vermelisin; aksesuarlar mobilde ağır |

* İstenen 8 animasyondan Roblox'un hazır setinde **sadece Idle ve Walk** var.
* Turn, Stop ve StartWalking: harmanlama (hız rampası + yumuşak geçiş + gövde eğilmesi) ile yapılır.
* DoorApproach, EnterBuilding ve ExitBuilding: kapıya yönelme + yavaşlama + kapı açılması + eşikten geçerken kararma ile yapılır.
* **Gerçek özel animasyonlar** (kapı kolu tutma vb.) çizilip Roblox'a yüklenmeli: bunu 2. seçenekte senin hesabınla yapabiliriz.

### G. Binaya giriş/çıkış (4)
* **Giriş noktası kayıt sistemi:** her bina için `BuildingEntrance` (kapı merkezi + dışa normal + kaldırım bağlantısı); evlerde bahçe yolu, dükkânlarda haritadaki giriş. Arsa verisinden hesaplanır, harita değişmez.
* **Kapı görseli:** düz cephelerde kapı yok. İki yol var:
  * (a) Sadece oyuncunun yakınında istemcide kapı modeli (havuzlu, trafik ışıkları gibi; açılıp kapanır, dünya değişmez).
  * (b) Bina üretiminde kalıcı kapı (dünya oluşturma değişikliği).
  * **Öneri: (a).**
* **Davranış:**
  * Girerken: yaklaşma → kapıya dönme → bekleme → kapı açılır → eşikten geçerken kararma → kapı kapanır.
  * Çıkarken tersi.
* Duvar içine yürüme yok: kapı noktası cephenin hemen dışında; geçiş kapı boşluğunda.

### H. Performans (6)
* Mevcut havuzlama korunur.
* **Güncelleme sıklığı:** mesafe ve görüşe göre (yakın 20 Hz, uzak 4 Hz, ekran dışı 2 Hz).
* **Rota:** A* sonuçları önbelleğe alınır, aynı hedefe tekrar hesaplanmaz; tik başına rota sınırı.
* **Animasyon LOD:** uzaktaki yayada animasyon durur.
* **Uyarlanır kalite:** FPS düşerse yoğunluk otomatik azalır.
* **Bellek:** model sayısı havuzla sınırlı. Uzun koşuda nesne sayısı izlenecek (test).

### I. Test (7)
* **Çevrimdışı (gerçek modüller + harita):** yoğunluk (100 stud başına araç/yaya), hız dağılımı, duruş nedenleri, kalkış gecikmesi, çakışma/çarpma/kırmızı 0, yaya geçiş/kapı giriş-çıkış sayıları, görüş içinde kaybolma 0, 30 dk kararlılık (nesne sayısı sabit), adım maliyeti.
* **Studio'da (senin):** mobil/tablet FPS (MicroProfiler), animasyon görünümü, kapı geçişleri, uzun oyun kararlılığı.

## 4. Kararlar (senden)
1. NPC modeli/animasyon: Seçenek 1 (öneri), 2 ya da 3?
2. Kapılar: (a) istemcide kapı modeli (öneri) ya da (b) dünya üretimine kalıcı kapı?
3. Bütçeler ve varsayılan yoğunluk (yukarıdaki öneriler) uygun mu?
4. Ticari araç modeli için ikinci bir CC0 paket gönderecek misin, yoksa kutu pikap/van kalsın mı?

## 5. Uygulama sırası (onaydan sonra)
1. Trafik: yoğunluk + LOD + hız/dur-kalk + ışık eşgüdümü (+ test)
2. Yaya: yoğunluk + LOD + doğal hareket (+ test)
3. Bina giriş/çıkış sistemi (+ test)
4. NPC modelleri ve animasyon (seçilen seçenek)
5. Performans uyarlaması, ayarlar menüsü, rapor
