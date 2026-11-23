/* Tarayıcı testi: index.html içindeki BR nesnesini ve tarayıcı panelini çıkarıp sahte ortamda çalıştırır.
   Çalıştır: node tools/browser.test.js */
const fs=require('fs'),path=require('path'),assert=require('assert');
const html=fs.readFileSync(path.join(__dirname,'..','app/src/main/assets/index.html'),'utf8');
const cut=(a,b)=>{const i=html.indexOf(a),j=html.indexOf(b,i);assert(i>=0&&j>i,'bulunamadı: '+a);return html.slice(i,j)};
const brSrc=cut('  const BR={\n    show:false,','  const AC=[');
const panelSrc=cut("  browser:()=>({\n    id:'browser',","  settings:()=>({\n    id:'settings',");
let pass=0;const ok=(c,m)=>{assert(c,m);pass++};

function env(){
  const calls=[],toasts=[];
  const store={v:{}};
  const E={
    Settings:{v:store.v,save(){E.saves++}},saves:0,
    Diag:{toast:m=>toasts.push(m),log(){}},
    BF:{hide(){E.hides++},load(u){E.loads.push(u)}},hides:0,loads:[],
    XR:{session:null},Hand:{on:false},WM:{panels:[],paint(){}},KBD:{ask(){}},
    NX_T:'tok',
    window:{AndroidBridge:{setDesktopMode:(...a)=>calls.push(['desk',...a]),setAdBlock:(...a)=>calls.push(['adb',...a])}},
    calls,toasts
  };
  const f=new Function('E',`
    const {Settings,Diag,BF,XR,Hand,WM,KBD,NX_T,window}=E;
    const AndroidBridge=new Proxy({},{get:(t,k)=>{const b=window.AndroidBridge;if(!b)throw new ReferenceError('AndroidBridge');return b[k]}});
    ${brSrc}
    return BR;`);
  E.BR=f(E);
  return E;
}

