package com.nexus.vr;

import android.view.Surface;

/**
 * Stage 56/57 — Shizuku UserService arayüzü. Servis, Shizuku tarafından "shell" (adb) yetkisiyle
 * ayrı bir süreçte çalıştırılır; uygulama yalnızca aşağıdaki sabit işlemleri isteyebilir
 * (keyfi komut çalıştırma YOKTUR).
 */
interface IShellService {
    /** Shizuku'nun ayırdığı yok-etme çağrısı (sabit kod). */
    void destroy() = 16777114;

    /**
     * Bileşeni (paket/Activity) verilen sanal ekranda başlatır.
     * Dönüş (Stage 57): 0 = başlatıldı, 10 = başlatılmadı (görev başka ekranda öne alındı),
     * 11 = `am` hata yazdı, -2 = geçersiz argüman, -1 = çalıştırılamadı / zaman aşımı, diğer = `am` çıkış kodu.
     */
    int launch(String component, int displayId) = 1;

    /** Gerçek dokunma olayı: action 0=bas 1=sürükle 2=bırak 3=iptal. Koordinatlar ekran pikseli. */
    boolean touch(int displayId, int action, float x, float y, long downTime) = 2;

    /** Tuş (BACK=4, ENTER=66, DEL=67 ...) bas+bırak, verilen ekrana (klavye kaynaklı olay). */
    boolean key(int displayId, int keyCode) = 3;

    /** Kaydırma: (x0,y0)->(x1,y1), süre ms. Servis iş parçacığında bloklar, çağıran arka plandan çağırmalı. */
    boolean swipe(int displayId, float x0, float y0, float x1, float y1, int durationMs) = 4;

    /** Verilen ekrandaki tüm görevleri kapatmak için paketi öldürür (force-stop). */
    boolean stopPackage(String pkg) = 5;

    /** Stage 57: metni verilen ekrandaki odaklı alana yazar. Dönüş: işlenen karakter sayısı, hata = -1. */
    int typeText(int displayId, String text) = 6;

    /** Stage 57: servis API sürümü (eski bir Stage 56 servisi bağlanırsa uygulama bunu anlar ve yeniden başlatır). */
    int version() = 7;

    /**
     * Stage 58: GÜVENİLİR (trusted) sanal ekran açar (Android 13+, shell yetkisiyle). Güvenilir ekranda dosya seçici,
     * başka uygulamanın etkinlikleri ve başlatıcı uygulamaların açtığı pencereler gerçek ekrana kaçmaz.
     * Dönüş: ekran numarası (> 0), açılamadıysa -1 (uygulama kendi sanal ekranına döner).
     */
    int createDisplay(String name, int width, int height, int dpi, in Surface surface) = 8;

    /** Stage 58: servisin açtığı ekranı yeniden boyutlandır ve yeni yüzeye bağla. */
    boolean resizeDisplay(int displayId, int width, int height, int dpi, in Surface surface) = 9;

    /** Stage 58: servisin açtığı ekranı kapat (görevleri yok edilir). */
    void releaseDisplay(int displayId) = 10;
}
