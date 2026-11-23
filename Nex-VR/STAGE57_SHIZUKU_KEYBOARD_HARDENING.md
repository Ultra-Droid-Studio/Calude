# Stage 57 — Shizuku: klavye desteği + sağlamlaştırma

Stage 56 prototipinin üstüne. Hedef: VR penceresindeki Android uygulamasına yazabilmek ve uygulamayı açarken
"siyah pencere / sessiz hata / takılma" çıkmaması.

## Yeni: klavye
- Uygulama penceresinin altındaki hapta **Klavye** düğmesi (ve başlık çubuğunda **Klavye** düğmesi) cam Türkçe klavyeyi
  **canlı mod**da açar: her tuş hemen uygulamaya gider (⌫ = Sil, ↵ = Enter). **Kapat** düğmesi / Esc kapatır.
- Kullanım: önce uygulamada yazı alanına çimdikle dokun (odak alsın), sonra klavyeden yaz.
- Fiziksel klavye bağlıysa o da çalışır; ayrıca yön tuşları, Tab, Delete, PageUp/Down, Home/End gönderilir.
- Java: `AndroidBridge.shzText(id, metin, jeton)` (en çok 64 karakter, jeton şart) ve `shzKey` artık **beyaz liste** ile
  çalışır: GERİ, Boşluk, Tab, Enter, Sil, Esc, ileri-Sil, yön tuşları, PageUp/Down, Home/End. Ana ekran, Güç, Ses,
  Son uygulamalar, Menü **gönderilemez**.
- ASCII karakterler standart (ABD) sanal klavye tuş dizisine çevrilir (Shift dahil). Tuş olayları artık klavye kaynaklıdır.
- **Doğrulanmadı / bilinen sınır:** `ç ş ğ ı ö ü İ` gibi ASCII dışı harfler tuş kodu olmadığı için `ACTION_MULTIPLE`
  ile denenir; bu yol Android sürümüne ve uygulamaya bağlıdır, çalışmayabilir (çalışmazsa harf yazılmaz, günlüğe düşer).
  Gerçek cihazda denenmedi. Çalışmazsa sonraki adım: panoya yazıp yapıştırma.

## Bulunan ve düzeltilen sorunlar (kod incelemesiyle)
1. **Eski servis sürümü:** Stage 56'dan kalan bir servis, AIDL değiştiği halde yeniden kullanılabilirdi. Servis
   sürümü 2'ye çıktı ve bağlanınca `version()` doğrulanıyor; uyuşmazsa servis yeniden başlatılıyor.
2. **Kapanış yarışı:** `onDestroy`'da uygulama durdurma isteği ile Shizuku bağlantısını kesme aynı anda çalışıyordu;
   durdurma çoğu kez yetişmiyor, uygulama sanal ekran silinince gerçek ekrana taşınıp açık kalıyordu. Artık kapanış
   en çok 1,5 sn beklenir, sonra bağlantı kesilir.
3. **Sessiz başarısızlık:** `am start` çıktısı atılıyor, "Activity not started… brought to the front" (uygulama başka
   ekranda açık, singleTask/singleInstance) başarı sayılıyordu → siyah pencere. Artık çıktı okunuyor; bu durumda
   uygulama durdurulup **bir kez** yeniden başlatılıyor (uygulamanın açık oturumu kaybolur).
4. **Takılma:** `am` komutuna zaman aşımı yoktu (servis iş parçacığı sonsuza kadar bloklanabilirdi). Artık 8 sn.
5. **Tek deneme:** açılış servis bağlanmadan / sanal ekran hazır olmadan başarısız olunca hemen gerçek ekrana
   düşülüyordu. Artık en çok 3 deneme, artan bekleyiş, servis için 2,5 sn bekleme; JS tarafında da 4 deneme.
6. **Kopma:** servis düşünce yeniden bağlanma yoktu. Artık 4 kereye kadar otomatik (artan aralıkla); pencere başlığında
   bağlantı noktası (yeşil = bağlı, turuncu = "Shizuku bağlanıyor…").
7. **Ölü pencere:** uygulama ilk kareyi hiç vermezse pencere sonsuza kadar siyah kalıyordu. 10 sn sonra uyarı verilip
   normal ekranda açılıyor; neden mesajı kullanıcıya gösteriliyor (başka ekranda açıktı / görüntü yok / Shizuku / hata).
8. **Arka planda boşa iş:** VR etkinliği arka plana gidince sanal ekranlar JPEG üretmeye devam ediyordu; artık duruyor.
9. **Sınırsız pencere:** en çok 3 eşzamanlı uygulama penceresi (zayıf cihazlarda bellek/ısı için).

## Doğrulama (bu ortamda yapılanlar)
- `node tools/shizuku.test.js`: **115 kontrol geçti** (Stage 56'dakiler + yeni: sürüm tutarlılığı, launch kodları,
  tuş beyaz listesi, jeton/uzunluk sınırları, yaşam döngüsü, KBD canlı mod mantığı çalıştırılarak).
- index.html betiği `node --check` ile söz dizimi temiz.
- Diğer tüm `tools/*.test.js` dosyaları Stage 56 ile **aynı sonucu** veriyor (20'si geçiyor). Önceden kalan iki durum:
  `mcworld-smoke` Node'da tarayıcıya ait `Image` olmadığı için başarısız, `browser.test.js` 92 kontrolü geçiyor ama süreç kapanmıyor.
  Not: `winhand.test.js` `KBD` nesnesinin `sym:false,` satırını bağlantı noktası olarak kullanır; Stage 57'de yeni alanlar o satırın dışında tutuldu.
- `ShellService`, `ShizukuLink`, `AppMirror` **Android/Shizuku taslaklarına karşı derlendi** (tür hatası yok).
  `MainActivity` yalnızca ayrıştırıldı (söz dizimi), tam derlenmedi.
- `ShellService.launch/stopPackage` sahte bir `am` komutuyla gerçekten çalıştırıldı: başarı → 0, "brought to the front" → 10,
  "Error:" / SecurityException → 11, takılan komut → 8 sn sonra -1, geçersiz bileşen/ekran/paket reddediliyor.

## Doğrulanmadı (cihazda denenmedi)
- Gerçek AIDL/Gradle derlemesi (ilk derlemede hata çıkarsa Gradle çıktısını paylaş).
- Yazı alanına yazma (özellikle ASCII dışı harfler), IME'nin sanal ekranda davranışı, Android sürümüne göre farklar.
- Singleton uygulamalarda "durdur + yeniden başlat" yolu, gerçek cihazdaki zamanlamalar.

## Sorun giderme
Günlük etiketleri: `NEXUS-Shizuku`, `NEXUS-Mirror`. Yeni iletiler: "görev başka ekranda öne alındı…",
"kabuk servisi sürümü uyuşmuyor", "sanal ekrandan kare gelmedi", "metin kısmen yazıldı n/m".

## Dosyalar
Değişen: `IShellService.aidl` (typeText=6, version=7), `ShellService.java`, `ShizukuLink.java`, `AppMirror.java`,
`MainActivity.java`, `assets/index.html` (`SHZ`, `KBD.live`, `BF.get`), `app/build.gradle` (sürüm 1.8 / kod 9),
`tools/shizuku.test.js`.
