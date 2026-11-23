# Stage 34 — Açılış başlatıcı sahnesi (Nexus VR Launcher)

## İstek
Uygulama açılınca, verilen görseldeki gibi bir başlatıcı sahnesi görünsün. İçindeki düğmeler
çalışsın (Başlat, Ayarlar, Kalibrasyon, VR Ayarları, Hakkında, Çıkış, üstteki dişli, Hızlı Erişim).
«VR Launcher» yerine **Nexus VR** yazsın. Bu sahnede el takibi açılıp kapanabilsin.

## Akış
Boot tamamlanınca eski yükleme ekranındaki «Başlat» yerine bu sahne açılır.
**Başlat** → `App.enter()` (VR masaüstü). Eski «NEXUS VR'a hoş geldiniz» animasyonu bu yolda atlanır;
sahne açılamazsa otomatik olarak eski açılışa (`Intro.run`) dönülür.

## Sahne
- Gece odası arka planı, kavisli cam panel (sol/sağ sütunlar CSS 3B ile yana yatık), dağ-göl manzaralı orta kart.
- Sol: logo + `Nexus VR v1.0.0`, menü (Ana Menü, Ayarlar, Kalibrasyon, VR Ayarları, **El Takibi** anahtarı, Hakkında, Çıkış).
- Orta: büyük gözlük simgesi, `Nexus VR`, slogan, açıklama, **Başlat**.
- Sağ: pil (%) + Wi-Fi + dişli, Uygulama Bilgisi, VR Durumu, Hızlı Erişim (Kalibrasyon / VR Ayarları / Tema).
- Alt: ipucu çubuğu.
- Sahne 1672×941 tasarım boyutunda çizilir, ekrana sığacak şekilde ölçeklenir.

## İşlevler (hepsi gerçek ayar/modüle bağlı)
| Düğme | Ne yapar |
|---|---|
| Başlat | VR masaüstünü açar (`App.enter`) |
| Ayarlar | vurgu rengi, hareketi azalt, ekranı açık tut, kamera geçişi, düşük güç, FPS sayacı, el çizimi (`Settings.v`) |
| Kalibrasyon | bakış yönünü sıfırla (`Cam.reset`), hareket sensörü aç/kapat, el takibi, kamera ön/arka, çimdik hassasiyeti, el yumuşatma, **canlı çimdik testi** |
| VR Ayarları | 8 gözlük profili + «Uygula», gözler arası mesafe, görüş açısı, dikey hiza, performans ölçeği (VR panelindekiyle aynı anahtarlar) |
| El Takibi | `Hand.start()/stop()`; sol menüde ve Kalibrasyon sayfasında anahtar |
| Hakkında | sürüm, geliştirici, platform, WebXR durumu, el takibi durumu |
| Çıkış | 3 sn içinde iki kez dokun → `AndroidBridge.exitApp` (uygulamayı kapatır) |
| Tema | 4 vurgu rengini döndürür (sahne + VR masaüstü) |
| Üstteki dişli | Ayarlar |
| VR Durumu kartı | `XR.check()` ile VR cihazını yeniden denetler |
| Pil / Wi-Fi | `navigator.getBattery`, `navigator.onLine` (API yoksa pil gizlenir) |

## El takibi bu sahnede
Eller açıkken `Hand.arbitrate()` sahneye yönlenir: işaret parmağı imleç (üzerine gelince düğme parlar),
**çimdik = tıklama** (kenar tetikli, 380 ms bekleme). Kamera görüntüsü/el çizimi `#hd` katmanında
(z-index 46) sahnenin (45) üstünde görünür. Kamera döndürme (look) bu sahnede devre dışıdır.
Eller açıkken Başlat'a basılırsa takip VR masaüstünde de sürer.

## Değişen dosyalar
- `index.html`: `LOBBY:CSS` / `LOBBY` blokları, `Hand.arbitrate` kancası, `App.boot` sonu.
- `MainActivity.java`: `exitApp(String t)` köprü metodu (token doğrulamalı, `finishAndRemoveTask`).
- `tools/lobby.test.js`: yeni statik test (34 kontrol).

## Test
`node tools/lobby.test.js` ve diğer tüm `tools/*.test.js` geçti. Ayrıca Chromium (Playwright) ile sahne
bağımsız bir sayfada çizilip 31 işlev kontrolü yapıldı: tüm menüler, anahtarlar, adımlayıcılar, profil uygulama,
tema döngüsü, el takibi aç/kapat, Çıkış çift dokunuşu, sahte elle çimdik → Başlat.

## Sınır
- Android derlemesi ve cihaz testi bu ortamda yapılamadı (SDK/ağ yok). Gerçek kamera/MediaPipe ve
  `exitApp` yalnızca kaynak düzeyinde doğrulandı. Cihazda ilk denenecekler: El Takibi anahtarı → çimdikle
  Başlat, Çıkış çift dokunuşu, pil yüzdesi.
- Manzara ve oda arka planı kod ile çizilmiş vektör çizimlerdir (görselin birebir fotoğrafı değil).
- `VR Durumu` yeşil onay işareti görseldeki gibi hep yeşildir; metin gerçek WebXR durumuna göre değişir.
- Sürüm metni görseldeki gibi `v1.0.0` (uygulamanın `versionName` değeri 1.4).
