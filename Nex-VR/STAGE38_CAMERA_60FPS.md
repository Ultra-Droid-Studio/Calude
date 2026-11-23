# Stage 38 — Kamera 60 FPS (cihazın verebildiği en yüksek hız)

## Sorun
El takibi Worker'da çalışmasına rağmen hâlâ kasıyordu. Kamera karesi hızı 30 fps ile sınırlıydı;
üstelik mobil (`lite`) modda veya CPU delegate'te `Hand.start()` içindeki ayrı bir satır kamerayı
**20-24 fps**'e geri düşürüyordu (Stage 37'deki 30 fps değişikliğini eziyordu).

## Değişiklikler (`app/src/main/assets/index.html`)
1. Yeni `CamFps` yardımcısı: `rate()` → `{ideal:60,max:60}` (cihaz 60 veremezse tarayıcı en yakın
   desteklenen değere düşer), `read(track)` → kameranın GERÇEK fps değerini okur, `floor()` → çıkarım
   aralığının alt sınırını (≈ 850/fps ms) verir.
2. `Pass.acquire()` (getUserMedia) ve `Hand.start()` içindeki `applyConstraints` artık 60 fps ister.
3. `lite`/CPU modunda kamerayı 20-24 fps'e düşüren satır kaldırıldı; çözünürlük sınırı (320×240) aynı.
4. Çıkarım aralığı (`iv`) alt sınırı artık sabit 33/45/28 ms değil, kameranın gerçek fps'ine bağlı.
   30 fps kamerada ≈28 ms (eskisine yakın), 60 fps kamerada ≈14 ms.
5. Kamera açılınca ekranda "Kamera NN FPS" bildirimi çıkar: cihazın gerçekte kaç fps verdiğini görürsün.

## Dürüst not
Kamera 60 fps verse bile el takibi 60 fps olmaz: MediaPipe çıkarımı telefonda tipik 12-25 ms sürer ve
`iv` bu süreye göre (ema×1.15-1.4) otomatik ayarlanır. Kazanç, ölçümler arası sürenin kısalması ve
Worker'ın boş kalmamasıdır. Bazı telefonlar düşük çözünürlükte veya loş ışıkta 60 fps'i desteklemez;
bildirimde 30 görürsen sebep budur.

## Doğrulanmadı
Gerçek cihazda denenmedi (bu ortamda kamera/SDK yok). Isınma/pil artışı olursa `CamFps.rate()` içindeki
60'ı 45 yapabilirsin.

## Stage 38b — 320x240'ta 60 fps modu yok: yüksek fps profili + küçültme + ölçüm
Cihazda kamera 60 fps destekliyor ama 30'da açılıyordu. Sebep: birçok telefon 320x240'ta yalnızca 30 fps modu sunar,
60 fps modları genelde 640x480 ve üstündedir. Bu yüzden:
1. `Pass.acquire()` önce `640x480 (tavan 1280x720)` + `frameRate:{min:50,ideal:60,max:60}` ile dener. `min:50` sert
   kısıt olduğu için ya gerçekten >=50 fps veren bir mod seçilir ya da hata verir; hata/düşük fps olursa eski 320x240 yola düşer.
2. Yüksek fps modunda (`CamFps.hi`) çözünürlüğü geri 320x240'a düşüren `applyConstraints` çağrıları atlanır.
3. MediaPipe'a giden kare `createImageBitmap(v,{resizeWidth:320,...,resizeQuality:'low'})` ile 320 genişliğe küçültülür;
   çıkarım maliyeti eskisi gibi kalır, kamera ise 60 fps akar.
4. Ölçüm: 2 sn'de bir kamera fps (ölçülen), çözünürlük, çıkarım/sn ve çıkarım ms hesaplanır. İlk ölçümde ekranda bildirim çıkar;
   "Kamera önizleme" açıksa aynı yazı önizlemedeki durum satırında güncellenir.

## Doğrulanmadı
Gerçek cihazda denenmedi. Yüksek çözünürlükte pasif görüntü (passthrough) arka planı biraz daha keskin/ağır olabilir.

## Stage 38c — Akıcı el (ara değerleme) + Tek el modu (ayarlardan)
- `Settings.hsmo` (varsayılan AÇIK, "Akıcı el (ara değerleme)"): ileri tahmin kapatılır; el, ölçümler arası süreye
  (`resDt`, `ingest` içinde ölçülür) göre `clamp(resDt*.6,20,55) ms` zaman sabitiyle yeni hedefe süzülür. Hız
  dalgalanması/aşım azalır; bedel ~20-40 ms gecikme. Kapatınca Stage 37 davranışı geri gelir. Çimdikte (pin) 12 ms.
- `Settings.hone` (varsayılan KAPALI, "Tek el modu"): MediaPipe `numHands:1`; çıkarım süresini düşürür. El takibi
  kapatılıp açılınca etkili olur.
## Doğrulanmadı
Gerçek cihazda denenmedi.
