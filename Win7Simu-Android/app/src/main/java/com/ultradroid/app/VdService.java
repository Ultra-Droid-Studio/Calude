package com.ultradroid.app;

import android.content.Context;
import android.content.ContextWrapper;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.Surface;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/**
 * Shizuku UserService: bu sınıf SHELL (uid 2000) yetkisiyle ayrı bir süreçte çalışır.
 * Burada yapılanlar normal bir uygulamanın yapamayacağı işlerdir:
 *  - trusted virtual display açmak
 *  - başka bir uygulamayı o ekranda başlatmak
 *  - o ekrana dokunma/tuş enjekte etmek
 *
 * Gizli (hidden) API'ler yansıma (reflection) ile çağrılır; derleme zamanında gerekmez.
 */
public class VdService extends IVdService.Stub {

    // VirtualDisplay bayrakları (gizli olanlar sayı olarak yazıldı)
    private static final int F_PUBLIC = 1 << 0;
    private static final int F_PRESENTATION = 1 << 1;
    private static final int F_OWN_CONTENT_ONLY = 1 << 3;
    private static final int F_SUPPORTS_TOUCH = 1 << 6;
    private static final int F_ROTATES_WITH_CONTENT = 1 << 7;
    private static final int F_DESTROY_CONTENT_ON_REMOVAL = 1 << 8;
    private static final int F_TRUSTED = 1 << 10;               // API 33+
    private static final int F_OWN_DISPLAY_GROUP = 1 << 11;     // API 33+
    private static final int F_ALWAYS_UNLOCKED = 1 << 12;       // API 33+
    private static final int F_TOUCH_FEEDBACK_DISABLED = 1 << 13; // API 33+
    private static final int F_OWN_FOCUS = 1 << 14;             // API 34+

    private static final Pattern COMPONENT_OK = Pattern.compile("^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+$");

    private final HandlerThread thread = new HandlerThread("w7-vd");
    private final Handler handler;
    // displayId -> sanal ekran / içinde açılan paket
    private final Map<Integer, VirtualDisplay> displays = new ConcurrentHashMap<>();
    private final Map<Integer, int[]> lastSize = new ConcurrentHashMap<>();
    private final Map<Integer, String> pkgs = new ConcurrentHashMap<>();
    private final Object injLock = new Object();
    private DisplayManager dm;
    private String lastError = "";

    // Dokunma enjeksiyonu için yansıma önbelleği
    private Object inputMgr;
    private Method injectMethod;
    private Method setDisplayIdMethod;

    public VdService() {
        thread.start();
        handler = new Handler(thread.getLooper());
    }

    /** Shizuku bazı sürümlerde Context'li kurucu da arar; zararsız. */
    public VdService(Context ignored) {
        this();
    }

    // ---------------------------------------------------------------- yardımcılar

    /** Paket adı "com.android.shell" gibi görünen sahte Context (createVirtualDisplay uid/paket eşleşmesi ister). */
    private static class FakeContext extends ContextWrapper {
        FakeContext(Context base) { super(base); }
        @Override public String getPackageName() { return "com.android.shell"; }
        @Override public String getOpPackageName() { return "com.android.shell"; }
        @Override public Context getApplicationContext() { return this; }
    }

    private DisplayManager displayManager() throws Exception {
        if (dm != null) return dm;
        Class<?> at = Class.forName("android.app.ActivityThread");
        Object thr = at.getMethod("currentActivityThread").invoke(null);
        if (thr == null) {
            try { android.os.Looper.prepareMainLooper(); } catch (Throwable ignored) { }
            thr = at.getMethod("systemMain").invoke(null);
        }
        Context sys = (Context) at.getMethod("getSystemContext").invoke(thr);
        Context fake = new FakeContext(sys);
        Constructor<DisplayManager> c = DisplayManager.class.getDeclaredConstructor(Context.class);
        c.setAccessible(true);
        dm = c.newInstance(fake);
        return dm;
    }

    private static int flags() {
        int f = F_PUBLIC | F_PRESENTATION | F_OWN_CONTENT_ONLY | F_SUPPORTS_TOUCH
                | F_ROTATES_WITH_CONTENT | F_DESTROY_CONTENT_ON_REMOVAL;
        if (Build.VERSION.SDK_INT >= 33) {
            f |= F_TRUSTED | F_OWN_DISPLAY_GROUP | F_ALWAYS_UNLOCKED | F_TOUCH_FEEDBACK_DISABLED;
        }
        if (Build.VERSION.SDK_INT >= 34) {
            f |= F_OWN_FOCUS;
        }
        return f;
    }

    private static String sh(String... cmd) throws Exception {
        Process p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
        StringBuilder sb = new StringBuilder();
        BufferedReader br = new BufferedReader(new InputStreamReader(p.getInputStream()));
        String line;
        while ((line = br.readLine()) != null) sb.append(line).append('\n');
        p.waitFor();
        return sb.toString().trim();
    }

