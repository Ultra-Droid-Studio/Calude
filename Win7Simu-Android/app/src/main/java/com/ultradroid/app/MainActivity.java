package com.ultradroid.app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ContentValues;
import android.content.Context;
import android.content.ComponentName;
import android.content.ServiceConnection;
import android.content.pm.PackageInfo;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.view.PixelCopy;
import java.nio.ByteBuffer;
import android.graphics.Rect;
import android.os.IBinder;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.media.AudioManager;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;
import android.view.MotionEvent;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.widget.FrameLayout;
import rikka.shizuku.Shizuku;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.drawable.Drawable;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

/**
 * UltraDroid'i (index.html) tam ekran bir WebView içinde çalıştırır.
 *
 * HTML dosyası içindeki w7-persist-js bloğu, sayfanın localStorage'ını
 * window.AndroidBridge (sGetAll / sPut / sDel / sClear) üzerinden
 * SharedPreferences'a yansıtıyor; böylece localStorage dolsa/temizlense
 * bile ayarlar/uygulamalar kaybolmuyor.
 *
 * Chrome / Internet Explorer / Nova Browser pencerelerindeki iframe'ler (http/https) HTML tarafında yakalanır ve
 * AndroidBridge.create/navigate/setRect2/destroy/snap ile gerçek (sistem) Android WebView'lere taşınır. WebView,
 * pencerenin üstüne konur; pencere sürüklenirken/boyutlandırılırken HTML, snap() ile aldığı JPEG görüntüyü
 * pencerenin içine koyup WebView'i gizler (dışarı taşma / geriden gelme olmaz).
 */
public class MainActivity extends Activity {

    private WebView webView;
    private SharedPreferences prefs;

    // ===== Tarayıcı pencereleri için yerel (sistem) WebView'ler =====
    private static final Pattern NID_OK = Pattern.compile("^[A-Za-z0-9_]{1,64}$");
    private final Map<String, WebView> nViews = new java.util.concurrent.ConcurrentHashMap<>();
    /** Yerel VNC görüntüleyiciler (noVNC WebView yerine): pencere id -> VncView */
    private final Map<String, VncView> vncViews = new java.util.concurrent.ConcurrentHashMap<>();
    /** window.open() ile açılan açılır pencereler (Google/GitHub giriş popup'ları): sekme id -> kapsayıcı */
    private final Map<String, NPopup> nPop = new java.util.concurrent.ConcurrentHashMap<>();
    private final Map<String, byte[]> nSnaps = new java.util.concurrent.ConcurrentHashMap<>();
    private int nSnapSeq = 0;
    private final Map<String, boolean[]> nNav = new java.util.concurrent.ConcurrentHashMap<>();   // id -> {geri, ileri}

    // ===== Shizuku + sanal ekran (virtual display) =====
    private static final int SHIZUKU_REQ = 7001;
    private final Map<String, Boolean> nDesk = new java.util.concurrent.ConcurrentHashMap<>();   // id -> masaüstü modu
    private final java.util.Set<String> nReload = java.util.concurrent.ConcurrentHashMap.newKeySet();   // görünür olunca yenilenecekler
    private volatile String defaultUa;
    private static final Pattern CB_OK = Pattern.compile("^[A-Za-z0-9_]{1,64}$");
    private static final Pattern KEY_OK = Pattern.compile("^[A-Za-z0-9_.]+\\|[A-Za-z0-9_.$]+$");
    private FrameLayout root;
    private volatile IVdService vdSvc;
    private volatile CountDownLatch bindLatch;
    private volatile int vdDpi = 0;
    // Her Win7 penceresi (JS tarafındaki id) için ayrı bir sanal ekran + SurfaceView
    private final Map<Integer, VdWin> vdWins = new java.util.concurrent.ConcurrentHashMap<>();
    private final java.util.Set<Integer> vdDead = java.util.concurrent.ConcurrentHashMap.newKeySet();
    private String permCb;
    private static final int FILE_REQ = 9001;
    private static final int CAM_REQ = 9004;           // Kamera uygulaması: CAMERA çalışma anı izni
    private android.webkit.PermissionRequest pendingCam;   // izin sonucu bekleyen WebView kamera isteği
    private static final int HOME_REQ = 9003;          // Launcher modu: varsayılan ana ekran isteği
    private volatile boolean homeAsked = false;        // Ayarlar'dan ana ekran seçimi açıldı; dönünce durumu yenile
    private android.webkit.ValueCallback<android.net.Uri[]> fileCb;
    private final ExecutorService vdIo = Executors.newSingleThreadExecutor();
    private final ExecutorService touchIo = Executors.newSingleThreadExecutor();
    private final ExecutorService zipIo = Executors.newSingleThreadExecutor();   // Dosya Gezgini: zip ayıkla / sıkıştır (uzun sürebilir)
    private final ExecutorService fsIo = Executors.newSingleThreadExecutor();   // Dosya Gezgini: kopyala/taşı/sil/son dosyalar

    private final ServiceConnection vdConn = new ServiceConnection() {
        @Override public void onServiceConnected(ComponentName name, IBinder b) {
            vdSvc = IVdService.Stub.asInterface(b);
            CountDownLatch l = bindLatch;
            if (l != null) l.countDown();
        }
        @Override public void onServiceDisconnected(ComponentName name) {
            vdSvc = null;
            for (VdWin w : vdWins.values()) { w.opened = false; w.displayId = -1; }
        }
    };

    private final Shizuku.OnRequestPermissionResultListener permListener = (code, result) -> {
        if (code != SHIZUKU_REQ) return;
        jsCall(permCb, result == PackageManager.PERMISSION_GRANTED ? "true" : "false");
    };

