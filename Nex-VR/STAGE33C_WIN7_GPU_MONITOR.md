# Stage 33c — Windows 7 monitörü GPU tarayıcı hattına bağlandı

## İstek
VR masasındaki 3 boyutlu monitöre tıklanınca içinde açılan Windows 7, eski
"ana görünümü View.draw() ile bitmap'e al → JPEG'e sıkıştır → anlık görüntü
olarak göster" yolunu kullanıyordu. Bu yol kasıyordu. İstenen: Win7'yi,
tarayıcının (nexus-browser) zaten kullandığı GPU hızlandırmalı render hattına
bağlamak — ama yine aynı 3 boyutlu monitör mesh'inin ekranı olarak görünsün.

## Arka plan
Stage 27'de tarayıcı için eklenen GPU yolu, WebView'i uygulamaya özel bir
**VirtualDisplay + Presentation** penceresinde, ana ekrana hiç eklemeden
çalıştırıyor; kareler `ImageReader` ile alınıp arka planda JPEG'e sıkıştırılıp
sayfaya **itiliyor** (poll yok, ~25-30 kare/sn). Bu, video/WebGL katmanlarını
da doğru yakalıyor ve ana iş parçacığını yormuyor. O zaman bu yol kasıtlı
olarak yalnızca `nexus-browser` kimliğiyle sınırlanmıştı; Win7 eski "anlık
görüntü" yolunda bırakılmıştı (Stage 26/27 notları).

Java tarafındaki GPU altyapısı (`gpuPages`, `gpuIds`, `gpuFrame`, `isGpu`,
`setGpu`, `gpuSize`, `prepareGazeView`, `setRect2`, `destroy`) zaten **kimliğe
(id) göre genel**di — yalnızca WebView'i oluşturan `Bridge.create` metodundaki
`wantGpu` koşulu Win7'yi açıkça dışlıyordu. JS tarafında da `BF` nesnesindeki
çoğu fonksiyon (`gpuFrame`, `gpuOff`, `requestSnapshot`, `drawSnapshot`)
zaten id-bazlı genel çalışıyordu; yalnızca birkaç yer tarayıcıya özeldi.

## Değişiklikler

**`MainActivity.java` — `Bridge.create`**
- `wantGpu` artık `"nexus-browser".equals(id)` VEYA win7 URL'si için de true
  dönüyor. Win7 WebView'i de artık VirtualDisplay/Presentation içinde açılıyor.

**`GpuPage.java`**
- Üstteki açıklama güncellendi (yalnızca tarayıcı değil, Win7 de kullanıyor
  artık). Davranışta değişiklik yok — sınıf zaten id'ye göre genel çalışıyordu.

**`index.html` — `BF` nesnesi**
- `gpuPanel(id)`: artık yalnızca ana tarayıcıyı değil, `id`'si GPU'lu olan
  **herhangi bir web panelini** (bu aşamada pratikte Win7) `webId()` eşlemesiyle
  bulup döndürüyor. Daha önce `null` dönüyordu — yani Java kare gönderse bile
  JS onu hiçbir mesh'e çizmiyordu.
- `get(m)`: alt WebView oluşturulunca (`AndroidBridge.create`/`createHtml`
  başarılı olunca) artık `this.markGpu(id)` çağrılıyor — tarayıcının `load()`
  metodunda zaten yapılan şeyin aynısı. Bu çağrı olmadan Java'nın GPU yolu
  açık olsa bile JS kareyi `this.gpu` kümesine hiç almıyordu (`gpuFrame`
  sessizce atıyordu).
- Yeni `gpuSizeExact(id,w,h,cw)`: Win7'nin kendi "arayüz boyutu/netlik"
  ayarından (`w7size()`) hesaplanan tam piksel/CSS genişliğini, eski
  `prepareGazeView`+`setViewScale` anlık görüntü API'si yerine doğrudan
  `AndroidBridge.gpuSize` (VirtualDisplay yeniden boyutlandırma) ile iletir.
- `update()`: Win7 paneli artık `this.gpu.has(id)` ise `gpuSizeExact`, değilse
  (GPU kapalıysa/kurulamadıysa) eskisi gibi `virtualizeExact` çağırıyor —
  otomatik eski yola düşüş korunur.
- `get(m)` ayrıca `AndroidBridge.create` çağrısından hemen önce `this.syncGpu()`
  çağırıyor, tıpkı tarayıcının `load()`'ı gibi — Ayarlar paneli hiç açılmamış
  olsa bile güncel GPU tercihi Java tarafına iletilsin diye.

## Davranış
- Win7 artık görsel olarak **hâlâ aynı 3 boyutlu monitör mesh'inin** ekranı
  (ayrı bir pencere/panel açılmıyor; değişen yalnızca görüntünün nasıl
  üretildiği).
- GPU kurulamazsa (düşük uçlu cihaz, `GpuPage.open` null döner) otomatik eski
  anlık-görüntü yoluna düşer — Win7 açılmaya devam eder, sadece eskisi gibi
  biraz daha kasılabilir.
- Ayarlar → "GPU tarayıcı (video, deneysel)" anahtarı artık hem tarayıcıyı
  hem Win7 monitörünü birlikte etkiler (tek global anahtar).
- El çimdiği/dokunma (`touchView`), kaydırma, pencere kapatma/temizleme gibi
  her şey değişmedi — bunlar zaten `id`'ye göre genel çalışıyordu.

## Test
`node tools/gpubrowser.test.js` (36 kontrol), `node tools/w7touch.test.js`,
`node tools/browser.test.js` (92 kontrol — test kendisi sonda node'u
kapatmıyor/timeout ile kesildi ama tüm kontroller geçti sayılarak bitti,
önceki aşamalarda da aynı davranış), ve projedeki diğer tüm `tools/*.test.js`
dosyaları: hepsi geçti. `node --check` ile birleştirilmiş JS sözdizimi de
doğrulandı.

## Sınır
- Android derlemesi ve cihaz testi bu ortamda yapılamadı (SDK/ağ yok).
  Değişiklik yalnızca kaynak düzeyinde yapıldı.
- `AndroidBridge.gpuSize` tarafında piksel boyutu 1920×1200'e, CSS genişliği
  1920'ye kadar sınırlanıyor (performans için kasıtlı bir üst sınır — Win7'nin
  kendi "arayüz boyutu" ayarı 2240'a kadar çıkabiliyor, bu durumda GPU yolunda
  fiilen 1920'de sınırlanmış olur; sorun değilse dokunulmadı).
- Cihazda ilk yapılacaklar: Win7 monitörünü aç/kapat birkaç kez dene, YouTube
  gibi video içeren bir sekmeyi Win7 içinde aç ve akıcılığı gerçek tarayıcıyla
  karşılaştır, GPU anahtarını kapatıp eski yola düştüğünü doğrula.
