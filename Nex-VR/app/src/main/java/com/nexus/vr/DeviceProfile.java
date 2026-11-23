package com.nexus.vr;

import android.app.ActivityManager;
import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorManager;
import android.os.Build;
import android.view.Display;
import android.view.WindowManager;

import org.json.JSONObject;

/**
 * Stage 63 — Cihaz sınıfı (telefon / tablet) ve performans seviyesi (0 düşük, 1 orta, 2 yüksek).
 *
 * Eskiden "hafif cihaz" tüm Android'lerde (tablet dahil) açıktı; güçlü bir telefon da güçlü bir tablet de
 * en düşük ayarlarla çalışıyordu. Burada tek bir yerde ölçülür, hem Java (AppMirror, yenileme hızı)
 * hem de JS (render bütçesi, el takibi profili) aynı sonucu kullanır.
 *
 * Seviye kuralı (bilinçli olarak temkinli; Tab S6 Lite gibi 4 GB'lık orta sınıf cihazlar "orta" kalır):
 *   0 düşük : düşük RAM bayrağı, ~3 GB ve altı, yalnızca 32-bit ABI veya en çok 4 çekirdek
 *   2 yüksek: ~5 GiB ve üstü RAM, en az 8 çekirdek, Android 10+, arm64
 *   1 orta  : geri kalan her şey
 */
final class DeviceProfile {
    final boolean phone;
    final int tier;
    final int swDp;
    final double ramGiB;
    final boolean lowRam;
    final int cores;
    final boolean arm64;
    final int sdk;
    final float hz;
    final float maxHz;
    /** Stage 64: bu ekran boyutunda desteklenen yenileme hızları (Hz, artan, tekrarsız). */
    final int[] hzs;
    /** Stage 65: hareket sensörü sınıfı: "rv" (rotation-vector), "am" (ivmeölçer+pusula), "acc" (yalnız ivmeölçer), "none". */
    final String sensor;
    /** Stage 65: ham donanım jiroskobu (TYPE_GYROSCOPE) var mı. */
    final boolean gyroHw;

    private DeviceProfile(boolean phone, int tier, int swDp, double ramGiB, boolean lowRam, int cores,
                          boolean arm64, int sdk, float hz, float maxHz, int[] hzs, String sensor, boolean gyroHw) {
        this.phone = phone; this.tier = tier; this.swDp = swDp; this.ramGiB = ramGiB; this.lowRam = lowRam;
        this.cores = cores; this.arm64 = arm64; this.sdk = sdk; this.hz = hz; this.maxHz = maxHz; this.hzs = hzs;
        this.sensor = sensor; this.gyroHw = gyroHw;
    }

    /** Saf karar mantığı: en iyi kullanılabilir sensör yolu (MainActivity ile aynı öncelik). */
    static String sensorOf(boolean rotationVector, boolean accel, boolean magnetic) {
        if (rotationVector) return "rv";
        if (accel && magnetic) return "am";
        if (accel) return "acc";
        return "none";
    }

    /** Saf karar mantığı (Android'e bağlı değil; birim testi için ayrı). */
    static int tierOf(boolean lowRam, double ramGiB, int cores, boolean arm64, int sdk) {
        if (lowRam || (ramGiB > 0 && ramGiB <= 3.2) || !arm64 || cores <= 4) return 0;
        if (ramGiB >= 5.0 && cores >= 8 && sdk >= 29) return 2;
        return 1;
    }

    static DeviceProfile collect(Context ctx) {
        int sw = ctx.getResources().getConfiguration().smallestScreenWidthDp;
        boolean low = false;
        double ram = 0;
        try {
            ActivityManager am = (ActivityManager) ctx.getSystemService(Context.ACTIVITY_SERVICE);
            if (am != null) {
                low = am.isLowRamDevice();
                ActivityManager.MemoryInfo mi = new ActivityManager.MemoryInfo();
                am.getMemoryInfo(mi);
                ram = mi.totalMem / (1024.0 * 1024.0 * 1024.0);
            }
        } catch (Throwable ignored) { }
        int cores = Math.max(1, Runtime.getRuntime().availableProcessors());
        boolean a64 = false;
        try {
            String[] abis = Build.SUPPORTED_64_BIT_ABIS;
            a64 = abis != null && abis.length > 0;
        } catch (Throwable ignored) { }
        float hz = 60f, max = 60f;
        java.util.TreeSet<Integer> rates = new java.util.TreeSet<>();
        try {
            WindowManager wm = (WindowManager) ctx.getSystemService(Context.WINDOW_SERVICE);
            Display d = wm == null ? null : wm.getDefaultDisplay();
            if (d != null) {
                hz = d.getRefreshRate();
                max = hz;
                rates.add(Math.round(hz));
                if (Build.VERSION.SDK_INT >= 23) {
                    Display.Mode cur = d.getMode();
                    for (Display.Mode m : d.getSupportedModes()) {
                        if (m.getPhysicalWidth() == cur.getPhysicalWidth() && m.getPhysicalHeight() == cur.getPhysicalHeight()) {
                            if (m.getRefreshRate() > max) max = m.getRefreshRate();
                            rates.add(Math.round(m.getRefreshRate()));
                        }
                    }
                }
            }
        } catch (Throwable ignored) { }
        boolean rv = false, acc = false, mag = false, gyro = false;
        try {
            SensorManager sm = (SensorManager) ctx.getSystemService(Context.SENSOR_SERVICE);
            if (sm != null) {
                rv = sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR) != null
                        || sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null;
                acc = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null;
                mag = sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null;
                gyro = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != null;
            }
        } catch (Throwable ignored) { }
        int tier = tierOf(low, ram, cores, a64, Build.VERSION.SDK_INT);
        return new DeviceProfile(sw < 600, tier, sw, ram, low, cores, a64, Build.VERSION.SDK_INT, hz, max, toArr(rates),
                sensorOf(rv, acc, mag), gyro);
    }

    private static int[] toArr(java.util.Set<Integer> set) {
        int[] a = new int[set.size()];
        int i = 0;
        for (Integer v : set) a[i++] = v;
        return a;
    }

    String toJson() {
        try {
            JSONObject o = new JSONObject();
            o.put("cls", phone ? "phone" : "tablet");
            o.put("tier", tier);
            o.put("swdp", swDp);
            o.put("ram", Math.round(ramGiB * 10) / 10.0);
            o.put("lowRam", lowRam);
            o.put("cores", cores);
            o.put("arm64", arm64);
            o.put("sdk", sdk);
            o.put("hz", Math.round(hz));
            o.put("maxHz", Math.round(maxHz));
            o.put("sensor", sensor);
            o.put("gyro", gyroHw);
            org.json.JSONArray ha = new org.json.JSONArray();
            for (int r : hzs) ha.put(r);
            o.put("hzs", ha);
            return o.toString();
        } catch (Throwable e) {
            return "{}";
        }
    }
}
