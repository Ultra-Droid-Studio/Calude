# SOLARA — Hata düzeltme 3: Tekerlerin kendi kendine sağa sola oynaması (otomobil + motosiklet)

Durum: **düzeltme uygulandı, Roblox Studio'da test edilmedi.**
Derleme: `place/SOLARA_Fix3_WheelWobble.rbxlx` (Aşama 1–4 + Düzeltme 1, 2 + bu düzeltme)
Kullanıcı gözlemi: "Lastikler çok oynuyor; sağ/sol yapmasam bile kendisi oynuyor, motorda dahil."

## Neden (kod + hesap)
Otomobil ve motosiklet aynı teker yapısını kullanır (`VehicleFactory.buildWheel`):

```
Şasi ──CylindricalConstraint (süspansiyon kayıcısı + direksiyon servosu)──► Mafsal ──HingeConstraint (motor)──► Teker
```

1. **Mafsal çok hafifti.** 0.6³ stud, varsayılan yoğunluk → kütle 0.15. Teker bundan 9–80 kat, şasi 120–790 kat
   ağırdı. Roblox kısıt çözücüsü, kısıtlarla bağlı parçalar arasında bu kadar büyük kütle farkı olunca
   kararsızlaşır; mafsalın (ve ona bağlı tekerin) dikey eksen etrafındaki açısı titrer.
2. **Direksiyon servosu aşırı güçlüydü.** `ServoMaxTorque = toplam kütle × 196.2 × 40` (0.17–1.3 milyon). Bu tork
   çok hafif mafsalı her adımda sert itip salınımı büyütüyordu.
3. (Sadece otomobil) `CarPhysics` araç 4°'den fazla yan kaydığında ve oyuncu direksiyonu bırakmışken ön tekerleri
   kendiliğinden karşı tarafa çeviriyordu; bu da "kendi kendine dönüyor" hissine katkı yapıyordu.

Bu değerler oyunun orijinal hâlinde de aynıydı (sorun Aşama 2'den önce de vardı).

## Değişiklikler
| Dosya | Değişiklik |
|---|---|
| `ServerScriptService/Vehicles/VehicleFactory.lua` | Mafsal kütlesi = teker kütlesi × 0.4 (`KNUCKLE_MASS_RATIO`). Direksiyon servo torku = köşe yükü × μ × teker yarıçapı × 4 (`STEER_SERVO_MARGIN`); otomobilde etkin yerçekimi (42), motosiklette Roblox yerçekimi ile. Otomobilde yerçekimi telafisi tekere ve mafsala ayrı ayrı, kendi kütleleriyle uygulanır. |
| `StarterPlayer/StarterPlayerScripts/Vehicles/CarPhysics.lua` | Otomatik karşı direksiyon sadece arka lastikler gerçekten kayarken devreye girer. Telemetri için her tekerin direksiyon hatası ve titreme ölçüsü hesaplanır (sürüşü etkilemez). |
| `StarterPlayer/StarterPlayerScripts/Controllers/VehicleTelemetryController.lua` | F4 panelinde her teker için `dir.hata°` ve `titreme°` sütunları. |

| Araç | Mafsal kütlesi | Teker/mafsal | Şasi/mafsal | Servo torku |
|---|---|---|---|---|
| Pico | 0.15 → 2.27 | 37 → 2.5 | 397 → 26 | 653 566 → 5 041 |
| Vela | 0.15 → 2.85 | 47 → 2.5 | 529 → 28 | 856 525 → 7 305 |
| Rayo GT | 0.15 → 3.56 | 59 → 2.5 | 496 → 21 | 872 937 → 9 441 |
| Terra | 0.15 → 4.85 | 80 → 2.5 | 694 → 22 | 1 209 340 → 11 518 |
| Mesa | 0.15 → 4.85 | 80 → 2.5 | 728 → 23 | 1 248 580 → 11 767 |
| Porter | 0.15 → 3.76 | 62 → 2.5 | 761 → 31 | 1 202 656 → 9 866 |
| Brisa | 0.15 → 4.85 | 80 → 2.5 | 794 → 25 | 1 327 060 → 12 153 |
| Veloz (motosiklet) | 0.15 → 1.24 | 20 → 2.5 | 172 → 21 | 254 961 → 27 200 |
| Tango (motosiklet) | 0.15 → 1.14 | 19 → 2.5 | 159 → 21 | 235 460 → 22 588 |
| Dune (motosiklet) | 0.15 → 1.72 | 28 → 2.5 | 198 → 17 | 305 314 → 31 097 |
| Zip (scooter) | 0.15 → 0.55 | 9 → 2.5 | 119 → 33 | 165 206 → 10 416 |
| Ruta (motosiklet) | 0.15 → 1.33 | 22 → 2.5 | 165 → 19 | 250 580 → 24 379 |

## Korunanlar
* Hızlanma, fren, azami hız: motor ve fren kuvvetleri toplam kütleyle ölçeklendiği için aynı kalır.
* Yay sertliği, sönüm, sürüş yüksekliği (yaylı kütleden hesaplanır; değişmedi).
* Lastik tutuşu, direksiyon açıları ve dönüş hızı (servo `AngularSpeed` = 8 rad/sn aynı), motosiklet yatışı,
  araç modelleri/görünümü, binme/inme, mobil kontroller, ağ sahipliği.
* Yeni parça, script veya sürekli döngü eklenmedi.

## Studio test senaryoları
1. Her otomobil tipinden birine bin, düz yolda 30–60 km/h giderken direksiyona dokunma: ön tekerler sabit
   kalmalı. F4 panelinde `titreme°` 0.5°'nin altında olmalı (önce/sonra karşılaştırma için Fix2 dosyasıyla da bak).
2. Duruşta direksiyonu tam sola/sağa çevir: tekerler eskisi gibi hızlı ve tam dönmeli (servo yetersizse yavaş
   dönerler → bildir).
3. Virajda ve test parkurunda (slalom, şerit değiştirme): direksiyon tepkisi eskisi gibi olmalı.
4. El freniyle kaydır, direksiyonu bırak: karşı direksiyon sadece arka kayarken gelmeli.
5. Her motosiklet tipinde (özellikle Zip scooter) düz giderken ön teker sabit olmalı; virajda yatış eskisi gibi.
6. Hızlanma/fren: test parkurundaki 0–100 ve fren ölçümleri önceki değerlere yakın olmalı.
7. Mobil (Device Emulator + gerçek cihaz): pad ve buton direksiyonu ile 1. ve 5. adımlar.

## Bilinen sorunlar / sonraki adımlar
* Motosikletler F4 telemetri panelinde görünmez; motosiklette kontrol gözle yapılır.
* Daha önce raporlanan gövde yatışı (viraj denge çubuğu yok) ve kaldırım ayrıştırma hatası (yol kenarında 0.8 stud
  basamak) bu düzeltmenin kapsamı dışında; titreme testinden sonra gerekirse ele alınacak.
