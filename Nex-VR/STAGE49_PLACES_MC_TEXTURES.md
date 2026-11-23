# Stage 49 — Mekânlar (Sinema değil) + gerçek Minecraft dokuları

## Mekânlar
* "Roblox evi (3D)" ve "Minecraft (3D)" artık **Sinema odası değil**. Ayarlar > Duvar kağıdı bölümünden dokununca `Places` modülü açılır:
  arka plan 3D dünyaya dönüşür, **normal pencereler (tarayıcı, ayarlar, uygulamalar, dock) olduğu gibi açılır** — sinema perdesi/video yok.
* Tekrar dokunmak, bir duvar kağıdı seçmek ya da Sinema/Oyun/Gezegen moduna girmek mekândan çıkarır (gökyüzü, zemin, sis, kamera yüksekliği geri yüklenir).
* Dünya yüklenirken (Roblox .glb) normal ortam görünür, hazır olunca mekân açılır.
* Sinema'daki oda listesinden 1 (Roblox) ve 2 (Minecraft) kaldırıldı: "Oda" düğmesi bunları atlar, eski kayıtlı oda değeri salona döner.

## Minecraft dokuları
* Gönderilen terrain atlas görseli (`16x16` kare ızgara) `MCTex.AT` içine data-URI olarak gömüldü (ek dosya/indirme yok).
* Çim üstü (0,0, yeşil tonlu), toprak (2,0), çim yanı (3,0), gövde kabuğu (4,1), gövde kesiti (5,1), yaprak (5,3, yeşil tonlu), domuz = pembe yün (2,8),
  zombi = yeşil yün (2,9) + camgöbeği yün (1,13), köylü = kum/kahverengi yün + kabuk kareleri.
* Atlas yüklenene kadar eski prosedürel renkler görünür; yüklenince kareler atlastan çizilir (`NearestFilter`, piksel keskinliği korunur).
