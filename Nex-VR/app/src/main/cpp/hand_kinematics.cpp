// Nex VR — Stage 74: native el kinematiği. Açıklama için hand_kinematics.h'e bak.
#include "hand_kinematics.h"

#include <cmath>
#include <cstring>

namespace nx {
namespace {

// Parmak zincirleri: [taban, eklem1, eklem2, uç] (başparmak: CMC, MCP, IP, TIP)
constexpr int kChain[5][4] = {{1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12}, {13, 14, 15, 16}, {17, 18, 19, 20}};
// Kemikler (iskelet tutarlılık denetimi): bilek→taban + parmak içi kemikler
constexpr int kBones[20][2] = {{0, 1},  {1, 2},   {2, 3},   {3, 4},   {0, 5},   {5, 6},   {6, 7},
                               {7, 8},  {0, 9},   {9, 10},  {10, 11}, {11, 12}, {0, 13}, {13, 14},
                               {14, 15}, {15, 16}, {0, 17}, {17, 18}, {18, 19}, {19, 20}};

struct V3 {
  float x, y, z;
};
inline V3 at(const float* p, int i, float a) { return {p[i * 3] * a, p[i * 3 + 1], p[i * 3 + 2] * a}; }
inline V3 sub(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline float dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline float len(V3 a) { return std::sqrt(dot(a, a)); }
inline V3 norm(V3 a) {
  const float l = len(a);
  return l > 1e-9f ? V3{a.x / l, a.y / l, a.z / l} : V3{0.f, 0.f, 0.f};
}
inline float clamp01(float v) { return v < 0.f ? 0.f : v > 1.f ? 1.f : v; }
inline bool finite(float v) { return std::isfinite(v); }

// İki vektör arasındaki açı (radyan), sayısal olarak güvenli
inline float angle(V3 a, V3 b) {
  const float la = len(a), lb = len(b);
  if (la < 1e-9f || lb < 1e-9f) return 0.f;
  float c = dot(a, b) / (la * lb);
  c = c < -1.f ? -1.f : c > 1.f ? 1.f : c;
  return std::acos(c);
}

}  // namespace

float palmSize(const float* p, float a) {
  // z gürültüsü boyutu şişirmesin: boyut yalnızca görüntü düzleminde (x,y) ölçülür.
  // bilek(0)→orta taban(9) ve işaret tabanı(5)→serçe tabanı(17); büyük olan (el yana dönünce biri kısalır)
  const float s1 = std::hypot((p[27] - p[0]) * a, p[28] - p[1]);
  const float s2 = std::hypot((p[15] - p[51]) * a, p[16] - p[52]) * 1.15f;
  return s1 > s2 ? s1 : s2;
}

// Parmak bükülmesi: zincirdeki eklem açılarının toplamı, parmağa özgü üst sınıra bölünür.
// Düz parmak ≈ 0, yumruk ≈ 1. Taban açısı (avuç düzlemi → ilk kemik) da sayılır; böylece MCP'den bükülme de görülür.
float fingerCurl(const float* p, int f, float a) {
  const int* c = kChain[f];
  const V3 w = at(p, 0, a), j0 = at(p, c[0], a), j1 = at(p, c[1], a), j2 = at(p, c[2], a), j3 = at(p, c[3], a);
  float sum = angle(sub(j1, j0), sub(j2, j1)) + angle(sub(j2, j1), sub(j3, j2));
  if (f == 0) {
    // başparmak: CMC→MCP→IP açıları; tam bükülme ~1.6 rad
    sum += 0.5f * angle(sub(j0, w), sub(j1, j0));
    return clamp01((sum - 0.25f) / 1.6f);
  }
  sum += angle(sub(j0, w), sub(j1, j0));  // MCP bükülmesi (bilek→taban doğrusuna göre)
  return clamp01((sum - 0.35f) / 3.6f);
}

void Kinematics::reset() {
  for (auto& s : slots_) {
    s = Slot();
  }
}

// Ölçümleri yuvalara eşle: önce yakınlık (avuç merkezleri), eşitlikte el etiketi.
int Kinematics::assign_(const float* in, int n, float a, int64_t tNs, int* slotOf) {
  float cx[kMaxHands], cy[kMaxHands];
  for (int i = 0; i < n; i++) {
    const float* p = in + i * kInStride + 2;
    cx[i] = (p[0] + p[27]) * 0.5f * a;
    cy[i] = (p[1] + p[28]) * 0.5f;
    slotOf[i] = -1;
  }
  auto cost = [&](int i, int s) -> float {
    const Slot& S = slots_[s];
    const bool right = in[i * kInStride + 1] > 0.5f;
    if (!S.active) return 1e3f + (right == (s == 1) ? 0.f : 1.f);
    const float dtS = (float)((tNs - S.lastNs) * 1e-9);
    const float px = S.cx + S.vx * S.size * (dtS > 0.f && dtS < 0.1f ? dtS : 0.f);
    const float py = S.cy + S.vy * S.size * (dtS > 0.f && dtS < 0.1f ? dtS : 0.f);
    return std::hypot(cx[i] - px, cy[i] - py) + (right == S.right ? 0.f : 0.25f);
  };
  if (n == 1) {
    const float c0 = cost(0, 0), c1 = cost(0, 1);
    slotOf[0] = c0 <= c1 ? 0 : 1;
  } else if (n >= 2) {
    const float straight = cost(0, 0) + cost(1, 1), swapped = cost(0, 1) + cost(1, 0);
    slotOf[0] = straight <= swapped ? 0 : 1;
    slotOf[1] = 1 - slotOf[0];
  }
  return n;
}

void Kinematics::features_(const float* p, float a, bool right, Slot& s, float* o) {
  const float size = palmSize(p, a);
  const float inv = size > 1e-6f ? 1.f / size : 0.f;
  for (int f = 0; f < 5; f++) o[O_CURL + f] = fingerCurl(p, f, a);
  const V3 th = at(p, 4, a);
  for (int f = 1; f < 5; f++) o[O_PINCH + f - 1] = len(sub(at(p, kChain[f][3], a), th)) * inv;
  // Komşu parmak açıklıkları: taban→uç doğrultuları arasındaki açı
  for (int f = 0; f < 4; f++) {
    const V3 d0 = sub(at(p, kChain[f][3], a), at(p, kChain[f][f == 0 ? 1 : 0], a));
    const V3 d1 = sub(at(p, kChain[f + 1][3], a), at(p, kChain[f + 1][0], a));
    o[O_SPREAD + f] = angle(d0, d1);
  }
  // Avuç çerçevesi
  const V3 w = at(p, 0, a), im = at(p, 5, a), mm = at(p, 9, a), pm = at(p, 17, a);
  const V3 yAx = norm(sub(mm, w));
  V3 xAx = sub(im, pm);
  xAx = norm(sub(xAx, V3{yAx.x * dot(xAx, yAx), yAx.y * dot(xAx, yAx), yAx.z * dot(xAx, yAx)}));
  V3 zAx = cross(xAx, yAx);
  // Avuç normali: sağ/sol elde avuç içi yönü ters; normal her zaman avuç İÇİNİN baktığı yön olsun
  V3 n = right ? V3{-zAx.x, -zAx.y, -zAx.z} : zAx;
  o[O_NORMAL] = n.x;
  o[O_NORMAL + 1] = n.y;
  o[O_NORMAL + 2] = n.z;
  // Dönüş matrisi [x y z] → kuaterniyon
  const float m00 = xAx.x, m01 = yAx.x, m02 = zAx.x, m10 = xAx.y, m11 = yAx.y, m12 = zAx.y, m20 = xAx.z, m21 = yAx.z,
              m22 = zAx.z;
  const float tr = m00 + m11 + m22;
  float qx, qy, qz, qw;
  if (tr > 0.f) {
    const float S = std::sqrt(tr + 1.f) * 2.f;
    qw = 0.25f * S;
    qx = (m21 - m12) / S;
    qy = (m02 - m20) / S;
    qz = (m10 - m01) / S;
  } else if (m00 > m11 && m00 > m22) {
    const float S = std::sqrt(1.f + m00 - m11 - m22) * 2.f;
    qw = (m21 - m12) / S;
    qx = 0.25f * S;
    qy = (m01 + m10) / S;
    qz = (m02 + m20) / S;
  } else if (m11 > m22) {
    const float S = std::sqrt(1.f + m11 - m00 - m22) * 2.f;
    qw = (m02 - m20) / S;
    qx = (m01 + m10) / S;
    qy = 0.25f * S;
    qz = (m12 + m21) / S;
  } else {
    const float S = std::sqrt(1.f + m22 - m00 - m11) * 2.f;
    qw = (m10 - m01) / S;
    qx = (m02 + m20) / S;
    qy = (m12 + m21) / S;
    qz = 0.25f * S;
  }
  if (!finite(qx + qy + qz + qw)) { qx = qy = qz = 0.f; qw = 1.f; }
  o[O_QUAT] = qx;
  o[O_QUAT + 1] = qy;
  o[O_QUAT + 2] = qz;
  o[O_QUAT + 3] = qw;

  // Jestler (histerezisli çimdik)
  const float c4 = (o[O_CURL + 1] + o[O_CURL + 2] + o[O_CURL + 3] + o[O_CURL + 4]) * 0.25f;
  const float pd = o[O_PINCH];
  s.pinch = s.pinch ? pd < 0.46f : pd < 0.34f;
  int fl = (int)o[O_FLAGS];
  if (c4 > 0.62f) fl |= F_FIST;
  if (c4 < 0.22f && o[O_CURL] < 0.5f) fl |= F_OPEN;
  if (s.pinch) fl |= F_PINCH;
  o[O_FLAGS] = (float)fl;
}

int Kinematics::process(const float* in, int nHands, int64_t tNs, float aspect, float* out) {
  if (nHands < 0) nHands = 0;
  if (nHands > kMaxHands) nHands = kMaxHands;
  const float a = aspect > 0.1f && aspect < 10.f ? aspect : 1.f;

  // Kayıp yuvaları sıfırla (eski konumdan kayarak gelme olmasın)
  for (auto& s : slots_) {
    if (s.active && (tNs - s.lastNs) * 1e-6 > cfg.lostMs) {
      const bool r = s.right;
      s = Slot();
      s.right = r;
    }
  }
  int slotOf[kMaxHands];
  assign_(in, nHands, a, tNs, slotOf);
  bool used[kMaxHands] = {false, false};

  int written = 0;
  for (int i = 0; i < nHands; i++) {
    const float* src = in + i * kInStride;
    const float score = src[0];
    const bool right = src[1] > 0.5f;
    const float* p = src + 2;
    float* o = out + written * O_STRIDE;
    std::memset(o, 0, sizeof(float) * O_STRIDE);
    int si = slotOf[i];
    if (si < 0 || used[si]) si = used[0] ? 1 : 0;
    used[si] = true;
    Slot& s = slots_[si];

    // Geçersiz sayı denetimi
    bool ok = true;
    for (int k = 0; k < kLm * 3; k++)
      if (!finite(p[k])) { ok = false; break; }
    if (!ok) continue;

    const float size = palmSize(p, a);
    const float cx = (p[0] + p[27]) * 0.5f * a, cy = (p[1] + p[28]) * 0.5f;
    float bones[20];
    const float inv = size > 1e-6f ? 1.f / size : 0.f;
    for (int b = 0; b < 20; b++) bones[b] = len(sub(at(p, kBones[b][1], a), at(p, kBones[b][0], a))) * inv;

    int flags = F_VALID | (right ? F_RIGHT : 0);
    const float dt = s.active ? (float)((tNs - s.lastNs) * 1e-9) : 0.f;

    // İskelet tutarlılığı: kemik oranları bir önceki kabul edilen kareye göre ne kadar bozuldu?
    float shapeErr = 0.f;
    if (s.active) {
      for (int b = 0; b < 20; b++) {
        const float ref = s.bones[b] > 0.05f ? s.bones[b] : 0.05f;
        shapeErr += std::fabs(bones[b] - s.bones[b]) / ref;
      }
      shapeErr /= 20.f;
    }
    // Sıçrama: tahmin edilen konuma göre yenilik (avuç boyu cinsinden)
    bool reject = false;
    if (s.active && dt > 0.f && dt < 0.15f && s.size > 1e-4f) {
      const float px = s.cx + s.vx * s.size * dt, py = s.cy + s.vy * s.size * dt;
      const float innov = std::hypot(cx - px, cy - py) / s.size;
      const float sizeJump = std::fabs(size - s.size) / s.size;
      const bool jump = innov > cfg.jumpPalms || sizeJump > 0.6f;
      if (jump && (shapeErr > 0.35f || sizeJump > 0.6f)) {
        // Tutarlı mı? Önceki reddedilen ölçüm de buradaysa bu gerçek (hızlı) bir harekettir → kabul et.
        const bool consistent = s.rejectRun > 0 && std::hypot(cx - s.pendX, cy - s.pendY) < 0.6f * size;
        if (!consistent && s.rejectRun < 2) reject = true;
      }
    }

    if (reject) {
      s.rejectRun++;
      s.pendX = cx;
      s.pendY = cy;
      flags |= F_REJECTED;
      // Önceki pozu tut; zamanı güncelleme (bir sonraki kare dt'yi doğru ölçsün)
      std::memcpy(o + O_LM, s.lm, sizeof(float) * kLm * 3);
      o[O_SLOT] = (float)si;
      o[O_FLAGS] = (float)flags;
      o[O_SIZE] = s.size;
      o[O_CONF] = score * 0.35f;
      features_(s.lm, a, right, s, o);
      o[O_VEL] = s.vx;
      o[O_VEL + 1] = s.vy;
      o[O_VEL + 2] = s.vs;
      written++;
      continue;
    }

    const bool snap = !s.active || s.rejectRun > 0;
    if (!s.active) flags |= F_REACQUIRED;
    if (snap)
      for (auto& f : s.f) f.reset();
    s.rejectRun = 0;

    // Hız (ham merkez farkı, kısa süzgeç)
    if (s.active && dt > 0.003f && dt < 0.25f && s.size > 1e-4f) {
      const float k = 0.6f;
      s.vx += ((cx - s.cx) / s.size / dt - s.vx) * k;
      s.vy += ((cy - s.cy) / s.size / dt - s.vy) * k;
      s.vs += ((size - s.size) / s.size / dt - s.vs) * k;
    } else {
      s.vx = s.vy = s.vs = 0.f;
    }

    // Uyarlanır süzgeç
    const float kSpeed = size > 1e-4f ? 1.f / size : 1.f;
    for (int k = 0; k < kLm * 3; k++) {
      const float v = p[k];
      // z daha gürültülü: kesme yarıya, beta aynı
      const bool isZ = (k % 3) == 2;
      const float kk = (k % 3) == 0 ? kSpeed * a : kSpeed;
      if (cfg.filter && dt > 0.f && s.f[k].init) {
        s.lm[k] = s.f[k].filter(v, dt, isZ ? cfg.minCut * 0.5f : cfg.minCut, cfg.beta, cfg.dCut, kk, cfg.deadZone);
      } else {  // ilk kare / süzgeç kapalı: ölçüme otur
        s.f[k].x = v;
        s.f[k].dx = 0.f;
        s.f[k].init = true;
        s.lm[k] = v;
      }
    }

    s.active = true;
    s.lastNs = tNs;
    s.cx = cx;
    s.cy = cy;
    s.size = size;
    s.right = right;
    std::memcpy(s.bones, bones, sizeof(bones));

    // Güven: model skoru × iskelet tutarlılığı × kadraj içinde olma × boyut
    int outside = 0;
    for (int k = 0; k < kLm; k++) {
      const float x = p[k * 3], y = p[k * 3 + 1];
      if (x < -0.02f || x > 1.02f || y < -0.02f || y > 1.02f) outside++;
    }
    if (outside > 0) flags |= F_PARTIAL;
    const bool far = size < 0.06f;
    if (far) flags |= F_FAR;
    float conf = clamp01(score);
    conf *= clamp01(1.2f - shapeErr * 1.5f);
    conf *= 1.f - 0.6f * (float)outside / (float)kLm;
    if (far) conf *= clamp01(size / 0.06f);

    o[O_SLOT] = (float)si;
    o[O_FLAGS] = (float)flags;
    o[O_CONF] = clamp01(conf);
    o[O_SIZE] = size;
    std::memcpy(o + O_LM, s.lm, sizeof(float) * kLm * 3);
    features_(s.lm, a, right, s, o);
    o[O_VEL] = s.vx;
    o[O_VEL + 1] = s.vy;
    o[O_VEL + 2] = s.vs;
    written++;
  }
  return written;
}

}  // namespace nx
