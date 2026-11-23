/* Stage 32 — App Store: katalog (40), bölümler, çizim, düğmeler, indirme, ilk açılışta site ikonu (Node, sahte canvas) */
const fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
const java=fs.readFileSync(path.join(__dirname,'../app/src/main/java/com/nexus/vr/MainActivity.java'),'utf8');
let ok=0;const bad=[];
const chk=(n,c)=>{if(c)ok++;else bad.push(n)};
const cut=(a,b)=>{const i=html.indexOf(a),j=html.indexOf(b,i);if(i<0||j<0)throw new Error('blok yok: '+a);return html.slice(i,j)};

const code=[
  cut('  const ICO={m:{}','  const IOSI=(()=>{'),
  cut('  const IOSI=(()=>{','  /* ---------- Web uygulaması kataloğu'),
  cut('  const CAT_GROUPS=','  const WebApps={'),
  cut('  const WebApps={','  const BF={'),
  cut('  const STORE={','  /* ---------- Uygulamalar ---------- */')
].join('\n');

/* sahte ortam */
function ctx(){
  const st={depth:0,min:0,nan:false,n:0};
  const grad={addColorStop(){}};
  return new Proxy({},{get(t,k){
    if(k==='__st')return st;
    if(k==='save')return()=>{st.depth++};
    if(k==='restore')return()=>{st.depth--;st.min=Math.min(st.min,st.depth)};
    if(/^create(Linear|Radial)Gradient$/.test(k))return()=>grad;
    if(k==='measureText')return s=>({width:String(s).length*9});
    if(k in t)return t[k];
    return(...a)=>{st.n++;for(const v of a)if(typeof v==='number'&&!isFinite(v))st.nan=true}
  },set(t,k,v){t[k]=v;return true}});
}
const store={};const toasts=[];const saved={};
const panels=[];
const sb={
  console,Math,Array,String,Object,Date,JSON,URL,RegExp,Number,Set,Map,
  rr(){},ICN(){},card(){},txt(){},clamp:(v,a,b)=>Math.max(a,Math.min(b,v)),
  TB:18,ACC:['#2f7bff'],AC:[['#f00','#00f']],Settings:{v:{acc:0}},
  XR:{session:null},Diag:{toast:(m)=>toasts.push(m)},KBD:{ask(t,d,cb){sb.__kbd=cb}},
  WM:{panels,paint(){sb.__paints=(sb.__paints||0)+1}},
  NX_T:'tok',performance:{now:()=>sb.__now},
  localStorage:{getItem:k=>store[k]||null,setItem:(k,v)=>{store[k]=v}},
  Image:function(){this.set=0;Object.defineProperty(this,'src',{set(v){this._s=v;setTimeout(()=>this.onload&&this.onload(),0)},get(){return this._s}})},
  document:{createElement:()=>({width:0,height:0,getContext:()=>({drawImage(){},getImageData:()=>({data:[10,20,30,255]})})})},
  setTimeout,clearTimeout,Date,
  BR:{},module:{},__now:1000
};
sb.window=sb;
const icoCalls=[];
sb.AndroidBridge={fetchIcon:(u,cb,t)=>{icoCalls.push([u,cb,t]);return true}};
vm.createContext(sb);
vm.runInContext(code+';module.exports={STORE,WebApps,CATALOG,CATK,CAT_GROUPS,IOSI,ICO}',sb);
const {STORE,WebApps,CATALOG,CATK,CAT_GROUPS,IOSI}=sb.module.exports;

/* --- katalog --- */
chk('katalog tam 40 uygulama',CATALOG.length===40);
chk('anahtarlar benzersiz',new Set(CATALOG.map(x=>x.k)).size===40);
chk('hepsi https',CATALOG.every(x=>/^https:\/\/[^\s/]+\.[^\s/]+/.test(x.u)));
chk('her uygulamanın grubu geçerli',CATALOG.every(x=>CAT_GROUPS.includes(x.g)));
chk('her bölümde en az 3 uygulama',CAT_GROUPS.every(g=>CATALOG.filter(x=>x.g===g).length>=3));
chk('adlar benzersiz',new Set(CATALOG.map(x=>x.n)).size===40);
chk('harf/renk tam',CATALOG.every(x=>x.gl&&Array.isArray(x.c)&&x.c.length===2));
chk('Popüler listesi katalogda',STORE.POP.every(k=>CATK[k]));

