/* Stage 44 — Native el takibi: mesaj biçimi (NativeCam.onResult → Hand.onNative) ve NHand.msg ayrıştırma testi.
   index.html'deki gerçek onNative/msg kodu kesilip çalıştırılır. */
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
function slice(from,to){const a=html.indexOf(from),b=html.indexOf(to,a);if(a<0||b<0)throw new Error('kod bulunamadı: '+from);return html.slice(a,b)}
const onNativeSrc=slice('onNative(s){','    nativeFailed(msg){').trim().replace(/,\s*$/,'');
const msgSrc=slice('    msg(s){','    opts(w){').trim().replace(/,\s*$/,'');
let fails=0;const ok=(n,v)=>{console.log((v?'PASS ':'FAIL ')+n);if(!v)fails++};

// Java NativeCam.num() birebir
function num(v,scale){if(!isFinite(v))v=0;let n=Math.round(v*scale),neg=n<0;if(neg)n=-n;const ip=Math.floor(n/scale),fp=n%scale,d=scale===10?1:scale===1000?3:4;return (neg?'-':'')+ip+'.'+String(fp).padStart(d,'0')}
ok('num 0.5→0.5000',num(0.5,10000)==='0.5000');
ok('num -0.0123→-0.0123',num(-0.0123,10000)==='-0.0123');
ok('num 1.0004→1.0004',num(1.0004,10000)==='1.0004');
ok('num 12.34→12.3',num(12.34,10)==='12.3');
ok('num 0.98→0.980',num(0.98,1000)==='0.980');

function hand(label,score,off){const a=[label,num(score,1000)];for(let i=0;i<21;i++){a.push(num(.3+off+i*.01,10000),num(-0.1+i*.02,10000),num(-0.0123,10000))}return a.join(',')}
const msg='R|'+num(31.4,10)+'|'+num(8.2,10)+'|2|'+hand('Right',.97,.1)+'|'+hand('Left',.88,.4);

// onNative
const calls=[];
const Hand={ema:10,infN:0,sw:0,status:'',ingest(r,t0,t){calls.push({r,t0,t})}};
const NHand={delegate:'GPU',camFps:60,camSize:'640x480'};
const Diag={toast(){}};const $=()=>null;
let now=1000;const performance={now:()=>now};
const onNative=new Function('Hand','NHand','Diag','$','performance','return {'+onNativeSrc+'}')(Hand,NHand,Diag,$,performance).onNative.bind(Hand);
onNative(msg);
ok('ingest bir kez çağrıldı',calls.length===1);
const c=calls[0];
ok('2 el, 21 nokta',c.r.landmarks.length===2&&c.r.landmarks.every(l=>l.length===21));
ok('etiketler',c.r.handedness[0][0].categoryName==='Right'&&c.r.handedness[1][0].categoryName==='Left');
ok('skor',Math.abs(c.r.handedness[0][0].score-.97)<1e-9);
ok('koordinat',Math.abs(c.r.landmarks[0][3].x-(.4+.03))<1e-9&&Math.abs(c.r.landmarks[0][3].z+.0123)<1e-9);
ok('yakalama zamanı = şimdi - yaş',Math.abs(c.t0-(1000-31.4))<1e-9&&c.t===1000);
onNative('R|10.0|5.0|0');
ok('el yok → boş sonuç ingest edilir',calls.length===2&&calls[1].r.landmarks.length===0);
onNative('R|10.0|5.0|1|Right,0.9,0.1,0.2,0.3');
ok('eksik/bozuk el atılır',calls.length===3&&calls[2].r.landmarks.length===0);
onNative('R|9999|5.0|0');
ok('aşırı yaş 250 ms ile sınırlı',Math.abs(calls[3].t0-(1000-250))<1e-9);

// NHand.msg
let routed=0,failed=null,pend=null;
const H2={on:true,native:true,onNative(){routed++},nativeFailed(m){failed=m}};
const N2=new Function('Hand','return {camFps:0,camSize:"",pend:null,'+msgSrc+'}')(H2);
N2.msg(msg);ok('R mesajı Hand.onNative\'e gider',routed===1);
let res=null;N2.pend={res:v=>res=v,rej:e=>res=new Error(e.message),to:0};
N2.msg('S|ready|GPU');ok('ready → pend çözülür',res==='GPU'&&N2.pend===null);
N2.pend={res:()=>{},rej:e=>res=e,to:0};N2.msg('S|err|kamera izni yok');ok('err → pend reddedilir',res instanceof Error&&/izni/.test(res.message));
N2.msg('S|err|çalışırken hata');ok('bekleyen yokken err → nativeFailed',failed==='çalışırken hata');
N2.msg('S|fps|58|640x480');ok('fps bilgisi',N2.camFps===58&&N2.camSize==='640x480');
N2.msg(42);ok('string olmayan yok sayılır',true);

