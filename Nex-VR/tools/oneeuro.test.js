/* One Euro filtresi testi: index.html içindeki OE sınıfını çıkarıp doğrudan sınar.
   Çalıştır: node tools/oneeuro.test.js
   NOT: bunlar sentetik sinyallerle yapılan Node denemeleridir; gerçek kamera/cihaz davranışı ayrıca denenmelidir. */
const fs=require('fs'),path=require('path'),assert=require('assert');
const html=fs.readFileSync(path.join(__dirname,'..','app/src/main/assets/index.html'),'utf8');
const cut=(a,b)=>{const i=html.indexOf(a),j=html.indexOf(b,i);assert(i>=0&&j>i,'bulunamadı: '+a);return html.slice(i,j)};
const clamp=(v,a,b)=>Math.min(b,Math.max(a,v));
const OE=new Function('clamp',cut('  class OE{','  /* ---------- Kamera tabanlı el takibi')+'\nreturn OE;')(clamp);
/* Karşılaştırma için Stage 20'deki eski sınıf (yalnızca bu testte durur) */
const OEold=new Function('clamp',`class OE{constructor(mc,b){this.mc=mc;this.b=b;this.x=null;this.dx=0;this.t=0}
a(c,dt){const r=6.28318530718*c*Math.max(.001,dt);return r/(r+1)}
f(v,t){if(this.x===null||!Number.isFinite(v)){this.x=v;this.t=t;this.dx=0;return v}
const dt=clamp((t-this.t)/1000,.001,.1);const rawDx=(v-this.x)/dt;const ad=this.a(1.0,dt);this.dx+=ad*(rawDx-this.dx);
const cutoff=Math.max(.8,this.mc+this.b*Math.abs(this.dx));const alpha=this.a(cutoff,dt);this.x+=alpha*(v-this.x);this.t=t;return this.x}
reset(){this.x=null;this.dx=0}}return OE`)(clamp);
let pass=0;const ok=(c,m)=>{assert(c,m);pass++};
const rngOf=seed=>{let s=seed>>>0;const r=()=>{s=(s*1664525+1013904223)>>>0;return s/4294967296};return{r,g:()=>{let u=0;while(!u)u=r();return Math.sqrt(-2*Math.log(u))*Math.cos(2*Math.PI*r())}}};
const MC=[3,2.2,1.6,1.1,.8]; /* Hand.mcut() ile aynı tablo */

/* --- kaynak kontrolü: çağrı yerleri gerçekten yeni imzayı kullanıyor --- */
ok(/fx:fa\?new OE\(1\.4,10,2,\.8\):new OE\(mc,bt\),fy:fa\?new OE\(1\.4,10,2,\.8\):new OE\(mc,bt\)/.test(html),'imleç süzgeçleri (normal 1.2 / anında mod: ölü bölgeli, Stage 62)');
ok(/fa\?new OE\(1\.4,10,2,\.8\):new OE\(mc\*1\.9,bt\)/.test(html),'iskelet süzgeçleri (anında modda ölü bölgeli düşük kesim, Stage 62)');
ok(/s\.fx\.f\(x,t0,ik\),ny=s\.fy\.f\(y,t0,ik\)/.test(html),'imleç el boyu çarpanıyla süzülüyor');
ok(/s\.lf\[i\*2\]\.f\(raw\[i\]\.x,t0,ik\)/.test(html)&&/s\.lf\[i\*2\+1\]\.f\(raw\[i\]\.y,t0,ik\)/.test(html),'iskelet el boyu çarpanıyla süzülüyor');
ok(!/new OE\([^)]*0\.045\)/.test(html),'eski beta kalmadı');

