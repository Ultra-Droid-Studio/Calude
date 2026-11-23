package com.nexus.vr;

import android.app.Presentation;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.widget.FrameLayout;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Stage 27 — GPU tarayıcı.
 *
 * Bir WebView'i ana ekrana HİÇ eklemeden, uygulamaya ait özel (private) bir VirtualDisplay içinde,
 * gerçek GPU hızlandırmalı bir pencerede (Presentation) çalıştırır. Böylece:
 *  - video / WebGL / CSS katmanları gerçek ekrandaki gibi çizilir (View.draw() bunları yakalayamıyordu),
 *  - WebView ana ekranda asılı kalamaz, pencerenin dışına çıkamaz,
 *  - kareler ImageReader ile alınır, arka plan iş parçacığında JPEG'e sıkıştırılır (ana iş parçacığı yorulmaz).
 *
 * Tüm genel yöntemler (frame sink hariç) ana (UI) iş parçacığından çağrılır.
 * 'nexus-browser' (ana tarayıcı) ve Win7 monitöründe kullanılır; diğer oyunlar ve
 * web uygulamaları eski (anlık görüntü) yolda kalır.
 */
final class GpuPage {
    interface Sink { void frame(String id, byte[] jpeg, int seq); }

    private static final String TAG = "NEXUS-Gpu";
    private static final int MIN_GAP_MS = 33;        // en çok ~30 kare/sn
    private static final int MAX_GAP_MS = 160;       // cihaz çok yavaşsa bile en az ~6 kare/sn
    private static final int Q_MOTION = 58;          // hareket (kaydırma / video) sırasında hafif JPEG
    private static final int Q_SETTLE = 84;          // hareket durunca tek keskin kare
    private static final int SETTLE_MS = 240;

    private final String id;
    private final Sink sink;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private HandlerThread thread;
    private Handler worker;
    private VirtualDisplay display;
    private Presentation presentation;
    private FrameLayout holder;
    private ImageReader reader;
    private WebView view;
    private int w, h, dpi;
    private volatile boolean active = true, hostPaused = false;
    private volatile boolean closed = false;

    // Yalnızca worker iş parçacığında kullanılır
    private Bitmap frame;
    private int frameW, frameH;
    private boolean dirty, encodePending, sharp = true;
    private long lastEncode;
    private float avgCost = 12f;   // son JPEG sıkıştırma sürelerinin hareketli ortalaması (ms)
    private final ByteArrayOutputStream bos = new ByteArrayOutputStream(128 * 1024);
    private final AtomicInteger seq = new AtomicInteger();

    // Boyut değişimi (sürükleyerek yeniden boyutlandırırken fırtına olmasın diye gecikmeli)
    private int pw, ph, pcss;
    private final Runnable resizeTask = new Runnable() {
        @Override public void run() { applyResize(pw, ph, pcss); }
    };

    private GpuPage(String id, Sink sink) { this.id = id; this.sink = sink; }

    static int align(int v) { return Math.max(64, Math.round(v / 64f) * 64); }
    static int dpiFor(int px, int cssW) { return Math.max(120, Math.min(480, Math.round(160f * px / Math.max(320, cssW)))); }

    /** Sanal ekran + pencere hazır olunca döner; herhangi bir adım başarısızsa null (çağıran eski yola düşer). */
    static GpuPage open(Context ctx, String id, int width, int height, int cssW, Sink sink) {
        GpuPage g = new GpuPage(id, sink);
        try {
            g.w = align(width); g.h = Math.max(240, height); g.dpi = dpiFor(g.w, cssW);
            g.thread = new HandlerThread("nexus-gpu-" + id);
            g.thread.start();
            g.worker = new Handler(g.thread.getLooper());
            g.reader = g.newReader(g.w, g.h);
            DisplayManager dm = (DisplayManager) ctx.getSystemService(Context.DISPLAY_SERVICE);
            // Özel (private) ekran: yalnızca bu uygulamaya ait, ayrıca izin gerekmez.
            g.display = dm.createVirtualDisplay("NEXUS " + id, g.w, g.h, g.dpi, g.reader.getSurface(), 0);
            if (g.display == null) throw new IllegalStateException("createVirtualDisplay null");
            g.presentation = new Presentation(ctx, g.display.getDisplay());
            g.holder = new FrameLayout(g.presentation.getContext());
            g.presentation.setContentView(g.holder);
            if (g.presentation.getWindow() != null) {
                g.presentation.getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            }
            g.presentation.show();
            return g;
        } catch (Throwable e) {
            Log.e(TAG, "GPU sayfası açılamadı: " + id, e);
            g.release();
            return null;
        }
    }

    /** WebView bu bağlamla oluşturulmalı: yoğunluk (dpi) sanal ekrandan gelir, CSS genişliği öngörülebilir olur. */
    Context context() { return presentation.getContext(); }

