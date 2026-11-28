# SOLARA — Yayalarla yapay zekâlı sohbet

Durum: **kod hazır; çevrimdışı testler PASS; lint önceki durumda. Oyunda test EDİLMEDİ.**
Roblox'un kendi dil modeli kullanılıyor (`TextGenerator`): ücretsiz (beta), çıktısı Roblox tarafından denetleniyor.
Dış servis, API anahtarı ya da para yok.

## Oyuncu ne görür
* Kaldırımda yürüyen ya da duran bir yayanın yanına gelince (7 stud) **"Konuş" [E]** istemi (kolda X, mobilde dokun).
  Karşıya geçen, kapıdan giren/çıkan, kazadan kalkan yayalarda istem çıkmaz. Araçtayken ve araç çalarken de çıkmaz.
* E →
  1. Yaya durur ve yavaşça sana döner (duruş animasyonu: nefes, ağırlık aktarma, etrafa bakma).
  2. Altta küçük bir **sohbet paneli** açılır: yayanın adı ve mesleği, son 6 mesaj, yazı kutusu ("Bir şey yaz…"),
     **Gönder** düğmesi (Enter da gönderir), kapatma (✕).
  3. Yaya **kendini tanıtarak selam verir**. Başının üstünde konuşma balonu çıkar: beklerken "...", sonra cevap
     (9 sn görünür).
  4. Yazdığın mesaj Roblox filtresinden geçer; panelde filtrelenmiş hâli "Sen: …" olarak görünür. Yaya cevap verir ve
     sohbeti hatırlar (aynı sohbet içinde).
* Sohbet şu durumlarda biter; yaya en yakın kaldırıma geri katılır ve eski yönünde yürümeye devam eder (yüzü sana
  dönükten yürüme yönüne yumuşakça döner):
  * paneli kapatınca,
  * 16 studdan uzaklaşınca,
  * araca binince,
  * 60 sn hiçbir şey yazmayınca.
