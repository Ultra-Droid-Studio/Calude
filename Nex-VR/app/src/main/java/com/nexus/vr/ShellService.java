package com.nexus.vr;

import android.content.Context;
import android.content.ContextWrapper;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.os.Build;
import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.Surface;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/**
 * Stage 56 — Shizuku UserService. Bu sınıf UYGULAMA sürecinde değil, Shizuku'nun başlattığı
 * shell-uid sürecinde çalışır. Burada gizli (hidden) API'lere yansıma ile erişmek serbesttir
 * (süreç zygote'tan türemediği için gizli API kısıtı yoktur).
 *
 * Güvenlik: yalnızca sabit işlemler vardır; bileşen ve paket adları sıkı biçimde doğrulanır,
 * komut dizesine kullanıcı verisi doğrudan eklenmez (argüman dizisi kullanılır).
 *
 * Stage 57: `am` çıktısı okunur ve zaman aşımı vardır (takılan komut servisi dondurmaz); başlatma
 * sonucu çıktıya bakılarak doğrulanır; metin yazma (typeText) eklendi; tuş olayları klavye kaynaklıdır.
 */
public class ShellService extends IShellService.Stub {
    private static final Pattern COMP = Pattern.compile("^[A-Za-z0-9_.]+/[A-Za-z0-9_.$]+$");
    private static final Pattern PKG = Pattern.compile("^[A-Za-z0-9_]+(\\.[A-Za-z0-9_]+)+$");

    /** Servis API sürümü: ShizukuLink.SERVICE_VERSION ile birlikte artırılır. */
    static final int API_VERSION = 3;
    /** launch() dönüş kodları (IShellService.aidl'deki açıklamayla aynı). */
    static final int L_OK = 0, L_FRONT = 10, L_ERROR = 11, L_INVALID = -2, L_FAIL = -1;
    private static final int MAX_TEXT = 64;
    private static final long AM_TIMEOUT_MS = 8000;

    private Object inputManager;
    private Method inject;
    private Method setDisplayIdMotion, setDisplayIdKey;

    /** Shizuku bu kurucuyu çağırır. */
    public ShellService() { }

    @Override public void destroy() {
        releaseAllDisplays();
        System.exit(0);
    }

    @Override
    public int launch(String component, int displayId) {
        if (component == null || !COMP.matcher(component).matches() || displayId < 0) return L_INVALID;
        Out o = run(AM_TIMEOUT_MS, amBin(), "start", "--display", String.valueOf(displayId),
                "-f", "0x18000000", // NEW_TASK | MULTIPLE_TASK
                "-n", component);
        if (o.code == -1) return L_FAIL;
        String t = o.text.toLowerCase(Locale.ROOT);
        // Görev zaten başka ekranda (ör. singleTask/singleInstance) ise `am` onu öne alır ve sanal ekrana HİÇBİR ŞEY açılmaz.
        if (t.contains("not started") || t.contains("brought to the front")) return L_FRONT;
        if (t.contains("error:") || t.contains("exception") || t.contains("permission denial")
                || t.contains("does not exist") || t.contains("error type")) return L_ERROR;
        return o.code;
    }

    @Override
    public boolean stopPackage(String pkg) {
        if (pkg == null || !PKG.matcher(pkg).matches()) return false;
        return run(AM_TIMEOUT_MS, amBin(), "force-stop", pkg).code == 0;
    }

    @Override
    public boolean touch(int displayId, int action, float x, float y, long downTime) {
        if (displayId < 0 || action < 0 || action > 3 || !Float.isFinite(x) || !Float.isFinite(y)) return false;
        int act = action == 0 ? MotionEvent.ACTION_DOWN : action == 1 ? MotionEvent.ACTION_MOVE
                : action == 2 ? MotionEvent.ACTION_UP : MotionEvent.ACTION_CANCEL;
        long now = SystemClock.uptimeMillis();
        if (downTime <= 0 || downTime > now) downTime = now;
        MotionEvent ev = MotionEvent.obtain(downTime, now, act, x, y, 1f, 1f, 0, 1f, 1f, 0, 0);
        try {
            ev.setSource(InputDevice.SOURCE_TOUCHSCREEN);
            return send(ev, displayId);
        } finally { ev.recycle(); }
    }

    @Override
    public boolean key(int displayId, int keyCode) {
        if (displayId < 0 || keyCode <= 0 || keyCode > 300) return false;
        return sendKey(displayId, keyCode, 0);
    }

    @Override
    public int version() { return API_VERSION; }

    // ---- Stage 58: güvenilir sanal ekran (shell yetkisiyle) ----

