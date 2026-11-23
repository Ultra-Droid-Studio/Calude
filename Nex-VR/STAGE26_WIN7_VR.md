# Stage 26 — Windows 7 (VR paneli): çözünürlük, ölçek, el kontrolü, tarayıcı WebView

## Kök nedenler (kodda bulundu)
| Şikâyet | Neden |
|---|---|
| Çözünürlük çok düşük | Win7 paneli 2,8 m genişliğinde ama dokusu **1024×439** tuvaldi; içine de WebView'in **≤800×500, JPEG kalite 52, RGB_565** küçültülmüş görüntüsü basılıyordu. |
| Her şey "kocaman" | WebView fiziksel piksel genişliğinde (≤960) açılıyordu → sayfa kendini **~350 CSS pikselde, telefon boyutunda** görüyordu. Görev çubuğu/simge/pencere/Başlat menüsü o ölçekte büyük çıkıyordu. |
| Kontroller kötü / pencere sürüklenmiyor | Web panellerine el çimdiği hiç iletilmiyordu. Yalnızca bakışla 3 sn bekleyip **tek dokunuş** vardı; `ACTION_MOVE` hiç gönderilmiyordu. Düz canvas düğmeleri de çimdikle değil yalnızca "bekleme" ile tıklanıyordu. |
| İçerideki tarayıcılar | Win7'nin iç tarayıcı pencereleri ayrı yerel WebView'lerdi ama görünmez ana görünümün anlık görüntüsüne **dahil olmuyorlardı** (boş görünür / ekranda asılı kalabilirdi). |

## Yapılanlar
**Çözünürlük** — Doku artık tuvalden değil doğrudan WebView görüntüsünden (`THREE.Texture`, mipmap + anizotropi). Varsayılan 1600×686 (CSS 1280 × netlik 1.25), kalite 80. Sıkıştırma arka plan iş parçacığında, görüntü base64 yerine `/_snap/<jeton>/<id>` adresinden ikili sunuluyor (JS dizgesi yok). Kare **değişmediyse** (JPEG özeti aynı) doku yüklenmez ve yenileme aralığı 300→1500 ms'ye uzar. Etkileşimde 60 ms aralık, 1280 px/kalite 62; durunca tam netlikte kare gelir.

**Ölçek** — Win7 `?vr=1` ile açılır; sayfa `viewport width=1280` kullanır (`window.__w7setW`). Başlat menüsü, görev çubuğu, simgeler, pencereler gerçek masaüstü oranına iner. Ayarlar → El takibi bölümünde **Win7 arayüz boyutu** (%80…%160) ve **Win7 netlik** (1.0–2.0×) satırları.

**El kontrolü** — Çimdik = gerçek dokunma akışı (`touchView`: bas / sürükle / bırak). Pencere başlığını çimdikleyip sürükle, kaydır, simge seç. 12 px titreme payı (tıklama bozulmaz), MOVE 16 ms'de bir. Masaüstü simgesi çift tıklaması 450→750 ms. Ayrıca **tüm panellerde** düz canvas düğmeleri artık çimdikle (bırakınca) tıklanır; bekleme sayacı çift tetiklemez.

**Tarayıcılar** — Win7 içindeki tarayıcı WebView'leri görünmez kalır ve ana görüntüye **birleştirilerek** çizilir (görünürlük/kırpma korunur); dokunuşlar üstteki tarayıcıya yönlendirilir. Ana görünüm gizlenince alt WebView'ler ekranda asılı kalmaz. Köprü, fiziksel/CSS piksel oranını `__NXW`'dan alır.

## Dosyalar
`MainActivity.java` (touchView, snap2, setViewScale, setNestedVirtual, /_snap/) · `index.html` (BF canlı doku, Input, ayarlar) · `win7simu.html` (VR ölçek betiği, köprü oranı) · test: `node tools/w7touch.test.js`.

## Cihazda doğrulanmadı (derleme/SDK/cihaz yok) — ilk bakılacaklar
1. APK derlenir mi (`javac` burada yoktu; yalnızca parantez dengesi + sözdizimi kontrolü yapıldı).
2. Arayüz hâlâ büyük/küçükse **Win7 arayüz boyutu** ayarı; metin okunmuyorsa boyutu büyüt veya netliği 1.5×'e çıkar.
3. Sürükleme akıcılığı cihaz GPU/CPU'suna bağlı (WebView yazılım çizimi). Düşükse netliği 1.0× yap.
4. Gerçek WebXR oturumunda (`XR.session`) web panelleri eskisi gibi gizli kalır.

## Yapılmadı
- Win7 içindeki metin alanlarına VR klavyesiyle yazma (WebView odağı ↔ vkb köprüsü yok).
- Bağımsız `Win7Activity` (dock'tan açılmıyor) hâlâ iframe tabanlı; WebView köprüsü yalnızca VR panelinde.
