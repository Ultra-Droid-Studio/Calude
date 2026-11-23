package com.nexus.vr;

import android.util.Log;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

/**
 * Stage 74 — native el kinematiği (libnxhand.so, C++) için ince Java sarmalayıcı.
 *
 * MediaPipe sonucu her karede {@link #in} tamponuna yazılır, {@link #process} tek bir JNI çağrısıyla C++ tarafında
 * süzgeç + parmak bükülmeleri + çimdik + avuç yönü + hız + güven + ışınlanma reddi hesaplar ve sonucu {@link #out}
 * tamponuna yazar. Tamponlar doğrudan (direct) olduğu için JNI geçişinde kopya yok, kare başına bellek ayırma yok.
 *
 * Kitaplık yüklenemezse (ABI eksik / derlenmemiş) {@link #available()} false döner; NativeCam eski (ham landmark) yoluna
 * döner, JS tarafı da kendi süzgecini kullanır. Yani native modül eksikliği el takibini bozmaz.
 *
 * Yalnızca tek iş parçacığından (MediaPipe sonuç iş parçacığı) kullanılır; kilit gerekmez.
 */
final class HandKin {
    static final String TAG = "NEXUS-HandKin";
    /** hand_kinematics.h: kInStride = 2 + 21*3 */
    static final int IN_STRIDE = 65;
    /** hand_kinematics.h: O_STRIDE = O_LM(27) + 63 */
    static final int OUT_STRIDE = 90;
    static final int O_SLOT = 0, O_FLAGS = 1, O_CONF = 2, O_SIZE = 3, O_CURL = 4, O_PINCH = 9, O_SPREAD = 13,
            O_NORMAL = 17, O_QUAT = 20, O_VEL = 24, O_LM = 27;

    private static final boolean LOADED;

    static {
        boolean ok;
        try {
            System.loadLibrary("nxhand");
            ok = nStride() == OUT_STRIDE;
            if (!ok) Log.w(TAG, "libnxhand sürüm uyuşmazlığı (adım " + nStride() + " != " + OUT_STRIDE + ")");
        } catch (Throwable e) {
            Log.w(TAG, "libnxhand yüklenemedi, JS süzgeci kullanılacak: " + e);
            ok = false;
        }
        LOADED = ok;
    }

    static boolean available() {
        return LOADED;
    }

    private long h;
    final FloatBuffer in, out;
    private final ByteBuffer inB, outB;

    HandKin() {
        inB = ByteBuffer.allocateDirect(4 * IN_STRIDE * 2).order(ByteOrder.nativeOrder());
        outB = ByteBuffer.allocateDirect(4 * OUT_STRIDE * 2).order(ByteOrder.nativeOrder());
        in = inB.asFloatBuffer();
        out = outB.asFloatBuffer();
        h = LOADED ? nCreate() : 0;
    }

    boolean ok() {
        return h != 0;
    }

    void config(boolean filter, float minCut, float beta, float dCut) {
        if (h != 0) nConfig(h, filter, minCut, beta, dCut);
    }

    void reset() {
        if (h != 0) nReset(h);
    }

    /** {@link #in} doldurulduktan sonra çağrılır. Dönen: yazılan el sayısı, hata -1. */
    int process(int nHands, long captureNs, float aspect) {
        if (h == 0) return -1;
        return nProcess(h, inB, outB, nHands, captureNs, aspect);
    }

    void release() {
        long x = h;
        h = 0;
        if (x != 0) nDestroy(x);
    }

    // ---- JNI (app/src/main/cpp/jni_bridge.cpp)
    private static native long nCreate();

    private static native void nDestroy(long h);

    private static native void nReset(long h);

    private static native void nConfig(long h, boolean filter, float minCut, float beta, float dCut);

    private static native int nProcess(long h, ByteBuffer in, ByteBuffer out, int nHands, long tNs, float aspect);

    private static native int nStride();
}