/* --- norm: eski güvenlik davranışı korunmuş --- */
{
  const {BR}=env();
  ok(BR.norm('http://example.com').url.startsWith('https://'),'http->https');
  ok(BR.norm('http://localhost:3000').err,'localhost engelli');
  ok(BR.norm('file:///etc/passwd').err,'file engelli');
  ok(BR.norm('merhaba dünya').url.includes('search?q='),'arama');
}
/* --- geçmiş --- */
{
  const E=env(),{BR,Settings}=E;
  BR.go('https://a.com');BR.go('https://a.com');BR.go('https://b.com');
  ok(Settings.v.hist.length===2&&Settings.v.hist[0].u==='https://b.com/','geçmiş yinelenen ardışık kaydı atlar, yeni önce');
  ok(Settings.v.hist[0].t==='b.com','geçmiş başlığı alan adı');
  for(let i=0;i<150;i++)BR.go('https://s'+i+'.com');
  ok(Settings.v.hist.length===100,'geçmiş 100 ile sınırlı');
  BR.delHist(Settings.v.hist[0].u);ok(Settings.v.hist.length===99,'geçmişten tek silme');
  BR.clearHist();ok(Settings.v.hist.length===0,'geçmişi temizle');
  BR.step(-1);ok(Settings.v.hist.length===0,'geri gitmek geçmişe eklemez');
}
/* --- yer imleri --- */
{
  const {BR,Settings}=env();
  Settings.v.bm=[];for(let i=0;i<20;i++)Settings.v.bm.push('https://x'+i+'.com/');
  ok(Settings.v.bm.length===20,'8 sınırı yok');
  BR.delBm('https://x3.com/');ok(Settings.v.bm.length===19&&!Settings.v.bm.includes('https://x3.com/'),'yer imi sil');
}
/* --- sekmeler --- */
{
  const E=env(),{BR}=E;
  BR.go('https://a.com');BR.go('https://a2.com');
  BR.newTab();ok(BR.tabs.length===2&&BR.t===1&&BR.hist.length===0&&!BR.show,'yeni sekme boş');
  BR.go('https://b.com');
  BR.sw(0);ok(BR.t===0&&BR.hist.length===2&&BR.hist[BR.i]==='https://a2.com/'&&BR.show,'sekme 0 geçmişi korunur ve yeniden yüklenir');
  ok(E.loads[E.loads.length-1]==='https://a2.com/','sekme değişince sayfa yüklendi');
  BR.sw(1);ok(BR.hist[BR.i]==='https://b.com/','sekme 1 geçmişi korunur');
  for(let i=0;i<6;i++)BR.newTab();
  ok(BR.tabs.length===5,'en çok 5 sekme');
  BR.closeTab(4);ok(BR.tabs.length===4&&BR.t<4,'son sekme kapatılınca indeks geçerli');
  const before=BR.hist;BR.t=3;BR.closeTab(0);ok(BR.t===2,'önceki sekme kapanınca etkin indeks kayar');
  while(BR.tabs.length>1)BR.closeTab(0);
  BR.closeTab(0);ok(BR.tabs.length===1&&BR.hist.length===0&&!BR.show,'tek sekme kapatılınca sıfırlanır');
}
/* --- PC sürümü + reklam engelleyici --- */
{
  const E=env(),{BR,Settings,calls}=E;
  BR.setDesk(true);ok(Settings.v.desk===true,'desk kaydedildi');
  ok(calls.some(c=>c[0]==='desk'&&c[1]==='nexus-browser'&&c[2]===true&&c[3]==='tok'),'setDesktopMode köprüye gitti');
  BR.setAdb(true);ok(calls.some(c=>c[0]==='adb'&&c[1]===true&&c[2]==='tok'),'setAdBlock köprüye gitti');
  BR.go('https://a.com');calls.length=0;BR.setDesk(false);
  ok(E.loads[E.loads.length-1]==='https://a.com/','PC sürümü değişince sayfa yeniden yüklenir');
  E.window.AndroidBridge={};   // eski APK: yöntemler yok
  BR.setAdb(false);ok(true,'eski APK köprüsünde çökmez');
  E.window.AndroidBridge=null;BR.setDesk(true);ok(true,'köprü yokken çökmez');
}
/* --- çizim: tüm durumlar --- */
function renderEnv(){
  const E=env();
  const ACC=['#19d3c5'];
  const SITES=[['A','https://a.com','A','#fff','#000'],['B','https://b.com','B','#fff','#000'],['C','https://c.com','C','#fff','#000'],['D','https://d.com','D','#fff','#000'],['E','https://e.com','E','#fff','#000'],['F','https://f.com','F','#fff','#000'],['G','https://g.com','G','#fff','#000'],['H','https://h.com','H','#fff','#000']];
  const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
  const ctx=new Proxy({},{get:(t,k)=>k==='measureText'?(s=>({width:String(s).length*9})):k==='createLinearGradient'?(()=>({addColorStop(){}})):(typeof t[k]==='undefined'?()=>{}:t[k]),set:(t,k,v)=>{t[k]=v;return true}});
  const f=new Function('E','ACC','SITES','clamp','ctx',`
    const {Settings,Diag,BF,XR,Hand,WM,KBD,NX_T,window,BR}=E;
    const drawGK=()=>{},drawLockK=()=>{},starK=()=>{},iconK=()=>{};
    const rr=()=>{},txt=(c,s,x,y)=>{if(!isFinite(x)||!isFinite(y))throw new Error('NaN txt '+s)},ICN=()=>{},card=()=>{};
    const qbtn=(c,B,cx,cy,ic,fn,nm)=>B(cx-22,cy-22,44,44,'',fn,false,null,'raw',nm);
    const P={${panelSrc}};
    return P.browser();`);
  E.panel=f(E,ACC,SITES,clamp,ctx);E.ctx=ctx;return E;
}
function draw(E,W=1024,H=610){
  const btns=[];
  const B=(x,y,w,h,l,fn,on,ic,kind,nm)=>{
    for(const v of [x,y,w,h])assert(Number.isFinite(v),'B sayısal değil: '+nm);
    btns.push({x,y,w,h,fn,nm:nm||l});return false};
  E.panel.render(E.ctx,W,H,B);return btns;
}
const inside=(b,W,H)=>b.x>=0&&b.y>=0&&b.x+b.w<=W+0.5&&b.y+b.h<=H+0.5&&b.w>0&&b.h>0;
const overlap=(a,b)=>a.x<b.x+b.w&&b.x<a.x+a.w&&a.y<b.y+b.h&&b.y<a.y+a.h;
{
  const E=renderEnv(),{BR,Settings}=E;
  Settings.v.bm=[];Settings.v.hist=[];
  for(let i=0;i<23;i++){Settings.v.bm.push('https://bm'+i+'.example.com/yol');}
  for(let i=0;i<60;i++)BR.addHist('https://h'+i+'.example.com/');
  /* başlangıç: üç görünüm, tüm sayfalar */
  for(const view of [0,1,2,3,4]){
    BR.view=view;
    for(let pg=0;pg<5;pg++){
      BR.pg=pg;const bs=draw(E);
      ok(bs.every(b=>inside(b,1024,610)),`görünüm ${view} sayfa ${pg}: düğmeler pencere içinde`);
      /* üst çubuk dışındaki düğmeler birbirini örtmez (kart + sil düğmesi hariç) */
      const si=bs.findIndex(b=>b.nm==='Pencereyi kapat');
      const body=(si>=0?bs.slice(si+1):bs).filter(b=>b.y>=124&&b.nm!=='Pencere');
      for(let i=0;i<body.length;i++)for(let j=i+1;j<body.length;j++)
        assert(!overlap(body[i],body[j]),`çakışma: ${body[i].nm} / ${body[j].nm} (görünüm ${view})`);
    }
  }
  ok(true,'yeni sekme sayfası ve pencereleri: çakışma yok');
  /* silme düğmesi kartın üstünde değil yanında */
  BR.view=1;BR.pg=0;const bs1=draw(E);
  const del=bs1.find(b=>b.nm==='Yer imini sil'),cardB=bs1.find(b=>b.nm==='bm0.example.com');
  ok(del&&cardB&&!overlap(del,cardB),'sil düğmesi kartla çakışmaz');
  del.fn();ok(Settings.v.bm.length===22&&Settings.v.bm[0]==='https://bm1.example.com/yol','sil düğmesi yer imini kaldırır');
  BR.view=2;const bh=draw(E);
  ok(bh.some(b=>b.nm==='Geçmişi temizle'),'geçmiş temizle düğmesi var');
  bh.find(b=>b.nm==='Geçmişi temizle').fn();ok(Settings.v.hist.length===0,'temizle çalışır');
  const empty=draw(E);ok(empty.every(b=>inside(b,1024,610)),'boş geçmiş çiziliyor');
}
{
  /* Ayarlar görünümü: anahtarlar çalışır; arama çubuğu adres sorar */
  const E=renderEnv(),{BR,Settings}=E;
  let asked=0;E.KBD.ask=()=>asked++;
  BR.view=3;const bs=draw(E);
  ok(bs.every(b=>inside(b,1024,610)),'tercihler penceresi içinde');
  bs.find(b=>b.nm==='Masaüstü sitesi anahtarı').fn();ok(Settings.v.desk===true,'tercihlerden masaüstü sitesi');
  bs.find(b=>b.nm==='Reklam engelleme anahtarı').fn();ok(Settings.v.adb===true,'tercihlerden reklam engelleme');
  bs.find(b=>b.nm==='Adres çubuğunu aç').fn();ok(asked===1&&BR.view===0,'tercihlerden adres çubuğu klavyesi');
  BR.view=0;const b0=draw(E);
  ok(b0.some(b=>b.nm==='Ara veya adres yaz'),'arama alanı düğmesi var');
  ok(['Yer imleri','Geçmiş','Tercihler'].every(n=>b0.some(b=>b.nm===n)),'3 kutucuk (yer imleri, geçmiş, tercihler)');
  ok(['YouTube','Wikipedia','Twitch','GitHub','Moon Rider','Kısayol ekle'].every(n=>b0.some(b=>b.nm===n)),'varsayılan kısayollar + ekle');
  /* kısayol ekle / sil */
  E.KBD.ask=(q,v,cb)=>cb('example.com');BR.addPin();
  ok(Settings.v.bpins&&Settings.v.bpins.some(p=>p.u==='https://example.com/'&&p.t==='example.com'),'kısayol eklendi');
  BR.delPin('https://example.com/');ok(!BR.pins().some(p=>p.u==='https://example.com/')&&BR.pins().length===5,'kısayol silindi');
  E.KBD.ask=(q,v,cb)=>cb('merhaba dünya');BR.addPin();ok(BR.pins().length===5,'boşluklu metin kısayol olmaz');
  /* sayfa açılınca pencere kapanır */
  BR.view=2;BR.go('https://site.com');ok(BR.view===0,'siteye gidince pencere kapanır');
}
{
  /* 1..5 sekme: şerit düğmeleri çakışmaz, sığar */
  const E=renderEnv(),{BR}=E;
  for(let n=1;n<=5;n++){
    while(BR.tabs.length<n)BR.newTab();
    BR.sw(0);const bs=draw(E);
    const strip=bs.filter(b=>b.y<56);
    ok(strip.every(b=>inside(b,1024,610)),`${n} sekme: şerit sığar`);
    for(let i=0;i<strip.length;i++)for(let j=i+1;j<strip.length;j++)
      assert(!overlap(strip[i],strip[j]),`${n} sekme: şerit çakışması ${strip[i].nm}/${strip[j].nm}`);
    ok(strip.filter(b=>b.nm==='Sekmeyi kapat').length===n,`${n} sekme: her sekmede kapat`);
    ok(strip.some(b=>b.nm==='Yeni sekme')===(n<5),`${n} sekme: artı düğmesi ${n<5?'var':'yok'}`);
  }
}
{
  /* menü: scrim önce, satırlar sonra (son çizilen düğme önceliklidir), anahtarlar çalışır */
  const E=renderEnv(),{BR,Settings}=E;
  BR.menu=true;const bs=draw(E);
  const si=bs.findIndex(b=>b.nm==='Menüyü kapat'),first=bs.findIndex(b=>b.nm==='PC sürümü');
  ok(si>=0&&first>si,'scrim menü satırlarından önce');
  ok(bs.slice(first).every(b=>inside(b,1024,610)),'menü satırları pencere içinde');
  const rows=bs.slice(first);
  for(let i=0;i<rows.length;i++)for(let j=i+1;j<rows.length;j++)assert(!overlap(rows[i],rows[j]),'menü satır çakışması');
  rows.find(b=>b.nm==='PC sürümü').fn();ok(Settings.v.desk===true,'menüden PC sürümü');
  rows.find(b=>b.nm==='Reklam engelleyici').fn();ok(Settings.v.adb===true,'menüden reklam engelleyici');
  rows.find(b=>b.nm==='Yer imleri').fn();ok(BR.view===1&&!BR.menu,'menüden yer imleri görünümü');
  BR.menu=true;BR.go('https://site.com');BR.menu=true;
  const bs2=draw(E);ok(bs2.some(b=>b.nm==='Tarayıcıda aç'),'sayfa açıkken menüde dış tarayıcı');
  ok(bs2.filter(b=>b.nm==='Menüyü kapat').length===1,'tek scrim');
  /* sayfa açık, menü kapalı */
  BR.menu=false;const bs3=draw(E);ok(BR.rect&&BR.rect.w>0,'sayfa alanı belirlendi');
  ok(bs3.every(b=>inside(b,1024,610)),'sayfa görünümü pencere içinde');
}
console.log('browser.test.js: '+pass+' kontrol geçti');
process.exit(0); /* Stage 74: test edilen kodun kurduğu zamanlayıcılar Node'u açık tutuyordu (CI'da zaman aşımı) */
