package com.ultradroid.app;

import android.view.Surface;

// Shizuku UserService (shell yetkili süreç) arayüzü. Birden çok sanal ekranı (pencere) aynı anda yönetir.
// Not: AIDL'de bir metoda sabit numara verildiyse TÜM metodlara verilmelidir.
interface IVdService {
    // Shizuku'nun zorunlu kıldığı destroy (transaction kodu sabit)
    void destroy() = 16777114;

    // Verilen Surface'e çizen "trusted" YENİ bir sanal ekran açar. Başarıda displayId, hatada -1.
    int open(in Surface surface, int width, int height, int dpi) = 1;

    // Surface/boyut değişince o sanal ekranı günceller.
    void resize(int displayId, in Surface surface, int width, int height, int dpi) = 2;

    // "paket/activity" bileşenini o sanal ekranda başlatır. Boş string = başarılı, aksi halde hata metni.
    String launch(int displayId, String component) = 3;

    // O sanal ekrana dokunma enjekte eder (çoklu dokunma). xs/ys 0..1 aralığında (görünümün oranı) gelir;
    // rot: -1 = otomatik (ekran dönüşüne göre), 0..3 = girdiyi 0/90/180/270 derece döndür.
    void injectTouch(int displayId, int action, int actionIndex, in float[] xs, in float[] ys, in int[] ids, int count, long downTime, int rot) = 4;

    // O sanal ekrana tuş enjekte eder (ör. KEYCODE_BACK = 4).
    void injectKey(int displayId, int keyCode) = 5;

    // O sanal ekranı kapatır VE içinde açılan uygulamayı tamamen sonlandırır (force-stop).
    void close(int displayId) = 6;

    // Son hata mesajı (teşhis için).
    String lastError() = 7;

    // Tüm sanal ekranları kapatır ve uygulamalarını sonlandırır.
    void closeAll() = 8;

    // Gerçek FARE olayı (hover, tuşlar, tekerlek). x/y 0..1 aralığında.
    void injectMouse(int displayId, int action, float x, float y, int buttonState, int actionButton, float hscroll, float vscroll, long downTime, int rot) = 9;
}
