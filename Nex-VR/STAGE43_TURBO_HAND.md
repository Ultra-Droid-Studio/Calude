# Stage 43 — Turbo el: gecikme telafisi + taze-kare Worker kuyruğu

## İstek
MediaPipe Worker'dan en hızlı tepki; el hareketi takılıp takılıp gitmesin.

## Kök neden
Stage 39 "anında" modunda görünen el yalnızca yeni ölçüm gelince güncelleniyordu (20-40 Hz). Render 60 Hz+ olduğu için
el ölçümler arasında donuyor, sonra zıplıyordu (basamaklı hareket). Ayrıca ölçüm; yakalama + çıkarım + aktarım kadar
eskiydi, el hep geriden geliyordu. Worker da bir kare yoldayken boşta bekliyordu.

## Değişiklikler
1. **Gecikme telafisi (`Hand.glide`, hızlı dal):** Her eklem için süzgeçli hız (`s.lvx/lvy`, `upd` içinde) tutulur.
   Görünen konum = ölçüm + hız × ölçümün yaşı (`now - s.pst`, yakalama→şimdi). Yani el gerçek konumunda görünür.
   Ölçüm yaşı 90 ms'ye kadar tam, yeni veri yoksa (el kaybı) 180 ms'de sıfıra iner. Ofset ±0.12 ile sınırlı.
2. **Her render karesinde güncelleme:** Konum 11 ms'lik çok kısa bir süzgeçle hedefe yaklaşır; yeni ölçüm gelince zıplama
   olmaz, hissedilir gecikme de eklenmez. İmleç (`dsx/dsy`) aynı yolu izler; sürüklemede `Input.move` her karede çağrılır.
3. **Titreşim koruması:** Hız < 0.04 ekran/sn ise tahmin 0; 0.14'te tam. Duran el titremez. Çimdikte tahmin kapalı
   (tıklama kaymasın), sürüklerken yarım.
4. **Worker: yalnızca en taze kare:** Worker bekleyen eski kareyi atar (`dropped` mesajı), ana thread aynı anda en çok
   2 kare yolda tutar (`inflight`), böylece Worker hiç boşta kalmaz ama gecikme birikmez. Zaman damgası kesin artandır.
   1.5 sn yanıt gelmezse sayaç sıfırlanır (takılma yok).
5. Ayar adı: "Turbo el (anında + gecikme telafisi)" (`hfast`, varsayılan AÇIK).

## Test
- `tools/turbo.test.js`: sabit hızda 30 Hz ölçüm, 38 ms gecikme simülasyonu → ortalama konum hatası 0.070 → 0.006,
  kare başı adım sapması 0.020 → ~0.
- `tools/mediapipe-worker.test.js` (16 kontrol) ve diğer testler geçti; HTML/Worker `node --check` temiz.

## DOĞRULANMADI
Gerçek cihazda denenmedi. Hâlâ MediaPipe çıkarım süresiyle sınırlıdır. Ayarlar:
- Hedefi aşıyorsa: `glide()` içinde `g=...:1` değerini 0.8'e düşür.
- Duran elde titreme olursa: `(sp-.04)/.1` eşiğini `(sp-.07)/.12` yap.

## Derleme (GitHub Actions) — `android-zip-build.yml`
- ZIP deponun köküne **herhangi bir adla** atılır; workflow kendisi bulur, iç içe klasör olsa da proje kökünü bulur.
- Android SDK hazırsa indirmez; eksikse çoklu deneme ile kurar. Gradle 8.7 üç adresten denenir.
- three.js (r128) ve MediaPipe (kitaplık + wasm + `hand_landmarker.task`) çoklu ayna + npm yedeği ile APK içine
  `assets/` altına gömülür. Uygulama önce bu gömülü dosyaları kullanır (`loadBundledMediaPipe`), yoksa eskisi gibi indirir.
- Gradle derlemesi geçici ağ hatalarına karşı 3 kez denenir; APK içeriği doğrulanır.