    void attach(WebView v) {
        view = v;
        holder.addView(v, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        apply();
    }

    void setActive(boolean a) { active = a; apply(); if (a && view != null) view.postInvalidate(); }
    void setHostPaused(boolean p) { hostPaused = p; apply(); }

    private void apply() {
        if (view == null || closed) return;
        try {
            if (active && !hostPaused) view.onResume(); else view.onPause();
        } catch (Throwable e) { Log.w(TAG, "pause/resume: " + e); }
    }

    /** Gecikmeli yeniden boyutlandırma: 150 ms sakinlikten sonra uygulanır. */
    void resizeLater(int width, int height, int cssW) {
        pw = width; ph = height; pcss = cssW;
        ui.removeCallbacks(resizeTask);
        ui.postDelayed(resizeTask, 150);
    }

    private void applyResize(int width, int height, int cssW) {
        if (closed || display == null) return;
        int nw = align(width), nh = Math.max(240, height), nd = dpiFor(nw, cssW);
        if (nw == w && nh == h && nd == dpi) return;
        try {
            ImageReader old = reader;
            ImageReader nr = newReader(nw, nh);
            display.setSurface(nr.getSurface());
            display.resize(nw, nh, nd);
            reader = nr; w = nw; h = nh; dpi = nd;
            if (old != null) worker.post(() -> { try { old.close(); } catch (Throwable ignored) { } });
        } catch (Throwable e) {
            Log.e(TAG, "yeniden boyutlandırma başarısız: " + id, e);
        }
    }

    private ImageReader newReader(int width, int height) {
        ImageReader r = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2);
        r.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
            @Override public void onImageAvailable(ImageReader rd) { onFrame(rd); }
        }, worker);
        return r;
    }

    // ---- worker iş parçacığı ----

    private void onFrame(ImageReader rd) {
        Image img = null;
        try {
            img = rd.acquireLatestImage();
            if (img == null || closed) return;
            Image.Plane p = img.getPlanes()[0];
            if (p.getPixelStride() != 4) return;
            ByteBuffer buf = p.getBuffer();
            int rowStride = p.getRowStride();
            int pad = rowStride / 4, iw = img.getWidth(), ih = img.getHeight();
            if (frame == null || frame.getWidth() != pad || frame.getHeight() != ih) {
                if (frame != null) frame.recycle();
                frame = Bitmap.createBitmap(pad, ih, Bitmap.Config.ARGB_8888);
            }
            int need = pad * 4 * ih;
            buf.rewind();
            if (buf.remaining() < need) {
                // Son satırda dolgu olmayabilir: eksik kısmı sıfırla doldur.
                ByteBuffer t = ByteBuffer.allocateDirect(need);
                t.put(buf);
                t.rewind();
                buf = t;
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

    /**
     * Uyarlanır kare hızı: sıkıştırma ne kadar sürdüyse o kadar dinlenilir (işlemci hiçbir zaman doyurulmaz).
     * Hareket sırasında hafif (Q_MOTION) kareler gider; hareket durunca SETTLE_MS sonra tek keskin (Q_SETTLE) kare gider.
     */
    private final Runnable encodeTask = new Runnable() {
        @Override public void run() {
            encodePending = false;
            if (!dirty || frame == null || closed) return;
            dirty = false;
            push(Q_MOTION);
            sharp = false;
            worker.removeCallbacks(settleTask);
            worker.postDelayed(settleTask, SETTLE_MS);
        }
    };

    private final Runnable settleTask = new Runnable() {
        @Override public void run() {
            if (closed || sharp || dirty || frame == null) return;
            sharp = true;
            push(Q_SETTLE);
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
        long cost = SystemClock.uptimeMillis() - t0;
        avgCost = avgCost * 0.7f + cost * 0.3f;
    }

    private void scheduleEncode() {
        if (encodePending || closed) return;
        encodePending = true;
        long gap = Math.max(MIN_GAP_MS, Math.min(MAX_GAP_MS, Math.round(avgCost * 1.8f)));
        long wait = Math.max(0, gap - (SystemClock.uptimeMillis() - lastEncode));
        worker.postDelayed(encodeTask, wait);
    }

    /** WebView'i pencereden ayırır, pencereyi/ekranı/okuyucuyu kapatır. Çağıran sonra view.destroy() yapabilir. */
    void release() {
        closed = true;
        ui.removeCallbacks(resizeTask);
        if (worker != null) { worker.removeCallbacks(encodeTask); worker.removeCallbacks(settleTask); }
        try {
            if (view != null && view.getParent() instanceof ViewGroup) ((ViewGroup) view.getParent()).removeView(view);
        } catch (Throwable ignored) { }
        try { if (presentation != null) presentation.dismiss(); } catch (Throwable ignored) { }
        try { if (display != null) display.release(); } catch (Throwable ignored) { }
        final ImageReader r = reader;
        final HandlerThread t = thread;
        if (worker != null) {
            worker.post(() -> {
                try { if (r != null) r.close(); } catch (Throwable ignored) { }
                if (frame != null) { frame.recycle(); frame = null; }
            });
        }
        if (t != null) t.quitSafely();
        view = null;
    }
}
