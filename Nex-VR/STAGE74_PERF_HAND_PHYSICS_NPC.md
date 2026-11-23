# Stage 74 — Performans mimarisi, native (C++) el kinematiği, parmak konturları, fizik, NPC, ses, monitör

Bu aşamada proje önce incelendi, ölçülebilir darboğazlar bulundu, sonra mevcut yapı korunarak geliştirildi.
Hiçbir mevcut özellik kaldırılmadı; eski yollar (Worker MediaPipe, JS süzgeci, kumanda modeli) yedek olarak duruyor.

## 1. İnceleme: bulunan gerçek darboğazlar

| Yer | Sorun | Etki |
|---|---|---|
| `MainActivity.onSensorChanged` | Her sensör olayında 2 yeni `float[9]` + metin birleştirme + her olay için ayrı `runOnUiThread(evaluateJavascript)` | UI iş parçacığı bir an meşgul olunca eski baş yönleri kuyrukta birikir, sonra art arda işlenir → baş takibinde gecikme ve takılma |
| `NativeCam.analyze` | Kamera karesi her seferinde Canvas ile yazılımda döndürülüyordu (ikinci tam kare kopyası) | Takip iş parçacığında gereksiz CPU ve bellek bant genişliği |
| `NativeCam` | Takip çözünürlüğü sabitti (cihaz yavaşlasa/ısınsa da 480×360) | Isınan cihazda çıkarım uzar, el gecikmesi artar |
| El işleme | Parmak bükülmesi, çimdik, avuç yönü vb. her tüketici kendi kaba ölçüsünü yapıyordu (goril oyunu: parmak ucu uzaklığı) | Tutarsız jestler, yumruk algısı kararsız |
| El görünümü | Stage 72'den beri yalnızca kumanda modeli; el kaybolunca 520 ms son pozda kalıyordu | Parmaklar görünmüyordu; kaybolan el ekranda asılı kalıyordu |
| `gorilla-phys.js` | Her çarpışma sorgusunda `bigs.slice()` + her alt adımda kapanış ve ara nesneler | Kare başına onlarca kısa ömürlü dizi/nesne → çöp toplama kaynaklı takılma riski |
| Goril dünyası | NPC'ler yalnızca oturan süs; doku boyutu 192 (WebGL1'de 2'nin kuvveti değil → yükleme sırasında yeniden boyutlanır, mipmap'siz) | Dünya cansız, yüksek kalitede dokular bulanık |
| Ana WebView | Renderer süreci çökerse/öldürülürse uygulama da kapanıyordu | Uzun oturumda düşük bellekte tüm VR kapanır |
| `setRect2` (alt WebView konumu) | Pencere sürüklenirken her çağrıda yeni `Rect` + her seferinde `onResume/onPause` | Sürükleme sırasında gereksiz iş ve JS zamanlayıcı uyandırma |
| Ölçüm | Yalnızca toplam FPS vardı | Darboğazın CPU/GPU/el/GC'den hangisi olduğu görülemiyordu |

## 2. El takip hattı (yeni)

```
CameraX (RGBA, yalnızca en taze kare, döndürme CameraX/libyuv'da)
  → zaman damgası (yakalama anı, monoton saat)
  → MediaPipe HandLandmarker (GPU, yoksa CPU; LIVE_STREAM; meşgulken yeni kare kopyalanmaz)
  → [C++ libnxhand] süzgeç + kinematik + güven + ışınlanma reddi   (iki el ≈ 2 µs, ayırma yok, JNI'da kopya yok)
  → kompakt metin (R|… + K blokları + F,1 + T + P) → WebMessagePort, yalnızca EN SON sonuç (ack ile akış denetimi)
  → JS: yuva eşleme, imleç, jestler, kontur (GPU), goril oyunu
```

* **Uyarlanır süzgeç C++'ta** (One-Euro, hıza göre kesme frekansı; durgunken titreme süzülür, hızlıda gecikme yok).
  Native süzülmüş landmark'lar gelince JS ikinci kez süzmez (çift süzgeç = çift gecikme).
* **Işınlanma reddi:** tek karelik, iskelet oranlarını bozan sıçramalar reddedilir (önceki poz tutulur).
  İskeleti tutarlı hızlı hamle hemen kabul edilir; aynı yere iki kez gelen sıçrama ikinci karede kabul edilir.
* **Kayıp/geri gelme:** 300 ms görülmeyen el sıfırlanır; geri gelince eski konumdan kayarak gelmez, yeni konumda belirir.
* **Güven:** model skoru × iskelet tutarlılığı × kadraj içinde olma × uzaklık. Bayraklar: uzak, kısmen kadraj dışı, reddedildi, yeniden bulundu.
* **Özellikler (el başına):** 5 parmak bükülmesi (başparmak ayrı formül), başparmak→4 parmak ucu çimdik mesafesi,
  4 komşu parmak açıklığı, avuç normali, el dönüşü (kuaterniyon), avuç hızı (x,y) ve kameraya yaklaşma hızı, yumruk/açık/çimdik.