    private static final int MAX_DISPLAYS = 4;
    private static final Pattern DNAME = Pattern.compile("^[A-Za-z0-9 _.-]{1,40}$");
    private final Map<Integer, VirtualDisplay> displays = new ConcurrentHashMap<>();
    private Context fakeCtx;

    /** DisplayManager.VIRTUAL_DISPLAY_FLAG_* değerlerini adıyla okur (gizli alanlar); okunamazsa bilinen sayı kullanılır. */
    private static int vflag(String name, int fallback) {
        try { return DisplayManager.class.getField(name).getInt(null); } catch (Throwable e) { return fallback; }
    }

    /** "com.android.shell" paketi adına konuşan bağlam: sistem hizmeti paket adını çağıran uid ile eşleştirir. */
    private static final class ShellContext extends ContextWrapper {
        ShellContext(Context base) { super(base); }
        @Override public String getPackageName() { return "com.android.shell"; }
        @Override public String getOpPackageName() { return "com.android.shell"; }
        @Override public Context getApplicationContext() { return this; }
        @Override public int getDeviceId() { return 0; }
        @Override public android.content.AttributionSource getAttributionSource() {
            return new android.content.AttributionSource.Builder(2000).setPackageName("com.android.shell").build();
        }
    }

    private Context shellContext() {
        if (fakeCtx != null) return fakeCtx;
        Context base = null;
        try {
            Class<?> at = Class.forName("android.app.ActivityThread");
            Object t = null;
            try { t = at.getMethod("currentActivityThread").invoke(null); } catch (Throwable ignored) { }
            if (t == null) {
                java.lang.reflect.Constructor<?> k = at.getDeclaredConstructor();
                k.setAccessible(true);
                t = k.newInstance();
                try {
                    java.lang.reflect.Field f = at.getDeclaredField("sCurrentActivityThread");
                    f.setAccessible(true); f.set(null, t);
                    java.lang.reflect.Field st = at.getDeclaredField("mSystemThread");
                    st.setAccessible(true); st.setBoolean(t, true);
                } catch (Throwable ignored) { }
            }
            base = (Context) at.getMethod("getSystemContext").invoke(t);
        } catch (Throwable e) { base = null; }
        fakeCtx = new ShellContext(base);
        return fakeCtx;
    }

    private VirtualDisplay makeDisplay(String name, int w, int h, int dpi, Surface surface, int flags) throws Exception {
        java.lang.reflect.Constructor<DisplayManager> k = DisplayManager.class.getDeclaredConstructor(Context.class);
        k.setAccessible(true);
        DisplayManager dm = k.newInstance(shellContext());
        return dm.createVirtualDisplay(name, w, h, dpi, surface, flags);
    }

    @Override
    public int createDisplay(String name, int width, int height, int dpi, Surface surface) {
        if (name == null || !DNAME.matcher(name).matches() || surface == null || !surface.isValid()) return L_FAIL;
        if (width < 64 || width > 4096 || height < 64 || height > 4096 || dpi < 72 || dpi > 640) return L_FAIL;
        if (displays.size() >= MAX_DISPLAYS) return L_FAIL;
        if (Build.VERSION.SDK_INT < 33) return L_FAIL; // TRUSTED bayrağı Android 13 ile geldi
        int base = vflag("VIRTUAL_DISPLAY_FLAG_PUBLIC", 1) | vflag("VIRTUAL_DISPLAY_FLAG_PRESENTATION", 2)
                | vflag("VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY", 8) | vflag("VIRTUAL_DISPLAY_FLAG_SUPPORTS_TOUCH", 64)
                | vflag("VIRTUAL_DISPLAY_FLAG_DESTROY_CONTENT_ON_REMOVAL", 256)
                | vflag("VIRTUAL_DISPLAY_FLAG_TRUSTED", 1 << 10);
        int more = vflag("VIRTUAL_DISPLAY_FLAG_OWN_DISPLAY_GROUP", 1 << 11) | vflag("VIRTUAL_DISPLAY_FLAG_ALWAYS_UNLOCKED", 1 << 12)
                | vflag("VIRTUAL_DISPLAY_FLAG_TOUCH_FEEDBACK_DISABLED", 1 << 13);
        int more14 = vflag("VIRTUAL_DISPLAY_FLAG_OWN_FOCUS", 1 << 14) | vflag("VIRTUAL_DISPLAY_FLAG_DEVICE_DISPLAY_GROUP", 1 << 15);
        // Önce tam bayrak kümesi, olmazsa yalnızca güvenilir (trusted) çekirdek. Güvenilir olmayan ekranın bir faydası yok.
        int[] tries = Build.VERSION.SDK_INT >= 34 ? new int[]{base | more | more14, base | more, base}
                : new int[]{base | more, base};
        for (int flags : tries) {
            try {
                VirtualDisplay vd = makeDisplay(name, width, height, dpi, surface, flags);
                if (vd == null || vd.getDisplay() == null) { if (vd != null) vd.release(); continue; }
                int id = vd.getDisplay().getDisplayId();
                displays.put(id, vd);
                return id;
            } catch (Throwable e) {
                android.util.Log.w("NEXUS-Shell", "güvenilir ekran açılamadı (bayrak " + flags + "): " + e);
            }
        }
        return L_FAIL;
    }

