# Stage 18 - Orman kanyonu, gorilla modeli, gerçek el kontrolü, VR

Stage 17 çekirdeği üzerine kuruludur. Win7 simülatörü, normal tarayıcı, Java dosyaları ve Stage 16 kaydırma kodlarına dokunulmadı.
`index.html` içinde yalnızca 2 satır değişti: `gorilla-art.js` script etiketi ve `Hand.arbitrate()` başında
"oyun elleri sahiplendiyse panel etkileşimi üretme" koruması.

## Neden "birebir aynısı" değil
İstenen görünüm (kare/low-poly orman kanyonu, tahta köprüler, gri göğüslü goriller, şapkalı topluluk) bu sürümde **özgün bir
yorumla** yapıldı. Oyun varlıklarının (modeller, dokular, harita) birebir kopyası yapılmadı: bunlar başka bir stüdyonun telif hakkı
altındadır ve zaten bu ortamdan erişilemez. Tüm dokular canvas ile kod içinde üretilir, dışarıdan görsel dosyası yoktur.

## Yeni / değişen dosyalar
| Dosya | İçerik |
|---|---|
| `gorilla-phys.js` | Yeni çarpışma türleri: **eğik kutu (obb)**, **dal (kapsül)**, **kanyon duvarı (ring)**; xz ızgarasıyla hızlı geniş evre; `forestMap()` (tohumlu, deterministik harita). Eski 18 test aynen geçer. |
| `gorilla-art.js` (yeni) | Dokular (kabuk, kaya, tahta, zemin, kiremit, tüy, yaprak, alev), saf-JS geometri üreticileri, facet normaller, malzeme başına **tek çizim çağrısı** birleştirme, gorilla modeli, oyuncu gövdesi/kolu/eli (iki kemikli dirsek IK, açık el/yumruk). |
| `gorilla.js` | Yeni dünya/avatar, 3 girdi kaynağı, kalite profilleri, menü (tüy rengi, kalite, kamera eli). |
| `tools/*.test.js` | `gorilla-forest`, `gorilla-art` yeni; `gorilla-smoke` yeniden yazıldı. |

## Harita (Emerald Forest yerine "Orman Kanyonu")
Dairesel kaya kanyon (çarpışmalı duvar, dışarı çıkılamaz), 16 tırmanılabilir ağaç + 79 tırmanılabilir dal, 285 yaprak kartı
(tek InstancedMesh), 8 tahta platform ve aralarında eğimli köprüler, 2 zemin rampası, direkler üzerinde ağaç evi + uzun rampa,
beyaz direkli kiremit çatılı kulübe, kaya blokları, ortada animasyonlu şenlik ateşi ve etrafında oturan 5 gorilla (şapkalı, süs).

## Kontroller
1. **Kamera ile gerçek el** (telefon/tablet): elini ön kameraya göster. Ekrandaki konum = kol yönü, el kameraya yaklaşırsa ileri uzanır,
   **yumruk = tut**. Soldaki el sol, sağdaki el sağ el. Menüden hareket ölçeği ayarlanır. Kamera yalnızca "Oyuna başla"
   dokunuşunda açılır (ilk kullanımda mevcut gizlilik onayı sorulur; MediaPipe modeli internetten yüklenir).
2. **WebXR denetleyicileri** (Quest vb.): oyun VR oturumunda açılır, menüsüz başlar. Squeeze/tetik = tut, A/X = destekli zıplama.
   Gövde, baş konumunun 0,25 m altında tutulur (oda ölçeğinde yürüyerek ilerleme yoktur; ilerleme eller ve fizikle olur).
3. **Dokunmatik**: Stage 17'deki gibi, yedek olarak kalır. El öncelik sırası: VR denetleyici > kamera eli > dokunma > dinlenme.
4. **Telefon VR (Stereo/Cardboard)**: menü beklemeden oyun başlar, kamera eli açılır.

