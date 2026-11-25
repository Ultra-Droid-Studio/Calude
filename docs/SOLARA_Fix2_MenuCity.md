# SOLARA — Hata düzeltme 2: Ana menü arka planında uzak şehrin hiç görünmemesi

Durum: **düzeltme uygulandı, Roblox Studio'da test edilmedi.**
Derleme: `place/SOLARA_Fix2_MenuCity.rbxlx` (Aşama 1–4 + Düzeltme 1 + bu düzeltme)
Kullanıcı gözlemi: "Uzak kısım hiç yok" (yakın kuleler görünüyor, arkadaki şehir boş/yarım).

## Neden (kanıt)
* Şehir çalışma anında sunucuda üretilir; `Workspace.StreamingEnabled = true`, diğer akış ayarları Roblox
  varsayılanında (yükleme yarıçapı `StreamingTargetRadius` = 1024 stud).
* Menüdeyken oyuncunun karakteri yoktur; içerik tek bir akış odağı (`FrontEndConfig.StreamFocus` = -270, 20, -270)
  çevresinde 1024 stud içinde yüklenir.
* İstemcideki `RequestStreamAroundAsync` sadece en küçük yarıçapı (`StreamingMinRadius`, 64 stud) yükler;
  menü şehrini büyütmez.
* Menü kamerası şehir merkezine ~760 stud uzaktan bakar. Harita verisi (1333 bina) ve kamera görüş alanıyla
  hesap: kameranın 3500 stud içinde gördüğü 498 binanın sadece 149'u (%30) yükleme alanında. Geri kalanı
  hiç gelmiyor → "uzak kısım yok". (Kod şehri silmiyor/gizlemiyor; istemci kodunda dünya parçalarına dokunan
  yer yok, tüm dünya parçaları Anchored.)

## Değişiklik
| Dosya | Değişiklik |
|---|---|
| `ReplicatedStorage/Modules/FrontEndConfig.lua` | `MenuExtraStreamFoci`: iki ek odak noktası (1900, 20, 0) ve (400, 20, 1200). |
| `ServerScriptService/Services/CharacterService.lua` | Menüdeki oyuncuya bu noktalar `Player:AddReplicationFocus` ile eklenir; doğarken (`LoadCharacter` öncesi ve `markInGame`) `RemoveReplicationFocus` ile kaldırılır. Doğma başarısız olursa menü akışı geri kurulur. API yoksa/hata verirse uyarı yazılır ve eski davranışla (tek odak) devam edilir. |

Ana odak, menü kamerası, şehir modelleri, harita düzeni ve oyun içi akış ayarları **değişmedi**.

## Beklenen etki (hesap, Studio ölçümü değil)
| | Görünen binalardan yüklenen (3500 stud) | Ekran alanı ağırlıklı | Menüde yüklenen toplam bina |
|---|---|---|---|
| Önce | %30 | %89 | 302 |
| Sonra | %76 | %97 | 532 |

En uzak, ekranda çok küçük kalan binaların bir kısmı hâlâ yüklenmez (atmosfer pusu onları zaten soldurur).

## Mobil/tablet bellek
* Menüde yüklenen bina sayısı ~%76 artar (302 → 532). Bu içerik, oyuna girdikten sonra Roblox varsayılanı gereği
  ancak bellek baskısında bırakılır; oyuncu şehirde gezdikçe zaten yükleyeceği içeriktir.
* Sürekli çalışan yeni döngü yok; ek odaklar menüden çıkınca kalkar.
* Tablette ölçülmedi. Ölçüm önerisi aşağıda.

## Studio test senaryoları
1. Play → ana menüde 30 sn bekle: kulelerin arkasındaki şehir (sağ ve uzak kısım) görünmeli; kamera
   200°→250° arası kayarken boş alan kalmamalı. Önce/sonra ekran görüntüsü al (Fix1 dosyasıyla karşılaştır).
2. Çıktı penceresinde "Ek akış odağı eklenemedi" uyarısı **olmamalı**. Varsa API bu Studio sürümünde yok
   demektir; menü eski hâliyle çalışır — bana bildir.
3. OYNA → doğma hızı ve doğma noktası çevresi eskisi gibi olmalı (ek odaklar kalkar).
4. Doğduktan sonra yürü/araç sür: akış karakteri takip etmeli.
5. Tablet/telefon: menüde 1. adım; F9 (veya sohbette `/console`) → Memory: menüde ve oyuna girdikten
   1 dk sonra toplam belleği not et.
6. Studio "Local Server + 2 oyuncu": biri menüde, biri oyundayken ikisinde de şehir doğru akmalı.

## Bilinen sorunlar
* Kalan uzak binalar (görünenlerin ~%24'ü, çoğu 1500+ stud ötede) yüklenmez.
* `AddReplicationFocus` resmi dokümanda olan, nispeten yeni bir API; Studio'da çalıştığı doğrulanmadı
  (hata verirse eski davranışa düşer).
* Oyun içi akış ayarları (hızlı araçta önünün geç yüklenmesi, bellek baskısında bırakma) bu düzeltmenin
  kapsamı dışında; şikâyet menüyle sınırlı olduğu için dokunulmadı.
