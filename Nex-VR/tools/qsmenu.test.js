/* Stage 42: Hızlı ayarlar cam açılır menüsü — statik denetim + sahte tuvalle çizim denemesi.  node tools/qsmenu.test.js */
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.join(__dirname,'..'),html=fs.readFileSync(path.join(root,'app/src/main/assets/index.html'),'utf8');
const java=fs.readFileSync(path.join(root,'app/src/main/java/com/nexus/vr/MainActivity.java'),'utf8');
let n=0;const ok=(c,m)=>{assert(c,m);n++;console.log('ok -',m)};

ok(/const sp=B\(x,cy-pH\/2,pw,pH,'',\(\)=>QS\.toggle\(\)/.test(html),'dock saat kapsülü QS.toggle() çağırır (pencere açmaz)');
ok(!/WM\.spawn\('qs'\)/.test(html),"hiçbir yerde WM.spawn('qs') kalmadı");
ok(/else if\(u\.skin!=='qs'&&u\.skin!=='shz'\)/.test(html),"WM.paint 'qs' görünümünde kendi arka planını çizmez");
ok(/if\(QS\.open&&o!==QS\.m&&!\(u\.dock&&QS\.onCap\(h\)\)\)QS\.close\(\)/.test(html),'dışarı dokunma menüyü kapatır, kapsül tekrar açmaz');
ok(/if\(QS\.open\)QS\.close\(\);\s*else if\(Launcher\.open&&!KBD\.open\)/.test(html),'Escape menüyü kapatır');
['sysState','setVolume','setBrightness','setTorch','setKeepOn','setRotationLock','mediaKey','openPanel'].forEach(m=>{
  ok(new RegExp('public \\w+ '+m+'\\(').test(java),'Java köprüsü: '+m);
  ok(new RegExp('call\\(\'?'+m+'|\\\''+m+'\\\'').test(html),'JS çağırır: '+m)
});
ok(/ACCESS_WIFI_STATE/.test(fs.readFileSync(path.join(root,'app/src/main/AndroidManifest.xml'),'utf8')),'manifest: ACCESS_WIFI_STATE');

/* QS bloğunu çıkar ve sahte tuvalle çalıştır */
const a=html.indexOf('const QS={'),b=html.indexOf('/* LOBBY:BEGIN */');
ok(a>0&&b>a,'QS bloğu bulundu');
const src=html.slice(a,b);
const calls=[];
const mkCtx=()=>new Proxy({},{get:(t,k)=>k in t?t[k]:(k==='createLinearGradient'||k==='createRadialGradient'?()=>({addColorStop(){}}):k==='createPattern'?()=>({}):k==='createImageData'?(w,h)=>({data:new Uint8ClampedArray(w*h*4)}):()=>{}),set:(t,k,v)=>(t[k]=v,true)});
global.Path2D=function(){};
global.document={createElement:()=>({width:0,height:0,getContext:()=>mkCtx()})};
const AB={sysState:t=>JSON.stringify({vol:.4,bright:.7,wifi:true,bt:false,air:false,data:true,torch:false,rot:false,keep:true,playing:true}),
  setVolume:(v,t)=>{calls.push(['vol',v]);return true},setBrightness:(v,t)=>{calls.push(['bri',v]);return true},setTorch:(o,t)=>{calls.push(['torch',o]);return true},
  setKeepOn:(o,t)=>{calls.push(['keep',o]);return true},setRotationLock:(o,t)=>{calls.push(['rot',o]);return true},mediaKey:(k,t)=>{calls.push(['media',k]);return true},openPanel:(w,t)=>{calls.push(['panel',w]);return true}};
global.window={AndroidBridge:AB};
const f=new Function('window','AndroidBridge','NX_T','rr','clamp','WM','Launcher','Diag','document','Path2D',src+';return QS');
const WM={panels:[],focused:null,paint(){},repaintAll(){},place(){},focus(){},create(d){return{userData:Object.assign({btns:[],hov:-1},d),visible:true}}};
const QS=f(global.window,AB,'tok',()=>{},(v,a,b)=>Math.min(b,Math.max(a,v)),WM,{open:false,close(){}},{toast(){},say(){},log(){}},global.document,global.Path2D);
QS.pull();ok(QS.S.vol===.4&&QS.S.playing===true&&QS.S.wifi===true,'sysState durumu okundu');
const u={btns:[],hov:-1};
const B=(x,y,w,h,l,fn,on,ic,kind,nm)=>{u.btns.push({x,y,w,h,fn,n:nm});return false};
QS.render(mkCtx(),1024,1065,B,u);
ok(u.btns.length===4+1+3+1+1+1+40,'tüm düğmeler kaydedildi ('+u.btns.length+')');
const by=nm=>u.btns.find(b=>b.n===nm);
['Uçak modu','Mobil veri','Wi-Fi','Bluetooth','Ses çıkışı','Önceki','Duraklat','Sonraki','Dönme kilidi','Fener','Ekran zaman aşımı'].forEach(nm=>ok(!!by(nm),'düğme: '+nm));
u.btns.forEach(b=>assert(b.x>=0&&b.y>=0&&b.x+b.w<=1024&&b.y+b.h<=1065,'sınır dışı: '+b.n));ok(true,'tüm tıklama alanları tuval içinde');
/* kaydırıcı: üst dilim = %100, alt dilim = %0 */
const sl=u.btns.filter(b=>/^Ses %/.test(b.n));ok(sl.length===20,'ses kaydırıcısı 20 dilim');
sl[0].fn();sl[19].fn();sl[10].fn();
ok(calls[0][0]==='vol'&&calls[0][1]===1&&calls[1][1]===0,'ses: üst dilim 1, alt dilim 0');
const br=u.btns.filter(b=>/^Parlaklık %/.test(b.n));br[19].fn();ok(calls.find(c=>c[0]==='bri'&&c[1]>=.02),'parlaklık alt sınırı 0.02 (ekran kararmaz)');
by('Fener').fn();by('Dönme kilidi').fn();by('Ekran zaman aşımı').fn();by('Duraklat').fn();by('Sonraki').fn();by('Wi-Fi').fn();by('Bluetooth').fn();by('Uçak modu').fn();by('Mobil veri').fn();by('Ses çıkışı').fn();
['torch','rot','keep','media','panel'].forEach(k=>ok(calls.some(c=>c[0]===k),'köprü çağrısı: '+k));
ok(calls.filter(c=>c[0]==='panel').map(c=>c[1]).sort().join()==='air,bt,data,volume,wifi','sistem panelleri: wifi/bt/air/data/volume');
console.log('\n'+n+' denetim geçti');
