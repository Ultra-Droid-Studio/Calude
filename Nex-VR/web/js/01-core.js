'use strict';
  const NX_T=window.__NX||'';try{delete window.__NX}catch(e){}

  /* Stage 63 — Cihaz sınıfı (phone/tablet) ve performans seviyesi (tier 0 düşük, 1 orta, 2 yüksek).
     Kaynak Java'daki DeviceProfile (RAM, çekirdek, ABI, Android sürümü, yenileme hızı). Köprü yoksa (masaüstü tarayıcı)
     ekran + navigator.deviceMemory/hardwareConcurrency ile aynı kuralla tahmin edilir. */
  const Dev=(()=>{
    const ssw=Math.min(screen.width,screen.height);
    const d={cls:ssw<600?'phone':'tablet',tier:1,ram:+navigator.deviceMemory||0,cores:+navigator.hardwareConcurrency||4,hz:60,maxHz:60,lowRam:false,arm64:true,sdk:0,java:false,sensor:'',gyroHw:null,android:/Android/i.test(navigator.userAgent)};
    try{
      if(window.AndroidBridge&&NX_T&&AndroidBridge.deviceProfile){
        const j=JSON.parse(AndroidBridge.deviceProfile(NX_T)||'{}');
        if(j&&(j.cls==='phone'||j.cls==='tablet')){d.cls=j.cls;d.ram=+j.ram||0;d.cores=+j.cores||d.cores;d.hz=+j.hz||60;d.maxHz=+j.maxHz||d.hz;d.lowRam=!!j.lowRam;if(Array.isArray(j.hzs))d.hzs=j.hzs.map(Number).filter(x=>x>0);d.arm64=j.arm64!==false;d.sdk=+j.sdk||0;d.java=true;d.sensor=String(j.sensor||'');d.gyroHw=j.gyro===true;if(j.tier>=0&&j.tier<=2)d.tier=j.tier|0}
      }
    }catch(e){}
    if(!d.java){
      /* Java yok: aynı eşikler (deviceMemory 2 üssü olarak yuvarlanır, bu yüzden 6 GB cihaz 4 görünür → orta kalır). */
      if(!d.android)d.tier=2;
      else if((d.ram&&d.ram<=3)||d.cores<=4)d.tier=0;
      else if(d.ram>=8&&d.cores>=8)d.tier=2;
      else d.tier=1
    }
    d.lite=d.android&&d.tier<2;
    d.mobLite=/Android|iPad|Tablet|Mobile/i.test(navigator.userAgent)&&d.tier<2;
    if(!Array.isArray(d.hzs)||!d.hzs.length)d.hzs=[Math.round(d.hz)||60];
    d.phone=d.cls==='phone';
    return d
  })();

  const $=s=>document.querySelector(s);
  const clamp=(v,a,b)=>Math.min(b,Math.max(a,v));
  const THREE_URLS=['three.min.js','https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js','https://cdn.jsdelivr.net/npm/three@0.128.0/build/three.min.js'];
  const loadThree=()=>new Promise(res=>{
    let i=0;
    const next=()=>{
      if(window.THREE)return res(true);
      if(i>=THREE_URLS.length)return res(false);
      const s=document.createElement('script');
      s.src=THREE_URLS[i++];
      s.onload=()=>window.THREE?res(true):next();
      s.onerror=next;
      document.head.appendChild(s)
    };
    next()
    });
  /* MediaPipe yükleyici v2: file:// dahil her ortamda çalışmak için çoklu strateji.
     1) import() ile .mjs  2) <script> ile .cjs (CORS gerektirmez)  3) elle seçilen yerel dosyalar (IndexedDB'de saklanır) */
