package com.nexus.vr;

import android.content.ComponentName;
import android.content.Context;
import android.content.ServiceConnection;
import android.content.pm.PackageManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.Log;
import android.view.Surface;

import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import rikka.shizuku.Shizuku;

/**
 * Stage 56/57 — Shizuku bağlantı yöneticisi (uygulama sürecinde).
 *
 * Stage 57: servis sürümü doğrulanır (eski Stage 56 servisi kalmışsa yeniden başlatılır), servis
 * düşerse otomatik yeniden bağlanılır, waitReady() ile açılışlar bağlantıyı bekleyebilir.
 *
 * Durumlar (state()):
 *   0 YOK     Shizuku çalışmıyor / yüklü değil
 *   1 İZİNSİZ Shizuku çalışıyor, bu uygulamaya izin verilmemiş
 *   2 RET     Kullanıcı "bir daha sorma" dedi; izin yalnızca Shizuku uygulamasından verilebilir
 *   3 BAĞLI-DEĞİL  İzin var, kabuk servisi henüz bağlanmadı (bağlanıyor)
 *   4 HAZIR   Kabuk servisi bağlı, VirtualDisplay'e uygulama açılabilir
 *
 * Hiçbir çağrı ana (UI) iş parçacığını bloklamaz: ikili (binder) çağrıları çağıranın iş parçacığında
 * çalışır; AppMirror bunları kendi 'io' iş parçacığından yapar.
 */
final class ShizukuLink {
    static final int REQ = 5601;
    static final int S_NONE = 0, S_NOPERM = 1, S_DENIED = 2, S_BINDING = 3, S_READY = 4;
    private static final String TAG = "NEXUS-Shizuku";
    private static final String SHIZUKU_PKG = "moe.shizuku.privileged.api";
    private static final int SERVICE_VERSION = 3; // Stage 58: AIDL değişti (createDisplay/resizeDisplay/releaseDisplay); Shizuku eski servisi yeniden başlatsın

    /** VR penceresinde AÇILMAYACAK uygulamalar (banka/ödeme/DRM akış). Bunlar normal ekranda açılır. */
    private static final String[] DENY_PARTS = {
            "bank", "banka", "paypal", "wallet", "papara", "garanti", "ziraat", "akbank", "isbank",
            "yapikredi", "denizbank", "enpara", "tosla", "ininal", "paycell", "binance", "tcmb",
            "netflix", "disney", "primevideo", "amazon.avod", "hbomax", "hbo.", "mubi", "blutv", "tabii",
            "e-devlet", "edevlet", "turkiye.gov"
    };

