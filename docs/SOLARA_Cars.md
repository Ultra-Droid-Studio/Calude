# SOLARA — Yeni arabalar (Patrol, Vento): orijinal görünüm, az üçgen

Durum: **dosyalar ve kod hazır; oyunda test EDİLMEDİ** (Studio'da içe aktarılınca görünür).

| Oyundaki ad | Kaynak | Üçgen (kaynak → hazır) | Oyunda |
|---|---|---|---|
| **Vento** | "(FREE) Porsche 911 Carrera 4S" — Karol Miklas, CC BY-SA 4.0 | 653 bin → ~53 bin | kompakt, sedan ve spor araçlar (oyuncunun sürdükleri de, trafik de); boya rengi aracın rengini alır |
| **Patrol** | "Police car" — Mateusz Woliński, CC BY 4.0 | 256 bin → ~33 bin | trafikte sedanların bir kısmı (merkezde/havalimanında daha sık); siyah-beyaz polis boyası sabit |

Eski Quaternius araba paketi kaldırıldı. SUV, kamyonet, minibüs ve iş aracının modeli yok: onlar eski kutu
görünümüyle kalır (model gelince eklenir).

## Ne yapıldı (`tools/car_prepare.py`)
* Dokular, malzemeler ve renkler **orijinal** (dokular aynen dosyada). Üçgenler MeshLab'ın dokuyu koruyan
  "quadric edge collapse" yöntemiyle azaltıldı; pürüzsüz görünüm için yüzey yönleri (normaller) orijinal modelden
  aktarıldı. Karşılaştırma: `assets/cars/compare_Patrol.png`, `assets/cars/compare_Vento.png` (sol kaynak, sağ hazır
  dosya; aynı ışık, aynı dokular).
* Görünmeyen ağır parçalar çıkarıldı: Vento'nun boyanın üstündeki saydam vernik kabuğu (177 bin üçgen) ve gölge düzlemi.
* Marka işaretleri çıkarıldı: Vento'nun arması, "PORSCHE / 911" yazıları ve plakaları; Patrol'ün ızgarasındaki amblem.
* Tekerlekler ayrı parça (oyunda döner); Vento'nun dingil başına tek olan tekerleği sağ/sol ayrıldı.
* Her parça Roblox'un parça başına 20 000 üçgen sınırının altında (gerekirse bölündü).

## Studio'da kurulum (internet kafede)
1. **File → Import 3D →** `assets/cars/Vento.glb`. Gelen pencerede ayarları değiştirme (Merge Meshes kapalı kalsın).
2. Explorer'da **ReplicatedStorage** içinde **`VehicleModels`** adlı bir **Folder** yoksa oluştur.
3. İçe aktarılan modeli bu klasöre sürükle; adı tam olarak **`Vento`** olsun.
4. Aynısını `assets/cars/Patrol.glb` için yap; adı **`Patrol`**.
5. Oyunu Studio'da başlat (Play): spor/sedan/kompakt bir araç doğur, bin, sür; tekerlekler dönüyor mu, araç yerde mi?
   Trafikte polis arabaları görünüyor mu? Çıktıda `[CarModelKit]` uyarısı var mı?
6. **File → Save to File** ile yeri `.rbxlx` olarak kaydet ve bana gönder (Termux'tan sonraki yayınlarda modeller
   silinmesin diye; bundan sonra o dosyadan derlerim).

## Bilinen sınırlamalar
* Studio'da test edilmedi. Roblox'un içe aktarıcısının saydam camları nasıl göstereceği orada görülecek.
* Bu modellerde farlar/stop lambaları gece ayrıca yanmaz (dokuda çizili); araç ışık sistemi bu modellerde boşta.
* Vento kaynağının biçimi Porsche 911'e benzer (marka işaretleri çıkarıldı, adı Vento); bunun riski kullanıcıya
  anlatıldı.
* Performans: Vento ~53 bin üçgen. Bilgisayarda sorun beklenmez; telefonda trafikte çok sayıda Vento FPS'i
  düşürebilir — gerekirse trafik için daha hafif bir sürümü ayrıca üretilir.
* Lisans: oyunun Roblox açıklamasına `docs/CREDITS.md`'deki atıf satırları eklenmeli; Vento'nun değiştirilmiş modeli
  CC BY-SA 4.0'dır.
