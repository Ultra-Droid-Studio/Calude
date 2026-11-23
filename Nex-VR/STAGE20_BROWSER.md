# Stage 20 - Tarayıcı: çoklu sekme, yer imi listesi, geçmiş, reklam engelleyici, PC sürümü

Stage 19 (Katalog) üzerine kuruludur. Değişen dosyalar: `index.html` (BR nesnesi + tarayıcı paneli, `BF.load`, `drawSnapshot` başında 1 satır),
`MainActivity.java` (reklam engelleyici + PC sürümü), `tools/browser.test.js` (yeni). Win7, gorilla ve katalog koduna dokunulmadı.

Fikir kaynağı: PhoneXR tarayıcısının özellik listesi (başlangıç sayfası, yer imleri, geçmiş, PC sürümü, reklam engelleyici). PhoneXR'da lisans dosyası
olmadığı için ondan kod alınmadı; hepsi bu projenin yapısına göre sıfırdan yazıldı. Reklam ana makine listesi bilinen reklam/izleme alan adlarından ayrıca derlendi.

## Kullanım
- **Sekmeler:** şeritte en çok 5 sekme. `+` yeni sekme, her sekmede `x` kapatır, başka sekmeye dokununca geçer. Son sekmeyi kapatmak onu sıfırlar.
- **Başlangıç sayfası** (sayfa açık değilken), PhoneXR tarayıcısının başlangıç sayfası gibi görünür: koyu gradyan zemin, büyük **Tarayıcı** başlığı,
  yuvarlak **Ara veya adres gir** çubuğu (dokununca klavye açılır), renkli büyük kareler, `#2c2c2e` kartlarda satır listeleri, turuncu vurgu (`#ff9544`),
  iOS tarzı yeşil anahtarlar. Sağ üstte dört bölüm çipi: **Favoriler / Yer imleri / Geçmiş / Ayarlar**.
  Yer imleri ve geçmiş sayfa başına 4 satır, sayfalı; her satırda turuncu **Sil**. Geçmişte **Temizle** var. **Ayarlar** bölümünde PC sürümü ve Reklam engelleyici anahtarları ile Yeni sekme satırı bulunur.
- **Yer imi sınırı** 8'den 200'e çıktı (araç çubuğundaki yer imi simgesi aynı şekilde ekler/kaldırır).
- **Geçmiş:** son 100 adres, art arda aynı adres tekrar yazılmaz. Geri/ileri geçmişe eklemez. `Settings.v.hist` içinde kalıcıdır.
- **Menü (⋮):** PC sürümü, Reklam engelleyici (anahtarlar), Yer imleri, Geçmiş, Yeni sekme, (sayfa açıkken) Tarayıcıda aç. Dışına dokunmak kapatır.
  Anahtar değişince açık sayfa yeniden yüklenir. Ayarlar `Settings.v.desk` ve `Settings.v.adb` içinde kalıcıdır.

## Görünüm hakkında
Görünüm yalnızca PhoneXR'ın `home.html` başlangıç sayfasından esinlendi (renk paleti, yerleşim düzeni, bölümlerin sırası); kod ya da stil dosyası kopyalanmadı, her şey bu projenin canvas çizimiyle yeniden yazıldı.
PhoneXR'ın pencere çerçevesi, sekme ve adres çubuğu Wolvic'in kendi arayüzü olup elimizdeki dosyalarda yoktur; o yüzden sekme şeridi ve araç çubuğu NEXUS'un mevcut Quest tarzı görünümünde kaldı.
`screenshots/` klasöründeki görüntüler, gerçek çizim kodunun Chromium'da sahte ikonlarla çizilmiş halidir (araç çubuğu ikonları ve sayfa okları yer tutucudur); cihazdaki görüntü birebir böyle olmayabilir.

## Nasıl çalışıyor
- **Sekmeler tek WebView paylaşır.** Her sekme kendi geri/ileri geçmişini tutar; sekme değişince sayfa yeniden yüklenir (kaydırma konumu ve form içeriği korunmaz).
  Sekmeler uygulama kapanınca korunmaz (yalnızca yer imleri ve geçmiş kalıcı).
- **Reklam engelleyici:** `AndroidBridge.setAdBlock(on)` -> `MainActivity.adBlock`; `intercept()` içinde reklam/izleme ana makinelerine (ve alt alan adlarına) giden istekler boş 204 döner.
  Yalnızca ana makine adına bakar; sitenin kendi alan adından sunulan reklamları (ör. YouTube video araları) engellemez. Tüm alt WebView'lere (web uygulamaları dahil) uygulanır.
- **PC sürümü:** `AndroidBridge.setDesktopMode('nexus-browser', on)`; masaüstü Chrome kullanıcı aracısı (sürüm cihazın WebView'inden alınır) + sayfayı sığdırma.
  Kimlik, WebView oluşmadan önce de kaydedilir; `create()` oluştururken uygular, oluşmuşsa hemen değiştirir. Kapatınca sistem varsayılanına döner.
- Eski bir APK'da bu iki köprü yöntemi yoksa arayüz hata vermez (try/catch), yalnızca özellik etkisiz kalır.

## Doğrulananlar (bu ortamda, Node)
`node tools/browser.test.js` (82 kontrol): adres güvenliği (`norm`) eskisi gibi; geçmiş (yinelenen atlama, 100 sınır, tek silme, temizleme);
yer imi 8'den fazla ve silme; sekme açma/kapama/geçiş ve sekme başına geçmiş (1-5 sekme); PC sürümü ve reklam engelleyicinin köprüye doğru
anahtarla gitmesi, köprü yokken/eski köprüde çökmemesi; çizimde tüm görünümlerde (3 görünüm x sayfalar, menü, açık sayfa, 1-5 sekme) düğmelerin
pencere içinde, sayısal ve çakışmasız olması; menü kapatma alanının satırlardan önce çizilmesi. Eski gorilla testleri aynen geçiyor; `index.html` betikleri `node --check` temiz.

## DOĞRULANMADI / AÇIK EKSİKLER
- **Java derlenmedi** (bu ortamda javac/Gradle yok); `MainActivity.java` değişikliğini yalnızca elle gözden geçirdim (parantez dengesi tutuyor). Derlemede hata çıkarsa bana yaz.
- **Gerçek cihazda hiçbiri denenmedi:** menünün konumu/dokunma hissi, PC sürümü düzeninin görünümü, reklam engelinin gerçekte neyi kestiği.
- PC sürümünde alt WebView sanal genişliği ≤ 960 px olduğundan masaüstü düzeni küçültülmüş görünür; metin küçük olabilir.
- Google gibi bazı siteler gömülü WebView'da oturum açmayı yine engelleyebilir; PC sürümü bunu çözmez.
- Sekme görünümü yalnızca başlık (alan adı) gösterir; sekme önizlemesi, sürükleyip sıralama, gizli sekme yok.
- PhoneXR'daki gibi WebXR siteleri VR içinde açılmaz (`VR içinde sayfa açılamaz` kısıtı sürüyor); WebXR polyfill bu aşamada eklenmedi.
