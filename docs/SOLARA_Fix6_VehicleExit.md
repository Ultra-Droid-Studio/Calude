# Hata düzeltme 6 — Araçtan inince kontroller araçta kalıyordu

Durum: **kod hazır; çevrimdışı test PASS; oyunda test EDİLMEDİ.**

## Kullanıcının bildirdiği
Araçtan inince araç kontrolleri kalıyor ve karakter kontrol edilemiyor. Bazen hızlı giderken inince, bazen başka bir yolla inince oluyor. Düzelmesi için oyundan çıkıp yeniden girmek gerekiyordu.

## Neden
1. **İniş yarıda kalıyordu.** `VehicleController.leave()` adımları sırayla çalıştırıyordu:
   * araç fiziğini bırak
   * bağlantıları temizle
   * kamera
   * araç tuşlarını kapat
   * mobil düzen
   * karakter kontrollerini aç
   * istemleri aç

   Herhangi biri hata verince geri kalanı hiç çalışmıyordu. Hata verebilen yerler:
   * aracın parçaları o an yok olmuşsa araç fiziği
   * kamera
   * mobil düzen hesabı

   Sonuç: araç tuşları (W/A/S/D) bağlı kalıyordu, karakter kontrolleri kapalıydı, mobilde Roblox joystick'i gizli kalıyordu. Üstelik "araçta" durumu bazen hiç temizlenmiyordu, yeniden denenmiyordu.
2. **Karakter "oturuyor" durumunda kalabiliyordu.** Sunucu koltuk kaynağını silip karakteri aracın yanına taşıyor. Ama karakterin durumu oyuncunun cihazında; "Oturuyor" durumu orada sürerse karakter yürümüyor.
3. Hızla inişte karakter aracın hızıyla yolda savruluyordu.
4. (Araç çalma) Çalma bitince karakter kontrolleri, oyuncu araca oturmuş olsa bile açılıyordu. Sürüşte zıplama tuşu koltuktan atabilirdi.

## Düzeltme
* `leave()`:
  * "araçta" durumu en başta temizlenir.
  * Her adım ayrı korunur (`safe`). Hata verense günlüğe yazılır, kalanlar yine çalışır.
  * Yaya kontrollerini geri veren kısım (`restoreOnFoot`) her zaman çalışır:
    * araç tuşları kapanır
    * mobil düzen "OnFoot" olur
    * karakter kontrolleri açılır
    * istemler açılır
    * analog değerler sıfırlanır
  * Karakter koltuksuz ama "oturuyor" durumundaysa ayağa kalkar (`GettingUp`, `Sit = false`).
* Hızla inişte karakterin yatay hızı 18 stud/sn ile sınırlanır; yön korunur. Bu, sunucu karakteri taşıdıktan sonra bir kez daha uygulanır.
* **Güvenlik ağı** (0.5 sn'de bir, çok ucuz):

  | Durum | Ne yapılır |
  |---|---|
  | Araç koltuğunda değil ama "araçta" durumu açık | iner |
  | Araç tuşları ya da mobil araç düzeni yayayken kalmış | yaya kontrollerine döner |
  | Araç koltuğunda ama binme olayı kaçmış | biner |

  Menü açıkken, oyuncu bankta otururken ve karakter ölüyken hiçbir şey yapmaz.
* Mobil düzen: düzen hesabı hata verse bile Roblox joystick'i doğru açılıp kapanır.
* Araç çalma: karakter kontrolleri sadece oyuncu hâlâ yayaysa geri açılır.

## Test
`tools/test_vehicle_exit.py` gerçek `VehicleController`'ı Roblox taklitleriyle çalıştırıyor. 6 kontrolün hepsi PASS:
1. Normal binme ve inme.
2. İnerken araç parçaları, kamera ve mobil düzen hata verse bile yaya kontrolleri tam geri geliyor.
3. 60 stud/sn hızla inişte karakter 18 stud/sn'de kalıyor.
4. "Oturuyor" durumunda kalan karakter ayağa kalkıyor.
5. Güvenlik ağı: kaçan iniş, takılı tuşlar ve kaçan biniş düzeliyor.
6. Güvenlik ağı menüye, banka ve ölü karaktere dokunmuyor.

Aynı test **eski kodla** 2. senaryoda hatayla duruyor: hatanın kendisini gösteriyor.
Diğer testler yeniden PASS: sürüş düzeni (184 yerleşim), araç çalma, arabalar, çarpışma, yaya sohbeti.

Test için `tools/luau2lua.py` düzeltildi: `x += 1 -- açıklama` satırında açıklama parantezin dışına alınıyor. Sadece çevrimdışı dönüştürücü; oyun kodu değil.