    @Override
    public boolean resizeDisplay(int displayId, int width, int height, int dpi, Surface surface) {
        VirtualDisplay vd = displays.get(displayId);
        if (vd == null || surface == null || !surface.isValid()) return false;
        if (width < 64 || width > 4096 || height < 64 || height > 4096 || dpi < 72 || dpi > 640) return false;
        try { vd.setSurface(surface); vd.resize(width, height, dpi); return true; } catch (Throwable e) { return false; }
    }

    @Override
    public void releaseDisplay(int displayId) {
        VirtualDisplay vd = displays.remove(displayId);
        if (vd != null) { try { vd.release(); } catch (Throwable ignored) { } }
    }

    private void releaseAllDisplays() {
        for (Integer id : displays.keySet()) releaseDisplay(id);
    }


    /**
     * Metni odaklı alana yazar. ASCII karakterler standart (ABD sanal klavye) tuş dizisine çevrilir
     * (Shift dahil). Eşleşmeyen karakterler (ç ş ğ ı ö ü İ ...) için ACTION_MULTIPLE denenir; bu yol
     * Android sürümüne ve uygulamaya bağlıdır, garanti değildir. Dönüş: işlenen karakter sayısı.
     */
    @Override
    public int typeText(int displayId, String text) {
        if (displayId < 0 || text == null || text.isEmpty() || text.length() > MAX_TEXT) return -1;
        int done = 0;
        int i = 0;
        while (i < text.length()) {
            int cp = text.codePointAt(i);
            i += Character.charCount(cp);
            if (cp < 32 || cp == 127) continue; // denetim karakterleri yazılmaz (Enter/Sil ayrı tuşlardır)
            boolean ok = false;
            if (cp < 128) ok = typeAscii((char) cp, displayId);
            if (!ok) ok = typeMultiple(new String(Character.toChars(cp)), displayId);
            if (ok) done++;
        }
        return done;
    }

    @Override
    public boolean swipe(int displayId, float x0, float y0, float x1, float y1, int durationMs) {
        int dur = Math.max(60, Math.min(durationMs, 800));
        int steps = Math.max(4, dur / 16);
        long t0 = SystemClock.uptimeMillis();
        boolean ok = touch(displayId, 0, x0, y0, t0);
        for (int i = 1; i <= steps && ok; i++) {
            float k = (float) i / steps;
            SystemClock.sleep(dur / steps);
            ok = touch(displayId, 1, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, t0);
        }
        touch(displayId, ok ? 2 : 3, x1, y1, t0);
        return ok;
    }

    // ---- iç yardımcılar ----

    private KeyCharacterMap kcm;
    private boolean kcmTried;

    private KeyCharacterMap kcm() {
        if (!kcmTried) {
            kcmTried = true;
            try { kcm = KeyCharacterMap.load(KeyCharacterMap.VIRTUAL_KEYBOARD); } catch (Throwable e) { kcm = null; }
        }
        return kcm;
    }

