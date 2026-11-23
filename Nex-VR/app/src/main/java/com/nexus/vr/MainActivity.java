package com.nexus.vr;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.util.Base64;
import android.util.Log;
import android.webkit.ConsoleMessage;
import android.webkit.WebResourceError;
import android.widget.FrameLayout;
import android.graphics.drawable.Drawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.SslErrorHandler;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebMessage;
import android.webkit.WebMessagePort;
import android.content.res.Configuration;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.os.Looper;
import androidx.camera.view.PreviewView;
import android.net.http.SslError;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

public class MainActivity extends Activity implements SensorEventListener {
    static final String HOST = "appassets.androidplatform.net";
    static final String ORIGIN = "https://" + HOST;
    static final Pattern PKG = Pattern.compile("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$");

    WebView web;
    FrameLayout root;
    final Map<String, WebView> childViews = new ConcurrentHashMap<>();
    /* Sanal (görünmez) WebView durumu: boyut, iç içe alt görünüm yerleşimi/kırpması, dokunma hedefi, anlık görüntü arabelleği */
    static class VS {
        boolean virt, vis, busy; int x, y, w, h, seq, cssW; int lastHash; long downTime; String tgKey;
        final Rect clip = new Rect(); Bitmap bmp;
    }
    final Map<String, VS> vstate = new ConcurrentHashMap<>();
    final Map<String, byte[]> snapData = new ConcurrentHashMap<>();
    final java.util.concurrent.ExecutorService snapExec = java.util.concurrent.Executors.newSingleThreadExecutor();
    /* Stage 32 — App Store: sitenin ikonunu (apple-touch-icon / favicon) yerelden indirir, 128x128 PNG data: URI olarak JS'e verir. */
    final java.util.concurrent.ExecutorService iconExec = java.util.concurrent.Executors.newFixedThreadPool(2);
    static final Pattern LINK_TAG = Pattern.compile("<link\\b[^>]*>", Pattern.CASE_INSENSITIVE);
    static final Pattern ATTR_REL = Pattern.compile("\\brel\\s*=\\s*[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE);
    static final Pattern ATTR_HREF = Pattern.compile("\\bhref\\s*=\\s*[\"']([^\"']*)[\"']", Pattern.CASE_INSENSITIVE);
    static final Pattern ATTR_SIZES = Pattern.compile("\\bsizes\\s*=\\s*[\"'](\\d+)x\\d+", Pattern.CASE_INSENSITIVE);

    static byte[] httpBytes(String addr, int max, boolean text) throws IOException {
        URL u = new URL(addr);
        checkTarget(u);
        HttpURLConnection c = (HttpURLConnection) u.openConnection();
        c.setConnectTimeout(6000);
        c.setReadTimeout(8000);
        c.setInstanceFollowRedirects(true);
        c.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36");
        c.setRequestProperty("Accept", text ? "text/html,*/*;q=0.5" : "image/*,*/*;q=0.5");
        try {
            if (c.getResponseCode() != 200) throw new IOException("http " + c.getResponseCode());
            URL fin = c.getURL();
            if (fin != null) checkTarget(fin);
            InputStream in = c.getInputStream();
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                o.write(buf, 0, n);
                if (o.size() > max) { if (text) break; throw new IOException("big"); }
            }
            in.close();
            return o.toByteArray();
        } finally {
            c.disconnect();
        }
    }

    /* Adaylar: sayfadaki apple-touch-icon ve icon bağlantıları (büyükten küçüğe), sonra /favicon.ico, en sonda Google ikon servisi. */
    static List<String> iconCandidates(String pageUrl) {
        List<String> out = new ArrayList<>();
        List<String[]> found = new ArrayList<>();
        try {
            URL page = new URL(pageUrl);
            String origin = page.getProtocol() + "://" + page.getHost() + (page.getPort() > 0 ? ":" + page.getPort() : "");
            try {
                String html = new String(httpBytes(pageUrl, 300_000, true), StandardCharsets.UTF_8);
                java.util.regex.Matcher m = LINK_TAG.matcher(html);
                while (m.find()) {
                    String tag = m.group();
                    java.util.regex.Matcher r = ATTR_REL.matcher(tag), h = ATTR_HREF.matcher(tag), z = ATTR_SIZES.matcher(tag);
                    if (!r.find() || !h.find()) continue;
                    String rel = r.group(1).toLowerCase();
                    if (!rel.contains("icon") || rel.contains("mask-icon")) continue;
                    int size = z.find() ? Integer.parseInt(z.group(1)) : 0;
                    int score = (rel.contains("apple-touch") ? 1000 : 0) + Math.min(size, 512);
                    found.add(new String[]{String.valueOf(score), new URL(page, h.group(1).trim()).toString()});
                }
            } catch (Exception ignored) { }
            java.util.Collections.sort(found, (a, b) -> Integer.parseInt(b[0]) - Integer.parseInt(a[0]));
            for (String[] f : found) if (!out.contains(f[1]) && f[1].startsWith("http")) out.add(f[1]);
            out.add(origin + "/favicon.ico");
            out.add("https://www.google.com/s2/favicons?sz=128&domain=" + page.getHost());
        } catch (Exception ignored) { }
        return out;
    }

