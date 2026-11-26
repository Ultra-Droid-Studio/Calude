# SOLARA — Mobil joystick ve kamera ayrımı

Durum: **uygulandı; telefon/tablette test EDİLMEDİ → cihaz testinden önce tamamlanmış sayılmaz.**
Derleme: `place/SOLARA_MobileCamera.rbxlx` (önceki her şey + bu düzeltme).

## Neden
Oyun Roblox kamerası yerine kendi kamerasını kullanır (`CameraController`, CameraType = Scriptable). Kamera,
bir GUI'nin işlemediği (`processed = false`) her dokunuşu kamera dokunuşu sayıyordu. Roblox'un dinamik hareket
joystick'i dokunuşu işlenmiş olarak işaretlemez; Roblox kendi kamerasında (PlayerModule → CameraInput) joystick
alanında başlayan parmağı ayrıca hariç tutar. Bizim kamerada bu kontrol yoktu. Sonuçları:
1. Joystick parmağı kamerayı da çeviriyordu.
2. Yürürken ikinci parmakla kamera sürüklenemiyordu (iki "kamera parmağı" yakınlaştırma sanılıyordu).
3. Joystick + kamera parmağı Roblox'un iki parmak yakınlaştırma olayını tetikleyip uzaklığı değiştirebiliyordu.

## Değişiklik (tek dosya: `StarterPlayer/StarterPlayerScripts/Controllers/CameraController.lua`)
* Dokunuş `PlayerGui.TouchGui.TouchControlFrame` içindeki `DynamicThumbstickFrame` ya da `ThumbstickFrame`
  alanında başlıyorsa kamera dokunuşu sayılmaz (Roblox'un kendi kontrolüyle aynı). Sadece Roblox dokunmatik
  kontrolleri açık ve joystick görünürken uygulanır.
* İki parmak yakınlaştırma sadece iki parmak da kamera alanındayken çalışır.

Değişmeyenler: Roblox joystick görünümü ve hareketi, PlayerModule / TouchControls, araç kontrolleri (direksiyon pedi
ve butonlar Roblox butonu olduğu için zaten kameraya karışmıyordu), araçta kameranın 1.2 sn bakış girişi yoksa
aracın arkasına dönmesi (bilinçli sürüş kamerası davranışı; istenirse kapatılabilir), masaüstü fare ve gamepad.

## Cihazda test (senin yapman gereken)
1. Joystick ileri / geri / sağ / sol: kamera sabit kalmalı.
2. Ekranın sağ / boş tarafında sürükle: sağa-sola yatay, yukarı-aşağı dikey dönmeli.
3. Yürürken (joystick basılıyken) ikinci parmakla kamerayı sürükle: dönmeli, yakınlaşma değişmemeli.
4. İki parmakla kamera alanında sıkıştır/aç: yakınlaştırma çalışmalı.
5. Araçta: direksiyon pedi / butonlar kamerayı çevirmemeli; boş alanda sürükleme kamerayı çevirmeli.
6. Araçtan in: Roblox joystick'i geri gelmeli, 1–4 tekrar.
7. Telefon ve tablet; Roblox ayarlarında klasik joystick (Thumbstick) seçiliyken de 1.

## Bilinen sınırlamalar
* Cihazda denenmedi.
* Joystick alanı Roblox'un `TouchGui` yapısındaki çerçeve adlarına dayanır; Roblox bu adları değiştirirse kontrol
  pasif kalır (eski davranış döner, oyun bozulmaz).