/* --- App Store ikonu: yeni uygulamada, Uygulamalarım'da değil --- */
chk('SYSK: store→appstore',IOSI.SYSK.store==='appstore');
chk('SYSK: lib artık appstore değil',IOSI.SYSK.lib===undefined);
chk('dock sistem listesinde store',/\['store','App Store','grid'\]/.test(html)&&/\['lib','Uygulamalarım','grid'\]/.test(html));
chk('APPS.store tanımlı',/\n  store:\(\)=>STORE\.def\(\),/.test(html));
chk('dock sabitleme geçişi (stoPin)',/Settings\.v\.stoPin/.test(html));

/* --- çizim: her bölüm, sayfa, kimlik --- */
function render(sv,pg,tag){
  const c=ctx(),btns=[];
  const W=1024,H=Math.round(1024*2.6/(3.2*1.2));
  const B=(x,y,w,h,l,fn,on,ic,kind,nm)=>{btns.push({x,y,w,h,fn,nm:nm||l});return false};
  const u={sv,pg};let err=null;
  try{STORE.render(c,W,H,B,u)}catch(e){err=e}
  chk(tag+' çizilir'+(err?' ('+err.message+')':''),!err);
  chk(tag+' save/restore dengeli',c.__st.depth===0&&c.__st.min===0);
  chk(tag+' sayılar sonlu',!c.__st.nan);
  chk(tag+' düğmeler tuval içinde',btns.every(b=>b.x>=0&&b.y>=0&&b.x+b.w<=W+.5&&b.y+b.h<=H+.5&&b.w>0&&b.h>0));
  chk(tag+' düğmelerde NaN yok',btns.every(b=>[b.x,b.y,b.w,b.h].every(isFinite)));
  return {btns,u,W,H};
}
const views=['feat','all','Medya','Google','Sohbet','Üretkenlik','Tasarım','Keşif','mine'];
for(const v of views){
  const r=render(v,0,v);
  chk(v+': sol menüde 9 bölüm düğmesi',r.btns.filter(b=>STORE.views.some(x=>x[1]===b.nm)).length>=9);
}
const all=render('all',0,'all s1'),all4=render('all',3,'all s4'),all9=render('all',99,'all s99 (sınır)');
chk('Tümü: 40 uygulama 4 sayfa',STORE.list('all').length===40&&Math.ceil(40/10)===4);
chk('Tümü sayfa 1: 10 AL düğmesi',all.btns.filter(b=>/^Al: /.test(b.nm)).length===10);
chk('Tümü sayfa 4: 10 AL düğmesi',all4.btns.filter(b=>/^Al: /.test(b.nm)).length===10);
chk('sayfa sınırı kıstırılır',all9.btns.filter(b=>/^Al: /.test(b.nm)).length===10);
chk('bölümlerin toplamı 40',CAT_GROUPS.reduce((n,g)=>n+STORE.list(g).length,0)===40);
{const f=render('feat',0,'feat');const al=f.btns.filter(b=>/^Al: /.test(b.nm)).length;chk('Öne Çıkan: 9 AL (hero+4+4)',al===9)}
chk('Yüklenenler boş: çizilir',render('mine',0,'mine boş').btns.every(b=>!/^Al: |^Aç: /.test(b.nm)));

