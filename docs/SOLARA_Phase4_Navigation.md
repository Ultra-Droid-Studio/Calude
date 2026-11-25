# SOLARA — Aşama 4: Mini harita ve GPS navigasyon

Durum: **kod tamamlandı, Roblox Studio'da test edilmedi.** Aşağıdaki Studio testleri geçmeden bu aşama
tamamlanmış sayılmaz. Çevrimdışı doğrulamalar (gerçek `Navigation.lua` + gerçek harita verisi) geçti.

Derleme: `place/SOLARA_Phase4_Navigation.rbxlx`

## Tek koordinat kaynağı

Her şey `ReplicatedStorage/Shared/MapDefinitions` verisinden okunur (düğümler, yol kenarları, şerit sayıları,
hız limitleri, sokak adları, POI'ler, ada/su alanları). Harita çizimi, rota grafiği ve hedef konumları aynı
dünya koordinatlarını (stud, X/Z) kullanır; ayrı bir harita koordinat sistemi yoktur. Ekran eşlemesi:
`ekran = (dünya − merkez) × ölçek`, +X sağ, +Z aşağı (kuzey yukarıda).

## Dosyalar

| Dosya | Durum | Görev |
|---|---|---|
| `ReplicatedStorage/Shared/Navigation.lua` | yeni | Yol grafiği, yola yapıştırma (snap), A* rota, manevralar, ilerleme. Saf Lua; Roblox'a bağımlı değil. |
| `Controllers/NavigationController.lua` | yeni | Hedef durumu, rota hesaplama, rotadan sapınca yeniden hesaplama, varış, dünyadaki hedef işareti. |
| `Controllers/MinimapController.lua` | yeni | Köşe haritası + yönlendirme paneli (sürüş HUD'u ile aynı düzen sistemi). |
| `FrontEnd/Map/MapCanvas.lua` | yeni | Ortak harita çizici (mini ve tam ekran). |
| `FrontEnd/Screens/MapScreen.lua` | yeni | Tam ekran harita, hedef seçimi, yerler listesi. |
| `Modules/DrivingLayout.lua` | değişti | `Guidance` dikdörtgeni (dokunmatik + masaüstü). |
| `Controllers/FrontEndController.lua` | değişti | HARİTA ekranı, `OpenMap`, araç dururken menü/harita. |
| `Controllers/VehicleController.lua` | değişti | `GetMobileLayout()` (menüden araca dönüşte mobil düzen). |
| `Controllers/VehicleHUDController.lua` | değişti | Aşama 3'teki boş harita yer tutucusu gizlendi (gerçek harita aynı yere çiziliyor). |
| `Modules/InputConfig.lua` | değişti | `OpenMap` = M; menüde M kapatır. |
| `FrontEnd/MenuInput.lua`, `Shell.lua`, `MainScreen.lua`, `Strings.lua`, `Fader.lua` | değişti | M tuşu, ana menüde 4. buton "HARİTA", ☰ butonu sağ üste, harita ipuçları, TR/EN metinler, büyük harita ağacını solma efektinden muaf tutma. |
| `tools/test_navigation.py` | yeni | Çevrimdışı navigasyon testi. |
| `tools/test_driving_layout.py` | değişti | Yönlendirme paneli dahil. |

## Rota hesaplama

* Grafik: her yol kenarı iki yönlü yay; `LanesForward = 0` / `LanesBackward = 0` olan yön eklenmez (tek yön).
* Maliyet: süre = uzunluk / hız limiti. A*, sezgisel = düz mesafe / en yüksek hız (kabul edilebilir).
* Başlangıç ve hedef en yakın yol parçasına yapıştırılır (256 stud ızgara; yükseklik farkı cezalı, oyuncunun
  **üstündeki** yollar çok daha cezalı → otoyol altındaki sokakta otoyola yapışmaz).
* Hedef yoldan 120 stud'dan uzaksa rota en yakın yol noktasında biter, son kısım kesikli "yol dışı" çizgi olur.
* Ulaşılamayan hedef (ayrık ada, ters tek yön) → rota yok, panelde "Rota bulunamadı"; çökme yok.
* Başlangıçta yakın yol yoksa → "Yakında yol yok".
* Manevralar (açıya göre): U dönüşü ≥150°, sola/sağa ≥60°, hafif sola/sağa ≥25°; 25°'den küçük ama yol adı
  değişiyorsa "devam et"; aynı yolda düz gidiş manevra sayılmaz; sonda "varış".
* Rotadan 35 stud sapma 1,2 sn sürerse yeniden hesaplanır (1 sn bekleme). 30 stud içinde varış.

## Çizim ve performans

* Harita **bir kez** çizilir (yollar, su, POI'ler). Kaydırma = kök çerçevenin konumu, yakınlaştırma = UIScale.
  Her karede tam harita yeniden çizilmez.
* 1024 stud karolar: görünmeyen karolar `Visible = false` (sadece görünür karo aralığı değişince güncellenir).
* Simgeler sabit piksel boyutunda; boyutları sadece yakınlaştırma %1'den fazla değişince yeniden hesaplanır.
* Rota çizgisi sadece rota değişince yeniden oluşturulur.
* Mini harita 30 Hz, yönlendirme paneli 5 Hz, navigasyon ilerlemesi 10 Hz güncellenir.
* Tam ekran harita ilk açılışta oluşturulur (oyun başlarken maliyet yok).
* Çevrimdışı ölçüm (masaüstü Lua 5.4, Luau değil): 1260 rota, ortalama 0,6 ms, en kötü ~5 ms.

## Kontroller

| | Masaüstü | Gamepad | Dokunmatik |
|---|---|---|---|
| Tam harita | M (veya menü → HARİTA) | menü (D-Pad sol) → HARİTA | köşe haritasına dokun |
| Kaydır | sürükle, WASD / oklar | sol çubuk / D-Pad | sürükle |
| Yakınlaş | tekerlek, Q / E | LB / RB | iki parmak |
| Hedef koy | tıkla (simgeye tıklarsan o yer) / Enter = artı işareti | A = artı işareti | dokun |
| Yerler listesi | tıkla | — (artı işaretiyle seç) | dokun |
| Kapat | M, Backspace (ana menüye), P | B | Geri |

Araçtayken menü/harita sadece araç neredeyse dururken (< 3 stud/sn) açılır; o sırada araç girişleri askıya
alınır, kapanınca geri gelir. Hareket halindeyken "Menü ve harita için aracı durdur." bildirimi çıkar.

Mini harita kuzey-yukarıdır; ortadaki ok oyuncunun/aracın yönünü gösterir. Yakınlık hızla değişir
(yaya yakın, hızlı araç uzak).

## Studio test adımları (zorunlu)

Başlamadan: `SOLARA_Phase4_Navigation.rbxlx` aç, Play. Çıktı penceresinde `Navigation` hatası olmamalı.

1. **Yaya hareketi**: Yürü/koş. Mini harita kaymadan oyuncuyu ortada tutmalı, ok yönü kameradan bağımsız
   olarak karakterin baktığı yönü göstermeli. Takılma (FPS düşüşü) olmamalı.
2. **Araç hareketi**: Bir araca bin, hızlan. Harita uzaklaşmalı, araç ok yönü direksiyonla dönmeli;
   HUD hız çubuğu, mini harita ve yönlendirme paneli çakışmamalı.
3. **Dönüşler**: Rota varken kavşaklarda "Sola dön / Sağa dön" ve mesafe doğru ve zamanında değişmeli;
   rotadan bilerek sap → ~1–2 sn sonra "Yeniden hesaplanıyor" ve yeni rota.
4. **Hedef değişikliği**: M → bir POI seç → rota çizilir; başka bir yere tıkla → rota değişir; "Temizle" →
   rota ve dünya işareti kaybolur. Varınca "Hedefe ulaştın".
5. **Farklı bölgeler**: şehir merkezi, otoyol üstü/altı, köprü, kırsal çiftlik (yol dışı bitiş), ada
   (ulaşılamaz mesajı). Otoyol altındaki sokaktan rota isteyince rota sokaktan başlamalı.
6. **Masaüstü**: 1280×720 ve 1920×1080. Tekerlek imlecin altına yakınlaşmalı.
7. **Mobil** (Device Emulator: iPhone + iPad, yatay ve dikey; ayrıca gerçek cihaz önerilir): sürükle,
   iki parmak, dokun; köşe haritasına dokununca tam harita açılmalı; sürüş butonlarıyla çakışma olmamalı.
8. **Gamepad**: D-Pad sol → HARİTA, çubukla kaydır, LB/RB yakınlaş, A hedef.
9. **Menü/dil**: TR ve EN cihaz dilinde metinler.
10. **Performans**: Tam haritayı açıp en uzak yakınlaştırmada kaydır; MicroProfiler'da kare süresi kontrolü.

Sonuçları (özellikle FPS, mobil düzen ekran görüntüleri ve hatalı rota örnekleri) bildirin.

## Bilinen sınırlamalar

* Rota hesabı istemcide; sunucu doğrulaması gerekmez (oyun mantığını değiştirmez).
* Tam harita listesi gamepad ile odaklanamaz (artı işaretiyle seçim yapılır).
* Dönüş yasakları/trafik ışıkları verisi haritada yok; rota sadece tek yön kurallarına uyar.
* Mesafe gösterimi: 1 stud = 0,28 m kabulü.

## Bulunan önceden var olan hata (DÜZELTİLMEDİ — onay gerekli)

`MapDefinitions.lua` kenar satırı ayrıştırıcısı `E|id|a|b|kind|width|lf|lb|speed|name|flags|span0|span1`
biçiminde 13 alan okur ama `flags = f[12]`, `BridgeSpan = f[13], f[14]` kullanır (bir kayık). Sonuç:
`Sidewalk` ve `Bridge` her zaman false → yol kenarı kaldırımları ve köprü korkulukları/ayakları hiç
oluşturulmuyor. Navigasyon etkilenmez (ad, şerit ve hız alanları doğru). Düzeltme dünya oluşturmayı
değiştireceği için onay bekleniyor.
