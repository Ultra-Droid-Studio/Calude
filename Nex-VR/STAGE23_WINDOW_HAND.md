# Stage 23 - Pencere çubuğu, cam klavye (TR), el menüsü

Stage 22 üzerine kuruludur (PhoneXR `WindowChrome.kt`, `KeyboardPanel.kt`, `HandMenu.kt` örnek alındı; kod JS'e yeniden yazıldı). **Değişen/eklenen:** `assets/index.html`, `tools/winhand.test.js`. Java'ya dokunulmadı.

## 1. Pencere çubuğu (alt hap)
- Her pencerenin altında yüzen koyu cam kapsül: solda başlık, sağda **klavye, büyüt/eski boyut, küçült, kapat**. Başlığı tutup sürükleyince pencere taşınır (elle çimdik, fare/dokunma ve bakışla).
- Pencerenin çocuk mesh'idir (`Pill`), ışın seçme (`Scene.targets`) ve mevcut düğme/bekleme yolları aynen kullanılır. Pencere boyutu değişince, büyütünce veya küçültülürken (animasyon) kendini ayarlar; pencere kapanınca temizlenir.
- Üstteki eski başlık şeridi (58 px) çubuk açıkken kaldırılır; pencere içeriği o kadar yükselir. **Ayarlar > Görünüm > Pencere çubuğu (altta)** ile kapatınca eski üst şerit geri gelir.
- Klavye düğmesi: Tarayıcıda adres kutusunu açar. Yazı alanı olmayan pencerede "Bu pencerede yazı alanı yok" der (pencere `kbdFn` tanımlarsa onu çağırır).
- Dock, klavye, Win7 masaüstü ve Library çubuk almaz (kendi çerçeveleri var).

## 2. Klavye (cam, Türkçe)
- Arka plan ve tuşlar yarı saydam (sahne görünür), tuş kenarları ince, **Enter mavi** ve dönüş oku (↵) çizer.
- Türkçe Q dizilimi: `ğ ü ş i ı ö ç`, Shift ile `İ`/`I` doğru büyür (`toLocaleUpperCase('tr')`).
- Yeni **?123 / ABC** sembol katmanı: `@ # ₺ % & * ( ) = ~ ^ + - _ / \ | < > { } : ; " ' ? , . [ ] € $` ve diğerleri. Alt satırda `/`, `@`, `.com` kısa yolları. Fiziksel klavye yazımı aynen çalışır.

## 3. El menüsü
- **Avuç yüze dönük + açık el (4 parmak uzatılmış) ~0,6 sn** tutulunca elin üstünde cam menü açılır: Kitaplık, Tarayıcı, Sinema, Ayarlar, Hizala, Küçült. El gidince (~1,5 sn) kapanır.
- Menü 3B bir paneldir (kameraya bakar, elin ekran konumunu 0,8 m'ye izdüşürür); öbür elin işaret parmağıyla bekleme süresi (Ayarlar > El takibi > Tıklama bekleme süresi) veya fare/dokunmayla seçilir. Tutan elin kendi imleci menü açıkken tıklama yapmaz.
- Çimdikleyen ya da başka işte (UI/bakış) olan el menüyü açmaz. VR (XR) oturumunda kapalıdır.
- Avuç yönü formülü PhoneXR `HandGestures.shape` ile aynı (arka kamera, el etiketi tersine çevrilmiş). **Ayarlar > El takibi**: "El menüsü" açma/kapama, "Avuç yönünü ters çevir" (menü el sırtında açılıyorsa).

## Doğrulananlar
- `node tools/winhand.test.js`: gerçek `Pill`/`HMenu` kodu sahte THREE ile çalıştırıldı: düğme sırası/eylemleri, pill konumu (pencerenin altında, aynı düzlemde), yeniden senkron, dispose, dock/klavye/ayar kapalıyken pill yok; sentetik el verisiyle avuç yönü/açık el/yumruk, 0,6 sn tutma, çimdik/meşgul el engeli, zaman aşımı, 6 menü eylemi; klavye düzeni (TR harfler birer kez, Enter, ?123, satır genişlikleri); entegrasyon noktaları. Eski testler (oneeuro, browser, gorilla, glbroom, envsky) geçiyor, `index.html` betikleri sözdizimi temiz.
- Gerçek `rr/ICON/KBD.render/Pill.paint/HMenu.paint` kodu Chromium'da çizdirilip gözle kontrol edildi (harf + sembol klavyesi, odaklı/odaksız/üstünde gezilen pill, normal/seçili menü).

## DOĞRULANMADI / AÇIK EKSİKLER
- **Cihazda ve Android derlemesinde denenmedi.** 3B yerleşim (pill boyutu, menü mesafesi/boyutu), hover/bekleme, WebView katmanının üst şerit kalkınca hizası gerçek tablette bakılmalı.
- **Avuç yönü algısı gerçek kamerada denenmedi**; formül PhoneXR'dan arka kamera için alındı. **Ön kamera eşlemesi tahmindir.** Yanlış el yüzünde açılırsa "Avuç yönünü ters çevir" ayarını kullan.
- Açık el beklemesi (0,6 sn) yanlışlıkla tetiklenebilir; gerekirse Ayarlar'dan menüyü kapat.
- El menüsünde Mikrofon/Kayıt/Passthrough yok (PhoneXR'da var; NEXUS'ta karşılığı yok).
- Klavye düğmesi yalnızca tarayıcıda işe yarar; diğer pencerelere yazı hedefi bağlanmadı.
- İki elle pencere büyütme (çimdik) pill üzerinde çalışmaz, pencere gövdesinde çalışır.
