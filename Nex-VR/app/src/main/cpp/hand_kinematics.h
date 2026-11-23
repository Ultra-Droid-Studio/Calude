// Nex VR — Stage 74: native el kinematiği (C++17, Android bağımlılığı yok; masaüstünde de derlenip test edilir).
//
// Girdi: MediaPipe HandLandmarker'ın 21 normalize landmark'ı (x,y ∈ [0,1] görüntü; z göreli derinlik).
// Çıktı (el başına): süzülmüş landmark'lar + parmak bükülmeleri + çimdik mesafeleri + parmak açıklıkları +
//                    avuç normali/rotasyonu + hız + güven skoru + durum bayrakları.
//
// Tasarım ilkeleri:
//  * Kare başına bellek ayırma yok (tüm durum sabit boyutlu diziler).
//  * Süzgeç: hıza uyarlanan One-Euro (durgunken titreme süzülür, hızlı harekette kesme frekansı yükselir → gecikme düşer).
//  * Işınlanma reddi: tek karelik, iskelet şeklini bozan sıçramalar reddedilir; tutarlı hızlı hareket (ikinci kare de
//    aynı yerde) hemen kabul edilir ve süzgeç yeni konuma oturtulur (gerçek hızlı hareket yavaşlatılmaz).
//  * Kayıp: el 300 ms görülmezse durum sıfırlanır; geri geldiğinde eski konumdan "kayarak" gelmez, doğrudan yeni konuma oturur.
#pragma once
#include <cstdint>

namespace nx {

constexpr int kLm = 21;                 // landmark sayısı
constexpr int kInStride = 2 + kLm * 3;  // [skor, sağ_mı, x0,y0,z0, ...]
constexpr int kMaxHands = 2;

// Çıktı düzeni (float). Java/JS tarafı bu sırayı kullanır; değiştirirsen HandKin.java ve 13-hand.js'i de güncelle.
enum Out : int {
  O_SLOT = 0,     // takip yuvası (0/1): aynı el kareler boyunca aynı yuvada kalır
  O_FLAGS = 1,    // bayraklar (aşağıda)
  O_CONF = 2,     // 0..1 birleşik güven
  O_SIZE = 3,     // avuç boyu (en-boy düzeltilmiş normalize birim)
  O_CURL = 4,     // 5 parmak bükülmesi 0 (düz) .. 1 (tam bükük): başparmak, işaret, orta, yüzük, serçe
  O_PINCH = 9,    // başparmak ucu → işaret/orta/yüzük/serçe ucu mesafesi / avuç boyu
  O_SPREAD = 13,  // komşu parmak açıklıkları (radyan): başparmak-işaret, işaret-orta, orta-yüzük, yüzük-serçe
  O_NORMAL = 17,  // avuç normali (görüntü uzayı, birim vektör; z<0 kameraya doğru)
  O_QUAT = 20,    // el çerçevesi dönüşü (x,y,z,w): X = serçe→işaret tabanı, Y = bilek→orta parmak tabanı
  O_VEL = 24,     // avuç merkezi hızı: x,y (avuç boyu/sn), z = boyut değişim hızı (1/sn, + = kameraya yaklaşıyor)
  O_LM = 27,      // 63 süzülmüş landmark (girdiyle aynı birimler)
  O_STRIDE = O_LM + kLm * 3
};

enum Flag : int {
  F_VALID = 1,       // geçerli el
  F_REJECTED = 2,    // bu karenin ölçümü ışınlanma/bozuk iskelet sayılıp reddedildi (önceki poz tutuldu)
  F_REACQUIRED = 4,  // el kayıptan sonra yeniden bulundu (süzgeç yeni konuma oturtuldu)
  F_FIST = 8,        // yumruk
  F_OPEN = 16,       // açık el
  F_PINCH = 32,      // başparmak-işaret çimdik (histerezisli)
  F_FAR = 64,        // el kameraya çok uzak (küçük)
  F_PARTIAL = 128,   // landmark'ların bir kısmı görüntü dışında (kısmen kadraj dışı / kapalı)
  F_RIGHT = 256      // sağ el etiketi
};

struct OneEuro {
  float x = 0.f, dx = 0.f;
  bool init = false;
  static float alpha(float cutoff, float dt) {
    const float r = 6.2831853f * cutoff * dt;
    return r / (r + 1.f);
  }
  // k: hızı "avuç boyu/sn" birimine çeviren çarpan; dz: türev ölü bölgesi (ölçüm gürültüsü kesmeyi şişirmesin)
  float filter(float v, float dt, float minCut, float beta, float dCut, float k, float dz) {
    if (!init) { x = v; dx = 0.f; init = true; return v; }
    if (!(dt > 0.f)) return x;
    const float raw = k * (v - x) / dt;
    dx += alpha(dCut, dt) * (raw - dx);
    float sp = dx < 0.f ? -dx : dx;
    sp = sp > dz ? sp - dz : 0.f;
    x += alpha(minCut + beta * sp, dt) * (v - x);
    return x;
  }
  void reset() { init = false; dx = 0.f; }
};

struct Config {
  bool filter = true;     // false: süzgeç yok (ham ölçüm), diğer hesaplar yine yapılır
  float minCut = 1.6f;    // Hz — durgun eldeki kesme (düşük = daha az titreme, biraz daha gecikme)
  float beta = 9.0f;      // hız kazancı (yüksek = hızlı harekette daha az gecikme)
  float dCut = 2.0f;      // türev kesmesi
  float deadZone = 0.8f;  // avuç boyu/sn
  float jumpPalms = 2.6f; // tek karede bu kadar avuç boyu sıçrama + iskelet bozulması = şüpheli
  float lostMs = 300.f;   // bu süre görülmeyen el sıfırlanır
};

struct Slot {
  bool active = false;
  int64_t lastNs = 0;
  float cx = 0.f, cy = 0.f, size = 0.f;       // son kabul edilen avuç merkezi ve boyu
  float vx = 0.f, vy = 0.f, vs = 0.f;         // süzülmüş hız (avuç/sn, 1/sn)
  float bones[20] = {0};                      // son kabul edilen kemik uzunlukları / avuç boyu
  bool pinch = false;
  int rejectRun = 0;
  float pendX = 0.f, pendY = 0.f;             // reddedilen ölçümün merkezi (tutarlılık için)
  float lm[kLm * 3] = {0};                    // son çıktı (süzülmüş)
  OneEuro f[kLm * 3];
  bool right = false;
};

class Kinematics {
 public:
  Config cfg;
  // in: nHands * kInStride float; out: nHands * O_STRIDE float. tNs: yakalama zamanı (monoton ns).
  // aspect: görüntü genişlik/yükseklik (x ve z bu oranla ölçeklenir ki açı/uzaklıklar doğru olsun).
  // Dönen değer: yazılan el sayısı.
  int process(const float* in, int nHands, int64_t tNs, float aspect, float* out);
  void reset();
  // Testler için: yuvaya erişim
  const Slot& slot(int i) const { return slots_[i]; }

 private:
  Slot slots_[kMaxHands];
  int assign_(const float* in, int nHands, float aspect, int64_t tNs, int* slotOf);
  void features_(const float* p, float aspect, bool right, Slot& s, float* o);
};

// Yardımcılar (testlerde de kullanılır)
float fingerCurl(const float* p, int finger, float aspect);
float palmSize(const float* p, float aspect);

}  // namespace nx
