/* Stage 43 — Turbo el: ileri tahmin + kısa süzgeç simülasyonu (glide fast dalının birebir matematiği). */
const clamp=(v,a,b)=>Math.min(b,Math.max(a,v));
function run(mode){
  const fps=30,lat=38,vel=1.2; // ekran/sn, ölçüm gecikmesi ms
  let q=0,lv=0,pst=-1e9,pq=0,disp=0,lastRender=0;const errs=[],steps=[];let prev=0;
  const meas=[];for(let t=0;t<2000;t+=1000/fps)meas.push(t);
  let mi=0;
  for(let t=0;t<2000;t+=1000/60){
    while(mi<meas.length&&meas[mi]+lat<=t){ // yeni ölçüm: gerçek konum, yakalama anına ait
      const tc=meas[mi],pos=vel*tc/1000;
      if(mi){const dt=(tc-pst)/1000;lv+=((pos-pq)/dt-lv)*.6}
      pq=pos;q=pos;pst=tc;mi++;
    }
    const dt=Math.min(.05,(t-lastRender)/1000)||.016;lastRender=t;
    let target=q;
    if(mode==='turbo'){const age=t-pst,ah=(age<=90?age:Math.max(0,180-age))/1000*1,w=clamp((Math.abs(lv)-.04)/.1,0,1);target=q+clamp(lv*w*ah,-.12,.12)}
    const a=mode==='turbo'?1-Math.exp(-dt/.011):1;
    disp+=(target-disp)*a;
    if(t>300){errs.push(Math.abs(disp-vel*t/1000));steps.push(Math.abs((disp-prev)));}
    prev=disp;
  }
  const mean=x=>x.reduce((a,b)=>a+b,0)/x.length,sd=x=>{const m=mean(x);return Math.sqrt(mean(x.map(v=>(v-m)**2)))};
  return{err:mean(errs),stepSd:sd(steps),stepMax:Math.max(...steps)};
}
const raw=run('raw'),turbo=run('turbo');
console.log('ham   : konum hatası',raw.err.toFixed(4),' adım sapması',raw.stepSd.toFixed(5));
console.log('turbo : konum hatası',turbo.err.toFixed(4),' adım sapması',turbo.stepSd.toFixed(5));
const ok=[['turbo hata daha düşük',turbo.err<raw.err*.5],['turbo adımlar daha düzgün',turbo.stepSd<raw.stepSd*.5]];
let f=0;for(const[n,v]of ok){console.log((v?'PASS ':'FAIL ')+n);if(!v)f++}
if(f)process.exit(1);console.log('turbo.test.js: geçti');
