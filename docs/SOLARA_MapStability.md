# SOLARA — Minimap, tam harita ve GPS kararlılık düzeltmesi

Durum: **uygulandı; görünüm hesabı çevrimdışı test edildi (PASS). Roblox Studio'da / cihazda test EDİLMEDİ →
Studio testinden önce tamamlanmış sayılmaz.**
Derleme: `place/SOLARA_MapStability.rbxlx` (önceki her şey + bu düzeltme).

## Analiz özeti
* **Konum kaynağı doğruydu.** `NavigationController:GetSubject()` araçta aracın şasisini (Model.PrimaryPart, aracın
  kök parçası), yürürken karakterin `HumanoidRootPart`ını verir; minimap, tam harita ve GPS hepsi bunu okur. Binme /
  inmede karakter koltuğa kaynaklı olduğu için iki konum aynı yerdedir. Sürücü aracın ağ sahibidir (gecikme yok);
  sunucunun hareket denetimi oturan oyuncuyu atlar (geri çekme yok). Tek GPS döngüsü var (10 Hz).
* **Asıl hata — `MapCanvas:SetView`:** tuval ölçeği (`UIScale`) sadece %1 değişince güncelleniyor, tuvalin konumu ise
  her seferinde yeni ölçekle hesaplanıyordu. Ölçekler farklıyken harita merkezi oyuncudan
  `(x + 5120) × ölçek farkı` kadar kayıyordu. Araçta yakınlık hızla sürekli değiştiği için kayma birikip eşik aşılınca
  geri zıplıyordu; araçtan inince %1'e kadar kalıcı kayma yürürken de kalıyordu. Yürürken (sabit yakınlık) sorun yoktu.
  Tam haritada iki parmakla küçük adımlı yakınlaştırmada da aynı uyumsuzluk vardı.
* Ek nedenler: minimap düzensiz 30 Hz'de (2-3 karede bir) güncelleniyordu; hıza bağlı yakınlık dikey hızı da (yol
  sarsıntısı) içeriyordu; ok yönü araç dikleşince/devrilince tanımsız vektörden hesaplanıyordu; kapalı tam haritadaki
  rota her yeniden rotada silinip yeniden yaratılıyordu.

## Yapılanlar
| Dosya | Değişiklik |
|---|---|
| `ReplicatedStorage/Shared/MapView.lua` (yeni) | Saf hesaplar: tuval konumu (tam birime yuvarlı), adımlı yakınlık, yatay düzlemde yön (dikleşmede son geçerli yön), açı farkı |
| `FrontEnd/Map/MapCanvas.lua` | `SetView`: `UIScale` ve konum her zaman aynı ölçekle; konum tam birime yuvarlanır (harita bütün olarak kayar); özellikler sadece değişince yazılır. Simge/rota kalınlığı eskisi gibi %1'lik değişimde yeniden boyutlanır (konumu etkilemez). Karo aralığı karşılaştırması string yerine sayı |
| `Controllers/MinimapController.lua` | Her karede hesaplanır, sadece değişimde yazılır (konum 1 px, ok 0.5°). Yakınlık hedefi yatay hızdan; uygulanan yakınlık %2.5'lik adımlarla. Yakınlık aralığı (0.34 / 0.22 / 0.12) ve harita boyutu aynı. Hata uyarısı en fazla 5 sn'de bir |
| `Controllers/NavigationController.lua` | `GetHeading` `MapView.Heading` ile (yumuşatma yok, gecikme yok). Konum kaynağı değişmedi |
| `FrontEnd/Screens/MapScreen.lua` | Harita kapalıyken gelen rota değişikliği harita açılınca bir kez çizilir |

Değişmeyenler: harita tasarımı ve renkleri, minimap boyutu ve yeri, hedef seçme, rota hesabı, waypoint, işaretçiler,
araç kontrolü, trafik, NPC'ler.

## Test
`python3 -I tools/test_map_view.py <lupa> --old <eski MapCanvas.lua>` — gerçek `MapView.lua`yı ve `MapCanvas.lua`dan
alınan gerçek `SetView`'ı çalıştırır, minimap adımını aynı sabitlerle taklit eder; 40 sn'lik sürüş (hızlanma, gürültülü
seyir, fren), 60 FPS, 240 px harita, haritanın üç bölgesinde. Ölçülen: okun oturduğu noktanın (harita merkezi)
gösterdiği dünya konumu ile gerçek konum farkı.

| | En büyük fark | Yakınlık yeniden yerleşimi |
|---|---|---|
| Eski (batı / orta / doğu) | 9 / 21 / 31 px = **35 / 81 / 119 stud** | 4.3 /sn |
| Yeni (üçü de) | **≤ 0.5 px** (piksel yuvarlaması) | 1.5 /sn |

Yön birim testleri (K/D/G/B, dikleşmiş araç, eğik bakış, açı sarması) PASS. Lint önceki durumla aynı (1 hata + 4
uyarı, hepsi dokunulmamış dosyalarda). Bu test Roblox'un çizimini ve fiziğini içermez.

## Studio / cihaz testi (istenen senaryolar)
1. Yürürken ve koşarken minimap: harita akıcı kayıyor mu, ok yollarla örtüşüyor mu?
2. Dururken: ok ve harita tamamen sabit mi?
3. Arabaya bin: yakınlık yumuşakça açılıyor mu, harita/ok sıçrıyor mu?
4. Düşük ve yüksek hız, viraj, durma: ok yolda kalıyor mu, yönü aracın yönüyle aynı mı, harita titriyor mu?
   Haritanın doğu/güney tarafında da dene (eski hata orada en büyüktü).
5. Arabadan in: yakınlık geri geliyor mu, ok karakterin yerinde mi?
6. Tam haritayı aç/kapat (araçta ve yürürken): ok doğru yerde mi, kapatınca minimap normal mi?
7. Hedef seç (yer ve dokunarak waypoint), sonra araçla rotayı takip et: rota, yönlendirme paneli, yeniden rota.
8. Tam haritada iki parmakla yakınlaştır, sonra dokunarak hedef koy: hedef parmağın altına mı düşüyor?
9. Telefon ve tablette FPS: minimap açıkken sürüşte takılma var mı?

## Bilinen sınırlamalar
* Studio'da / cihazda test edilmedi. Piksel yuvarlamanın ve her kare güncellemenin görsel etkisi orada görülmeli.
* Yolcu koltuğunda konum, sürücünün aracından gelen (Roblox'un yumuşattığı) konumdur; değiştirilmedi.
* Uygulanan yakınlık hedefin %2.5 yakınında kalabilir (sadece yakınlık, konum hatası değil).
