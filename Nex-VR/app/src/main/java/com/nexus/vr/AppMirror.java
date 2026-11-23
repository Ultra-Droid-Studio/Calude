package com.nexus.vr;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Stage 56/57 — Başka bir Android uygulamasını VR penceresinde gösterir.
 *
 * Akış: uygulamaya ait PUBLIC bir VirtualDisplay açılır -> Shizuku kabuk servisi seçilen uygulamayı
 * o ekranda başlatır ("am start --display") -> ekran görüntüsü ImageReader ile alınıp JPEG'e
 * sıkıştırılır ve GpuPage ile aynı yoldan (gpuFrame / __nxGpu / _snap) VR dokusuna gider.
 * Dokunma/kaydırma/tuş olayları Shizuku üzerinden aynı ekrana enjekte edilir.
 *
 * İş parçacıkları: 'gfx' (kare okuma + JPEG), 'io' (Shizuku binder çağrıları — UI'yi bloklamaz).
 * Tüm genel yöntemler herhangi bir iş parçacığından çağrılabilir.
 *
 * Stage 57: başlatma doğrulanır ve yeniden denenir (servis bağlanıyor / görev başka ekranda öne alındı /
 * sanal ekran henüz hazır değil), ilk kare gelmezse zaman aşımıyla bildirilir, ana ekran arka plana
 * gidince kare sıkıştırma durur, klavye (metin + tuş) girdisi eklendi, kapanış beklenebilir.
 */
final class AppMirror {
    /** why: "" (başarılı) | "front" | "error" | "service" | "noframe" | "closed". */
    interface Result { void launched(String id, boolean ok, String why); }

    private static final String TAG = "NEXUS-Mirror";
    private static final int MIN_GAP_MS = 33, MAX_GAP_MS = 160, Q_MOTION = 58, Q_SETTLE = 84, SETTLE_MS = 240;
    /** Stage 59 — telefon profili: küçük ekran/zayıf GPU-CPU için daha az piksel, daha seyrek ve hafif JPEG. */
    private static final int PH_MAX_W = 960, PH_MIN_GAP_MS = 55, PH_MAX_GAP_MS = 220, PH_Q_MOTION = 48, PH_Q_SETTLE = 78, PH_SETTLE_MS = 320;
    /** Telefonda hedef en/boy (yatay 16:9); sanal ekran tablet boyutunda açılmaz. */
    private volatile boolean phone;
    private int minGap = MIN_GAP_MS, maxGap = MAX_GAP_MS, qMotion = Q_MOTION, qSettle = Q_SETTLE, settleMs = SETTLE_MS;
    /** Stage 63: sınıf+seviyeye göre sanal ekran genişliği üst sınırı (0 = sınırsız). */
    private int maxW = 0;
    /** Başlatma denemesi sayısı ve ilk karenin gelmesi için beklenen en uzun süre. */
    private static final int LAUNCH_TRIES = 3, FIRST_FRAME_MS = 20000;

    final String id, pkg;
    private final ShizukuLink link;
    private final GpuPage.Sink sink;

    private HandlerThread gfxT, ioT;
    private Handler gfx, io;
    private volatile VirtualDisplay display;
    private volatile ImageReader reader;
    /** Stage 58: ekran Shizuku servisinde (güvenilir/trusted) açıldı; display alanı null, kapatma/boyutlandırma servis üzerinden. */
    private volatile boolean remote;
    private final Object lock = new Object();
    private volatile int displayId = -1;
    private volatile int w, h, dpi;
    private volatile boolean closed;
    /** Uygulama sanal ekranda gerçekten başlatıldı mı (kapatırken yalnızca o zaman force-stop yapılır). */
    private volatile boolean started;
    /** Sanal ekrandan en az bir kare geldi mi (gelmediyse uygulama büyük olasılıkla başka ekranda açıldı). */
    private volatile boolean gotFrame;
    /** Ana etkinlik arka planda: kareler atılır, JPEG üretilmez. */
    private volatile boolean paused;

    // gfx iş parçacığı
    private Bitmap frame;
    private int frameW, frameH;
    private boolean dirty, encodePending, sharp = true;
    private long lastEncode;
    private float avgCost = 12f;
    private final ByteArrayOutputStream bos = new ByteArrayOutputStream(128 * 1024);
    private final AtomicInteger seq = new AtomicInteger();

    // io iş parçacığı
    private long downTime;
    private final AtomicReference<float[]> pendingMove = new AtomicReference<>();
    private int pw, ph, pcss;

    private AppMirror(String id, String pkg, ShizukuLink link, GpuPage.Sink sink) {
        this.id = id; this.pkg = pkg; this.link = link; this.sink = sink;
    }

    static int align(int v) { return Math.max(64, Math.round(v / 64f) * 64); }

    private static String whyOf(int rc) {
        if (rc == ShellService.L_FRONT) return "front";
        if (rc == ShellService.L_ERROR || rc == ShellService.L_INVALID) return "error";
        return "service";
    }

    /**
     * 'io' iş parçacığında çalışır. Hazır olana kadar servisi bekler; geçici hatalarda artan bekleyişle,
     * görev başka ekranda öne alındıysa (singleTask/singleInstance) uygulamayı durdurup bir kez daha dener.
     * Dönüş: ShellService.L_* kodu (0 = başlatıldı).
     */
    private int launchSmart(String component, int did) {
        int rc = ShellService.L_FAIL;
        boolean stoppedOnce = false;
        for (int attempt = 0; attempt < LAUNCH_TRIES && !closed; attempt++) {
            if (!link.ready() && !link.waitReady(2500)) { rc = ShellService.L_FAIL; continue; }
            rc = link.launch(component, did);
            if (rc == ShellService.L_OK || rc == ShellService.L_INVALID) return rc;
            if (rc == ShellService.L_FRONT && !stoppedOnce) {
                // Uygulamanın görevi başka ekranda: durdurmadan sanal ekrana taşınamaz.
                Log.w(TAG, "görev başka ekranda öne alındı, uygulama durdurulup yeniden başlatılıyor: " + pkg);
                stoppedOnce = true;
                link.stopPackage(pkg);
                sleep(450);
                continue;
            }
            sleep(450L * (attempt + 1)); // sanal ekran / servis henüz hazır olmayabilir
        }
        return rc;
    }

    /**
     * Stage 63 — profil (sınıf × seviye). Telefon orta seviye = Stage 59 değerleri aynen; tablet orta/yüksek = eski varsayılan.
     *                 maxW   minGap maxGap qMotion qSettle settleMs
     *  telefon düşük   800     70    260     44     74     340
     *  telefon orta    960     55    220     48     78     320   (Stage 59)
     *  telefon yüksek 1080     40    180     54     82     280
     *  tablet  düşük  1024     45    200     52     80     280
     *  tablet  orta/yüksek: sınırsız, 33/160, 58/84, 240   (eski davranış)
     */
    private void applyProfile(DeviceProfile dp) {
        if (dp.phone) {
            switch (dp.tier) {
                case 0: maxW = 800;  minGap = 70; maxGap = 260; qMotion = 44; qSettle = 74; settleMs = 340; break;
                case 2: maxW = 1080; minGap = 40; maxGap = 180; qMotion = 54; qSettle = 82; settleMs = 280; break;
                default: maxW = PH_MAX_W; minGap = PH_MIN_GAP_MS; maxGap = PH_MAX_GAP_MS;
                         qMotion = PH_Q_MOTION; qSettle = PH_Q_SETTLE; settleMs = PH_SETTLE_MS;
            }
        } else if (dp.tier == 0) {
            maxW = 1024; minGap = 45; maxGap = 200; qMotion = 52; qSettle = 80; settleMs = 280;
        }
    }

    private static void sleep(long ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
    }

    /** Sanal ekran hazır ve uygulama başlatma isteği gönderilmiş olarak döner; başarısızsa null. */
    static AppMirror open(Context ctx, ShizukuLink link, String id, String pkg, String component,
                          int width, int height, int cssW, GpuPage.Sink sink, Result res) {
        AppMirror m = new AppMirror(id, pkg, link, sink);
        try {
            DeviceProfile dp = DeviceProfile.collect(ctx);
            m.phone = dp.phone;
            m.applyProfile(dp);
            int rw = width, rh = height;
            if (m.maxW > 0 && rw > m.maxW) {
                // Aynı dp genişliği (düzen değişmez), ama daha az piksel: dpi cssW'ye göre yeniden hesaplanır.
                rh = Math.round(rh * (m.maxW / (float) rw));
                rw = m.maxW;
            }
            m.w = align(rw); m.h = Math.max(240, rh);
            m.dpi = GpuPage.dpiFor(m.w, cssW);
            m.gfxT = new HandlerThread("nexus-mirror-gfx-" + id); m.gfxT.start();
            m.ioT = new HandlerThread("nexus-mirror-io-" + id); m.ioT.start();
            m.gfx = new Handler(m.gfxT.getLooper());
            m.io = new Handler(m.ioT.getLooper());
            m.reader = m.newReader(m.w, m.h);
            DisplayManager dm = (DisplayManager) ctx.getSystemService(Context.DISPLAY_SERVICE);
            int own = DisplayManager.VIRTUAL_DISPLAY_FLAG_PUBLIC | DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY;
            try {
                m.display = dm.createVirtualDisplay("NEXUS app " + id, m.w, m.h, m.dpi, m.reader.getSurface(),
                        own | DisplayManager.VIRTUAL_DISPLAY_FLAG_PRESENTATION);
            } catch (Throwable first) {
                Log.w(TAG, "PRESENTATION bayrağıyla açılamadı, bayraksız deneniyor: " + first);
                m.display = dm.createVirtualDisplay("NEXUS app " + id, m.w, m.h, m.dpi, m.reader.getSurface(), own);
            }
            if (m.display == null || m.display.getDisplay() == null) throw new IllegalStateException("createVirtualDisplay null");
            m.displayId = m.display.getDisplay().getDisplayId();
            m.io.post(() -> {
                // Stage 58: önce güvenilir sanal ekrana geçmeyi dene (başarısızsa uygulamanın kendi ekranı kullanılır).
                m.upgradeToTrusted();
                final int did = m.displayId;
                int rc = m.launchSmart(component, did);
                boolean ok = rc == ShellService.L_OK;
                m.started = ok;
                if (!ok) Log.w(TAG, "uygulama sanal ekranda başlatılamadı: " + component + " display=" + did + " kod=" + rc);
                if (res != null) res.launched(id, ok, ok ? "" : m.closed ? "closed" : whyOf(rc));
                if (ok) {
                    // İlk kare gelmezse (görev gerçek ekranda öne alınmış olabilir) bir kez daha haber ver.
                    m.io.postDelayed(() -> {
                        if (!m.closed && !m.gotFrame && res != null) {
                            Log.w(TAG, "sanal ekrandan kare gelmedi: " + component);
                            res.launched(id, false, "noframe");
                        }
                    }, FIRST_FRAME_MS);
                }
            });
            return m;
        } catch (Throwable e) {
            Log.e(TAG, "Uygulama penceresi açılamadı: " + pkg, e);
            m.release(false);
            return null;
        }
    }

    /**
     * Stage 58 — 'io' iş parçacığı. Güvenilir (trusted) bir sanal ekranı Shizuku servisinde (shell yetkisiyle) açmayı dener.
     * Güvenilmeyen ekranda Android, başka uygulamanın etkinliklerini (dosya seçici, başlatıcının açtığı uygulamalar)
     * reddedip gerçek ekrana atar; güvenilir ekranda pencerenin içinde kalırlar. Olmazsa hiçbir şey değişmez.
     */
    private void upgradeToTrusted() {
        if (closed) return;
        if (!link.ready() && !link.waitReady(2500)) return;
        ImageReader nr = null;
        try {
            String nm = "NEXUS " + (id.length() > 30 ? id.substring(0, 30) : id);
            nr = newReader(w, h);
            int nid = link.createDisplay(nm, w, h, dpi, nr.getSurface());
            if (nid <= 0) {
                Log.w(TAG, "güvenilir sanal ekran açılamadı, uygulamanın kendi ekranı kullanılıyor (Android 13+ ve Shizuku gerekir)");
                nr.close();
                return;
            }
            VirtualDisplay oldD; ImageReader oldR;
            synchronized (lock) {
                if (closed) { link.releaseDisplay(nid); nr.close(); return; }
                oldD = display; oldR = reader;
                display = null; reader = nr; remote = true; displayId = nid;
            }
            try { if (oldD != null) oldD.release(); } catch (Throwable ignored) { }
            try { if (oldR != null) oldR.close(); } catch (Throwable ignored) { }
            Log.i(TAG, "güvenilir sanal ekran kullanılıyor: display=" + nid);
        } catch (Throwable e) {
            Log.w(TAG, "güvenilir ekrana geçilemedi: " + e);
            if (nr != null) { try { nr.close(); } catch (Throwable ignored) { } }
        }
    }

    // ---- girdi (Shizuku üzerinden) ----

    /** action 0=bas 1=sürükle 2=bırak 3=iptal; nx,ny 0..1. */
    void touch(final int action, float nx, float ny) {
        if (closed || displayId < 0) return;
        final float x = Math.max(0f, Math.min(1f, nx)) * (w - 1), y = Math.max(0f, Math.min(1f, ny)) * (h - 1);
        if (action == 1) {
            // Sürükleme: yalnızca en son konum gönderilir (kuyruk birikmez)
            if (pendingMove.getAndSet(new float[]{x, y}) != null) return;
            io.post(() -> {
                float[] p = pendingMove.getAndSet(null);
                if (p != null && downTime != 0) link.touch(displayId, 1, p[0], p[1], downTime);
            });
            return;
        }
        io.post(() -> {
            if (action == 0) downTime = SystemClock.uptimeMillis();
            else if (downTime == 0) return;
            link.touch(displayId, action, x, y, downTime);
            if (action >= 2) downTime = 0;
        });
    }

    /** Bakış/dokunma ile tek tık. */
    void tap(float nx, float ny) {
        if (closed || displayId < 0) return;
        final float x = Math.max(0f, Math.min(1f, nx)) * (w - 1), y = Math.max(0f, Math.min(1f, ny)) * (h - 1);
        io.post(() -> {
            long t = SystemClock.uptimeMillis();
            link.touch(displayId, 0, x, y, t);
            SystemClock.sleep(45);
            link.touch(displayId, 2, x, y, t);
        });
    }

    /** direction > 0: içerik aşağı kayar (parmak yukarı), < 0: yukarı. */
    void scroll(int direction) {
        if (closed || displayId < 0) return;
        final float x = w * .5f, a = h * (direction > 0 ? .72f : .28f), b = h * (direction > 0 ? .28f : .72f);
        io.post(() -> link.swipe(displayId, x, a, x, b, 240));
    }

    void key(final int keyCode) {
        if (closed || displayId < 0) return;
        io.post(() -> link.key(displayId, keyCode));
    }

    /**
     * Stage 57: odaklı alana metin yaz. Yazı sırayı korur (aynı 'io' kuyruğu). Dönüş: kuyruğa alındı mı;
     * işlenen karakter sayısı günlüğe yazılır (ASCII dışı harfler uygulamaya bağlıdır).
     */
    boolean typeText(final String text) {
        if (closed || displayId < 0 || text == null || text.isEmpty() || text.length() > 64) return false;
        io.post(() -> {
            int n = link.typeText(displayId, text);
            if (n < text.codePointCount(0, text.length())) Log.w(TAG, "metin kısmen yazıldı: " + n + "/" + text.length());
        });
        return true;
    }

    // ---- ana etkinlik arka planda ----

    void setPaused(boolean p) {
        paused = p;
        if (!p && gfx != null && !closed) gfx.post(() -> { dirty = frame != null; scheduleEncode(); });
    }

    // ---- boyut ----

    void resizeLater(int width, int height, int cssW) {
        if (closed) return;
        pw = width; ph = height; pcss = cssW;
        gfx.removeCallbacks(resizeTask);
        gfx.postDelayed(resizeTask, 500); // sürüklerken uygulama sürekli yeniden başlamasın
    }

    private final Runnable resizeTask = new Runnable() {
        @Override public void run() {
            synchronized (lock) {
                if (closed || (display == null && !remote)) return;
                int rw2 = pw, rh2 = ph;
                if (maxW > 0 && rw2 > maxW) { rh2 = Math.round(rh2 * (maxW / (float) rw2)); rw2 = maxW; }
                int nw = align(rw2), nh = Math.max(240, rh2), nd = GpuPage.dpiFor(nw, pcss);
                if (nw == w && nh == h && nd == dpi) return;
                ImageReader nr = null;
                try {
                    ImageReader old = reader;
                    nr = newReader(nw, nh);
                    if (remote) {
                        if (!link.resizeDisplay(displayId, nw, nh, nd, nr.getSurface())) { nr.close(); return; }
                    } else {
                        display.setSurface(nr.getSurface());
                        display.resize(nw, nh, nd);
                    }
                    reader = nr; w = nw; h = nh; dpi = nd;
                    if (old != null) { try { old.close(); } catch (Throwable ignored) { } }
                } catch (Throwable e) {
                    Log.e(TAG, "yeniden boyutlandırma başarısız: " + id, e);
                    if (nr != null && nr != reader) { try { nr.close(); } catch (Throwable ignored) { } }
                }
            }
        }
    };

    private ImageReader newReader(int width, int height) {
        ImageReader r = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2);
        r.setOnImageAvailableListener(rd -> onFrame(rd), gfx);
        return r;
    }

    // ---- kare hattı (gfx iş parçacığı; GpuPage ile aynı mantık) ----

    private void onFrame(ImageReader rd) {
        Image img = null;
        try {
            img = rd.acquireLatestImage();
            if (img == null || closed) return;
            gotFrame = true;
            if (paused) return; // görüntü atılır (reader tıkanmasın diye yukarıda alındı); arka planda JPEG üretme
            Image.Plane p = img.getPlanes()[0];
            if (p.getPixelStride() != 4) return;
            ByteBuffer buf = p.getBuffer();
            int pad = p.getRowStride() / 4, iw = img.getWidth(), ih = img.getHeight();
            if (frame == null || frame.getWidth() != pad || frame.getHeight() != ih) {
                if (frame != null) frame.recycle();
                frame = Bitmap.createBitmap(pad, ih, Bitmap.Config.ARGB_8888);
            }
            int need = pad * 4 * ih;
            buf.rewind();
            if (buf.remaining() < need) {
                ByteBuffer t = ByteBuffer.allocateDirect(need);
                t.put(buf); t.rewind(); buf = t;
            }
            frame.copyPixelsFromBuffer(buf);
            frameW = iw; frameH = ih; dirty = true; sharp = false;
        } catch (Throwable e) {
            Log.w(TAG, "kare okunamadı: " + e);
        } finally {
            if (img != null) { try { img.close(); } catch (Throwable ignored) { } }
        }
        scheduleEncode();
    }

    private final Runnable encodeTask = new Runnable() {
        @Override public void run() {
            encodePending = false;
            if (!dirty || frame == null || closed) return;
            dirty = false;
            push(qMotion);
            sharp = false;
            gfx.removeCallbacks(settleTask);
            gfx.postDelayed(settleTask, settleMs);
        }
    };

    private final Runnable settleTask = new Runnable() {
        @Override public void run() {
            if (closed || sharp || dirty || frame == null) return;
            sharp = true;
            push(qSettle);
        }
    };

    private void push(int quality) {
        long t0 = SystemClock.uptimeMillis();
        lastEncode = t0;
        Bitmap src = frame, crop = null;
        try {
            if (src.getWidth() != frameW) { crop = Bitmap.createBitmap(src, 0, 0, frameW, frameH); src = crop; }
            bos.reset();
            src.compress(Bitmap.CompressFormat.JPEG, quality, bos);
            sink.frame(id, bos.toByteArray(), seq.incrementAndGet());
        } catch (Throwable e) {
            Log.w(TAG, "JPEG sıkıştırma başarısız: " + e);
        } finally {
            if (crop != null) crop.recycle();
        }
        avgCost = avgCost * 0.7f + (SystemClock.uptimeMillis() - t0) * 0.3f;
    }

    private void scheduleEncode() {
        if (encodePending || closed) return;
        encodePending = true;
        long gap = Math.max(minGap, Math.min(maxGap, Math.round(avgCost * (phone ? 2.4f : 1.8f))));
        long wait = Math.max(0, gap - (SystemClock.uptimeMillis() - lastEncode));
        gfx.postDelayed(encodeTask, wait);
    }

    // ---- kapatma ----

    /**
     * Pencereyi kapatır. stopApp=true ise uygulama durdurulur: sanal ekran silinince görevleri
     * gerçek ekrana taşınabildiği için önce durdurulur (uygulamanın açık oturumu kaybolur).
     */
    void release(boolean stopApp) { release(stopApp, null); }

    /** done (boş olabilir): sanal ekran kapatılıp (ve gerekiyorsa uygulama durdurulup) bittiğinde 'io' iş parçacığında çağrılır. */
    void release(boolean stopApp, final Runnable done) {
        if (closed) { if (done != null) done.run(); return; }
        closed = true;
        final Handler ioh = io, gfxh = gfx;
        final HandlerThread it = ioT, gt = gfxT;
        Runnable finish = () -> {
            final VirtualDisplay d; final ImageReader r; final boolean rem; final int did;
            synchronized (lock) { d = display; r = reader; rem = remote; did = displayId; }
            try { if (d != null) d.release(); } catch (Throwable ignored) { }
            if (rem && did >= 0) link.releaseDisplay(did);
            if (gfxh != null) gfxh.post(() -> {
                try { if (r != null) r.close(); } catch (Throwable ignored) { }
                if (frame != null) { frame.recycle(); frame = null; }
                if (gt != null) gt.quitSafely();
            }); else if (gt != null) gt.quitSafely();
            if (done != null) { try { done.run(); } catch (Throwable ignored) { } }
            if (it != null) it.quitSafely();
        };
        if (gfxh != null) { gfxh.removeCallbacks(encodeTask); gfxh.removeCallbacks(settleTask); gfxh.removeCallbacks(resizeTask); }
        if (ioh != null) {
            ioh.post(() -> {
                if (stopApp && started) link.stopPackage(pkg);
                finish.run();
            });
        } else {
            finish.run();
        }
    }
}