    private final Context ctx;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private volatile IShellService svc;
    private volatile boolean binding;
    private volatile Runnable onChange;
    private boolean listenersOn;
    private final ExecutorService worker = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "nexus-shz-link"); t.setDaemon(true); return t;
    });
    private int staleTries, reconnectTries;
    private volatile boolean stopped;

    private final Shizuku.OnBinderReceivedListener onBinder = () -> { refresh(); };
    private final Shizuku.OnBinderDeadListener onDead = () -> { svc = null; binding = false; reconnectTries = 0; changed(); };
    private final Shizuku.OnRequestPermissionResultListener onPerm = (code, result) -> { refresh(); };

    private final ServiceConnection conn = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName n, IBinder b) {
            if (b == null || !b.pingBinder()) { binding = false; changed(); return; }
            final IShellService s = IShellService.Stub.asInterface(b);
            // Sürüm denetimi binder çağrısıdır: UI iş parçacığında yapılmaz.
            worker.execute(() -> {
                int v = -1;
                try { v = s.version(); } catch (Throwable ignored) { }
                if (v != ShellService.API_VERSION) {
                    Log.w(TAG, "kabuk servisi sürümü uyuşmuyor (" + v + " != " + ShellService.API_VERSION + ")");
                    binding = false;
                    if (!stopped && staleTries++ < 2) { unbind(); ui.postDelayed(ShizukuLink.this::refresh, 500); }
                    else changed();
                    return;
                }
                staleTries = 0; reconnectTries = 0;
                svc = s;
                binding = false;
                changed();
            });
        }
        @Override public void onServiceDisconnected(ComponentName n) {
            svc = null; binding = false; changed();
            scheduleReconnect();
        }
    };

    /** Servis beklenmedik biçimde düştüyse (Shizuku yeniden başladı, süreç öldü) birkaç kez yeniden bağlan. */
    private void scheduleReconnect() {
        if (stopped || reconnectTries >= 4) return;
        long delay = 600L * (1 << reconnectTries++);
        ui.postDelayed(() -> { if (!stopped) refresh(); }, delay);
    }

    ShizukuLink(Context c) { ctx = c.getApplicationContext(); }

    void setOnChange(Runnable r) { onChange = r; }

    /** Dinleyicileri kaydet (Activity açılırken bir kez). */
    void start() {
        if (listenersOn) return;
        listenersOn = true;
        stopped = false;
        try {
            Shizuku.addBinderReceivedListenerSticky(onBinder);
            Shizuku.addBinderDeadListener(onDead);
            Shizuku.addRequestPermissionResultListener(onPerm);
        } catch (Throwable e) { Log.w(TAG, "dinleyici eklenemedi: " + e); }
    }

    void stop() {
        stopped = true;
        if (listenersOn) {
            listenersOn = false;
            try {
                Shizuku.removeBinderReceivedListener(onBinder);
                Shizuku.removeBinderDeadListener(onDead);
                Shizuku.removeRequestPermissionResultListener(onPerm);
            } catch (Throwable ignored) { }
        }
        unbind();
        worker.shutdownNow();
    }

    private void changed() {
        final Runnable r = onChange;
        if (r != null) ui.post(r);
    }

    private boolean alive() {
        try { return Shizuku.pingBinder(); } catch (Throwable e) { return false; }
    }

    boolean installed() {
        try { ctx.getPackageManager().getPackageInfo(SHIZUKU_PKG, 0); return true; }
        catch (PackageManager.NameNotFoundException e) { return false; }
        catch (Throwable e) { return false; }
    }

    boolean ready() {
        IShellService s = svc;
        return s != null && s.asBinder().pingBinder();
    }

    /**
     * Kabuk servisi hazır olana kadar (en çok timeoutMs) bekler; gerekirse bağlanmayı tetikler.
     * UI iş parçacığından ÇAĞIRMAYIN (AppMirror 'io' iş parçacığı kullanır).
     */
    boolean waitReady(long timeoutMs) {
        long end = System.currentTimeMillis() + timeoutMs;
        while (!stopped) {
            if (ready()) return true;
            if (state() == S_BINDING) bind();
            if (System.currentTimeMillis() >= end) break;
            try { Thread.sleep(120); } catch (InterruptedException e) { Thread.currentThread().interrupt(); return false; }
        }
        return ready();
    }

    int state() {
        if (!alive()) return S_NONE;
        try {
            if (Shizuku.isPreV11()) return S_NONE; // çok eski Shizuku: UserService desteklemez
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) {
                return Shizuku.shouldShowRequestPermissionRationale() ? S_DENIED : S_NOPERM;
            }
        } catch (Throwable e) { return S_NONE; }
        return svc != null && svc.asBinder().pingBinder() ? S_READY : S_BINDING;
    }

    /** İzin zaten verilmişse kabuk servisine bağlan. İzin İSTEMEZ (Shizuku açılınca ansızın iletişim kutusu çıkmasın). */
    void refresh() {
        if (state() == S_BINDING) bind();
        changed();
    }

    /** Kullanıcı eylemiyle çağrılır: izin yoksa Shizuku'nun kendi iletişim kutusunu açar, varsa bağlanır. */
    void poke() {
        int s = state();
        if (s == S_NOPERM) {
            try { Shizuku.requestPermission(REQ); } catch (Throwable e) { Log.w(TAG, "izin istenemedi: " + e); }
        } else if (s == S_BINDING) {
            bind();
        }
        changed();
    }

    private void bind() {
        if (binding || svc != null) return;
        binding = true;
        try {
            Shizuku.UserServiceArgs a = new Shizuku.UserServiceArgs(
                    new ComponentName(ctx.getPackageName(), ShellService.class.getName()))
                    .daemon(false).processNameSuffix("shell").debuggable(false).version(SERVICE_VERSION);
            Shizuku.bindUserService(a, conn);
        } catch (Throwable e) {
            binding = false;
            Log.w(TAG, "bindUserService başarısız: " + e);
        }
    }

    private void unbind() {
        svc = null; binding = false;
        try {
            Shizuku.UserServiceArgs a = new Shizuku.UserServiceArgs(
                    new ComponentName(ctx.getPackageName(), ShellService.class.getName()))
                    .daemon(false).processNameSuffix("shell").debuggable(false).version(SERVICE_VERSION);
            Shizuku.unbindUserService(a, conn, true);
        } catch (Throwable ignored) { }
    }

    /** JSON: {"s":durum,"i":yüklü} */
    String statusJson() {
        return "{\"s\":" + state() + ",\"i\":" + installed() + "}";
    }

    static boolean denied(String pkg) {
        if (pkg == null) return true;
        String p = pkg.toLowerCase(Locale.ROOT);
        for (String d : DENY_PARTS) if (p.contains(d)) return true;
        // Sistem ve Nex VR'ın kendisi
        return p.equals("android") || p.startsWith("com.android.systemui") || p.startsWith("com.nexus.vr")
                || p.equals(SHIZUKU_PKG);
    }

    // ---- kabuk servisi çağrıları (bloklar; UI iş parçacığından ÇAĞIRMAYIN) ----

    /** Dönüş kodları: ShellService.L_* (0 = başlatıldı). */
    int launch(String component, int displayId) {
        IShellService s = svc;
        if (s == null) return ShellService.L_FAIL;
        try { return s.launch(component, displayId); } catch (Throwable e) { return ShellService.L_FAIL; }
    }

    /** Metin yaz. Dönüş: işlenen karakter sayısı, hata = -1. */
    int typeText(int displayId, String text) {
        IShellService s = svc;
        if (s == null) return -1;
        try { return s.typeText(displayId, text); } catch (Throwable e) { return -1; }
    }

    boolean touch(int displayId, int action, float x, float y, long downTime) {
        IShellService s = svc;
        if (s == null) return false;
        try { return s.touch(displayId, action, x, y, downTime); } catch (Throwable e) { return false; }
    }

    boolean key(int displayId, int keyCode) {
        IShellService s = svc;
        if (s == null) return false;
        try { return s.key(displayId, keyCode); } catch (Throwable e) { return false; }
    }

    boolean swipe(int displayId, float x0, float y0, float x1, float y1, int ms) {
        IShellService s = svc;
        if (s == null) return false;
        try { return s.swipe(displayId, x0, y0, x1, y1, ms); } catch (Throwable e) { return false; }
    }

    boolean stopPackage(String pkg) {
        IShellService s = svc;
        if (s == null) return false;
        try { return s.stopPackage(pkg); } catch (Throwable e) { return false; }
    }

    /** Stage 58: güvenilir sanal ekran aç. Dönüş: ekran numarası (> 0), olmadıysa -1. */
    int createDisplay(String name, int w, int h, int dpi, Surface surface) {
        IShellService s = svc;
        if (s == null) return -1;
        try { return s.createDisplay(name, w, h, dpi, surface); } catch (Throwable e) { return -1; }
    }

    boolean resizeDisplay(int displayId, int w, int h, int dpi, Surface surface) {
        IShellService s = svc;
        if (s == null) return false;
        try { return s.resizeDisplay(displayId, w, h, dpi, surface); } catch (Throwable e) { return false; }
    }

    void releaseDisplay(int displayId) {
        IShellService s = svc;
        if (s == null) return;
        try { s.releaseDisplay(displayId); } catch (Throwable ignored) { }
    }
}