* **Uyarlanır takip çözünürlüğü:** standart profilde çıkarım 3 sn boyunca > 42 ms ya da cihaz ısınırsa 320×240'a iner,
  15 sn boyunca < 20 ms ve serinse 480×360'a döner (8 sn bekleme ile gidip gelme yok).
* **Yedek:** `libnxhand.so` yüklenemezse K blokları gönderilmez → JS kendi süzgecini ve aynı formüllerin JS kopyasını
  (`web/js/131-hand-feat.js`) kullanır. Worker (tarayıcı MediaPipe) yolunda da özellikler aynıdır.

Dosyalar: `app/src/main/cpp/{hand_kinematics.h,hand_kinematics.cpp,jni_bridge.cpp,CMakeLists.txt}`,
`app/src/main/java/com/nexus/vr/HandKin.java`, `NativeCam.java`, `web/js/131-hand-feat.js`, `web/js/13-hand.js`.

## 3. İçi boş siyah parmak konturları (`web/js/132-hand-contour.js`)

* El başına **tek dörtgen**; şekil fragment shader'da işaretli uzaklık alanı ile hesaplanır.
* Her parmak kendi eklem zincirinin inceltilmiş kapsüllerinden oluşur ve **ayrı halka** olarak çizilir:
  parmaklar birbirine değse de tek lekeye dönüşmez. Avuç ince çizgidir; parmakların içinden geçen kısmı çizilmez.
* Yalnızca `|uzaklık| < kalınlık/2` boyanır → **içi tamamen boş**; arka plan / kamera görüntüsü / sahne görünür.
* Kalınlık piksel cinsinden sabittir (fwidth ile kenar yumuşatma), kamera çocuğu olduğu için stereo'da iki gözde aynıdır.
* Kare başına CPU işi: 21 nokta + 21 yarıçap uniform'u. Geometri/malzeme bir kez kurulur. Parmak başına sınır çemberi ile uzak pikseller atlanır.
* Kamera arka planı (native önizleme, FILL_CENTER kırpması) açıkken analiz koordinatları ekrandaki önizlemeye eşlenir;
  kontur gerçek elin üstüne oturur ve dokunulan yer görünen yer olur.
* Ölçüm kesilince kontur ölçüm aralığının ~2.5 katı (110–300 ms) sonra ~120 ms'de söner.
* Ayar: Ayarlar → El → **El görünümü**: Parmak konturu (varsayılan) / Kontur + kumanda / Kumanda.
  Kontur modunda gövdesiz işaret ışını işaret parmağının ucundan çıkar.

## 4. Fizik, NPC, ses, görsel (goril dünyası)

* **Fizik** (`gorilla-phys.js`): sabit adım, küre/kapsül/kutu/OBB çarpıştırıcıları ve ızgara geniş evresi zaten vardı.
  Kare başına dizi/kapanış ayırmaları kaldırıldı; el temas olayları (temas başlangıcı, yaklaşma hızı, malzeme) eklendi.
  Ölçüm: 20 000 karede kare başına ≈ 0.005 ms (Node).
* **NPC** (`gorilla-npc.js`, yeni): durum makinesi (Boşta, Yürüyor, Keşif, Dönüyor, Engelden kaçıyor, Oyuncuyu gördü,
  Etkileşim, Geri dönüyor), 1 m ızgarada A* (görüş hattıyla sadeleştirilmiş yol), önü yoklayarak engel algılama,
  uzamsal karma ile NPC–NPC ayrışması, oyuncu–NPC iki yönlü çarpışma, meraklı/ürkek kişilik, elle dokununca tepki
  (zıplama + göğüs vurma). **LOD:** yakın her kare, orta her 3, uzak her 8, görüş dışı her 12 karede güncellenir;
  uzakta tek mesh (1 çizim çağrısı), yakında eklemli model (5 çizim çağrısı). 6 NPC ≈ 0.02 ms/kare (Node).
* **Ses** (`gorilla-audio.js`, yeni): 6 sesli havuz (PannerNode + Gain bir kez kurulur), sentezlenmiş sesler
  (goril "huu", göğüs vurma, malzemeye göre el teması, kuş), 90 ms tekrar önleme, 30 m üstü başlatılmaz,
  düşük seviyede HRTF yerine ucuz stereo. Ortam rüzgârı tek döngü.
* **Görsel:** 2'nin kuvveti dokular (64/128/256) + kalite ≥ 1'de anizotropik süzme, pişirilmiş temas gölgelemesi
  (yere yakın köşeler koyu), ağaç diplerinde tek InstancedMesh ile yumuşak gölge lekeleri, NPC altında gölge.
  Gerçek zamanlı gölge haritası/ağır post-process eklenmedi (mobil GPU bütçesi).

## 5. Performans ölçümü, uyarlanır kalite, ısı

