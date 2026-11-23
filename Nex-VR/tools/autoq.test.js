// Stage 61: otomatik çözünürlük (Perf.auto) davranış testi — index.html'deki gerçek kodu çalıştırır.
const fs=require('fs'),path=require('path');
const h=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
let f=0;const ok=(n,c)=>{console.log((c?'PASS ':'FAIL ')+n);if(!c)f++};
const a=h.indexOf('    hold:0,lock:0,upAt:-1e9,probe:null,'),b=h.indexOf('  const Renderer={');
const body=h.slice(a,b).replace(/\n  };\s*$/,'');
let now=0;global.performance={now:()=>now};global.document={hidden:false};
const Settings={v:{autoq:true}},XR={session:null},Stereo={on:true},App={cap:()=>0};
const Renderer={r:{},scale:1,phone:()=>true,resize(){Perf.hold=now+1600}};
const Perf=eval('({fps:0,lo:0,hi:0,'+body+'})');
function run(fn,sec){Renderer.scale=1;Perf.hold=Perf.lock=0;Perf.upAt=-1e9;Perf.probe=null;now=0;for(let t=0;t<sec*2;t++){now+=500;Perf.fps=fn(Renderer.scale);Perf.auto()}return Renderer.scale}
ok('GPU darboğazı: çözünürlük düşer (telefon VR tabanı 0.8)',run(s=>Math.min(60,34/(s*s)),40)===0.8);
ok('CPU darboğazı (el takibi): fayda yoksa adım geri alınır, 1.0 kalır',run(()=>25,40)===1);
ok('Sağlıklı fps: dokunulmaz',run(()=>58,20)===1);
ok('Yük kalkınca çözünürlük 1.0\'a geri döner',run(s=>now<20000?Math.min(60,34/(s*s)):60,60)===1);
ok('Renderer.resize: telefon piksel bütçesi + hafif ceza',/budget=\[\.9e6,1\.3e6,1\.9e6\]/.test(h)&&/Hand&&Hand\.on\?\(phone\?\.92:\.78\)/.test(h)&&/\(phone\?\(stereo\?\.9:\.8\):\.55\)/.test(h));
console.log(f?('\n'+f+' BAŞARISIZ'):'\nTÜMÜ GEÇTİ');process.exit(f?1:0);
