# Stage 33 — VR açılışında kısayol çizimi güvenliği

## Sorun
Bazı eski/bozuk yerel kısayol kayıtlarında ana ekran çizimi sırasında kısayol renk/başlık hesaplaması beklenmeyen veri alabiliyordu. Kullanıcıya `Cannot read properties of undefined (reading 'length')` hatası gösterilerek VR başlatma akışı kesiliyordu.

## Düzeltme
- Tarayıcı ana sayfasındaki kısayol listesi çizimden önce dizi ve nesne türü açısından doğrulanıyor.
- URL alanı boş veya metin olmayan kayıtlar çizime alınmıyor.
- Başlık alanı eksikse URL ana bilgisayar adından güvenli varsayılan üretiliyor.
- Kısayol renk anahtarı `undefined`/`null` için boş metne dönüştürülüyor; karakterler güvenli biçimde dolaşılıyor.
- Varsayılan kısayollar ve mevcut kısayol davranışı korunuyor.

## Doğrulama
- App Store: 161 kontrol geçti.
- Tarayıcı: 92 kontrol geçti.
- GPU tarayıcı: tüm kontroller geçti.
- Gorilla/orman/fizik/el çizimi/ikon/Win7 ve diğer araç testleri: geçti.
- Android cihaz üzerinde gerçek WebXR oturum testi bu çalışma ortamında yapılamadı; APK'yı cihazda yeniden derleyip denemek gerekir.

## Ek güvenlik düzeltmesi (1.2)
- `pcol` renk seçimi artık yalnızca mevcut `PC` paletinin uzunluğuna güvenmiyor; palet eksik/bozuksa kendi güvenli varsayılan paletini kullanıyor.
- Kısayol sağlayıcısı bulunamazsa boş listeyle devam ediyor.
- Sürüm `1.2` / versionCode `3` olarak yükseltildi.
