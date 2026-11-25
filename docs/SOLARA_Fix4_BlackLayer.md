# SOLARA — Hata düzeltme 4: Oyun içinde ekranı karartan siyah katman

Durum: **düzeltme uygulandı, Roblox Studio'da test edilmedi.**
Derleme: `place/SOLARA_Fix4_BlackLayer.rbxlx` (Aşama 1–4 + Düzeltme 1–3 + bu düzeltme)
Kullanıcı gözlemi: Ana menü normal; OYNA'dan sonra oyun içinde ekranı karartan siyah bir katman.

## Ayrıştırılan ihtimaller
| İhtimal | Sonuç |
|---|---|
| 1. Siyah UI Frame | **Kaynak bu.** Mini haritanın tuvali (`MapCanvas` → `MapRoot`) 10240×10240, rengi rgb(22, 25, 32), saydamlığı 0.05 (neredeyse opak siyah). Ekrana taşmasını yalnızca yuvarlak kırpan `CanvasGroup` engelliyordu. Mini harita sadece oyun içinde (FrontEnd durumu "Playing") görünür → menüde yok, oyunda var. CanvasGroup'un düşük bellekte/bazı cihazlarda düzgün kırpamadığı bildiriliyor; o zaman koyu tuval ekranı kaplar. Aşama 5'teki "minimap taşması" şikâyetiyle aynı kök. |
| 2. Kapanmayan yükleme ekranı | Ayrı yükleme ekranı yok. Menü katmanları (`Backdrop`, `Footer`) `hideMenu(0)` ile anında gizleniyor. |
| 3. Takılan fade | Geçiş perdesi (`Shell.Veil`, tam siyah) normalde 0.5 sn'de kalkıyor; ancak perde siyahken `enterWorld` içindeki bir adım hata verirse perde hiç kalkmıyordu (tam siyah ekran). Ek güvenlik olarak düzeltildi. |
| 4. Lighting / post-processing | Menü renk efekti (`SolaraMenuGrade`) oyunda kapatılıyor ve karartmıyor; sunucu efektleri (Bloom, ColorCorrection, Atmosphere) menüde de aynı. Değiştirilmedi. |
| 5. Kamera geçişi | Kamera karakterin arkasına yerleşiyor; perde arkasında oluyor. Değiştirilmedi. |

## Değişiklikler
| Dosya | Değişiklik |
|---|---|
| `Controllers/MinimapController.lua` | CanvasGroup artık `ClipsDescendants = true` olan sıradan bir `MinimapClip` Frame'in içinde. CanvasGroup kırpamasa bile taşma mini haritanın kare alanında kalır. Zemin rengi kaba taşındı. |
| `FrontEnd/Map/MapCanvas.lua` | Mini haritada tuvalin arka planı saydam (`MapCanvas.LandColor` kaba verilir). Tam harita aynı. |
| `Controllers/FrontEndController.lua` | `enterWorld`: perde siyahken yapılan adımlar `pcall` içinde; hata olursa günlüğe yazılır ve perde her durumda kalkar. |

Korunanlar: ana menü görünümü, Lighting ayarları, kamera, mini harita boyutu/konumu/yuvarlak görünümü, tam harita ekranı.

## Studio test senaryoları
1. **Play**: OYNA → oyun normal parlaklıkta açılmalı, ekranın üstünde koyu katman olmamalı; mini harita kendi dairesinde.
2. **Respawn**: karakteri öldür (Reset) → yeniden doğunca katman olmamalı.
3. **Menüye dönüş**: P / ☰ ile menüyü aç, Garaj/Ayarlar/Harita'ya gir, kapat → oyun görüntüsü normal; tekrar aç-kapa.
4. **Araç**: bin/in, mini harita ve HUD doğru sırada (mini harita, hız göstergesi, mobil butonlar) görünmeli.
5. **Mobil/tablet**: Device Emulator ve gerçek cihazda 1–4. Özellikle tablette, düşük grafik kalitesinde de kontrol et.
6. Çıktı penceresinde "Oyuna geçişte hata" satırı çıkarsa metnini gönder (perde artık kalksa da bir adım hata vermiş demektir).

## Bilinen sorunlar
* CanvasGroup'un neden kırpamadığı cihaz/bellek koşuluna bağlı; Studio'da yeniden üretilmedi. Güvenlik kırpıcısı
  sayesinde en kötü durumda mini haritanın köşelerinde kare taşma görülebilir (Aşama 5'te ele alınacak).
