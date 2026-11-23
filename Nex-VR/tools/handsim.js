const OE=require('./handsim-oe.js');
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
function rng(seed){let s=seed>>>0;return()=>{s=(s*1664525+1013904223)>>>0;return s/4294967296}}
function gauss(r){return Math.sqrt(-2*Math.log(r()+1e-12))*Math.cos(2*Math.PI*r())}
/* P: {mc,beta,mcL,betaL,lead...}; model: 'cur' = mevcut Turbo */
function run(P,{infHz,renderHz,motion,sigma,lat,dur=6,seed=7}){
  const r=rng(seed),ik=4; // el boyu ~0.25
  const fx=new OE(P.mc,P.beta,P.dc,P.dz),lf=new OE(P.mcL,P.betaL,P.dcL||P.dc,P.dzL);
  let q=0,lv=0,pst=0,sx=0,evx=0,hasT=false,dsx=0;
  const truth=t=>motion(t);
  const out=[];let nextInf=0,pend=[];
  const dtI=1000/infHz,dtR=1000/renderHz;
  let t=0,fgt=0;
  const samples=[];
  for(t=0;t<dur*1000;t+=0.5){
    // ölçüm üret (yakalama zamanı = t - lat, sonuç t anında gelir, ±2ms titreşim)
    if(t>=nextInf){
      const tc=t-lat+(r()-.5)*3,z=truth(tc)+sigma*gauss(r);
      // ingest/upd
      const t0=t-lat; // Hand.onNative yakalama zamanı (zaman damgası temiz)
      const ox=q;q=lf.f(z,t0,ik);
      const dtv=pst?(t0-pst)/1000:0,okv=dtv>=.004&&dtv<.25;
      if(okv)lv+=((q-ox)/dtv-lv)*.6;else lv=0;
      const nx=fx.f(z,t0,ik);
      if(pst){const dt=Math.max(.004,(t0-pst)/1000);evx=(evx);}
      sx=nx;pst=t0;hasT=true;if(!out.init){dsx=q;out.init=1}
      pend.push(t);
      nextInf+=dtI;
    }
    // render karesi
    if(t>=fgt&&hasT){
      const dt=Math.min(.05,Math.max(.001,(t-(fgt-dtR||t))/1000));
      const age=t-(pst+lat); // ölçüm yaşı: now - s.pst(=t0)... aşağıda düzeltilir
      const ageMs=t-(pst); // s.pst = yakalama zamanı t0 → 'age' zaten yakalamadan beri geçen süre
      const am=ageMs+(P.comp||0);const ah=(am<=90?Math.max(0,am):Math.max(0,180-am))/1000*P.g;
      const a=1-Math.exp(-dtR/1000/P.tau);
      const sp=Math.abs(lv),w=clamp((sp-.04)/.1,0,1);
      const tgt=q+clamp(lv*w*ah,-.12,.12);
      dsx+=(tgt-dsx)*a;
      samples.push([t,dsx]);
      fgt=t+dtR;
    }
  }
  // metrikler
  const S=samples.filter(s=>s[0]>1000);
  // gecikme: dsx(t) ≈ truth(t - d) en küçük hata
  let best=1e9,bd=0;
  for(let d=0;d<=120;d+=1){let e=0;for(const s of S){const z=truth(s[0]-d);e+=(s[1]-z)**2}e=Math.sqrt(e/S.length);if(e<best){best=e;bd=d}}
  // gerçek hata (gecikme telafisiz, doğrudan truth(t))
  let e0=0;for(const s of S){e0+=(s[1]-truth(s[0]))**2}e0=Math.sqrt(e0/S.length);
  // judder: kare başına yer değiştirmenin değişkenliği (hareket varken)
  // judder = görüntülenen ivme ile gerçek (gecikmeli) ivme farkının RMS'i (px/kare²): kare-kare pürüzsüzlük
  let acc=0,n=0;for(let k=2;k<S.length;k++){const a1=S[k][1]-2*S[k-1][1]+S[k-2][1];const z=(truth(S[k][0]-bd)-2*truth(S[k-1][0]-bd)+truth(S[k-2][0]-bd));acc+=(a1-z)**2;n++}
  return{lag:bd,rmsTruth:e0*915,jit:best*915,judder:Math.sqrt(acc/n)*915};
}
const motions={
  still:t=>.5,
  slow:t=>.5+.12*Math.sin(2*Math.PI*.4*t/1000),
  swing:t=>.5+.15*Math.sin(2*Math.PI*1.6*t/1000),
  cross:t=>{const p=((t/1000)%2)/2;return .3+.4*(p<.5?p*2:2-p*2)}, // üçgen süpürme, sabit hız ~0.4/s
};
module.exports={run,motions};
if(require.main===module){
  const CUR={mc:3,beta:9,mcL:4.8,betaL:9,g:1,tau:.011};
  const cases=[[30,60],[30,120],[45,60],[60,120]];
  for(const [ih,rh] of cases){
    console.log(`\n== çıkarım ${ih} Hz, render ${rh} Hz (mevcut Turbo) ==`);
    for(const [n,mo] of Object.entries(motions)){
      const R=run(CUR,{infHz:ih,renderHz:rh,motion:mo,sigma:.004,lat:45});
      console.log(n.padEnd(6),'gecikme',R.lag+'ms','rms(px)',R.rmsTruth.toFixed(1),'titreme/hata(px)',R.jit.toFixed(2),'judder(px)',R.judder.toFixed(2))
    }
  }
}
