package com.nexus.vr;

import android.app.Activity;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraMetadata;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.os.Build;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;
import android.util.Range;
import android.util.Size;
import android.view.Surface;

import androidx.annotation.NonNull;

import androidx.camera.camera2.interop.Camera2Interop;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.core.AspectRatio;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.core.resolutionselector.AspectRatioStrategy;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.camera.core.resolutionselector.ResolutionStrategy;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.core.Delegate;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Stage 44 — Native el takibi.
 * Kamera CameraX ile (ImageAnalysis RGBA, yalnızca en taze kare) açılır, kareler doğrudan MediaPipe HandLandmarker'a
 * (LIVE_STREAM, GPU; olmazsa CPU) verilir. Sonuçlar WebView'e metin olarak (Sink) iletilir.
 * Önizleme (kamera arka planı) varsa WebView'in ARKASINDAKİ PreviewView'e çizilir; WebView saydamdır.
 * UI iş parçacığı dışında hiçbir ağır iş yapılmaz; WebView'e giden her sonuç yalnızca "en son" sonuçtur (eskisi atılır).
 */
@androidx.annotation.OptIn(markerClass = ExperimentalCamera2Interop.class)
public class NativeCam {
    static final String TAG = "NEXUS-NativeCam";
    static final String MODEL = "hand_landmarker.task";

    /** WebView tarafına mesaj gönderen alıcı (MainActivity uygular). Her çağrı herhangi bir iş parçacığından gelebilir. */
    public interface Sink {
        void post(String msg, boolean droppable);
    }

    /** Ayarlar (JS'ten gelir). */
    public static class Cfg {
        public boolean front, prev, hand, lite;
        /** Stage 74: native süzgeç (C++ HandKin). false: ham landmark gönderilir, JS süzer. */
        public boolean nf = true;
        public int hands = 2, q = 0;
        public float det = .42f, pres = .42f, trk = .40f;

        boolean sameCamera(Cfg o) {
            return o != null && front == o.front && prev == o.prev && hand == o.hand && q == o.q && lite == o.lite;
        }

        boolean sameModel(Cfg o) {
            return o != null && hands == o.hands && det == o.det && pres == o.pres && trk == o.trk && nf == o.nf;
        }
    }

