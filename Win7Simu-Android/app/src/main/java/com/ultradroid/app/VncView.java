package com.ultradroid.app;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.os.HandlerThread;
import android.view.TextureView;
import android.widget.FrameLayout;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.util.SparseIntArray;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.io.BufferedInputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Yerel VNC (RFB 3.8) görüntüleyici. noVNC + websockify + WebView yerine Xvnc'ye doğrudan TCP ile bağlanır,
 * kareleri Java'da çözüp Bitmap'e yazar (JavaScript çözme yok). Raw + CopyRect + (Extended)DesktopSize.
 * Dokunma/fare/klavye doğrudan Xvnc'ye gider.
 */
public class VncView extends FrameLayout {

    public interface Host {
        /** Hiç bağlanamadı: HTML tarafı bu pencereyi noVNC'ye geri çevirsin. */
        void failed(String id);
    }

    private final String vid;
    private final String addr;
    private final int port;
    private final float scale;      // sunucu pikseli / görünüm pikseli (1, 0.75, 0.5)
    private final float dpr;        // ana sayfanın cihaz piksel oranı: sunucu çözünürlüğü CSS pikseli esas alınır (noVNC ile aynı boyut)
    private final Host host;

    private final Object lock = new Object();
    private final Object outLock = new Object();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint btnPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Rect srcR = new Rect();
    private final Rect dstR = new Rect();

    private Bitmap bmp;
    /** Çerçeve: sunucudan gelen ham B,G,R,X baytları. Soketten doğrudan buraya okunur, GPU'ya da buradan yüklenir (ara kopya yok). */
    private byte[] fb;
    private int fbW, fbH;
    private byte[] rowBuf = new byte[4096];
    private int[] bmpTmp = new int[0];   // yalnız yedek (Canvas) yol: bayt -> ARGB dönüşümü

    private volatile Socket sock;
    private DataInputStream in;
    private OutputStream out;
    private Thread reader;
    private volatile boolean closed;
    private volatile boolean connected;
    private volatile boolean paused;
    private volatile boolean needFull;
    private volatile boolean reqPending;
    // TigerVNC ContinuousUpdates: sunucu her kare için istek beklemeden değişiklikleri gönderir
    private volatile boolean cuSupported;
    private volatile boolean cuActive;
    private volatile String status = "Bağlanılıyor…";

    // ---- TANI (debug): ekranın sol üstünde canlı sayaçlar. Sorun çözülünce DEBUG = false yap.
    private static final boolean DEBUG = true;
    private volatile int dbgFrames, dbgRects, dbgSent, dbgTouch, dbgReconn, dbgResize;
    private volatile long dbgLastFrame;
    private volatile int dbgFps, dbgDecMs;
    private volatile int dbgGlMs, dbgGlFps, dbgGlKb;   // GPU: son çizim süresi, saniyedeki çizim, son yüklenen KB
    private int dbgGlN;
    private long dbgGlT = System.currentTimeMillis();
    private int dbgFpsN;
    private long dbgFpsT = System.currentTimeMillis();
    private volatile String dbgErr = "";
    private final long dbgStart = System.currentTimeMillis();
    private final Paint dbgPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint dbgBg = new Paint();
    private final Runnable dbgTick = new Runnable() {
        @Override public void run() {
            if (closed) return;
            invalidate();
            ui.postDelayed(this, 500);
        }
    };

    private int screenId;
    private int screenFlags;
    private boolean haveScreen;

    // dokunma durumu
    private int btnMask;
    private boolean twoFinger;
    private float downX, downY;
    private boolean moved;
    private boolean scrolled;
    private float scrollAcc;
    private float lastAvgY;
    private long twoDownT;
    private float twoX, twoY;
    private boolean imeShown;
    private boolean kbDown;
    private final SparseIntArray keyMap = new SparseIntArray();
    private String composing = "";
    private final float density;

    private final Runnable resizeJob = new Runnable() {
        @Override public void run() { sendResizeIfNeeded(); }
    };
    private final Runnable pauseJob = new Runnable() {
        @Override public void run() { paused = true; if (cuActive) enableCU(false); }
    };