    static String iconDataUri(byte[] raw) {
        try {
            Bitmap b = android.graphics.BitmapFactory.decodeByteArray(raw, 0, raw.length);
            if (b == null || b.getWidth() < 16 || b.getHeight() < 16) return null;
            Bitmap sq = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(sq);
            android.graphics.Paint p = new android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG | android.graphics.Paint.ANTI_ALIAS_FLAG);
            float k = Math.min(128f / b.getWidth(), 128f / b.getHeight());
            float w = b.getWidth() * k, h = b.getHeight() * k;
            cv.drawBitmap(b, null, new android.graphics.RectF((128 - w) / 2, (128 - h) / 2, (128 + w) / 2, (128 + h) / 2), p);
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            sq.compress(Bitmap.CompressFormat.PNG, 100, o);
            return "data:image/png;base64," + Base64.encodeToString(o.toByteArray(), Base64.NO_WRAP);
        } catch (Throwable e) { return null; }
    }

    VS vs(String id) { VS s = vstate.get(id); if (s == null) { s = new VS(); vstate.put(id, s); } return s; }

    /* Stage 27 — GPU tarayıcı: yalnızca 'nexus-browser' için, ana ekrana eklenmeyen VirtualDisplay içinde çalışan WebView. */
    final Map<String, GpuPage> gpuPages = new ConcurrentHashMap<>();
    final Set<String> gpuIds = ConcurrentHashMap.newKeySet();
    final Map<String, Integer> gpuSeq = new ConcurrentHashMap<>();
    final Map<String, Integer> gpuSent = new ConcurrentHashMap<>();
    final java.util.concurrent.atomic.AtomicBoolean gpuNotify = new java.util.concurrent.atomic.AtomicBoolean();
    volatile boolean gpuOn = true;

    /* Stage 56 — Shizuku: Android uygulamalarını VR penceresindeki sanal ekranda açma */
    ShizukuLink shz;
    final Map<String, AppMirror> mirrors = new ConcurrentHashMap<>();
    /** Stage 64: "sınırsız" seçiliyken bile mantıklı bir üst sınır (her pencere sanal ekran + JPEG hattı). */
    static final int MAX_APP_WINDOWS = 16;
    /** Stage 64: Ayarlar → Grafik → Android pencere sayısı (0 = sınırsız). */
    private volatile int userMaxWin = 0;
    /** Stage 63: cihaz sınıfı (telefon/tablet) + performans seviyesi; tek doğruluk kaynağı. */
    DeviceProfile dev;
    /** Stage 57: sanal ekrana gönderilmesine izin verilen tuşlar (GERİ, Enter, Sil, Tab, Esc, yön, sayfa, Boşluk...). */
    static final java.util.Set<Integer> SHZ_KEYS = new java.util.HashSet<>(java.util.Arrays.asList(
            4, 62, 61, 66, 67, 111, 112, 19, 20, 21, 22, 92, 93, 122, 123));

    /** Shizuku durumu değişti: sayfaya bildir (JS, durumu {"s":..,"i":..} olarak alır). */
    void shzNotify() {
        if (web == null || shz == null) return;
        web.evaluateJavascript("window.__nxShzState&&window.__nxShzState(" + shz.statusJson() + ")", null);
    }

    /**
     * Uygulama sanal ekranda başlatılamadı (ya da ilk kare gelmedi): pencereyi kapat, sayfa normal ekranda açsın.
     * why: "" | front | error | service | noframe | closed (sabit sözcükler; JS'e güvenle gömülür).
     */
    void shzLaunched(String id, boolean ok, String why) {
        final String w = (why != null && why.matches("[a-z]{0,12}")) ? why : "error";
        if (!ok && "closed".equals(w)) return; // pencere zaten kapatılmış
        if (!ok) {
            AppMirror m = mirrors.remove(id);
            if (m != null) m.release(false);
            snapData.remove(id); gpuSeq.remove(id); gpuSent.remove(id);
        }
        runOnUiThread(() -> {
            if (web != null) web.evaluateJavascript("window.__nxShzLaunched&&window.__nxShzLaunched('" + id + "'," + ok + ",'" + w + "')", null);
        });
    }

    /** Worker iş parçacığından: yeni kare hazır. JPEG saklanır, sayfaya (birleştirilmiş) tek bildirim gider. */
    void gpuFrame(String id, byte[] jpeg, int seq) {
        snapData.put(id, jpeg);
        gpuSeq.put(id, seq);
        if (!gpuNotify.compareAndSet(false, true)) return;
        runOnUiThread(() -> {
            gpuNotify.set(false);
            if (web == null) return;
            StringBuilder js = new StringBuilder();
            for (Map.Entry<String, Integer> e : gpuSeq.entrySet()) {
                Integer sent = gpuSent.get(e.getKey());
                if (sent != null && sent.intValue() == e.getValue().intValue()) continue;
                gpuSent.put(e.getKey(), e.getValue());
                js.append("window.__nxGpu&&window.__nxGpu('").append(e.getKey()).append("',").append(e.getValue()).append(");");
            }
            if (js.length() > 0) web.evaluateJavascript(js.toString(), null);
        });
    }

    /** GPU yolu kurulamadı / çöktü: sayfa eski yola düşsün (gone=true ise WebView yok, yeniden oluşturulsun). */
    void gpuOff(String id, boolean gone) {
        gpuIds.remove(id);
        gpuSeq.remove(id);
        gpuSent.remove(id);
        if (web != null) web.evaluateJavascript("window.__nxGpuOff&&window.__nxGpuOff('" + id + "'," + gone + ")", null);
    }

    /** Var olan alt WebView'i (GPU ya da eski yol) güvenle kaldırır. */
    void dropChild(String id) {
        GpuPage gp = gpuPages.remove(id);
        if (gp != null) gp.release();
        gpuSeq.remove(id); gpuSent.remove(id);
        WebView old = childViews.remove(id);
        if (old != null) {
            try { if (root != null) root.removeView(old); old.stopLoading(); old.destroy(); }
            catch (Exception e) { Log.w("NEXUS-WebView", "WebView cleanup failed: " + id, e); }
        }
    }
    static int clampI(int v, int lo, int hi) { return Math.max(lo, Math.min(hi, v)); }
    /* Tarayıcı ayarları (arayüzden gelir): PC sürümü kullanılacak alt WebView kimlikleri ve reklam engelleyici */
    final java.util.Set<String> desktopIds = ConcurrentHashMap.newKeySet();
    volatile boolean adBlock = false;
    /* Yaygın reklam / izleme ana makineleri; alt alan adları da eşleşir. Yalnızca adBlock açıkken uygulanır. */
    static final String[] AD_HOSTS = {
            "doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com",
            "googletagservices.com", "google-analytics.com", "pagead2.googlesyndication.com",
            "adnxs.com", "adsrvr.org", "taboola.com", "outbrain.com", "criteo.com", "criteo.net",
            "pubmatic.com", "rubiconproject.com", "openx.net", "moatads.com", "scorecardresearch.com",
            "amazon-adsystem.com", "adform.net", "mgid.com", "propellerads.com", "popads.net",
            "hotjar.com", "quantserve.com", "2mdn.net", "advertising.com", "smartadserver.com",
            "yieldmo.com", "casalemedia.com", "adcolony.com", "unityads.unity3d.com", "applovin.com",
            "an.yandex.ru", "mc.yandex.ru", "yandexadexchange.net"
    };

    static boolean isAdHost(String host) {
        if (host == null) return false;
        String h = host.toLowerCase(java.util.Locale.ROOT);
        for (String d : AD_HOSTS) {
            if (h.equals(d) || h.endsWith("." + d)) return true;
        }
        return false;
    }

    /* PC sürümü: masaüstü Chrome kullanıcı aracısı + sayfayı sığdır. Kapalıyken varsayılana döner. */
    static void applyDesktop(WebView v, boolean on) {
        WebSettings st = v.getSettings();
        if (on) {
            String cur = st.getUserAgentString();
            String ver = "120.0.0.0";
            java.util.regex.Matcher m = java.util.regex.Pattern.compile("Chrome/([0-9.]+)").matcher(cur == null ? "" : cur);
            if (m.find()) ver = m.group(1);
            st.setUserAgentString("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/"
                    + ver + " Safari/537.36");
            st.setUseWideViewPort(true);
            st.setLoadWithOverviewMode(true);
        } else {
            st.setUserAgentString(null); // sistem varsayılanı
            st.setUseWideViewPort(true);
            st.setLoadWithOverviewMode(false);
        }
    }
    PackageManager pm;
    ValueCallback<Uri[]> fileCb;
    final Map<String, byte[]> icons = new ConcurrentHashMap<>();

    /* Her uygulama açılışında üretilen rastgele anahtar. Yalnızca ana sayfaya (index.html) enjekte edilir;
       iframe içindeki üçüncü taraf siteler bunu göremez, dolayısıyla AndroidBridge'i kullanamaz. */
    final String token = newToken();

    static String newToken() {
        byte[] b = new byte[24];
        new SecureRandom().nextBytes(b);
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    /* Stage 44 — Native el takibi: kamera + MediaPipe Android tarafında; sonuçlar WebMessagePort ile (en taze sonuç) JS'e gider. */
    PreviewView camPv;
    NativeCam ncam;
    volatile WebMessagePort ncPort;
    volatile boolean modelOk;
    /* Stage 45 — gecikme/takılma düzeltmesi:
       1) Sonuçlar UI iş parçacığına uğramadan, ayrı yüksek öncelikli bir iş parçacığından (nx-post) gönderilir.
          Bu iş parçacığından gönderim bir cihazda çalışmazsa (ack gelmezse) otomatik olarak UI iş parçacığına döner.
       2) Akış denetimi: JS her sonucu aldığında 'a' (ack) yollar; yolda en çok 2 sonuç tutulur. JS bir an takılırsa
          arada biriken eski sonuçlar JS kuyruğunda birikmez, yalnızca EN SONUNCUSU gönderilir (yetişme takılması yok).
          Hiç ack gelmezse denetim kendiliğinden kapanır (eski davranış).
       3) Her sonuca gönderim anı (P) eklenir; JS saat farkını çıkarıp yakalama zamanını titreşimsiz bulur. */
    final Handler ncMain = new Handler(Looper.getMainLooper());
    final HandlerThread ncThread = ncStartThread();
    final Handler ncHandler = new Handler(ncThread.getLooper());
    static HandlerThread ncStartThread() {
        HandlerThread t = new HandlerThread("nx-post", android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY);
        t.start();
        return t;
    }
    final java.util.concurrent.atomic.AtomicReference<String> ncLatest = new java.util.concurrent.atomic.AtomicReference<>();
    final java.util.concurrent.atomic.AtomicBoolean ncScheduled = new java.util.concurrent.atomic.AtomicBoolean(false);
    final java.util.concurrent.atomic.AtomicInteger ncUnacked = new java.util.concurrent.atomic.AtomicInteger(0);
    volatile long ncLastSend = 0;
    volatile boolean ncUi = false;      // true: sonuçlar UI iş parçacığından gönderilir (yedek yol)
    volatile boolean ncFlow = true;     // false: ack tabanlı akış denetimi kapalı (yedek yol)
    volatile boolean ncAckSeen = false;
    volatile int ncSinceAck = 0;
    final Runnable ncFlush = () -> {
        ncScheduled.set(false);
        long now = SystemClock.elapsedRealtime();
        if (ncFlow && ncAckSeen && ncUnacked.get() >= 2) {
            if (now - ncLastSend < 250) return; // ack gelince yeniden denenir
            ncUnacked.set(0);                   // ack kayboldu: takılı kalma
        }
        String m = ncLatest.getAndSet(null);
        if (m == null) return;
        if (!ncAckSeen && ++ncSinceAck > 8) {   // hiç ack yok: önce UI'den göndermeyi dene, olmazsa denetimi kapat
            ncSinceAck = 0;
            if (!ncUi) ncUi = true;
            else ncFlow = false;
        }
        ncUnacked.incrementAndGet();
        ncLastSend = now;
        ncPost(m);
    };

    /** JS'ten ack geldi (ncHandler iş parçacığında). */
    void ncOnAck() {
        ncAckSeen = true;
        ncSinceAck = 0;
        if (ncUnacked.decrementAndGet() < 0) ncUnacked.set(0);
        if (ncLatest.get() != null && ncScheduled.compareAndSet(false, true)) ncHandler.post(ncFlush);
    }

    /** El sonucu gönderimi (R mesajı): gönderim anı eklenir. */
    void ncPost(final String m) {
        final WebMessagePort p = ncPort;
        if (p == null) return;
        if (ncUi) { ncMain.post(() -> ncDo(p, m, true)); return; }
        ncDo(p, m, false);
    }

    void ncDo(WebMessagePort p, String m, boolean ui) {
        try {
            long t = SystemClock.elapsedRealtimeNanos() / 100000L; // 0.1 ms
            StringBuilder sb = new StringBuilder(m.length() + 24).append(m).append("|P,").append(t / 10).append('.').append(t % 10);
            p.postMessage(new WebMessage(sb.toString()));
        } catch (Throwable e) {
            if (!ui) ncUi = true; // bu iş parçacığından gönderilemedi → UI iş parçacığına geç
        }
    }

    /** Denetim mesajları (S|...): güvenli yol, her zaman UI iş parçacığı. */
    void ncPostRaw(String m) {
        WebMessagePort p = ncPort;
        if (p == null) return;
        try { p.postMessage(new WebMessage(m)); } catch (Exception ignored) { }
    }

    /** NativeCam'den gelir (herhangi bir iş parçacığı). droppable=true: yalnızca en son mesaj tutulur, eskisi atılır. */
    void ncSend(final String msg, boolean droppable) {
        if (droppable) {
            ncLatest.set(msg);
            if (ncScheduled.compareAndSet(false, true)) ncHandler.post(ncFlush);
        } else {
            ncMain.post(() -> ncPostRaw(msg));
        }
    }

    volatile boolean torchOn = false, rotLocked = false;
    private SensorManager sensorManager;
    private Sensor rotationSensor;
    /** Stage 66: rotation-vector yoksa hibrit mod: yalnız ivmeölçer (yerçekimi → eğim); yön JS tarafında dokunmayla. */
    private Sensor accelSensor;
    private final float[] accelValues = new float[3];
    private boolean hasAccelValues = false;
    private volatile boolean nativeGyroActive = false;
    private long lastGyroJsMs = 0;

    boolean tokenOk(String t) {
        return t != null && MessageDigest.isEqual(t.getBytes(StandardCharsets.UTF_8), token.getBytes(StandardCharsets.UTF_8));
    }

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        pm = getPackageManager();
        shz = new ShizukuLink(this);
        shz.setOnChange(this::shzNotify);
        shz.start();
        sensorManager = (SensorManager) getSystemService(SENSOR_SERVICE);
        if (sensorManager != null) {
            rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR);
            if (rotationSensor == null) rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
            // Some budget phones omit a rotation-vector/gyroscope sensor. Stage 66 hybrid mode:
            // the accelerometer (gravity) gives pitch/roll; yaw comes from touch drag (the magnetometer
            // is too noisy/drifty indoors, so it is not used).
            if (rotationSensor == null) {
                accelSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
            }
        }
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        applyImmersiveMode();
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams windowParams = getWindow().getAttributes();
            windowParams.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            getWindow().setAttributes(windowParams);
        }
        dev = DeviceProfile.collect(this);
        applyRefreshRate(0);
        boolean debuggable = (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        WebView.setWebContentsDebuggingEnabled(debuggable);
        root = new FrameLayout(this);
        camPv = new PreviewView(this);
        camPv.setVisibility(View.INVISIBLE);
        root.addView(camPv, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        ncam = new NativeCam(this, camPv, this::ncSend);
        modelOk = NativeCam.modelPresent(this);   // önceki açılıştan kalan kopya varsa hemen hazır
        // Stage 71: model her açılışta internetten indirilir (APK'da gömülü değil)
        NativeCam.ensureModel(this, ok -> modelOk = ok);
        web = new WebView(this);
        web.setBackgroundColor(0x00000000); // saydam: kamera önizlemesi arkadan görünsün (sayfa kendi arka planını çizer)
        root.addView(web, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root);
        WebSettings w = web.getSettings();
        w.setJavaScriptEnabled(true);
        w.setDomStorageEnabled(true);
        w.setDatabaseEnabled(true);
        // Dosya / content erişimi kapalı: web içeriği cihaz dosyalarını okuyamaz
        w.setAllowFileAccess(false);
        w.setAllowContentAccess(false);
        w.setAllowFileAccessFromFileURLs(false);
        w.setAllowUniversalAccessFromFileURLs(false);
        w.setGeolocationEnabled(false);
        w.setSupportMultipleWindows(false);
        w.setSaveFormData(false);
        w.setUseWideViewPort(true);
        // Respect the page's viewport meta tag. Overview mode force-scales the whole
        // document and makes responsive CSS/VR overlay sizing disagree on tablets.
        w.setLoadWithOverviewMode(false);
        w.setTextZoom(100);
        w.setMediaPlaybackRequiresUserGesture(false);
        w.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        if (Build.VERSION.SDK_INT >= 26) w.setSafeBrowsingEnabled(true);
        w.setUserAgentString(w.getUserAgentString().replace("; wv", "").replaceAll("Version/\\d+\\.\\d+ ", ""));
        CookieManager cm = CookieManager.getInstance();
        cm.setAcceptCookie(true);
        cm.setAcceptThirdPartyCookies(web, true);
        web.addJavascriptInterface(new Bridge(), "AndroidBridge");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                return intercept(r);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                Uri u = r.getUrl();
                String sc = u.getScheme() == null ? "" : u.getScheme().toLowerCase();
                if (r.isForMainFrame()) {
                    // Ana çerçeve yalnızca uygulamanın kendi sayfasında kalabilir
                    return !(sc.equals("https") && HOST.equalsIgnoreCase(u.getHost()));
                }
                // iframe içinde yalnızca web şemalarına izin ver (intent:, market: vb. engellenir)
                return !(sc.equals("http") || sc.equals("https") || sc.equals("about") || sc.equals("blob") || sc.equals("data"));
            }

            @Override
            public void onReceivedSslError(WebView v, SslErrorHandler h, SslError e) {
                h.cancel(); // geçersiz sertifikalar asla kabul edilmez
            }

            @Override
            public void onReceivedError(WebView v, WebResourceRequest request, WebResourceError error) {
                super.onReceivedError(v, request, error);
                if (request.isForMainFrame()) {
                    Log.e("NEXUS-WebView", "Ana arayüz yükleme hatası: " + request.getUrl()
                            + " code=" + error.getErrorCode() + " " + error.getDescription());
                }
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage message) {
                if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                    Log.e("NEXUS-JS", message.message() + " (" + message.sourceId() + ":" + message.lineNumber() + ")");
                }
                return true;
            }
            @Override
            public void onPermissionRequest(final PermissionRequest r) {
                // Kamera/mikrofon yalnızca uygulamanın kendi sayfasına verilir, iframe'deki sitelere verilmez
                final boolean own = r.getOrigin() != null && HOST.equalsIgnoreCase(r.getOrigin().getHost())
                        && "https".equalsIgnoreCase(r.getOrigin().getScheme());
                runOnUiThread(() -> {
                    if (!own) {
                        r.deny();
                        return;
                    }
                    List<String> ok = new ArrayList<>();
                    for (String s : r.getResources()) {
                        if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(s) || PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(s))
                            ok.add(s);
                    }
                    if (ok.isEmpty()) r.deny();
                    else r.grant(ok.toArray(new String[0]));
                });
            }

            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (fileCb != null) fileCb.onReceiveValue(null);
                fileCb = cb;
                try {
                    startActivityForResult(p.createIntent(), 7);
                } catch (Exception e) {
                    fileCb = null;
                    return false;
                }
                return true;
            }
        });
        if (Build.VERSION.SDK_INT >= 23) {
            requestPermissions(new String[]{Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO}, 1);
        }
        web.loadUrl(ORIGIN + "/index.html");
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        if (req == 7 && fileCb != null) {
            fileCb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data));
            fileCb = null;
        }
        super.onActivityResult(req, res, data);
    }

    static WebResourceResponse status(int code, String reason, String body) {
        Map<String, String> h = new HashMap<>();
        h.put("Cache-Control", "no-store");
        return new WebResourceResponse("text/html", "UTF-8", code, reason, h,
                new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8)));
    }

    /** Sanal ana görünümün içindeki, verilen noktayı kapsayan görünür iç içe (tarayıcı) alt WebView'i; yoksa null. */
    String hitChild(String hostId, float x, float y) {
        String prefix = hostId + "__";
        for (Map.Entry<String, VS> e : vstate.entrySet()) {
            String k = e.getKey(); VS c = e.getValue();
            if (!k.startsWith(prefix) || !c.vis || !childViews.containsKey(k)) continue;
            if (x >= c.x + c.clip.left && x < c.x + c.clip.right && y >= c.y + c.clip.top && y < c.y + c.clip.bottom) return k;
        }
        return null;
    }

    /** Win7 içindeki tarayıcı (iç içe) WebView'ini görünmez tutar; yerleşimi anlık görüntüye birleştirmek için saklar. */
    void setNestedVirtual(String key, int x, int y, int w, int h, boolean visible, int cl, int ct, int cr, int cb) {
        runOnUiThread(() -> {
            WebView v = childViews.get(key);
            if (v == null || root == null) return;
            int ww = clampI(w, 2, 4096), hh = clampI(h, 2, 4096);
            FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) v.getLayoutParams();
            if (lp == null || lp.width != ww || lp.height != hh) v.setLayoutParams(new FrameLayout.LayoutParams(ww, hh));
            v.setX(0); v.setY(0);
            v.setClipBounds(new Rect(0, 0, ww, hh));
            VS s = vs(key);
            s.virt = true; s.x = x; s.y = y; s.w = ww; s.h = hh; s.vis = visible;
            s.clip.set(clampI(cl, 0, ww), clampI(ct, 0, hh), clampI(cr, 0, ww), clampI(cb, 0, hh));
            v.setVisibility(View.INVISIBLE);
            if (visible) v.onResume(); else v.onPause();
        });
    }

    void snapCb(String callback, String arg) {
        if (web == null) return;
        String q = JSONObject.quote(callback);
        web.evaluateJavascript("if(window[" + q + "])window[" + q + "](" + arg + ")", null);
    }

    WebResourceResponse intercept(WebResourceRequest r) {
        try {
            Uri u = r.getUrl();
            if (adBlock && isAdHost(u.getHost())) return status(204, "No Content", "");
            if (HOST.equalsIgnoreCase(u.getHost())) return serveAsset(r, u);
            String acc = r.getRequestHeaders().get("Accept");
            String sc = u.getScheme();
            if (!r.isForMainFrame() && "GET".equals(r.getMethod()) && acc != null && acc.contains("text/html")
                    && sc != null && sc.startsWith("http")) {
                return proxy(r);
            }
        } catch (Blocked e) {
            return status(403, "Forbidden", "<meta charset=utf-8><body style='font:16px sans-serif;padding:24px'>Bu adres güvenlik nedeniyle engellendi.</body>");
        } catch (Exception e) {
            // WebView normal akışına bırak
        }
        return null;
    }

    WebResourceResponse serveAsset(WebResourceRequest r, Uri u) {
        String p = u.getPath();
        if (p == null || p.equals("/")) p = "/index.html";
        if (p.contains("..") || p.contains("\\") || !p.startsWith("/")) return status(404, "Not Found", "");
        try {
            if (p.startsWith("/_icon/")) {
                // /_icon/<token>/<paket>
                String rest = p.substring(7);
                int i = rest.indexOf('/');
                if (i < 0 || !tokenOk(rest.substring(0, i))) return status(403, "Forbidden", "");
                String pkg = rest.substring(i + 1);
                if (!PKG.matcher(pkg).matches()) return status(400, "Bad Request", "");
                return new WebResourceResponse("image/png", null, new ByteArrayInputStream(icon(pkg)));
            }
            if (p.equals("/index.html")) {
                // Ana sayfa yalnızca ana çerçeve olarak yüklenebilir; iframe içinde gömülemez
                if (!r.isForMainFrame()) return status(403, "Forbidden", "");
                String html = new String(readAll(getAssets().open("index.html")), StandardCharsets.UTF_8);
                int k = html.indexOf("<head>");
                String inj = "<script>window.__NX=\"" + token + "\";</script>";
                html = k >= 0 ? html.substring(0, k + 6) + inj + html.substring(k + 6) : inj + html;
                Map<String, String> h = new HashMap<>();
                h.put("Cache-Control", "no-store");
                h.put("X-Content-Type-Options", "nosniff");
                h.put("Referrer-Policy", "no-referrer");
                h.put("Content-Security-Policy", "frame-ancestors 'none'");
                return new WebResourceResponse("text/html", "UTF-8", 200, "OK", h,
                        new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
            }
            if (p.equals("/win7simu.html")) {
                // Inject the session token before the simulator's iframe shim executes.
                String html = new String(readAll(getAssets().open("win7simu.html")), StandardCharsets.UTF_8);
                int k = html.indexOf("<head>");
                String inj = "<script>window.__NX=\"" + token + "\";</script>";
                html = k >= 0 ? html.substring(0, k + 6) + inj + html.substring(k + 6) : inj + html;
                Map<String, String> h = new HashMap<>();
                h.put("Cache-Control", "no-store");
                h.put("X-Content-Type-Options", "nosniff");
                return new WebResourceResponse("text/html", "UTF-8", 200, "OK", h,
                        new ByteArrayInputStream(html.getBytes(StandardCharsets.UTF_8)));
            }
            if (p.startsWith("/_snap/")) {
                // /_snap/<jeton>/<kimlik>: canlı doku JPEG'i (base64 yerine ikili aktarım)
                String rest = p.substring(7);
                int i = rest.indexOf('/');
                if (i < 0 || !tokenOk(rest.substring(0, i))) return status(403, "Forbidden", "");
                String sid = rest.substring(i + 1);
                byte[] bytes = sid.matches("[A-Za-z0-9_-]{1,80}") ? snapData.get(sid) : null;
                if (bytes == null) return status(404, "Not Found", "");
                Map<String, String> h = new HashMap<>();
                h.put("Cache-Control", "no-store");
                return new WebResourceResponse("image/jpeg", null, 200, "OK", h, new ByteArrayInputStream(bytes));
            }
            String m = mime(p);
            String enc = (m.startsWith("text/") || m.endsWith("javascript") || m.endsWith("json")) ? "UTF-8" : null;
            return new WebResourceResponse(m, enc, getAssets().open(p.substring(1)));
        } catch (IOException e) {
            return status(404, "Not Found", "");
        }
    }

    static byte[] readAll(InputStream in) throws IOException {
        try {
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) > 0) o.write(buf, 0, n);
            return o.toByteArray();
        } finally {
            in.close();
        }
    }

    static class Blocked extends IOException {
        Blocked(String m) {
            super(m);
        }
    }

    /* Yerel / özel ağ adreslerini ve kendi iç adresimizi engeller. */
    static void checkTarget(URL u) throws IOException {
        String proto = u.getProtocol();
        if (!"http".equals(proto) && !"https".equals(proto)) throw new Blocked("scheme");
        String h = u.getHost();
        if (h == null || h.isEmpty() || HOST.equalsIgnoreCase(h)) throw new Blocked("host");
        String lh = h.toLowerCase();
        if (lh.equals("localhost") || lh.endsWith(".localhost") || lh.endsWith(".local") || lh.endsWith(".internal"))
            throw new Blocked("local");
        for (InetAddress a : InetAddress.getAllByName(h)) {
            if (a.isAnyLocalAddress() || a.isLoopbackAddress() || a.isLinkLocalAddress() || a.isSiteLocalAddress()
                    || a.isMulticastAddress()) throw new Blocked("private");
            byte[] b = a.getAddress();
            if (a instanceof Inet6Address) {
                if ((b[0] & 0xFE) == 0xFC) throw new Blocked("ula"); // fc00::/7
            } else if (b.length == 4) {
                int b0 = b[0] & 0xFF, b1 = b[1] & 0xFF;
                if (b0 == 100 && b1 >= 64 && b1 <= 127) throw new Blocked("cgnat"); // 100.64.0.0/10
                if (b0 == 0) throw new Blocked("zero");
            }
        }
    }

    /* iframe (tarayıcı / web uygulamaları) sayfalarında çerçeveleme engelini kaldırarak yükler.
       Yalnızca X-Frame-Options ve CSP'nin 'frame-ancestors' yönergesi çıkarılır; sitenin diğer CSP kuralları korunur. */
    WebResourceResponse proxy(WebResourceRequest r) throws Exception {
        String url = r.getUrl().toString();
        URL target = new URL(url);
        checkTarget(target);
        HttpURLConnection c = (HttpURLConnection) target.openConnection();
        c.setConnectTimeout(15000);
        c.setReadTimeout(30000);
        c.setInstanceFollowRedirects(false); // yönlendirmeyi WebView yapar ve hedef yeniden denetlenir
        for (Map.Entry<String, String> e : r.getRequestHeaders().entrySet()) {
            String k = e.getKey();
            if (k.equalsIgnoreCase("Accept-Encoding") || k.equalsIgnoreCase("Cookie")
                    || k.equalsIgnoreCase("X-Requested-With") // uygulama paket adını sızdırır
                    || k.equalsIgnoreCase("Host")) continue;
            c.setRequestProperty(k, e.getValue());
        }
        CookieManager cm = CookieManager.getInstance();
        String ck = cm.getCookie(url);
        if (ck != null) c.setRequestProperty("Cookie", ck);
        int code = c.getResponseCode();
        if (code >= 300 && code < 400) {
            c.disconnect();
            return null;
        }
        Map<String, String> h = new HashMap<>();
        for (Map.Entry<String, List<String>> e : c.getHeaderFields().entrySet()) {
            String k = e.getKey();
            if (k == null || e.getValue().isEmpty()) continue;
            String lk = k.toLowerCase();
            if (lk.equals("set-cookie")) {
                for (String v : e.getValue()) cm.setCookie(url, v);
                continue;
            }
            if (lk.equals("x-frame-options") || lk.equals("content-length")
                    || lk.equals("content-encoding") || lk.equals("transfer-encoding")) continue;
            String val = e.getValue().get(e.getValue().size() - 1);
            if (lk.equals("content-security-policy") || lk.equals("content-security-policy-report-only")) {
                val = stripFrameAncestors(val);
                if (val.isEmpty()) continue;
            }
            h.put(k, val);
        }
        InputStream in = code >= 400 ? c.getErrorStream() : c.getInputStream();
        if (in == null) in = new ByteArrayInputStream(new byte[0]);
        String ct = c.getContentType(), mimeT = "text/html", enc = null;
        if (ct != null) {
            String[] pp = ct.split(";");
            mimeT = pp[0].trim();
            for (String q : pp) {
                String t = q.trim();
                if (t.toLowerCase().startsWith("charset=")) enc = t.substring(8).replace("\"", "");
            }
        }
        String reason = c.getResponseMessage();
        if (reason == null || reason.isEmpty()) reason = "OK";
        return new WebResourceResponse(mimeT, enc, code, reason, h, in);
    }

    static String stripFrameAncestors(String csp) {
        StringBuilder sb = new StringBuilder();
        for (String d : csp.split(";")) {
            String t = d.trim();
            if (t.isEmpty() || t.toLowerCase().startsWith("frame-ancestors")) continue;
            if (sb.length() > 0) sb.append("; ");
            sb.append(t);
        }
        return sb.toString();
    }

    static String mime(String p) {
        String x = p.substring(p.lastIndexOf('.') + 1).toLowerCase();
        switch (x) {
            case "html": return "text/html";
            case "js": case "mjs": return "text/javascript";
            case "css": return "text/css";
            case "json": return "application/json";
            case "png": return "image/png";
            case "jpg": case "jpeg": return "image/jpeg";
            case "webp": return "image/webp";
            case "svg": return "image/svg+xml";
            case "mp4": return "video/mp4";
            case "woff2": return "font/woff2";
            case "wasm": return "application/wasm";
            default: return "application/octet-stream";
        }
    }

    byte[] icon(String pkg) {
        byte[] b = icons.get(pkg);
        if (b != null) return b;
        try {
            Drawable d = pm.getApplicationIcon(pkg);
            Bitmap bm = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(bm);
            d.setBounds(0, 0, 128, 128);
            d.draw(cv);
            ByteArrayOutputStream o = new ByteArrayOutputStream();
            bm.compress(Bitmap.CompressFormat.PNG, 100, o);
            b = o.toByteArray();
            icons.put(pkg, b);
        } catch (Exception e) {
            b = new byte[0];
        }
        return b;
    }

    /* Köprü yöntemleri artık anahtar (token) ister; iframe içindeki siteler anahtarı bilmediği için reddedilir. */
    class Bridge {
        /** Stage 63: cihaz sınıfı + performans seviyesi (JSON). JS tarafı render bütçesini ve el takibi profilini buna göre seçer. */
        @JavascriptInterface
        public String deviceProfile(String t) {
            if (!tokenOk(t) || dev == null) return "{}";
            return dev.toJson();
        }

        /** Stage 64: Ayarlar'dan yenileme hızı (0 = otomatik). */
        @JavascriptInterface
        public void setRefreshRate(int hz, String t) {
            if (!tokenOk(t)) return;
            final int h = Math.max(0, Math.min(240, hz));
            runOnUiThread(() -> applyRefreshRate(h));
        }

        /** Stage 64: Ayarlar'dan eşzamanlı Android uygulama penceresi sınırı (0 = sınırsız). */
        @JavascriptInterface
        public void shzSetMaxWin(int n, String t) {
            if (!tokenOk(t)) return;
            userMaxWin = Math.max(0, Math.min(MAX_APP_WINDOWS, n));
        }

        /** Stage 44: native kamera + MediaPipe kullanılabilir mi? (izin verilmiş ve model APK içinde) */
        /** Device orientation sensor: native fallback for WebView builds that do not dispatch deviceorientation. */
        @JavascriptInterface
        public boolean nativeGyroAvailable(String t) {
            return tokenOk(t) && sensorManager != null && (rotationSensor != null || accelSensor != null);
        }

        @JavascriptInterface
        public boolean nativeGyroStart(String t) {
            if (!tokenOk(t) || sensorManager == null || (rotationSensor == null && accelSensor == null)) return false;
            runOnUiThread(() -> {
                try {
                    nativeGyroActive = true;
                    registerOrientationSensors();
                } catch (Throwable e) { nativeGyroActive = false; }
            });
            return true;
        }

        @JavascriptInterface
        public void nativeGyroStop(String t) {
            if (!tokenOk(t)) return;
            runOnUiThread(() -> {
                nativeGyroActive = false;
                if (sensorManager != null) sensorManager.unregisterListener(MainActivity.this);
            });
        }

        @JavascriptInterface
        public boolean nativeCamAvailable(String t) {
            if (!tokenOk(t) || !modelOk) return false;
            return Build.VERSION.SDK_INT < 23 || checkSelfPermission(Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED;
        }

        /** Stage 44: kamerayı/el takibini (yeniden) yapılandır. Sonuç "S|ready|..." veya "S|err|..." olarak port'a gelir. */
        @JavascriptInterface
        public void nativeCamStart(String t, String json) {
            if (!tokenOk(t) || json == null || json.length() > 2048) return;
            final NativeCam.Cfg c = new NativeCam.Cfg();
            try {
                JSONObject o = new JSONObject(json);
                c.front = "user".equals(o.optString("fac", "environment"));
                c.prev = o.optBoolean("prev", false);
                c.hand = o.optBoolean("hand", false);
                c.lite = o.optBoolean("lite", false);
                c.hands = Math.max(1, Math.min(2, o.optInt("hands", 2)));
                c.q = Math.max(0, Math.min(2, o.optInt("q", 0)));
                c.det = (float) Math.max(.05, Math.min(.95, o.optDouble("det", .42)));
                c.pres = (float) Math.max(.05, Math.min(.95, o.optDouble("pres", .42)));
                c.trk = (float) Math.max(.05, Math.min(.95, o.optDouble("trk", .40)));
            } catch (Exception e) { return; }
            runOnUiThread(() -> {
                try {
                    WebMessagePort old = ncPort;
                    if (old != null) { try { old.close(); } catch (Exception ignored) { } }
                    WebMessagePort[] ch = web.createWebMessageChannel();
                    ncUnacked.set(0); ncAckSeen = false; ncSinceAck = 0;
                    ch[0].setWebMessageCallback(new WebMessagePort.WebMessageCallback() {
                        @Override public void onMessage(WebMessagePort port, WebMessage message) { ncOnAck(); }
                    }, ncHandler);
                    ncPort = ch[0];
                    web.postWebMessage(new WebMessage("nxport:" + token, new WebMessagePort[]{ch[1]}), Uri.parse(ORIGIN));
                    if (Build.VERSION.SDK_INT >= 23 && checkSelfPermission(Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        ncSend("S|err|kamera izni yok", false);
                        return;
                    }
                    ncam.configure(c);
                } catch (Throwable e) {
                    ncSend("S|err|" + String.valueOf(e.getMessage()).replace('|', '/'), false);
                }
            });
        }

        /** Stage 44: native kamerayı tamamen kapat. */
        @JavascriptInterface
        public void nativeCamStop(String t) {
            if (!tokenOk(t)) return;
            runOnUiThread(() -> {
                try { ncam.stop(); } catch (Throwable ignored) { }
                camPv.setVisibility(View.INVISIBLE);
            });
        }

        private boolean validWebUrl(String value) {
            try {
                Uri u = Uri.parse(value);
                String s = u.getScheme();
                return value != null && ("http".equalsIgnoreCase(s) || "https".equalsIgnoreCase(s))
                        && u.getHost() != null && value.length() <= 8192;
            } catch (Exception e) { return false; }
        }

        /**
         * Sends one gaze-generated tap to the topmost visible embedded WebView
         * under the supplied screen point. Coordinates are physical pixels, matching
         * the Android View bounds configured by setRect2().
         */
        @JavascriptInterface
        public boolean gazeTapAt(float screenX, float screenY, String t) {
            if (!tokenOk(t) || !Float.isFinite(screenX) || !Float.isFinite(screenY)) return false;
            runOnUiThread(() -> {
                if (root == null) return;
                // Walk in reverse child order so overlapping nested WebViews receive
                // the event exactly as they would for a physical touch.
                for (int i = root.getChildCount() - 1; i >= 0; i--) {
                    View child = root.getChildAt(i);
                    if (!(child instanceof WebView) || child == web || child.getVisibility() != View.VISIBLE) continue;
                    float left = child.getX(), top = child.getY();
                    float right = left + child.getWidth(), bottom = top + child.getHeight();
                    if (screenX < left || screenX >= right || screenY < top || screenY >= bottom) continue;
                    long downTime = android.os.SystemClock.uptimeMillis();
                    float localX = screenX - left, localY = screenY - top;
                    android.view.MotionEvent down = android.view.MotionEvent.obtain(
                            downTime, downTime, android.view.MotionEvent.ACTION_DOWN, localX, localY, 0);
                    android.view.MotionEvent up = android.view.MotionEvent.obtain(
                            downTime, downTime + 45, android.view.MotionEvent.ACTION_UP, localX, localY, 0);
                    try {
                        child.dispatchTouchEvent(down);
                        child.dispatchTouchEvent(up);
                    } finally {
                        down.recycle();
                        up.recycle();
                    }
                    return;
                }
            });
            return true;
        }

        /**
         * Gaze interaction for embedded live pages. The fixed gaze point can be
         * placed over the top/bottom edge of a WebView to scroll; otherwise it
         * dispatches a normal tap so links, buttons and form fields keep native
         * WebView behavior. Coordinates are physical pixels, as used by setRect2.
         */
        /**
         * Keeps a WebView laid out at content resolution while its native overlay is hidden
         * for stereo mode. Unlike setRect2(..., visible=false), this does not pause the page.
         */
        @JavascriptInterface
        public void prepareGazeView(String id, int width, int height, String t) {
            if (!tokenOk(t) || id == null || id.length() > 256) return;
            int w = Math.max(3, Math.min(width, 4096));
            int h = Math.max(3, Math.min(height, 4096));
            runOnUiThread(() -> {
                WebView target = childViews.get(id);
                if (target == null || root == null) return;
                GpuPage gpu0 = gpuPages.get(id);
                if (gpu0 != null) { gpu0.setActive(true); return; }
                VS st = vs(id);
                boolean changed = st.w != w || st.h != h;
                st.virt = true; st.w = w; st.h = h;
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) target.getLayoutParams();
                if (lp == null || lp.width != w || lp.height != h) target.setLayoutParams(new FrameLayout.LayoutParams(w, h));
                target.setX(0); target.setY(0);
                target.setClipBounds(new Rect(0, 0, w, h));
                target.setVisibility(View.INVISIBLE);
                target.onResume();
                // Sayfa, fiziksel piksel / CSS piksel oranını (iç içe tarayıcı yerleşimi için) buradan öğrenir.
                if (changed) target.evaluateJavascript("window.__NXW=" + w + ";", null);
            });
        }

        /**
         * Sends a gaze tap to a backing WebView by normalized content coordinates.
         * This also works when the native overlay is INVISIBLE for stereo rendering;
         * the WebView is never made visible by this method.
         */
        @JavascriptInterface
        public boolean gazeInteractInView(String id, float nx, float ny, String t) {
            if (!tokenOk(t) || id == null || id.length() > 256 || !Float.isFinite(nx) || !Float.isFinite(ny)) return false;
            final float fx = Math.max(0f, Math.min(1f, nx));
            final float fy = Math.max(0f, Math.min(1f, ny));
            AppMirror am0 = mirrors.get(id);
            if (am0 != null) { am0.tap(fx, fy); return true; }
            runOnUiThread(() -> {
                WebView target = childViews.get(id);
                if (target == null || target.getWidth() < 3 || target.getHeight() < 3) return;
                int width = target.getWidth(), height = target.getHeight();
                float x = fx * Math.max(1, width - 1), y = fy * Math.max(1, height - 1);
                // Always deliver a real tap at the mapped page coordinate. Previously
                // the top/bottom 8% of the page was treated as a scroll zone, making
                // links, tabs and controls near the edges impossible to activate.
                long downTime = android.os.SystemClock.uptimeMillis();
                android.view.MotionEvent down = android.view.MotionEvent.obtain(
                        downTime, downTime, android.view.MotionEvent.ACTION_DOWN, x, y, 0);
                android.view.MotionEvent up = android.view.MotionEvent.obtain(
                        downTime, downTime + 45, android.view.MotionEvent.ACTION_UP, x, y, 0);
                try {
                    target.requestFocus();
                    target.dispatchTouchEvent(down);
                    target.dispatchTouchEvent(up);
                } finally {
                    down.recycle();
                    up.recycle();
                }
            });
            return true;
        }

        /** Double-clicks a point in the hidden backing WebView (used for Win7 desktop icons). */
        @JavascriptInterface
        public boolean gazeDoubleTapInView(String id, float nx, float ny, String t) {
            if (!tokenOk(t) || id == null || id.length() > 256 || !Float.isFinite(nx) || !Float.isFinite(ny)) return false;
            final float fx = Math.max(0f, Math.min(1f, nx));
            final float fy = Math.max(0f, Math.min(1f, ny));
            AppMirror am0 = mirrors.get(id);
            if (am0 != null) { am0.tap(fx, fy); return true; }
            runOnUiThread(() -> {
                WebView target = childViews.get(id);
                if (target == null || target.getWidth() < 3 || target.getHeight() < 3) return;
                float x = fx * Math.max(1, target.getWidth() - 1);
                float y = fy * Math.max(1, target.getHeight() - 1);
                long down = android.os.SystemClock.uptimeMillis();
                target.requestFocus();
                for (int tap = 0; tap < 2; tap++) {
                    long dt = down + tap * 90L;
                    android.view.MotionEvent e1 = android.view.MotionEvent.obtain(dt, dt, android.view.MotionEvent.ACTION_DOWN, x, y, 0);
                    android.view.MotionEvent e2 = android.view.MotionEvent.obtain(dt, dt + 45L, android.view.MotionEvent.ACTION_UP, x, y, 0);
                    try { target.dispatchTouchEvent(e1); target.dispatchTouchEvent(e2); }
                    finally { e1.recycle(); e2.recycle(); }
                }
            });
            return true;
        }

        /**
         * Sanal (VR paneli) sayfanın CSS yerleşim genişliğini ayarlar. Sayfa kendi arayüzünü bu genişliğe göre
         * ölçekler; böylece görev çubuğu, pencereler ve Başlat menüsü telefon boyutunda "kocaman" görünmez.
         */
        @JavascriptInterface
        public boolean setViewScale(String id, int cssWidth, String t) {
            if (!tokenOk(t) || id == null || id.length() > 256) return false;
            final int cw = clampI(cssWidth, 480, 4096);
            runOnUiThread(() -> {
                WebView target = childViews.get(id);
                vs(id).cssW = cw;
                if (target != null) target.evaluateJavascript("window.__w7setW&&window.__w7setW(" + cw + ")", null);
            });
            return true;
        }

        /**
         * Gerçek dokunma akışı: action 0=bas, 1=sürükle, 2=bırak, 3=iptal. Koordinatlar 0..1 normalize.
         * Win7 içindeki tarayıcı WebView'ine denk gelen noktalar o alt görünüme yönlendirilir; böylece pencere
         * sürükleme, kaydırma ve tarayıcı içi dokunuşlar el çimdiğiyle çalışır.
         */
        @JavascriptInterface
        public boolean touchView(String id, int action, float nx, float ny, String t) {
            if (!tokenOk(t) || id == null || id.length() > 256 || action < 0 || action > 3
                    || !Float.isFinite(nx) || !Float.isFinite(ny)) return false;
            final float fx = Math.max(0f, Math.min(1f, nx));
            final float fy = Math.max(0f, Math.min(1f, ny));
            AppMirror am0 = mirrors.get(id);
            if (am0 != null) { am0.touch(action, fx, fy); return true; }
            runOnUiThread(() -> {
                WebView host = childViews.get(id);
                if (host == null || host.getWidth() < 3 || host.getHeight() < 3) return;
                VS st = vs(id);
                float x = fx * Math.max(1, host.getWidth() - 1), y = fy * Math.max(1, host.getHeight() - 1);
                long now = android.os.SystemClock.uptimeMillis();
                if (action == 0) { st.downTime = now; st.tgKey = hitChild(id, x, y); host.requestFocus(); }
                else if (st.downTime == 0) return;
                WebView tg = st.tgKey != null ? childViews.get(st.tgKey) : null;
                VS cs = st.tgKey != null ? vstate.get(st.tgKey) : null;
                float lx = x, ly = y;
                if (tg == null) tg = host; else if (cs != null) { lx = x - cs.x; ly = y - cs.y; if (action == 0) tg.requestFocus(); }
                int act = action == 0 ? android.view.MotionEvent.ACTION_DOWN : action == 1 ? android.view.MotionEvent.ACTION_MOVE
                        : action == 2 ? android.view.MotionEvent.ACTION_UP : android.view.MotionEvent.ACTION_CANCEL;
                android.view.MotionEvent ev = android.view.MotionEvent.obtain(st.downTime, now, act, lx, ly, 0);
                ev.setSource(android.view.InputDevice.SOURCE_TOUCHSCREEN);
                try { tg.dispatchTouchEvent(ev); } finally { ev.recycle(); }
                if (action >= 2) { st.tgKey = null; st.downTime = 0; }
            });
            return true;
        }

        /** Scrolls the browser or embedded simulator without synthesizing a screen-overlay touch. */
        @JavascriptInterface
        public boolean scrollViewBy(String id, int direction, String t) {
            if (!tokenOk(t) || id == null || id.length() > 256 || direction == 0) return false;
            final int dir = direction < 0 ? -1 : 1;
            AppMirror am0 = mirrors.get(id);
            if (am0 != null) { am0.scroll(dir); return true; }
            runOnUiThread(() -> {
                // Only scroll the requested child WebView (normal browser or the selected web app).
                // Prefer the scrollable container under the viewport center; if the page uses a
                // custom layout, fall back to the largest scrollable element, then the document.
                WebView target = childViews.get(id);
                if (target == null) return;
                String js = "(function(){var d=" + dir + ";var step=Math.max(320,Math.floor(innerHeight*0.72));"
                    + "function ok(e){if(!e||e===document.documentElement||e===document.body)return false;var s=getComputedStyle(e);return e.scrollHeight>e.clientHeight+4&&/(auto|scroll|overlay)/.test(s.overflowY)}"
                    + "var el=document.elementFromPoint(innerWidth/2,innerHeight/2),p=el;while(p&&p!==document.body){if(ok(p)){p.scrollBy({top:d*step,behavior:'auto'});return 'element'}p=p.parentElement;}"
                    + "var all=document.querySelectorAll('body *'),best=null,area=0;for(var i=0;i<all.length;i++){var e=all[i];if(ok(e)){var a=e.clientWidth*e.clientHeight;if(a>area){area=a;best=e;}}}"
                    + "if(best){best.scrollBy({top:d*step,behavior:'auto'});return 'fallback'}"
                    + "var root=document.scrollingElement||document.documentElement;root.scrollBy({top:d*step,behavior:'auto'});window.scrollBy(0,d*step);return 'document';})()";
                target.evaluateJavascript(js, null);
            });
            return true;
        }

        @JavascriptInterface
        public boolean gazeInteractAt(float screenX, float screenY, String t) {
            if (!tokenOk(t) || !Float.isFinite(screenX) || !Float.isFinite(screenY)) return false;
            runOnUiThread(() -> {
                if (root == null) return;
                for (int i = root.getChildCount() - 1; i >= 0; i--) {
                    View child = root.getChildAt(i);
                    if (!(child instanceof WebView) || child == web || child.getVisibility() != View.VISIBLE) continue;
                    float left = child.getX(), top = child.getY();
                    float right = left + child.getWidth(), bottom = top + child.getHeight();
                    if (screenX < left || screenX >= right || screenY < top || screenY >= bottom) continue;
                    WebView target = (WebView) child;
                    float localX = screenX - left, localY = screenY - top;
                    float edge = Math.max(28f, target.getHeight() * 0.08f);
                    if (localY <= edge) {
                        target.scrollBy(0, -Math.max(100, target.getHeight() / 3));
                        return;
                    }
                    if (localY >= target.getHeight() - edge) {
                        target.scrollBy(0, Math.max(100, target.getHeight() / 3));
                        return;
                    }
                    long downTime = android.os.SystemClock.uptimeMillis();
                    android.view.MotionEvent down = android.view.MotionEvent.obtain(
                            downTime, downTime, android.view.MotionEvent.ACTION_DOWN, localX, localY, 0);
                    android.view.MotionEvent up = android.view.MotionEvent.obtain(
                            downTime, downTime + 45, android.view.MotionEvent.ACTION_UP, localX, localY, 0);
                    try {
                        target.dispatchTouchEvent(down);
                        target.dispatchTouchEvent(up);
                    } finally {
                        down.recycle();
                        up.recycle();
                    }
                    return;
                }
            });
            return true;
        }

        @JavascriptInterface
        public boolean create(String id, String url, String t) {
            if (!tokenOk(t) || id == null || !id.matches("[A-Za-z0-9_-]{1,80}") || !validWebUrl(url)) return false;
            // GPU yolu: ana tarayıcı VE Windows 7 monitörü. İkisi de VirtualDisplay/Presentation
            // üzerinden gerçek GPU hızlandırmalı render alır (video/WebGL akıcı kalır, ana iş
            // parçacığı yorulmaz) — Win7 artık eski "View.draw() -> JPEG" anlık görüntü yolu yerine
            // bu yolu kullanıyor. İçindeki "__" önekli alt tarayıcılar ve diğer web uygulamaları
            // eski (anlık görüntü) yolda kalır.
            // Compact phones use the direct WebView snapshot path: several vendor GPU drivers
            // cannot reliably composite a private VirtualDisplay/Presentation. Tablets retain
            // the high-throughput GPU path. The normal WebView engine remains hardware accelerated.
            final boolean phoneLayout = dev != null ? dev.phone : getResources().getConfiguration().smallestScreenWidthDp < 600;
            final boolean wantGpu = gpuOn && !phoneLayout && ("nexus-browser".equals(id) || url.startsWith(ORIGIN + "/win7simu.html"));
            if (wantGpu) gpuIds.add(id); else gpuIds.remove(id);
            runOnUiThread(() -> {
                try {
                    dropChild(id);
                    GpuPage gp = null;
                    if (wantGpu) {
                        gp = GpuPage.open(MainActivity.this, id, 1024, 576, 800, MainActivity.this::gpuFrame);
                        if (gp == null) gpuOff(id, false);
                    }
                    final GpuPage gpuPage = gp;
                    WebView v = new WebView(gpuPage != null ? gpuPage.context() : MainActivity.this);
                    WebSettings s = v.getSettings();
                    s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setDatabaseEnabled(true);
                    s.setAllowFileAccess(false); s.setAllowContentAccess(false);
                    s.setAllowFileAccessFromFileURLs(false); s.setAllowUniversalAccessFromFileURLs(false);
                    s.setSupportMultipleWindows(false); s.setJavaScriptCanOpenWindowsAutomatically(false);
                    s.setMediaPlaybackRequiresUserGesture(false); s.setUseWideViewPort(true);
                    // Keep each embedded page's responsive viewport; do not globally shrink it.
                    s.setLoadWithOverviewMode(false); s.setTextZoom(100);
                    s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
                    if (Build.VERSION.SDK_INT >= 26) s.setSafeBrowsingEnabled(true);
                    // Web apps must present as a normal mobile Chrome tab, not a bare embedded
                    // WebView: strip the "; wv" marker and stray "Version/x.y" token that make
                    // sites detect an in-app browser and respond with a desktop layout or an
                    // "update your browser" banner. Same cleanup the main browser WebView gets.
                    s.setUserAgentString(s.getUserAgentString().replace("; wv", "").replaceAll("Version/\\d+\\.\\d+ ", ""));
                    if (desktopIds.contains(id)) applyDesktop(v, true);
                    v.setBackgroundColor(0xffffffff);
                    v.setLayerType(View.LAYER_TYPE_HARDWARE, null);
                    final boolean isWin7 = url.startsWith(ORIGIN + "/win7simu.html");
                    v.setWebViewClient(new WebViewClient() {
                        @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                            // Child WebViews must use the same local asset router as the main WebView.
                            // appassets.androidplatform.net is a virtual host, not a public website.
                            return intercept(request);
                        }
                        @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                            Uri u = request.getUrl(); String sc = u.getScheme();
                            return !("http".equalsIgnoreCase(sc) || "https".equalsIgnoreCase(sc)
                                    || "about".equalsIgnoreCase(sc) || "blob".equalsIgnoreCase(sc)
                                    || "data".equalsIgnoreCase(sc) || (isWin7 && "file".equalsIgnoreCase(sc)));
                        }
                        @Override public void onPageFinished(WebView view, String finishedUrl) {
                            super.onPageFinished(view, finishedUrl);
                            if (isWin7 && (finishedUrl.startsWith(ORIGIN + "/win7simu.html") || finishedUrl.startsWith("file:///android_asset/win7simu.html"))) {
                                view.evaluateJavascript("window.__NX=" + JSONObject.quote(token) + ";", null);
                                VS pv = vstate.get(id);
                                if (pv != null) {
                                    if (pv.w > 0) view.evaluateJavascript("window.__NXW=" + pv.w + ";", null);
                                    if (pv.cssW > 0) view.evaluateJavascript("window.__w7setW&&window.__w7setW(" + pv.cssW + ")", null);
                                }
                            }
                        }
                        @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                            super.onReceivedError(view, request, error);
                            if (request.isForMainFrame()) {
                                Log.e("NEXUS-WebView", "Alt WebView yükleme hatası: " + request.getUrl()
                                        + " code=" + error.getErrorCode() + " " + error.getDescription());
                                if (isWin7) {
                                    String message = "<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>"
                                            + "<meta charset='utf-8'><body style='margin:0;background:#101820;color:#fff;font:16px sans-serif;"
                                            + "display:grid;place-items:center;min-height:100vh;text-align:center'><main>"
                                            + "<h2>Windows 7 yüklenemedi</h2><p>Kaynak yüklenirken hata oluştu. Günlükteki NEXUS-WebView kaydını kontrol edin.</p>"
                                            + "<button style='padding:12px 20px' onclick='location.reload()'>Tekrar dene</button></main></body>";
                                    view.loadDataWithBaseURL(ORIGIN + "/win7simu.html", message, "text/html", "UTF-8", null);
                                }
                            }
                        }
                        @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                            if (request.isForMainFrame()) Log.e("NEXUS-WebView", "HTTP " + response.getStatusCode() + ": " + request.getUrl());
                        }
                        @Override public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) { handler.cancel(); }
                        @Override public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
                            Log.e("NEXUS-WebView", "Alt WebView renderer sonlandı; crashed=" + detail.didCrash());
                            runOnUiThread(() -> {
                                GpuPage dead0 = gpuPages.get(id);
                                if (dead0 != null && childViews.get(id) == view) {
                                    // GPU tarayıcı: pencereden ayır, kaydı sil, sayfa bir sonraki açışta yeniden oluştursun.
                                    gpuPages.remove(id); dead0.release(); childViews.remove(id);
                                    try { view.destroy(); } catch (Exception ignored) { }
                                    gpuOff(id, true);
                                    return;
                                }
                                WebView dead = childViews.values().stream().filter(x -> x == view).findFirst().orElse(null);
                                if (dead != null) {
                                    childViews.values().remove(view);
                                    if (root != null) root.removeView(view);
                                    try { view.destroy(); } catch (Exception ignored) { }
                                }
                            });
                            return true;
                        }
                    });
                    v.setWebChromeClient(new WebChromeClient() {
                        @Override public boolean onConsoleMessage(ConsoleMessage message) {
                            if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                                Log.e("NEXUS-JS", message.message() + " (" + message.sourceId() + ":" + message.lineNumber() + ")");
                            }
                            return true;
                        }
                    });
                    if (isWin7) {
                        // Windows 7's own iframe shim needs a scoped bridge. Its child
                        // WebViews are positioned relative to the Win7 panel, not screen origin.
                        v.addJavascriptInterface(new Bridge() {
                            private String scoped(String childId) {
                                if (childId == null || !childId.matches("[A-Za-z0-9_-]{1,80}")) return null;
                                return id + "__" + childId;
                            }
                            @Override public boolean create(String childId, String childUrl, String t) {
                                String key = scoped(childId);
                                return key != null && super.create(key, childUrl, t);
                            }
                            @Override public boolean navigate(String childId, String childUrl, String t) {
                                String key = scoped(childId);
                                return key != null && super.navigate(key, childUrl, t);
                            }
                            @Override public void setRect2(String childId, int x, int y, int w, int h, boolean visible,
                                    int cl, int ct, int cr, int cb, String t) {
                                String key = scoped(childId);
                                WebView host = childViews.get(id);
                                if (key == null || host == null || !tokenOk(t)) return;
                                VS hs = vstate.get(id);
                                if (hs != null && hs.virt) { setNestedVirtual(key, x, y, w, h, visible, cl, ct, cr, cb); return; }
                                int ox = Math.round(host.getX()), oy = Math.round(host.getY());
                                super.setRect2(key, x + ox, y + oy, w, h, visible, cl, ct, cr, cb, t);
                            }
                            @Override public void destroy(String childId, String t) {
                                String key = scoped(childId);
                                if (key != null) super.destroy(key, t);
                            }
                            @Override public void snap(String childId, String callback, String t) {
                                String key = scoped(childId);
                                if (key != null) super.snap(key, callback, t);
                            }
                        }, "AndroidBridge");
                    }
                    if (gpuPage != null) {
                        gpuPage.attach(v);
                        gpuPages.put(id, gpuPage);
                    } else {
                        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
                        root.addView(v, lp); v.setVisibility(View.INVISIBLE);
                    }
                    childViews.put(id, v); v.loadUrl(url);
                } catch (Exception e) {
                    Log.e("NEXUS-WebView", "Alt WebView oluşturulamadı: " + id + " -> " + url, e);
                }
            });
            return true;
        }

        @JavascriptInterface
        public boolean createHtml(String id, String html, String t) {
            if (!tokenOk(t) || id == null || !id.matches("[A-Za-z0-9_-]{1,80}") || html == null || html.length() > 4_000_000) return false;
            runOnUiThread(() -> {
                try {
                    dropChild(id);
                    WebView v = new WebView(MainActivity.this);
                    WebSettings s = v.getSettings();
                    s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true); s.setDatabaseEnabled(true);
                    s.setAllowFileAccess(false); s.setAllowContentAccess(false);
                    s.setAllowFileAccessFromFileURLs(false); s.setAllowUniversalAccessFromFileURLs(false);
                    s.setSupportMultipleWindows(false); s.setJavaScriptCanOpenWindowsAutomatically(false);
                    s.setMediaPlaybackRequiresUserGesture(false); s.setUseWideViewPort(true);
                    // Keep each embedded page's responsive viewport; do not globally shrink it.
                    s.setLoadWithOverviewMode(false); s.setTextZoom(100);
                    s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
                    if (Build.VERSION.SDK_INT >= 26) s.setSafeBrowsingEnabled(true);
                    // Same mobile-browser user-agent cleanup as the URL-backed web apps above,
                    // in case HTML-backed content loads remote sub-resources or links out.
                    s.setUserAgentString(s.getUserAgentString().replace("; wv", "").replaceAll("Version/\\d+\\.\\d+ ", ""));
                    v.setBackgroundColor(0xffffffff);
                    // HTML-backed child views do not have a URL argument; infer Win7 from the validated child id.
                    final boolean isWin7 = id.toLowerCase(java.util.Locale.ROOT).contains("win7");
                    v.setWebViewClient(new WebViewClient() {
                        @Override public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                            // Child WebViews must use the same local asset router as the main WebView.
                            // appassets.androidplatform.net is a virtual host, not a public website.
                            return intercept(request);
                        }
                        @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                            Uri u = request.getUrl(); String sc = u.getScheme();
                            return !("http".equalsIgnoreCase(sc) || "https".equalsIgnoreCase(sc)
                                    || "about".equalsIgnoreCase(sc) || "blob".equalsIgnoreCase(sc)
                                    || "data".equalsIgnoreCase(sc));
                        }
                        @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                            super.onReceivedError(view, request, error);
                            if (request.isForMainFrame()) {
                                Log.e("NEXUS-WebView", "Alt WebView yükleme hatası: " + request.getUrl()
                                        + " code=" + error.getErrorCode() + " " + error.getDescription());
                                if (isWin7) {
                                    String message = "<!doctype html><meta name='viewport' content='width=device-width,initial-scale=1'>"
                                            + "<meta charset='utf-8'><body style='margin:0;background:#101820;color:#fff;font:16px sans-serif;"
                                            + "display:grid;place-items:center;min-height:100vh;text-align:center'><main>"
                                            + "<h2>Windows 7 yüklenemedi</h2><p>Kaynak yüklenirken hata oluştu. Günlükteki NEXUS-WebView kaydını kontrol edin.</p>"
                                            + "<button style='padding:12px 20px' onclick='location.reload()'>Tekrar dene</button></main></body>";
                                    view.loadDataWithBaseURL(ORIGIN + "/win7simu.html", message, "text/html", "UTF-8", null);
                                }
                            }
                        }
                        @Override public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse response) {
                            if (request.isForMainFrame()) Log.e("NEXUS-WebView", "HTTP " + response.getStatusCode() + ": " + request.getUrl());
                        }
                        @Override public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) { handler.cancel(); }
                        @Override public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
                            Log.e("NEXUS-WebView", "Alt WebView renderer sonlandı; crashed=" + detail.didCrash());
                            runOnUiThread(() -> {
                                WebView dead = childViews.values().stream().filter(x -> x == view).findFirst().orElse(null);
                                if (dead != null) {
                                    childViews.values().remove(view);
                                    if (root != null) root.removeView(view);
                                    try { view.destroy(); } catch (Exception ignored) { }
                                }
                            });
                            return true;
                        }
                    });
                    v.setWebChromeClient(new WebChromeClient() {
                        @Override public boolean onConsoleMessage(ConsoleMessage message) {
                            if (message.messageLevel() == ConsoleMessage.MessageLevel.ERROR) {
                                Log.e("NEXUS-JS", message.message() + " (" + message.sourceId() + ":" + message.lineNumber() + ")");
                            }
                            return true;
                        }
                    });
                    FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
                    root.addView(v, lp); v.setVisibility(View.INVISIBLE); childViews.put(id, v);
                    v.loadDataWithBaseURL("https://nexus.local/", html, "text/html", "UTF-8", null);
                } catch (Exception ignored) { }
            });
            return true;
        }

        @JavascriptInterface
        public boolean setAdBlock(boolean on, String t) {
            if (!tokenOk(t)) return false;
            adBlock = on;
            return true;
        }

        @JavascriptInterface
        public boolean setDesktopMode(String id, boolean on, String t) {
            if (!tokenOk(t) || id == null || !id.matches("[A-Za-z0-9_-]{1,80}")) return false;
            if (on) desktopIds.add(id); else desktopIds.remove(id);
            runOnUiThread(() -> {
                WebView v = childViews.get(id);
                if (v != null) applyDesktop(v, on);
            });
            return true;
        }

        @JavascriptInterface
        public boolean navigate(String id, String url, String t) {
            if (!tokenOk(t) || id == null || !validWebUrl(url)) return false;
            runOnUiThread(() -> { WebView v = childViews.get(id); if (v != null) v.loadUrl(url); });
            return true;
        }

        @JavascriptInterface
        public void setRect2(String id, int x, int y, int w, int h, boolean visible,
                             int cl, int ct, int cr, int cb, String t) {
            if (!tokenOk(t) || id == null) return;
            runOnUiThread(() -> {
                WebView v = childViews.get(id); if (v == null || root == null) return;
                GpuPage gpu0 = gpuPages.get(id);
                if (gpu0 != null) { gpu0.setActive(visible); return; }
                int ww = Math.max(2, Math.min(w, root.getWidth()));
                int hh = Math.max(2, Math.min(h, root.getHeight()));
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) v.getLayoutParams();
                if (lp == null || lp.width != ww || lp.height != hh) {
                    lp = new FrameLayout.LayoutParams(ww, hh); v.setLayoutParams(lp);
                }
                v.setX(x); v.setY(y);
                int left = Math.max(0, Math.min(cl, ww)), top = Math.max(0, Math.min(ct, hh));
                int right = Math.max(left, Math.min(cr, ww)), bottom = Math.max(top, Math.min(cb, hh));
                v.setClipBounds(new Rect(left, top, right, bottom));
                v.setVisibility(visible && right > left && bottom > top ? View.VISIBLE : View.INVISIBLE);
                if (visible) v.onResume(); else v.onPause();
                if (!visible) {
                    // Ana görünüm gizlenince içindeki tarayıcı alt WebView'leri ekranda asılı kalmasın.
                    String prefix = id + "__";
                    for (Map.Entry<String, WebView> e : childViews.entrySet()) {
                        if (!e.getKey().startsWith(prefix)) continue;
                        e.getValue().setVisibility(View.INVISIBLE);
                        VS cs = vstate.get(e.getKey());
                        if (cs != null) cs.vis = false;
                    }
                }
            });
        }

        @JavascriptInterface
        public void destroy(String id, String t) {
            if (!tokenOk(t) || id == null) return;
            AppMirror am0 = mirrors.remove(id);
            if (am0 != null) {
                am0.release(true);
                snapData.remove(id); gpuSeq.remove(id); gpuSent.remove(id);
                return;
            }
            runOnUiThread(() -> {
                // Destroy nested Win7 browser views before their host view. Their IDs are
                // namespaced to the host so closing/reopening a simulator cannot leave
                // orphan overlays or collide with another web app's iframe IDs.
                String prefix = id + "__";
                for (String key : new ArrayList<>(childViews.keySet())) {
                    if (key.startsWith(prefix)) {
                        vstate.remove(key);
                        WebView nested = childViews.remove(key);
                        if (nested != null) {
                            try { if (root != null) root.removeView(nested); nested.stopLoading(); nested.destroy(); }
                            catch (Exception e) { Log.w("NEXUS-WebView", "Nested WebView cleanup failed: " + key, e); }
                        }
                    }
                }
                vstate.remove(id); snapData.remove(id);
                GpuPage gpu0 = gpuPages.remove(id);
                if (gpu0 != null) gpu0.release();
                gpuIds.remove(id); gpuSeq.remove(id); gpuSent.remove(id);
                WebView v = childViews.remove(id);
                if (v != null) {
                    try { if (root != null) root.removeView(v); v.stopLoading(); v.destroy(); }
                    catch (Exception e) { Log.w("NEXUS-WebView", "WebView cleanup failed: " + id, e); }
                }
            });
        }

        @JavascriptInterface
        public void snap(String id, String callback, String t) {
            if (!tokenOk(t) || id == null || callback == null || !callback.matches("[A-Za-z_$][A-Za-z0-9_$]{0,100}")) return;
            runOnUiThread(() -> {
                WebView v = childViews.get(id); if (v == null) { web.evaluateJavascript("if(window[" + JSONObject.quote(callback) + "])window[" + JSONObject.quote(callback) + "](null)", null); return; }
                Bitmap scaled = null;
                try {
                    int sourceW = Math.max(1, v.getWidth()), sourceH = Math.max(1, v.getHeight());
                    // Full-size PNG snapshots every few hundred milliseconds created
                    // multi-megabyte base64 strings and caused severe frame drops.
                    // Scale to a bounded preview size and use JPEG for the live texture.
                    float scale = Math.min(1f, Math.min(800f / sourceW, 500f / sourceH));
                    int outW = Math.max(1, Math.round(sourceW * scale));
                    int outH = Math.max(1, Math.round(sourceH * scale));
                    scaled = Bitmap.createBitmap(outW, outH, Bitmap.Config.RGB_565);
                    Canvas canvas = new Canvas(scaled);
                    canvas.drawColor(android.graphics.Color.WHITE);
                    canvas.save();
                    canvas.scale((float) outW / sourceW, (float) outH / sourceH);
                    v.draw(canvas);
                    canvas.restore();
                    ByteArrayOutputStream out = new ByteArrayOutputStream(64 * 1024);
                    scaled.compress(Bitmap.CompressFormat.JPEG, 52, out);
                    String data = "data:image/jpeg;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP);
                    web.evaluateJavascript("if(window[" + JSONObject.quote(callback) + "])window[" + JSONObject.quote(callback) + "](" + JSONObject.quote(data) + ")", null);
                } catch (Exception e) {
                    web.evaluateJavascript("if(window[" + JSONObject.quote(callback) + "])window[" + JSONObject.quote(callback) + "](null)", null);
                } finally {
                    if (scaled != null && !scaled.isRecycled()) scaled.recycle();
                }
            });
        }

        /**
         * Yüksek çözünürlüklü canlı doku: görünmez WebView'i (ve içindeki tarayıcı alt WebView'lerini) tek bitmap'e
         * çizer, JPEG'e arka planda sıkıştırır ve base64/JS dizgesi yerine /_snap/ adresinden sunar.
         * Geri çağrı: seq (>0 yeni kare), 0 (değişmedi), -1 (görünüm yok), -2 (meşgul).
         */
        @JavascriptInterface
        public void snap2(String id, String callback, int maxW, int quality, String t) {
            if (!tokenOk(t) || id == null || id.length() > 80 || callback == null
                    || !callback.matches("[A-Za-z_$][A-Za-z0-9_$]{0,100}")) return;
            final int mw = clampI(maxW, 320, 2560), q = clampI(quality, 30, 92);
            runOnUiThread(() -> {
                WebView v = childViews.get(id);
                VS st = vs(id);
                if (v == null || v.getWidth() < 3 || v.getHeight() < 3) { snapCb(callback, "-1"); return; }
                if (st.busy) { snapCb(callback, "-2"); return; }
                int sw = v.getWidth(), sh = v.getHeight();
                float sc = Math.min(1f, mw / (float) sw);
                int ow = Math.max(1, Math.round(sw * sc)), oh = Math.max(1, Math.round(sh * sc));
                try {
                    if (st.bmp == null || st.bmp.getWidth() != ow || st.bmp.getHeight() != oh) {
                        st.bmp = Bitmap.createBitmap(ow, oh, Bitmap.Config.ARGB_8888);
                    }
                    Canvas c = new Canvas(st.bmp);
                    c.drawColor(0xffffffff);
                    c.save();
                    c.scale(sc, sc);
                    v.draw(c);
                    String prefix = id + "__";
                    for (Map.Entry<String, WebView> e : childViews.entrySet()) {
                        if (!e.getKey().startsWith(prefix)) continue;
                        VS cs = vstate.get(e.getKey());
                        WebView cv = e.getValue();
                        if (cs == null || !cs.vis || cv.getWidth() < 3) continue;
                        c.save();
                        c.translate(cs.x, cs.y);
                        c.clipRect(cs.clip);
                        cv.draw(c);
                        c.restore();
                    }
                    c.restore();
                } catch (Exception e) {
                    snapCb(callback, "-1");
                    return;
                }
                st.busy = true;
                final Bitmap b = st.bmp;
                snapExec.execute(() -> {
                    String res = "-1";
                    try {
                        ByteArrayOutputStream out = new ByteArrayOutputStream(Math.max(16384, ow * oh / 8));
                        b.compress(Bitmap.CompressFormat.JPEG, q, out);
                        byte[] bytes = out.toByteArray();
                        int hsh = java.util.Arrays.hashCode(bytes) * 31 + bytes.length;
                        if (st.seq > 0 && hsh == st.lastHash) res = "0";
                        else { st.lastHash = hsh; snapData.put(id, bytes); res = String.valueOf(++st.seq); }
                    } catch (Exception ignored) { }
                    final String r = res;
                    runOnUiThread(() -> { st.busy = false; snapCb(callback, r); });
                });
            });
        }

        /* ---- Stage 27: GPU tarayıcı köprüsü ---- */
        /** Stage 32: sitenin ikonunu indirir; sonuç callback(dataUri | null) olarak JS'e döner. */
        @JavascriptInterface
        public boolean fetchIcon(String url, String callback, String t) {
            if (!tokenOk(t) || !validWebUrl(url) || !url.toLowerCase().startsWith("https://") || callback == null
                    || !callback.matches("[A-Za-z_$][A-Za-z0-9_$]{0,100}")) return false;
            iconExec.execute(() -> {
                String res = null;
                int tried = 0;
                for (String cand : iconCandidates(url)) {
                    if (++tried > 6) break;
                    try {
                        res = iconDataUri(httpBytes(cand, 1_000_000, false));
                        if (res != null) break;
                    } catch (Exception ignored) { }
                }
                final String arg = res == null ? "null" : JSONObject.quote(res);
                runOnUiThread(() -> snapCb(callback, arg));
            });
            return true;
        }

        @JavascriptInterface
        public boolean isGpu(String id, String t) {
            return tokenOk(t) && id != null && gpuIds.contains(id);
        }

        @JavascriptInterface
        public void setGpu(boolean on, String t) {
            if (tokenOk(t)) gpuOn = on;
        }

        /** GPU sayfasının görüntü boyutu (piksel) ve CSS yerleşim genişliği. Etkinleştirir (görünür olunca sürdürür). */
        @JavascriptInterface
        public boolean gpuSize(String id, int width, int height, int cssWidth, String t) {
            if (!tokenOk(t) || id == null || !id.matches("[A-Za-z0-9_-]{1,80}")) return false;
            final int ww = clampI(width, 320, 1920), hh = clampI(height, 240, 1200), cw = clampI(cssWidth, 320, 1920);
            AppMirror am0 = mirrors.get(id);
            if (am0 != null) { am0.resizeLater(ww, hh, cw); return true; }
            runOnUiThread(() -> {
                GpuPage gp = gpuPages.get(id);
                if (gp == null) return;
                gp.resizeLater(ww, hh, cw);
                gp.setActive(true);
            });
            return true;
        }

        @JavascriptInterface
        public boolean openExternal(String value, String t) {
            if (!tokenOk(t) || !validWebUrl(value)) return false;
            try {
                Uri uri = Uri.parse(value);
                Intent intent = new Intent(Intent.ACTION_VIEW, uri);
                intent.addCategory(Intent.CATEGORY_BROWSABLE);
                runOnUiThread(() -> {
                    try { startActivity(intent); } catch (Exception ignored) { }
                });
                return true;
            } catch (Exception e) { return false; }
        }

        @JavascriptInterface
        public boolean openWin7(String t) {
            if (!tokenOk(t)) return false;
            try {
                runOnUiThread(() -> startActivity(new Intent(MainActivity.this, Win7Activity.class)));
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        /** Açılış sahnesindeki «Çıkış» düğmesi: uygulamayı kapatır (görev listesinden de kaldırır). */
        @JavascriptInterface
        public boolean exitApp(String t) {
            if (!tokenOk(t)) return false;
            try {
                runOnUiThread(() -> finishAndRemoveTask());
                return true;
            } catch (Exception e) {
                return false;
            }
        }

        /** Hızlı ayarlar menüsü: cihaz durumu (ses, parlaklık, Wi-Fi, Bluetooth, uçak modu, veri, fener, kilit). */
        @JavascriptInterface
        public String sysState(String t) {
            if (!tokenOk(t)) return "{}";
            JSONObject o = new JSONObject();
            try {
                android.media.AudioManager am = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
                int max = Math.max(1, am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC));
                o.put("vol", am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC) / (double) max);
                o.put("playing", am.isMusicActive());
            } catch (Exception ignored) { }
            try {
                float b = getWindow().getAttributes().screenBrightness;
                if (b < 0) b = android.provider.Settings.System.getInt(getContentResolver(),
                        android.provider.Settings.System.SCREEN_BRIGHTNESS, 128) / 255f;
                o.put("bright", b);
            } catch (Exception ignored) { }
            try {
                android.net.wifi.WifiManager wm = (android.net.wifi.WifiManager)
                        getApplicationContext().getSystemService(WIFI_SERVICE);
                o.put("wifi", wm != null && wm.isWifiEnabled());
            } catch (Exception ignored) { }
            try {
                android.bluetooth.BluetoothAdapter ba = android.bluetooth.BluetoothAdapter.getDefaultAdapter();
                o.put("bt", ba != null && ba.isEnabled());
            } catch (Exception ignored) { }
            try {
                o.put("air", android.provider.Settings.Global.getInt(getContentResolver(),
                        android.provider.Settings.Global.AIRPLANE_MODE_ON, 0) == 1);
            } catch (Exception ignored) { }
            try {
                o.put("data", android.provider.Settings.Global.getInt(getContentResolver(), "mobile_data", 0) == 1);
            } catch (Exception ignored) { }
            try {
                o.put("torch", torchOn);
                o.put("rot", rotLocked);
                o.put("keep", (getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) != 0);
            } catch (Exception ignored) { }
            return o.toString();
        }

        @JavascriptInterface
        public boolean setVolume(double v, String t) {
            if (!tokenOk(t)) return false;
            try {
                android.media.AudioManager am = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
                int max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC);
                am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC,
                        (int) Math.round(Math.max(0, Math.min(1, v)) * max), 0);
                return true;
            } catch (Exception e) { return false; }
        }

        @JavascriptInterface
        public boolean setBrightness(double v, String t) {
            if (!tokenOk(t)) return false;
            final float f = (float) Math.max(0.02, Math.min(1, v));
            try {
                runOnUiThread(() -> {
                    WindowManager.LayoutParams lp = getWindow().getAttributes();
                    lp.screenBrightness = f;
                    getWindow().setAttributes(lp);
                });
                return true;
            } catch (Exception e) { return false; }
        }

        @JavascriptInterface
        public boolean setTorch(boolean on, String t) {
            if (!tokenOk(t)) return false;
            try {
                android.hardware.camera2.CameraManager cm =
                        (android.hardware.camera2.CameraManager) getSystemService(CAMERA_SERVICE);
                String id = null;
                for (String cid : cm.getCameraIdList()) {
                    android.hardware.camera2.CameraCharacteristics ch = cm.getCameraCharacteristics(cid);
                    Boolean fl = ch.get(android.hardware.camera2.CameraCharacteristics.FLASH_INFO_AVAILABLE);
                    Integer face = ch.get(android.hardware.camera2.CameraCharacteristics.LENS_FACING);
                    if (Boolean.TRUE.equals(fl) && face != null
                            && face == android.hardware.camera2.CameraCharacteristics.LENS_FACING_BACK) { id = cid; break; }
                }
                if (id == null) return false;
                cm.setTorchMode(id, on);
                torchOn = on;
                return true;
            } catch (Exception e) { return false; }
        }

        @JavascriptInterface
        public boolean setKeepOn(boolean on, String t) {
            if (!tokenOk(t)) return false;
            try {
                runOnUiThread(() -> {
                    if (on) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                    else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                });
                return true;
            } catch (Exception e) { return false; }
        }

        @JavascriptInterface
        public boolean setRotationLock(boolean on, String t) {
            if (!tokenOk(t)) return false;
            try {
                rotLocked = on;
                runOnUiThread(() -> setRequestedOrientation(on
                        ? android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LOCKED
                        : android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE));
                return true;
            } catch (Exception e) { return false; }
        }

        @JavascriptInterface
        public boolean mediaKey(String k, String t) {
            if (!tokenOk(t)) return false;
            try {
                int code = "next".equals(k) ? android.view.KeyEvent.KEYCODE_MEDIA_NEXT
                        : "prev".equals(k) ? android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
                        : android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE;
                android.media.AudioManager am = (android.media.AudioManager) getSystemService(AUDIO_SERVICE);
                am.dispatchMediaKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, code));
                am.dispatchMediaKeyEvent(new android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, code));
                return true;
            } catch (Exception e) { return false; }
        }

        /** Wi-Fi / Bluetooth / uçak modu / mobil veri Android 10+ sürümünde uygulamadan değiştirilemez: sistem paneli açılır. */
        @JavascriptInterface
        public boolean openPanel(String which, String t) {
            if (!tokenOk(t)) return false;
            try {
                boolean q = Build.VERSION.SDK_INT >= 29;
                String a;
                switch (which == null ? "" : which) {
                    case "wifi": a = q ? android.provider.Settings.Panel.ACTION_WIFI : android.provider.Settings.ACTION_WIFI_SETTINGS; break;
                    case "data": a = q ? android.provider.Settings.Panel.ACTION_INTERNET_CONNECTIVITY : android.provider.Settings.ACTION_DATA_ROAMING_SETTINGS; break;
                    case "bt": a = android.provider.Settings.ACTION_BLUETOOTH_SETTINGS; break;
                    case "air": a = android.provider.Settings.ACTION_AIRPLANE_MODE_SETTINGS; break;
                    case "volume": a = q ? android.provider.Settings.Panel.ACTION_VOLUME : android.provider.Settings.ACTION_SOUND_SETTINGS; break;
                    default: return false;
                }
                final Intent in = new Intent(a).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                runOnUiThread(() -> { try { startActivity(in); } catch (Exception ignored) { } });
                return true;
            } catch (Exception e) { return false; }
        }

        /** Stage 56: Shizuku durumu. {"s":0..4,"i":yüklü}; s=4 hazır. */
        @JavascriptInterface
        public String shzStatus(String t) {
            if (!tokenOk(t) || shz == null) return "{\"s\":0,\"i\":false}";
            return shz.statusJson();
        }

        /** Stage 56: izin iste / kabuk servisine bağlan (kullanıcı eylemiyle çağrılmalı). */
        @JavascriptInterface
        public void shzRequest(String t) {
            if (!tokenOk(t) || shz == null) return;
            shz.poke();
        }

        /** Stage 56: bu paket VR penceresinde açılabilir mi? (Shizuku hazır, yasak listesinde değil, başlatılabilir) */
        @JavascriptInterface
        public boolean shzCanOpen(String pkg, String t) {
            if (!tokenOk(t) || shz == null || pkg == null || !PKG.matcher(pkg).matches()
                    || ShizukuLink.denied(pkg) || shz.state() != ShizukuLink.S_READY) return false;
            Intent li = pm.getLaunchIntentForPackage(pkg);
            return li != null && li.getComponent() != null;
        }

        /**
         * Stage 56: uygulamayı sanal ekranda başlat. Kare akışı GpuPage ile aynı yoldan gelir (id ile __nxGpu).
         * id: [A-Za-z0-9_-]{1,80}; başlatma sonucu __nxShzLaunched(id, ok) ile bildirilir.
         */
        @JavascriptInterface
        public boolean shzOpen(String id, String pkg, int width, int height, int cssW, String t) {
            if (!tokenOk(t) || shz == null || id == null || !id.matches("[A-Za-z0-9_-]{1,80}")
                    || pkg == null || !PKG.matcher(pkg).matches() || ShizukuLink.denied(pkg)
                    || shz.state() != ShizukuLink.S_READY) return false;
            if (mirrors.containsKey(id)) return true;
            // Her pencere bir sanal ekran + JPEG hattıdır; zayıf cihazlarda sınırsız açılmasın.
            // Stage 64: sınıf/seviye sınırı kaldırıldı; sınır yalnızca kullanıcı ayarından gelir (0 = sınırsız).
            final int maxWin = maxAppWindows();
            if (mirrors.size() >= maxWin) return false;
            Intent li = pm.getLaunchIntentForPackage(pkg);
            if (li == null || li.getComponent() == null) return false;
            final String comp = li.getComponent().flattenToString();
            AppMirror m = AppMirror.open(MainActivity.this, shz, id, pkg, comp,
                    clampI(width, 320, 1920), clampI(height, 240, 1200), clampI(cssW, 320, 1920),
                    MainActivity.this::gpuFrame, MainActivity.this::shzLaunched);
            if (m == null) return false;
            mirrors.put(id, m);
            return true;
        }

        /**
         * Stage 56/57: sanal ekrandaki uygulamaya tuş gönder. Yalnızca SHZ_KEYS beyaz listesi
         * (GERİ, Enter, Sil, Tab, Esc, yön tuşları, sayfa, Boşluk); Ana ekran/Güç/Ses gibi tuşlar reddedilir.
         */
        @JavascriptInterface
        public boolean shzKey(String id, int keyCode, String t) {
            if (!tokenOk(t) || id == null || !SHZ_KEYS.contains(keyCode)) return false;
            AppMirror m = mirrors.get(id);
            if (m == null) return false;
            m.key(keyCode);
            return true;
        }

        /**
         * Stage 57: sanal ekrandaki uygulamanın odaklı alanına metin yaz (en çok 64 karakter; denetim
         * karakterleri yazılmaz). Dönüş: kuyruğa alındıysa karakter sayısı, pencere yoksa/geçersizse -1.
         */
        @JavascriptInterface
        public int shzText(String id, String text, String t) {
            if (!tokenOk(t) || id == null || text == null || text.isEmpty() || text.length() > 64) return -1;
            AppMirror m = mirrors.get(id);
            if (m == null) return -1;
            return m.typeText(text) ? text.codePointCount(0, text.length()) : -1;
        }

        @JavascriptInterface
        public String getApps(String t) {
            if (!tokenOk(t)) return "[]";
            try {
                Intent i = new Intent(Intent.ACTION_MAIN);
                i.addCategory(Intent.CATEGORY_LAUNCHER);
                List<ResolveInfo> list = pm.queryIntentActivities(i, 0);
                JSONArray a = new JSONArray();
                Set<String> seen = new HashSet<>();
                for (ResolveInfo ri : list) {
                    String p = ri.activityInfo.packageName;
                    if (p.equals(getPackageName()) || !seen.add(p)) continue;
                    JSONObject o = new JSONObject();
                    o.put("p", p);
                    o.put("n", ri.loadLabel(pm).toString());
                    a.put(o);
                }
                return a.toString();
            } catch (Exception e) {
                return "[]";
            }
        }

        @JavascriptInterface
        public boolean launch(String t, final String p) {
            if (!tokenOk(t) || p == null || !PKG.matcher(p).matches() || p.equals(getPackageName())) return false;
            try {
                final Intent i = pm.getLaunchIntentForPackage(p);
                if (i == null) return false;
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                runOnUiThread(() -> startActivity(i));
                return true;
            } catch (Exception e) {
                return false;
            }
        }
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else moveTaskToBack(true);
    }

    @Override
    protected void onResume() {
        super.onResume();
        applyImmersiveMode();
        if (nativeGyroActive && sensorManager != null) {
            try { registerOrientationSensors(); }
            catch (Throwable e) { Log.w("NEXUS-Sensor", "Sensör yeniden başlatılamadı", e); }
        }
        web.onResume();
        if (ncam != null) ncam.onResume();
        for (GpuPage g : gpuPages.values()) g.setHostPaused(false);
        for (AppMirror am : mirrors.values()) am.setPaused(false);
    }

    @Override
    protected void onPause() {
        if (sensorManager != null) sensorManager.unregisterListener(this);
        for (GpuPage g : gpuPages.values()) g.setHostPaused(true);
        for (AppMirror am : mirrors.values()) am.setPaused(true);
        if (ncam != null) ncam.onPause();
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        nativeGyroActive = false;
        if (sensorManager != null) sensorManager.unregisterListener(this);
        if (ncam != null) { try { ncam.onDestroy(); } catch (Throwable ignored) { } }
        try { ncThread.quitSafely(); } catch (Throwable ignored) { }
        WebMessagePort np = ncPort;
        if (np != null) { try { np.close(); } catch (Exception ignored) { } ncPort = null; }
        for (GpuPage g : gpuPages.values()) { try { g.release(); } catch (Exception ignored) { } }
        gpuPages.clear();
        // Stage 57: uygulamaları durdurma isteği Shizuku bağlantısı kesilmeden ÖNCE bitmeli (en çok ~1,5 sn beklenir),
        // yoksa sanal ekran silinince uygulamalar gerçek ekrana taşınıp açık kalabiliyordu.
        if (!mirrors.isEmpty()) {
            final java.util.concurrent.CountDownLatch latch = new java.util.concurrent.CountDownLatch(mirrors.size());
            for (AppMirror am : mirrors.values()) {
                try { am.release(true, latch::countDown); } catch (Exception e) { latch.countDown(); }
            }
            try { latch.await(1500, java.util.concurrent.TimeUnit.MILLISECONDS); }
            catch (InterruptedException ie) { Thread.currentThread().interrupt(); }
        }
        mirrors.clear();
        if (shz != null) { try { shz.stop(); } catch (Exception ignored) { } }
        for (WebView v : childViews.values()) { try { if (root != null) root.removeView(v); v.stopLoading(); v.destroy(); } catch (Exception ignored) { } }
        childViews.clear();
        if (web != null) {
            web.removeJavascriptInterface("AndroidBridge");
            web.destroy();
        }
        super.onDestroy();
    }

    @Override
    public void onConfigurationChanged(Configuration cfg) {
        super.onConfigurationChanged(cfg);
        if (ncam != null) ncam.onRotation();
    }

    /** Stage 64: aynı anda açık Android uygulama penceresi sınırı. Cihaz sınıfı/seviyesi artık sınırlamaz; yalnızca kullanıcı ayarı geçerli. */
    int maxAppWindows() {
        int n = userMaxWin;
        return n > 0 ? Math.min(n, MAX_APP_WINDOWS) : MAX_APP_WINDOWS;
    }

    /**
     * Stage 64: ekran yenileme hızı. hz = 0 otomatik (yüksek seviyede en yüksek mod, aksi hâlde sistem varsayılanı);
     * hz &gt; 0 aynı çözünürlükteki modlardan istenene en yakın olanı seçer.
     */
    private void applyRefreshRate(int hz) {
        if (Build.VERSION.SDK_INT < 23) return;
        try {
            android.view.Display d = getWindowManager().getDefaultDisplay();
            android.view.Display.Mode cur = d.getMode(), pick = null;
            for (android.view.Display.Mode m : d.getSupportedModes()) {
                if (m.getPhysicalWidth() != cur.getPhysicalWidth() || m.getPhysicalHeight() != cur.getPhysicalHeight()) continue;
                if (hz > 0) {
                    if (pick == null || Math.abs(m.getRefreshRate() - hz) < Math.abs(pick.getRefreshRate() - hz) - 0.01f) pick = m;
                } else if (dev != null && dev.tier >= 2) {
                    if (pick == null || m.getRefreshRate() > pick.getRefreshRate()) pick = m;
                }
            }
            WindowManager.LayoutParams lp = getWindow().getAttributes();
            int id = pick == null ? 0 : pick.getModeId();
            if (lp.preferredDisplayModeId != id) {
                lp.preferredDisplayModeId = id;
                getWindow().setAttributes(lp);
            }
        } catch (Throwable e) { Log.w("NEXUS-Dev", "yenileme hızı ayarlanamadı", e); }
    }

    /** Stage 63: bellek baskısı. Sistem bellek isterse sayfa çözünürlüğü düşürülür (JS tarafı __nxTrim). */
    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (level < android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW || web == null) return;
        final int lv = level;
        runOnUiThread(() -> {
            try { web.evaluateJavascript("window.__nxTrim&&window.__nxTrim(" + lv + ")", null); }
            catch (Throwable ignored) { }
        });
    }

    private void applyImmersiveMode() {
        final int flags = View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;
        getWindow().getDecorView().setSystemUiVisibility(flags);
    }

    private void registerOrientationSensors() {
        if (sensorManager == null) return;
        sensorManager.unregisterListener(this);
        if (rotationSensor != null) sensorManager.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_GAME);
        else {
            hasAccelValues = false;
            if (accelSensor != null) sensorManager.registerListener(this, accelSensor, SensorManager.SENSOR_DELAY_GAME);
        }
    }

    @Override public void onSensorChanged(SensorEvent event) {
        if (!nativeGyroActive || event == null || event.sensor == null) return;
        long now = android.os.SystemClock.uptimeMillis();
        if (web == null) return;
        try {
            float[] rotation = new float[9];
            int type = event.sensor.getType();
            if (rotationSensor != null && type == rotationSensor.getType()) {
                if (now - lastGyroJsMs < 8) return; // en çok ~120 Hz; WebView kuyruğunu doldurma
                SensorManager.getRotationMatrixFromVector(rotation, event.values);
            } else if (rotationSensor == null && type == Sensor.TYPE_ACCELEROMETER) {
                // Stage 66 hibrit mod: yerçekimi vektörü (eğim + yatış). Hareket ivmesi yerçekimini bozar:
                // ivme büyüklüğü 9.81'den saptıkça süzgeç katsayısı küçülür (hareket anında az güven).
                float ax = event.values[0], ay = event.values[1], az = event.values[2];
                if (Float.isNaN(ax) || Float.isNaN(ay) || Float.isNaN(az)) return;
                float mag = (float) Math.sqrt(ax * ax + ay * ay + az * az);
                float k = 0.18f * Math.max(0.08f, 1f - Math.abs(mag - 9.81f) / 1.5f);
                if (!hasAccelValues) { accelValues[0] = ax; accelValues[1] = ay; accelValues[2] = az; hasAccelValues = true; }
                else { accelValues[0] += k * (ax - accelValues[0]); accelValues[1] += k * (ay - accelValues[1]); accelValues[2] += k * (az - accelValues[2]); }
                if (now - lastGyroJsMs < 16) return; // en çok ~60 Hz
                lastGyroJsMs = now;
                float fx = accelValues[0], fy = accelValues[1], gz = accelValues[2], gx, gy;
                int dr = getWindowManager().getDefaultDisplay().getRotation();
                // Ham eksenler ekranın varsayılan yönüne göre; ekran döndürmesine göre ekran eksenlerine çevir.
                if (dr == android.view.Surface.ROTATION_90) { gx = -fy; gy = fx; }
                else if (dr == android.view.Surface.ROTATION_180) { gx = -fx; gy = -fy; }
                else if (dr == android.view.Surface.ROTATION_270) { gx = fy; gy = -fx; }
                else { gx = fx; gy = fy; }
                final String gjs = "window.__nxNativeGrav&&window.__nxNativeGrav(" + gx + "," + gy + "," + gz + ")";
                runOnUiThread(() -> {
                    if (web != null && nativeGyroActive) web.evaluateJavascript(gjs, null);
                });
                return;
            } else return;
            lastGyroJsMs = now;
            int displayRotation = getWindowManager().getDefaultDisplay().getRotation();
            int axisX = SensorManager.AXIS_X, axisY = SensorManager.AXIS_Y;
            if (displayRotation == android.view.Surface.ROTATION_90) { axisX = SensorManager.AXIS_Y; axisY = SensorManager.AXIS_MINUS_X; }
            else if (displayRotation == android.view.Surface.ROTATION_180) { axisX = SensorManager.AXIS_MINUS_X; axisY = SensorManager.AXIS_MINUS_Y; }
            else if (displayRotation == android.view.Surface.ROTATION_270) { axisX = SensorManager.AXIS_MINUS_Y; axisY = SensorManager.AXIS_X; }
            float[] m = new float[9];
            SensorManager.remapCoordinateSystem(rotation, axisX, axisY, m);
            // Euler açıları (getOrientation) yerine dönüş matrisini gönder: telefon gözlükte dik
            // dururken Euler açıları tekil (gimbal kilidi) olup sahneyi sıçratıyordu.
            for (int i = 0; i < 9; i++) if (Float.isNaN(m[i]) || Float.isInfinite(m[i])) return;
            final String js = "window.__nxNativeMatrix&&window.__nxNativeMatrix(" + m[0] + "," + m[1] + "," + m[2] + ","
                    + m[3] + "," + m[4] + "," + m[5] + "," + m[6] + "," + m[7] + "," + m[8] + ")";
            runOnUiThread(() -> {
                if (web != null && nativeGyroActive) web.evaluateJavascript(js, null);
            });
        } catch (Throwable e) { Log.w("NEXUS-Sensor", "Yön sensörü okunamadı", e); }
    }

    @Override public void onAccuracyChanged(Sensor sensor, int accuracy) { }

    @Override public void onWindowFocusChanged(boolean f) {
        super.onWindowFocusChanged(f);
        if (f) applyImmersiveMode();
    }
}