    private boolean sendKey(int displayId, int keyCode, int meta) {
        long now = SystemClock.uptimeMillis();
        KeyEvent d = new KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0, meta,
                KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, InputDevice.SOURCE_KEYBOARD);
        KeyEvent u = new KeyEvent(now, now + 15, KeyEvent.ACTION_UP, keyCode, 0, meta,
                KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, InputDevice.SOURCE_KEYBOARD);
        boolean a = send(d, displayId);
        boolean b = send(u, displayId);
        return a && b;
    }

    private boolean typeAscii(char c, int displayId) {
        KeyCharacterMap m = kcm();
        if (m != null) {
            try {
                KeyEvent[] evs = m.getEvents(new char[]{c});
                if (evs != null && evs.length > 0) {
                    boolean ok = true;
                    long now = SystemClock.uptimeMillis();
                    for (KeyEvent e : evs) {
                        KeyEvent k = new KeyEvent(now, now, e.getAction(), e.getKeyCode(), 0, e.getMetaState(),
                                KeyCharacterMap.VIRTUAL_KEYBOARD, 0, 0, InputDevice.SOURCE_KEYBOARD);
                        ok &= send(k, displayId);
                    }
                    return ok;
                }
            } catch (Throwable ignored) { /* aşağıdaki yedek tabloya düş */ }
        }
        // Yedek: harf, rakam ve birkaç işaret
        int code = 0, meta = 0;
        if (c >= 'a' && c <= 'z') code = KeyEvent.KEYCODE_A + (c - 'a');
        else if (c >= 'A' && c <= 'Z') { code = KeyEvent.KEYCODE_A + (c - 'A'); meta = KeyEvent.META_SHIFT_ON; }
        else if (c >= '0' && c <= '9') code = KeyEvent.KEYCODE_0 + (c - '0');
        else if (c == ' ') code = KeyEvent.KEYCODE_SPACE;
        else if (c == '.') code = KeyEvent.KEYCODE_PERIOD;
        else if (c == ',') code = KeyEvent.KEYCODE_COMMA;
        else if (c == '-') code = KeyEvent.KEYCODE_MINUS;
        else if (c == '/') code = KeyEvent.KEYCODE_SLASH;
        else if (c == '@') code = KeyEvent.KEYCODE_AT;
        if (code == 0) return false;
        return sendKey(displayId, code, meta);
    }

    @SuppressWarnings("deprecation")
    private boolean typeMultiple(String s, int displayId) {
        try {
            KeyEvent e = new KeyEvent(SystemClock.uptimeMillis(), s, KeyCharacterMap.VIRTUAL_KEYBOARD, 0);
            return send(e, displayId);
        } catch (Throwable t) {
            return false;
        }
    }

    private static String amBin() {
        return new java.io.File("/system/bin/am").exists() ? "/system/bin/am" : "am";
    }

    private boolean send(InputEvent ev, int displayId) {
        try {
            if (inject == null) init();
            if (ev instanceof MotionEvent) setDisplayIdMotion.invoke(ev, displayId);
            else setDisplayIdKey.invoke(ev, displayId);
            // 0 = INJECT_INPUT_EVENT_MODE_ASYNC
            return (Boolean) inject.invoke(inputManager, ev, 0);
        } catch (Throwable e) {
            return false;
        }
    }

    private void init() throws Exception {
        // Android 14+: InputManagerGlobal; eski sürümler: InputManager.getInstance()
        Object im = null;
        try {
            Class<?> g = Class.forName("android.hardware.input.InputManagerGlobal");
            im = g.getMethod("getInstance").invoke(null);
            inject = g.getMethod("injectInputEvent", InputEvent.class, int.class);
        } catch (Throwable ignored) { im = null; }
        if (im == null) {
            Class<?> c = Class.forName("android.hardware.input.InputManager");
            im = c.getDeclaredMethod("getInstance").invoke(null);
            inject = c.getMethod("injectInputEvent", InputEvent.class, int.class);
        }
        inputManager = im;
        setDisplayIdMotion = InputEvent.class.getMethod("setDisplayId", int.class);
        setDisplayIdKey = setDisplayIdMotion;
    }

    /** Komut sonucu: çıkış kodu (-1 = çalışmadı / zaman aşımı) ve birleşik çıktı (en çok ~8 KB). */
    private static final class Out {
        final int code; final String text;
        Out(int c, String t) { code = c; text = t; }
    }

    /** Argüman dizisiyle komut çalıştırır; çıktı ayrı iş parçacığında okunur, süre dolarsa süreç öldürülür. */
    private static Out run(long timeoutMs, String... cmd) {
        Process p = null;
        try {
            p = new ProcessBuilder(cmd).redirectErrorStream(true).start();
            final Process fp = p;
            final StringBuilder sb = new StringBuilder();
            Thread rd = new Thread(() -> {
                try (BufferedReader r = new BufferedReader(new InputStreamReader(fp.getInputStream()))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        synchronized (sb) { if (sb.length() < 8192) sb.append(line).append('\n'); }
                    }
                } catch (Throwable ignored) { }
            }, "nexus-shell-out");
            rd.setDaemon(true);
            rd.start();
            rd.join(timeoutMs);
            if (rd.isAlive()) { p.destroy(); return new Out(-1, ""); }
            int code = p.waitFor();
            String text;
            synchronized (sb) { text = sb.toString(); }
            return new Out(code, text);
        } catch (Throwable e) {
            if (p != null) { try { p.destroy(); } catch (Throwable ignored) { } }
            return new Out(-1, "");
        }
    }
}