/* --- temel davranış --- */
{
  const f=new OE(1.6,1.2);let y;
  for(let i=0;i<50;i++)y=f.f(.42,i*33,1/.15);
  ok(Math.abs(y-.42)<1e-12,'sabit girdi aynen çıkar');
  ok(f.f(.42,50*33,1/.15)===y||Math.abs(f.f(.42,51*33,1/.15)-.42)<1e-12,'sabit girdide kayma yok');
  const g=new OE(1.6,1.2);ok(g.f(.3,1000,5)===.3,'ilk örnek aynen geçer');
  g.reset();ok(g.x===null&&g.dx===0&&g.t===0,'reset durumu sıfırlar');
  ok(g.f(.9,5000,5)===.9,'reset sonrası ilk örnek yine aynen geçer');
}
/* --- sağlamlık: sayı olmayan girdi süzgeci bozmaz (eski sürüm kalıcı NaN'a düşerdi) --- */
{
  const f=new OE(1.6,1.2),o=new OEold(1.6,.045);
  for(let i=0;i<10;i++){f.f(.5,i*33,6);o.f(.5,i*33)}
  f.f(NaN,10*33,6);o.f(NaN,10*33);
  f.f(Infinity,11*33,6);
  const y=f.f(.5,12*33,6),yo=o.f(.5,12*33);
  ok(Number.isFinite(y)&&Math.abs(y-.5)<1e-9,'NaN/Infinity sonrası süzgeç sağlam');
  ok(!Number.isFinite(yo),'(karşılaştırma) eski sürüm NaN ile kalıcı bozuluyordu');
  const h=new OE(1.6,1.2);h.f(.5,0,6);
  ok(Number.isFinite(h.f(.6,33,NaN))&&Number.isFinite(h.f(.6,66,0))&&Number.isFinite(h.f(.6,99,-3)),'geçersiz k çarpanı 1 sayılır');
  ok(Number.isFinite(h.f(.7,NaN,6))&&Number.isFinite(h.f(.7,Infinity,6)),'geçersiz zaman damgası yok sayılır');
}
/* --- zaman damgası: aynı/geri giden/çok yakın damga durumu bozmaz; büyük boşlukta yeni konuma oturur --- */
{
  const f=new OE(1.6,1.2);f.f(.2,1000,6);const a=f.f(.25,1033,6);
  ok(f.f(.9,1033,6)===a,'aynı damga: çıktı değişmez');
  ok(f.f(.9,1000,6)===a,'geri giden damga: çıktı değişmez');
  ok(f.f(.9,1035,6)===a,'4 ms altı damga: türev patlamaz');
  const b=f.f(.9,1033+300,6);
  ok(b===.9,'250 ms üstü boşlukta (el yeniden bulundu) yeni konuma oturur');
  const c=f.f(.9,1333+33,6);ok(Math.abs(c-.9)<1e-9,'boşluk sonrası sıçrama/yavaş sürünme yok');
}
/* --- çıktı her zaman girdilerin aralığında kalır (dışbükey birleşim): aşım/salınım yok --- */
{
  const R=rngOf(99);const f=new OE(MC[2],1.2);let lo=1e9,hi=-1e9,t=0;
  for(let i=0;i<5000;i++){
    t+=12+R.r()*70; /* düzensiz çıkarım aralığı: 12-82 ms */
    const v=.5+.4*Math.sin(i/40)+R.g()*.01+(R.r()<.01?(R.r()-.5):0); /* ara sıra ani sıçrama */
    lo=Math.min(lo,v);hi=Math.max(hi,v);
    const y=f.f(v,t,1/.15);
    ok(Number.isFinite(y)&&y>=lo-1e-9&&y<=hi+1e-9,'çıktı girdi aralığında, sayı');
  }
}
/* --- ölçümler --- */
const jitter=(make,size,seed)=>{ /* durgun el: gürültü ~ el boyunun %3'ü; çıktı/girdi RMS oranı */
  const R=rngOf(seed),f=make(),k=1/size;let ss=0,n=0;
  for(let i=0;i<1500;i++){const y=f.f(.5+R.g()*.03*size,i*33,k);if(i>60){ss+=(y-.5)**2;n++}}
  return Math.sqrt(ss/n)/(.03*size)};