    // ---------------------------------------------------------------- AIDL

    @Override
    public synchronized int open(Surface surface, int width, int height, int dpi) {
        try {
            if (Build.VERSION.SDK_INT < 29) {
                lastError = "Android 10+ gerekli";
                return -1;
            }
            // Uygulamaların ikinci ekranda yeniden boyutlanabilmesi için
            try { sh("settings", "put", "global", "force_resizable_activities", "1"); } catch (Throwable ignored) { }

            DisplayManager m = displayManager();
            VirtualDisplay vd = m.createVirtualDisplay("UltraDroid-VD", width, height, dpi, surface, flags(), null, handler);
            if (vd == null) {
                lastError = "createVirtualDisplay null döndü";
                return -1;
            }
            int id = vd.getDisplay().getDisplayId();
            displays.put(id, vd);
            lastSize.put(id, new int[]{width, height, dpi});
            lastError = "";
            return id;
        } catch (Throwable t) {
            lastError = describe(t);
            return -1;
        }
    }

    @Override
    public synchronized void resize(int displayId, Surface surface, int width, int height, int dpi) {
        try {
            VirtualDisplay vd = displays.get(displayId);
            if (vd == null) return;
            width = Math.max(16, Math.min(4096, width));
            height = Math.max(16, Math.min(4096, height));
            int[] last = lastSize.get(displayId);
            // Boyut aynıysa sanal ekranı yeniden boyutlandırma: uygulamaya gereksiz yapılandırma değişikliği gitmesin
            if (last == null || last[0] != width || last[1] != height || last[2] != dpi) {
                vd.resize(width, height, dpi);
                lastSize.put(displayId, new int[]{width, height, dpi});
            }
            if (surface != null && surface.isValid()) vd.setSurface(surface);
        } catch (Throwable t) {
            lastError = describe(t);
        }
    }

    @Override
    public String launch(int displayId, String component) {
        try {
            if (!displays.containsKey(displayId)) return "Sanal ekran yok";
            if (component == null || !COMPONENT_OK.matcher(component).matches()) return "Geçersiz bileşen";
            pkgs.put(displayId, component.substring(0, component.indexOf('/')));
            String out = sh("am", "start", "--display", String.valueOf(displayId), "-n", component);
            // am hata verirse çıktıda "Error" geçer
            if (out.contains("Error") || out.contains("Exception")) return out;
            return "";
        } catch (Throwable t) {
            return describe(t);
        }
    }

    // ---- Koordinat çevirisi: SurfaceView oranı -> VirtualDisplay pikseli ----
    // VirtualDisplay, SurfaceView'in mevcut genişlik/yüksekliğiyle oluşturulur ve
    // yeniden boyutlandırılır. Bu nedenle SurfaceView'den gelen normalize x/y
    // koordinatlarına Display.getRotation() dönüşümünü tekrar uygulamak hatalıdır:
    // özellikle 90/270 derecede eksenleri yer değiştirip fareyi ters/yan hareket ettirir.
    // rot parametresi AIDL uyumluluğu için korunur; koordinat dönüşümünde kullanılmaz.
    private float[] map(int id, float nx, float ny, int rot) {
        int[] size = lastSize.get(id);
        int width = (size != null && size.length > 1) ? Math.max(1, size[0]) : 1;
        int height = (size != null && size.length > 1) ? Math.max(1, size[1]) : 1;

        nx = Math.max(0f, Math.min(1f, nx));
        ny = Math.max(0f, Math.min(1f, ny));

        float px = nx * Math.max(0, width - 1);
        float py = ny * Math.max(0, height - 1);
        return new float[]{px, py};
    }

