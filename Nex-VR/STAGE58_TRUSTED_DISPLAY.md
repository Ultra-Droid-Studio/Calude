# Stage 58 — Uygulamalar VR penceresinden kaçmasın (güvenilir sanal ekran)

## Sorun
VR penceresindeki Android uygulaması (örn. HyperDroid) bir süre sonra gerçek ekranda ayrı uygulama gibi açılıyordu;
dosya/görsel seçici de aynı şekilde tam ekranda açılıyordu.

## Neden
Uygulamalar şimdiye kadar Nex VR'ın kendi açtığı sanal ekranda çalışıyordu. Android, başka bir uygulamanın
ekranına (başka uid) yeni görev olarak başka bir uygulamanın etkinliğini koymayı reddeder ve etkinliği gerçek
ekrana atar. Dosya seçici (sistem uygulaması) ve başlatıcı uygulamaların açtığı uygulamalar bu yüzden kaçıyordu.
`am start` komutu shell yetkisiyle çalıştığı için yalnızca ilk açılış bu denetime takılmıyordu.

## Çözüm
- Sanal ekran artık Shizuku kabuk servisinde, shell yetkisiyle **güvenilir (TRUSTED)** olarak açılır
  (`createDisplay` / `resizeDisplay` / `releaseDisplay`, AIDL kodları 8-10, servis sürümü 3). Güvenilir ekranda
  her uygulamanın etkinliği o ekranda açılır; seçici ve alt uygulamalar pencerenin içinde kalır.
- Ekran `DESTROY_CONTENT_ON_REMOVAL` ile açılır: pencere kapanınca görevler gerçek ekrana taşınmaz, yok edilir.
- Kare yolu aynı: ImageReader (uygulama sürecinde) → JPEG → VR dokusu. Yalnızca ekranı üreten taraf servise taşındı.
- **Yedek:** güvenilir ekran açılamazsa (Android 12 ve altı, izin reddi, üretici kısıtı) Stage 57'deki gibi uygulamanın
  kendi sanal ekranı kullanılır; hiçbir şey bozulmaz. Bu durumda günlükte `NEXUS-Mirror: güvenilir sanal ekran açılamadı` görünür.
- İlk kare bekleme süresi 10 sn → 20 sn: yavaş açılan başlatıcılar "ekranda görüntü vermedi" diye erkenden
  normal ekrana atılmıyordu.

## Doğrulanmadı (cihazda denenmedi, burada derlenemedi)
- Gizli API yansıması: `DisplayManager(Context)` kurucusu, `com.android.shell` bağlamı, `ActivityThread` sistem bağlamı.
  Samsung/One UI bunları farklı işleyebilir. Çalışmazsa günlükte `NEXUS-Shell: güvenilir ekran açılamadı (bayrak N): ...` görünür.
- `ADD_TRUSTED_DISPLAY` izninin shell'de bulunması (Android 13+ için bekleniyor).
- HyperDroid'in kendi davranışı: uygulama kendini başka bir görevde/ekranda yeniden başlatıyorsa yine kaçabilir.
- Güvenilir ekranda ekran klavyesi (IME) gerçek ekranda belirebilir; Nex VR'ın kendi klavyesi yine çalışır.

## Sorun giderme
Günlük etiketleri: `NEXUS-Mirror` ("güvenilir sanal ekran kullanılıyor: display=N" görürsen çalışıyor), `NEXUS-Shell`.

## Dosyalar
`IShellService.aidl`, `ShellService.java`, `ShizukuLink.java`, `AppMirror.java`, `app/build.gradle` (1.9 / 10),
`tools/shizuku.test.js`.