## Performans tasarımı
- Tüm tahta/kaya/gövde/kiremit yüzeyleri malzeme başına tek mesh; toplam yaklaşık 16 çizim çağrısı (zemin, duvar, yaprak, 3 ateş kartı, 5 NPC dahil).
- Gorilla ~730 üçgen. NPC ve yaprak sayısı kaliteyle azalır (düşük: 128/285 yaprak, 3 NPC).
- Kalite: telefon = Düşük, tablet = Orta, masaüstü = Yüksek, VR = Orta; ayrıca **otomatik düşürme** (ortalama kare süresi ~33 ms üstü,
  VR'de ~15,5 ms üstü 2,5 sn sürerse bir kademe iner; kendiliğinden yükselmez, böylece salınım olmaz). Çözünürlük çarpanı 0,8/0,92/1.
- Gölge haritası yok; zemin dokusuna gölge lekeleri boyanır. Işık: yarım küre + tek yönlü.
- Çarpışma sorgusu ızgaralı (20 000 çözüm ≈ 30 ms Node'da).

## Doğrulananlar (bu ortamda, Node)
- Fizik: eski 18 test + yeni orman testleri: harita deterministik; başlangıçta ayakta; 8 platform ve köprü ortası, ağaç evi zemini, kulübe çatısı taşıyor;
  kanyondan çıkılamıyor; ağaca tutunarak tırmanma (1,0 -> 9,3 m); 30 000 rastgele adımda NaN/dışarı/altına düşme yok.
- Geometri: normaller dışa bakıyor, öznitelik uzunlukları tutarlı, gorilla ateşe bakıyor.
- Duman (sahte THREE/DOM): dokunma, kamera eli (taraf atama, yumruk, yükseklik, derinlik, takip kaybı), XR (denetleyici->el çevirisi, rig kayması,
  squeeze, A/X zıplama, oturum bitince geri dönüş), otomatik kalite, telefon/tablet profili, stereo otomatik başlama, 20 aç/kapat'ta **GPU kaynağı sızıntısı yok**.
- `index.html` satır içi betikleri `node --check` ile temiz.

## DOĞRULANMADI / AÇIK EKSİKLER (dürüst liste)
- **Gradle/APK derlenmedi; gerçek cihazda, gerçek WebView'da, gerçek WebGL'de ve gerçek VR başlığında çalıştırılmadı.** Bu ortamda gerçek THREE ve ağ yok;
  görünüm (renkler, doku ölçeği, yaprak yoğunluğu, ateş), kare hızı, ısınma ve dokunmatik/el hissi cihazda ayarlanmalıdır. Sayılar (kalite eşikleri, el ölçekleri) başlangıç değeridir.
- **Kamera el eşlemesi sezgiseldir**: derinlik, görünen el boyutundan tahmin edilir (MediaPipe z güvenilir değil); kamerayla itiş hissi cihazda ve ışıkta değişir.
  Tek kamerayla gerçek 3B konum yoktur. Yumruk eşikleri (1,5 / 1,85) cihazda ince ayar isteyebilir.
- XR yolu: `getController` konumu hedef ışını kökenidir (grip uzayı değil); `inputSource.gamepad` düğme eşlemesi Quest düzenine göredir. Başka denetleyicilerde ayar gerekebilir.
  Quest el izleme (parmak) kullanılmıyor. VR'de DOM menüsü çizilmez; çıkış başlığın kendi menüsüyle.
- Stereo modda DOM arayüzü çift göze çizilmez (Stage 17'den kalan); oyun el/gyro ile oynanır.
- Çok oyunculu, tag kuralları, ses, mağaza, kozmetik envanteri yok; NPC'ler hareketsiz süstür.
- `three.min.js` projede yok (derlemede indirilir); `gradle-wrapper.jar` hâlâ eksik.

## Testler
```
node tools/gorilla-phys.test.js
node tools/gorilla-forest.test.js
node tools/gorilla-art.test.js
node tools/gorilla-smoke.test.js
```
