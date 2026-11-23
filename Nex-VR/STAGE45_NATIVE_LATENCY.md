# Stage 45 — Native el takibi: gecikme + takılma düzeltmesi

## İstek
Native MediaPipe el takibi arada takılıyor / gecikiyor. Çok akıcı, çok hızlı algılayan bir el istendi.

## Bulunan kök nedenler (Stage 44 kodunda)
1. **Yaş yanlıştı.** `Hand.onNative` yakalama zamanını `şimdi − yaş` diye buluyordu; yaş, sonucun Java'da hazırlandığı ana kadarki süreydi.
   UI iş parçacığı kuyruğu + WebMessagePort + JS kuyruğu süresi hiç sayılmıyordu ve bu süre kareden kareye değişiyordu (0–30 ms).
   Zaman damgası titreyince One Euro süzgeçlerin hız tahmini ve Turbo ileri tahmin titredi = **"arada bir takılma"**.
2. **Sonuçlar UI iş parçacığından geçiyordu** (`Handler(mainLooper)`): UI meşgulken sonuç beklerdi.
3. **JS kuyruğu birikiyordu.** JS bir an takılınca (GC, ağır kare) native taraf göndermeye devam ediyordu; JS sonra eski sonuçları art arda
   işleyip her birinde süzgeç + raycast + çizim yapıyordu (**yetişme takılması**).
4. **Boşa iş:** MediaPipe meşgulken gelen her kare yine de RGBA→Bitmap kopyalanıyordu (CPU çıkarımla yarışıyordu);
   sonuç gelince ana iş parçacığında bir de ekstra senkron çizim yapılıyordu (render karesi zaten çiziyor).
5. Zaman damgası kaynağı UNKNOWN (monotonic) olan cihazlarda yaş 0 sayılıyordu → gecikme telafisi hiç çalışmıyordu.
6. Kamera ISP hattı: video sabitleme kareleri tamponlar, yüksek kalite gürültü/keskinlik işleme gecikme ekler.

## Düzeltmeler
**Java (`NativeCam.java`)**
- Meşgul kapısı: MediaPipe bir kareyi işlerken yeni kare hiç kopyalanmaz/dönüştürülmez (`busySince`, en çok 120 ms; sonuç/hata gelince açılır).
  Sonuç gelince hemen en taze kare işlenir. CPU ve GPU boşa yorulmaz.
- Yakalama zamanı: REALTIME **ya da** MONOTONIC kaynağı otomatik denenir (0–400 ms makul olan seçilir).
- Her sonuca yakalama zamanı `T` (ms, 0.1 hassasiyet) eklenir; `ConcurrentHashMap` yerine halka tampon, `StringBuilder`/satır tamponları/Canvas yeniden kullanılır (kare başına GC azaldı).
- `nx-hand-analysis` iş parçacığına ve MediaPipe sonuç iş parçacığına `THREAD_PRIORITY_URGENT_DISPLAY` (Java `MAX_PRIORITY` Android'de neredeyse etkisizdi).
- Kamera: video sabitleme KAPALI, gürültü azaltma ve keskinlik FAST (yalnızca cihaz destekliyorsa, özellikleri okuyarak); 60 fps aralığı seçimi aynen duruyor.

**Java (`MainActivity.java`)**
- Sonuç gönderimi UI iş parçacığından çıkarıldı: ayrı `nx-post` (URGENT_DISPLAY) iş parçacığı. Her sonuca gönderim anı `P` eklenir.
- Akış denetimi: JS her R mesajına `a` (ack) yollar; yolda en çok **2** sonuç. JS takılırsa aradakiler atılır, yalnızca en yenisi gider.
- Kendi kendini onarma: ack hiç gelmezse (8 gönderim) önce UI iş parçacığından göndermeye, o da olmazsa akış denetimini kapatmaya geçer
  (eski Stage 44 davranışı). Denetim mesajları (`S|...`) her zaman UI iş parçacığından gider.

**JS (`index.html`)**
- `Hand.onNative`: yakalama zamanı = `T + o`; `o = min(alış − P)` (saat farkı, yavaş yükselen). Aktarım/kuyruk gecikmesi dalgalanması t0'ı oynatmaz,
  yaş artık aktarım süresini de kapsar. `T/P` yoksa eski `şimdi − yaş` yolu aynen çalışır.
- `NHand.msg`: her sonuçta native'e ack.
- `Hand.glide`: native modda sonuç gelince eşzamanlı çizim atlanır (render karesi hemen çiziyor) → ana iş parçacığı yükü yarıya iner.

## Test
- `node tools/nativehand.test.js` 21 → 30 kontrol (T/P saat farkı kestirimi, 2–21 ms aktarım dalgalanmasında t0 oynaması < 0.3 ms, saat sıçraması, ack).
- `turbo`, `mediapipe-worker`, `oneeuro`, `handpaint`, `winhand` testleri ve `index.html` `node --check` geçti.

## DOĞRULANMADI (önemli)
Java derlenmedi (bu ortamda Android SDK yok; yalnızca sözdizimi ayrıştırıldı, hata yok) ve cihazda çalıştırılmadı. Cihazda bak:
1. Üst bilgi satırındaki **gecikme** (ms) ve **çıkarım** değerleri; el hareketinde takılma kalıp kalmadığı.
2. `nx-post` iş parçacığından `postMessage` bazı cihazlarda reddedilirse kod ~0,15 sn sonra UI'ye döner (hand ilk anda bir an gecikebilir).
3. `CONTROL_VIDEO_STABILIZATION_MODE`/`NOISE_REDUCTION_MODE`/`EDGE_MODE` ayarlarını bir cihaz beğenmezse görüntü bozulursa `NativeCam.applyTune` içindeki ilgili satırı sil.
4. GPU delegate bazı telefonlarda CPU'dan yavaştır; `inf` (çıkarım) ms değeri GPU'da 20 ms üstündeyse `buildLandmarker` içinde `Delegate.CPU` önce denenebilir.