/* --- indirme akışı --- */
const key='youtube';
chk('başta yüklü değil',!WebApps.has(key));
sb.__now=1000;STORE.get(key);
chk('indirme başladı',STORE.dl[key]===1000);
{const r=render('all',0,'indirirken');chk('indirirken % düğmesi',r.btns.some(b=>b.nm==='İndiriliyor: YouTube'))}
STORE.get(key);chk('çift dokunuş ikinci indirme başlatmaz',Object.keys(STORE.dl).length===1);
/* süre dolunca kur */
sb.__now=1000+STORE.DLMS+10;
const step=()=>new Promise(r=>setTimeout(r,200));
(async()=>{
  await step();
  const a=WebApps.has(key);
  chk('indirme bitince kuruldu',!!a);
  chk('st bayrağı (App Store\'dan)',a&&a.st===1);
  chk('dl temizlendi',STORE.dl[key]===undefined);
  chk('toast: ilk açılışta ikon',toasts.some(t=>/İndirildi: YouTube/.test(t)&&/ikon/.test(t)));
  chk('kalıcı kayıt (nexus.apps)',/youtube/.test(store['nexus.apps']||''));
  chk('kurulunca drawn ikon yok (harf)',IOSI.keyOf(a)===null);
  {const r=render('all',0,'kurulu');chk('kurulu: AÇ düğmesi',r.btns.some(b=>b.nm==='Aç: YouTube'))}
  {const r=render('mine',0,'mine');chk('Yüklenenler: Aç + Sil',r.btns.some(b=>b.nm==='Aç: YouTube')&&r.btns.some(b=>b.nm==='Sil: YouTube'))}

  /* --- ilk açılışta ikon çekme --- */
  chk('henüz ikon çekilmedi',icoCalls.length===0&&!a.ico);
  WebApps.def('app:'+a.id);
  chk('ilk açılışta fetchIcon çağrıldı (site adresi + belirteç)',icoCalls.length===1&&icoCalls[0][0]===a.url&&icoCalls[0][2]==='tok');
  WebApps.def('app:'+a.id);
  chk('ikinci açılışta tekrar çekmez',icoCalls.length===1);
  const cbName=icoCalls[0][1];
  chk('geri çağrı adı geçerli',/^[A-Za-z_$][A-Za-z0-9_$]{0,100}$/.test(cbName)&&typeof sb[cbName]==='function');
  const png='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
  sb[cbName](png);
  chk('ikon kaydedildi',a.ico===png&&/"ico":/.test(store['nexus.apps']));
  chk('geri çağrı temizlendi',sb[cbName]===undefined);
  {const r=render('mine',0,'ikonlu');chk('ikonlu çizim sorunsuz',true)}
  /* kötü veri reddedilir */
  const b=WebApps.addCat('spotify',true);WebApps.def('app:'+b.id);
  const cb2=icoCalls[1][1];sb[cb2]('javascript:alert(1)');
  chk('geçersiz ikon verisi reddedilir',!b.ico);
  const c3=WebApps.addCat('github',true);icoCalls.length=0;sb.AndroidBridge.fetchIcon=()=>false;WebApps.def('app:'+c3.id);
  chk('köprü false dönerse tekrar denenebilir',c3.icoTried===0&&sb['__nxIco'+WebApps.icoSeq]===undefined);
  sb.AndroidBridge.fetchIcon=(u,cb,t)=>{icoCalls.push([u,cb,t]);return true};
  /* http / belirteçsiz */
  const d=WebApps.add({name:'x',type:'url',url:'http://example.com',st:1});icoCalls.length=0;WebApps.def('app:'+d.id);
  chk('http adres için ikon istenmez',icoCalls.length===0);
  /* katalogdan (st yok) çizimli uygulama: ikon çekilmez */
  const e=WebApps.addCat('discord');icoCalls.length=0;WebApps.def('app:'+e.id);
  chk('çizimli (katalog) uygulama için ikon çekilmez',icoCalls.length===0);
  /* ara */
  STORE.q='goo';const sr=STORE.list('q');
  chk('arama: "goo" → Google ürünleri',sr.length>=6&&sr.every(x=>/goo/i.test(x.n+x.g+CATK[x.k].u)));
  chk('arama sayfası çizilir',render('q',0,'arama').btns.length>0);
  STORE.q='zzzz';chk('arama sonucu boş',STORE.list('q').length===0&&render('q',0,'arama boş').btns.length>=9);
  /* kaldır */
  WebApps.remove(a.id);chk('kaldırınca yeniden AL olur',!WebApps.has(key));

  /* --- Java köprüsü --- */
  chk('Java: fetchIcon köprüsü + token',/public boolean fetchIcon\(String url, String callback, String t\)[\s\S]{0,200}tokenOk\(t\)/.test(java));
  chk('Java: yalnızca https',/startsWith\("https:\/\/"\)/.test(java));
  chk('Java: özel ağ engeli (checkTarget) indirmede',/static byte\[\] httpBytes[\s\S]{0,400}checkTarget\(u\)/.test(java)&&/checkTarget\(fin\)/.test(java));
  chk('Java: boyut sınırı',/1_000_000/.test(java)&&/300_000/.test(java));
  chk('Java: geri çağrı adı doğrulanır',/fetchIcon[\s\S]{0,300}callback\.matches\("\[A-Za-z_\$\]/.test(java));

  console.log(bad.length?('BAŞARISIZ ('+bad.length+'): '+bad.join(' | ')):'TAMAM');
  console.log(ok+' kontrol geçti');
  process.exit(bad.length?1:0);
})();
