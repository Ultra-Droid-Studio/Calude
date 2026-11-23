# Stage 67 — Android uygulama penceresi, web app penceresiyle aynı görünüme getirildi

## İstenen
- Android uygulamalarını açan pencere (Shizuku ile yansıtılan gerçek uygulamalar), web
  uygulamalarını açan pencereyle aynı görünsün.
- Pencerenin üstündeki ayrı çubuk (kapsül) kaldırılsın.
- Pencerede yukarı/aşağı kaydırma ve dik/yatay mod değiştirme kalsın.
- Alttaki pil'e (pencere taşıma çubuğu) bir taşıma tutamacı eklensin.

## Değişiklik — `app/src/main/assets/index.html`

### `SHZ.def(id).render(...)`
Eskiden pencerenin **dışında**, hemen üstünde ayrı, koyu kapsül şeklinde bir çubuk
vardı (Kapat, "Normal ekranda aç", Dik/Yatay, aşağı/yukarı ok, Geri, Klavye —
hepsi tek satır, pencerenin üstünde yüzen bir kapsülde). Bu tamamen kaldırıldı.

Artık pencere, web app pencereleriyle birebir aynı yapıda: tek parça, köşeleri
yuvarlak, tam pencereyi kaplayan bir uygulama alanı — üstte ayrı bir çubuk yok.
Döndürme, kaydırma, geri ve "gerçek ekranda aç" işlevleri kayboldu değil; pencere
içeriğinin **sağ üst köşesine** küçük, tek tek yuvarlak yüzen ikonlar olarak
taşındı (bir çubuk değil, ayrı ayrı ikonlar — `ghost` stil, sadece üzerine
gelince belirginleşiyor). Shizuku bağlantı noktası da sol üst köşeye küçük bir
noktaya indirildi.

Kapat/Küçült/Büyüt/Klavye düğmeleri zaten alttaki pil'de (`Pill`) vardı; bu
pencere için ayrıca tekrar çizilmiyordu, o yüzden onlar aynen kaldı.

### `Pill.paint(...)` (alttaki taşıma çubuğu)
Pil zaten her pencerede (web app da dahil, Shizuku penceresi de dahil) vardı ve
üzerinden tutup sürükleyince pencereyi taşıyordu — ama bunu gösteren bir işaret
yoktu. Artık pilin üst ortasında ince, yarı saydam bir **tutamaç çizgisi**
var; bu, pilin "taşıma çubuğu" olduğunu görsel olarak belli ediyor. İşlev
değişmedi, sadece görünür hale geldi.

## Sonuç
İki pencere türü artık aynı iskeleti paylaşıyor: üstte çubuk yok, köşeleri
yuvarlak tek bir içerik alanı, gerekli küçük kontroller köşelerde ikon olarak,
taşıma/kapat/küçült/büyüt/klavye alttaki pil'de ve pilin üstünde görünür bir
taşıma tutamacıyla.

---

# Stage 68 — Ayarlar → Grafik: Pencere uzaklığı ve Dok uzaklığı

## İstenen
Ayarlar → Grafik kısmına, pencerelerin (ve dock'un) kullanıcıya ne kadar
uzak/yakın duracağını metre cinsinden seçebileceğimiz iki ayar eklensin.

## Değişiklik — `app/src/main/assets/index.html`
- `DEF`'e `wdist:2.9` (pencere uzaklığı, metre) ve `ddist:1.8` (dok uzaklığı,
  metre) eklendi. Eski kayıtlı ayarlarda bu alanlar yoksa `Object.assign({},
  DEF,Storage.get())` zaten varsayılana düşüyor, sorun çıkmaz.
- `WM.create(def)`: kendi `R` (uzaklık) değerini özel olarak belirtmeyen
  sıradan pencereler (tarayıcı, ayarlar, web uygulaması, Android uygulaması
  vb.) artık `Settings.v.wdist`'i; dock ise `Settings.v.ddist`'i kullanıyor.
  Klavye, sinema ekranı, el menüsü, gezegen menüsü gibi kendi `R`'sini zaten
  belirten özel paneller bundan etkilenmiyor (bozulmasınlar diye).
- `WM.applyDist()` (yeni): ayar değişince *açık* pencerelere ve dock'a hemen
  uygulanır — pencereyi kapatıp yeniden açmaya gerek yok.
- Ayarlar → Grafik sekmesine iki yeni satır: **"Pencere uzaklığı"** (1.2–5 m,
  0.2 m adım) ve **"Dok uzaklığı"** (0.8–3.2 m, 0.1 m adım). `rowsCard(11)` →
  `rowsCard(13)`.