* `web/js/041-prof.js` — **Prof**: input / el / oyun / fizik / NPC / UI / render bölümlerinin CPU süresi, kare aralığı,
  düşen kare sayısı, JS dışı duraksama (GC/derleme şüphesi), WebGL zaman sorgusu varsa GPU süresi
  (Android WebView'de çoğu cihazda yok → "ölçülemiyor" yazar, uydurmaz), darboğaz tahmini.
* **Performans monitörü** (Ayarlar → Grafik → Performans monitörü, ya da başlangıç ekranı Ayarlar): FPS, CPU/GPU kare
  süresi, bölüm süreleri, el çıkarım/gecikme/sonuç hızı/kamera FPS'i, iki elin güveni ve parmak bükülmeleri, landmark sayısı,
  kalite kademesi, termal durum, darboğaz, pencere/WebView/Android uygulaması sayısı, JS yığını, native yığın, boş RAM,
  goril fizik/NPC süreleri. Kapalıyken DOM'a dokunulmaz.
* **Uyarlanır kalite** (Performans / Dengeli / Kalite): FPS hedefin %85'inin altında 6 sn kalırsa bir kademe iner,
  25 sn rahat ve serinse çıkar, her değişimden sonra 10 sn bekler; termal ≥ 3'te hemen iner. El takibi bu kademeden etkilenmez.
* **Isı:** Android 10+ termal durum dinleyicisi → `__nxThermal`; destekleyen cihazda **sürdürülebilir performans modu**
  (saatler ısınınca ani düşmek yerine sürdürülebilir düzeyde sabitlenir).

## 6. Android tarafı

* Sensör yolu: diziler yeniden kullanılıyor, kuyrukta en fazla bir iş; çalıştığında EN SON yön gönderiliyor.
* Ana WebView renderer'ı ölürse uygulama kapanmıyor: ölü WebView ayrılıp Activity yeniden oluşturuluyor.
* `setRect2`: kırpma değişmediyse `Rect` ayrılmıyor, görünürlük değişmediyse `onResume/onPause` tekrarlanmıyor.
* `perfInfo` köprüsü: native yığın, Java yığını, boş RAM, düşük bellek, WebView/uygulama penceresi sayıları.
* NDK/CMake: `libnxhand.so` (arm64-v8a, armeabi-v7a; c++_static; 16 KB sayfa hizası).

## 7. Doğrulama

| Test | Sonuç |
|---|---|
| `node tools/nxhand.test.js` — C++ kinematiği g++ ile derlenip çalıştırılır (27 kontrol) + JNI köprüsü JDK başlıklarıyla derlenip dışa aktarılan işlevler `HandKin.java` ile karşılaştırılır | geçti |
| `node tools/gorilla-npc.test.js` — gerçek orman haritasında yol bulma, 90 sn dolaşma, engel/çarpışma, algılama, LOD, süre (25 kontrol) | geçti |
| `tools/e2e/hand-contour.e2e.js` — Chromium + WebGL'de uygulama açılır; native biçimli sentetik el mesajlarıyla kontur piksel analizi (siyah kenar, boş iç, tek parmak bükülmesi, el kaybı), monitör, goril NPC'leri | geçti |
| Mevcut tüm `tools/*.test.js` | geçti (yalnızca Stage 67'den kalma `shizuku.test.js` "başlık çubuğunda Klavye düğmesi" kontrolü önceden de başarısızdı) |
| Java sözdizimi (`javac`, Android sınıfları olmadan) | sözdizimi hatası yok |
| APK derlemesi (Gradle + NDK) | `.github/workflows/nexvr-apk.yml` GitHub Actions'ta derler; bu ortamda Android SDK indirilemediği için yerelde derlenmedi |

**Cihazda denenmedi.** Gerçek kamera, MediaPipe GPU delegate, CameraX döndürme, termal dinleyici, sürdürülebilir
performans modu, uyarlanır takip çözünürlüğü ve gerçek FPS/gecikme değerleri fiziksel Android cihazda ölçülmelidir.
Masaüstü testlerindeki süreler (µs/ms) cihazdaki değerler değildir.

## 8. Bilerek yapılmayanlar (gerekçeli)

* **OpenXR / Vulkan:** uygulama WebView + WebGL (Three.js) üzerinde stereo çiziyor; OpenXR çalışma zamanı olan bir
  başlık ya da native renderer yok. Bunları eklemek ayrı bir native renderer yazmak demek; mevcut yapıyla uyumsuz.
* **NNAPI / ayrı TFLite modeli:** MediaPipe Tasks zaten GPU delegate (olmazsa CPU) kullanıyor; NNAPI yeni Android'de
  kullanımdan kalkıyor ve el modeli için ölçülmüş bir kazanç yok.
* **Kamera karesini doğrudan ByteBuffer ile MediaPipe'a verme:** MediaPipe'ın kareyi eşzamanlı kopyaladığı cihazda
  doğrulanmadan uygulanmadı (yanlışsa kareler bozulur).
* **Her parmağa ayrı fizik çarpıştırıcısı:** goril hareketi el başına tek küre ile yapılıyor; parmak çarpıştırıcıları
  maliyet getirip oynanışa katkı vermiyor.
