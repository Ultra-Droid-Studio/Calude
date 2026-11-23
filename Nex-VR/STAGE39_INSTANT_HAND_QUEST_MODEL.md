# Stage 39 — Anında el takibi (tahminsiz) + Quest tarzı el modeli

## İstek
El takibi olabildiğince hızlı, tahmine dayalı olmasın, el nerede ise anında orada olsun; el modeli Quest'teki
yarı saydam gri-mavi eller gibi görünsün.

## Hız (`app/src/main/assets/index.html`)
Yeni ayar: **"Anında el (ham veri, tahminsiz)"** — varsayılan AÇIK (`Settings.v.hfast`). Kapatınca Stage 38c davranışı döner.
1. **Tahmin yok:** `glide()` anında modda ileri tahmin (`lead`/`extra`) ve ara değerleme kullanmaz. Yeni ölçüm gelince
   el ve imleç doğrudan ölçülen konuma oturur ve aynı çağrıda çizilir (`ingest → glide(force) → draw`).
   Render döngüsündeki `step()` bu modda boşa çizim yapmaz.
2. **Çıkarım aralığı sınırı yok:** `tick()` artık `iv` (ema×1.2…) ile beklemez; Worker boşalır boşalmaz yeni kamera karesi gönderilir.
   Eski "en çok 1 kare uçuşta" kuralı korunur (birikme/gecikme olmaz). El hiç yokken 24 ms aralık (CPU tasarrufu).
3. **Sonuç gelir gelmez bir sonraki kare:** Worker sonucu işlendikten hemen sonra `tick()` çağrılır; kamera karesi beklemede ise
   bir sonraki `requestVideoFrameCallback` beklenmez (boru hattı).
4. **Süzgeç gecikmesi çok düşük:** One Euro anında modda `mc=3, beta=9` (iskelet `mc*1.6`). Duran elde titreşimi hâlâ keser,
   hızlı harekette kesim frekansı ~20 Hz'in üstüne çıkar, yani pratikte gecikme ~0. (Normal mod: 1.2 beta.)
5. Kamera 60 fps profili (Stage 38/38b) ve 320 px küçültme aynen duruyor.

## Model (`Hand.paint`)
Quest el modeline benzer görünüm: yarı saydam gri-mavi dolgu, açık renkli yumuşak kenar, koyu ince dış çizgi, uca doğru
incelen yuvarlak parmak uçları, bilekten kola doğru solarak kaybolan ön kol.
- Parmaklar 3 kademede (boğum → uç) giderek incelir; her kademe TEK path + TEK stroke (5 parmak birlikte).
- 3 katman: koyu dış çizgi (mobilde atlanır), açık kenar, gövde. Ön kol her katmanda gradyanla solar.
- Yarı saydamlık canvas'ın CSS `opacity:.88` değeriyle verilir; böylece üst üste binen parçalar koyulaşmaz.
- Çimdikte iki uç parlar, imleç halkası korunur.
- Çizim çağrısı: masaüstü 13 stroke, mobil 9 stroke (Stage 25'te 7/5 idi; ilk hâl 48). Bedel küçük, görünüm için kabul edildi.
- Silinen alan (dirty-rect) ön kolu da kapsayacak şekilde genişletildi (iz kalmaması için).

## Testler
`node --check` (2 script bloğu) temiz. `tools/*.test.js` (browser hariç) geçti; `handpaint` ve `oneeuro` testleri yeni
tasarıma/parametrelere göre güncellendi.

## DOĞRULANMADI / AÇIK EKSİKLER
- **Gerçek cihazda denenmedi** (bu ortamda kamera/SDK/ekran yok); görünüm de ekranda görülmedi, yalnızca çizim çağrıları test edildi.
- Çıkarım hızı hâlâ MediaPipe'ın cihazdaki süresiyle sınırlı (telefonda tipik 12-25 ms). Tahmin olmadığı için el, ölçüm
  süresi kadar geriden gelir ve çıkarım hızında "adım adım" hareket edebilir; kamera/çıkarım sınırının altına yazılımla inilemez.
- Daha fazla hız için: "Tek el modu" (numHands:1) açılabilir.
- Renk/opaklık ayarı: `paint()` içindeki `rgb(112,130,152)` (gövde), `rgb(206,222,238)` (kenar) ve `initF()` içindeki `.88`.

## Stage 40 — Kamera kalitesi ayarı
Ayarlar > El sekmesinde **Kamera kalitesi**: Düşük 480p (varsayılan, eski davranış) / Orta 720p / Yüksek 1080p (`Settings.v.hcq`).
- Yalnızca kameradan alınan görüntünün (arka plan/önizleme) netliğini etkiler. MediaPipe'a giden kare her zaman 320 px'e
  küçültülür, bu yüzden el takibi hızı/doğruluğu değişmez.
- `Pass.acquire()` merdiven dener: seçilen çözünürlükte ≥50 fps → aynı çözünürlükte ≥30 fps → bir alt çözünürlük… → 480p.
  Cihaz seçilen kaliteyi veremezse otomatik bir alta düşer.
- Değiştirilince el takibi açıksa kamera otomatik yeniden başlatılır (arka plan sürekli açıksa değişiklik kamera bir sonraki açılışta etkili olur).
- Ayarlar sekmesi kart yüksekliği satır sayısına (14) eşitlendi.
### Doğrulanmadı
Gerçek cihazda denenmedi. 1080p'de createImageBitmap küçültme ve görüntü kopyalama maliyeti telefonda ısınma/FPS düşüşü yapabilir; sorun olursa Orta'ya dön.