* Mesaj en fazla 140 karakter. Çok hızlı yazarsan (3 mesaj, sonra 4 sn'de bir) yaya "Bir saniye, nefes alayım!" der.
* Yazılı sohbete izni olmayan hesaplarda (Roblox hesap ayarları / yaş) yaya sadece kısa bir selam verir; yazı kutusu
  kapalıdır ve "Hesap ayarların yazılı sohbete izin vermiyor." yazar.
* Model cevap veremezse (sınır, kesinti, özellik kapalı) yaya hazır kısa bir cümle söyler ("Kusura bakma, şu an aklım
  başka yerde."); oyun bozulmaz.

## Yayanın kişiliği (sunucuda)
* Her yayanın bir tohumu (seed) var; sunucu bu tohumdan **aynı kişiyi** üretir: ad soyad (gerçekçi kadın modellerinde
  kadın, erkek modellerinde erkek adı; Türkçe ve İspanyolca karışık), yaş (22–66), meslek, bir iki huy, o anki ruh
  hâli.
* Bağlam: bulunduğu semt (harita verisi), vakit (sabah / öğle / akşam / gece, oyun saatinden), yakındaki en fazla 4
  işletme (260 stud içinde; adı ve türü).
* Kurallar (modele verilen talimat):
  * karşısındakinin dilinde cevap ver (varsayılan Türkçe),
  * en fazla iki kısa cümle,
  * yapay zekâ ya da oyun karakteri olduğunu söyleme,
  * gerçek marka / kişi, siyaset, din, şiddet ve yetişkin konular yok (nazikçe konu değiştir),
  * kişisel bilgi sorma / isteme,
  * para, görev, eşya vaat etme,
  * kaba davranılırsa kibarca uzaklaş.
* İstemci kişilik metni gönderemez: sadece tohum, cinsiyet (F / M / belirsiz), konum, mesaj ve sohbet belirteci.

## Güvenlik ve sınırlar
* Oyuncunun mesajı **modele gitmeden önce** `TextService` ile filtrelenir. Modelin cevabı da oyuncuya gösterilmeden
  önce filtrelenir. Roblox ayrıca modelin çıktısını kendisi denetler.
* `TextChatService:CanUserChatAsync`: izni olmayan hesapta serbest metin yok (sonuç oyuncu başına önbellekte).
* Oyuncu başına sıklık sınırı (3 hak, 4 sn'de bir dolar). Roblox'un sınırı başta dakikada 100 istek (bütün oyun);
  oyuncu sayısı arttıkça artar.
* Sunucu kontrolleri:
  * istek tablo mu,
  * tohum ve konum sayı mı (NaN / aşırı değer yok),
  * oyuncu yayaya yakın mı (26 stud),
  * mesaj geçerli UTF-8 mi; uzunsa kırpılır.
* Sunucu oyuncu başına en fazla 6 sohbet üreticisi tutar; en eski kullanılan silinir. 5 dk kullanılmayan üretici ve
  oyundan çıkan oyuncunun üreticileri silinir.
* Hiçbir mesaj saklanmaz. Sohbet hafızası, Roblox'un verdiği belirteçte (ContextToken) ve sadece o sohbet boyunca
  tutulur.

## Bilinmeyenler (oyunda görülecek)
* `TextGenerator`'ın bu oyunda ve hesabında açık olup olmadığı. Kapalıysa yayalar sadece hazır cümleleri söyler.
  Bunu sunucu günlüğündeki "TextGenerator yanıt vermedi" uyarısı gösterir.
* Türkçe cevapların kalitesi ve hızı (cevap birkaç saniye sürebilir; o sırada balonda "..." görünür).
* Yayalar her oyuncunun kendi cihazında. Konuşma balonunu sadece konuşan oyuncu görür.

## Kod
| Dosya | Ne yapar |
|---|---|
| `Modules/NPCChatConfig.lua` | ayarlar: mesafeler, süreler, sınırlar, model ayarları, ad / meslek / huy listeleri, hazır cümleler |
| `Services/NPCChatService.lua` | kişilik, sistem talimatı, filtreler, izin, sınırlar, TextGenerator, `NPCRemotes.Talk` |
| `Shared/RemoteRegistry.lua` | `NPCRemotes.Talk` (RemoteFunction) |
| `Ambient/NPCChat.lua` | sohbet paneli ve konuşma balonu (kodla kurulur) |
| `Ambient/PedRenderer.lua` | `Gender` (modelden F / M), `TalkPrompt` ("Konuş" istemi; havuza dönerken kapanır) |
| `Controllers/AmbientController.lua` | istemi açma / kapama, sohbeti başlatma (yaya simülasyondan çıkar, durur, döner), bitirme ve kaldırıma geri katılma |

## Testler
* `tools/test_npcchat.py` — 17 kontrolün hepsi PASS. Gerçek NPCChatService ve NPCChat paneli birlikte, Roblox
  taklitleriyle (TextGenerator, filtre, sohbet izni, küçük görev zamanlayıcı) ve gerçek harita semtleri / yerleriyle
  çalışıyor.
  * Sunucu kontrolleri:
    * kişilik tohuma bağlı ve çeşitli,
    * talimatta kişi, semt, yakındaki yer, vakit ve kurallar var,
    * selam ve mesaj akışı,
    * mesaj modele filtrelenmiş gidiyor,
    * belirteç taşınıyor,
    * uzun cevap kırpılıyor,
    * hatalı istekler modeli çağırmıyor,
    * sıklık sınırı çalışıyor,
    * izinsiz hesapta serbest metin yok,
    * model / filtre hatasında hazır cümle geliyor,
    * üretici sınırı ve temizliği çalışıyor.
  * Panel kontrolleri:
    * açılış, ad ve meslek,
    * gönderme,
    * beklerken kilit,
    * uzunluk sınırı ve Enter,
    * kapatma ve geç gelen cevap,
    * izinsiz hesap,
    * bağlantı hatası,
    * balonun kaybolması.
  * Yaya kontrolleri:
    * cinsiyet modelden okunuyor,
    * istem bir kez kuruluyor, kapalı başlıyor ve havuzda kapanıyor.
* Sohbet sırasında yayanın durması / dönmesi / kaldırıma geri katılması (AmbientController) çevrimdışı test edilmedi.
  Bunun için gereken kaldırıma geri katılma (`PedSim:Rejoin`) `test_crash` ile test ediliyor.
* Diğer testler (araç çalma, yayalar, çarpışma) yeniden PASS.
