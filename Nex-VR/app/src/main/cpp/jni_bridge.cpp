// Nex VR — Stage 74: HandKin.java ↔ nx::Kinematics JNI köprüsü.
// Veri doğrudan (direct) ByteBuffer'lar üzerinden paylaşılır: JNI geçişinde dizi kopyası yok, kare başına ayırma yok.
#include <jni.h>

#include <new>

#include "hand_kinematics.h"

extern "C" {

JNIEXPORT jlong JNICALL Java_com_nexus_vr_HandKin_nCreate(JNIEnv*, jclass) {
  return reinterpret_cast<jlong>(new (std::nothrow) nx::Kinematics());
}

JNIEXPORT void JNICALL Java_com_nexus_vr_HandKin_nDestroy(JNIEnv*, jclass, jlong h) {
  delete reinterpret_cast<nx::Kinematics*>(h);
}

JNIEXPORT void JNICALL Java_com_nexus_vr_HandKin_nReset(JNIEnv*, jclass, jlong h) {
  if (h) reinterpret_cast<nx::Kinematics*>(h)->reset();
}

JNIEXPORT void JNICALL Java_com_nexus_vr_HandKin_nConfig(JNIEnv*, jclass, jlong h, jboolean filter, jfloat minCut,
                                                         jfloat beta, jfloat dCut) {
  if (!h) return;
  auto* k = reinterpret_cast<nx::Kinematics*>(h);
  k->cfg.filter = filter == JNI_TRUE;
  if (minCut > 0.05f && minCut < 20.f) k->cfg.minCut = minCut;
  if (beta >= 0.f && beta < 100.f) k->cfg.beta = beta;
  if (dCut > 0.05f && dCut < 20.f) k->cfg.dCut = dCut;
}

// in/out: native sıralı direct ByteBuffer. Dönen: yazılan el sayısı (hata: -1).
JNIEXPORT jint JNICALL Java_com_nexus_vr_HandKin_nProcess(JNIEnv* env, jclass, jlong h, jobject in, jobject out,
                                                          jint nHands, jlong tNs, jfloat aspect) {
  if (!h || !in || !out) return -1;
  auto* pin = static_cast<float*>(env->GetDirectBufferAddress(in));
  auto* pout = static_cast<float*>(env->GetDirectBufferAddress(out));
  if (!pin || !pout) return -1;
  const jlong capIn = env->GetDirectBufferCapacity(in), capOut = env->GetDirectBufferCapacity(out);
  if (nHands < 0) nHands = 0;
  if (nHands > nx::kMaxHands) nHands = nx::kMaxHands;
  if (capIn < (jlong)(sizeof(float) * nx::kInStride * nHands) || capOut < (jlong)(sizeof(float) * nx::O_STRIDE * nHands))
    return -1;
  return reinterpret_cast<nx::Kinematics*>(h)->process(pin, nHands, (int64_t)tNs, aspect, pout);
}

JNIEXPORT jint JNICALL Java_com_nexus_vr_HandKin_nStride(JNIEnv*, jclass) { return nx::O_STRIDE; }

}  // extern "C"
