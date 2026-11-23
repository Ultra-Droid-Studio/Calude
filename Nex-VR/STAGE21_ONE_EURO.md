# Stage 21 - One Euro filtresi düzeltmesi (el imleci ve iskelet)

Stage 20 üzerine kuruludur. **Değişen dosyalar:** `app/src/main/assets/index.html` (yalnızca `OE` sınıfı, `mkSlot`, `Hand.upd`
içindeki süzgeç çağrıları ve bir satır `lead`), `tools/oneeuro.test.js` (yeni). Java, Win7, gorilla, katalog ve tarayıcı koduna dokunulmadı.

## Asıl bulgu
NEXUS'ta zaten bir One Euro filtresi (`OE`) vardı, ama pratikte **sabit bir alçak geçiren süzgeç gibi** çalışıyordu:
`beta` (0.045 / 0.06) 0-1 aralığındaki normalleştirilmiş koordinatlara göre yaklaşık 100 kat küçüktü; hız arttığında kesme
frekansı neredeyse hiç yükselmiyordu. Ölçüm (sentetik el, 6 el-boyu/sn): **~90 ms sabit gecikme**, hızdan bağımsız.
Ayrıca iki gerçek hata vardı: tek bir `NaN` süzgeci kalıcı olarak bozuyordu, ve 100 ms'den uzun boşluktan sonra el konumuna
yalnızca yarı yolda oturuyordu.

## Ne değişti
- **Hız, el boyuna göre ölçülüyor** (`f(v,t,k)`, `k = 1/el boyu`). El kameraya yakın da olsa uzak da olsa aynı ayar aynı davranır.
- **beta 1.2** (imleç ve iskelet). Durgun kesme frekansları (`Settings.v.hsm` kademeleri: 3 / 2.2 / 1.6 / 1.1 / .8 Hz, iskelette x1.9) **aynen korundu**;
  yani el durgunken eskisi kadar sakin, hızlı harekette çok daha çevik.
- **Sağlamlık:** sayı olmayan girdi ve zaman damgası yok sayılır; aynı/geri giden/4 ms'den yakın damga durumu değiştirmez;
  250 ms'den uzun boşlukta (el yeniden bulundu) süzgeç yeni konuma anında oturur; geçersiz `k` 1 sayılır.
- **Öne tahmin (`Hand.lead`) küçüldü:** `clamp(ema*.7+8,10,32)` -> `clamp((ema*.7+8)*.4,4,13)`. Eskiden 90 ms gecikmenin bir kısmını
  gizliyordu; süzgeç gecikmesi azalınca aynı değer imleci hedefin ötesine taşıyordu.

## Ölçümler (Node, sentetik sinyal; gerçek cihazda ayrıca denenmeli)
Durgun el titremesi eskisiyle aynı düzeyde (gürültünün ~%40'ı geçiyor; eski ~%39).

| | eski | yeni |
|---|---|---|
| 6 el-boyu/sn'de gecikme | 84-94 ms | 13 ms (el boyundan bağımsız) |
| hızlı hamle (250 ms), hedefe oturma | 331 ms | 40 ms |
| orta hız hamle (500 ms), hedefe oturma | 262 ms | 13 ms |
| yavaş hamle (900 ms), hedefe oturma | 153 ms | 6 ms |
| ortada geri kalma (500 ms hamle, 1080 px) | 109 px | 58 px |
| hedefi aşma (500 ms hamle) | 2.0 px | 5.4 px |

**Bedel:** gecikme azalınca imleç hedefte biraz daha fazla "yerleşme payı" gösterir: tipik hamlede 2 -> 5 px, çok sert bir fırlatmada
(0.4 ekran / 250 ms) 2.5 -> 10 px. Ölçüm gürültüsü zaten ~3-4 px taban oluşturuyor. Çimdik anında imleç, mevcut sabitleme mantığı
(`s.pa`) sayesinde aynı şekilde kilitleniyor; o kod değişmedi.

## Ayarlanabilir sabitler (cihazda hissi beğenmezsen)
- İmleç durgunken titriyorsa: `new OE(mc,1.2)` içindeki **1.2'yi 0.8'e** indir (daha sakin, biraz daha gecikme), ya da `hsm` kademesini artır.
- Hızlı harekette hâlâ geri kalıyorsa: 1.2'yi 2'ye çıkar.
- Hedefi aşıyorsa: `Hand.lead` satırındaki **.4 çarpanını .2'ye** düşür.

## Doğrulananlar (bu ortamda, Node)
- `node tools/oneeuro.test.js` (5053 kontrol): sabit girdi, NaN/Infinity, geçersiz zaman/k, aynı ve geri giden damga, boşlukta yeniden oturma,
  reset, çıktının girdi aralığında kalması (5000 düzensiz aralıklı örnek), 3 farklı el boyunda titreme ve gecikme, ölçek bağımsızlığı,
  5 yumuşatma kademesinin tek yönde çalışması, iskeletin imleçten çevik olması, `upd`+`glide` zincirinin 3 hamle hızında aşım/oturma ölçümü,
  ve çağrı yerlerinin gerçekten yeni imzayı kullandığı.
- Eski testler aynen geçiyor: `browser.test.js` (82), gorilla art/forest/phys/smoke. `index.html` betikleri `node --check` temiz.

## DOĞRULANMADI / AÇIK EKSİKLER
- **Gerçek cihazda ve gerçek kamerayla denenmedi.** Gürültü modeli (el boyunun %3'ü, beyaz gürültü) bir varsayım; gerçek MediaPipe gürültüsü
  farklı olabilir (ör. ışık azken daha büyük, bazı eklemlerde ilişkili). Beta değerini yukarıdaki üç satırla cihazda ince ayarlamak gerekebilir.
- `upd`+`glide` zinciri testte **kopya** olarak duruyor; `glide` ileride değişirse test onu otomatik izlemez.
- Yalnızca x ekseni simüle edildi; y ekseni aynı sınıfı aynı şekilde kullanıyor ama ayrıca ölçülmedi.
- Çimdik anı tıklama doğruluğu sayısal olarak ölçülmedi (kod yolu değişmedi, ama süzgeç gecikmesi azaldığı için his farklı olabilir).
- Z (derinlik) süzgeçlenmiyor; bu projede kullanılmıyordu.