const lag=(make,size,hs,seed)=>{ /* sabit hızla hareket (el boyu/sn); kararlı durumda gecikme ms */
  const R=rngOf(seed),f=make(),k=1/size,v=hs*size;let sum=0,c=0;
  for(let i=0;i<70;i++){const t=i*33,x=.1+v*t/1000;const y=f.f(x+R.g()*.03*size,t,k);if(i>=40){sum+=x-y;c++}}
  return sum/c/v*1000};
const avg=(fn,N=12)=>{let s=0;for(let i=0;i<N;i++)s+=fn(500+i);return s/N};
{
  const mk=()=>new OE(MC[2],1.2),mkOld=()=>new OEold(MC[2],.045);
  for(const size of [.08,.15,.3]){
    const j=avg(sd=>jitter(mk,size,sd)),jo=avg(sd=>jitter(mkOld,size,sd));
    ok(j<.5,`durgunken titreme bastırılıyor (boy ${size}, oran ${j.toFixed(2)})`);
    ok(j<jo*1.25,`titreme eskisinden en fazla %25 fazla (boy ${size}: yeni ${j.toFixed(2)}, eski ${jo.toFixed(2)})`);
    const l6=avg(sd=>lag(mk,size,6,sd)),l6o=avg(sd=>lag(mkOld,size,6,sd));
    ok(l6<30,`6 el-boyu/sn'de gecikme <30 ms (boy ${size}: ${l6.toFixed(0)} ms)`);
    ok(l6o>70&&l6<l6o/3,`eskiye göre gecikme 3 kattan fazla düştü (boy ${size}: ${l6o.toFixed(0)} -> ${l6.toFixed(0)} ms)`);
    const l2=avg(sd=>lag(mk,size,2,sd));
    ok(l2<45,`2 el-boyu/sn'de gecikme <45 ms (boy ${size}: ${l2.toFixed(0)} ms)`);
  }
  /* ölçek bağımsızlığı: aynı hareket farklı el boyunda aynı gecikmeyi vermeli */
  const a=avg(sd=>lag(mk,.08,6,sd)),b=avg(sd=>lag(mk,.3,6,sd));
  ok(Math.abs(a-b)<8,`ölçek bağımsız: boy .08 ${a.toFixed(0)} ms ~ boy .3 ${b.toFixed(0)} ms`);
  const ao=avg(sd=>lag(mkOld,.08,6,sd)),bo=avg(sd=>lag(mkOld,.3,6,sd));
  console.log(`  (bilgi) 6 el-boyu/sn gecikme: yeni ${a.toFixed(0)}/${b.toFixed(0)} ms, eski ${ao.toFixed(0)}/${bo.toFixed(0)} ms (boy .08/.3)`);
}
/* --- yumuşatma kademeleri tek yönde çalışıyor (1 az süzgeç ... 5 çok süzgeç) --- */
{
  const js=MC.map(mc=>avg(sd=>jitter(()=>new OE(mc,1.2),.15,sd)));
  for(let i=1;i<js.length;i++)ok(js[i]<js[i-1],`kademe ${i+1} kademe ${i}'den daha sakin (${js[i].toFixed(2)} < ${js[i-1].toFixed(2)})`);
  const ls=MC.map(mc=>avg(sd=>lag(()=>new OE(mc,1.2),.15,2,sd)));
  for(let i=1;i<ls.length;i++)ok(ls[i]>=ls[i-1]-1,`kademe ${i+1} gecikmesi ${i}'den az değil`);
}
/* --- iskelet süzgeci (mc*1.9) imleçten daha çevik --- */
{
  const lm=avg(sd=>lag(()=>new OE(MC[2]*1.9,1.2),.15,2,sd)),lc=avg(sd=>lag(()=>new OE(MC[2],1.2),.15,2,sd));
  ok(lm<lc,`iskelet gecikmesi (${lm.toFixed(0)} ms) imleçten (${lc.toFixed(0)} ms) az`);
}
/* --- Hand.upd + Hand.glide zinciri (x ekseni, birebir kopya): hızlı hamlede hedefi aşma ve oturma süresi --- */
function chain(make,k0,lead,{T,size,seed}){
  const R=rngOf(seed),fx=make(),S={sx:.3,psx:.3,pst:0,vx:0,ox:0,dsx:.3,has:false};
  const x0=.3,x1=.7,t0=200,pos=t=>{const u=clamp((t-t0)/T,0,1);return x0+(x1-x0)*(10*u**3-15*u**4+6*u**5)};
  let nextM=0,pt=0,gt=0;const out=[];
  const glide=(t,force)=>{
    if(!force&&t-gt<14)return;
    const dt=Math.min(.08,Math.max(.001,(t-pt)/1000));pt=t;gt=t;
    if(t-S.pst>70)S.vx*=.85;
    const tx=clamp(S.vx*lead/1000,-.035,.035),ka=1-Math.exp(-dt/.03);
    S.ox+=(tx-S.ox)*ka;const a=1-Math.exp(-dt/.013);S.dsx+=(S.sx+S.ox-S.dsx)*a};
  for(let t=0;t<1500;t+=1000/240){
    if(t>=nextM){
      nextM=t+28+R.r()*14;
      const nx=fx.f(pos(t)+R.g()*.03*size,t,k0?1/clamp(size,.05,.6):undefined);
      if(S.pst){const dt=Math.max(.004,(t-S.pst)/1000);S.vx+=((nx-S.psx)/dt-S.vx)*.55}
      S.psx=nx;S.pst=t;S.sx=nx;if(!S.has){S.dsx=nx;S.has=true}
      glide(t,true)}
    if(Math.floor(t/16.67)!==Math.floor((t-4.17)/16.67)&&t>0)glide(t,false);
    out.push([t,pos(t),S.dsx])}
  let over=0,lagMid=0,cm=0,settle=1000;
  for(const [t,p,d] of out){
    if(t>t0+T)over=Math.max(over,d-x1);
    if(t>t0+T*.3&&t<t0+T*.7){lagMid+=p-d;cm++}
    if(settle===1000&&t>t0+T&&Math.abs(d-x1)<.004)settle=t-(t0+T)}
  return{over:over*1080,lag:lagMid/cm*1080,settle}}
{
  const mean=(make,k0,lead,cfg)=>{const r={over:0,lag:0,settle:0},N=24;for(let i=0;i<N;i++){const c=chain(make,k0,lead,{...cfg,seed:3000+i});for(const q in r)r[q]+=c[q]/N}return r};
  for(const T of [250,500,900]){
    const nw=mean(()=>new OE(MC[2],1.2),true,(20*.7+8)*.4,{T,size:.15});   /* ema=20 ms varsayımıyla Hand.lead */
    const od=mean(()=>new OEold(MC[2],.045),false,Math.min(32,Math.max(10,20*.7+8)),{T,size:.15});
    console.log(`  hamle ${T} ms (1080 px ekran, ort. 24 deneme): oturma ${od.settle.toFixed(0)}->${nw.settle.toFixed(0)} ms | ortada geri kalma ${od.lag.toFixed(0)}->${nw.lag.toFixed(0)} px | aşım ${od.over.toFixed(1)}->${nw.over.toFixed(1)} px`);
    ok(nw.settle<od.settle/2,`hamle ${T} ms: oturma ${od.settle.toFixed(0)} -> ${nw.settle.toFixed(0)} ms`);
    ok(nw.lag<od.lag*.75,`hamle ${T} ms: ortada geri kalma ${od.lag.toFixed(0)} -> ${nw.lag.toFixed(0)} px`);
    ok(nw.over<12,`hamle ${T} ms: hedefi aşma ${nw.over.toFixed(1)} px (eski ${od.over.toFixed(1)} px) <12 px`);
  }
}
console.log('One Euro testi: '+pass+' kontrol geçti');
