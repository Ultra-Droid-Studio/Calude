// Stage 62: el süzgeci (ölü bölgeli One Euro) + çizim yumuşatma — simülasyonla ölçülür.
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
const {run,motions}=require('./handsim.js');
let f=0;const ok=(n,c)=>{console.log((c?'PASS ':'FAIL ')+n);if(!c)f++};
const OLD={mc:3,beta:9,mcL:4.8,betaL:9,g:1,tau:.011};
const NEW={mc:1.4,beta:10,dc:2,dz:.8,mcL:1.4,betaL:10,dcL:2,dzL:.8,g:1,tau:.018,comp:9};
const sc=(P,mo,ih,rh,sg)=>run(P,{infHz:ih,renderHz:rh,motion:mo,sigma:sg,lat:45});
let sO=0,sN=0,jO=0,jN=0,lO=0,lN=0,n=0;
for(const [ih,rh] of [[30,60],[30,120],[45,60]])for(const sg of [.003,.004,.006]){n++;
  sO+=sc(OLD,motions.still,ih,rh,sg).jit;sN+=sc(NEW,motions.still,ih,rh,sg).jit;
  jO+=sc(OLD,motions.cross,ih,rh,sg).judder;jN+=sc(NEW,motions.cross,ih,rh,sg).judder;
  lO+=sc(OLD,motions.swing,ih,rh,sg).lag;lN+=sc(NEW,motions.swing,ih,rh,sg).lag}
console.log(`duran el titremesi ${(sO/n).toFixed(2)} → ${(sN/n).toFixed(2)} px; süpürme judder ${(jO/n).toFixed(2)} → ${(jN/n).toFixed(2)}; salınım gecikmesi ${(lO/n).toFixed(0)} → ${(lN/n).toFixed(0)} ms`);
ok('duran el titremesi en az %45 azaldı',sN<sO*.55);
ok('süpürme judder\'ı azaldı',jN<jO*.9);
ok('hızlı harekette gecikme artışı ≤ 6 ms',(lN-lO)/n<=6);
ok('index.html: OE ölü bölge parametresi',/constructor\(mc,b,dc,dz\)/.test(html)&&/Math\.max\(0,Math\.abs\(this\.dx\)-this\.dz\)/.test(html));
ok('index.html: Turbo çizim süzgeci 18 ms (pinli 7 ms) + 9 ms tahmin',/pin\?\.007:\.018/.test(html)&&/const ag=pin\?age:age\+9/.test(html));
const nc=fs.readFileSync(path.join(__dirname,'../app/src/main/java/com/nexus/vr/NativeCam.java'),'utf8');
ok('NativeCam: uyarlanır kare aralığı (16 ms ... 33/25 ms) + termal denetim',/long analysisGap\(long nowMs\)/.test(nc)&&/Math\.max\(16L, Math\.min\(base, g\)\)/.test(nc)&&/getCurrentThermalStatus/.test(nc)&&/final long minGap = analysisGap\(nowMs\)/.test(nc));
ok('NativeCam: çıkarım süresi EMA\'sı güncelleniyor',/infEma \+= \(inf - infEma\) \* 0\.2f/.test(nc));
console.log(f?('\n'+f+' BAŞARISIZ'):'\nTÜMÜ GEÇTİ');process.exit(f?1:0);