    // Yüklü uygulama listesi önbelleği (başlat menüsü anında dolsun diye açılışta arka planda hazırlanır)
    private static final String ICON_HOST = "w7appicon.local";
    private static final String FRAME_HOST = "w7vdframe.local";   // sürüklerken canlı JPEG kareleri
    private static final String MEDIA_HOST = "w7media.local";     // Media Player: telefon dosyaları (video/ses/resim), Range destekli
    private final Object appLock = new Object();
    private String appsJson = null;
    private long appsTime = 0;
    private final Map<String, byte[]> iconCache = new HashMap<>();

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        getWindow().setFlags(
                WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN
        );
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            getWindow().setDecorFitsSystemWindows(false);
        }

        prefs = getSharedPreferences("w7simu_storage", Context.MODE_PRIVATE);

        webView = new WebView(this);
        root = new FrameLayout(this) {
            @Override
            public boolean dispatchTouchEvent(MotionEvent ev) {
                // Sanal fare (touchpad) açıkken parmak hareketlerini alttaki native pencereler değil, yalnızca HTML (w7vm-js) alır
                if (vcOn && !physMouse && webView != null && (ev.getSource() & InputDevice.SOURCE_MOUSE) != InputDevice.SOURCE_MOUSE) {
                    MotionEvent c = MotionEvent.obtain(ev);
                    c.offsetLocation(-webView.getLeft(), -webView.getTop());
                    boolean r = webView.dispatchTouchEvent(c);
                    c.recycle();
                    return r;
                }
                return super.dispatchTouchEvent(ev);
            }
        };
        root.addView(webView, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        setContentView(root);
        physInit();
        volInit();
        // Samsung alt çubuğu / durum çubuğu gizlenir (tam ekran, kenardan kaydırınca geçici görünür)
        hideSystemBars();
        // Sadece çentik (cutout) kadar boşluk bırak; sistem çubukları gizli olduğu için Win7 görev çubuğu en alta oturur
        root.setOnApplyWindowInsetsListener((v, ins) -> {
            int l = 0, t = 0, r = 0, b = 0;
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets i = ins.getInsets(android.view.WindowInsets.Type.displayCutout());
                l = i.left; t = i.top; r = i.right; b = i.bottom;
            } else if (Build.VERSION.SDK_INT >= 28) {
                android.view.DisplayCutout dc = ins.getDisplayCutout();
                if (dc != null) {
                    l = dc.getSafeInsetLeft(); t = dc.getSafeInsetTop();
                    r = dc.getSafeInsetRight(); b = dc.getSafeInsetBottom();
                }
            }
            lbCl = l; lbCt = t; lbCr = r; lbCb = b;
            lbApply();
            return ins;
        });
        // 16:9 kutu: boyut değişince (döndürme vb.) kenar boşlukları yeniden hesaplanır
        root.setBackgroundColor(Color.BLACK);
        root.addOnLayoutChangeListener((v, a, b2, c2, d2, oa, ob, oc, od) -> {
            if ((c2 - a) != (oc - oa) || (d2 - b2) != (od - ob)) root.post(this::lbApply);
        });
        root.requestApplyInsets();
        try { Shizuku.addRequestPermissionResultListener(permListener); } catch (Throwable ignored) { }

        WebSettings ws = webView.getSettings();
        ws.setJavaScriptEnabled(true);
        ws.setDomStorageEnabled(true);
        ws.setUseWideViewPort(true); /* Ayarlar > Ekran > Ölçek: viewport genişliğini JS değiştirebilsin */
        ws.setDatabaseEnabled(true);
        ws.setAllowFileAccess(true);
        ws.setAllowContentAccess(true);
        ws.setLoadWithOverviewMode(true);
        ws.setUseWideViewPort(true);
        ws.setMediaPlaybackRequiresUserGesture(false);
        ws.setCacheMode(WebSettings.LOAD_DEFAULT);
        ws.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                try {
                    android.net.Uri u = request.getUrl();
                    if (u != null && MEDIA_HOST.equals(u.getHost())) {
                        String mp = u.getQueryParameter("p");
                        Map<String, String> rq = request.getRequestHeaders();
                        String rg = rq == null ? null : (rq.containsKey("Range") ? rq.get("Range") : rq.get("range"));
                        return FileOps.serve(MainActivity.this, mp, rg);
                    }
                    if (u != null && FRAME_HOST.equals(u.getHost())) {
                        byte[] jpg;
                        if ("/n".equals(u.getPath())) {
                            jpg = nSnaps.get(u.getQueryParameter("k"));   // tarayıcı penceresi anlık görüntüsü
                        } else {
                            VdWin fw = vdWins.get(Integer.parseInt(u.getQueryParameter("id")));
                            jpg = fw == null ? null : awaitFrame(fw);
                        }
                        Map<String, String> fh = new HashMap<>();
                        fh.put("Access-Control-Allow-Origin", "*");
                        fh.put("Cache-Control", "no-store");
                        if (jpg != null) {
                            WebResourceResponse r = new WebResourceResponse("image/jpeg", null, new ByteArrayInputStream(jpg));
                            r.setResponseHeaders(fh);
                            return r;
                        }
                        return new WebResourceResponse("image/jpeg", null, 404, "No frame", fh, new ByteArrayInputStream(new byte[0]));
                    }
                    if (u != null && ICON_HOST.equals(u.getHost())) {
                        byte[] png = getIconPng(u.getQueryParameter("k"));
                        if (png != null) {
                            WebResourceResponse r = new WebResourceResponse("image/png", null,
                                    new ByteArrayInputStream(png));
                            Map<String, String> h = new HashMap<>();
                            h.put("Access-Control-Allow-Origin", "*");
                            h.put("Cache-Control", "max-age=600");
                            r.setResponseHeaders(h);
                            return r;
                        }
                    }
                } catch (Throwable ignored) {
                }
                return super.shouldInterceptRequest(view, request);
            }
        });
        webView.setWebChromeClient(new WebChromeClient() {
            // <input type="file"> (duvar kağıdı "Gözat...", dosya geri yükleme vb.) için dosya seçiciyi aç
            @Override
            public boolean onShowFileChooser(WebView view, android.webkit.ValueCallback<android.net.Uri[]> cb,
                                             FileChooserParams params) {
                if (fileCb != null) { try { fileCb.onReceiveValue(null); } catch (Throwable ignored) { } }
                fileCb = cb;
                try {
                    Intent i = params.createIntent();
                    startActivityForResult(i, FILE_REQ);
                } catch (Throwable t) {
                    try {
                        Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                        i.addCategory(Intent.CATEGORY_OPENABLE);
                        i.setType("*/*");
                        startActivityForResult(Intent.createChooser(i, "Dosya seç"), FILE_REQ);
                    } catch (Throwable t2) {
                        fileCb = null;
                        cb.onReceiveValue(null);
                        return false;
                    }
                }
                return true;
            }

            // Kamera uygulaması (getUserMedia): WebView izni burada verilir
            @Override
            public void onPermissionRequest(final android.webkit.PermissionRequest req) {
                runOnUiThread(() -> camPermission(req));
            }

            @Override
            public void onPermissionRequestCanceled(android.webkit.PermissionRequest req) {
                if (pendingCam == req) pendingCam = null;
            }
        });
        webView.addJavascriptInterface(new AndroidBridge(), "AndroidBridge");

        // Uygulama listesini hemen arka planda hazırla
        new Thread(() -> { try { getAppsJson(true); } catch (Throwable ignored) { } }).start();

        webView.loadUrl("file:///android_asset/index.html");
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == HOME_REQ) {
            homeChanged();
            return;
        }
        if (requestCode == FILE_REQ) {
            android.webkit.ValueCallback<android.net.Uri[]> cb = fileCb;
            fileCb = null;
            if (cb != null) {
                android.net.Uri[] res = (resultCode == RESULT_OK && data != null)
                        ? WebChromeClient.FileChooserParams.parseResult(resultCode, data) : null;
                cb.onReceiveValue(res);
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private void hideSystemBars() {
        try {
            if (Build.VERSION.SDK_INT >= 28) {
                WindowManager.LayoutParams lp = getWindow().getAttributes();
                lp.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
                getWindow().setAttributes(lp);
            }
            if (Build.VERSION.SDK_INT >= 30) {
                android.view.WindowInsetsController c = getWindow().getInsetsController();
                if (c != null) {
                    c.setSystemBarsBehavior(android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                    c.hide(android.view.WindowInsets.Type.systemBars());
                }
            } else {
                getWindow().getDecorView().setSystemUiVisibility(
                        android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                                | android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                                | android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                                | android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                                | android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                                | android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
            }
        } catch (Throwable ignored) { }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) hideSystemBars();
        if (hasFocus && physMouse) { physRetry = 0; physApply(); }   // pencere odağı geri gelince fare yakalamayı yeniden iste
    }

    @SuppressLint("NewApi")
    @Override
    public void onPointerCaptureChanged(boolean hasCapture) {
        super.onPointerCaptureChanged(hasCapture);
        physCap = hasCapture;
        physNotifyCap(hasCapture);
        if (hasCapture) { physRetry = 0; return; }
        // Sınırsız döngü olmasın: art arda en fazla 6 kez, giderek uzayan aralıkla yeniden dene
        if (physMouse && root != null && physRetry < 6) {
            physRetry++;
            root.postDelayed(this::physApply, 300L + physRetry * 400L);
        }
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
            return;
        }
        // Launcher (ana ekran) olarak çalışırken geri tuşu masaüstünü kapatmaz; ana ekranda geri tuşu normalde hiçbir şey yapmaz.
        if (isDefaultHome()) return;
        super.onBackPressed();
    }

    /**
     * Ana Sayfa tuşuna basıldığında (uygulama zaten çalışıyorsa) sistem aynı activity'ye yeni intent verir (singleTask).
     * Hiçbir tuşu engellemiyoruz: Ana Sayfa / Son Uygulamalar / Geri sistem tarafından normal işlenir.
     */
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        hideSystemBars();
    }

    /** WebView kamera isteği: yalnızca video (ses yok). Kendi sayfamız doğrudan, diğer siteler onayla. */
    private void camPermission(final android.webkit.PermissionRequest req) {
        try {
            boolean video = false;
            for (String r : req.getResources()) {
                if (android.webkit.PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(r)) video = true;
            }
            if (!video) { req.deny(); return; }
            android.net.Uri o = req.getOrigin();
            if (o != null && "file".equals(o.getScheme())) { camGrant(req); return; }
            String host = (o != null && o.getHost() != null) ? o.getHost() : "Bir site";
            new android.app.AlertDialog.Builder(this)
                    .setTitle("Kamera izni")
                    .setMessage(host + " kamerayı kullanmak istiyor. İzin verilsin mi?")
                    .setPositiveButton("İzin ver", (d, w) -> camGrant(req))
                    .setNegativeButton("Reddet", (d, w) -> req.deny())
                    .setOnCancelListener(d -> req.deny())
                    .show();
        } catch (Throwable t) {
            try { req.deny(); } catch (Throwable ignored) { }
        }
    }

    private void camGrant(android.webkit.PermissionRequest req) {
        try {
            if (Build.VERSION.SDK_INT < 23
                    || checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                req.grant(new String[]{android.webkit.PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                return;
            }
            pendingCam = req;
            requestPermissions(new String[]{android.Manifest.permission.CAMERA}, CAM_REQ);
        } catch (Throwable t) {
            try { req.deny(); } catch (Throwable ignored) { }
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        if (requestCode == CAM_REQ) {
            android.webkit.PermissionRequest r = pendingCam;
            pendingCam = null;
            if (r != null) {
                try {
                    if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                        r.grant(new String[]{android.webkit.PermissionRequest.RESOURCE_VIDEO_CAPTURE});
                    } else {
                        r.deny();
                    }
                } catch (Throwable ignored) { }
            }
            return;
        }
        if (requestCode == TERMUX_RUN_REQ) {
            boolean ok = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
            jsCall(termuxPermCb, ok ? "true" : "false");
            return;
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
    }

    /** Kamera uygulamasının çektiği fotoğrafı Resimler/UltraDroid klasörüne kaydeder. */
    private void savePhotoBytes(byte[] data, String name) throws Exception {
        if (Build.VERSION.SDK_INT >= 29) {
            ContentValues cv = new ContentValues();
            cv.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            cv.put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg");
            cv.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/UltraDroid");
            cv.put(MediaStore.MediaColumns.IS_PENDING, 1);
            android.net.Uri u = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
            if (u == null) throw new java.io.IOException("insert null");
            try (java.io.OutputStream os = getContentResolver().openOutputStream(u)) { os.write(data); }
            ContentValues done = new ContentValues();
            done.put(MediaStore.MediaColumns.IS_PENDING, 0);
            getContentResolver().update(u, done, null, null);
        } else {
            java.io.File dir = new java.io.File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "UltraDroid");
            //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
            java.io.File f = new java.io.File(dir, name);
            try (java.io.FileOutputStream fo = new java.io.FileOutputStream(f)) { fo.write(data); }
            android.media.MediaScannerConnection.scanFile(this, new String[]{f.getAbsolutePath()}, new String[]{"image/jpeg"}, null);
        }
    }

    /** Bu uygulama şu an cihazın varsayılan ana ekranı (launcher) mı? */
    private boolean isDefaultHome() {
        try {
            Intent i = new Intent(Intent.ACTION_MAIN);
            i.addCategory(Intent.CATEGORY_HOME);
            ResolveInfo ri = getPackageManager().resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY);
            if (ri != null && ri.activityInfo != null && getPackageName().equals(ri.activityInfo.packageName)) return true;
        } catch (Throwable ignored) { }
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                android.app.role.RoleManager rm = (android.app.role.RoleManager) getSystemService(Context.ROLE_SERVICE);
                if (rm != null && rm.isRoleHeld(android.app.role.RoleManager.ROLE_HOME)) return true;
            }
        } catch (Throwable ignored) { }
        return false;
    }

    /** Ayarlar sayfasına "ana ekran durumu değişmiş olabilir" haberi gönderir. */
    private void homeChanged() {
        try {
            if (webView != null) webView.evaluateJavascript("try{window.dispatchEvent(new Event('w7homechg'))}catch(e){}", null);
        } catch (Throwable ignored) { }
    }

    @Override
    protected void onDestroy() {
        flushCookies();
        volRegister(false);
        try { if (physMgr != null) physMgr.unregisterInputDeviceListener(physListener); } catch (Throwable ignored) { }
        try { Shizuku.removeRequestPermissionResultListener(permListener); } catch (Throwable ignored) { }
        try {
            if (vdSvc != null) vdSvc.closeAll();
            Shizuku.unbindUserService(userServiceArgs(), vdConn, true);
        } catch (Throwable ignored) { }
        vdIo.shutdownNow();
        touchIo.shutdownNow();
        for (String k : new java.util.ArrayList<>(vncViews.keySet())) destroyVnc(k);
        for (String k : new java.util.ArrayList<>(nViews.keySet())) destroyNative(k);
        if (webView != null) {
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }


    private List<ResolveInfo> queryLaunchers() {
        PackageManager pm = getPackageManager();
        Intent i = new Intent(Intent.ACTION_MAIN);
        i.addCategory(Intent.CATEGORY_LAUNCHER);
        return pm.queryIntentActivities(i, 0);
    }

    /** [{k:"paket|activity", n:"Ad"}, ...] — ada göre sıralı, simgesiz (simgeler ayrıca tembel yüklenir). */
    private String getAppsJson(boolean force) {
        synchronized (appLock) {
            long now = System.currentTimeMillis();
            if (!force && appsJson != null && now - appsTime < 5000) return appsJson;
            JSONArray arr = new JSONArray();
            try {
                final PackageManager pm = getPackageManager();
                List<ResolveInfo> list = queryLaunchers();
                final Map<ResolveInfo, String> names = new HashMap<>();
                for (ResolveInfo ri : list) {
                    if (getPackageName().equals(ri.activityInfo.packageName)) continue;
                    CharSequence l = ri.loadLabel(pm);
                    names.put(ri, l == null ? ri.activityInfo.packageName : l.toString());
                }
                List<ResolveInfo> sorted = new java.util.ArrayList<>(names.keySet());
                Collections.sort(sorted, new Comparator<ResolveInfo>() {
                    @Override
                    public int compare(ResolveInfo a, ResolveInfo b) {
                        return names.get(a).toLowerCase(new Locale("tr")).compareTo(names.get(b).toLowerCase(new Locale("tr")));
                    }
                });
                for (ResolveInfo ri : sorted) {
                    JSONObject o = new JSONObject();
                    o.put("k", ri.activityInfo.packageName + "|" + ri.activityInfo.name);
                    o.put("n", names.get(ri));
                    arr.put(o);
                }
            } catch (Throwable ignored) {
            }
            appsJson = arr.toString();
            appsTime = now;
            return appsJson;
        }
    }

    /** Uygulama simgesini 96x96 PNG olarak döndürür (önbellekli). */
    private byte[] getIconPng(String key) {
        if (key == null) return null;
        synchronized (iconCache) {
            byte[] c = iconCache.get(key);
            if (c != null) return c;
        }
        try {
            int bar = key.indexOf('|');
            if (bar < 0) return null;
            String pkg = key.substring(0, bar), cls = key.substring(bar + 1);
            PackageManager pm = getPackageManager();
            Drawable d = pm.getActivityIcon(new ComponentName(pkg, cls));
            int S = 96;
            Bitmap bmp = Bitmap.createBitmap(S, S, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(bmp);
            d.setBounds(0, 0, S, S);
            d.draw(cv);
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            bmp.compress(Bitmap.CompressFormat.PNG, 100, bo);
            bmp.recycle();
            byte[] out = bo.toByteArray();
            synchronized (iconCache) { iconCache.put(key, out); }
            return out;
        } catch (Throwable t) {
            return null;
        }
    }


    // =====================================================================
    //  SHIZUKU + SANAL EKRAN
    // =====================================================================

    private Shizuku.UserServiceArgs userServiceArgs() {
        return new Shizuku.UserServiceArgs(new ComponentName(getPackageName(), VdService.class.getName()))
                .daemon(false)
                .processNameSuffix("vd")
                .debuggable(true)
                .version(3); // arayüz değişti: eski süreç yeniden başlatılsın
    }

    private void jsCall(final String cb, final String json) {
        if (cb == null || !CB_OK.matcher(cb).matches()) return;
        runOnUiThread(() -> {
            if (webView == null) return;
            webView.evaluateJavascript("window['" + cb + "'] && window['" + cb + "'](" + json + ");", null);
        });
    }

    private boolean shizukuInstalled() {
        try {
            PackageInfo pi = getPackageManager().getPackageInfo("moe.shizuku.privileged.api", 0);
            return pi != null;
        } catch (Throwable t) {
            return false;
        }
    }

    private boolean pkgInstalled(String pkg) {
        try {
            PackageInfo pi = getPackageManager().getPackageInfo(pkg, 0);
            return pi != null;
        } catch (Throwable t) {
            return false;
        }
    }

    // ===== Termux RUN_COMMAND =====
    private static final int TERMUX_RUN_REQ = 7002;
    private static final String PERM_TERMUX_RUN = "com.termux.permission.RUN_COMMAND";
    private static final String TERMUX_PREFIX = "/data/data/com.termux/files/";
    private static final String TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash";
    private static final String TERMUX_HOME = "/data/data/com.termux/files/home";
    private static final int TERMUX_OUT_MAX = 20000;
    private final java.util.concurrent.atomic.AtomicInteger termuxSeq = new java.util.concurrent.atomic.AtomicInteger(0);
    private final Handler termuxH = new Handler(android.os.Looper.getMainLooper());
    private String termuxPermCb;

    private boolean hasTermuxRunPerm() {
        try {
            return Build.VERSION.SDK_INT < 23
                    || checkSelfPermission(PERM_TERMUX_RUN) == PackageManager.PERMISSION_GRANTED;
        } catch (Throwable t) {
            return false;
        }
    }

    private static String termuxErr(String code, String msg) {
        try {
            JSONObject o = new JSONObject();
            o.put("ok", false);
            o.put("err", code);
            o.put("errmsg", msg == null ? "" : msg);
            return o.toString();
        } catch (Throwable t) {
            return "{\"ok\":false,\"err\":\"" + code + "\"}";
        }
    }

    private static String clip(String x) {
        if (x == null) return "";
        return x.length() > TERMUX_OUT_MAX ? x.substring(0, TERMUX_OUT_MAX) : x;
    }

    /**
     * Termux'ta komut çalıştırır (RUN_COMMAND). background=true ise çıktı/çıkış kodu cb'ye döner:
     * {ok, exitCode, stdout, stderr, err, errmsg}. background=false ise Termux oturumu açılır ve
     * cb hemen {ok:true, started:true} ile çağrılır.
     * Gerekenler: Termux kurulu + bir kez açılmış, ~/.termux/termux.properties içinde
     * allow-external-apps=true, ve com.termux.permission.RUN_COMMAND izni.
     */
    private void termuxExec(final String path, final String[] args, final String workdir,
                            final boolean bg, final int session, final String cb) {
        try {
            if (!pkgInstalled("com.termux")) { jsCall(cb, termuxErr("termux_missing", "Termux kurulu değil")); return; }
            if (!hasTermuxRunPerm()) { jsCall(cb, termuxErr("no_permission", "RUN_COMMAND izni verilmemiş")); return; }

            final Intent i = new Intent("com.termux.RUN_COMMAND");
            i.setClassName("com.termux", "com.termux.app.RunCommandService");
            i.putExtra("com.termux.RUN_COMMAND_PATH", path);
            i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", args);
            i.putExtra("com.termux.RUN_COMMAND_WORKDIR", workdir);
            i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", bg);
            i.putExtra("com.termux.RUN_COMMAND_SESSION_ACTION", String.valueOf(session));

            final boolean wantResult = bg && cb != null && CB_OK.matcher(cb).matches();
            if (wantResult) {
                final String action = "com.ultradroid.app.TERMUX_RESULT." + termuxSeq.incrementAndGet();
                final BroadcastReceiver rx = new BroadcastReceiver() {
                    @Override public void onReceive(Context c, Intent in) {
                        try { unregisterReceiver(this); } catch (Throwable ignored) { }
                        try {
                            Bundle r = in.getBundleExtra("result");
                            JSONObject o = new JSONObject();
                            if (r == null) {
                                jsCall(cb, termuxErr("no_result", "Termux sonuç döndürmedi"));
                                return;
                            }
                            int exit = r.getInt("exitCode", -1);
                            int err = r.getInt("err", -1);
                            o.put("exitCode", exit);
                            o.put("stdout", clip(r.getString("stdout", "")));
                            o.put("stderr", clip(r.getString("stderr", "")));
                            o.put("err", err);
                            o.put("errmsg", r.getString("errmsg", ""));
                            o.put("ok", exit == 0 && (err == -1 || err == 0));
                            jsCall(cb, o.toString());
                        } catch (Throwable t) {
                            jsCall(cb, termuxErr("parse_error", String.valueOf(t.getMessage())));
                        }
                    }
                };
                final IntentFilter f = new IntentFilter(action);
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(rx, f, Context.RECEIVER_NOT_EXPORTED);
                else registerReceiver(rx, f);

                Intent ri = new Intent(action);
                ri.setPackage(getPackageName());
                int flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT;
                if (Build.VERSION.SDK_INT >= 31) flags |= android.app.PendingIntent.FLAG_MUTABLE;
                android.app.PendingIntent pi = android.app.PendingIntent.getBroadcast(
                        this, termuxSeq.get(), ri, flags);
                i.putExtra("com.termux.RUN_COMMAND_PENDING_INTENT", pi);

                // Sonuç hiç gelmezse alıcıyı 5 dakika sonra bırak
                termuxH.postDelayed(() -> {
                    try { unregisterReceiver(rx); } catch (Throwable ignored) { }
                }, 5 * 60 * 1000L);
            }

            if (Build.VERSION.SDK_INT >= 26) startForegroundService(i); else startService(i);
            if (!wantResult && cb != null) jsCall(cb, "{\"ok\":true,\"started\":true}");
        } catch (SecurityException se) {
            jsCall(cb, termuxErr("no_permission", "Güvenlik hatası: RUN_COMMAND izni/allow-external-apps"));
        } catch (Throwable t) {
            jsCall(cb, termuxErr("exec_error", String.valueOf(t.getMessage())));
        }
    }

    private boolean shizukuRunning() {
        try { return Shizuku.pingBinder(); } catch (Throwable t) { return false; }
    }

    private boolean shizukuGranted() {
        try {
            return shizukuRunning() && !Shizuku.isPreV11()
                    && Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED;
        } catch (Throwable t) {
            return false;
        }
    }

    /** UI iş parçacığı DIŞINDA çağrılmalı: servis bağlanana kadar bekler. */
    private boolean ensureService() {
        try {
            IBinder b = vdSvc != null ? vdSvc.asBinder() : null;
            if (b != null && b.pingBinder()) return true;
            vdSvc = null;
            final CountDownLatch l = new CountDownLatch(1);
            bindLatch = l;
            runOnUiThread(() -> {
                try { Shizuku.bindUserService(userServiceArgs(), vdConn); } catch (Throwable ignored) { }
            });
            return l.await(12, TimeUnit.SECONDS) && vdSvc != null;
        } catch (Throwable t) {
            return false;
        }
    }

    private int displayDpi() {
        return vdDpi > 0 ? vdDpi : getResources().getDisplayMetrics().densityDpi;
    }


    // ------------------------------------------------------------ Canlı JPEG kare modu (sürükleme/boyutlandırma)

    /** İstemcinin (WebView) bir sonraki karesini bekler; en fazla 250 ms. Yeni kare yoksa son kareyi tekrar verir. */
    private byte[] awaitFrame(VdWin win) {
        synchronized (win.frameLock) {
            long end = SystemClock.uptimeMillis() + 250;
            while (win.frameSeq == win.servedSeq && win.live) {
                long left = end - SystemClock.uptimeMillis();
                if (left <= 0) break;
                try { win.frameLock.wait(left); } catch (InterruptedException e) { break; }
            }
            win.servedSeq = win.frameSeq;
            return win.frame;
        }
    }

    private void publishFrame(VdWin win, byte[] jpg) {
        synchronized (win.frameLock) {
            win.frame = jpg;
            win.frameSeq++;
            win.frameLock.notifyAll();
        }
    }

    /** Bitmap'i uzun kenarı en çok 960 px olacak şekilde küçültüp JPEG'e çevirir. */
    private byte[] encodeJpeg(Bitmap src) {
        int w = src.getWidth(), h = src.getHeight();
        float sc = Math.min(1f, 960f / Math.max(w, h));
        Bitmap out = src;
        if (sc < 1f) out = Bitmap.createScaledBitmap(src, Math.max(2, Math.round(w * sc)), Math.max(2, Math.round(h * sc)), true);
        ByteArrayOutputStream bo = new ByteArrayOutputStream(64 * 1024);
        out.compress(Bitmap.CompressFormat.JPEG, 62, bo);
        if (out != src) out.recycle();
        return bo.toByteArray();
    }

    /** liveH iş parçacığında: yeniden kullanılan bitmap'leri serbest bırakır. */
    private void freeLiveBitmaps(VdWin win) {
        if (win.fullBmp != null) { try { win.fullBmp.recycle(); } catch (Throwable ignored) { } win.fullBmp = null; }
        if (win.outBmp != null) { try { win.outBmp.recycle(); } catch (Throwable ignored) { } win.outBmp = null; }
    }

    /** liveH iş parçacığı: ImageReader'dan gelen kareyi (bitmap'ler yeniden kullanılarak) JPEG'e çevirir. */
    private void encodeReaderFrame(VdWin win, ImageReader rd) {
        Image img = null;
        try {
            img = rd.acquireLatestImage();
            if (img == null) return;
            long now = SystemClock.uptimeMillis();
            if (now - win.lastEnc < 33) return;   // en çok ~30 kare/sn
            win.lastEnc = now;
            if (!win.live) return;
            Image.Plane pl = img.getPlanes()[0];
            int px = pl.getPixelStride(), rs = pl.getRowStride();
            int iw = img.getWidth(), ih = img.getHeight();
            int bw = rs / px;
            if (win.fullBmp == null || win.fullBmp.getWidth() != bw || win.fullBmp.getHeight() != ih) {
                if (win.fullBmp != null) win.fullBmp.recycle();
                win.fullBmp = Bitmap.createBitmap(bw, ih, Bitmap.Config.ARGB_8888);
            }
            ByteBuffer buf = pl.getBuffer();
            buf.rewind();
            win.fullBmp.copyPixelsFromBuffer(buf);
            float sc = Math.min(1f, 960f / Math.max(iw, ih));
            int ow = Math.max(2, Math.round(iw * sc)), oh = Math.max(2, Math.round(ih * sc));
            if (win.outBmp == null || win.outBmp.getWidth() != ow || win.outBmp.getHeight() != oh) {
                if (win.outBmp != null) win.outBmp.recycle();
                win.outBmp = Bitmap.createBitmap(ow, oh, Bitmap.Config.ARGB_8888);
            }
            Canvas c = new Canvas(win.outBmp);
            win.srcR.set(0, 0, iw, ih);
            win.dstR.set(0, 0, ow, oh);
            c.drawBitmap(win.fullBmp, win.srcR, win.dstR, win.pnt);
            win.jbo.reset();
            win.outBmp.compress(Bitmap.CompressFormat.JPEG, 62, win.jbo);
            if (win.live) publishFrame(win, win.jbo.toByteArray());
        } catch (Throwable ignored) {
        } finally {
            if (img != null) { try { img.close(); } catch (Throwable ignored) { } }
        }
    }

    /** UI iş parçacığı. Önce anlık görüntü (PixelCopy), sonra sanal ekranı ImageReader'a bağlar. */
    private void startLive(final VdWin win) {
        if (win.live) return;
        final int w = win.w, h = win.h, did = win.displayId;
        if (w < 8 || h < 8 || did < 0 || w > 4096 || h > 4096) return;
        if (win.view == null || !win.view.getHolder().getSurface().isValid()) return;
        win.live = true;
        if (win.liveT == null) {
            win.liveT = new HandlerThread("w7-live-" + win.id);
            win.liveT.start();
            win.liveH = new Handler(win.liveT.getLooper());
        }
        final Handler lh = win.liveH;
        final Runnable attach = () -> vdIo.execute(() -> {
            ImageReader r = null;
            try {
                if (!win.live || vdSvc == null || lh == null) return;
                r = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2);
                final ImageReader fr = r;
                r.setOnImageAvailableListener(rd -> encodeReaderFrame(win, rd), lh);
                win.reader = r;
                vdSvc.resize(did, r.getSurface(), w, h, displayDpi());
                if (!win.live) {   // bu sırada bırakıldıysa hemen geri çevir (stopLive'ın işi de arkadan gelir)
                    win.reader = null;
                    try { fr.setOnImageAvailableListener(null, null); fr.close(); } catch (Throwable ignored) { }
                }
            } catch (Throwable t) {
                if (r != null) { win.reader = null; try { r.setOnImageAvailableListener(null, null); r.close(); } catch (Throwable ignored) { } }
            }
        });
        try {
            final Bitmap snap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
            PixelCopy.request(win.view, snap, res -> {
                try { if (res == PixelCopy.SUCCESS && win.live) publishFrame(win, encodeJpeg(snap)); } catch (Throwable ignored) { }
                try { snap.recycle(); } catch (Throwable ignored) { }
                attach.run();
            }, lh);
        } catch (Throwable t) {
            attach.run();
        }
    }

    /** UI iş parçacığı. Sanal ekranı SurfaceView'e geri bağlar, ImageReader'ı kapatır. */
    private void stopLive(final VdWin win) {
        if (!win.live) return;
        win.live = false;
        synchronized (win.frameLock) { win.frameLock.notifyAll(); }
        final int w = win.view.getWidth() >= 8 ? win.view.getWidth() : win.w;
        final int h = win.view.getHeight() >= 8 ? win.view.getHeight() : win.h;
        final int did = win.displayId;
        win.w = w; win.h = h;
        if (win.liveH != null) win.liveH.post(() -> freeLiveBitmaps(win));
        vdIo.execute(() -> {
            // reader, çalışma anında okunur: attach henüz bitmemiş olsa bile sızıntı olmaz
            ImageReader r = win.reader;
            win.reader = null;
            try {
                Surface sf = win.view.getHolder().getSurface();
                if (vdSvc != null && did >= 0 && sf.isValid()) vdSvc.resize(did, sf, w, h, displayDpi());
            } catch (Throwable ignored) { }
            if (r != null) { try { r.setOnImageAvailableListener(null, null); r.close(); } catch (Throwable ignored) { } }
        });
    }

    private void releaseLive(VdWin win) {
        win.live = false;
        synchronized (win.frameLock) { win.frameLock.notifyAll(); }
        ImageReader r = win.reader; win.reader = null;
        if (r != null) { try { r.setOnImageAvailableListener(null, null); r.close(); } catch (Throwable ignored) { } }
        HandlerThread t = win.liveT; Handler hh = win.liveH;
        win.liveT = null; win.liveH = null;
        if (t != null) {
            if (hh != null) hh.post(() -> freeLiveBitmaps(win));
            t.quitSafely();
        }
    }

    // ------------------------------------------------------------ Yerel WebView'ler (Chrome / IE / Nova pencereleri)

    private static boolean httpUrl(String u) {
        return u != null && (u.startsWith("http://") || u.startsWith("https://"));
    }

    /** Linux uygulama pencerelerinin noVNC sayfası (127.0.0.1/vnc.html): tarayıcıdan farklı, ayrı bir WebView profili kullanır. */
    private final java.util.Set<String> nVnc = new java.util.HashSet<>();
    private static boolean isVncUrl(String u) {
        return u != null && u.startsWith("http://127.0.0.1:") && u.contains("/vnc.html");
    }

    /** noVNC için sade WebView: masaüstü UA/1280 viewport/yakınlaştırma/popup yok, siyah zemin, yüksek öncelikli renderer. */
    private void applyVnc(WebView wv) {
        WebSettings s = wv.getSettings();
        s.setUseWideViewPort(false);
        s.setLoadWithOverviewMode(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setDisplayZoomControls(false);
        s.setSupportMultipleWindows(false);
        s.setJavaScriptCanOpenWindowsAutomatically(false);
        s.setTextZoom(100);
        wv.setInitialScale(0);
        wv.setBackgroundColor(Color.BLACK);
        wv.setOverScrollMode(android.view.View.OVER_SCROLL_NEVER);
        wv.setLayerType(android.view.View.LAYER_TYPE_HARDWARE, null);
        try {
            if (android.os.Build.VERSION.SDK_INT >= 26) wv.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false);
        } catch (Throwable ignored) { }
    }

    /** Ana sayfaya (HTML) gezinme bildirimi: adres çubuğunu güncellemek için. */
    private void notifyUrl(final String id, final WebView wv, final String url) {
        pushNav(id, wv, url);
        // geri/ileri listesi sayfa geçişinde bir an eski kalabiliyor: kısa süre sonra bir kez daha oku
        wv.postDelayed(() -> { if (nViews.get(id) == wv) pushNav(id, wv, wv.getUrl() != null ? wv.getUrl() : url); }, 350);
    }

    private void pushNav(String id, WebView wv, String url) {
        if (webView == null || url == null) return;
        boolean b = wv.canGoBack(), f = wv.canGoForward();
        nNav.put(id, new boolean[]{b, f});
        webView.evaluateJavascript("window.__w7url&&window.__w7url(" + JSONObject.quote(id) + "," + JSONObject.quote(url) + "," + b + "," + f + ");", null);
    }

    /** Sayfa başlığı + simge (favicon) bilgisini ana sayfadaki Chrome sekmesine bildirir. */
    private void notifyMeta(String id, String url, String title, String icon) {
        if (webView == null) return;
        String ch = faviconCache.get(hostOf(url));
        if (ch != null) icon = ch;   // WebView'in verdiği (veya daha önce alınan) favicon her zaman uzak adresten güvenilirdir
        webView.evaluateJavascript("window.__w7meta&&window.__w7meta(" + JSONObject.quote(id) + ","
                + JSONObject.quote(url == null ? "" : url) + ","
                + JSONObject.quote(title == null ? "" : title) + ","
                + JSONObject.quote(icon == null ? "" : icon) + ");", null);
    }

    /** host -> favicon (data:image/png;base64,...). En çok 64 site. */
    private final java.util.Map<String, String> faviconCache = java.util.Collections.synchronizedMap(
            new java.util.LinkedHashMap<String, String>(32, 0.75f, true) {
                @Override
                protected boolean removeEldestEntry(java.util.Map.Entry<String, String> e) { return size() > 64; }
            });

    private static String hostOf(String url) {
        try { return url == null ? null : android.net.Uri.parse(url).getHost(); } catch (Throwable t) { return null; }
    }

    private static String iconData(Bitmap b) {
        try {
            Bitmap s = Bitmap.createScaledBitmap(b, 32, 32, true);
            java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            s.compress(Bitmap.CompressFormat.PNG, 100, bo);
            return "data:image/png;base64," + android.util.Base64.encodeToString(bo.toByteArray(), android.util.Base64.NO_WRAP);
        } catch (Throwable t) {
            return null;
        }
    }

    /** Sayfadaki başlığı ve en uygun favicon adresini okur (WebView'e JS köprüsü eklenmez; sonuç evaluateJavascript ile döner). */
    private static final String META_JS = "(function(){try{var best='',bs=-1,l=document.querySelectorAll('link[rel*=\"icon\" i]');"
            + "for(var i=0;i<l.length;i++){var h=l[i].href;if(!h||/^data:/i.test(h)&&h.length>20000)continue;"
            + "var m=/(\\d+)x/.exec(l[i].getAttribute('sizes')||'');var z=m?+m[1]:16;if(z>64)z=64-(z-64)/100;"
            + "if(/apple/i.test(l[i].rel))z=Math.min(z,48);if(z>bs){bs=z;best=h;}}"
            + "if(!best&&location.protocol.indexOf('http')===0)best=location.origin+'/favicon.ico';"
            + "return {t:document.title||'',i:best,u:location.href};}catch(e){return null;}})()";

    private void pullMeta(final String id, final WebView view) {
        view.evaluateJavascript(META_JS, value -> {
            try {
                if (value == null || value.equals("null")) return;
                JSONObject o = new JSONObject(value);
                notifyMeta(id, o.optString("u", view.getUrl()), o.optString("t", ""), o.optString("i", ""));
            } catch (Throwable ignored) { }
        });
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void createNative(final String id, String url) {
        if (isNativeVnc(url)) {
            if (nViews.containsKey(id)) destroyNative(id);
            if (!vncViews.containsKey(id)) createVnc(id, url);
            return;
        }
        if (vncViews.containsKey(id)) destroyVnc(id);
        if (nViews.containsKey(id)) { navigateNative(id, url); return; }
        final WebView wv = new NWebView(this, id);
        final boolean vnc = isVncUrl(url);
        if (vnc) nVnc.add(id);
        WebSettings s = wv.getSettings();
        if (defaultUa == null) defaultUa = s.getUserAgentString();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        s.setSupportMultipleWindows(true);                 // window.open() giriş penceleri (OAuth popup) çalışsın
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setSupportZoom(true);
        s.setBuiltInZoomControls(true);
        s.setDisplayZoomControls(false);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        try { android.webkit.CookieManager.getInstance().setAcceptCookie(true); } catch (Throwable ignored) { }
        try { android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true); } catch (Throwable ignored) { }
        wv.setBackgroundColor(Color.WHITE);
        if (vnc) applyVnc(wv); else applyDesktop(wv, true);   // tarayıcı: masaüstü sitesi; noVNC: sade profil
        // NOT: bu WebView'lere addJavascriptInterface EKLENMEZ; uzak siteler AndroidBridge'e erişemez.
        wv.setWebViewClient(new WebViewClient() {
            /** Dosya Gezgini'nden açılan HTML dosyaları: https://w7media.local/h/<anahtar>/<dosya> (yalnızca bu yol; geri kalanı 404). */
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                try {
                    android.net.Uri u = request.getUrl();
                    if (u != null && MEDIA_HOST.equals(u.getHost())) {
                        String ep = u.getEncodedPath();
                        if (ep != null && ep.startsWith("/h/")) {
                            Map<String, String> rq = request.getRequestHeaders();
                            String rg = rq == null ? null : (rq.containsKey("Range") ? rq.get("Range") : rq.get("range"));
                            return FileOps.serveWeb(MainActivity.this, ep, rg);
                        }
                        return FileOps.serveWeb(MainActivity.this, null, null);   // 404
                    }
                } catch (Throwable ignored) {
                }
                return super.shouldInterceptRequest(view, request);
            }
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                android.net.Uri u = request.getUrl();
                String sc = u == null ? null : u.getScheme();
                if ("http".equals(sc) || "https".equals(sc)) return false;   // aynı pencerede yükle
                if ("mailto".equals(sc) || "tel".equals(sc)) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Throwable ignored) { }
                }
                return true;   // diğer şemalar (intent:, market: ...) engellenir
            }
            @Override
            public void doUpdateVisitedHistory(WebView view, String u, boolean isReload) {
                if (!vnc) notifyUrl(id, view, u);
            }
            @Override
            public void onPageStarted(WebView view, String u, Bitmap fav) {
                if (!vnc) view.evaluateJavascript(DESK_JS, null);
                NPopup pp = nPop.get(id);
                if (pp != null && pp.decided) {   // sekme başka sayfaya geçti: giriş penceresi değilse üstte kalmasın
                    String pu = pp.web.getUrl();
                    if (pu == null || !isAuthUrl(pu)) closePopup(id);
                }
            }
            @Override
            public void onPageCommitVisible(WebView view, String u) {
                if (!vnc) view.evaluateJavascript(DESK_JS, null);
            }
            @Override
            public void onPageFinished(WebView view, String u) {
                if (!vnc) view.evaluateJavascript(DESK_JS, null);
                if (!vnc) notifyUrl(id, view, u);   // geri/ileri durumu sayfa bitince de güncellensin
                if (!vnc) pullMeta(id, view);       // başlık + favicon -> Chrome sekmesi
                if (!vnc) flushCookies();           // giriş çerezleri diske yazılsın (uygulama kapanınca oturum gitmesin)
            }
        });
        wv.setWebChromeClient(popupChromeClient(id, true));
        wv.setDownloadListener((du, ua, cd, mime, len) -> handleDownload(wv, du, ua, cd, mime));
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        root.addView(wv, lp);
        wv.setTranslationX(-20000);   // ilk setRect2'ye kadar ekran dışında bekler
        nViews.put(id, wv);
        wv.loadUrl(url);
    }

    /** Tarayıcı penceresi WebView'i. Görev çubuğu vb. altına kırpılan bölgeye yapılan dokunmaları geçirir. */
    private class NWebView extends WebView {
        final String nid;
        NWebView(Context c, String nid) { super(c); this.nid = nid; }
        @SuppressLint("NewApi")
        @Override
        public boolean onCapturedPointerEvent(MotionEvent ev) { return physCaptured(ev) || super.onCapturedPointerEvent(ev); }
        @Override
        public boolean dispatchTouchEvent(MotionEvent ev) {
            if (ev.getActionMasked() == MotionEvent.ACTION_DOWN) {
                Rect c = getClipBounds();
                if (c != null && !c.contains((int) ev.getX(), (int) ev.getY())) return false;
            }
            return super.dispatchTouchEvent(ev);
        }
    }

    /** Masaüstü modunda sayfanın viewport'unu 1280 px'e sabitler (mobil düzene dönmesin). */
    private static final String DESK_JS = "(function(){try{if(window.__w7dv)return;window.__w7dv=1;"
            + "var f=function(){var m=document.querySelector('meta[name=viewport]');"
            + "if(!m){if(!document.head)return;m=document.createElement('meta');m.name='viewport';document.head.appendChild(m);}"
            + "if(m.getAttribute('content')!=='width=1280')m.setAttribute('content','width=1280');};"
            + "f();new MutationObserver(f).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['content']});"
            + "}catch(e){}})();";

    /** Gerçek masaüstü Chrome'un gönderdiği "azaltılmış" User-Agent (Chrome/MAJOR.0.0.0). */
    private String desktopUa() {
        return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/" + chromeMajor() + ".0.0.0 Safari/537.36";
    }

    private String chromeFull() {
        String d = defaultUa == null ? "" : defaultUa;
        Matcher m = Pattern.compile("Chrome/([\\d.]+)").matcher(d);
        return m.find() ? m.group(1) : "120.0.0.0";
    }

    private String chromeMajor() {
        String f = chromeFull();
        int i = f.indexOf('.');
        return i > 0 ? f.substring(0, i) : f;
    }

    /**
     * Google "Bu tarayıcı veya uygulama güvenli olmayabilir / tarayıcınızı güncelleyin" uyarısı üç şeye bakar:
     * (1) User-Agent'taki "; wv" / "Version/4.0" (yukarıda temizlendi),
     * (2) "X-Requested-With: com.ultradroid.app" başlığı (WebView her istekte yollar) -> kaldırılır,
     * (3) Sec-CH-UA ipuçları: "Android WebView" markası + mobil + Android platformu -> Linux masaüstü Google Chrome olarak değiştirilir.
     * Bu özellikler yeni WebView sürümü ister (111+ / 124+); desteklemeyen cihazda sessizce atlanır.
     */
    private void hardenForGoogle(WebView wv) {
        WebSettings s = wv.getSettings();
        try {
            if (androidx.webkit.WebViewFeature.isFeatureSupported(androidx.webkit.WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST)) {
                androidx.webkit.WebSettingsCompat.setRequestedWithHeaderOriginAllowList(s, new java.util.HashSet<String>());
            }
        } catch (Throwable ignored) { }
        try {
            if (androidx.webkit.WebViewFeature.isFeatureSupported(androidx.webkit.WebViewFeature.USER_AGENT_METADATA)) {
                String major = chromeMajor(), full = chromeFull();
                java.util.List<androidx.webkit.UserAgentMetadata.BrandVersion> br = new java.util.ArrayList<>();
                br.add(new androidx.webkit.UserAgentMetadata.BrandVersion.Builder().setBrand("Not_A Brand").setMajorVersion("8").setFullVersion("8.0.0.0").build());
                br.add(new androidx.webkit.UserAgentMetadata.BrandVersion.Builder().setBrand("Chromium").setMajorVersion(major).setFullVersion(full).build());
                br.add(new androidx.webkit.UserAgentMetadata.BrandVersion.Builder().setBrand("Google Chrome").setMajorVersion(major).setFullVersion(full).build());
                androidx.webkit.UserAgentMetadata md = new androidx.webkit.UserAgentMetadata.Builder()
                        .setBrandVersionList(br)
                        .setFullVersion(full)
                        .setPlatform("Linux")
                        .setPlatformVersion("6.5.0")
                        .setMobile(false)
                        .setModel("")
                        .setArchitecture("x86")
                        .setBitness(64)
                        .setWow64(false)
                        .build();
                androidx.webkit.WebSettingsCompat.setUserAgentMetadata(s, md);
            }
        } catch (Throwable ignored) { }
        // (4) Sayfa JS'i: WebView'de eksik olan window.chrome nesnesi ve platform tutarsızlığı (Google JS ile kontrol eder)
        try {
            if (androidx.webkit.WebViewFeature.isFeatureSupported(androidx.webkit.WebViewFeature.DOCUMENT_START_SCRIPT)) {
                androidx.webkit.WebViewCompat.addDocumentStartJavaScript(wv, CHROME_JS,
                        new java.util.HashSet<String>(java.util.Arrays.asList("*")));
            }
        } catch (Throwable ignored) { }
    }

    /** Gerçek masaüstü Chrome gibi görünmek için sayfa başlamadan çalışan betik (tekrar çalışırsa kendini atlar). */
    private static final String CHROME_JS = "(function(){try{if(window.__w7cj)return;window.__w7cj=1;"
            + "if(!window.chrome)window.chrome={};var c=window.chrome;"
            + "if(!c.app)c.app={isInstalled:false,InstallState:{DISABLED:'disabled',INSTALLED:'installed',NOT_INSTALLED:'not_installed'},RunningState:{CANNOT_RUN:'cannot_run',READY_TO_RUN:'ready_to_run',RUNNING:'running'}};"
            + "if(!c.loadTimes)c.loadTimes=function(){return{}};"
            + "if(!c.csi)c.csi=function(){return{}};"
            + "try{Object.defineProperty(navigator,'platform',{get:function(){return 'Linux x86_64'},configurable:true});}catch(e){}"
            + "}catch(e){}})();";

    /** Çerezleri diske yazar. WebView bunu kendi başına geç yapar; uygulama kapanırsa giriş oturumu kaybolurdu. */
    private void flushCookies() {
        try { android.webkit.CookieManager.getInstance().flush(); } catch (Throwable ignored) { }
    }

    // ---- window.open() popup'ları (Google ile giriş, GitHub OAuth vb.) ----

    /** Popup WebView + sağ üstte kapat (✕) düğmesi. Üst sekmenin konumunu/kırpmasını izler. */
    private class NPopup extends FrameLayout {
        final WebView web;
        boolean decided;   // popup'ın ilk adresi görüldü mü (sıradan bağlantı -> sekmede aç, giriş penceresi -> göster)
        boolean gesture;   // kullanıcı dokunuşuyla mı açıldı
        NPopup(Context c, WebView web) { super(c); this.web = web; }
        @Override
        public boolean dispatchTouchEvent(MotionEvent ev) {
            if (ev.getActionMasked() == MotionEvent.ACTION_DOWN) {
                Rect cb = getClipBounds();
                if (cb != null && !cb.contains((int) ev.getX(), (int) ev.getY())) return false;
            }
            return super.dispatchTouchEvent(ev);
        }
    }

    private WebChromeClient popupChromeClient(final String id) { return popupChromeClient(id, false); }

    private WebChromeClient popupChromeClient(final String id, final boolean main) {
        return new WebChromeClient() {
            /** Sayfa başlığı değişince (SPA dahil) Chrome sekmesine bildir. */
            @Override
            public void onReceivedTitle(WebView view, String title) {
                if (main) notifyMeta(id, view.getUrl(), title, null);
            }
            @Override
            public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, android.os.Message resultMsg) {
                return openPopup(id, resultMsg, isUserGesture);
            }
            /** WebView'in kendi bulduğu favicon: küçük PNG (data:) olarak sekmeye gönderilir (hotlink/CORS/hız sınırı derdi yok). */
            @Override
            public void onReceivedIcon(WebView view, Bitmap icon) {
                if (!main || icon == null) return;
                String d = iconData(icon);
                if (d == null) return;
                String u = view.getUrl();
                String h = hostOf(u);
                if (h != null) faviconCache.put(h, d);
                notifyMeta(id, u, null, d);
            }
            @Override
            public void onCloseWindow(WebView window) { closePopup(id); }
            // Tarayıcı pencerelerinde (Chrome / Nova / IE) <input type="file"> ve "Dosya yükle" düğmeleri için dosya seçici
            @Override
            public boolean onShowFileChooser(WebView view, android.webkit.ValueCallback<android.net.Uri[]> cb,
                                             FileChooserParams params) {
                return showFileChooser(cb, params);
            }
        };
    }

    /** Web sayfasından gelen dosya seçme isteğini sistemin dosya seçicisiyle karşılar (çoklu seçim ve dosya türü desteklenir). */
    private boolean showFileChooser(android.webkit.ValueCallback<android.net.Uri[]> cb, WebChromeClient.FileChooserParams params) {
        if (fileCb != null) { try { fileCb.onReceiveValue(null); } catch (Throwable ignored) { } }
        fileCb = cb;
        try {
            startActivityForResult(params.createIntent(), FILE_REQ);
        } catch (Throwable t) {
            try {
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params != null && params.getMode() == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE);
                startActivityForResult(Intent.createChooser(i, "Dosya seç"), FILE_REQ);
            } catch (Throwable t2) {
                fileCb = null;
                cb.onReceiveValue(null);
                return false;
            }
        }
        return true;
    }

    @SuppressLint({"SetJavaScriptEnabled", "SetTextI18n"})
    private boolean openPopup(final String id, android.os.Message resultMsg, final boolean userGesture) {
        WebView parent = nViews.get(id);
        if (parent == null || resultMsg == null || !(resultMsg.obj instanceof WebView.WebViewTransport)) return false;
        closePopup(id);   // aynı anda tek popup
        final WebView pw = new NWebView(this, id);
        WebSettings s = pw.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportMultipleWindows(true);
        s.setJavaScriptCanOpenWindowsAutomatically(true);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        try { android.webkit.CookieManager.getInstance().setAcceptThirdPartyCookies(pw, true); } catch (Throwable ignored) { }
        pw.setBackgroundColor(Color.WHITE);
        applyDesktop(pw, true);
        final NPopup box = new NPopup(this, pw);
        box.gesture = userGesture;
        box.setVisibility(View.INVISIBLE);   // ilk adres görülene kadar gizli: sıradan bağlantılar sekmede açılır, üstte çarpılı katman kalmaz
        pw.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                android.net.Uri u = request.getUrl();
                String sc = u == null ? null : u.getScheme();
                if (!("http".equals(sc) || "https".equals(sc))) return true;
                return routePopup(id, box, u.toString());
            }
            @Override
            public void onPageStarted(WebView view, String u, Bitmap fav) {
                if (routePopup(id, box, u)) view.stopLoading();
            }
            @Override
            public void onPageFinished(WebView view, String u) { flushCookies(); }
        });
        pw.setWebChromeClient(popupChromeClient(id));
        // adres hiç gelmezse (window.open('') + document.write): dokunuşla açıldıysa göster, değilse kapat
        root.postDelayed(() -> {
            if (nPop.get(id) != box || box.decided) return;
            box.decided = true;
            if (box.gesture) box.setVisibility(View.VISIBLE); else closePopup(id);
        }, 3500);
        box.addView(pw, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        android.widget.TextView x = new android.widget.TextView(this);
        x.setText("✕");
        x.setTextColor(Color.WHITE);
        x.setTextSize(18);
        x.setGravity(Gravity.CENTER);
        x.setBackgroundColor(0xCC444444);
        x.setOnClickListener(v -> closePopup(id));
        int sz = (int) (44 * getResources().getDisplayMetrics().density);
        FrameLayout.LayoutParams xl = new FrameLayout.LayoutParams(sz, sz);
        xl.gravity = Gravity.TOP | Gravity.RIGHT;
        box.addView(x, xl);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        root.addView(box, lp);
        nPop.put(id, box);
        syncPopup(id);
        ((WebView.WebViewTransport) resultMsg.obj).setWebView(pw);
        resultMsg.sendToTarget();
        return true;
    }

    /** Popup'ı üst sekmenin gövdesiyle aynı yere / boyuta oturtur. */
    private void syncPopup(String id) {
        NPopup box = nPop.get(id);
        WebView wv = nViews.get(id);
        if (box == null || wv == null) return;
        FrameLayout.LayoutParams p = (FrameLayout.LayoutParams) wv.getLayoutParams();
        FrameLayout.LayoutParams q = (FrameLayout.LayoutParams) box.getLayoutParams();
        if (q.width != p.width || q.height != p.height) { q.width = p.width; q.height = p.height; box.setLayoutParams(q); }
        box.setTranslationX(wv.getTranslationX());
        box.setTranslationY(wv.getTranslationY());
        Rect cb = wv.getClipBounds();
        box.setClipBounds(cb == null ? null : new Rect(cb));
    }

    /**
     * Popup'ın ilk gerçek adresi geldiğinde karar verir. Giriş (OAuth) pencereleri çarpılı katmanda kalır;
     * sıradan bağlantılar (target=_blank, window.open) aynı sekmede açılır -> adres çubuğu, favicon, geri/ileri doğru çalışır.
     * Dokunuşsuz (reklam) popup'lar sessizce kapatılır. true = bu yükleme popup'ta yapılmasın.
     */
    private boolean routePopup(final String id, final NPopup box, String url) {
        if (box.decided) return false;
        if (url == null || !(url.startsWith("http://") || url.startsWith("https://"))) return false;   // about:blank vb.: beklemeye devam
        box.decided = true;
        if (isAuthUrl(url)) { box.setVisibility(View.VISIBLE); return false; }
        final String target = url;
        final boolean g = box.gesture;
        root.post(() -> {
            if (nPop.get(id) != box) return;
            closePopup(id);
            WebView parent = nViews.get(id);
            if (g && parent != null) parent.loadUrl(target);
        });
        return true;
    }

    /** Giriş / yetkilendirme (OAuth) sayfası mı? Bunlar popup olarak kalmalı (window.opener ile ana sayfaya sonuç döner). */
    private static boolean isAuthUrl(String url) {
        try {
            android.net.Uri u = android.net.Uri.parse(url);
            String h = u.getHost() == null ? "" : u.getHost().toLowerCase(Locale.ROOT);
            String p = u.getPath() == null ? "" : u.getPath().toLowerCase(Locale.ROOT);
            String q = u.getQuery() == null ? "" : u.getQuery().toLowerCase(Locale.ROOT);
            String[] hosts = {"accounts.google.", "accounts.youtube.", "appleid.apple.", "login.microsoftonline.", "login.live.",
                    "login.microsoft.", "login.yahoo.", "auth0.com", "okta.com", "id.twitch.", "id.atlassian."};
            for (String x : hosts) if (h.contains(x)) return true;
            if (p.contains("/oauth") || p.contains("/authorize") || p.contains("/dialog/oauth") || p.contains("/o/oauth2")) return true;
            return q.contains("client_id=") && (q.contains("redirect_uri=") || q.contains("response_type="));
        } catch (Throwable t) {
            return false;
        }
    }

    private void closePopup(String id) {
        NPopup box = nPop.remove(id);
        if (box == null) return;
        flushCookies();
        try { root.removeView(box); box.web.stopLoading(); box.web.loadUrl("about:blank"); box.web.destroy(); } catch (Throwable ignored) { }
    }

    /** Masaüstü modunu aç/kapat: gerçek User-Agent + geniş viewport. Yenileme çağıranın işi. */
    private void applyDesktop(WebView wv, boolean on) {
        WebSettings s = wv.getSettings();
        s.setUserAgentString(desktopUa());   // her zaman masaüstü UA
        hardenForGoogle(wv);                 // X-Requested-With + Sec-CH-UA: WebView olduğu belli olmasın
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        if (on) wv.setInitialScale(0);
    }

    private void setDesktopNative(String id, boolean on) {
        on = true;   // mobil mod yok: yerel WebView'ler hep masaüstü
        boolean was = Boolean.TRUE.equals(nDesk.get(id));
        nDesk.put(id, on);
        WebView wv = nViews.get(id);
        if (wv == null || was == on) return;   // henüz oluşmadıysa createNative uygular
        applyDesktop(wv, on);
        if (wv.getTranslationX() > -10000) wv.reload(); else nReload.add(id);   // görünmeyen sekme görününce yenilenir
    }

    private static String errJson(String m) {
        try { return new JSONObject().put("ok", false).put("err", m == null ? "hata" : m).toString(); }
        catch (Throwable t) { return "{\"ok\":false}"; }
    }

    /** Sayfanın o anki DOM görüntüsünü (script'siz, <base> ile) HTML olarak Downloads klasörüne yazar. */
    private String writeHtmlToDownloads(String raw) throws Exception {
        Object o = new org.json.JSONTokener(raw == null ? "null" : raw).nextValue();
        if (!(o instanceof String)) return errJson("Sayfa içeriği alınamadı");
        JSONObject j = new JSONObject((String) o);
        if (j.has("err")) return errJson(j.optString("err"));
        String html = j.optString("h", "");
        if (html.isEmpty()) return errJson("Sayfa boş");
        String title = j.optString("t", "").trim();
        if (title.isEmpty()) {
            try { title = android.net.Uri.parse(j.optString("u", "")).getHost(); } catch (Throwable ignored) { }
            if (title == null || title.isEmpty()) title = "sayfa";
        }
        title = title.replaceAll("[\\\\/:*?\"<>|\\s]+", "_").replaceAll("^_+|_+$", "");
        if (title.length() > 60) title = title.substring(0, 60);
        if (title.isEmpty()) title = "sayfa";
        String name = title + "_" + new java.text.SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(new java.util.Date()) + ".html";
        byte[] data = html.getBytes(StandardCharsets.UTF_8);
        if (Build.VERSION.SDK_INT >= 29) {
            writeViaMediaStore(name, data);
        } else {
            java.io.File dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
            if (!dir.exists()) dir.mkdirs();
            java.io.File f = new java.io.File(dir, name);
            java.io.FileOutputStream fo = new java.io.FileOutputStream(f);
            try { fo.write(data); } finally { fo.close(); }
            android.media.MediaScannerConnection.scanFile(this, new String[]{f.getAbsolutePath()}, new String[]{"text/html"}, null);
        }
        return new JSONObject().put("ok", true).put("name", name).toString();
    }

    @android.annotation.TargetApi(29)
    private void writeViaMediaStore(String name, byte[] data) throws Exception {
        android.content.ContentResolver cr = getContentResolver();
        ContentValues cv = new ContentValues();
        cv.put(MediaStore.Downloads.DISPLAY_NAME, name);
        cv.put(MediaStore.Downloads.MIME_TYPE, "text/html");
        cv.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
        cv.put(MediaStore.Downloads.IS_PENDING, 1);
        android.net.Uri u = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
        if (u == null) throw new java.io.IOException("Downloads'a yazılamadı");
        try {
            java.io.OutputStream os = cr.openOutputStream(u);
            if (os == null) throw new java.io.IOException("Dosya açılamadı");
            try { os.write(data); } finally { os.close(); }
            ContentValues done = new ContentValues();
            done.put(MediaStore.Downloads.IS_PENDING, 0);
            cr.update(u, done, null, null);
        } catch (Exception e) {
            try { cr.delete(u, null, null); } catch (Throwable ignored) { }
            throw e;
        }
    }

    // ---- Sürükleme/boyutlandırma anlık görüntüsü ----

    /** Başka bir yerel pencere (WebView / uygulama yüzeyi) bu WebView'in üstünü kapatıyor mu? */
    private boolean coveredByNative(View v) {
        try {
            int[] a = new int[2]; v.getLocationInWindow(a);
            Rect me = new Rect(a[0], a[1], a[0] + v.getWidth(), a[1] + v.getHeight());
            int idx = root.indexOfChild(v);
            for (int i = idx + 1; i < root.getChildCount(); i++) {
                View o = root.getChildAt(i);
                if (o.getVisibility() != View.VISIBLE || o.getWidth() < 2 || o.getTranslationX() < -10000) continue;
                int[] b = new int[2]; o.getLocationInWindow(b);
                if (Rect.intersects(me, new Rect(b[0], b[1], b[0] + o.getWidth(), b[1] + o.getHeight()))) return true;
            }
        } catch (Throwable t) { return true; }
        return false;
    }

    /**
     * Görüntüyü önce PixelCopy ile (ekranda gerçekten görünen kareyi alır: video/hızlandırılmış katmanlar dahil),
     * olmazsa View.draw ile alır. Çözünürlük 2048'e kadar, JPEG kalitesi 88.
     */
    private void snapCapture(final String id, final WebView wv, final String cb) {
        final int w = wv.getWidth(), h = wv.getHeight();
        final float sc = Math.min(1f, 2048f / Math.max(w, h));
        final int dw = Math.max(2, Math.round(w * sc)), dh = Math.max(2, Math.round(h * sc));
        try {
            Rect clip = wv.getClipBounds();
            boolean full = clip == null || (clip.left <= 0 && clip.top <= 0 && clip.right >= w && clip.bottom >= h);
            int[] loc = new int[2]; wv.getLocationInWindow(loc);
            View dec = getWindow().getDecorView();
            boolean inWin = loc[0] >= 0 && loc[1] >= 0 && loc[0] + w <= dec.getWidth() && loc[1] + h <= dec.getHeight();
            if (Build.VERSION.SDK_INT >= 26 && full && inWin && wv.getTranslationX() > -10000 && !coveredByNative(wv)) {
                final Bitmap bmp = Bitmap.createBitmap(dw, dh, Bitmap.Config.ARGB_8888);
                android.view.PixelCopy.request(getWindow(), new Rect(loc[0], loc[1], loc[0] + w, loc[1] + h), bmp, res -> {
                    if (res == android.view.PixelCopy.SUCCESS) finishSnap(id, bmp, cb);
                    else { bmp.recycle(); snapDraw(id, wv, cb, sc, dw, dh); }
                }, new android.os.Handler(android.os.Looper.getMainLooper()));
                return;
            }
        } catch (Throwable ignored) { }
        snapDraw(id, wv, cb, sc, dw, dh);
    }

    private void snapDraw(String id, WebView wv, String cb, float sc, int dw, int dh) {
        try {
            if (nViews.get(id) != wv) { jsCall(cb, "null"); return; }
            Bitmap bmp = Bitmap.createBitmap(dw, dh, Bitmap.Config.ARGB_8888);
            Canvas c = new Canvas(bmp);
            c.scale(sc, sc);
            c.drawColor(nVnc.contains(id) ? Color.BLACK : Color.WHITE);
            wv.draw(c);
            finishSnap(id, bmp, cb);
        } catch (Throwable t) {
            jsCall(cb, "null");
        }
    }

    private void finishSnap(String id, Bitmap bmp, String cb) {
        try {
            if (!nViews.containsKey(id)) { bmp.recycle(); jsCall(cb, "null"); return; }
            ByteArrayOutputStream bo = new ByteArrayOutputStream(160 * 1024);
            bmp.compress(Bitmap.CompressFormat.JPEG, 88, bo);
            bmp.recycle();
            nSnaps.put(id, bo.toByteArray());
            jsCall(cb, JSONObject.quote("https://" + FRAME_HOST + "/n?k=" + id + "&t=" + (++nSnapSeq)));
        } catch (Throwable t) {
            jsCall(cb, "null");
        }
    }

    private static boolean isNativeVnc(String u) { return u != null && u.contains("/udvnc"); }

    private void createVnc(final String id, String url) {
        int port = 0;
        float sc = 1f, dpr = 1f;
        try {
            android.net.Uri u = android.net.Uri.parse(url);
            port = u.getPort();
            String q = u.getQueryParameter("s");
            if (q != null) sc = Float.parseFloat(q);
            String dq = u.getQueryParameter("d");
            if (dq != null) dpr = Float.parseFloat(dq);
        } catch (Throwable ignored) { }
        if (port <= 0) return;
        VncView v = new VncView(this, id, "127.0.0.1", port, sc, dpr, new VncView.Host() {
            @Override public void failed(String fid) {
                runOnUiThread(() -> {
                    if (webView == null) return;
                    webView.evaluateJavascript("window.__w7vncFail&&window.__w7vncFail('" + fid.replaceAll("[^A-Za-z0-9_-]", "") + "');", null);
                });
            }
        });
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        root.addView(v, lp);
        v.setTranslationX(-20000);   // ilk setRect2'ye kadar ekran dışında bekler
        vncViews.put(id, v);
        v.start();
    }

    private void destroyVnc(String id) {
        VncView v = vncViews.remove(id);
        if (v == null) return;
        try { root.removeView(v); } catch (Throwable ignored) { }
        try { v.close(); } catch (Throwable ignored) { }
    }

    private void navigateNative(String id, String url) {
        if (vncViews.containsKey(id)) { createNative(id, url); return; }
        WebView wv = nViews.get(id);
        if (wv == null) return;
        String cur = wv.getUrl();
        if (url.equals(cur)) return;   // adres çubuğu zaten bu sayfada: yeniden yükleme
        wv.loadUrl(url);
    }

    /** Görünmeyen (küçültülmüş / başka pencerenin altında) noVNC penceresini 1,2 sn sonra duraklatır: JS çözme ve sunucu güncellemesi durur. */
    private final java.util.Set<String> nVncPaused = java.util.concurrent.ConcurrentHashMap.newKeySet();
    private final Map<String, Runnable> nVncPauseJobs = new java.util.concurrent.ConcurrentHashMap<>();
    private final Handler nVncH = new Handler(android.os.Looper.getMainLooper());
    private void vncVisibility(final String id, final WebView wv, boolean vis) {
        Runnable pend = nVncPauseJobs.remove(id);
        if (pend != null) nVncH.removeCallbacks(pend);
        if (vis) {
            if (nVncPaused.remove(id)) { try { wv.onResume(); } catch (Throwable ignored) { } }
        } else if (!nVncPaused.contains(id)) {
            Runnable r = () -> {
                nVncPauseJobs.remove(id);
                if (nViews.get(id) == wv && nVncPaused.add(id)) { try { wv.onPause(); } catch (Throwable ignored) { } }
            };
            nVncPauseJobs.put(id, r);
            nVncH.postDelayed(r, 1200);
        }
    }

    private void destroyNative(String id) {
        destroyVnc(id);
        WebView wv = nViews.remove(id);
        nDesk.remove(id);
        nVnc.remove(id);
        nVncPaused.remove(id);
        Runnable pj = nVncPauseJobs.remove(id); if (pj != null) nVncH.removeCallbacks(pj);
        nReload.remove(id);
        nSnaps.remove(id);
        nNav.remove(id);
        closePopup(id);
        flushCookies();
        if (wv == null) return;
        try { root.removeView(wv); wv.stopLoading(); wv.loadUrl("about:blank"); wv.destroy(); } catch (Throwable ignored) { }
    }


    // ===================== Tarayıcı pencerelerinden dosya indirme =====================
    // Tarayıcı pencerelerindeki (Chrome, Nova Browser, Internet Explorer) dosya/video indirmeleri tablet İndirilenler klasörüne gider
    // (Dosya Gezgini'ndeki "İndirilenler" ile aynı klasör). http(s): DownloadManager (çerez + referer ile, bildirimli);
    // blob: ve data: bağlantıları sayfadan okunup doğrudan yazılır.
    // İndirme geçmişi SharedPreferences'ta ("w7_dl_hist") tutulur; Chrome/IE "İndirilenler" sayfaları AndroidBridge.dlList() ile okur.
    private final java.util.Set<Long> dlIds = java.util.Collections.synchronizedSet(new java.util.HashSet<Long>());
    private boolean dlRegistered = false;
    private final java.util.concurrent.ExecutorService dlIo = java.util.concurrent.Executors.newSingleThreadExecutor();
    private static final int DL_CHUNK = 393216;   // 4'ün katı: base64 parçaları tek tek çözülebilsin
    private final Object dlLock = new Object();
    private final java.util.Map<String, long[]> dlProg = new java.util.concurrent.ConcurrentHashMap<String, long[]>();   // key -> {indirilen, toplam}
    private int dlSeq = 0;

    private static class DlOut {
        final java.io.OutputStream os; final String uri;
        DlOut(java.io.OutputStream os, String uri) { this.os = os; this.uri = uri; }
    }

    // ---- geçmiş (JSON dizisi, en yeni sonda) ----
    private org.json.JSONArray dlHistRead() {
        try { return new org.json.JSONArray(prefs == null ? "[]" : prefs.getString("w7_dl_hist", "[]")); }
        catch (Throwable t) { return new org.json.JSONArray(); }
    }

    private void dlHistWrite(org.json.JSONArray a) {
        try {
            while (a.length() > 200) a.remove(0);   // en eski kayıtları at
            if (prefs != null) prefs.edit().putString("w7_dl_hist", a.toString()).apply();
        } catch (Throwable ignored) { }
    }

    /** Yeni kayıt ekler, anahtarını döndürür. state: "d" (iniyor), "ok", "err". */
    private String dlHistAdd(String name, String url, String mime, String state, long dm) {
        synchronized (dlLock) {
            String k = "dl" + System.currentTimeMillis() + "_" + (dlSeq++);
            try {
                org.json.JSONArray a = dlHistRead();
                org.json.JSONObject o = new org.json.JSONObject();
                o.put("k", k); o.put("n", name); o.put("u", url == null ? "" : (url.startsWith("http") ? url : ""));
                o.put("mime", mime == null ? "" : mime); o.put("t", System.currentTimeMillis());
                o.put("s", state); o.put("dm", dm); o.put("uri", ""); o.put("size", 0L);
                a.put(o);
                dlHistWrite(a);
            } catch (Throwable ignored) { }
            return k;
        }
    }

    private void dlHistSet(String k, String state, String uri, long size, long dm) {
        synchronized (dlLock) {
            try {
                org.json.JSONArray a = dlHistRead();
                for (int i = 0; i < a.length(); i++) {
                    org.json.JSONObject o = a.getJSONObject(i);
                    if (k.equals(o.optString("k"))) {
                        if (state != null) o.put("s", state);
                        if (uri != null) o.put("uri", uri);
                        if (size >= 0) o.put("size", size);
                        if (dm >= 0) o.put("dm", dm);
                        break;
                    }
                }
                dlHistWrite(a);
            } catch (Throwable ignored) { }
            if (state != null && !"d".equals(state)) dlProg.remove(k);
        }
    }

    private org.json.JSONObject dlHistFind(String k) {
        synchronized (dlLock) {
            try {
                org.json.JSONArray a = dlHistRead();
                for (int i = 0; i < a.length(); i++) {
                    org.json.JSONObject o = a.getJSONObject(i);
                    if (k.equals(o.optString("k"))) return o;
                }
            } catch (Throwable ignored) { }
            return null;
        }
    }

    /** DownloadManager'daki sürmekte olan kayıtların durumunu geçmişe yansıtır (liste açılırken). */
    private void dlRefreshActive() {
        synchronized (dlLock) {
            android.database.Cursor cu = null;
            try {
                org.json.JSONArray a = dlHistRead();
                android.app.DownloadManager dm = (android.app.DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                boolean changed = false;
                for (int i = 0; i < a.length(); i++) {
                    org.json.JSONObject o = a.getJSONObject(i);
                    long id = o.optLong("dm", 0);
                    if (!"d".equals(o.optString("s")) || id <= 0) continue;
                    cu = dm.query(new android.app.DownloadManager.Query().setFilterById(id));
                    if (cu != null && cu.moveToFirst()) {
                        int st = cu.getInt(cu.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_STATUS));
                        long cur = cu.getLong(cu.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR));
                        long tot = cu.getLong(cu.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_TOTAL_SIZE_BYTES));
                        if (st == android.app.DownloadManager.STATUS_SUCCESSFUL) {
                            o.put("s", "ok"); o.put("size", tot > 0 ? tot : cur);
                            try { android.net.Uri u = dm.getUriForDownloadedFile(id); if (u != null) o.put("uri", u.toString()); } catch (Throwable ignored) { }
                            dlProg.remove(o.optString("k")); changed = true;
                        } else if (st == android.app.DownloadManager.STATUS_FAILED) {
                            o.put("s", "err"); dlProg.remove(o.optString("k")); changed = true;
                        } else {
                            dlProg.put(o.optString("k"), new long[]{cur, tot});
                        }
                    } else {
                        o.put("s", "err"); dlProg.remove(o.optString("k")); changed = true;   // kayıt silinmiş
                    }
                    if (cu != null) { cu.close(); cu = null; }
                }
                if (changed) dlHistWrite(a);
            } catch (Throwable ignored) {
            } finally { try { if (cu != null) cu.close(); } catch (Throwable ignored) { } }
        }
    }

    /** Sayfa için liste: en yeni başta; sürmekte olanlara ilerleme (cur/total) eklenir. */
    private String dlListJson() {
        dlRefreshActive();
        synchronized (dlLock) {
            try {
                org.json.JSONArray a = dlHistRead(), out = new org.json.JSONArray();
                for (int i = a.length() - 1; i >= 0; i--) {
                    org.json.JSONObject o = a.getJSONObject(i);
                    long[] pr = dlProg.get(o.optString("k"));
                    if (pr != null && "d".equals(o.optString("s"))) { o.put("cur", pr[0]); o.put("total", pr[1]); }
                    out.put(o);
                }
                return out.toString();
            } catch (Throwable t) { return "[]"; }
        }
    }

    private void dlOpenItem(String k) {
        try {
            org.json.JSONObject o = dlHistFind(k);
            if (o == null || !"ok".equals(o.optString("s"))) return;
            String uri = o.optString("uri", "");
            if (uri.isEmpty()) { dlToast("Dosya bulunamadı"); return; }
            String mime = o.optString("mime", "");
            if (mime.isEmpty()) {
                String ext = android.webkit.MimeTypeMap.getFileExtensionFromUrl(o.optString("n", "").replace(" ", "_"));
                String g = ext == null ? null : android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext.toLowerCase());
                mime = g == null ? "*/*" : g;
            }
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(android.net.Uri.parse(uri), mime);
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(i);
        } catch (Throwable t) { dlToast("Bu dosya açılamadı"); }
    }

    private void dlCancelItem(String k) {
        try {
            org.json.JSONObject o = dlHistFind(k);
            if (o == null) return;
            long id = o.optLong("dm", 0);
            if (id > 0) {
                dlIds.remove(id);
                ((android.app.DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE)).remove(id);
            }
            dlHistSet(k, "err", null, -1, -1);
            dlCancelled.add(k);
        } catch (Throwable ignored) { }
    }
    private final java.util.Set<String> dlCancelled = java.util.Collections.synchronizedSet(new java.util.HashSet<String>());

    private void dlRemoveItem(String k) {
        synchronized (dlLock) {
            try {
                org.json.JSONArray a = dlHistRead(), n = new org.json.JSONArray();
                for (int i = 0; i < a.length(); i++) {
                    org.json.JSONObject o = a.getJSONObject(i);
                    if (!k.equals(o.optString("k"))) n.put(o);
                }
                dlHistWrite(n);
                dlProg.remove(k);
            } catch (Throwable ignored) { }
        }
    }

    private void dlClearAll() {
        synchronized (dlLock) {
            try {
                org.json.JSONArray a = dlHistRead(), n = new org.json.JSONArray();
                for (int i = 0; i < a.length(); i++) {
                    org.json.JSONObject o = a.getJSONObject(i);
                    if ("d".equals(o.optString("s"))) n.put(o);   // sürenler kalsın
                }
                dlHistWrite(n);
            } catch (Throwable ignored) { }
        }
    }

    private final BroadcastReceiver dlRx = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) {
            android.database.Cursor cu = null;
            try {
                long id = i.getLongExtra(android.app.DownloadManager.EXTRA_DOWNLOAD_ID, -1);
                if (id < 0 || !dlIds.remove(id)) return;
                android.app.DownloadManager dm = (android.app.DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                cu = dm.query(new android.app.DownloadManager.Query().setFilterById(id));
                if (cu != null && cu.moveToFirst()) {
                    int st = cu.getInt(cu.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_STATUS));
                    String title = cu.getString(cu.getColumnIndexOrThrow(android.app.DownloadManager.COLUMN_TITLE));
                    dlRefreshActive();   // geçmişi (durum, boyut, uri) güncelle
                    dlToast(st == android.app.DownloadManager.STATUS_SUCCESSFUL
                            ? "İndirme tamamlandı: " + title + " (İndirilenler)" : "İndirme başarısız: " + title);
                }
            } catch (Throwable ignored) {
            } finally { try { if (cu != null) cu.close(); } catch (Throwable ignored) { } }
        }
    };

    private void dlRegister(boolean on) {
        try {
            if (on && !dlRegistered) {
                IntentFilter f = new IntentFilter(android.app.DownloadManager.ACTION_DOWNLOAD_COMPLETE);
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(dlRx, f, Context.RECEIVER_EXPORTED);
                else registerReceiver(dlRx, f);
                dlRegistered = true;
                dlRefreshActive();   // arka planda biten indirmeler geçmişe işlensin
            } else if (!on && dlRegistered) {
                unregisterReceiver(dlRx);
                dlRegistered = false;
            }
        } catch (Throwable ignored) { }
    }

    private void dlToast(final String m) {
        runOnUiThread(() -> { try { android.widget.Toast.makeText(MainActivity.this, m, android.widget.Toast.LENGTH_SHORT).show(); } catch (Throwable ignored) { } });
    }

    private void handleDownload(final WebView wv, final String url, String ua, String cd, String mime) {
        try {
            if (url == null) return;
            final String name = android.webkit.URLUtil.guessFileName(url, cd, mime);
            if (url.startsWith("blob:")) { dlBlob(wv, url, name, mime); return; }
            if (url.startsWith("data:")) { dlData(url, name, mime); return; }
            if (!url.startsWith("http://") && !url.startsWith("https://")) return;
            try {
                android.app.DownloadManager.Request rq = new android.app.DownloadManager.Request(android.net.Uri.parse(url));
                if (mime != null && !mime.isEmpty()) rq.setMimeType(mime);
                if (ua != null && !ua.isEmpty()) rq.addRequestHeader("User-Agent", ua);
                String ck = android.webkit.CookieManager.getInstance().getCookie(url);
                if (ck != null && !ck.isEmpty()) rq.addRequestHeader("Cookie", ck);
                String ref = wv.getUrl();
                if (ref != null && !ref.isEmpty()) rq.addRequestHeader("Referer", ref);
                rq.setTitle(name);
                rq.setNotificationVisibility(android.app.DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                rq.allowScanningByMediaScanner();
                rq.setDestinationInExternalPublicDir(android.os.Environment.DIRECTORY_DOWNLOADS, name);
                android.app.DownloadManager dm = (android.app.DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE);
                long id = dm.enqueue(rq);
                dlIds.add(id);
                dlHistAdd(name, url, mime, "d", id);
                dlToast("İndiriliyor: " + name);
            } catch (Throwable t) {
                dlHistAdd(name, url, mime, "err", 0);
                dlToast("İndirme başlatılamadı: " + name);
                try { startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url))); } catch (Throwable ignored) { }
            }
        } catch (Throwable ignored) { }
    }

    /** İndirilenler klasöründe yeni dosya açar (Android 10+: MediaStore, öncesi: doğrudan dosya). */
    private DlOut dlOpen(String name, String mime) throws Exception {
        if (mime == null || mime.isEmpty()) mime = "application/octet-stream";
        if (Build.VERSION.SDK_INT >= 29) {
            android.content.ContentValues cv = new android.content.ContentValues();
            cv.put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name);
            cv.put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime);
            cv.put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS);
            android.net.Uri u = getContentResolver().insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
            if (u == null) throw new java.io.IOException("insert null");
            return new DlOut(getContentResolver().openOutputStream(u), u.toString());
        }
        java.io.File dir = android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS);
        //noinspection ResultOfMethodCallIgnored
        dir.mkdirs();
        java.io.File f = new java.io.File(dir, name);
        int n = 1;
        String base = name, ext = "";
        int dot = name.lastIndexOf('.');
        if (dot > 0) { base = name.substring(0, dot); ext = name.substring(dot); }
        while (f.exists()) f = new java.io.File(dir, base + " (" + (n++) + ")" + ext);
        String uri;
        try { uri = androidx.core.content.FileProvider.getUriForFile(this, getPackageName() + ".files", f).toString(); }
        catch (Throwable t) { uri = android.net.Uri.fromFile(f).toString(); }
        return new DlOut(new java.io.FileOutputStream(f), uri);
    }

    private void dlData(final String url, final String name, final String mime) {
        dlToast("İndiriliyor: " + name);
        final String key = dlHistAdd(name, "", mime, "d", 0);
        dlIo.execute(() -> {
            try {
                int comma = url.indexOf(',');
                String head = url.substring(5, comma);
                String payload = url.substring(comma + 1);
                byte[] data = head.contains(";base64")
                        ? android.util.Base64.decode(payload, android.util.Base64.DEFAULT)
                        : java.net.URLDecoder.decode(payload, "UTF-8").getBytes("UTF-8");
                DlOut o = dlOpen(name, mime);
                try { o.os.write(data); } finally { o.os.close(); }
                dlHistSet(key, "ok", o.uri, data.length, -1);
                dlToast("İndirme tamamlandı: " + name + " (İndirilenler)");
            } catch (Throwable t) { dlHistSet(key, "err", null, -1, -1); dlToast("İndirme başarısız: " + name); }
        });
    }

    /** blob: bağlantısı: sayfada fetch ile okunup base64 olarak parça parça çekilir. */
    private void dlBlob(final WebView wv, final String url, final String name, final String mime) {
        final String js = "(function(){window.__w7dl=null;window.__w7dlS='p';fetch(" + JSONObject.quote(url)
                + ").then(function(r){return r.blob();}).then(function(b){var rd=new FileReader();"
                + "rd.onload=function(){var s=String(rd.result);window.__w7dl=s.substring(s.indexOf(',')+1);window.__w7dlS='ok';};"
                + "rd.onerror=function(){window.__w7dlS='err';};rd.readAsDataURL(b);}).catch(function(){window.__w7dlS='err';});})();";
        wv.evaluateJavascript(js, null);
        dlToast("İndiriliyor: " + name);
        final String key = dlHistAdd(name, "", mime, "d", 0);
        dlPoll(wv, key, name, mime, SystemClock.uptimeMillis() + 180000L);
    }

    private void dlPoll(final WebView wv, final String key, final String name, final String mime, final long deadline) {
        if (dlCancelled.remove(key)) return;
        wv.evaluateJavascript("window.__w7dlS||''", v -> {
            String st = v == null ? "" : v.replace("\"", "");
            if ("ok".equals(st)) {
                wv.evaluateJavascript("window.__w7dl?window.__w7dl.length:0", lv -> {
                    int total = 0;
                    try { total = Integer.parseInt(lv.trim()); } catch (Throwable ignored) { }
                    if (total <= 0) { dlHistSet(key, "err", null, -1, -1); dlToast("İndirme başarısız: " + name); return; }
                    try {
                        final DlOut o = dlOpen(name, mime);
                        dlProg.put(key, new long[]{0, (long) total * 3 / 4});
                        dlChunk(wv, o, key, 0, total, name);
                    } catch (Throwable t) { dlHistSet(key, "err", null, -1, -1); dlToast("İndirme başarısız: " + name); }
                });
            } else if ("err".equals(st) || SystemClock.uptimeMillis() > deadline) {
                dlHistSet(key, "err", null, -1, -1);
                dlToast("İndirme başarısız: " + name);
            } else {
                wv.postDelayed(() -> dlPoll(wv, key, name, mime, deadline), 300);
            }
        });
    }

    private void dlChunk(final WebView wv, final DlOut o, final String key, final int p, final int total, final String name) {
        wv.evaluateJavascript("window.__w7dl.substr(" + p + "," + DL_CHUNK + ")", v -> dlIo.execute(() -> {
            try {
                if (dlCancelled.remove(key)) { o.os.close(); runOnUiThread(() -> wv.evaluateJavascript("window.__w7dl=null;window.__w7dlS='';", null)); return; }
                String s = v == null ? "" : v;
                if (s.length() >= 2 && s.charAt(0) == '"') s = s.substring(1, s.length() - 1);
                s = s.replace("\\/", "/");   // WebView JSON çıktısında '/' kaçışlı gelir
                o.os.write(android.util.Base64.decode(s, android.util.Base64.DEFAULT));
                final int next = p + DL_CHUNK;
                if (next < total) {
                    dlProg.put(key, new long[]{(long) next * 3 / 4, (long) total * 3 / 4});
                    runOnUiThread(() -> dlChunk(wv, o, key, next, total, name));
                } else {
                    o.os.close();
                    runOnUiThread(() -> wv.evaluateJavascript("window.__w7dl=null;window.__w7dlS='';", null));
                    dlHistSet(key, "ok", o.uri, (long) total * 3 / 4, -1);
                    dlToast("İndirme tamamlandı: " + name + " (İndirilenler)");
                }
            } catch (Throwable t) {
                try { o.os.close(); } catch (Throwable ignored) { }
                dlHistSet(key, "err", null, -1, -1);
                dlToast("İndirme başarısız: " + name);
            }
        }));
    }

    // ===================== Android pencerelerinde fare imleci =====================
    // Android pencerelerine fare olayı (hover / SOURCE_MOUSE) gidince Android pencerenin içine kendi imlecini çizebiliyor.
    // "İmleci gizle" açıkken (varsayılan): sol tık/sürükleme dokunma olarak, hover hiç gönderilmez; sağ/orta tık ve tekerlek
    // fare olarak gider. Kapalıyken eskisi gibi her şey gerçek fare olayıdır.
    private volatile boolean vdMouseAsTouch = false;   // şu anki basılı sıra dokunma olarak mı gidiyor

    private boolean vdTouchPtr() {
        try { return prefs == null || prefs.getBoolean("w7_vdptr", true); } catch (Throwable e) { return true; }
    }

    private void vdInjectMouse(IVdService svc, int did, int action, float nx, float ny, int bs, int ab,
                               float hs, float vs, long dn, int rot) throws Exception {
        if (!vdTouchPtr()) { svc.injectMouse(did, action, nx, ny, bs, ab, hs, vs, dn, rot); return; }
        final float[] xs = {nx}, ys = {ny};
        final int[] ids = {0};
        switch (action) {
            case MotionEvent.ACTION_HOVER_ENTER:
            case MotionEvent.ACTION_HOVER_MOVE:
            case MotionEvent.ACTION_HOVER_EXIT:
                return;   // hover gönderme: Android imleç çizmesin
            case MotionEvent.ACTION_DOWN:
                if (bs == MotionEvent.BUTTON_PRIMARY) {
                    vdMouseAsTouch = true;
                    svc.injectTouch(did, MotionEvent.ACTION_DOWN, 0, xs, ys, ids, 1, dn, rot);
                } else {
                    vdMouseAsTouch = false;
                    svc.injectMouse(did, action, nx, ny, bs, ab, hs, vs, dn, rot);
                }
                return;
            case MotionEvent.ACTION_MOVE:
                if (vdMouseAsTouch) svc.injectTouch(did, MotionEvent.ACTION_MOVE, 0, xs, ys, ids, 1, dn, rot);
                else if (bs != 0) svc.injectMouse(did, action, nx, ny, bs, ab, hs, vs, dn, rot);
                return;
            case MotionEvent.ACTION_BUTTON_PRESS:
            case MotionEvent.ACTION_BUTTON_RELEASE:
                if (!vdMouseAsTouch) svc.injectMouse(did, action, nx, ny, bs, ab, hs, vs, dn, rot);
                return;
            case MotionEvent.ACTION_UP:
                if (vdMouseAsTouch) {
                    vdMouseAsTouch = false;
                    svc.injectTouch(did, MotionEvent.ACTION_UP, 0, xs, ys, ids, 1, dn, rot);
                } else {
                    svc.injectMouse(did, action, nx, ny, bs, ab, hs, vs, dn, rot);
                }
                return;
            default:   // ACTION_SCROLL vb.
                svc.injectMouse(did, action, nx, ny, bs, ab, hs, vs, dn, rot);
        }
    }

    // ===================== Telefonda 16:9 kutu (kalan alan siyah) =====================
    // Telefon algılanırsa (en küçük ekran genişliği < 600 dp) simülatör 16:9 oranında ortalanır, kalan yerler siyah kalır.
    // Tablette (>= 600 dp) hiçbir şey değişmez. Kutu, çentik boşluğuna ek bir root padding olarak uygulanır; WebView ve
    // tüm native pencereler/imleç aynı padding içinde konumlandığı için hizaları bozulmaz.
    private int lbCl = 0, lbCt = 0, lbCr = 0, lbCb = 0;

    private boolean lbIsPhone() {
        try { return getResources().getConfiguration().smallestScreenWidthDp < 600; } catch (Throwable e) { return false; }
    }

    /** Ekran modu: kullanıcı Win11 Ayarlar > Ekran > Ekran modu'ndan seçtiyse o; seçmediyse telefonda 16:9, tabletta tam ekran. */
    private boolean lbWant16x9() {
        String m = null;
        try { if (prefs != null) m = prefs.getString("w7_aspect", null); } catch (Throwable ignored) { }
        if ("16x9".equals(m)) return true;
        if ("full".equals(m)) return false;
        return lbIsPhone();
    }

    private void lbApply() {
        if (root == null) return;
        int l = lbCl, t = lbCt, r = lbCr, b = lbCb;
        int rw = root.getWidth(), rh = root.getHeight();
        if (lbWant16x9() && rw > 0 && rh > 0) {
            int aw = rw - lbCl - lbCr, ah = rh - lbCt - lbCb;
            if (aw > 0 && ah > 0) {
                if ((long) aw * 9 > (long) ah * 16 + ah / 50) {            // çok geniş: sağ/sol siyah
                    int ex = (aw - Math.round(ah * 16f / 9f)) / 2;
                    l += ex; r += ex;
                } else if ((long) aw * 9 < (long) ah * 16 - ah / 50) {     // çok uzun: üst/alt siyah
                    int ex = (ah - Math.round(aw * 9f / 16f)) / 2;
                    t += ex; b += ex;
                }
            }
        }
        if (root.getPaddingLeft() != l || root.getPaddingTop() != t || root.getPaddingRight() != r || root.getPaddingBottom() != b)
            root.setPadding(l, t, r, b);
    }

    // ===================== Ses düzeyi göstergesi (Windows 11 tarzı, görev çubuğunun ortasında) =====================
    // Donanım ses tuşları yakalanır: Android'in kendi ses paneli çıkmaz, gerçek tablet ses düzeyi (STREAM_MUSIC)
    // değişir ve görev çubuğunun hemen üstünde ortada küçük bir gösterge kayarak girip çıkar.
    // Gösterge, Android uygulama pencereleri (SurfaceView, en üstte) tam ekranken de görünsün diye native SurfaceView'dir.
    private AudioManager volAudio;
    private VolView volView;
    private int volPct = 0, volLastCur = -1;
    private boolean volMuted = false, volLastMute = false;
    private float volTbCss = 48f, volVw = 0f;
    private boolean volW11 = true, volDark = true;
    private float volDens = 1f;
    private float volAlpha = 0f;
    private boolean volPendingIn = false;
    private android.animation.ValueAnimator volAnim;
    private final Handler volH = new Handler(android.os.Looper.getMainLooper());
    private final Runnable volHideRun = () -> volAnimOut();
    private boolean volRegistered = false;
    private final BroadcastReceiver volRx = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) {
            try {
                if (i == null || i.getIntExtra("android.media.EXTRA_VOLUME_STREAM_TYPE", -1) != AudioManager.STREAM_MUSIC) return;
                if (volAudio == null) return;
                int cur = volAudio.getStreamVolume(AudioManager.STREAM_MUSIC);
                boolean m = Build.VERSION.SDK_INT >= 23 ? volAudio.isStreamMute(AudioManager.STREAM_MUSIC) : cur == 0;
                if (cur != volLastCur || m != volLastMute) volShow();   // dışarıdan (ör. başka tuş/Bluetooth) değiştiyse de göster
            } catch (Throwable ignored) { }
        }
    };

    private void volInit() {
        try { volAudio = (AudioManager) getSystemService(Context.AUDIO_SERVICE); } catch (Throwable ignored) { }
    }

    private void volRegister(boolean on) {
        dlRegister(on);   // indirme tamamlandı bildirimi de aynı yaşam döngüsünde
        try {
            if (on && !volRegistered) {
                IntentFilter f = new IntentFilter("android.media.VOLUME_CHANGED_ACTION");
                if (Build.VERSION.SDK_INT >= 33) registerReceiver(volRx, f, Context.RECEIVER_EXPORTED);
                else registerReceiver(volRx, f);
                volRegistered = true;
            } else if (!on && volRegistered) {
                unregisterReceiver(volRx);
                volRegistered = false;
            }
        } catch (Throwable ignored) { }
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent ev) {
        int kc = ev.getKeyCode();
        if (kc == KeyEvent.KEYCODE_VOLUME_UP || kc == KeyEvent.KEYCODE_VOLUME_DOWN || kc == KeyEvent.KEYCODE_VOLUME_MUTE) {
            if (ev.getAction() == KeyEvent.ACTION_DOWN) volKey(kc);
            return true;   // sistemin kendi ses panelini engelle
        }
        return super.dispatchKeyEvent(ev);
    }

    private void volKey(int kc) {
        try {
            if (volAudio == null) volInit();
            if (volAudio != null) {
                int dir = kc == KeyEvent.KEYCODE_VOLUME_UP ? AudioManager.ADJUST_RAISE
                        : kc == KeyEvent.KEYCODE_VOLUME_DOWN ? AudioManager.ADJUST_LOWER : AudioManager.ADJUST_TOGGLE_MUTE;
                volAudio.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, 0);   // flags=0: sistem arayüzü gösterilmez
            }
        } catch (Throwable ignored) { }
        volShow();
    }

    /** Gerçek ses düzeyini okur, sayfadan görev çubuğu ölçüsü/tema bilgisini alır ve göstergeyi açar. */
    /** Gerçek ses düzeyini okur (volPct / volMuted / volLast*). */
    private boolean volRead() {
        try {
            if (volAudio == null) volInit();
            if (volAudio == null) return false;
            int max = Math.max(1, volAudio.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
            int cur = volAudio.getStreamVolume(AudioManager.STREAM_MUSIC);
            boolean m = Build.VERSION.SDK_INT >= 23 ? volAudio.isStreamMute(AudioManager.STREAM_MUSIC) : cur == 0;
            volLastCur = cur; volLastMute = m;
            volMuted = m || cur == 0;
            volPct = Math.round(cur * 100f / max);
            return true;
        } catch (Throwable ignored) { return false; }
    }

    /** Simülatördeki ses çubuklarını (Win7 tepsisi, Win11 hızlı ayarlar/Ayarlar) gerçek sese eşitler. */
    private void volPushJs() {
        if (webView == null) return;
        webView.evaluateJavascript("window.__w7volSet&&window.__w7volSet(" + volPct + "," + volMuted + ");", null);
    }

    /** Simülatör ses çubuğundan gelen değeri gerçek tablet sesine uygular (UI iş parçacığı). Gösterge açılmaz. */
    private void volApply(int pct) {
        try {
            if (volAudio == null) volInit();
            if (volAudio == null) return;
            pct = Math.max(0, Math.min(100, pct));
            int max = Math.max(1, volAudio.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
            int idx = Math.round(pct * max / 100f);
            if (pct > 0 && idx == 0) idx = 1;
            if (Build.VERSION.SDK_INT >= 23 && idx > 0 && volAudio.isStreamMute(AudioManager.STREAM_MUSIC))
                volAudio.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0);
            volAudio.setStreamVolume(AudioManager.STREAM_MUSIC, idx, 0);   // flags=0: sistem paneli çıkmaz
            volRead();   // volLast* güncellenir: ses değişikliği yayını göstergeyi tekrar açmasın
        } catch (Throwable ignored) { }
    }

    private void volShow() {
        if (volAudio == null || root == null) return;
        if (!volRead()) return;
        volPushJs();
        if (webView != null) {
            webView.evaluateJavascript("(window.__w7volGeo?window.__w7volGeo():'')", v -> {
                volParseGeo(v);
                volDisplay();
            });
        } else volDisplay();
    }

    private void volParseGeo(String v) {
        try {
            if (v == null) return;
            v = v.replace("\"", "");
            String[] a = v.split("\\|");
            if (a.length < 4) return;
            volTbCss = Float.parseFloat(a[0]);
            volW11 = "1".equals(a[1]);
            volDark = "1".equals(a[2]);
            volVw = Float.parseFloat(a[3]);
        } catch (Throwable ignored) { }
    }

    private void volDisplay() {
        if (root == null || webView == null) return;
        float vw = volVw > 0 ? volVw : 0;
        volDens = vw > 0 ? webView.getWidth() / vw : getResources().getDisplayMetrics().density;
        if (volDens <= 0) volDens = getResources().getDisplayMetrics().density;
        volH.removeCallbacks(volHideRun);
        if (volView == null) {
            int pw = Math.round(294f * volDens), ph = Math.round(78f * volDens);
            volView = new VolView(this);
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(pw, ph);
            lp.gravity = Gravity.TOP | Gravity.LEFT;
            lp.leftMargin = webView.getLeft() + (webView.getWidth() - pw) / 2;
            lp.topMargin = webView.getTop() + webView.getHeight() - Math.round((volTbCss * 1.146f) * volDens) - ph;   // fotoğraf: panel ile görev çubuğu arası = çubuk yüksekliğinin %14.6'sı
            volView.setAlpha(1f);
            volAlpha = 0f;
            volView.setTranslationY(ph * 0.5f);
            volPendingIn = true;
            root.addView(volView, lp);
            if (vcOn) root.post(this::vcTop);   // imleç göstergenin de üstünde kalsın
        } else {
            volView.redraw(volAlpha);
            if (volAlpha < 1f) volAnimIn(); else volH.postDelayed(volHideRun, 1500);
        }
    }

    private void volAnimIn() {
        if (volView == null) return;
        if (volAnim != null) volAnim.cancel();
        final float from = volAlpha;
        final float off = volView.getHeight() * 0.5f;
        volAnim = android.animation.ValueAnimator.ofFloat(from, 1f);
        volAnim.setDuration(Math.max(60, (long) (170 * (1f - from))));
        volAnim.setInterpolator(new android.view.animation.DecelerateInterpolator());
        volAnim.addUpdateListener(a -> {
            if (volView == null) return;
            volAlpha = (float) a.getAnimatedValue();
            volView.setTranslationY(off * (1f - volAlpha));
            volView.redraw(volAlpha);
        });
        volAnim.addListener(new android.animation.AnimatorListenerAdapter() {
            boolean cancelled = false;
            @Override public void onAnimationCancel(android.animation.Animator an) { cancelled = true; }
            @Override public void onAnimationEnd(android.animation.Animator an) {
                if (!cancelled) { volH.removeCallbacks(volHideRun); volH.postDelayed(volHideRun, 1500); }
            }
        });
        volAnim.start();
    }

    private void volAnimOut() {
        if (volView == null) return;
        if (volAnim != null) volAnim.cancel();
        final float from = volAlpha;
        final float off = volView.getHeight() * 0.5f;
        volAnim = android.animation.ValueAnimator.ofFloat(from, 0f);
        volAnim.setDuration(Math.max(60, (long) (220 * from)));
        volAnim.setInterpolator(new android.view.animation.AccelerateInterpolator());
        volAnim.addUpdateListener(a -> {
            if (volView == null) return;
            volAlpha = (float) a.getAnimatedValue();
            volView.setTranslationY(off * (1f - volAlpha));
            volView.redraw(volAlpha);
        });
        volAnim.addListener(new android.animation.AnimatorListenerAdapter() {
            boolean cancelled = false;
            @Override public void onAnimationCancel(android.animation.Animator an) { cancelled = true; }
            @Override public void onAnimationEnd(android.animation.Animator an) { if (!cancelled) volHideNow(); }
        });
        volAnim.start();
    }

    private void volHideNow() {
        volH.removeCallbacks(volHideRun);
        if (volAnim != null) { volAnim.cancel(); volAnim = null; }
        volPendingIn = false;
        if (volView != null && root != null) {
            try { root.removeView(volView); } catch (Throwable ignored) { }
        }
        volView = null;
        volAlpha = 0f;
    }

    private class VolView extends SurfaceView implements SurfaceHolder.Callback {
        private final android.graphics.Paint p = new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        private final android.graphics.Path body = new android.graphics.Path();
        VolView(Context c) {
            super(c);
            setZOrderOnTop(true);
            getHolder().setFormat(PixelFormat.TRANSLUCENT);
            getHolder().addCallback(this);
            body.moveTo(3, 9); body.lineTo(3, 15); body.lineTo(7, 15); body.lineTo(12, 20); body.lineTo(12, 4); body.lineTo(7, 9); body.close();
        }
        private int al(int color, float a) { return Color.argb(Math.round(Color.alpha(color) * a), Color.red(color), Color.green(color), Color.blue(color)); }
        void redraw(float a) {
            SurfaceHolder h = getHolder();
            Surface sf = h.getSurface();
            if (sf == null || !sf.isValid() || getWidth() <= 0 || getHeight() <= 0) return;
            Canvas c = null;
            try {
                c = h.lockCanvas();
                if (c == null) return;
                c.drawColor(0, android.graphics.PorterDuff.Mode.CLEAR);
                drawPanel(c, a);
            } catch (Throwable ignored) {
            } finally {
                if (c != null) { try { h.unlockCanvasAndPost(c); } catch (Throwable ignored) { } }
            }
        }
        private void drawPanel(Canvas c, float a) {
            // Win11 ses göstergesi: referans fotoğraftan ölçüldü (panel 509x135 -> k = yükseklik/135).
            final float d = volDens, w = getWidth(), hh = getHeight();
            final float k = hh / 135f;
            final boolean dark = volW11 && volDark;
            final int bg    = dark ? Color.argb(0xF2, 0x2C, 0x2C, 0x2C) : Color.argb(0xF2, 0xD0, 0xD5, 0xE6);
            final int txt   = dark ? Color.WHITE : 0xFF3B3B45;
            final int track = dark ? Color.argb(0x73, 255, 255, 255) : 0xFFA6A8B5;
            final int fill  = dark ? 0xFF60CDFF : 0xFF1563B6;
            final float rad = 20f * k;
            android.graphics.RectF r = new android.graphics.RectF(0, 0, w, hh);
            p.setStyle(android.graphics.Paint.Style.FILL);
            p.setColor(al(bg, a));
            c.drawRoundRect(r, rad, rad, p);

            // hoparlör simgesi: içi boş (çizgi) hoparlör + ses düzeyine göre 1-3 dalga; boyut 38x31 (fotoğraf birimi)
            float s = 38f * k / 20.5f, ix = 46f * k - 3f * s + 0.8f * s, iy = hh / 2f - 12 * s;
            c.save();
            c.translate(ix, iy);
            c.scale(s, s);
            p.setColor(al(txt, a));
            p.setStyle(android.graphics.Paint.Style.STROKE);
            p.setStrokeCap(android.graphics.Paint.Cap.ROUND);
            p.setStrokeJoin(android.graphics.Paint.Join.ROUND);
            p.setStrokeWidth(1.5f);
            c.drawPath(body, p);
            if (volMuted) {
                c.drawLine(15.5f, 9.5f, 21.5f, 14.5f, p);
                c.drawLine(21.5f, 9.5f, 15.5f, 14.5f, p);
            } else {
                int waves = volPct < 34 ? 1 : 2;
                android.graphics.RectF a1 = new android.graphics.RectF(8, 8, 16, 16);
                android.graphics.RectF a2 = new android.graphics.RectF(4, 4, 20, 20);
                c.drawArc(a1, -40, 80, false, p);
                if (waves >= 2 || volPct >= 67) c.drawArc(a2, -42, 84, false, p);
            }
            c.restore();

            // çubuk: x 136..464 (fotoğraf birimi), kalınlık 12, uçlar yuvarlak, tutamaç ve yüzde yazısı YOK
            float x0 = 136f * k, x1 = w - 44f * k, cy = hh / 2f, th = 12f * k;
            android.graphics.RectF tr = new android.graphics.RectF(x0, cy - th / 2, x1, cy + th / 2);
            p.setStyle(android.graphics.Paint.Style.FILL);
            p.setColor(al(track, a));
            c.drawRoundRect(tr, th / 2, th / 2, p);
            float frac = volMuted ? 0f : Math.max(0f, Math.min(1f, volPct / 100f));
            if (frac > 0f) {
                android.graphics.RectF fr = new android.graphics.RectF(x0, cy - th / 2, x0 + (x1 - x0) * frac, cy + th / 2);
                p.setColor(al(fill, a));
                c.drawRoundRect(fr, th / 2, th / 2, p);
            }
        }
        @Override public void surfaceCreated(SurfaceHolder holder) {
            redraw(volAlpha);
            if (volPendingIn) { volPendingIn = false; volAnimIn(); }
        }
        @Override public void surfaceChanged(SurfaceHolder holder, int format, int w, int h) { redraw(volAlpha); }
        @Override public void surfaceDestroyed(SurfaceHolder holder) { }
        @Override public boolean onTouchEvent(MotionEvent ev) { return false; }
    }

    // ===================== Sanal fare imleci: native, her şeyin üstünde =====================
    // Imleç artık HTML'de değil, root'a EN SON eklenen saydam bir SurfaceView'de çizilir. Böylece index.html'in,
    // Android uygulama pencerelerinin (VdSurfaceView) ve tarayıcı WebView'lerinin (NWebView) üstünde kalır.
    // Tıklama/hover/kaydırma imlecin altındaki hedefe gerçek fare olayı (SOURCE_MOUSE) olarak gönderilir.
    private volatile boolean vcOn = false;
    private CursorView vcView;
    private volatile Bitmap vcBmp;
    private volatile float vcCssW = 32, vcCssH = 32, vcHotX = 0, vcHotY = 0, vcX = -1, vcY = -1, vcScale = 1f;
    private final java.util.concurrent.atomic.AtomicBoolean vcPosPending = new java.util.concurrent.atomic.AtomicBoolean(false);
    private View vcCapture, vcHoverTgt;     // yalnızca JavaBridge iş parçacığında kullanılır
    private boolean vcHtmlDown = false;
    private long vcDownTime = 0;

    // ===================== Gerçek fare (OTG / Bluetooth) =====================
    // Fare takılınca HTML (w7vm-js) sanal fareyi otomatik açar ve vcPhys(true) çağırır. Burada "pointer capture" istenir:
    // sistemin kendi imleci gizlenir, fare hareketi/tuşları/tekerleği göreli olarak gelir ve sanal imleci sürmek için HTML'e iletilir.
    private volatile boolean physMouse = false;     // gerçek fare modu etkin (pointer capture isteniyor)
    private volatile boolean physPresent = false;   // takılı bir fare var
    private android.hardware.input.InputManager physMgr;
    private float physDx = 0, physDy = 0;
    private int physBtn = 0;
    private boolean physPend = false;
    private final Runnable physRun = () -> { if (physPend) physFlush(0f, 0f); };
    private final android.hardware.input.InputManager.InputDeviceListener physListener =
            new android.hardware.input.InputManager.InputDeviceListener() {
                @Override public void onInputDeviceAdded(int id) { physSchedule(150); }
                @Override public void onInputDeviceRemoved(int id) { physSchedule(150); }
                @Override public void onInputDeviceChanged(int id) { physSchedule(400); }
            };
    private final Handler physH = new Handler(android.os.Looper.getMainLooper());
    private final Runnable physScanRun = () -> physRefresh();
    private int physMiss = 0;          // üst üste kaç taramada fare bulunamadı (çıkarma doğrulaması)
    private int physRetry = 0;         // yakalama kaybında yeniden deneme sayacı
    private volatile boolean physCap = false;   // pointer capture şu an gerçekten aktif mi

    private void physSchedule(long delay) {
        physH.removeCallbacks(physScanRun);
        physH.postDelayed(physScanRun, delay);
    }

    private void physNotifyCap(boolean c) {
        if (webView != null) webView.evaluateJavascript("window.__w7vmCap&&window.__w7vmCap(" + c + ");", null);
    }

    @SuppressLint("NewApi")
    private void physInit() {
        try {
            physPresent = physScan();
            physMgr = (android.hardware.input.InputManager) getSystemService(Context.INPUT_SERVICE);
            if (physMgr != null) physMgr.registerInputDeviceListener(physListener, new Handler(android.os.Looper.getMainLooper()));
            if (Build.VERSION.SDK_INT >= 26) {
                View.OnCapturedPointerListener l = (v, e) -> physCaptured(e);
                webView.setOnCapturedPointerListener(l);
                root.setOnCapturedPointerListener(l);
            }
        } catch (Throwable ignored) { }
    }

    /** Sanal olmayan, fare kaynağı olan bir giriş cihazı var mı? (pointer capture için Android 8+) */
    private boolean physScan() {
        if (Build.VERSION.SDK_INT < 26) return false;
        try {
            for (int id : InputDevice.getDeviceIds()) {
                InputDevice d = InputDevice.getDevice(id);
                if (d == null || d.isVirtual()) continue;
                int src = d.getSources();
                // Pointer capture açıkken Android fareyi SOURCE_MOUSE yerine SOURCE_MOUSE_RELATIVE olarak bildirir.
                // Sadece SOURCE_MOUSE'a bakmak yakalamayı açınca "fare çıktı" sanıp kapatma -> açma döngüsü yapıyordu.
                if ((src & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE
                        || (src & InputDevice.SOURCE_MOUSE_RELATIVE) == InputDevice.SOURCE_MOUSE_RELATIVE) return true;
            }
        } catch (Throwable ignored) { }
        return false;
    }

    /** Cihaz eklenince/çıkınca (UI iş parçacığı) HTML'e haber verir. */
    private void physRefresh() {
        boolean has = physScan();
        if (has) {
            physMiss = 0;
            if (physPresent) return;
            physPresent = true;
        } else {
            if (!physPresent) { physMiss = 0; return; }
            // Çıkarma tek taramayla kabul edilmez: 3 ardışık taramada yoksa gerçekten çıkmıştır (~1 sn)
            if (++physMiss < 3) { physH.postDelayed(physScanRun, 400); return; }
            physMiss = 0;
            physPresent = false;
        }
        if (webView != null) webView.evaluateJavascript("window.__w7vmPhys&&window.__w7vmPhys(" + physPresent + ");", null);
    }

    /** Fare yakalamayı aç/kapat (UI iş parçacığı). */
    @SuppressLint("NewApi")
    private void physApply() {
        if (Build.VERSION.SDK_INT < 26 || root == null) return;
        try {
            if (physMouse) {
                if (webView != null && root.findFocus() == null) webView.requestFocus();
                if (!root.hasPointerCapture()) root.requestPointerCapture();
            } else {
                if (root.hasPointerCapture()) root.releasePointerCapture();
                physDx = 0; physDy = 0; physBtn = 0; physPend = false;
            }
        } catch (Throwable ignored) { }
    }

    /** Yakalanan fare olayı: hareketi biriktirir, tuş/tekerlek değişince hemen HTML'e yollar. */
    private boolean physCaptured(MotionEvent ev) {
        if (!physMouse || ev == null) return false;
        if ((ev.getSource() & InputDevice.SOURCE_MOUSE_RELATIVE) != InputDevice.SOURCE_MOUSE_RELATIVE) return false;
        int act = ev.getActionMasked();
        if (act == MotionEvent.ACTION_MOVE || act == MotionEvent.ACTION_HOVER_MOVE) {
            physDx += ev.getX();
            physDy += ev.getY();
        }
        float hs = 0, vs = 0;
        if (act == MotionEvent.ACTION_SCROLL) {
            hs = ev.getAxisValue(MotionEvent.AXIS_HSCROLL);
            vs = ev.getAxisValue(MotionEvent.AXIS_VSCROLL);
        }
        int bs = ev.getButtonState() & 7;
        if (bs != physBtn || hs != 0 || vs != 0) {
            physBtn = bs;
            physFlush(hs, vs);
        } else if (!physPend) {
            physPend = true;
            if (root != null) root.postOnAnimation(physRun);
        }
        return true;
    }

    private void physFlush(float hs, float vs) {
        physPend = false;
        if (webView == null) return;
        float sc = vcScale > 0 ? vcScale : 1f;
        float dx = physDx / sc, dy = physDy / sc;
        physDx = 0; physDy = 0;
        webView.evaluateJavascript("window.__w7vmPhysEv&&window.__w7vmPhysEv(" + dx + "," + dy + "," + physBtn + "," + hs + "," + vs + ");", null);
    }

    private class CursorView extends SurfaceView implements SurfaceHolder.Callback {
        private final android.graphics.Paint pnt = new android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG);
        CursorView(Context c) {
            super(c);
            setZOrderOnTop(true);
            getHolder().setFormat(PixelFormat.TRANSLUCENT);
            getHolder().addCallback(this);
        }
        void redraw() {
            SurfaceHolder h = getHolder();
            Surface sf = h.getSurface();
            if (sf == null || !sf.isValid() || getWidth() <= 0 || getHeight() <= 0) return;
            Canvas c = null;
            try {
                c = h.lockCanvas();
                if (c == null) return;
                c.drawColor(0, android.graphics.PorterDuff.Mode.CLEAR);
                Bitmap b = vcBmp;
                if (b != null) c.drawBitmap(b, null, new Rect(0, 0, getWidth(), getHeight()), pnt);
            } catch (Throwable ignored) {
            } finally {
                if (c != null) { try { h.unlockCanvasAndPost(c); } catch (Throwable ignored) { } }
            }
        }
        @Override public void surfaceCreated(SurfaceHolder holder) { redraw(); }
        @Override public void surfaceChanged(SurfaceHolder holder, int format, int w, int h) { redraw(); }
        @Override public void surfaceDestroyed(SurfaceHolder holder) { }
        @Override public boolean onTouchEvent(MotionEvent ev) { return false; }
    }

    private void vcEnsure() {
        if (vcView != null || root == null) return;
        vcView = new CursorView(this);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        root.addView(vcView, lp);
        vcView.setTranslationX(-20000);
    }

    /** Imleç yüzeyini yeniden oluşturup en yeni (= en üstteki) SurfaceView yapar. UI iş parçacığı. */
    private void vcTop() {
        if (vcView == null || root == null || !vcOn) return;
        ViewGroup.LayoutParams lp = vcView.getLayoutParams();
        root.removeView(vcView);
        root.addView(vcView, lp);
        vcApply();
    }

    private void vcApply() {
        if (vcView == null) return;
        float s = vcScale;
        if (s <= 0) return;
        int pw = Math.max(2, Math.round(vcCssW * s)), ph = Math.max(2, Math.round(vcCssH * s));
        FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) vcView.getLayoutParams();
        if (lp.width != pw || lp.height != ph) {
            lp.width = pw;
            lp.height = ph;
            vcView.setLayoutParams(lp);
        }
        if (!vcOn || vcX < 0) { vcView.setTranslationX(-20000); return; }
        vcView.setTranslationX((vcX - vcHotX) * s);
        vcView.setTranslationY((vcY - vcHotY) * s);
    }

    /** (px,py) root fiziksel pikseli altındaki en üstteki görünür native pencere (VD uygulama / tarayıcı WebView), yoksa null. */
    private View vcHit(float px, float py) {
        try {
            for (int i = root.getChildCount() - 1; i >= 0; i--) {
                View v = root.getChildAt(i);
                if (v == null || v == webView || v == vcView || v.getVisibility() != View.VISIBLE) continue;
                if (v instanceof VdSurfaceView) {
                    VdWin w = ((VdSurfaceView) v).win;
                    if (!w.opened || w.live || w.displayId < 0) continue;   // canlı (JPEG) modda girdiyi HTML alır
                } else if (!(v instanceof NWebView) && !(v instanceof VncView)) continue;
                float tx = v.getTranslationX(), ty = v.getTranslationY();
                if (tx < -10000) continue;
                ViewGroup.LayoutParams lp = v.getLayoutParams();
                float l = tx, t = ty, r = tx + lp.width, b = ty + lp.height;
                Rect c = v.getClipBounds();
                if (c != null) { l = tx + c.left; t = ty + c.top; r = tx + c.right; b = ty + c.bottom; }
                if (px >= l && px < r && py >= t && py < b) return v;
            }
        } catch (Throwable ignored) { }
        return null;
    }

    private static java.lang.reflect.Method sSetActionButton;

    /** MotionEvent.setActionButton gizli (@hide) API; genel SDK'da yok, bu yüzden yansıma ile çağrılır. */
    private static void vcSetActionButton(MotionEvent ev, int ab) {
        try {
            if (sSetActionButton == null) {
                sSetActionButton = MotionEvent.class.getDeclaredMethod("setActionButton", int.class);
                sSetActionButton.setAccessible(true);
            }
            sSetActionButton.invoke(ev, ab);
        } catch (Throwable ignored) { }
    }

    private boolean vcSend(View v, int action, float lx, float ly, int buttons, int ab, float hs, float vs, long down, boolean generic) {
        MotionEvent.PointerProperties pp = new MotionEvent.PointerProperties();
        pp.id = 0;
        pp.toolType = MotionEvent.TOOL_TYPE_MOUSE;
        MotionEvent.PointerCoords pc = new MotionEvent.PointerCoords();
        pc.x = lx; pc.y = ly; pc.size = 1f;
        pc.pressure = buttons != 0 ? 1f : 0f;
        pc.setAxisValue(MotionEvent.AXIS_HSCROLL, hs);
        pc.setAxisValue(MotionEvent.AXIS_VSCROLL, vs);
        long now = SystemClock.uptimeMillis();
        MotionEvent ev = MotionEvent.obtain(down > 0 ? down : now, now, action, 1,
                new MotionEvent.PointerProperties[]{pp}, new MotionEvent.PointerCoords[]{pc},
                0, buttons, 1f, 1f, 0, 0, InputDevice.SOURCE_MOUSE, 0);
        if (ab != 0) vcSetActionButton(ev, ab);
        try { return generic ? v.dispatchGenericMotionEvent(ev) : v.dispatchTouchEvent(ev); }
        finally { ev.recycle(); }
    }

    private void vcExit(NWebView wv, float px, float py) {
        vcSend(wv, MotionEvent.ACTION_HOVER_EXIT, px - wv.getTranslationX(), py - wv.getTranslationY(), 0, 0, 0, 0, 0, true);
    }

    /** UI iş parçacığı. action: 0 bas, 1 bırak, 2 basılıyken hareket, 7 hover, 8 tekerlek. */
    private void vcDeliver(View v, int action, float px, float py, int buttons, int ab, float hs, float vs, long down) {
        final float lx = px - v.getTranslationX(), ly = py - v.getTranslationY();
        if (v instanceof NWebView) {
            NWebView wv = (NWebView) v;
            switch (action) {
                case 0:
                    wv.requestFocus();
                    vcSend(wv, MotionEvent.ACTION_DOWN, lx, ly, buttons, 0, 0, 0, down, false);
                    vcSend(wv, MotionEvent.ACTION_BUTTON_PRESS, lx, ly, buttons, ab, 0, 0, down, true);
                    break;
                case 2: vcSend(wv, MotionEvent.ACTION_MOVE, lx, ly, buttons, 0, 0, 0, down, false); break;
                case 1:
                    vcSend(wv, MotionEvent.ACTION_BUTTON_RELEASE, lx, ly, 0, ab, 0, 0, down, true);
                    vcSend(wv, MotionEvent.ACTION_UP, lx, ly, 0, 0, 0, 0, down, false);
                    break;
                case 7: vcSend(wv, MotionEvent.ACTION_HOVER_MOVE, lx, ly, 0, 0, 0, 0, down, true); break;
                case 8: vcSend(wv, MotionEvent.ACTION_SCROLL, lx, ly, 0, 0, hs, vs, down, true); break;
                default: break;
            }
        } else if (v instanceof VncView) {
            ((VncView) v).injectMouse(action, lx, ly, buttons, vs);
        } else if (v instanceof VdSurfaceView) {
            final VdSurfaceView sv = (VdSurfaceView) v;
            final VdWin win = sv.win;
            final int did = win.displayId, w = v.getWidth(), h = v.getHeight(), rot = win.rot;
            if (did < 0 || w <= 0 || h <= 0 || vdSvc == null) return;
            final float nx = Math.max(0f, Math.min(1f, lx / w)), ny = Math.max(0f, Math.min(1f, ly / h));
            if (action == 0) { win.mouseDown = SystemClock.uptimeMillis(); sv.focusMe(); }
            final long dn = win.mouseDown;
            final int act = action, bs = buttons, abn = ab;
            final float fhs = hs, fvs = vs;
            touchIo.execute(() -> {
                try {
                    IVdService svc = vdSvc;
                    if (svc == null) return;
                    switch (act) {
                        case 0:
                            vdInjectMouse(svc, did, MotionEvent.ACTION_DOWN, nx, ny, bs, 0, 0, 0, dn, rot);
                            vdInjectMouse(svc, did, MotionEvent.ACTION_BUTTON_PRESS, nx, ny, bs, abn, 0, 0, dn, rot);
                            break;
                        case 2: vdInjectMouse(svc, did, MotionEvent.ACTION_MOVE, nx, ny, bs, 0, 0, 0, dn, rot); break;
                        case 1:
                            vdInjectMouse(svc, did, MotionEvent.ACTION_BUTTON_RELEASE, nx, ny, 0, abn, 0, 0, dn, rot);
                            vdInjectMouse(svc, did, MotionEvent.ACTION_UP, nx, ny, 0, 0, 0, 0, dn, rot);
                            break;
                        case 7: vdInjectMouse(svc, did, MotionEvent.ACTION_HOVER_MOVE, nx, ny, 0, 0, 0, 0, dn, rot); break;
                        case 8: vdInjectMouse(svc, did, MotionEvent.ACTION_SCROLL, nx, ny, 0, 0, fhs, fvs, dn, rot); break;
                        default: break;
                    }
                } catch (Throwable ignored) { }
            });
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (vcOn && root != null) root.postDelayed(this::vcTop, 300);   // yüzeyler yeniden oluşunca imleç yine en üstte olsun
        volRegister(true);
        if (volRead()) volPushJs();   // uygulama arka plandayken ses değiştiyse çubuklar güncellensin
        if (homeAsked) {              // Ana ekran seçimi ekranından döndük: Ayarlar'daki durum yazısını yenile
            homeAsked = false;
            if (root != null) root.postDelayed(this::homeChanged, 300);
        }
    }

    @Override
    protected void onPause() {
        volRegister(false);
        volHideNow();
        flushCookies();   // uygulama arka plana gidince / kapanınca giriş çerezleri kaybolmasın
        super.onPause();
    }

    @Override
    protected void onStop() {
        flushCookies();
        super.onStop();
    }

    /** Bir Win7 penceresinin sanal ekranı + onu gösteren SurfaceView */
    private class VdWin {
        final int id;
        VdSurfaceView view;
        volatile int displayId = -1;
        volatile boolean opened = false;
        volatile int w = 0, h = 0;
        Runnable pendingOpen;
        volatile long touchDown = 0, mouseDown = 0;   // JPEG (HTML) modunda iletilen girdinin downTime'ı
        volatile int rot = 7;   // girdi kodu: 7 = otomatik dönüş, 0..3 = dönüş, +16 = x/y yer değiştir
        // --- sürüklerken canlı JPEG kare modu (hibrit) ---
        volatile boolean live = false;
        volatile ImageReader reader;
        HandlerThread liveT;
        Handler liveH;
        final Object frameLock = new Object();
        byte[] frame;
        long frameSeq = 0, servedSeq = 0;
        volatile long lastEnc = 0;
        // kare başına bellek tahsisini önlemek için yeniden kullanılan nesneler (yalnızca liveH iş parçacığında kullanılır)
        Bitmap fullBmp, outBmp;
        final ByteArrayOutputStream jbo = new ByteArrayOutputStream(96 * 1024);
        final Rect srcR = new Rect(), dstR = new Rect();
        final android.graphics.Paint pnt = new android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG);
        final java.util.concurrent.atomic.AtomicBoolean resizing = new java.util.concurrent.atomic.AtomicBoolean(false);
        VdWin(int id) { this.id = id; }
    }

    /** UI iş parçacığında çağrılmalı. Kapatılmış pencere için null döner. */
    private VdWin getWin(int id) {
        if (vdDead.contains(id)) return null;
        VdWin w = vdWins.get(id);
        if (w == null) {
            w = new VdWin(id);
            w.view = new VdSurfaceView(this, w);
            FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(2, 2);
            lp.gravity = Gravity.TOP | Gravity.LEFT;
            root.addView(w.view, lp);
            w.view.setTranslationX(-20000); // başta ekran dışında (görünmez) bekler
            vdWins.put(id, w);
            if (vcOn && root != null) root.postDelayed(this::vcTop, 400);
        }
        return w;
    }

    /** Surface hazır olunca sanal ekranı açıp uygulamayı başlatır. */
    private void startDisplay(final VdWin win, final String key, final String cb) {
        final Surface surface = win.view.getHolder().getSurface();
        final int w = win.view.getWidth(), h = win.view.getHeight();
        win.w = w; win.h = h;
        vdIo.execute(() -> {
            try {
                if (vdDead.contains(win.id)) return;
                if (!ensureService()) {
                    jsCall(cb, "{\"ok\":false,\"err\":\"Shizuku servisine bağlanılamadı\"}");
                    return;
                }
                int id = vdSvc.open(surface, w, h, displayDpi());
                if (id < 0) {
                    jsCall(cb, "{\"ok\":false,\"err\":" + JSONObject.quote(vdSvc.lastError()) + "}");
                    return;
                }
                win.displayId = id;
                win.opened = true;
                if (vdDead.contains(win.id)) { // açılırken pencere kapatıldı
                    vdSvc.close(id);
                    return;
                }
                String comp = key.replace('|', '/');
                String err = vdSvc.launch(id, comp);
                if (err != null && err.length() > 0) {
                    jsCall(cb, "{\"ok\":false,\"displayId\":" + id + ",\"err\":" + JSONObject.quote(err) + "}");
                } else {
                    jsCall(cb, "{\"ok\":true,\"displayId\":" + id + "}");
                }
            } catch (Throwable t) {
                jsCall(cb, "{\"ok\":false,\"err\":" + JSONObject.quote(String.valueOf(t.getMessage())) + "}");
            }
        });
    }

    /** Sanal ekranın görüntüsünü gösteren ve dokunmaları sanal ekrana ileten katman. */
    private class VdSurfaceView extends SurfaceView implements SurfaceHolder.Callback {
        private final VdWin win;

        VdSurfaceView(Context c, VdWin win) {
            super(c);
            this.win = win;
            setZOrderOnTop(true);
            getHolder().setFormat(PixelFormat.RGBA_8888);
            getHolder().addCallback(this);
        }

        @Override public void surfaceCreated(SurfaceHolder holder) { if (vcOn && root != null) root.postDelayed(MainActivity.this::vcTop, 150); }

        @Override
        public void surfaceChanged(SurfaceHolder holder, int format, final int w, final int h) {
            if (w < 8 || h < 8) return;
            if (win.pendingOpen != null) {
                Runnable r = win.pendingOpen;
                win.pendingOpen = null;
                r.run();
            } else if (win.opened) {
                if (win.live) return;   // canlı kare modunda sanal ekran ImageReader'a bağlı; bırakınca geri döner
                win.w = w; win.h = h;
                // Boyutlandırırken art arda gelen değişiklikler tek bir resize'a birleştirilir (en son boyut kullanılır)
                if (win.resizing.compareAndSet(false, true)) {
                    vdIo.execute(() -> {
                        win.resizing.set(false);
                        try {
                            int did = win.displayId;
                            Surface sf = win.view.getHolder().getSurface();
                            if (win.live || vdSvc == null || did < 0 || !sf.isValid()) return;
                            vdSvc.resize(did, sf, win.w, win.h, displayDpi());
                        } catch (Throwable ignored) { }
                    });
                }
            }
        }

        @Override public void surfaceDestroyed(SurfaceHolder holder) { }

        private boolean isMouse(MotionEvent ev) {
            return ev.getToolType(0) == MotionEvent.TOOL_TYPE_MOUSE
                    || (ev.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE;
        }

        private void focusMe() {
            if (webView != null) webView.evaluateJavascript(
                    "window.__w7vdFocus&&window.__w7vdFocus(" + win.id + ");", null);
        }

        /** Fare olayını (dokunma / hover / tuş / tekerlek) gerçek fare olarak sanal ekrana iletir. */
        private void sendMouse(MotionEvent ev) {
            final int did = win.displayId;
            if (did < 0 || getWidth() <= 0 || getHeight() <= 0) return;
            final int action = ev.getActionMasked();
            final float nx = ev.getX() / getWidth(), ny = ev.getY() / getHeight();
            final int bs = ev.getButtonState(), ab = ev.getActionButton();
            final float hs = ev.getAxisValue(MotionEvent.AXIS_HSCROLL), vs = ev.getAxisValue(MotionEvent.AXIS_VSCROLL);
            final long down = ev.getDownTime();
            final int rot = win.rot;
            touchIo.execute(() -> {
                try { if (vdSvc != null) vdInjectMouse(vdSvc, did, action, nx, ny, bs, ab, hs, vs, down, rot); } catch (Throwable ignored) { }
            });
        }

        @Override
        public boolean onGenericMotionEvent(MotionEvent ev) {
            if (!win.opened || !isMouse(ev)) return false;
            sendMouse(ev);   // hover, tekerlek, fare tuşu basma/bırakma
            return true;
        }

        @Override
        public boolean onTouchEvent(MotionEvent ev) {
            if (!win.opened || getWidth() <= 0 || getHeight() <= 0) return false;
            Rect clip = getClipBounds();
            if (ev.getActionMasked() == MotionEvent.ACTION_DOWN) {
                if (clip != null && !clip.contains((int) ev.getX(), (int) ev.getY())) {
                    return false; // görev çubuğu vb. altına kırpılan bölge
                }
                focusMe();   // dokunulan pencere öne gelsin
            }
            if (isMouse(ev)) { sendMouse(ev); return true; }
            final int did = win.displayId;
            final int n = ev.getPointerCount();
            final float[] xs = new float[n], ys = new float[n];
            final int[] ids = new int[n];
            for (int i = 0; i < n; i++) {
                xs[i] = ev.getX(i) / getWidth();
                ys[i] = ev.getY(i) / getHeight();
                ids[i] = ev.getPointerId(i);
            }
            final int action = ev.getActionMasked(), idx = ev.getActionIndex();
            final long down = ev.getDownTime();
            final int rot = win.rot;
            touchIo.execute(() -> {
                try { if (vdSvc != null && did >= 0) vdSvc.injectTouch(did, action, idx, xs, ys, ids, n, down, rot); } catch (Throwable ignored) { }
            });
            return true;
        }
    }

    /** JS <-> Android köprüsü: kalıcı depolama + (opsiyonel) site bilgisi çekme */
    public class AndroidBridge {


        // ------------------------------------------------------------ Dosya Gezgini (gerçek telefon dosyaları)

        /** Tüm dosyalara erişim izni var mı? */
        @JavascriptInterface
        public boolean fsAccess() {
            return FileOps.hasAccess(MainActivity.this);
        }

        /** İzin ekranını açar (Android 11+: "Tüm dosyalara erişim"; daha eskide normal depolama izni). */
        @JavascriptInterface
        public void fsRequestAccess() {
            runOnUiThread(() -> {
                try {
                    if (Build.VERSION.SDK_INT >= 30) {
                        try {
                            Intent i = new Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    android.net.Uri.parse("package:" + getPackageName()));
                            startActivity(i);
                        } catch (Throwable t) {
                            startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
                        }
                    } else if (Build.VERSION.SDK_INT >= 23) {
                        requestPermissions(new String[]{
                                android.Manifest.permission.READ_EXTERNAL_STORAGE,
                                android.Manifest.permission.WRITE_EXTERNAL_STORAGE}, 9002);
                    }
                } catch (Throwable ignored) { }
            });
        }

        /** İzin verildikten sonra standart klasörleri (İndirilenler, Belgeler, ... Projeler) hazırlar. */
        @JavascriptInterface
        public void fsEnsure() {
            if (FileOps.hasAccess(MainActivity.this)) FileOps.ensureStd();
        }

        /** Klasör listesi (sanal yol, kök = ""). */
        @JavascriptInterface
        public String fsList(String path) {
            if (!FileOps.hasAccess(MainActivity.this)) return "{\"ok\":false,\"err\":\"noaccess\"}";
            return FileOps.list(path);
        }

        @JavascriptInterface
        public String fsMkdir(String parent, String name) {
            return FileOps.mkdir(parent, name);
        }

        @JavascriptInterface
        public String fsNewFile(String parent, String name) {
            return FileOps.newFile(parent, name);
        }

        @JavascriptInterface
        public String fsRename(String path, String newName) {
            return FileOps.rename(path, newName);
        }

        @JavascriptInterface
        public String fsOpen(String path) {
            return FileOps.open(MainActivity.this, path);
        }

        /** HTML dosyasını tarayıcı pencerelerinde (Chrome / IE / Nova) açmak için adres: {"ok":true,"url":"https://w7media.local/h/..."} */
        @JavascriptInterface
        public String fsWebUrl(String path) {
            return FileOps.webUrl(MainActivity.this, path);
        }

        @JavascriptInterface
        public String fsSpace() {
            return FileOps.space();
        }

        /** Silme (arka planda). Sonuç: callback({ok,err?}) */
        @JavascriptInterface
        public void fsDelete(final String path, final String cb) {
            fsIo.execute(() -> jsCall(cb, FileOps.delete(path)));
        }

        /** Kopyala / taşı (arka planda). Sonuç: callback({ok,err?}) */
        @JavascriptInterface
        public void fsPaste(final String src, final String destDir, final boolean move, final String cb) {
            fsIo.execute(() -> jsCall(cb, FileOps.paste(src, destDir, move)));
        }

        /** Zip'i ayıklar (arka planda). intoNew: hedefte zip adıyla yeni klasör. Sonuç: callback({ok,n,skipped,dir?,err?}) */
        @JavascriptInterface
        public void fsZipExtract(final String zipPath, final String destDir, final boolean intoNew, final String cb) {
            zipIo.execute(() -> jsCall(cb, FileOps.zipExtract(zipPath, destDir, intoNew)));
        }

        /** Seçili öğeleri zip'e sıkıştırır (arka planda). namesJson: ["ad1","ad2"]. Sonuç: callback({ok,name,n,skipped,err?}) */
        @JavascriptInterface
        public void fsZipCreate(final String parent, final String namesJson, final String zipName, final String cb) {
            zipIo.execute(() -> jsCall(cb, FileOps.zipCreate(parent, namesJson, zipName)));
        }

        /** Son değiştirilen dosyalar (arka planda). Sonuç: callback({ok,items}) */
        @JavascriptInterface
        public void fsRecent(final int max, final String cb) {
            fsIo.execute(() -> jsCall(cb, FileOps.recent(max)));
        }

        /** Kurulum sihirbazı: yalnızca https bağlantılarını dış tarayıcıda açar. */
        @JavascriptInterface
        public void openUrl(final String url) {
            runOnUiThread(() -> {
                try {
                    if (url != null && url.startsWith("https://")) {
                        startActivity(new Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)));
                    }
                } catch (Throwable ignored) { }
            });
        }

        /** Kurulum sihirbazı: Shizuku uygulamasını açar (kuruluysa). */
        @JavascriptInterface
        public void openShizuku() {
            runOnUiThread(() -> {
                try {
                    Intent i = getPackageManager().getLaunchIntentForPackage("moe.shizuku.privileged.api");
                    if (i != null) startActivity(i);
                } catch (Throwable ignored) { }
            });
        }

        /** Kurulum sihirbazı: {"termux":bool} (Termux kurulu mu). */
        @JavascriptInterface
        public String termuxStatus() {
            return "{\"termux\":" + pkgInstalled("com.termux") + "}";
        }

        /** Kurulum sihirbazı: Termux uygulamasını açar (kuruluysa). */
        @JavascriptInterface
        public void openTermux() {
            runOnUiThread(() -> {
                try {
                    Intent i = getPackageManager().getLaunchIntentForPackage("com.termux");
                    if (i != null) startActivity(i);
                } catch (Throwable ignored) { }
            });
        }

        /** Termux RUN_COMMAND izni verilmiş mi? */
        @JavascriptInterface
        public boolean termuxCanRun() {
            return hasTermuxRunPerm();
        }

        /** Termux RUN_COMMAND iznini ister; sonuç cb(true/false). */
        @JavascriptInterface
        public void termuxRequestRun(final String cb) {
            runOnUiThread(() -> {
                try {
                    if (!pkgInstalled("com.termux")) { jsCall(cb, "false"); return; }
                    if (hasTermuxRunPerm()) { jsCall(cb, "true"); return; }
                    termuxPermCb = cb;
                    requestPermissions(new String[]{PERM_TERMUX_RUN}, TERMUX_RUN_REQ);
                } catch (Throwable t) {
                    jsCall(cb, "false");
                }
            });
        }

        /**
         * Termux'ta komut çalıştırır. json: {path?, args?:[], workdir?, background?:true, session?:0-3}
         * path yalnızca Termux dizini altında olabilir (varsayılan bash). Sonuç cb(json).
         */
        @JavascriptInterface
        public void termuxRun(final String json, final String cb) {
            try {
                JSONObject o = new JSONObject(json == null ? "{}" : json);
                String path = o.optString("path", TERMUX_BASH);
                if (!path.startsWith(TERMUX_PREFIX) || path.contains("..")) {
                    jsCall(cb, termuxErr("bad_path", "Yol Termux dizini altında olmalı")); return;
                }
                String workdir = o.optString("workdir", TERMUX_HOME);
                if (!workdir.startsWith(TERMUX_PREFIX) || workdir.contains("..")) {
                    jsCall(cb, termuxErr("bad_workdir", "Çalışma dizini Termux dizini altında olmalı")); return;
                }
                JSONArray a = o.optJSONArray("args");
                int n = a == null ? 0 : Math.min(a.length(), 64);
                String[] args = new String[n];
                for (int k = 0; k < n; k++) {
                    String v = a.optString(k, "");
                    if (v.length() > 65536) { jsCall(cb, termuxErr("bad_args", "Argüman çok uzun")); return; }
                    args[k] = v;
                }
                boolean bg = o.optBoolean("background", true);
                int session = Math.max(0, Math.min(3, o.optInt("session", 0)));
                final String[] fa = args; final String fp = path, fw = workdir;
                final boolean fbg = bg; final int fs = session;
                runOnUiThread(() -> termuxExec(fp, fa, fw, fbg, fs, cb));
            } catch (Throwable t) {
                jsCall(cb, termuxErr("bad_json", String.valueOf(t.getMessage())));
            }
        }

        /** Kısayol: bash -c "script". background=true ise çıktı cb'ye döner. */
        @JavascriptInterface
        public void termuxShell(final String script, final boolean background, final String cb) {
            if (script == null || script.length() > 65536) {
                jsCall(cb, termuxErr("bad_args", "Komut boş ya da çok uzun")); return;
            }
            runOnUiThread(() -> termuxExec(TERMUX_BASH, new String[]{"-c", script},
                    TERMUX_HOME, background, 0, cb));
        }

        /** Metni panoya kopyalar (kurulum sihirbazındaki komutlar için). */
        @JavascriptInterface
        public void copyText(final String text) {
            runOnUiThread(() -> {
                try {
                    android.content.ClipboardManager cm =
                            (android.content.ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
                    if (cm != null && text != null && text.length() <= 4096) {
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("UltraDroid", text));
                    }
                } catch (Throwable ignored) { }
            });
        }

        // ------------------------------------------------------------ Shizuku / sanal ekran

        /** {"installed":bool,"running":bool,"granted":bool,"sdk":int} */
        @JavascriptInterface
        public String shizukuStatus() {
            return "{\"installed\":" + shizukuInstalled() + ",\"running\":" + shizukuRunning()
                    + ",\"granted\":" + shizukuGranted() + ",\"sdk\":" + Build.VERSION.SDK_INT + "}";
        }

        /** Shizuku izin penceresini açar; sonuç callback(true/false) ile döner. */
        @JavascriptInterface
        public void shizukuRequest(final String cb) {
            runOnUiThread(() -> {
                try {
                    if (!shizukuRunning()) { jsCall(cb, "false"); return; }
                    if (shizukuGranted()) { jsCall(cb, "true"); return; }
                    if (Shizuku.shouldShowRequestPermissionRationale()) { jsCall(cb, "false"); return; }
                    permCb = cb;
                    Shizuku.requestPermission(SHIZUKU_REQ);
                } catch (Throwable t) {
                    jsCall(cb, "false");
                }
            });
        }

        /**
         * wid numaralı pencere için sanal ekranı açıp uygulamayı başlatır.
         * key = "paket|activity". Sonuç: callback({ok, displayId, err}).
         */
        @JavascriptInterface
        public void vdOpen(final int wid, final String key, final String cb) {
            runOnUiThread(() -> {
                if (key == null || !KEY_OK.matcher(key).matches()) {
                    jsCall(cb, "{\"ok\":false,\"err\":\"Geçersiz uygulama\"}");
                    return;
                }
                if (!shizukuGranted()) {
                    jsCall(cb, "{\"ok\":false,\"err\":\"Shizuku izni yok\"}");
                    return;
                }
                final VdWin win = getWin(wid);
                if (win == null) return;
                win.opened = false;
                final Runnable go = () -> startDisplay(win, key, cb);
                if (win.view.getHolder().getSurface().isValid() && win.view.getWidth() >= 8 && win.view.getHeight() >= 8) {
                    go.run();
                } else {
                    win.pendingOpen = go; // surfaceChanged'de çalışır
                }
            });
        }

        /**
         * Pencerenin katmanını HTML penceresinin içindeki alana oturtur. Tüm değerler CSS pikseli.
         * (l,t,w,h) = pencere gövdesi, (cl,ct,cr,cb) = ekranda görünen (kırpılmış) bölge,
         * viewW = HTML tarafındaki innerWidth.
         */
        @JavascriptInterface
        public void vdRect(final int wid, final float l, final float t, final float w, final float h, final boolean vis,
                           final float cl, final float ct, final float cr, final float cb, final float viewW) {
            runOnUiThread(() -> {
                if (webView == null || viewW <= 0) return;
                VdWin win = getWin(wid);
                if (win == null) return;
                VdSurfaceView vdView = win.view;
                float s = (float) webView.getWidth() / viewW;
                int pw = Math.max(2, Math.round(w * s)), ph = Math.max(2, Math.round(h * s));
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) vdView.getLayoutParams();
                if (lp.width != pw || lp.height != ph) {
                    lp.width = pw;
                    lp.height = ph;
                    vdView.setLayoutParams(lp);
                }
                if (vis) {
                    vdView.setTranslationX(l * s);
                    vdView.setTranslationY(t * s);
                    vdView.setClipBounds(new Rect(
                            Math.round((cl - l) * s), Math.round((ct - t) * s),
                            Math.round((cr - l) * s), Math.round((cb - t) * s)));
                } else {
                    vdView.setTranslationX(-20000);
                }
            });
        }


        // ------------------------------------------------------------ Yerel WebView köprüsü (iframe yerine)

        /** id numaralı yerel WebView'i oluşturup url'yi yükler. (auth: HTML'in gönderdiği değer; kullanılmaz) */
        @JavascriptInterface
        public void create(final String id, final String url, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches() || !httpUrl(url)) return;
            runOnUiThread(() -> createNative(id, url));
        }

        @JavascriptInterface
        public void navigate(final String id, final String url, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches() || !httpUrl(url)) return;
            runOnUiThread(() -> navigateNative(id, url));
        }

        /** Yerel WebView'in kendi geçmişinde geri. Geri gidilebiliyorsa true. */
        @JavascriptInterface
        public void goBack(final String id, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches()) return;
            runOnUiThread(() -> { WebView wv = nViews.get(id); if (wv != null && wv.canGoBack()) wv.goBack(); });
        }

        @JavascriptInterface
        public void goForward(final String id, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches()) return;
            runOnUiThread(() -> { WebView wv = nViews.get(id); if (wv != null && wv.canGoForward()) wv.goForward(); });
        }

        @JavascriptInterface
        public void reload(final String id, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches()) return;
            runOnUiThread(() -> { WebView wv = nViews.get(id); if (wv != null) wv.reload(); });
        }

        /** "geri,ileri" -> "1,0" gibi (son bilinen durum). */
        @JavascriptInterface
        public String navState(final String id) {
            boolean[] n = id == null ? null : nNav.get(id);
            return n == null ? "0,0" : ((n[0] ? "1" : "0") + "," + (n[1] ? "1" : "0"));
        }

        @JavascriptInterface
        public void destroy(final String id, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches()) return;
            runOnUiThread(() -> destroyNative(id));
        }

        /**
         * WebView'i pencerenin gövdesine oturtur. Tüm değerler FİZİKSEL piksel.
         * (l,t,w,h) = gövde; (cl,ct,cr,cb) = görünen bölge (gövdeye göre).
         */
        @JavascriptInterface
        public void setRect2(final String id, final int l, final int t, final int w, final int h, final boolean vis,
                             final int cl, final int ct, final int cr, final int cb, final String auth) {
            runOnUiThread(() -> {
                VncView vv = vncViews.get(id);
                if (vv != null) {
                    int vw = Math.max(2, w), vh = Math.max(2, h);
                    FrameLayout.LayoutParams vlp = (FrameLayout.LayoutParams) vv.getLayoutParams();
                    if (vlp.width != vw || vlp.height != vh) {
                        vlp.width = vw;
                        vlp.height = vh;
                        vv.setLayoutParams(vlp);
                    }
                    if (vis) {
                        vv.setTranslationX(l);
                        vv.setTranslationY(t);
                        vv.setClipBounds(new Rect(cl, ct, cr, cb));
                    } else {
                        vv.setTranslationX(-20000);
                    }
                    vv.setShown(vis);
                    return;
                }
                WebView wv = nViews.get(id);
                if (wv == null) return;
                int pw = Math.max(2, w), ph = Math.max(2, h);
                FrameLayout.LayoutParams lp = (FrameLayout.LayoutParams) wv.getLayoutParams();
                if (lp.width != pw || lp.height != ph) {
                    lp.width = pw;
                    lp.height = ph;
                    wv.setLayoutParams(lp);
                }
                if (vis) {
                    wv.setTranslationX(l);
                    wv.setTranslationY(t);
                    wv.setClipBounds(new Rect(cl, ct, cr, cb));
                    if (nReload.remove(id)) wv.reload();
                } else {
                    wv.setTranslationX(-20000);
                }
                if (nVnc.contains(id)) vncVisibility(id, wv, vis);
                syncPopup(id);
            });
        }

        /** Masaüstü sitesi modu (gerçek masaüstü User-Agent + geniş viewport). Görünür sayfa yenilenir. */
        @JavascriptInterface
        public void setDesktop(final String id, final boolean on, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches()) return;
            runOnUiThread(() -> setDesktopNative(id, on));
        }

        /** Sayfanın anlık HTML görüntüsünü Downloads'a kaydeder; callback({ok,name} | {ok:false,err}). */
        @JavascriptInterface
        public void saveHtml(final String id, final String cb, final String auth) {
            if (id == null || !NID_OK.matcher(id).matches()) return;
            runOnUiThread(() -> {
                WebView wv = nViews.get(id);
                if (wv == null) { jsCall(cb, errJson("Sayfa bulunamadı")); return; }
                String js = "(function(){try{var d=document.documentElement.cloneNode(true);"
                        + "var sc=d.querySelectorAll('script');for(var i=0;i<sc.length;i++)sc[i].remove();"
                        + "var h=d.querySelector('head');"
                        + "if(h&&!h.querySelector('base')){var b=document.createElement('base');b.href=location.href;h.insertBefore(b,h.firstChild);}"
                        + "var dt=document.doctype?'<!DOCTYPE '+document.doctype.name+'>':'<!DOCTYPE html>';"
                        + "return JSON.stringify({t:document.title||'',u:location.href,h:dt+'\\n'+d.outerHTML});"
                        + "}catch(e){return JSON.stringify({err:String(e)});}})()";
                wv.evaluateJavascript(js, val -> new Thread(() -> {
                    String res;
                    try { res = writeHtmlToDownloads(val); } catch (Throwable t) { res = errJson(String.valueOf(t.getMessage())); }
                    jsCall(cb, res);
                }).start());
            });
        }

        /**
         * WebView'in anlık görüntüsünü JPEG olarak alır; callback(url) ile https://w7vdframe.local/n?k=id adresini verir
         * (alınamazsa null). HTML bunu sürüklerken pencerenin arka planına koyar.
         */
        @JavascriptInterface
        public void snap(final String id, final String cb, final String auth) {
            runOnUiThread(() -> {
                if (vncViews.containsKey(id)) { jsCall(cb, "null"); return; }
                WebView wv = nViews.get(id);
                if (wv == null || wv.getWidth() < 2 || wv.getHeight() < 2) { jsCall(cb, "null"); return; }
                snapCapture(id, wv, cb);
            });
        }

        /**
         * Sürükleme/boyutlandırma başlarken on=true: sanal ekran geçici olarak ImageReader'a bağlanır ve kareler
         * https://w7vdframe.local/f?id=N adresinden JPEG olarak sunulur. Bırakınca on=false: SurfaceView'e geri döner.
         */
        @JavascriptInterface
        public void vdLive(final int wid, final boolean on) {
            runOnUiThread(() -> {
                VdWin win = vdWins.get(wid);
                if (win == null || !win.opened || win.view == null) return;
                if (on) startLive(win); else stopLive(win);
            });
        }

        /** Girdi kodu: 7 = otomatik dönüş, 0..3 = 0/90/180/270 derece, +16 = x/y yer değiştir. */
        @JavascriptInterface
        public void vdRot(final int wid, final int code) {
            VdWin win = vdWins.get(wid);
            if (win != null) win.rot = code;
        }

        /** Pencereyi diğer katmanların önüne getirir. */
        @JavascriptInterface
        public void vdFront(final int wid) {
            runOnUiThread(() -> {
                VdWin win = vdWins.get(wid);
                if (win != null && win.view != null) win.view.bringToFront();
            });
        }

        /**
         * JPEG (HTML) modunda SurfaceView gizli olduğu için dokunmayı HTML alır ve buraya iletir.
         * xs/ys: 0..1 aralığında, virgülle ayrılmış (pencere gövdesine göre); ids: 0..9 işaretçi numaraları.
         * action: MotionEvent.ACTION_* (0 DOWN, 1 UP, 2 MOVE, 3 CANCEL, 5 POINTER_DOWN, 6 POINTER_UP).
         */
        @JavascriptInterface
        public void vdTouch(final int wid, final int action, final int idx, final String xs, final String ys, final String ids) {
            final VdWin win = vdWins.get(wid);
            if (win == null || !win.opened || win.displayId < 0 || xs == null || ys == null || ids == null) return;
            try {
                String[] a = xs.split(","), b = ys.split(","), c = ids.split(",");
                final int n = Math.min(a.length, Math.min(b.length, c.length));
                if (n <= 0 || n > 10) return;
                final float[] fx = new float[n], fy = new float[n];
                final int[] fi = new int[n];
                for (int i = 0; i < n; i++) {
                    fx[i] = Float.parseFloat(a[i]);
                    fy[i] = Float.parseFloat(b[i]);
                    fi[i] = Integer.parseInt(c[i].trim());
                }
                if (action == MotionEvent.ACTION_DOWN) win.touchDown = SystemClock.uptimeMillis();
                final long down = win.touchDown;
                final int did = win.displayId, rot = win.rot;
                touchIo.execute(() -> {
                    try { if (vdSvc != null) vdSvc.injectTouch(did, action, idx, fx, fy, fi, n, down, rot); } catch (Throwable ignored) { }
                });
            } catch (Throwable ignored) { }
        }

        // ------------------------------------------------------------ Native sanal fare imleci

        /** Sanal fare açılıp kapanınca (touchpad modu). Açıkken gerçek dokunmalar yalnızca HTML'e gider. */
        @JavascriptInterface
        public void vcShow(final boolean on) {
            vcOn = on;
            runOnUiThread(() -> {
                if (!on) {
                    vcCapture = null; vcHtmlDown = false; vcHoverTgt = null;
                    if (vcView != null) vcView.setVisibility(View.GONE);
                    return;
                }
                vcEnsure();
                vcView.setVisibility(View.VISIBLE);
                vcTop();
            });
        }

        /** Gerçek fare modu: true → sistem imleci gizlenir (pointer capture), fareyi sanal imleç kullanır. */
        @JavascriptInterface
        public void vcPhys(final boolean on) {
            physMouse = on;
            physRetry = 0;
            runOnUiThread(MainActivity.this::physApply);
        }

        /** İndirme geçmişi (JSON dizisi, en yeni başta). Chrome/IE "İndirilenler" sayfaları kullanır. */
        @JavascriptInterface
        public String dlList() { return dlListJson(); }

        @JavascriptInterface
        public void dlOpenItem(final String k) { runOnUiThread(() -> MainActivity.this.dlOpenItem(k)); }

        @JavascriptInterface
        public void dlCancelItem(final String k) { MainActivity.this.dlCancelItem(k); }

        @JavascriptInterface
        public void dlRemoveItem(final String k) { MainActivity.this.dlRemoveItem(k); }

        @JavascriptInterface
        public void dlClearAll() { MainActivity.this.dlClearAll(); }

        /** Android pencerelerinde imleci gizle (dokunma modu) açık mı? */
        @JavascriptInterface
        public boolean vdPtrGet() {
            return vdTouchPtr();
        }

        @JavascriptInterface
        public void vdPtrSet(boolean on) {
            try { if (prefs != null) prefs.edit().putBoolean("w7_vdptr", on).apply(); } catch (Throwable ignored) { }
            vdMouseAsTouch = false;
        }

        /** Ekran modu: "16x9" ya da "full" (seçilmediyse telefonda 16x9, tabletta full). */
        @JavascriptInterface
        public String aspectGet() {
            return lbWant16x9() ? "16x9" : "full";
        }

        /** Ekran modunu kaydet ve hemen uygula. */
        @JavascriptInterface
        public void aspectSet(final String mode) {
            try { if (prefs != null) prefs.edit().putString("w7_aspect", "16x9".equals(mode) ? "16x9" : "full").apply(); } catch (Throwable ignored) { }
            runOnUiThread(MainActivity.this::lbApply);
        }

        /** Gerçek tablet ses düzeyi (0..100, müzik akışı). */
        @JavascriptInterface
        public int volGet() {
            volRead();
            return volPct;
        }

        /** Müzik akışı sessizde mi? */
        @JavascriptInterface
        public boolean volIsMuted() {
            volRead();
            return volMuted;
        }

        /** Simülatör ses çubuğundan: gerçek tablet sesini ayarla (0..100). */
        @JavascriptInterface
        public void volSet(final int pct) {
            runOnUiThread(() -> volApply(pct));
        }

        /** Şu an takılı bir fare var mı? (sayfa yüklenirken ilk durum) */
        @JavascriptInterface
        public boolean vcPhysPresent() {
            return physPresent;
        }

        /** İmleç görseli (PNG, base64). cssW/cssH: görselin CSS piksel boyutu; hotX/hotY: sıcak nokta (CSS px). */
        @JavascriptInterface
        public void vcBitmap(final String b64, final float cssW, final float cssH, final float hotX, final float hotY) {
            if (b64 == null || cssW <= 0 || cssH <= 0) return;
            try {
                byte[] raw = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
                final Bitmap bmp = android.graphics.BitmapFactory.decodeByteArray(raw, 0, raw.length);
                if (bmp == null) return;
                runOnUiThread(() -> {
                    vcBmp = bmp; vcCssW = cssW; vcCssH = cssH; vcHotX = hotX; vcHotY = hotY;
                    vcEnsure();
                    vcApply();
                    if (vcView != null) vcView.redraw();
                });
            } catch (Throwable ignored) { }
        }

        /** İmleç konumu (CSS px, viewport'a göre). */
        @JavascriptInterface
        public void vcPos(final float x, final float y, final float viewW) {
            if (webView == null || viewW <= 0) return;
            vcX = x; vcY = y; vcScale = webView.getWidth() / viewW;
            if (vcPosPending.compareAndSet(false, true)) runOnUiThread(() -> { vcPosPending.set(false); vcApply(); });
        }

        /**
         * Fare olayını imlecin altındaki native pencereye (Android uygulaması / tarayıcı WebView) gerçek fare olarak iletir.
         * action: 0 bas, 1 bırak, 2 basılıyken hareket, 7 hover, 8 tekerlek. buttons: MotionEvent.BUTTON_* (1 sol, 2 sağ).
         * Dönüş 1 = native hedef işledi (HTML'e sahte olay gönderme), 0 = hedef HTML.
         */
        @JavascriptInterface
        public int vcRoute(final int action, final float x, final float y, final int buttons, final int actionButton,
                           final float hs, final float vs, final float viewW) {
            if (!vcOn || webView == null || root == null || viewW <= 0) return 0;
            final float s = webView.getWidth() / viewW;
            final float px = x * s, py = y * s;
            View target;
            if (action == 0) {
                target = vcHit(px, py);
                vcCapture = target;
                vcHtmlDown = target == null;
                vcDownTime = SystemClock.uptimeMillis();
            } else if (action == 2) {
                target = vcCapture;          // basılıyken hedef, basıldığı yerde kalır (sürükleme)
            } else if (action == 1) {
                target = vcCapture;
                vcCapture = null;
                vcHtmlDown = false;
            } else {
                target = (vcCapture != null || vcHtmlDown) ? vcCapture : vcHit(px, py);
            }
            if (action == 7 && target != vcHoverTgt) {
                final View old = vcHoverTgt;
                vcHoverTgt = target;
                if (old instanceof NWebView) runOnUiThread(() -> vcExit((NWebView) old, px, py));
            }
            if (target == null) return 0;
            final View tv = target;
            final long down = vcDownTime;
            runOnUiThread(() -> vcDeliver(tv, action, px, py, buttons, actionButton, hs, vs, down));
            return 1;
        }

        /** JPEG (HTML) modunda fare olayı (hover, tuş, tekerlek) iletir. x/y 0..1. */
        @JavascriptInterface
        public void vdMouse(final int wid, final int action, final float x, final float y, final int buttonState,
                            final int actionButton, final float hscroll, final float vscroll) {
            final VdWin win = vdWins.get(wid);
            if (win == null || !win.opened || win.displayId < 0) return;
            if (action == MotionEvent.ACTION_DOWN) win.mouseDown = SystemClock.uptimeMillis();
            final long down = win.mouseDown;
            final int did = win.displayId, rot = win.rot;
            touchIo.execute(() -> {
                try { if (vdSvc != null) vdInjectMouse(vdSvc, did, action, x, y, buttonState, actionButton, hscroll, vscroll, down, rot); } catch (Throwable ignored) { }
            });
        }

        /** Pencerenin sanal ekranına tuş gönderir (ör. 4 = GERİ). */
        @JavascriptInterface
        public void vdKey(final int wid, final int keyCode) {
            final VdWin win = vdWins.get(wid);
            if (win == null) return;
            vdIo.execute(() -> {
                try { if (vdSvc != null && win.displayId >= 0) vdSvc.injectKey(win.displayId, keyCode); } catch (Throwable ignored) { }
            });
        }

        /** Pencerenin sanal ekranını kapatır, uygulamayı sonlandırır ve katmanı kaldırır. */
        @JavascriptInterface
        public void vdClose(final int wid) {
            vdDead.add(wid);
            runOnUiThread(() -> {
                final VdWin win = vdWins.remove(wid);
                if (win == null) return;
                win.pendingOpen = null;
                win.opened = false;
                releaseLive(win);
                if (win.view != null) root.removeView(win.view);
                // vdIo tek iş parçacığı: açılış sürüyorsa bitince çalışır, displayId o zaman okunur
                vdIo.execute(() -> {
                    try { if (vdSvc != null && win.displayId >= 0) vdSvc.close(win.displayId); } catch (Throwable ignored) { }
                });
            });
        }

        /** Yüklü (başlatılabilir) Android uygulamaları: JSON dizi [{k, n}] */
        @JavascriptInterface
        public int viewWidthPx() { return webView != null ? webView.getWidth() : 0; }

        @JavascriptInterface
        public String getInstalledApps() {
            return getAppsJson(false);
        }

        /** Simge adresi (shouldInterceptRequest ile PNG olarak sunulur) */
        @JavascriptInterface
        public String getAppIconUrl(String key) {
            try {
                return "https://" + ICON_HOST + "/icon?k=" + java.net.URLEncoder.encode(key, "UTF-8");
            } catch (Exception e) {
                return "";
            }
        }

        /** Kamera: JPEG (base64) fotoğrafı Resimler/UltraDroid klasörüne kaydeder. */
        @JavascriptInterface
        public void savePhoto(final String b64, final String name) {
            fsIo.execute(() -> {
                try {
                    String n = (name == null || !name.matches("[A-Za-z0-9_.\\-]{1,80}")) ? ("foto-" + System.currentTimeMillis() + ".jpg") : name;
                    savePhotoBytes(android.util.Base64.decode(b64, android.util.Base64.DEFAULT), n);
                    runOnUiThread(() -> android.widget.Toast.makeText(MainActivity.this, "Fotoğraf kaydedildi: Resimler/UltraDroid/" + n, android.widget.Toast.LENGTH_LONG).show());
                } catch (Throwable t) {
                    runOnUiThread(() -> android.widget.Toast.makeText(MainActivity.this, "Fotoğraf kaydedilemedi", android.widget.Toast.LENGTH_LONG).show());
                }
            });
        }

        /** Launcher modu: UltraDroid şu an varsayılan ana ekran mı? */
        @JavascriptInterface
        public boolean isDefaultHome() {
            return MainActivity.this.isDefaultHome();
        }

        /** Launcher modu: UltraDroid'u varsayılan ana ekran yapma / ana ekranı değiştirme ekranını açar. */
        @JavascriptInterface
        public void requestDefaultHome() {
            runOnUiThread(() -> {
                homeAsked = true;
                // 1) Android 10+: "UltraDroid varsayılan ana ekran uygulaması olsun mu?" iletişim kutusu
                if (Build.VERSION.SDK_INT >= 29 && !MainActivity.this.isDefaultHome()) {
                    try {
                        android.app.role.RoleManager rm = (android.app.role.RoleManager) getSystemService(Context.ROLE_SERVICE);
                        if (rm != null && rm.isRoleAvailable(android.app.role.RoleManager.ROLE_HOME)
                                && !rm.isRoleHeld(android.app.role.RoleManager.ROLE_HOME)) {
                            startActivityForResult(rm.createRequestRoleIntent(android.app.role.RoleManager.ROLE_HOME), HOME_REQ);
                            return;
                        }
                    } catch (Throwable ignored) { }
                }
                // 2) Ayarlar > Uygulamalar > Varsayılan uygulamalar > Ana ekran uygulaması
                try {
                    startActivity(new Intent(android.provider.Settings.ACTION_HOME_SETTINGS));
                    return;
                } catch (Throwable ignored) { }
                homeAsked = false;
                android.widget.Toast.makeText(MainActivity.this,
                        "Ayarlar > Uygulamalar > Varsayılan uygulamalar > Ana ekran uygulaması yolundan UltraDroid'u seç",
                        android.widget.Toast.LENGTH_LONG).show();
            });
        }

        /** Android uygulamasını başlat. key = "paket|activity" */
        @JavascriptInterface
        public void launchApp(final String key) {
            runOnUiThread(() -> {
                try {
                    int bar = key.indexOf('|');
                    Intent i = new Intent(Intent.ACTION_MAIN);
                    i.addCategory(Intent.CATEGORY_LAUNCHER);
                    i.setComponent(new ComponentName(key.substring(0, bar), key.substring(bar + 1)));
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
                    startActivity(i);
                } catch (Throwable t) {
                    android.widget.Toast.makeText(MainActivity.this, "Uygulama açılamadı", android.widget.Toast.LENGTH_SHORT).show();
                }
            });
        }

        @JavascriptInterface
        public String sGetAll() {
            try {
                JSONObject o = new JSONObject();
                Map<String, ?> all = prefs.getAll();
                for (Map.Entry<String, ?> e : all.entrySet()) {
                    Object v = e.getValue();
                    if (v instanceof String) {
                        o.put(e.getKey(), (String) v);
                    }
                }
                return o.toString();
            } catch (Exception e) {
                return "{}";
            }
        }

        @JavascriptInterface
        public void sPut(String key, String value) {
            prefs.edit().putString(key, value).apply();
        }

        @JavascriptInterface
        public void sDel(String key) {
            prefs.edit().remove(key).apply();
        }

        @JavascriptInterface
        public void sClear() {
            prefs.edit().clear().apply();
        }

        /** Chrome'da "uygulama olarak kaydet" diyalogu site başlığı/simgesini bununla çeker. */
        @JavascriptInterface
        public void fetchSiteInfo(final String url, final String callbackName) {
            new Thread(() -> {
                String title = "";
                String icon = "";
                try {
                    URL u = new URL(url);
                    HttpURLConnection conn = (HttpURLConnection) u.openConnection();
                    conn.setConnectTimeout(8000);
                    conn.setReadTimeout(8000);
                    conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Windows NT 6.1; WOW64)");
                    BufferedReader br = new BufferedReader(
                            new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    int lines = 0;
                    while ((line = br.readLine()) != null && lines < 500 && sb.length() < 200000) {
                        sb.append(line).append('\n');
                        lines++;
                    }
                    br.close();

                    Matcher m = Pattern.compile("<title[^>]*>([^<]*)</title>", Pattern.CASE_INSENSITIVE)
                            .matcher(sb.toString());
                    if (m.find()) {
                        title = m.group(1).trim();
                    }
                } catch (Exception ignored) {
                }

                try {
                    icon = "https://www.google.com/s2/favicons?sz=64&domain=" + new URL(url).getHost();
                } catch (Exception ignored) {
                }

                final JSONObject result = new JSONObject();
                try {
                    result.put("title", title);
                    result.put("icon", icon);
                } catch (Exception ignored) {
                }

                runOnUiThread(() -> {
                    if (webView == null) return;
                    String js = "window['" + callbackName + "'] && window['" + callbackName + "'](" + result + ");";
                    webView.evaluateJavascript(js, null);
                });
            }).start();
        }
    }
}
