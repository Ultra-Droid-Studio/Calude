# Stage 62 — Çok akıcı el takibi (ölçümle ayarlandı)

## Yöntem
Gerçek `OE` süzgeç kodunu ve Turbo çizim matematiğini çalıştıran bir simülatör (`tools/handsim.js`) yazıldı:
sentetik el hareketi (duran / yavaş / hızlı salınım / sabit hızlı süpürme) + ölçüm gürültüsü (σ = 0,3–0,6 % ekran),
30/45/24 Hz çıkarım, 60/120 Hz ekran, 45 ms gecikme. Ölçülenler: duran el titremesi (px), gecikme (ms), izleme hatası,
kare-kare pürüzsüzlük ("judder": görüntülenen ivmenin gerçek ivmeden sapması).

## Bulgular
- Eski süzgeç duran elde gürültüyü neredeyse hiç bastırmıyordu: One Euro'nun hız terimi, ölçüm gürültüsünün türevini de "hareket" saydığı için
  kesme frekansı duran elde bile ~6-7 Hz'e şişiyordu (min. kesme 4,8 Hz + beta × gürültü hızı).
- Çıkarım 30 Hz ve çizim 11 ms'lik süzgeçle: her yeni ölçümde küçük bir "basamak" (judder).

## Değişiklikler
- `OE`: isteğe bağlı ölü bölge (`dz`). Hız, gürültü tabanının altındaysa kesme frekansı yükselmez. Varsayılan 0 → eski davranış aynen.
- Anında (hızlı) mod süzgeçleri: min. kesme 1,4 Hz, beta 10, türev kesmesi 2 Hz, ölü bölge 0,8 (imleç ve 21 eklem).
- Turbo çizim: pinsiz süzgeç 11 → 18 ms, süzgeç gecikmesini kapatmak için +9 ms ek ileri tahmin (çimdikteyken 7 ms ve tahmin aynı: tıklama kaymaz).
- `NativeCam`: kare aralığı artık çıkarım süresine göre uyarlanır (16 ms … 33/25 ms; hızlı telefonda ≈60 Hz'e kadar). Android 10+ termal durum
  MODERATE'ta hızlanma kapanır, SEVERE'de 20 Hz'e inilir. Meşgul kapısı (MediaPipe doluyken kare kopyalanmaz) aynen duruyor.

## Simülasyon sonucu (eski → yeni, ortalama)
- Duran el titremesi: 3,3 → 1,4 px (≈ −%56)
- Süpürme judder: 8,7 → 6,6 (≈ −%24), 120 Hz ekranda daha da düşük
- Hızlı harekette gecikme: 31 → 33 ms (≈ +2 ms)
- Yavaş harekette gecikme: ~+7 ms (süzgeç daha sakin)

## Doğrulanmadı
Gürültü seviyesi simülasyonda varsayıldı (σ 0,3-0,6 %); gerçek MediaPipe gürültüsü cihaza ve ışığa göre değişir. Java derlenmedi, cihazda denenmedi.
Titreme hâlâ görünüyorsa `new OE(1.4,10,2,.8)` değerlerinde ilk sayıyı (min. kesme) 1.0'a indir; hareket ağır gelirse 2.0'a çıkar
(`mkSlot`, 3 yer). Test: `node tools/handsmooth.test.js`, simülatör: `node tools/handsim.js`.
