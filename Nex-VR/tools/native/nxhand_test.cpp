// Nex VR — Stage 74: native el kinematiği masaüstü testi.
// Çalıştır: node tools/nxhand.test.js   (g++ ile derler, çalıştırır)
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <ctime>

#include "../../app/src/main/cpp/hand_kinematics.h"

using namespace nx;

static int fails = 0, passes = 0;
#define CHECK(c, msg, ...)                                   \
  do {                                                       \
    if (c) {                                                 \
      passes++;                                              \
      std::printf("PASS " msg "\n", ##__VA_ARGS__);          \
    } else {                                                 \
      fails++;                                               \
      std::printf("FAIL " msg "\n", ##__VA_ARGS__);          \
    }                                                        \
  } while (0)

// Sentetik el: bilek (cx,cy), avuç boyu s (y ekseninde, görüntü yukarı = -y), parmak bükülmesi curl[5] (0..1).
// Bükülme parmak düzleminde kameraya doğru (z-) yapılır; böylece 3B açı ölçümü sınanır.
static void makeHand(float* p, float cx, float cy, float s, const float curl[5], float aspect = 1.f, float thumbToIndex = -1.f) {
  auto set = [&](int i, float x, float y, float z) {
    p[i * 3] = cx + x / aspect;
    p[i * 3 + 1] = cy + y;
    p[i * 3 + 2] = z;
  };
  set(0, 0, 0, 0);
  // taban eklemleri (MCP): avuç üst kenarı
  const float baseX[5] = {0.32f, 0.22f, 0.0f, -0.2f, -0.38f};
  const float baseY[5] = {-0.28f, -0.95f, -1.0f, -0.95f, -0.85f};
  const float segL[5][3] = {{0.32f, 0.28f, 0.24f}, {0.45f, 0.28f, 0.22f}, {0.5f, 0.32f, 0.24f}, {0.46f, 0.3f, 0.22f}, {0.36f, 0.24f, 0.2f}};
  for (int f = 0; f < 5; f++) {
    float x = baseX[f] * s, y = baseY[f] * s, z = 0;
    const int b = 1 + f * 4;
    set(b, x, y, z);
    // parmak yönü: yukarı (başparmak yana-yukarı)
    float dx = f == 0 ? 0.7f : 0.0f, dy = f == 0 ? -0.7f : -1.f;
    const float th = curl[f] * (f == 0 ? 0.55f : 1.25f);  // eklem başına bükülme açısı
    float ang = 0.f;
    for (int j = 0; j < 3; j++) {
      ang += th;
      // bükülme: (dx,dy) düzlem yönü ile -z arasında döner
      const float c = std::cos(ang), sn = std::sin(ang);
      x += dx * c * segL[f][j] * s;
      y += dy * c * segL[f][j] * s;
      z += -sn * segL[f][j] * s;
      set(b + 1 + j, x, y, z);
    }
  }
  if (thumbToIndex >= 0.f) {  // başparmak ucunu işaret ucuna yaklaştır (çimdik)
    const float ix = p[8 * 3], iy = p[8 * 3 + 1], iz = p[8 * 3 + 2];
    p[4 * 3] = ix + thumbToIndex * s / aspect;
    p[4 * 3 + 1] = iy;
    p[4 * 3 + 2] = iz;
  }
}

static void pack(float* in, int h, float score, bool right, const float* lm) {
  in[h * kInStride] = score;
  in[h * kInStride + 1] = right ? 1.f : 0.f;
  std::memcpy(in + h * kInStride + 2, lm, sizeof(float) * kLm * 3);
}

int main() {
  const float open[5] = {0, 0, 0, 0, 0}, fist[5] = {1, 1, 1, 1, 1};
  float lm[kLm * 3], in[kInStride * 2], out[O_STRIDE * 2];
  const int64_t MS = 1000000;

  // 1) Bükülme ve jestler
  {
    Kinematics K;
    K.cfg.filter = false;
    makeHand(lm, .5f, .7f, .15f, open);
    pack(in, 0, .95f, true, lm);
    int n = K.process(in, 1, 1000 * MS, 1.f, out);
    CHECK(n == 1, "tek el işlendi");
    float mx = 0;
    for (int f = 0; f < 5; f++) mx = std::fmax(mx, out[O_CURL + f]);
    CHECK(mx < 0.2f, "açık elde tüm parmak bükülmeleri düşük (en büyük %.2f)", mx);
    CHECK(((int)out[O_FLAGS] & F_OPEN) != 0, "açık el bayrağı");
    CHECK(((int)out[O_FLAGS] & F_FIST) == 0, "açık elde yumruk bayrağı yok");
    makeHand(lm, .5f, .7f, .15f, fist);
    pack(in, 0, .95f, true, lm);
    K.process(in, 1, 1033 * MS, 1.f, out);
    float mn = 1;
    for (int f = 1; f < 5; f++) mn = std::fmin(mn, out[O_CURL + f]);
    CHECK(mn > 0.6f, "yumrukta 4 parmak bükülmesi yüksek (en küçük %.2f)", mn);
    CHECK(((int)out[O_FLAGS] & F_FIST) != 0, "yumruk bayrağı");
    // tek parmak bağımsızlığı: yalnızca işaret parmağı bükük
    const float one[5] = {0, 1, 0, 0, 0};
    makeHand(lm, .5f, .7f, .15f, one);
    pack(in, 0, .95f, true, lm);
    K.process(in, 1, 1066 * MS, 1.f, out);
    CHECK(out[O_CURL + 1] > 0.6f && out[O_CURL + 2] < 0.2f && out[O_CURL + 3] < 0.2f, "işaret parmağı ayrı algılandı (işaret %.2f, orta %.2f, yüzük %.2f)",
          out[O_CURL + 1], out[O_CURL + 2], out[O_CURL + 3]);
    // çimdik
    makeHand(lm, .5f, .7f, .15f, open, 1.f, 0.05f);
    pack(in, 0, .95f, true, lm);
    K.process(in, 1, 1100 * MS, 1.f, out);
    CHECK(out[O_PINCH] < 0.2f && ((int)out[O_FLAGS] & F_PINCH), "başparmak-işaret çimdik (mesafe %.2f)", out[O_PINCH]);
    CHECK(out[O_PINCH + 3] > 0.5f, "başparmak-serçe uzak (%.2f)", out[O_PINCH + 3]);
    // kuaterniyon birim mi, normal birim mi
    const float ql = std::sqrt(out[O_QUAT] * out[O_QUAT] + out[O_QUAT + 1] * out[O_QUAT + 1] + out[O_QUAT + 2] * out[O_QUAT + 2] + out[O_QUAT + 3] * out[O_QUAT + 3]);
    const float nl = std::sqrt(out[O_NORMAL] * out[O_NORMAL] + out[O_NORMAL + 1] * out[O_NORMAL + 1] + out[O_NORMAL + 2] * out[O_NORMAL + 2]);
    CHECK(std::fabs(ql - 1) < 1e-3f && std::fabs(nl - 1) < 1e-3f, "kuaterniyon ve avuç normali birim (%.4f, %.4f)", ql, nl);
    // en-boy oranı düzeltmesi: 4:3 görüntüde aynı el aynı bükülmeyi vermeli
    Kinematics K2;
    K2.cfg.filter = false;
    makeHand(lm, .5f, .7f, .15f, one, 4.f / 3.f);
    pack(in, 0, .95f, true, lm);
    K2.process(in, 1, 1000 * MS, 4.f / 3.f, out);
    CHECK(out[O_CURL + 1] > 0.6f && out[O_CURL + 2] < 0.2f, "4:3 en-boy düzeltmesiyle bükülmeler doğru");
  }

  // 2) Süzgeç: durgun elde titreme azalır, hızlı harekette gecikme küçük
  {
    std::mt19937 rng(7);
    std::normal_distribution<float> nz(0.f, 0.0025f);
    Kinematics K;
    double rawVar = 0, outVar = 0;
    int cnt = 0;
    int64_t t = 0;
    for (int i = 0; i < 120; i++) {
      makeHand(lm, .5f, .6f, .15f, open);
      float noisy[kLm * 3];
      for (int k = 0; k < kLm * 3; k++) noisy[k] = lm[k] + nz(rng);
      pack(in, 0, .9f, false, noisy);
      t += 16 * MS;
      K.process(in, 1, t, 1.f, out);
      if (i > 20) {
        const double r = noisy[8 * 3] - lm[8 * 3], o = out[O_LM + 8 * 3] - lm[8 * 3];
        rawVar += r * r;
        outVar += o * o;
        cnt++;
      }
    }
    CHECK(outVar < rawVar * 0.5, "durgun elde titreme en az yarıya indi (ham %.2e → süzülmüş %.2e)", rawVar / cnt, outVar / cnt);
    // hızlı hareket: 1.2 m/s benzeri (0.03 görüntü birimi/16ms)
    double maxLag = 0;
    float cx = .3f;
    for (int i = 0; i < 25; i++) {
      cx += 0.012f;
      makeHand(lm, cx, .6f, .15f, open);
      pack(in, 0, .9f, false, lm);
      t += 16 * MS;
      K.process(in, 1, t, 1.f, out);
      if (i > 8) maxLag = std::fmax(maxLag, std::fabs(out[O_LM] - lm[0]) / 0.15f);
    }
    CHECK(maxLag < 0.12, "hızlı harekette gecikme küçük (en çok %.3f avuç boyu)", maxLag);
    CHECK(out[O_VEL] > 3.f, "hız hesaplandı (vx %.2f avuç/sn)", out[O_VEL]);
  }

  // 3) Işınlanma reddi ve gerçek hızlı hareketin kabulü
  {
    Kinematics K;
    K.cfg.filter = false;
    int64_t t = 0;
    for (int i = 0; i < 10; i++) {
      makeHand(lm, .4f, .6f, .15f, open);
      pack(in, 0, .9f, true, lm);
      t += 33 * MS;
      K.process(in, 1, t, 1.f, out);
    }
    // tek karelik bozuk iskelet + uzak sıçrama → reddedilmeli
    makeHand(lm, .85f, .2f, .15f, fist);
    for (int k = 0; k < 6; k++) lm[(12 + k % 3) * 3] += 0.2f;  // iskeleti boz
    pack(in, 0, .9f, true, lm);
    t += 33 * MS;
    K.process(in, 1, t, 1.f, out);
    CHECK(((int)out[O_FLAGS] & F_REJECTED) != 0, "tek karelik bozuk sıçrama reddedildi");
    CHECK(std::fabs(out[O_LM] - .4f) < 1e-4f, "reddedilen karede el önceki konumda kaldı (x=%.3f)", out[O_LM]);
    // sonra el eski yerinde görülmeye devam → normal
    makeHand(lm, .4f, .6f, .15f, open);
    pack(in, 0, .9f, true, lm);
    t += 33 * MS;
    K.process(in, 1, t, 1.f, out);
    CHECK(((int)out[O_FLAGS] & F_REJECTED) == 0, "sonraki normal kare kabul edildi");
    // gerçek, iskeleti tutarlı hızlı hareket: hiç reddedilmemeli
    makeHand(lm, .75f, .6f, .15f, open);
    pack(in, 0, .9f, true, lm);
    t += 33 * MS;
    K.process(in, 1, t, 1.f, out);
    CHECK(((int)out[O_FLAGS] & F_REJECTED) == 0 && std::fabs(out[O_LM] - .75f) < 1e-4f, "iskeleti tutarlı hızlı hamle hemen kabul edildi");
    // aynı yere iki kez gelen sıçrama (gerçek) en çok bir karede kabul edilir
    makeHand(lm, .1f, .3f, .15f, fist);
    for (int k = 0; k < 6; k++) lm[(12 + k % 3) * 3] += 0.2f;
    pack(in, 0, .9f, true, lm);
    t += 33 * MS;
    K.process(in, 1, t, 1.f, out);
    const bool r1 = ((int)out[O_FLAGS] & F_REJECTED) != 0;
    t += 33 * MS;
    K.process(in, 1, t, 1.f, out);
    const bool r2 = ((int)out[O_FLAGS] & F_REJECTED) != 0;
    CHECK(r1 && !r2 && std::fabs(out[O_LM] - .1f) < 1e-4f, "tutarlı (iki kare aynı yerde) sıçrama ikinci karede kabul edildi");
  }

  // 4) Kayıp ve geri gelme: eski konumdan kayarak gelmez
  {
    Kinematics K;
    int64_t t = 0;
    for (int i = 0; i < 10; i++) {
      makeHand(lm, .3f, .6f, .15f, open);
      pack(in, 0, .9f, false, lm);
      t += 16 * MS;
      K.process(in, 1, t, 1.f, out);
    }
    t += 500 * MS;  // el 500 ms görülmedi
    makeHand(lm, .7f, .5f, .15f, open);
    pack(in, 0, .9f, false, lm);
    K.process(in, 1, t, 1.f, out);
    CHECK(((int)out[O_FLAGS] & F_REACQUIRED) != 0, "kayıptan sonra yeniden bulundu bayrağı");
    CHECK(std::fabs(out[O_LM] - .7f) < 1e-4f, "yeniden bulunan el doğrudan yeni konumda (x=%.3f)", out[O_LM]);
  }

  // 5) İki el: yuvalar el yer değiştirse de korunur
  {
    Kinematics K;
    K.cfg.filter = false;
    int64_t t = 0;
    float a[kLm * 3], b[kLm * 3];
    makeHand(a, .25f, .6f, .14f, open);
    makeHand(b, .75f, .6f, .14f, fist);
    pack(in, 0, .9f, false, a);
    pack(in, 1, .9f, true, b);
    t += 16 * MS;
    K.process(in, 2, t, 1.f, out);
    const int sa = (int)out[O_SLOT], sb = (int)out[O_STRIDE + O_SLOT];
    // sıralama değişti (MediaPipe sırayı garanti etmez)
    makeHand(a, .26f, .6f, .14f, open);
    makeHand(b, .74f, .6f, .14f, fist);
    pack(in, 0, .9f, true, b);
    pack(in, 1, .9f, false, a);
    t += 16 * MS;
    K.process(in, 2, t, 1.f, out);
    CHECK((int)out[O_SLOT] == sb && (int)out[O_STRIDE + O_SLOT] == sa && sa != sb, "iki el, sıra değişince de aynı yuvada kaldı");
    CHECK(((int)out[O_FLAGS] & F_FIST) && !((int)out[O_STRIDE + O_FLAGS] & F_FIST), "sağ el yumruk, sol el açık birbirine karışmadı");
  }

  // 6) Sağlamlık: NaN girdi atlanır, kısmen kadraj dışı el güveni düşer
  {
    Kinematics K;
    makeHand(lm, .5f, .5f, .15f, open);
    lm[10] = NAN;
    pack(in, 0, .9f, true, lm);
    int n = K.process(in, 1, 1 * MS, 1.f, out);
    CHECK(n == 0, "NaN içeren el atlandı");
    makeHand(lm, .05f, .5f, .2f, open);  // sol kenardan taşan el
    pack(in, 0, .9f, true, lm);
    K.process(in, 1, 2 * MS, 1.f, out);
    CHECK(((int)out[O_FLAGS] & F_PARTIAL) && out[O_CONF] < 0.9f, "kadraj dışı el: kısmi bayrağı, güven %.2f", out[O_CONF]);
    makeHand(lm, .5f, .5f, .03f, open);  // çok uzak el
    Kinematics K3;
    pack(in, 0, .9f, true, lm);
    K3.process(in, 1, 2 * MS, 1.f, out);
    CHECK(((int)out[O_FLAGS] & F_FAR) && out[O_CONF] < 0.6f, "uzak el: uzak bayrağı, güven %.2f", out[O_CONF]);
  }

  // 7) Hız ölçümü (performans): 2 el × 10000 kare
  {
    Kinematics K;
    float a[kLm * 3], b[kLm * 3];
    int64_t t = 0;
    timespec t0{}, t1{};
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < 10000; i++) {
      makeHand(a, .3f + 0.0001f * (i % 100), .6f, .14f, open);
      makeHand(b, .7f, .6f, .14f, fist);
      pack(in, 0, .9f, false, a);
      pack(in, 1, .9f, true, b);
      t += 16 * MS;
      K.process(in, 2, t, 1.33f, out);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    const double us = ((t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec)) / 1e3 / 10000;
    CHECK(us < 50, "kare başına iki el işleme süresi %.2f µs (sentetik veri üretimi dahil)", us);
  }

  std::printf("\n%d geçti, %d başarısız\n", passes, fails);
  return fails ? 1 : 0;
}