    @Override
    public void injectTouch(int displayId, int action, int actionIndex, float[] xs, float[] ys, int[] ids, int count, long downTime, int rot) {
        try {
            if (!displays.containsKey(displayId) || count <= 0) return;
            MotionEvent.PointerProperties[] props = new MotionEvent.PointerProperties[count];
            MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[count];
            for (int i = 0; i < count; i++) {
                float[] xy = map(displayId, xs[i], ys[i], rot);
                props[i] = new MotionEvent.PointerProperties();
                props[i].id = ids[i];
                props[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
                coords[i] = new MotionEvent.PointerCoords();
                coords[i].x = xy[0];
                coords[i].y = xy[1];
                coords[i].pressure = 1f;
                coords[i].size = 1f;
            }
            int act = action;
            if (action == MotionEvent.ACTION_POINTER_DOWN || action == MotionEvent.ACTION_POINTER_UP) {
                act = action | (actionIndex << MotionEvent.ACTION_POINTER_INDEX_SHIFT);
            }
            long now = SystemClock.uptimeMillis();
            MotionEvent ev = MotionEvent.obtain(downTime > 0 ? downTime : now, now, act, count, props, coords,
                    0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
            inject(displayId, ev);
            ev.recycle();
        } catch (Throwable t) {
            lastError = describe(t);
        }
    }

    private Method setActionButtonMethod;

    @Override
    public void injectMouse(int displayId, int action, float x, float y, int buttonState, int actionButton,
                            float hscroll, float vscroll, long downTime, int rot) {
        try {
            if (!displays.containsKey(displayId)) return;
            float[] xy = map(displayId, x, y, rot);
            MotionEvent.PointerProperties[] props = new MotionEvent.PointerProperties[1];
            MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[1];
            props[0] = new MotionEvent.PointerProperties();
            props[0].id = 0;
            props[0].toolType = MotionEvent.TOOL_TYPE_MOUSE;
            coords[0] = new MotionEvent.PointerCoords();
            coords[0].x = xy[0];
            coords[0].y = xy[1];
            coords[0].pressure = (buttonState != 0) ? 1f : 0f;
            coords[0].size = 1f;
            if (action == MotionEvent.ACTION_SCROLL) {
                coords[0].setAxisValue(MotionEvent.AXIS_HSCROLL, hscroll);
                coords[0].setAxisValue(MotionEvent.AXIS_VSCROLL, vscroll);
            }
            long now = SystemClock.uptimeMillis();
            MotionEvent ev = MotionEvent.obtain(downTime > 0 ? downTime : now, now, action, 1, props, coords,
                    0, buttonState, 1f, 1f, 0, 0, InputDevice.SOURCE_MOUSE, 0);
            if (actionButton != 0) {
                try {
                    if (setActionButtonMethod == null) {
                        setActionButtonMethod = MotionEvent.class.getDeclaredMethod("setActionButton", int.class);
                        setActionButtonMethod.setAccessible(true);
                    }
                    setActionButtonMethod.invoke(ev, actionButton);
                } catch (Throwable ignored) { }
            }
            inject(displayId, ev);
            ev.recycle();
        } catch (Throwable t) {
            lastError = describe(t);
        }
    }

    @Override
    public void injectKey(int displayId, int keyCode) {
        try {
            if (!displays.containsKey(displayId)) return;
            long now = SystemClock.uptimeMillis();
            KeyEvent down = new KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0, 0, -1, 0, 0, InputDevice.SOURCE_KEYBOARD);
            KeyEvent up = new KeyEvent(now, now, KeyEvent.ACTION_UP, keyCode, 0, 0, -1, 0, 0, InputDevice.SOURCE_KEYBOARD);
            inject(displayId, down);
            inject(displayId, up);
        } catch (Throwable t) {
            lastError = describe(t);
        }
    }

    @Override
    public synchronized void close(int displayId) {
        closeDisplay(displayId);
    }

    @Override
    public synchronized void closeAll() {
        for (Integer id : new java.util.ArrayList<>(displays.keySet())) closeDisplay(id);
    }

    @Override
    public String lastError() {
        return lastError;
    }

    @Override
    public void destroy() {
        try { closeAll(); } catch (Throwable ignored) { }
        thread.quitSafely();
        System.exit(0);
    }

    // ---------------------------------------------------------------- iç işler

    /** Sanal ekranı bırakır ve içindeki uygulamayı tamamen kapatır. */
    private void closeDisplay(int id) {
        lastSize.remove(id);
        VirtualDisplay vd = displays.remove(id);
        try {
            if (vd != null) vd.release();
        } catch (Throwable ignored) {
        }
        String pkg = pkgs.remove(id);
        if (pkg != null) {
            try { sh("am", "force-stop", pkg); } catch (Throwable ignored) { }
        }
    }

    private void inject(int displayId, InputEvent ev) throws Exception {
      synchronized (injLock) {
        if (injectMethod == null) {
            Object im;
            try {
                // Android 14+
                Class<?> g = Class.forName("android.hardware.input.InputManagerGlobal");
                im = g.getMethod("getInstance").invoke(null);
            } catch (Throwable t) {
                Class<?> c = Class.forName("android.hardware.input.InputManager");
                Method gi = c.getDeclaredMethod("getInstance");
                gi.setAccessible(true);
                im = gi.invoke(null);
            }
            Method inj = im.getClass().getMethod("injectInputEvent", InputEvent.class, int.class);
            inj.setAccessible(true);
            Method sd = InputEvent.class.getDeclaredMethod("setDisplayId", int.class);
            sd.setAccessible(true);
            inputMgr = im;
            injectMethod = inj;
            setDisplayIdMethod = sd;
        }
        setDisplayIdMethod.invoke(ev, displayId);
        injectMethod.invoke(inputMgr, ev, 0 /* INJECT_INPUT_EVENT_MODE_ASYNC */);
      }
    }

    private static String describe(Throwable t) {
        Throwable c = t;
        while (c.getCause() != null) c = c.getCause();
        return c.getClass().getSimpleName() + ": " + c.getMessage();
    }
}
