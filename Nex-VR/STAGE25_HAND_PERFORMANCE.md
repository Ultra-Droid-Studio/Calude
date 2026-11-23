# Stage 25 — El takibi performans optimizasyonu

## İstek
Kullanıcı: el takibinin **aşırı performanslı** olmasını, çizilen el modelinin de **çok detaylı olmadan hızlı** çalışmasını istedi; referans olarak PhoneXR açık kaynak projesini (`phonexr-main`) yükledi.

## Önce ne incelendi
`phonexr-main` içindeki ilgili kod okundu:
- `pwa/app.js` — MediaPipe HandLandmarker kurulumu: `delegate:'GPU'`, `runningMode:'VIDEO'`, `numHands:2`, float16 model.
- `orangehanding/FusionHands.kt` — tespit işini render/izleme thread'ini hiç bloklamayacak şekilde arka planda çalıştırma deseni, güven eşiği ayrımı (video .45 / kurtarma .3).
- `orangehanding/OneEuro.kt` — One Euro süzgeci referans implementasyonu.

**Sonuç:** NEXUS VR'nin algılama (detection) tarafı zaten PhoneXR ile aynı desenleri kullanıyor — GPU önce denenip CPU'ya düşülüyor, aynı float16 `hand_landmarker.task` modeli, uyarlanabilir (adaptive) çıkarım aralığı (`iv`), mobilde 320×240/30fps kamera sınırı, OneEuro süzgeci. Yani "model" (MediaPipe algılama modeli) tarafında zaten doğru/performanslı seçim yapılmıştı; burada değiştirilecek bir şey yoktu — gereksiz yere model küçültmek (ör. daha düşük çözünürlüklü özel model) doğrulanabilir bir kazanç getirmez ve tespit kalitesini düşürebilirdi, bu yüzden dokunulmadı.

**Asıl darboğaz:** her karede ekrana çizilen el silüeti (`Hand.paint()`), parmak başına 3 ayrı boğum segmentini **3 farklı geçişte** (siyah kenar / şeffaf oyma / ince parlaklık) tek tek `stroke()` ediyordu → elde başına **48 canvas çizim çağrısı/kare** (iki el = 96). Bu, GPU/CPU'dan bağımsız olarak saf JS+canvas CPU maliyetiydi ve kullanıcının "model çok detaylı olmasın, hızlı olsun" isteğiyle doğrudan örtüşüyordu.

## Yapılan değişiklikler (`app/src/main/assets/index.html`)

1. **Parmak başına tek stroke:** Önceki 3 segment x 3 geçiş (boğum boğum sivrilme) kaldırıldı; her parmak artık taban→uç arası tüm noktalardan geçen **tek bir path**, tek bir ortalama genişlikle çiziliyor. Elin kıvrımı (landmark pozisyonları) korunuyor, yalnızca "sivrilme" detayı feda edildi — bu tam olarak istenen "daha az detaylı, daha hızlı" değişim.
   - Masaüstü: 48 → **19** çizim çağrısı/el/kare (**~%60 azalma**)
2. **Mobilde (lite) üçüncü geçiş atlanıyor:** %5 alfa'lık ince mavi parlaklık katmanı gözle neredeyse görünmüyordu; telefonlarda tamamen atlanıyor.
   - Mobil: 48 → **13** çizim çağrısı/el/kare (**~%73 azalma**)
3. **Çizim için her kare yeni dizi ayırma kaldırıldı:** `draw()` içinde `p.map(...)` ile her karede 2 yeni JS dizisi üretmek yerine, her slotta önceden ayrılmış (`Float64Array(21)`) diziler yeniden dolduruluyor — gereksiz çöp toplama (GC) baskısı azaldı.

## Değişmeyenler (bilinçli olarak dokunulmadı)
- MediaPipe modeli, güven eşikleri, GPU/CPU delegate sırası, kamera çözünürlüğü/fps sınırı, uyarlanabilir çıkarım aralığı (`iv`), OneEuro süzgeci — bunlar zaten PhoneXR ile aynı/iyi ayarlanmış desenlerdi, kanıtlanmamış bir "hız" varsayımıyla bozulmadı.
- El çimdik/çizgi mantığı, slot eşleme, dokunma eşleşmesi — görsel/işlevsel davranış birebir korundu.

## Ek tur (aynı oturumda, "daha performanslı yap" isteği üzerine)
Kullanıcı tekrar "daha performanslı yap" deyince, aynı `paint()` fonksiyonu üzerinde bir adım daha gidildi:

1. **5 parmağın tamamı TEK path + TEK stroke():** Önceki sürümde parmaklar (4'ü birleşik + başparmak ayrı) 2 stroke çağrısıydı; şimdi hepsi aynı ortalama genişlikle (`.207`) tek bir path'te, tek `stroke()` ile çiziliyor. Başparmağın görece kalınlığı feda edildi — kullanıcı detaydan açıkça hızı üstün tuttuğu için bilinçli bir tercih.
2. **Avuç çokgeni düz (flat) `Float64Array(16)` önbellekte:** Önceden her karede 8 küçük `[x,y]` dizisinden oluşan bir dizi (`PP`) yeniden allocate ediliyordu; şimdi `this._PP` olarak bir kez ayrılıp her karede yerinde dolduruluyor — gereksiz çöp toplama (GC) baskısı azaldı.

**Sonuç — elde başına çizim çağrısı (stroke):**
| Aşama | Masaüstü | Mobil (lite) |
|---|---|---|
| İlk hâl (stage 24 ve öncesi) | 48 | 48 |
| Stage 25 (ilk tur) | 19 | 13 |
| Stage 25 (ikinci tur, bu bölüm) | **7** | **5** |

İlk hâlden bu yana **~%85 (masaüstü) / ~%90 (mobil)** daha az canvas çizim çağrısı — algılama (MediaPipe) tarafına dokunulmadan, yalnızca görsel çizim katmanı sadeleştirilerek.

## Test
- `node --check` ile ana HTML'deki JS blokları sözdizimi kontrolünden geçti.
- `tools/*.test.js` içindeki **10** dosyanın tamamı (9 eski + güncellenmiş `tools/handpaint.test.js`) çalıştırıldı, hepsi geçti.
- `tools/handpaint.test.js`: gerçek `paint()` kaynağını HTML'den çıkarıp sahte bir canvas context ile çalıştırır, çizim çağrısı sayısını ölçer (7 / 5), `_PP` önbelleğinin karelerarası doğru güncellendiğini ve veri bütünlüğünü (NaN/istisna yok) doğrular.
- Fiziksel Android cihaz üzerinde kare hızı ölçümü bu ortamda yapılamadı (ağ/SDK yok) — Android Studio'da derleyip gerçek cihazda hissedilen akıcılığı ve elin görünümünü (artık tüm parmaklar aynı kalınlıkta) kontrol etmen gerekir.
