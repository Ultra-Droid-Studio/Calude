# Stage 37 — Hızlı el hareketinde "tekleme" (judder) düzeltmesi

## Şikayet
"Uygulama hiç kasmıyor ama elimi hızlı hareket ettirince el/imleç ya geç geliyor ya da
tekleye tekleye (kasa kasa) geliyor." — yani genel performans sorunu değil, özellikle
**hızlı el hareketinde** görülen basamaklı/sıçramalı bir hareket.

## Kök neden
Kamera + MediaPipe çıkarımı saniyede ~20-24 kare (kamera `frameRate` sınırı) ile
sınırlıyken, render döngüsü 60 Hz ve üzerinde çalışıyor. `Hand.glide()` her render
karesinde eli, son gelen gerçek ölçüme (`s.q`) çok hızlı bir zaman sabitiyle
(8-13 ms) yaklaştırıyordu. Bu zaman sabiti, iki kamera/çıkarım karesi arası süreden
(~42-50 ms) çok daha kısa olduğu için el konumu yeni veri geldikten sonra 2-3 render
karesinde hedefe tamamen oturuyor, sonraki ~25-35 ms boyunca **tamamen hareketsiz
kalıyor**, sonra yeni ölçüm gelince aniden bir sonraki konuma zıplıyor. El yavaşken bu
sıçramalar küçük olduğu için göze batmıyor; el hızlı hareket ederken sıçramalar
büyüyor ve "tekleme" olarak hissediliyor. Bu, Stage 21'de One Euro gecikmesinin
düşürülmesinin (daha hızlı tepki için zaman sabitinin kısaltılması) bir yan etkisi —
gecikme azaldı ama iki ölçüm arasındaki "donma" süresi görünür hale geldi.

## Yapılan değişiklikler (`app/src/main/assets/index.html`)

1. **Kamera karesi hızı artırıldı:** `Pass.acquire()` içindeki `getUserMedia`
   isteği `frameRate:{ideal:20,max:24}` yerine `frameRate:{ideal:30,max:30}` istiyor.
   Çözünürlük (320×240 hedef, 480×360 tavan) değişmedi — yalnızca kare hızı. Bu,
   MediaPipe çıkarımının gerçekte çalışabileceği üst sınırı ~42-50 ms'den ~33 ms'ye
   indirir (cihaz destekliyorsa); `iv` zaten `lite` modda 33 ms'ye kadar inebiliyordu,
   bu değişiklikle o alt sınıra kameradan gerçekten ulaşılabilir hale geldi.
2. **Ölçümler arası "donma" yerine yön tahmini devam ediyor (`Hand.glide()`):**
   Önceden ileri tahmin (`lead`) sabit ve çok küçüktü (4-13 ms), yalnızca süzgeç
   gecikmesini gizlemek içindi. Şimdi buna, son **gerçek** algılamadan
   (`s.pst`) bu yana geçen süre de ekleniyor (en fazla 90 ms, %50 ağırlıkla):
   el, yeni kamera/çıkarım karesi gelene kadar son bilinen hızıyla **hareket etmeye
   devam ediyor**, donmuyor. Yeni gerçek ölçüm gelir gelmez bu ek tahmin sıfırlanıp
   süzgeçlenmiş gerçek konuma göre devam ediyor; çimdik sırasında (tıklama/sabitleme)
   bu tahmin öncekiyle aynı şekilde tamamen kapalı. Üst sınır (±0.035 → ±0.07 ekran
   genişliği/yüksekliği oranı) tahminin daha uzun pencerede de makul kalması için
   iki katına çıkarıldı.

## Değişmeyenler
- One Euro filtresi (`OE`), süzgeç sabitleri, MediaPipe modeli/güven eşikleri, GPU/CPU
  delege sırası, Worker mimarisi (Stage 35), çift-tick düzeltmesi (Stage 36), el
  çizim optimizasyonu (Stage 25) — hiçbiri değişmedi. Bu stage yalnızca iki ölçüm
  arasındaki boşlukta elin görünür biçimde donmasını hedef aldı.

## Beklenen etki
Hızlı el hareketinde artık konum, yeni ölçüm gelene kadar tahmini hızla ilerlemeye
devam ediyor; "dur-kalk" hissi yerine sürekli akan bir hareket beklenir. Kamera 30
fps'i desteklemeyen cihazlarda tarayıcı otomatik olarak desteklenen en yakın değere
düşer (`ideal`/`max` aynı olduğu için sorun çıkarmaz).

## Test
- `node --check`: HTML içindeki iki `<script>` bloğu da sözdizimi hatasız.
- `tools/*.test.js`: 16 dosyanın tamamı tek tek çalıştırıldı, hepsi geçti
  (`browser.test.js` 92 kontrolü geçtikten sonra kendi içindeki ilgisiz bir
  zamanlayıcı yüzünden süreç kapanmadı — testin kendisi başarılı, bu çalışmadan
  önce de vardı, bu stage'le ilgisi yok).
- `tools/oneeuro.test.js` ve `tools/handpaint.test.js` — doğrudan ilgili iki test —
  sorunsuz geçti. `oneeuro.test.js` içindeki `glide` zinciri testte ayrı bir kopya
  olduğundan (ayrıca not düşülmüştü) bu stage'deki `glide()` değişikliğini otomatik
  izlemiyor; istersen ayrıca güncellenebilir.

## DOĞRULANMADI / AÇIK EKSİKLER
- **Gerçek Android cihazda denenmedi** (bu ortamda SDK/kamera yok). Asıl "akıcı mı"
  sorusunun cevabı cihazda hissedilecek.
- Kameranın gerçekten 30 fps verip vermediği cihaza/WebView'e bağlı; bazı düşük uçlu
  telefonlarda sürücü 30 fps'i desteklemeyip otomatik 24-25'e düşebilir — zararı yok,
  sadece eski davranışa yakın kalır.
- Ek tahmin ağırlığı (%50) ve üst sınır (±0.07) tahmini sabitler; cihazda "hâlâ
  tekliyor" hissi olursa %50'yi artırabilir, "imleç hedefi aşıyor/titriyor" hissi
  olursa düşürebilirsin — aşağıdaki satırda:
  `const extra=pin?0:clamp(since,0,90)/1000*.5,`