    public VncView(Context c, String id, String addr, int port, float scale, float dpr, Host host) {
        super(c);
        this.vid = id;
        this.addr = addr;
        this.port = port;
        this.scale = (scale >= 0.4f && scale <= 1f) ? scale : 1f;
        this.dpr = (dpr >= 1f && dpr <= 4f) ? dpr : 1f;
        this.host = host;
        this.density = c.getResources().getDisplayMetrics().density;
        setFocusable(true);
        setFocusableInTouchMode(true);
        textPaint.setColor(Color.rgb(200, 200, 210));
        textPaint.setTextSize(14 * density);
        btnPaint.setColor(Color.argb(150, 20, 20, 30));
        setBackgroundColor(Color.BLACK);
        dbgPaint.setColor(Color.YELLOW);
        dbgPaint.setTextSize(11 * density);
        dbgBg.setColor(Color.argb(190, 0, 0, 0));
        setWillNotDraw(false);
        setDescendantFocusability(FOCUS_BLOCK_DESCENDANTS);
        if (USE_GL) {
            glView = new TextureView(c);
            gl = new Gl();
            glView.setSurfaceTextureListener(gl);
            addView(glView, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        }
    }

    public void start() {
        if (DEBUG) ui.post(dbgTick);
        reader = new Thread(new Runnable() {
            @Override public void run() { loop(); }
        }, "vnc-" + vid);
        reader.setDaemon(true);
        reader.start();
    }

    public void close() {
        closed = true;
        ui.removeCallbacks(resizeJob);
        ui.removeCallbacks(pauseJob);
        ui.removeCallbacks(dbgTick);
        try { Socket s = sock; if (s != null) s.close(); } catch (Throwable ignored) { }
        try { wr.shutdownNow(); } catch (Throwable ignored) { }
        try { if (gl != null) gl.shutdown(); } catch (Throwable ignored) { }
        synchronized (lock) {
            if (bmp != null) { try { bmp.recycle(); } catch (Throwable ignored) { } bmp = null; }
            fb = null;
        }
    }

    /** Görünürken canlı; görünmezken 1,2 sn sonra duraklar (sunucuya yeni güncelleme istenmez). */
    public void setShown(boolean shown) {
        ui.removeCallbacks(pauseJob);
        if (shown) {
            if (paused) {
                paused = false;
                if (connected) { needFull = true; sendUpdateRequest(false); if (cuSupported) enableCU(true); }
            }
        } else if (!paused) {
            ui.postDelayed(pauseJob, 1200);
        }
    }

    // ------------------------------------------------------------ bağlantı

    private void loop() {
        try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DISPLAY); } catch (Throwable ignored) { }
        int fails = 0;
        boolean everConnected = false;
        while (!closed) {
            try {
                connect();
                everConnected = true;
                fails = 0;
                readLoop();
            } catch (Throwable t) {
                if (closed) return;
                dbgErr = String.valueOf(t);
                dbgReconn++;
                fails++;
                connected = false;
                status = everConnected ? "Bağlantı koptu, yeniden deneniyor…" : "Bağlanılıyor…";
                postInvalidate();
                if (!everConnected && fails >= 3) {
                    status = "Yerel görüntüleyici bağlanamadı";
                    postInvalidate();
                    if (host != null) host.failed(vid);
                    return;
                }
                if (everConnected && fails >= 3) {
                    status = "Bağlantı koptu, noVNC'ye geçiliyor…";
                    postInvalidate();
                    if (host != null) host.failed(vid);
                    return;
                }
            } finally {
                try { Socket s = sock; if (s != null) s.close(); } catch (Throwable ignored) { }
            }
            try { Thread.sleep(everConnected ? 1000 : 700); } catch (InterruptedException e) { return; }
        }
    }

    private void connect() throws IOException {
        Socket s = new Socket();
        try { s.setReceiveBufferSize(1 << 22); } catch (Throwable ignored) { }
        s.connect(new InetSocketAddress(addr, port), 6000);
        s.setTcpNoDelay(true);
        sock = s;
        in = new DataInputStream(new BufferedInputStream(s.getInputStream(), 1 << 18));
        out = s.getOutputStream();

        byte[] ver = new byte[12];
        in.readFully(ver);
        writeOut("RFB 003.008\n".getBytes("US-ASCII"));

        int n = in.readUnsignedByte();
        if (n == 0) {
            int l = in.readInt();
            byte[] r = new byte[Math.max(0, Math.min(l, 512))];
            in.readFully(r);
            throw new IOException("sunucu reddetti");
        }
        byte[] types = new byte[n];
        in.readFully(types);
        boolean none = false;
        for (int i = 0; i < n; i++) if (types[i] == 1) none = true;
        if (!none) throw new IOException("kimlik doğrulama gerekli");
        writeOut(new byte[] { 1 });
        int res = in.readInt();
        if (res != 0) throw new IOException("güvenlik hatası");
        writeOut(new byte[] { 1 });   // ClientInit: paylaşımlı

        int w = in.readUnsignedShort();
        int h = in.readUnsignedShort();
        skipFully(16);                // sunucunun piksel biçimi (kendi biçimimizi isteyeceğiz)
        int nl = in.readInt();
        skipFully(nl);
        allocFb(w, h);

        // SetPixelFormat: 32 bpp, derinlik 24, little-endian, true color, R<<16 G<<8 B
        byte[] pf = new byte[20];
        pf[0] = 0;
        pf[4] = 32; pf[5] = 24; pf[6] = 0; pf[7] = 1;
        pf[8] = 0; pf[9] = (byte) 255; pf[10] = 0; pf[11] = (byte) 255; pf[12] = 0; pf[13] = (byte) 255;
        pf[14] = 16; pf[15] = 8; pf[16] = 0;
        writeOut(pf);

        // SetEncodings: CopyRect, Raw, ExtendedDesktopSize, DesktopSize, Fence, ContinuousUpdates
        cuSupported = false;
        cuActive = false;
        int[] enc = { 1, 0, -308, -223, -312, -313 };
        byte[] se = new byte[4 + enc.length * 4];
        se[0] = 2;
        se[2] = 0; se[3] = (byte) enc.length;
        for (int i = 0; i < enc.length; i++) put32(se, 4 + i * 4, enc[i]);
        writeOut(se);

        connected = true;
        needFull = true;
        status = "";
        postInvalidate();
        sendUpdateRequest(false);
        ui.removeCallbacks(resizeJob);
        ui.postDelayed(resizeJob, 600);
    }

    private void readLoop() throws IOException {
        while (!closed) {
            int type = in.readUnsignedByte();
            switch (type) {
                case 0: readUpdate(); break;
                case 1: {   // SetColourMapEntries
                    in.readUnsignedByte();
                    in.readUnsignedShort();
                    int cnt = in.readUnsignedShort();
                    skipFully(cnt * 6);
                    break;
                }
                case 2: break;   // Bell
                case 150:        // EndOfContinuousUpdates: sunucu destekliyor (ya da kapatmamızı onayladı)
                    cuSupported = true;
                    cuActive = false;
                    if (!paused) enableCU(true);
                    break;
                case 248: {      // Fence: sunucu gecikmeyi ölçer; isteği aynı veriyle geri gönder
                    skipFully(3);
                    int flags = in.readInt();
                    int len = in.readUnsignedByte();
                    byte[] pl = new byte[len];
                    in.readFully(pl);
                    if ((flags & 0x80000000) != 0) {
                        byte[] m = new byte[9 + len];
                        m[0] = (byte) 248;
                        put32(m, 4, flags & 3);   // BlockBefore | BlockAfter (sırayla işlediğimiz için ikisi de sağlanır)
                        m[8] = (byte) len;
                        System.arraycopy(pl, 0, m, 9, len);
                        send(m);
                    }
                    break;
                }
                case 3: {        // ServerCutText
                    skipFully(3);
                    int l = in.readInt();
                    skipFully(l);
                    break;
                }
                default: throw new IOException("bilinmeyen ileti " + type);
            }
        }
    }

    private void skipFully(int n) throws IOException {
        while (n > 0) {
            int k = in.skipBytes(n);
            if (k <= 0) { in.readByte(); k = 1; }
            n -= k;
        }
    }

    private void readUpdate() throws IOException {
        final long t0 = System.currentTimeMillis();
        in.readUnsignedByte();
        int nr = in.readUnsignedShort();
        // Boru hattı: sunucu sıradaki kareyi biz çözerken hazırlasın (çözme bitmesini beklemeyelim).
        // ContinuousUpdates açıksa istek hiç gerekmez: sunucu kendisi gönderir.
        final boolean pipelined = !paused && !cuActive;
        if (pipelined) sendUpdateRequest(true);
        int minX = Integer.MAX_VALUE, minY = Integer.MAX_VALUE, maxX = -1, maxY = -1;
        boolean resized = false;
        for (int i = 0; i < nr; i++) {
            int x = in.readUnsignedShort();
            int y = in.readUnsignedShort();
            int w = in.readUnsignedShort();
            int h = in.readUnsignedShort();
            int enc = in.readInt();
            if (enc == 0) {
                readRaw(x, y, w, h);
                blit(x, y, w, h);
                if (x < minX) minX = x;
                if (y < minY) minY = y;
                if (x + w > maxX) maxX = x + w;
                if (y + h > maxY) maxY = y + h;
            } else if (enc == 1) {
                int sx = in.readUnsignedShort();
                int sy = in.readUnsignedShort();
                copyRect(x, y, w, h, sx, sy);
                blit(x, y, w, h);
                if (x < minX) minX = x;
                if (y < minY) minY = y;
                if (x + w > maxX) maxX = x + w;
                if (y + h > maxY) maxY = y + h;
            } else if (enc == -223) {
                if (w != fbW || h != fbH) { allocFb(w, h); resized = true; }
            } else if (enc == -308) {
                int ns = in.readUnsignedByte();
                skipFully(3);
                for (int k = 0; k < ns; k++) {
                    int sid = in.readInt();
                    in.readUnsignedShort(); in.readUnsignedShort();
                    in.readUnsignedShort(); in.readUnsignedShort();
                    int fl = in.readInt();
                    if (k == 0) { screenId = sid; screenFlags = fl; haveScreen = true; }
                }
                if (y == 0 && (w != fbW || h != fbH)) { allocFb(w, h); resized = true; }
            } else if (enc == -224) {
                break;
            } else {
                throw new IOException("desteklenmeyen kodlama " + enc);
            }
        }
        if (resized) {
            needFull = true;
            synchronized (lock) {
                if (!glActive) fbToBitmapLocked(0, 0, fbW, fbH);
            }
        }
        dbgFrames++;
        {
            long nowT = System.currentTimeMillis();
            dbgDecMs = (int) (nowT - t0);
            dbgFpsN++;
            if (nowT - dbgFpsT >= 1000) { dbgFps = (int) (dbgFpsN * 1000L / (nowT - dbgFpsT)); dbgFpsN = 0; dbgFpsT = nowT; }
        }
        dbgRects += nr;
        dbgLastFrame = System.currentTimeMillis();
        if (glActive && gl != null) gl.requestDraw(); else postInvalidateOnAnimation();
        if (paused) { reqPending = true; }
        else if (resized) { needFull = true; sendUpdateRequest(false); if (cuActive) enableCU(true); }   // yeni alanı bildir
        else if (!pipelined && !cuActive) { sendUpdateRequest(true); }
    }

    /** Raw dikdörtgeni soketten doğrudan çerçeveye okur (eskiden: soket -> ara tampon -> int[] -> alfa döngüsü). */
    private void readRaw(int x, int y, int w, int h) throws IOException {
        if (w <= 0 || h <= 0) return;
        int rb = w * 4;
        byte[] p = fb;
        boolean okRect = p != null && x >= 0 && y >= 0 && x + w <= fbW && y + h <= fbH;
        if (!okRect) {
            if (rowBuf.length < rb) rowBuf = new byte[rb];
            for (int r = 0; r < h; r++) in.readFully(rowBuf, 0, rb);
            return;
        }
        int stride = fbW * 4;
        if (x == 0 && w == fbW) { in.readFully(p, y * stride, h * stride); return; }   // tam genişlik: tek okuma
        for (int r = 0, o = y * stride + x * 4; r < h; r++, o += stride) in.readFully(p, o, rb);
    }

    /** GPU yolunda değişen satırları işaretler; yedek yolda yalnız değişen dikdörtgeni bitmap'e yazar. */
    private void blit(int x, int y, int w, int h) {
        if (x < 0) { w += x; x = 0; }
        if (y < 0) { h += y; y = 0; }
        if (x + w > fbW) w = fbW - x;
        if (y + h > fbH) h = fbH - y;
        if (w <= 0 || h <= 0) return;
        if (glActive) { dirtyAdd(x, y, w, h); return; }   // GPU: yalnız değişen satır bantları dokuya yüklenir
        synchronized (lock) { fbToBitmapLocked(x, y, w, h); }
    }

    /** Yedek (Canvas) yol: ham B,G,R,X baytlarını bitmap'e opak ARGB olarak yazar. lock tutulurken çağrılır. */
    private void fbToBitmapLocked(int x, int y, int w, int h) {
        byte[] p = fb;
        if (bmp == null || p == null || bmp.isRecycled() || bmp.getWidth() != fbW || bmp.getHeight() != fbH) return;
        if (w <= 0 || h <= 0) return;
        int rows = Math.max(1, Math.min(h, (1 << 18) / w));
        if (bmpTmp.length < w * rows) bmpTmp = new int[w * rows];
        int[] t = bmpTmp;
        int stride = fbW * 4;
        for (int r0 = 0; r0 < h; r0 += rows) {
            int n = Math.min(rows, h - r0);
            for (int r = 0, k = 0; r < n; r++) {
                for (int i = 0, o = (y + r0 + r) * stride + x * 4; i < w; i++, o += 4) {
                    t[k++] = 0xFF000000 | ((p[o + 2] & 0xFF) << 16) | ((p[o + 1] & 0xFF) << 8) | (p[o] & 0xFF);
                }
            }
            bmp.setPixels(t, 0, w, x, y + r0, w, n);
        }
    }

    private void copyRect(int x, int y, int w, int h, int sx, int sy) {
        byte[] p = fb;
        if (p == null || x < 0 || y < 0 || sx < 0 || sy < 0
                || x + w > fbW || y + h > fbH || sx + w > fbW || sy + h > fbH) return;
        int stride = fbW * 4, n = w * 4;
        if (sy < y) {
            for (int r = h - 1; r >= 0; r--) System.arraycopy(p, (sy + r) * stride + sx * 4, p, (y + r) * stride + x * 4, n);
        } else {
            for (int r = 0; r < h; r++) System.arraycopy(p, (sy + r) * stride + sx * 4, p, (y + r) * stride + x * 4, n);
        }
    }

    private void allocFb(int w, int h) {
        if (w < 1 || h < 1 || (long) w * h > 16000000L) return;
        synchronized (lock) {
            byte[] np = new byte[w * h * 4];   // siyah; alfa GPU'da 1 yapılır, yedek yolda dönüşümde eklenir
            Bitmap nb = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            try { nb.setHasAlpha(false); } catch (Throwable ignored) { }
            Bitmap old = bmp;
            fb = np;
            bmp = nb;
            fbW = w;
            fbH = h;
            if (old != null) { try { old.recycle(); } catch (Throwable ignored) { } }
        }
    }

    // ------------------------------------------------------------ gönderme

    private void writeOut(byte[] b) throws IOException {
        synchronized (outLock) {
            OutputStream o = out;
            if (o == null) throw new IOException("kapalı");
            o.write(b);
            o.flush();
        }
    }

    /** Ağ yazması ana iş parçacığında yapılamaz (NetworkOnMainThreadException): tek iş parçacıklı sıraya koy. */
    private final java.util.concurrent.ExecutorService wr = java.util.concurrent.Executors.newSingleThreadExecutor();

    private void send(final byte[] b) {
        if (!connected || closed) return;
        dbgSent++;
        try {
            wr.execute(new Runnable() {
                @Override public void run() {
                    try { writeOut(b); } catch (Throwable t) {
                        dbgErr = "yazma: " + t;
                        try { Socket s = sock; if (s != null) s.close(); } catch (Throwable ignored) { }
                    }
                }
            });
        } catch (Throwable ignored) { }
    }

    private static void put16(byte[] b, int o, int v) { b[o] = (byte) (v >> 8); b[o + 1] = (byte) v; }
    private static void put32(byte[] b, int o, int v) {
        b[o] = (byte) (v >> 24); b[o + 1] = (byte) (v >> 16); b[o + 2] = (byte) (v >> 8); b[o + 3] = (byte) v;
    }

    /** ContinuousUpdates aç/kapat (tüm ekran). Açıkken sunucu değişiklikleri istek beklemeden gönderir; gidiş-dönüş gecikmesi kalkar. */
    private void enableCU(boolean on) {
        if (!connected || !cuSupported || fbW < 1) return;
        byte[] m = new byte[10];
        m[0] = (byte) 150;
        m[1] = (byte) (on ? 1 : 0);
        put16(m, 2, 0); put16(m, 4, 0); put16(m, 6, fbW); put16(m, 8, fbH);
        cuActive = on;
        send(m);
    }

    private void sendUpdateRequest(boolean incremental) {
        if (!connected || fbW < 1) return;
        boolean inc = incremental && !needFull;
        needFull = false;
        reqPending = false;
        byte[] m = new byte[10];
        m[0] = 3;
        m[1] = (byte) (inc ? 1 : 0);
        put16(m, 2, 0); put16(m, 4, 0); put16(m, 6, fbW); put16(m, 8, fbH);
        send(m);
    }

    // ---- Dokunma/tık güvenilirliği: önce imleci taşı, basışı en az MIN_PRESS_MS tut.
    private static final long MIN_PRESS_MS = 60;
    private final Object ptrLock = new Object();
    private int lastBtn;            // son gönderilen sol/orta/sağ düğme maskesi
    private long pressT;
    private Runnable pendingRel;
    private float pendRelX, pendRelY;

    // ---- İşaretçi olayı birleştirme: yazma kuyruğu doluysa art arda gelen hareketlerden yalnız en yenisi gider.
    // Gecikme eklenmez: yazıcı boşsa olay hemen gider; düğme/tekerlek değişimleri sırayla ve eksiksiz gider.
    private final Object movLock = new Object();
    private int lastRawMask = -1;
    private int pendMask, pendX, pendY;
    private boolean pendSet, movQueued;
    private final Runnable movTask = new Runnable() {
        @Override public void run() {
            byte[] m = new byte[6];
            synchronized (movLock) {
                movQueued = false;
                if (!pendSet) return;
                pendSet = false;
                m[0] = 5; m[1] = (byte) pendMask;
                put16(m, 2, pendX); put16(m, 4, pendY);
            }
            if (!connected || closed) return;
            try { writeOut(m); } catch (Throwable t) {
                dbgErr = "yazma: " + t;
                try { Socket s = sock; if (s != null) s.close(); } catch (Throwable ignored) { }
            }
        }
    };

    private void rawPointer(int mask, float ex, float ey) {
        int w = getWidth(), h = getHeight();
        if (w < 1 || h < 1 || fbW < 1) return;
        int x = (int) (ex * fbW / w), y = (int) (ey * fbH / h);
        if (x < 0) x = 0; if (y < 0) y = 0;
        if (x >= fbW) x = fbW - 1; if (y >= fbH) y = fbH - 1;
        synchronized (movLock) {
            if (mask == lastRawMask && (mask & 24) == 0) {
                // yalnız konum değişti: bekleyen hareketin üzerine yaz
                pendMask = mask; pendX = x; pendY = y; pendSet = true;
                if (!movQueued && connected && !closed) {
                    movQueued = true;
                    dbgSent++;
                    try { wr.execute(movTask); } catch (Throwable t) { movQueued = false; }
                }
                return;
            }
            pendSet = false;          // bu olay konumu da taşıdığı için eski bekleyen hareket gereksiz
            lastRawMask = mask;
        }
        byte[] m = new byte[6];
        m[0] = 5; m[1] = (byte) mask;
        put16(m, 2, x); put16(m, 4, y);
        send(m);
    }

    private void sendPointer(int mask, float ex, float ey) {
        synchronized (ptrLock) {
            // bekleyen (geciktirilmiş) bırakma varsa önce onu sırayla gönder
            if (pendingRel != null) {
                ui.removeCallbacks(pendingRel);
                pendingRel = null;
                rawPointer(lastBtn & ~7, pendRelX, pendRelY);
                lastBtn = 0;
            }
            int btn = mask & 7;
            if (btn != 0 && lastBtn == 0) {
                // yeni basış: önce imleci oraya taşı, sonra bas (sunucu konumu tanısın)
                rawPointer(mask & ~7, ex, ey);
                pressT = System.currentTimeMillis();
            } else if (btn == 0 && lastBtn != 0) {
                long el = System.currentTimeMillis() - pressT;
                if (el < MIN_PRESS_MS) {
                    // çok kısa dokunuş: bırakmayı geciktir, yoksa sunucu tıkı kaçırır
                    pendRelX = ex; pendRelY = ey;
                    final int keep = mask & ~7;
                    pendingRel = new Runnable() {
                        @Override public void run() {
                            synchronized (ptrLock) {
                                if (pendingRel != this) return;
                                pendingRel = null;
                                rawPointer(keep, pendRelX, pendRelY);
                                lastBtn = 0;
                            }
                        }
                    };
                    lastBtn = btn;   // henüz bırakılmadı say
                    ui.postDelayed(pendingRel, MIN_PRESS_MS - el);
                    return;
                }
            }
            lastBtn = btn;
            rawPointer(mask, ex, ey);
        }
    }

    private void sendKey(int keysym, boolean down) {
        if (keysym == 0) return;
        byte[] m = new byte[8];
        m[0] = 4; m[1] = (byte) (down ? 1 : 0);
        put32(m, 4, keysym);
        send(m);
    }

    private void tapKey(int keysym) { sendKey(keysym, true); sendKey(keysym, false); }

    private void sendResizeIfNeeded() {
        if (closed || !connected || !haveScreen) return;
        int vw = getWidth(), vh = getHeight();
        if (vw < 100 || vh < 100) return;
        int w = Math.max(320, Math.round(vw / dpr * scale / 2f) * 2);
        int h = Math.max(240, Math.round(vh / dpr * scale / 2f) * 2);
        if (w == fbW && h == fbH) return;
        byte[] m = new byte[24];
        m[0] = (byte) 251;
        put16(m, 2, w); put16(m, 4, h);
        m[6] = 1;
        put32(m, 8, screenId);
        put16(m, 12, 0); put16(m, 14, 0);
        put16(m, 16, w); put16(m, 18, h);
        put32(m, 20, screenFlags);
        dbgResize++;
        send(m);
    }

    @Override
    protected void onSizeChanged(int w, int h, int ow, int oh) {
        super.onSizeChanged(w, h, ow, oh);
        ui.removeCallbacks(resizeJob);
        ui.postDelayed(resizeJob, 500);
    }

    // ------------------------------------------------------------ GPU (OpenGL ES 2) çizim

    /** false yapılırsa eski Canvas/Bitmap yolu kullanılır. GPU başlatılamazsa zaten kendiliğinden o yola döner. */
    private static final boolean USE_GL = true;

    private volatile boolean glActive;
    private volatile boolean glFailed;
    private TextureView glView;
    private Gl gl;

    /*
     * Değişen bölgeler: tam genişlikte satır bantları [y0, y1). Tam genişlik sayesinde bant çerçevede bitişiktir ve
     * kopyalanmadan doğrudan dokuya yüklenir. Birbirinden uzak değişiklikler (ör. üstte saat, altta imleç) ayrı bant
     * kalır; eskiden tek bir birleşik kutu olduğu için neredeyse tüm ekran yeniden yükleniyordu.
     */
    private static final int MAX_BANDS = 16;
    private final Object dirtyLock = new Object();
    private final int[] dBand = new int[2 * MAX_BANDS];
    private int dBandN;
    private boolean dFull;

    private void dirtyAdd(int x, int y, int w, int h) {
        int a = y, b = y + h;
        synchronized (dirtyLock) {
            if (dFull) return;
            for (int i = 0; i < dBandN; ) {
                int s0 = dBand[2 * i], s1 = dBand[2 * i + 1];
                if (a <= s1 + 8 && b >= s0 - 8) {   // çakışıyor ya da çok yakın: birleştir, baştan tara
                    if (s0 < a) a = s0;
                    if (s1 > b) b = s1;
                    dBandN--;
                    dBand[2 * i] = dBand[2 * dBandN];
                    dBand[2 * i + 1] = dBand[2 * dBandN + 1];
                    i = 0;
                } else {
                    i++;
                }
            }
            if (dBandN == MAX_BANDS) {   // çok parça: hepsini tek banda topla
                for (int i = 0; i < dBandN; i++) {
                    if (dBand[2 * i] < a) a = dBand[2 * i];
                    if (dBand[2 * i + 1] > b) b = dBand[2 * i + 1];
                }
                dBandN = 0;
            }
            dBand[2 * dBandN] = a;
            dBand[2 * dBandN + 1] = b;
            dBandN++;
        }
    }

    private void dirtyFull() { synchronized (dirtyLock) { dFull = true; } }

    /** GPU yolundan çıkınca (yüzey yok / hata) bitmap'i güncel piksellerle eşitler. */
    private void resyncBitmap() {
        synchronized (lock) {
            fbToBitmapLocked(0, 0, fbW, fbH);
        }
        postInvalidate();
    }

    private final class Gl implements TextureView.SurfaceTextureListener {
        private HandlerThread th;
        private Handler hnd;
        private EGLDisplay dpy = EGL14.EGL_NO_DISPLAY;
        private EGLContext ctx = EGL14.EGL_NO_CONTEXT;
        private EGLSurface surf = EGL14.EGL_NO_SURFACE;
        private int prog, tex, aPos, aTex, uTex, maxTex;
        private int texW, texH;
        private final int[] bands = new int[2 * MAX_BANDS];
        private FloatBuffer quad;
        private boolean up;
        private final AtomicBoolean pending = new AtomicBoolean();
        private final Runnable drawRun = new Runnable() { @Override public void run() { draw(); } };

        private synchronized void ensureThread() {
            if (th == null) {
                th = new HandlerThread("vnc-gl-" + vid);
                th.start();
                hnd = new Handler(th.getLooper());
            }
        }

        void requestDraw() {
            Handler hh = hnd;
            if (!glActive || hh == null) return;
            if (pending.compareAndSet(false, true)) {
                try { hh.post(drawRun); } catch (Throwable t) { pending.set(false); }
            }
        }

        void shutdown() {
            glActive = false;
            final Handler hh = hnd;
            HandlerThread t = th;
            if (hh != null) {
                try { hh.post(new Runnable() { @Override public void run() { releaseGl(); } }); } catch (Throwable ignored) { }
            }
            if (t != null) { try { t.quitSafely(); } catch (Throwable ignored) { } }
        }

        @Override public void onSurfaceTextureAvailable(final SurfaceTexture st, int w, int h) {
            if (glFailed || closed) return;
            ensureThread();
            hnd.post(new Runnable() { @Override public void run() { initGl(st); } });
        }

        @Override public void onSurfaceTextureSizeChanged(SurfaceTexture st, int w, int h) { requestDraw(); }

        @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture st) {
            glActive = false;
            Handler hh = hnd;
            if (hh != null) {
                final CountDownLatch l = new CountDownLatch(1);
                try {
                    hh.post(new Runnable() { @Override public void run() { try { releaseGl(); } finally { l.countDown(); } } });
                    l.await(500, TimeUnit.MILLISECONDS);
                } catch (Throwable ignored) { }
            }
            if (!closed) resyncBitmap();
            return true;
        }

        @Override public void onSurfaceTextureUpdated(SurfaceTexture st) { }

        private int compile(int type, String src) {
            int sh = GLES20.glCreateShader(type);
            GLES20.glShaderSource(sh, src);
            GLES20.glCompileShader(sh);
            int[] ok = new int[1];
            GLES20.glGetShaderiv(sh, GLES20.GL_COMPILE_STATUS, ok, 0);
            if (ok[0] == 0) {
                String log = GLES20.glGetShaderInfoLog(sh);
                GLES20.glDeleteShader(sh);
                throw new RuntimeException("shader: " + log);
            }
            return sh;
        }

        private void initGl(SurfaceTexture st) {
            try {
                dpy = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
                int[] ver = new int[2];
                if (dpy == EGL14.EGL_NO_DISPLAY || !EGL14.eglInitialize(dpy, ver, 0, ver, 1)) throw new RuntimeException("egl init");
                int[] ca = { EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                        EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
                        EGL14.EGL_NONE };
                EGLConfig[] cfgs = new EGLConfig[1];
                int[] n = new int[1];
                if (!EGL14.eglChooseConfig(dpy, ca, 0, cfgs, 0, 1, n, 0) || n[0] < 1) throw new RuntimeException("egl config");
                int[] xa = { EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE };
                ctx = EGL14.eglCreateContext(dpy, cfgs[0], EGL14.EGL_NO_CONTEXT, xa, 0);
                surf = EGL14.eglCreateWindowSurface(dpy, cfgs[0], st, new int[] { EGL14.EGL_NONE }, 0);
                if (ctx == EGL14.EGL_NO_CONTEXT || surf == EGL14.EGL_NO_SURFACE) throw new RuntimeException("egl surface");
                if (!EGL14.eglMakeCurrent(dpy, surf, surf, ctx)) throw new RuntimeException("egl current");
                try { EGL14.eglSwapInterval(dpy, 0); } catch (Throwable ignored) { }   // vsync bekleme: kare hazır olunca hemen göster

                int vs = compile(GLES20.GL_VERTEX_SHADER,
                        "attribute vec2 aPos;attribute vec2 aTex;varying vec2 vTex;"
                        + "void main(){gl_Position=vec4(aPos,0.0,1.0);vTex=aTex;}");
                // sunucudan B,G,R,X bayt sırası gelir; doku RGBA okunur, burada kırmızı/mavi yer değiştirir
                int fs = compile(GLES20.GL_FRAGMENT_SHADER,
                        "precision mediump float;varying vec2 vTex;uniform sampler2D uTex;"
                        + "void main(){vec4 c=texture2D(uTex,vTex);gl_FragColor=vec4(c.b,c.g,c.r,1.0);}");
                prog = GLES20.glCreateProgram();
                GLES20.glAttachShader(prog, vs);
                GLES20.glAttachShader(prog, fs);
                GLES20.glLinkProgram(prog);
                int[] ok = new int[1];
                GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, ok, 0);
                if (ok[0] == 0) throw new RuntimeException("program: " + GLES20.glGetProgramInfoLog(prog));
                aPos = GLES20.glGetAttribLocation(prog, "aPos");
                aTex = GLES20.glGetAttribLocation(prog, "aTex");
                uTex = GLES20.glGetUniformLocation(prog, "uTex");

                int[] t = new int[1];
                GLES20.glGenTextures(1, t, 0);
                tex = t[0];
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex);
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
                int[] mt = new int[1];
                GLES20.glGetIntegerv(GLES20.GL_MAX_TEXTURE_SIZE, mt, 0);
                maxTex = mt[0];

                float[] qv = { -1f, 1f, 0f, 0f,   -1f, -1f, 0f, 1f,   1f, 1f, 1f, 0f,   1f, -1f, 1f, 1f };
                quad = ByteBuffer.allocateDirect(qv.length * 4).order(ByteOrder.nativeOrder()).asFloatBuffer();
                quad.put(qv);
                quad.position(0);

                texW = 0; texH = 0;
                up = true;
                dirtyFull();
                glActive = true;
                draw();
            } catch (Throwable t) {
                dbgErr = "gl: " + t;
                glFailed = true;
                glActive = false;
                releaseGl();
                ui.post(new Runnable() {
                    @Override public void run() {
                        if (glView != null) glView.setVisibility(View.GONE);
                        resyncBitmap();
                    }
                });
            }
        }

        private void releaseGl() {
            up = false;
            if (dpy != EGL14.EGL_NO_DISPLAY) {
                try {
                    EGL14.eglMakeCurrent(dpy, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT);
                    if (surf != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(dpy, surf);
                    if (ctx != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(dpy, ctx);
                    EGL14.eglTerminate(dpy);
                } catch (Throwable ignored) { }
            }
            dpy = EGL14.EGL_NO_DISPLAY;
            ctx = EGL14.EGL_NO_CONTEXT;
            surf = EGL14.EGL_NO_SURFACE;
            texW = 0; texH = 0;
        }

        private void draw() {
            pending.set(false);
            if (!up) return;
            final long g0 = System.nanoTime();
            int upBytes = 0;
            try {
                int nb;
                boolean full;
                synchronized (dirtyLock) {
                    full = dFull;
                    dFull = false;
                    nb = dBandN;
                    System.arraycopy(dBand, 0, bands, 0, 2 * nb);
                    dBandN = 0;
                }
                GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex);
                synchronized (lock) {   // çerçeve yeniden ayrılırken yükleme yapılmasın
                    byte[] p = fb;
                    int W = fbW, H = fbH;
                    if (p == null || W < 1 || H < 1 || p.length < W * H * 4) return;
                    if (W != texW || H != texH) {
                        if (W > maxTex || H > maxTex) throw new RuntimeException("doku çok büyük " + W + "x" + H);
                        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, W, H, 0,
                                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null);
                        texW = W; texH = H;
                        full = true;
                    }
                    if (full) { nb = 1; bands[0] = 0; bands[1] = H; }
                    // Çerçeve dizisi doğrudan verilir (Android GLES bağlaması diziyi sabitleyip okur): kopya yok.
                    ByteBuffer bb = ByteBuffer.wrap(p);
                    int stride = W * 4;
                    for (int i = 0; i < nb; i++) {
                        int y0 = Math.max(0, bands[2 * i]), y1 = Math.min(H, bands[2 * i + 1]);
                        if (y1 <= y0) continue;
                        bb.position(y0 * stride);
                        upBytes += (y1 - y0) * stride;
                        GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, y0, W, y1 - y0,
                                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, bb);
                    }
                }
                int[] sz = new int[1];
                EGL14.eglQuerySurface(dpy, surf, EGL14.EGL_WIDTH, sz, 0);
                int sw = sz[0];
                EGL14.eglQuerySurface(dpy, surf, EGL14.EGL_HEIGHT, sz, 0);
                int sh = sz[0];
                if (sw < 1 || sh < 1) return;
                GLES20.glViewport(0, 0, sw, sh);
                GLES20.glUseProgram(prog);
                GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
                GLES20.glUniform1i(uTex, 0);
                quad.position(0);
                GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, 16, quad);
                GLES20.glEnableVertexAttribArray(aPos);
                quad.position(2);
                GLES20.glVertexAttribPointer(aTex, 2, GLES20.GL_FLOAT, false, 16, quad);
                GLES20.glEnableVertexAttribArray(aTex);
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
                EGL14.eglSwapBuffers(dpy, surf);
                if (DEBUG) {
                    long nowG = System.currentTimeMillis();
                    dbgGlMs = (int) ((System.nanoTime() - g0) / 1000000L);
                    dbgGlKb = upBytes / 1024;
                    dbgGlN++;
                    if (nowG - dbgGlT >= 1000) { dbgGlFps = (int) (dbgGlN * 1000L / (nowG - dbgGlT)); dbgGlN = 0; dbgGlT = nowG; }
                }
            } catch (Throwable t) {
                dbgErr = "gl çizim: " + t;
                glFailed = true;
                glActive = false;
                releaseGl();
                ui.post(new Runnable() {
                    @Override public void run() {
                        if (glView != null) glView.setVisibility(View.GONE);
                        resyncBitmap();
                    }
                });
            }
        }
    }

    // ------------------------------------------------------------ çizim

    @Override
    protected void dispatchDraw(Canvas c) {
        if (!glActive) synchronized (lock) {
            if (bmp != null && !bmp.isRecycled()) {
                srcR.set(0, 0, bmp.getWidth(), bmp.getHeight());
                dstR.set(0, 0, getWidth(), getHeight());
                c.drawBitmap(bmp, srcR, dstR, paint);
            }
        }
        super.dispatchDraw(c);   // GPU yüzeyi (TextureView); altındaki bitmap yalnız yedek yol
        if (status.length() > 0) {
            c.drawText(status, 16 * density, getHeight() / 2f, textPaint);
        }
        if (DEBUG) {
            long now = System.currentTimeMillis();
            long age = dbgLastFrame == 0 ? -1 : (now - dbgLastFrame) / 1000;
            String l1 = "bağ:" + (connected ? "EVET" : "HAYIR") + " duraklı:" + paused + " kare:" + dbgFrames
                    + " dikdörtgen:" + dbgRects + " sonKare:" + (age < 0 ? "yok" : age + "sn") + " fps:" + dbgFps + " guncelleme:" + dbgDecMs + "ms";
            String l2 = "dokunma:" + dbgTouch + " gönderilen:" + dbgSent + " boyutİst:" + dbgResize
                    + " yenidenBağ:" + dbgReconn + " fb:" + fbW + "x" + fbH + " görünüm:" + getWidth() + "x" + getHeight()
                    + " dpr:" + dpr + " s:" + scale;
            String l3 = "çizim:" + (glActive ? "GPU" : (glFailed ? "Canvas(GPU hata)" : "Canvas")) + " gpuFps:" + dbgGlFps + " gpuÇizim:" + dbgGlMs + "ms yüklenen:" + dbgGlKb + "KB"
                    + " sürekliGünc:" + (cuActive ? "AÇIK" : (cuSupported ? "kapalı" : "yok"));
            String l4 = "hata:" + dbgErr + " sn:" + ((now - dbgStart) / 1000);
            float th = dbgPaint.getTextSize() + 3 * density;
            float bw = Math.max(Math.max(dbgPaint.measureText(l1), dbgPaint.measureText(l2)),
                    Math.max(dbgPaint.measureText(l3), dbgPaint.measureText(l4))) + 8 * density;
            c.drawRect(0, 0, Math.min(bw, getWidth()), th * 4 + 6 * density, dbgBg);
            c.drawText(l1, 4 * density, th, dbgPaint);
            c.drawText(l2, 4 * density, th * 2, dbgPaint);
            c.drawText(l3, 4 * density, th * 3, dbgPaint);
            c.drawText(l4, 4 * density, th * 4, dbgPaint);
        }
        // klavye düğmesi (sağ alt)
        float r = 18 * density;
        float cx = getWidth() - r - 8 * density, cy = getHeight() - r - 8 * density;
        c.drawCircle(cx, cy, r, btnPaint);
        float ts = textPaint.getTextSize();
        textPaint.setTextSize(18 * density);
        textPaint.setTextAlign(Paint.Align.CENTER);
        c.drawText("⌨", cx, cy + 6 * density, textPaint);
        textPaint.setTextAlign(Paint.Align.LEFT);
        textPaint.setTextSize(ts);
    }

    // ------------------------------------------------------------ dokunma / fare

    private boolean inKbButton(float x, float y) {
        float r = 22 * density;
        float cx = getWidth() - 18 * density - 8 * density, cy = getHeight() - 18 * density - 8 * density;
        return Math.abs(x - cx) < r && Math.abs(y - cy) < r;
    }

    private void toggleIme() {
        InputMethodManager imm = (InputMethodManager) getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        if (imm == null) return;
        requestFocus();
        if (imeShown) { imm.hideSoftInputFromWindow(getWindowToken(), 0); imeShown = false; }
        else { imm.showSoftInput(this, InputMethodManager.SHOW_FORCED); imeShown = true; }
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent ev) {
        if (ev.getActionMasked() == MotionEvent.ACTION_DOWN) {
            Rect c = getClipBounds();
            if (c != null && !c.contains((int) ev.getX(), (int) ev.getY())) return false;
        }
        return super.dispatchTouchEvent(ev);
    }

    @Override
    public boolean onTouchEvent(MotionEvent ev) {
        int act = ev.getActionMasked();
        dbgTouch++;
        boolean mouse = ev.getToolType(0) == MotionEvent.TOOL_TYPE_MOUSE;
        if (act == MotionEvent.ACTION_DOWN) {
            requestFocus();
            if (!mouse && inKbButton(ev.getX(), ev.getY())) { toggleIme(); return true; }
        }
        if (mouse) {
            int bs = ev.getButtonState();
            int mask = 0;
            if ((bs & MotionEvent.BUTTON_PRIMARY) != 0) mask |= 1;
            if ((bs & MotionEvent.BUTTON_TERTIARY) != 0) mask |= 2;
            if ((bs & MotionEvent.BUTTON_SECONDARY) != 0) mask |= 4;
            if (act == MotionEvent.ACTION_UP || act == MotionEvent.ACTION_CANCEL) mask = 0;
            btnMask = mask;
            sendPointer(mask, ev.getX(), ev.getY());
            return true;
        }
        int n = ev.getPointerCount();
        switch (act) {
            case MotionEvent.ACTION_DOWN:
                twoFinger = false; scrolled = false; scrollAcc = 0;
                downX = ev.getX(); downY = ev.getY(); moved = false;
                btnMask = 1;
                sendPointer(1, downX, downY);
                break;
            case MotionEvent.ACTION_POINTER_DOWN:
                if (n == 2) {
                    if (btnMask != 0) { sendPointer(0, ev.getX(0), ev.getY(0)); btnMask = 0; }
                    twoFinger = true; scrolled = false; scrollAcc = 0;
                    lastAvgY = (ev.getY(0) + ev.getY(1)) / 2f;
                    twoDownT = ev.getEventTime();
                    twoX = ev.getX(0); twoY = ev.getY(0);
                } else if (n == 3) {
                    toggleIme();
                }
                break;
            case MotionEvent.ACTION_MOVE:
                if (twoFinger && n >= 2) {
                    float avg = (ev.getY(0) + ev.getY(1)) / 2f;
                    scrollAcc += avg - lastAvgY;
                    lastAvgY = avg;
                    float step = 36 * density;
                    while (Math.abs(scrollAcc) >= step) {
                        int btn = scrollAcc > 0 ? 8 : 16;   // parmak aşağı = yukarı kaydır (4), yukarı = aşağı (5)
                        sendPointer(btn, twoX, twoY);
                        sendPointer(0, twoX, twoY);
                        scrollAcc += scrollAcc > 0 ? -step : step;
                        scrolled = true;
                    }
                } else if (!twoFinger) {
                    if (!moved) {
                        // parmak titremesi tıkı sürükleme yapmasın: eşik aşılana kadar yerinde tut
                        float dx = ev.getX() - downX, dy = ev.getY() - downY;
                        float slop = 10 * density;
                        if (dx * dx + dy * dy < slop * slop) break;
                        moved = true;
                    }
                    sendPointer(btnMask, ev.getX(), ev.getY());
                }
                break;
            case MotionEvent.ACTION_POINTER_UP:
                if (twoFinger && !scrolled && ev.getEventTime() - twoDownT < 300) {
                    sendPointer(4, twoX, twoY);     // iki parmak dokunuş = sağ tık
                    sendPointer(0, twoX, twoY);
                }
                break;
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                if (!twoFinger && btnMask != 0) {
                    if (moved) sendPointer(0, ev.getX(), ev.getY());
                    else sendPointer(0, downX, downY);   // tık: bırakma basış noktasında
                }
                btnMask = 0;
                twoFinger = false;
                break;
            default: break;
        }
        return true;
    }

    @Override
    public boolean onGenericMotionEvent(MotionEvent ev) {
        int act = ev.getActionMasked();
        if (act == MotionEvent.ACTION_HOVER_MOVE) {
            sendPointer(btnMask, ev.getX(), ev.getY());
            return true;
        }
        if (act == MotionEvent.ACTION_SCROLL) {
            float v = ev.getAxisValue(MotionEvent.AXIS_VSCROLL);
            int btn = v > 0 ? 8 : 16;
            int times = Math.max(1, Math.round(Math.abs(v)));
            for (int i = 0; i < times; i++) {
                sendPointer(btnMask | btn, ev.getX(), ev.getY());
                sendPointer(btnMask, ev.getX(), ev.getY());
            }
            return true;
        }
        return super.onGenericMotionEvent(ev);
    }


    /** Sanal fare (touchpad) modunda ana sayfadan gelen fare olayları. action: 0 bas, 1 bırak, 2 basılıyken hareket, 7 hover, 8 tekerlek. */
    public void injectMouse(int action, float lx, float ly, int buttons, float vs) {
        dbgTouch++;
        int mask = 0;
        if ((buttons & MotionEvent.BUTTON_PRIMARY) != 0) mask |= 1;
        if ((buttons & MotionEvent.BUTTON_TERTIARY) != 0) mask |= 2;
        if ((buttons & MotionEvent.BUTTON_SECONDARY) != 0) mask |= 4;
        switch (action) {
            case 0:
                requestFocus();
                if (inKbButton(lx, ly)) { kbDown = true; toggleIme(); break; }
                kbDown = false;
                btnMask = mask;
                sendPointer(mask, lx, ly);
                break;
            case 2:
                if (kbDown) break;
                btnMask = mask;
                sendPointer(mask, lx, ly);
                break;
            case 1:
                if (kbDown) { kbDown = false; break; }
                btnMask = 0;
                sendPointer(0, lx, ly);
                break;
            case 7:
                sendPointer(btnMask, lx, ly);
                break;
            case 8: {
                int btn = vs > 0 ? 8 : 16;
                sendPointer(btnMask | btn, lx, ly);
                sendPointer(btnMask, lx, ly);
                break;
            }
            default: break;
        }
    }

    // ------------------------------------------------------------ klavye

    private static int cpToKeysym(int cp) {
        if (cp < 0x20 || cp == 0x7F) return 0;
        if (cp < 0x100) return cp;
        return 0x01000000 | cp;
    }

    private static int specialKeysym(int kc) {
        switch (kc) {
            case KeyEvent.KEYCODE_DEL: return 0xFF08;
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_NUMPAD_ENTER: return 0xFF0D;
            case KeyEvent.KEYCODE_TAB: return 0xFF09;
            case KeyEvent.KEYCODE_ESCAPE: return 0xFF1B;
            case KeyEvent.KEYCODE_DPAD_LEFT: return 0xFF51;
            case KeyEvent.KEYCODE_DPAD_UP: return 0xFF52;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 0xFF53;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 0xFF54;
            case KeyEvent.KEYCODE_MOVE_HOME: return 0xFF50;
            case KeyEvent.KEYCODE_MOVE_END: return 0xFF57;
            case KeyEvent.KEYCODE_PAGE_UP: return 0xFF55;
            case KeyEvent.KEYCODE_PAGE_DOWN: return 0xFF56;
            case KeyEvent.KEYCODE_INSERT: return 0xFF63;
            case KeyEvent.KEYCODE_FORWARD_DEL: return 0xFFFF;
            case KeyEvent.KEYCODE_SHIFT_LEFT: return 0xFFE1;
            case KeyEvent.KEYCODE_SHIFT_RIGHT: return 0xFFE2;
            case KeyEvent.KEYCODE_CTRL_LEFT: return 0xFFE3;
            case KeyEvent.KEYCODE_CTRL_RIGHT: return 0xFFE4;
            case KeyEvent.KEYCODE_ALT_LEFT: return 0xFFE9;
            case KeyEvent.KEYCODE_ALT_RIGHT: return 0xFFEA;
            case KeyEvent.KEYCODE_META_LEFT: return 0xFFEB;
            case KeyEvent.KEYCODE_META_RIGHT: return 0xFFEC;
            case KeyEvent.KEYCODE_CAPS_LOCK: return 0xFFE5;
            default: break;
        }
        if (kc >= KeyEvent.KEYCODE_F1 && kc <= KeyEvent.KEYCODE_F12) return 0xFFBE + (kc - KeyEvent.KEYCODE_F1);
        return 0;
    }

    private static int keysymFor(KeyEvent e) {
        int sp = specialKeysym(e.getKeyCode());
        if (sp != 0) return sp;
        int meta = e.getMetaState() & ~(KeyEvent.META_CTRL_MASK | KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON
                | KeyEvent.META_CTRL_RIGHT_ON | KeyEvent.META_ALT_MASK | KeyEvent.META_ALT_ON
                | KeyEvent.META_ALT_LEFT_ON | KeyEvent.META_ALT_RIGHT_ON | KeyEvent.META_META_MASK);
        int u = e.getUnicodeChar(meta);
        if ((u & KeyCharacterMap.COMBINING_ACCENT) != 0) return 0;
        return cpToKeysym(u);
    }

    private static boolean isSystemKey(int kc) {
        return kc == KeyEvent.KEYCODE_BACK || kc == KeyEvent.KEYCODE_HOME || kc == KeyEvent.KEYCODE_APP_SWITCH
                || kc == KeyEvent.KEYCODE_VOLUME_UP || kc == KeyEvent.KEYCODE_VOLUME_DOWN
                || kc == KeyEvent.KEYCODE_VOLUME_MUTE || kc == KeyEvent.KEYCODE_POWER
                || kc == KeyEvent.KEYCODE_MENU || kc == KeyEvent.KEYCODE_SEARCH;
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (isSystemKey(keyCode)) return super.onKeyDown(keyCode, event);
        int ks = keysymFor(event);
        if (ks == 0) return super.onKeyDown(keyCode, event);
        keyMap.put(keyCode, ks);
        sendKey(ks, true);
        return true;
    }

    @Override
    public boolean onKeyUp(int keyCode, KeyEvent event) {
        if (isSystemKey(keyCode)) return super.onKeyUp(keyCode, event);
        int ks = keyMap.get(keyCode, 0);
        if (ks == 0) return super.onKeyUp(keyCode, event);
        keyMap.delete(keyCode);
        sendKey(ks, false);
        return true;
    }

    @Override
    public boolean onCheckIsTextEditor() { return true; }

    @Override
    public InputConnection onCreateInputConnection(EditorInfo ei) {
        ei.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
        ei.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_ACTION_NONE;
        composing = "";
        return new BaseInputConnection(this, false) {
            private void typeDiff(String text) {
                int p = 0;
                int m = Math.min(composing.length(), text.length());
                while (p < m && composing.charAt(p) == text.charAt(p)) p++;
                for (int i = composing.length(); i > p; i--) tapKey(0xFF08);
                for (int i = p; i < text.length(); ) {
                    int cp = text.codePointAt(i);
                    i += Character.charCount(cp);
                    if (cp == '\n') tapKey(0xFF0D); else tapKey(cpToKeysym(cp));
                }
            }
            @Override public boolean setComposingText(CharSequence text, int newCursorPosition) {
                String t = text == null ? "" : text.toString();
                typeDiff(t);
                composing = t;
                return true;
            }
            @Override public boolean commitText(CharSequence text, int newCursorPosition) {
                String t = text == null ? "" : text.toString();
                typeDiff(t);
                composing = "";
                return true;
            }
            @Override public boolean finishComposingText() { composing = ""; return true; }
            @Override public boolean deleteSurroundingText(int before, int after) {
                for (int i = 0; i < before; i++) tapKey(0xFF08);
                for (int i = 0; i < after; i++) tapKey(0xFFFF);
                return true;
            }
            @Override public boolean sendKeyEvent(KeyEvent event) {
                int kc = event.getKeyCode();
                if (event.getAction() == KeyEvent.ACTION_DOWN) return VncView.this.onKeyDown(kc, event);
                if (event.getAction() == KeyEvent.ACTION_UP) return VncView.this.onKeyUp(kc, event);
                return true;
            }
            @Override public boolean performEditorAction(int actionCode) { tapKey(0xFF0D); return true; }
        };
    }
}