    final Activity act;
    final PreviewView pv;
    final Sink sink;
    final ExecutorService analysisExec = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(() -> {
            // Stage 45: Java önceliği Android'de neredeyse etkisiz; gerçek zamanlı ekran önceliği iş parçacığına verilir.
            try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY); } catch (Throwable ignored) { }
            r.run();
        }, "nx-hand-analysis");
        t.setPriority(Thread.MAX_PRIORITY);
        return t;
    });

    /** CameraX yaşam döngüsü: Activity onResume/onPause ile sürülür. */
    final LifecycleRegistry lifecycle;
    final LifecycleOwner owner;

    ProcessCameraProvider provider;
    Preview preview;
    ImageAnalysis analysis;
    HandLandmarker landmarker;
    String delegateName = "";
    Cfg cfg;
    boolean resumed = true;
    int gen = 0; // her yeniden yapılandırmada artar; eski geri çağrılar yok sayılır

    // Çıkarım / dönüştürme tamponları (yalnızca analysisExec üzerinde kullanılır)
    Bitmap rgba, rot;
    final Matrix mat = new Matrix();
    long lastTs = 0;
    Canvas rotCanvas;
    // Yakalama→gönderme zaman damgaları (küçük halka tampon; kare başına nesne/GC üretmez)
    final long[] ringTs = new long[16], ringCap = new long[16], ringEnter = new long[16];
    int ringPos = 0;
    /** MediaPipe şu an bir kareyi işliyorsa (sonuç gelmedi) yeni kareyi hiç dönüştürme/kopyalama: CPU ve GPU boşa harcanmaz, bir sonraki en taze kare işlenir. */
    volatile long busySince = 0;
    // Avoid feeding the vision model faster than the tablet can process it.
    // Lite devices use 320x240 at 30 Hz; standard devices use 480x360 at 40 Hz.
    long lastAnalysisMs = 0;
    volatile boolean liteMode = false;
    final StringBuilder outSb = new StringBuilder(2048);
    volatile boolean prioSet = false;
    /** Stage 62: çıkarım süresinin (analiz girişi → sonuç) üstel ortalaması; hızlı cihazda kare aralığı otomatik kısalır (≈60 Hz'e kadar). */
    volatile float infEma = 33f;
    private int thermal = 0;
    private long thermalChecked = 0;
    long fpsT0 = 0;
    int fpsN = 0;
    /** Stage 74: native el kinematiği (C++). Yalnızca MediaPipe sonuç iş parçacığında kullanılır. */
    final HandKin kin = HandKin.available() ? new HandKin() : null;
    volatile boolean kinOn = true;
    /** Analiz karesinin (döndürülmüş) en-boy oranı; landmark x'i bu oranla ölçeklenir. */
    volatile float aspect = 4f / 3f;
    /**
     * Stage 74 — uyarlanır takip çözünürlüğü: standart profilde (480x360) çıkarım sürekli yavaşsa ya da cihaz ısınırsa
     * analiz 320x240'a iner; uzun süre rahatsa geri çıkar. Ani gidip gelme olmasın diye histerezis + bekleme süresi var.
     * Kullanıcı "hafif" profili zorladıysa (Cfg.lite) zaten 320x240'tır, burası devreye girmez.
     */
    volatile boolean autoLite = false;
    long slowSince = 0, fastSince = 0, lastResSwitch = 0;

    public NativeCam(Activity a, PreviewView p, Sink s) {
        act = a;
        pv = p;
        sink = s;
        final LifecycleRegistry[] holder = new LifecycleRegistry[1];
        owner = new LifecycleOwner() {
            @NonNull
            @Override
            public Lifecycle getLifecycle() {
                return holder[0];
            }
        };
        lifecycle = new LifecycleRegistry(owner);
        holder[0] = lifecycle;
        lifecycle.setCurrentState(Lifecycle.State.RESUMED);
    }

    // ---------------------------------------------------------------- model (Stage 71: internetten)
    static final String[] MODEL_URLS = {
            "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task",
            "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
    };
    static final long MODEL_MIN = 1000000L;

    static java.io.File modelFile(Context c) {
        return new java.io.File(c.getFilesDir(), MODEL);
    }

    /** Model dosyası cihazda var ve sağlam mı? (yoksa JS eski Worker yolunu kullanır) */
    public static boolean modelPresent(Context c) {
        try {
            java.io.File f = modelFile(c);
            return f.isFile() && f.length() >= MODEL_MIN;
        } catch (Exception e) {
            return false;
        }
    }

    /** Uygulama her açıldığında modeli internetten indirir (arka planda). İndirilemezse daha önce inen kopya kullanılır.
     *  Bitince onDone (herhangi bir iş parçacığında) çağrılır; parametre: model kullanılabilir mi. */
    public static void ensureModel(final Context c, final java.util.function.Consumer<Boolean> onDone) {
        final Context app = c.getApplicationContext();
        Thread t = new Thread(() -> {
            boolean got = false;
            for (int round = 0; round < 3 && !got; round++) {
                for (String address : MODEL_URLS) {
                    java.io.File tmp = new java.io.File(app.getFilesDir(), MODEL + ".download");
                    java.net.HttpURLConnection conn = null;
                    try {
                        conn = (java.net.HttpURLConnection) new java.net.URL(address).openConnection();
                        conn.setConnectTimeout(15000);
                        conn.setReadTimeout(30000);
                        conn.setRequestProperty("User-Agent", "NEXUS-VR/1.0");
                        if (conn.getResponseCode() != 200) throw new java.io.IOException("HTTP " + conn.getResponseCode());
                        try (java.io.InputStream in = conn.getInputStream();
                             java.io.FileOutputStream out = new java.io.FileOutputStream(tmp)) {
                            byte[] buf = new byte[64 * 1024];
                            int n;
                            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                        }
                        if (tmp.length() < MODEL_MIN) throw new java.io.IOException("model eksik indi");
                        java.io.File dst = modelFile(app);
                        if (dst.exists()) dst.delete();
                        if (!tmp.renameTo(dst)) throw new java.io.IOException("model kaydedilemedi");
                        got = true;
                        Log.i(TAG, "hand_landmarker.task indirildi: " + address);
                        break;
                    } catch (Throwable e) {
                        Log.w(TAG, "Model indirilemedi (" + address + "): " + e);
                    } finally {
                        if (conn != null) try { conn.disconnect(); } catch (Throwable ignored) { }
                        if (tmp.exists()) tmp.delete();
                    }
                }
                if (!got) try { Thread.sleep(3000); } catch (InterruptedException ignored) { }
            }
            boolean ok = modelPresent(app);   // indirilemediyse önceki kopya
            if (onDone != null) try { onDone.accept(ok); } catch (Throwable ignored) { }
        }, "nx-model-dl");
        t.setPriority(Thread.NORM_PRIORITY - 1);
        t.start();
    }

    static java.nio.ByteBuffer loadModelBuffer(Context c) throws java.io.IOException {
        try (java.io.RandomAccessFile raf = new java.io.RandomAccessFile(modelFile(c), "r");
             java.nio.channels.FileChannel ch = raf.getChannel()) {
            return ch.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, 0, ch.size());
        }
    }

    // ---------------------------------------------------------------- yaşam döngüsü
    public void onResume() {
        resumed = true;
        lifecycle.setCurrentState(Lifecycle.State.RESUMED);
    }

    public void onPause() {
        resumed = false;
        lifecycle.setCurrentState(Lifecycle.State.CREATED);
    }

    public void onDestroy() {
        stop();
        analysisExec.execute(() -> { if (kin != null) kin.release(); });
        analysisExec.shutdown();
    }

    /** Ekran dönmesi (sensorLandscape: 90° ↔ 270°) sonrası çağrılır. */
    public void onRotation() {
        int r = rotation();
        if (analysis != null) analysis.setTargetRotation(r);
        if (preview != null) preview.setTargetRotation(r);
    }

    int rotation() {
        try {
            return act.getWindowManager().getDefaultDisplay().getRotation();
        } catch (Exception e) {
            return Surface.ROTATION_90;
        }
    }

    // ---------------------------------------------------------------- başlat / durdur
    /** UI iş parçacığında çağrılır. Başarılıysa sink'e "S|ready|<delegate>", hata olursa "S|err|<mesaj>" gider. */
    public void configure(final Cfg c) {
        final int my = ++gen;
        final Cfg old = cfg;
        cfg = c;
        if (!c.prev && !c.hand) {
            stop();
            sink.post("S|ready|off", false);
            return;
        }
        // Yalnızca model ayarı değiştiyse kamerayı yeniden açma
        final boolean camSame = old != null && c.sameCamera(old) && provider != null && (analysis != null || !c.hand);
        final boolean modelSame = c.sameModel(old) && landmarker != null;
        if (camSame && (modelSame || !c.hand)) {
            sink.post("S|ready|" + (c.hand ? delegateName : "cam"), false);
            return;
        }
        analysisExec.execute(() -> {
            try {
                if (c.hand && (!modelSame || landmarker == null)) buildLandmarker(c, my);
                if (!c.hand) closeLandmarker();
            } catch (Throwable e) {
                Log.e(TAG, "HandLandmarker oluşturulamadı", e);
                final String m = String.valueOf(e.getMessage()).replace('|', '/');
                act.runOnUiThread(() -> {
                    if (my == gen) {
                        stop();
                        sink.post("S|err|" + m, false);
                    }
                });
                return;
            }
            act.runOnUiThread(() -> {
                if (my != gen) return;
                bindCamera(c, my);
            });
        });
    }

    public void stop() {
        gen++;
        cfg = null;
        try {
            if (provider != null) provider.unbindAll();
        } catch (Throwable ignored) {
        }
        preview = null;
        analysis = null;
        analysisExec.execute(this::closeLandmarker);
    }

    // ---------------------------------------------------------------- MediaPipe
    void closeLandmarker() {
        HandLandmarker l = landmarker;
        landmarker = null;
        if (l != null) {
            try {
                l.close();
            } catch (Throwable ignored) {
            }
        }
    }

    void buildLandmarker(Cfg c, final int my) throws Exception {
        closeLandmarker();
        Throwable first = null;
        for (Delegate d : new Delegate[]{Delegate.GPU, Delegate.CPU}) {
            try {
                BaseOptions base = BaseOptions.builder().setModelAssetBuffer(loadModelBuffer(act.getApplicationContext())).setDelegate(d).build();
                HandLandmarker.HandLandmarkerOptions o = HandLandmarker.HandLandmarkerOptions.builder()
                        .setBaseOptions(base)
                        .setRunningMode(RunningMode.LIVE_STREAM)
                        .setNumHands(c.hands)
                        .setMinHandDetectionConfidence(c.det)
                        .setMinHandPresenceConfidence(c.pres)
                        .setMinTrackingConfidence(c.trk)
                        .setResultListener((res, img) -> onResult(res, my))
                        .setErrorListener(e -> { busySince = 0; Log.w(TAG, "MediaPipe hata: " + e); })
                        .build();
                landmarker = HandLandmarker.createFromOptions(act.getApplicationContext(), o);
                delegateName = d == Delegate.GPU ? "GPU" : "CPU";
                lastTs = 0;
                return;
            } catch (Throwable e) {
                if (first == null) first = e;
                Log.w(TAG, "Delegate " + d + " başarısız: " + e);
            }
        }
        throw new Exception("MediaPipe başlatılamadı: " + (first == null ? "?" : first.getMessage()));
    }

    // ---------------------------------------------------------------- Kamera
    /** Kamera ayarı: en yüksek (en çok 60) kare hızı aralığı + gecikme ekleyen görüntü işlemlerini kapatma. */
    static class Tune {
        Range<Integer> fps;
        boolean stabOff, nrFast, edgeFast;
    }

    static boolean has(int[] arr, int v) {
        if (arr == null) return false;
        for (int x : arr) if (x == v) return true;
        return false;
    }

    /** Cihazın verebildiği en yüksek (en çok 60) kare hızı aralığını seçer; düşük ışıkta 30'a inebilsin diye alt sınırı düşük tutar.
     *  Ayrıca video sabitleme (kareleri tamponlar → gecikme), ağır gürültü/keskinlik işleme kapatılır (desteklenen cihazlarda). */
    static Tune tune(Context ctx, boolean front) {
        Tune t = new Tune();
        try {
            CameraManager cm = (CameraManager) ctx.getSystemService(Context.CAMERA_SERVICE);
            int want = front ? CameraCharacteristics.LENS_FACING_FRONT : CameraCharacteristics.LENS_FACING_BACK;
            for (String id : cm.getCameraIdList()) {
                CameraCharacteristics cc = cm.getCameraCharacteristics(id);
                Integer lf = cc.get(CameraCharacteristics.LENS_FACING);
                if (lf == null || lf != want) continue;
                Range<Integer>[] rs = cc.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
                if (rs != null) {
                    Range<Integer> best = null;
                    for (Range<Integer> r : rs) {
                        if (r.getUpper() > 60) continue;
                        if (best == null || r.getUpper() > best.getUpper()
                                || (r.getUpper() == best.getUpper() && betterLower(r.getLower(), best.getLower()))) best = r;
                    }
                    t.fps = best;
                }
                t.stabOff = has(cc.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES), CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF);
                t.nrFast = has(cc.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES), CameraMetadata.NOISE_REDUCTION_MODE_FAST);
                t.edgeFast = has(cc.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES), CameraMetadata.EDGE_MODE_FAST);
                return t;
            }
        } catch (Throwable e) {
            Log.w(TAG, "Kamera özellikleri okunamadı: " + e);
        }
        return t;
    }

    static void applyTune(Camera2Interop.Extender<?> ex, Tune t) {
        if (t.fps != null) ex.setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, t.fps);
        if (t.stabOff) ex.setCaptureRequestOption(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, CameraMetadata.CONTROL_VIDEO_STABILIZATION_MODE_OFF);
        if (t.nrFast) ex.setCaptureRequestOption(CaptureRequest.NOISE_REDUCTION_MODE, CameraMetadata.NOISE_REDUCTION_MODE_FAST);
        if (t.edgeFast) ex.setCaptureRequestOption(CaptureRequest.EDGE_MODE, CameraMetadata.EDGE_MODE_FAST);
    }

    static boolean betterLower(int a, int b) {
        // 24 ve üstü alt sınırlardan en küçüğü; hiçbiri yoksa en büyüğü
        boolean aOk = a >= 24, bOk = b >= 24;
        if (aOk && bOk) return a < b;
        if (aOk) return true;
        if (bOk) return false;
        return a > b;
    }

    void bindCamera(final Cfg c, final int my) {
        final ListenableFuture<ProcessCameraProvider> f = ProcessCameraProvider.getInstance(act);
        f.addListener(() -> {
            if (my != gen) return;
            try {
                provider = f.get();
                provider.unbindAll();
                final int rot = rotation();
                final Tune tn = tune(act, c.front);

                ImageAnalysis.Builder ab = new ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                        // Stage 74: döndürmeyi CameraX native (libyuv) yapar; her karede Canvas ile ikinci kopya + döndürme kalkar.
                        // Desteklenmeyen cihazda getRotationDegrees() != 0 gelir ve aşağıdaki eski Canvas yolu yine çalışır.
                        .setOutputImageRotationEnabled(true)
                        .setTargetRotation(rot)
                        .setResolutionSelector((c.lite || autoLite) ? sel(320, 240) : sel(480, 360));
                applyTune(new Camera2Interop.Extender<>(ab), tn);

                Preview.Builder pb = new Preview.Builder().setTargetRotation(rot);
                final int[][] RES = {{640, 480}, {1280, 720}, {1920, 1080}};
                int qi = Math.max(0, Math.min(2, c.q));
                pb.setResolutionSelector(sel(RES[qi][0], RES[qi][1]));
                applyTune(new Camera2Interop.Extender<>(pb), tn);

                CameraSelector cs = c.front ? CameraSelector.DEFAULT_FRONT_CAMERA : CameraSelector.DEFAULT_BACK_CAMERA;
                if (c.hand) {
                    liteMode = c.lite || autoLite;
                    if (kin != null) {
                        kin.reset();
                        kinOn = c.nf;
                        kin.config(c.nf, 1.6f, 9f, 2f);
                    }
                    lastAnalysisMs = 0;
                    analysis = ab.build();
                    analysis.setAnalyzer(analysisExec, img -> analyze(img, my));
                } else analysis = null;
                if (c.prev) {
                    pv.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
                    pv.setScaleType(PreviewView.ScaleType.FILL_CENTER);
                    preview = pb.build();
                    preview.setSurfaceProvider(pv.getSurfaceProvider());
                    pv.setVisibility(android.view.View.VISIBLE);
                } else {
                    preview = null;
                    pv.setVisibility(android.view.View.INVISIBLE);
                }
                if (preview != null && analysis != null) provider.bindToLifecycle(owner, cs, preview, analysis);
                else if (preview != null) provider.bindToLifecycle(owner, cs, preview);
                else provider.bindToLifecycle(owner, cs, analysis);
                fpsT0 = SystemClock.elapsedRealtime();
                fpsN = 0;
                sink.post("S|ready|" + (c.hand ? delegateName : "cam"), false);
            } catch (Throwable e) {
                Log.e(TAG, "Kamera açılamadı", e);
                sink.post("S|err|" + String.valueOf(e.getMessage()).replace('|', '/'), false);
            }
        }, ContextCompat.getMainExecutor(act));
    }

    static ResolutionSelector sel(int w, int h) {
        return new ResolutionSelector.Builder()
                .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                .setResolutionStrategy(new ResolutionStrategy(new Size(w, h), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
                .build();
    }

    // ---------------------------------------------------------------- Çıkarım
    void ringPut(long ts, long cap, long enter) {
        synchronized (ringTs) {
            ringPos = (ringPos + 1) & 15;
            ringTs[ringPos] = ts;
            ringCap[ringPos] = cap;
            ringEnter[ringPos] = enter;
        }
    }

    boolean ringGet(long ts, long[] out) {
        synchronized (ringTs) {
            for (int i = 0; i < 16; i++) {
                if (ringTs[i] == ts) {
                    out[0] = ringCap[i];
                    out[1] = ringEnter[i];
                    ringTs[i] = -1;
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * Stage 62 — uyarlanır kare aralığı. Sabit 33 ms (30 Hz) sınırı hızlı telefonlarda el güncellemesini gereksiz seyreltiyordu
     * (30 Hz çıkarım, 60-120 Hz ekranda basamaklı görünür). Çıkarım ~10 ms ise ≈60 Hz'e çıkılır; yavaşlarsa kendiliğinden eski
     * sınıra döner. Cihaz ısınırsa (Android 10+ termal durum) hızlanma kapanır, ciddi ısınmada 20 Hz'e inilir.
     */
    long analysisGap(long nowMs) {
        final long base = liteMode ? 33L : 25L;
        if (Build.VERSION.SDK_INT >= 29 && nowMs - thermalChecked > 2000) {
            thermalChecked = nowMs;
            try {
                PowerManager pm = (PowerManager) act.getSystemService(Context.POWER_SERVICE);
                thermal = pm == null ? 0 : pm.getCurrentThermalStatus();
            } catch (Throwable ignored) { thermal = 0; }
        }
        if (thermal >= 3) return 50L;       // SEVERE ve üstü: ısıyı düşür
        if (thermal >= 2) return base;      // MODERATE: hızlanma yok
        long g = Math.round(infEma * 0.9f);
        return Math.max(16L, Math.min(base, g));
    }

    /** analysisExec üzerinde, her yeni kare için. RGBA kareyi (gerekirse döndürerek) MediaPipe'a verir. */
    void analyze(ImageProxy img, int my) {
        try {
            final HandLandmarker lm = landmarker;
            if (lm == null || my != gen || !resumed) return;
            // Stage 45: MediaPipe hâlâ önceki kareyi işliyorsa bu kareyi hiç kopyalama/dönüştürme (en çok 120 ms, sonra yine dener).
            final long nowMs = SystemClock.elapsedRealtime();
            final long bs = busySince;
            if (bs != 0 && nowMs - bs < 120) return;
            final long minGap = analysisGap(nowMs);
            if (lastAnalysisMs != 0 && nowMs - lastAnalysisMs < minGap) return;
            lastAnalysisMs = nowMs;
            final long enter = SystemClock.elapsedRealtimeNanos();
            // Gerçek yakalama zamanı: donanım damgası ya REALTIME (elapsedRealtimeNanos) ya da MONOTONIC (nanoTime) tabanlıdır.
            // İkisini de dener, makul olanı (0..400 ms) kullanır; böylece UNKNOWN zaman kaynaklı cihazlarda da yaş doğru olur.
            final long cap = img.getImageInfo().getTimestamp();
            long age = enter - cap;
            if (age < 0 || age > 400_000_000L) {
                age = System.nanoTime() - cap;
                if (age < 0 || age > 400_000_000L) age = 0; // damga kaynağı bilinmiyor: güvenilmez
            }
            final int w = img.getWidth(), h = img.getHeight(), deg = img.getImageInfo().getRotationDegrees();
            if (rgba == null || rgba.getWidth() != w || rgba.getHeight() != h) {
                rgba = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
                rot = null;
                rotCanvas = null;
            }
            ImageProxy.PlaneProxy p = img.getPlanes()[0];
            java.nio.ByteBuffer buf = p.getBuffer();
            buf.rewind();
            int rowPad = p.getRowStride() - w * 4;
            if (rowPad == 0) rgba.copyPixelsFromBuffer(buf);
            else { // satır dolgusu varsa satır satır kopyala (tamponlar yeniden kullanılır)
                if (rowTmp == null || rowTmp.length != w * 4) rowTmp = new byte[w * 4];
                if (padBuf == null || padBuf.capacity() != w * 4 * h) padBuf = java.nio.ByteBuffer.allocateDirect(w * 4 * h);
                padBuf.clear();
                for (int y = 0; y < h; y++) {
                    buf.position(y * p.getRowStride());
                    buf.get(rowTmp, 0, w * 4);
                    padBuf.put(rowTmp);
                }
                padBuf.rewind();
                rgba.copyPixelsFromBuffer(padBuf);
            }
            Bitmap use = rgba;
            if (deg != 0) {
                int rw = (deg == 90 || deg == 270) ? h : w, rh = (deg == 90 || deg == 270) ? w : h;
                if (rot == null || rot.getWidth() != rw || rot.getHeight() != rh) {
                    rot = Bitmap.createBitmap(rw, rh, Bitmap.Config.ARGB_8888);
                    rotCanvas = new Canvas(rot);
                }
                mat.reset();
                mat.postTranslate(-w / 2f, -h / 2f);
                mat.postRotate(deg);
                mat.postTranslate(rw / 2f, rh / 2f);
                rotCanvas.drawBitmap(rgba, mat, null);
                use = rot;
            }
            if (use.getHeight() > 0) aspect = use.getWidth() / (float) use.getHeight();
            long ts = SystemClock.uptimeMillis();
            if (ts <= lastTs) ts = lastTs + 1;
            lastTs = ts;
            ringPut(ts, enter - age, enter); // {yakalama anı, analiz girişi} (elapsedRealtimeNanos)
            MPImage mp = new BitmapImageBuilder(use).build();
            busySince = SystemClock.elapsedRealtime();
            try {
                lm.detectAsync(mp, ts);
            } catch (Throwable e) {
                busySince = 0;
                throw e;
            }
            fpsN++;
            long now = SystemClock.elapsedRealtime();
            if (now - fpsT0 >= 2000) {
                sink.post("S|fps|" + Math.round(fpsN * 1000f / (now - fpsT0)) + "|" + w + "x" + h, false);
                fpsT0 = now;
                fpsN = 0;
            }
        } catch (Throwable e) {
            Log.w(TAG, "Kare işlenemedi: " + e);
        } finally {
            img.close();
        }
    }

    byte[] rowTmp;
    java.nio.ByteBuffer padBuf;

    /** MediaPipe iş parçacığında. Sonucu kompakt metne çevirip gönderir.
     *  Biçim: R|yaş_ms|çıkarım_ms|elSayısı|Etiket,skor,x,y,z,...|...|T,yakalama_ms  (MainActivity sona |P,gönderim_ms ekler).
     *  T ve P aynı (elapsedRealtime) saatinin milisaniyesidir; JS iki saat arasındaki farkı P'den çıkarır, böylece
     *  yakalama zamanı aktarım gecikmesi dalgalanmasından etkilenmez. */
    void onResult(HandLandmarkerResult res, int my) {
        busySince = 0; // MediaPipe boşaldı: sıradaki en taze kare hemen işlenebilir
        if (!prioSet) { // MediaPipe sonuç iş parçacığına bir kez yüksek öncelik ver
            prioSet = true;
            try { android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY); } catch (Throwable ignored) { }
        }
        if (my != gen) return;
        long tsMs = res.timestampMs();
        long[] cap = tmpCap;
        boolean have = ringGet(tsMs, cap);
        long nowN = SystemClock.elapsedRealtimeNanos();
        float age = !have ? 0f : Math.max(0f, (nowN - cap[0]) / 1e6f);
        float inf = !have ? 0f : Math.max(0f, (nowN - cap[1]) / 1e6f);
        if (have && inf > 0f && inf < 250f) infEma += (inf - infEma) * 0.2f;
        adaptResolution(my);
        List<List<NormalizedLandmark>> L = res.landmarks();
        List<List<Category>> H = res.handedness();
        String out;
        // Stage 74: önce C++ kinematiği (süzgeç + özellikler); başarılıysa el blokları süzülmüş landmark'larla yazılır.
        final boolean kOk = runKin(L, H, have ? cap[0] : SystemClock.elapsedRealtimeNanos());
        final boolean filtered = kOk && kinOn;
        synchronized (outSb) {
            StringBuilder sb = outSb;
            sb.setLength(0);
            sb.append("R|");
            num(sb, age, 10);
            sb.append('|');
            num(sb, inf, 10);
            sb.append('|').append(L.size());
            for (int i = 0; i < L.size(); i++) {
                List<NormalizedLandmark> pts = L.get(i);
                String lab = "";
                float sc = 1f;
                if (H != null && i < H.size() && !H.get(i).isEmpty()) {
                    lab = H.get(i).get(0).categoryName();
                    sc = H.get(i).get(0).score();
                }
                sb.append('|').append(lab).append(',');
                num(sb, sc, 1000);
                if (filtered && i < 2) {
                    final java.nio.FloatBuffer ko = kin.out;
                    final int o = i * HandKin.OUT_STRIDE + HandKin.O_LM;
                    for (int j = 0; j < 63; j++) {
                        sb.append(',');
                        num(sb, ko.get(o + j), 10000);
                    }
                    continue;
                }
                for (NormalizedLandmark p : pts) {
                    sb.append(',');
                    num(sb, p.x(), 10000);
                    sb.append(',');
                    num(sb, p.y(), 10000);
                    sb.append(',');
                    num(sb, p.z(), 10000);
                }
            }
            if (kOk) appendKin(sb, Math.min(2, L.size()), filtered);
            if (have) {
                long t10 = cap[0] / 100000L; // 0.1 ms
                sb.append("|T,").append(t10 / 10).append('.').append(t10 % 10);
            }
            out = sb.toString();
        }
        sink.post(out, true);
    }

    final long[] tmpCap = new long[2];

    /**
     * Stage 74: C++ kinematiğini çalıştırır ve her el için bir "K" bloğu ekler:
     * K,yuva,bayrak,güven,boy,bükülme×5,çimdik×4,açıklık×4,normal×3,kuaterniyon×4,hız×3
     * Native süzgeç açıksa el bloklarındaki landmark'lar süzülmüş değerlerdir ve mesaja "|F,1" eklenir (JS kendi süzgecini atlar).
     * Kitaplık yoksa ya da bir el atlanırsa hiçbir şey eklenmez → JS eski (ham + JS süzgeci) yolunu kullanır.
     */
    boolean runKin(List<List<NormalizedLandmark>> L, List<List<Category>> H, long capNs) {
        final HandKin k = kin;
        if (k == null || !k.ok() || L == null) return false;
        final int n = Math.min(2, L.size());
        if (n == 0) return false;
        final java.nio.FloatBuffer in = k.in;
        for (int i = 0; i < n; i++) {
            List<NormalizedLandmark> pts = L.get(i);
            if (pts.size() < 21) return false;
            float sc = 1f;
            boolean right = false;
            if (H != null && i < H.size() && !H.get(i).isEmpty()) {
                sc = H.get(i).get(0).score();
                right = "Right".equals(H.get(i).get(0).categoryName());
            }
            int b = i * HandKin.IN_STRIDE;
            in.put(b, sc);
            in.put(b + 1, right ? 1f : 0f);
            for (int j = 0; j < 21; j++) {
                NormalizedLandmark p = pts.get(j);
                in.put(b + 2 + j * 3, p.x());
                in.put(b + 3 + j * 3, p.y());
                in.put(b + 4 + j * 3, p.z());
            }
        }
        // bir el atlandıysa (bozuk veri) bu karede K yok, ham veri gönderilir
        return k.process(n, capNs, aspect) == n;
    }

    void appendKin(StringBuilder sb, int n, boolean filtered) {
        final java.nio.FloatBuffer out = kin.out;
        for (int i = 0; i < n; i++) {
            int o = i * HandKin.OUT_STRIDE;
            sb.append("|K,");
            sb.append((int) out.get(o + HandKin.O_SLOT)).append(',').append((int) out.get(o + HandKin.O_FLAGS));
            for (int j = HandKin.O_CONF; j < HandKin.O_LM; j++) {
                sb.append(',');
                num(sb, out.get(o + j), 1000);
            }
        }
        if (filtered) sb.append("|F,1");
    }

    /** Stage 74: çıkarım süresine ve ısıya göre analiz çözünürlüğünü uyarlar (histerezisli). */
    void adaptResolution(final int my) {
        final Cfg c = cfg;
        if (c == null || c.lite || !c.hand) return;
        final long now = SystemClock.elapsedRealtime();
        if (now - lastResSwitch < 8000) return;
        final boolean hot = thermal >= 2;
        if (!autoLite) {
            if (infEma > 42f || hot) { if (slowSince == 0) slowSince = now; } else slowSince = 0;
            if (slowSince != 0 && now - slowSince > 3000) switchRes(true, my, now);
        } else {
            if (infEma < 20f && !hot) { if (fastSince == 0) fastSince = now; } else fastSince = 0;
            if (fastSince != 0 && now - fastSince > 15000) switchRes(false, my, now);
        }
    }

    void switchRes(final boolean lite, final int my, long now) {
        autoLite = lite;
        lastResSwitch = now;
        slowSince = fastSince = 0;
        sink.post("S|res|" + (lite ? "320x240" : "480x360") + "|" + Math.round(infEma), false);
        act.runOnUiThread(() -> {
            final Cfg c = cfg;
            // gen ARTIRILMAZ: landmarker'ın sonuç dinleyicisi mevcut gen'e bağlıdır; yalnızca kamera yeniden bağlanır.
            if (my != gen || c == null) return;
            bindCamera(c, my);
        });
    }

    /** Hızlı sabit-ondalık yazım (String.format yok; kare başına ~130 sayı). scale: 10, 1000, 10000. */
    static void num(StringBuilder sb, float v, int scale) {
        if (Float.isNaN(v) || Float.isInfinite(v)) v = 0f;
        long n = Math.round((double) v * scale);
        if (n < 0) {
            sb.append('-');
            n = -n;
        }
        long ip = n / scale, fp = n % scale;
        sb.append(ip).append('.');
        int digits = scale == 10 ? 1 : scale == 1000 ? 3 : 4;
        String f = Long.toString(fp);
        for (int i = f.length(); i < digits; i++) sb.append('0');
        sb.append(f);
    }
}