// ---- Stage 45: T/P zaman damgaları (saat farkı kestirimi) ----
{
  const calls2=[];
  const H3={ema:10,infN:0,sw:0,status:'',ingest(r,t0,t){calls2.push({t0,t})}};
  const on3=new Function('Hand','NHand','Diag','$','performance','return {'+onNativeSrc+'}')(H3,NHand,Diag,$,performance).onNative.bind(H3);
  // Native saati JS saatinden 5000 ms ileride; yakalama→gönderim yaşı 30 ms; aktarım gecikmesi 2 ms (en küçük), bazen 20 ms.
  const OFF=5000;
  const mk=(capJS,delivery,ageNative)=>{const postN=capJS+ageNative+OFF; return {postN,capN:capJS+OFF,recvJS:capJS+ageNative+delivery}};
  const feed=(capJS,delivery)=>{const m=mk(capJS,delivery,30);now=m.recvJS;
    on3('R|30.0|8.0|0|T,'+m.capN.toFixed(1)+'|P,'+m.postN.toFixed(1))};
  feed(100,2);feed(116.7,2);feed(133.4,21);feed(150.1,2);feed(166.8,9);
  const e=calls2.map((c,i)=>c.t0-[100,116.7,133.4,150.1,166.8][i]);
  // Sabit sapma = en küçük aktarım gecikmesi (2 ms, saat farkına karışır); aktarım dalgalanması (2→21 ms) t0'ı oynatmaz.
  ok('t0 titreşimsiz: aktarım dalgalanması (2–21 ms) t0\'ı < 0.3 ms oynatır',Math.max(...e)-Math.min(...e)<.3);
  ok('t0 sapması ≈ en küçük aktarım gecikmesi',e.every(x=>Math.abs(x-2)<.3));
  ok('t0 artan sırada',calls2.every((c,i)=>i===0||c.t0>calls2[i-1].t0));
  // T/P yoksa eski davranış (yaş alanı)
  now=2000;on3('R|20.0|5.0|0');
  ok('T/P yoksa şimdi−yaş',Math.abs(calls2[calls2.length-1].t0-1980)<1e-9);
  // Saat sıçraması: ofset yeniden kurulur, takılmaz
  now=9000;on3('R|30.0|5.0|0|T,'+(9000-30+777777).toFixed(1)+'|P,'+(9000+777777).toFixed(1));
  ok('saat sıçramasında t0 makul (şimdi−~30 ms)',Math.abs(calls2[calls2.length-1].t0-(9000-30))<3);
  // El bloğu varken T/P indeksi doğru okunur
  const c0=calls2.length;now=12000;
  const m2='R|30.0|8.0|1|'+hand('Right',.9,.1)+'|T,'+(12000-31+5000).toFixed(1)+'|P,'+(12000-1+5000).toFixed(1);
  on3(m2);
  ok('1 el + T/P ayrıştırılır',calls2.length===c0+1);
}
// ---- NHand.msg: ack ----
{
  const sent=[];const H4={on:true,native:true,onNative(){}};
  const N4=new Function('Hand','return {camFps:0,camSize:"",pend:null,port:null,'+msgSrc+'}')(H4);
  N4.port={postMessage:v=>sent.push(v)};
  N4.msg(msg);N4.msg(msg);
  ok('her R mesajına ack gider',sent.length===2&&sent[0]==='a');
  N4.msg('S|fps|60|640x480');
  ok('S mesajına ack gitmez',sent.length===2);
  N4.port={postMessage(){throw new Error('x')}};
  let thrown=false;try{N4.msg(msg)}catch(e){thrown=true}
  ok('ack hatası yutulur',!thrown);
}
if(fails){console.log(fails+' başarısız');process.exit(1)}console.log('nativehand.test.js: geçti');
