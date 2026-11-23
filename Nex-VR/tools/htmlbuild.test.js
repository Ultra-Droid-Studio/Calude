/* Stage 69 — web/ parçaları ↔ index.html tutarlılığı. node tools/htmlbuild.test.js
   Parçalardan üretilen çıktı index.html / web/dev.html ile BİREBİR aynı olmalı; parçalar tek başına derlenmeli;
   dev sayfasında (global kapsam) isim çakışması ve "tanımdan önce çağrı" riski olmamalı. */
const fs=require('fs'),vm=require('vm'),path=require('path');
const {build}=require('./build-html.js');
const ROOT=path.join(__dirname,'..'),A=path.join(ROOT,'app/src/main/assets');
let ok=0;const bad=[];const chk=(n,c)=>{if(c)ok++;else bad.push(n)};
const b=build();
const idx=fs.readFileSync(path.join(A,'index.html'),'utf8');
const dev=fs.existsSync(path.join(ROOT,'web/dev.html'))?fs.readFileSync(path.join(ROOT,'web/dev.html'),'utf8'):'';

// 1) güncellik
chk('index.html == web/ parçalarından üretilen (değilse: node tools/build-html.js)',idx===b.inline);
chk('web/dev.html güncel',dev===b.dev);

// 2) sözdizimi
let e1=null;try{new vm.Script(b.inline.slice(b.inline.lastIndexOf('<script>\n/* NEXUS'),b.inline.lastIndexOf('</script>')).replace(/^<script>\n/,''))}catch(e){e1=e}
chk('Birleşik ana script derleniyor'+(e1?': '+e1.message:''),!e1);
b.parts.forEach(p=>{let e=null;try{new vm.Script(p.text,{filename:p.file})}catch(x){e=x}chk(p.file+' tek başına derleniyor'+(e?': '+e.message:''),!e)});
let e2=null;try{new vm.Script(fs.readFileSync(path.join(ROOT,'web/head-guard.js'),'utf8'))}catch(e){e2=e}
chk('head-guard.js derleniyor',!e2);
chk('Parça sayısı >= 10',b.parts.length>=10);

// 3) dev (global kapsam) güvenliği
const decl=new Map(),fns=[],destr=[];
b.parts.forEach((p,i)=>p.text.split('\n').forEach((l,k)=>{
  const m=/^  (const|let|var|function|class)\s+([A-Za-z_$][\w$]*)/.exec(l);
  if(m){chk('Çift üst seviye tanım yok: '+m[2],!decl.has(m[2]));decl.set(m[2],p.file);if(m[1]==='function')fns.push([m[2],i])}
  if(/^  (const|let|var)\s*[{\[]/.test(l))destr.push(p.file+':'+(k+1));
}));
chk('Üst seviyede destructuring tanımı yok'+(destr.length?': '+destr.join(','):''),!destr.length);
const RESTRICTED=['window','self','document','location','top','undefined','NaN','Infinity','parent','frames','opener','navigator','history','screen','performance','console','length','name','status','event'];
for(const n of decl.keys())chk('Tarayıcı global adıyla çakışmıyor: '+n,!RESTRICTED.includes(n));
['gorilla-phys.js','gorilla-art.js','gorilla.js'].forEach(f=>{
  const t=fs.readFileSync(path.join(A,f),'utf8');
  for(const n of decl.keys())if(new RegExp('^(?:const|let|var|function|class)\\s+'+n.replace(/\$/g,'\\$')+'\\b','m').test(t))chk(f+' ile çakışma: '+n,false);
});
// fonksiyon bildirimi sonraki parçadaysa, önceki parçaların ÜST SEVİYE satırlarında çağrılmamalı (dev'de hoisting yok)
for(const [f,j] of fns)for(let i=0;i<j;i++){
  const re=new RegExp('^  [^\\s/*][^\\n]*(?<![\\w$.])'+f.replace(/\$/g,'\\$')+'\\s*\\(','m');
  chk('Dev: '+f+'() tanımından önce üst seviyede çağrılmıyor ('+b.parts[i].file+')',!re.test(b.parts[i].text));
}

// 4) dev sayfası: bağlantılar gerçek dosyalara çıkıyor, sırayla
const base=path.join(ROOT,'web'),assets=A;
const srcs=[...dev.matchAll(/(?:src|href)="(\.\.\/\.\.\/\.\.\/\.\.\/web\/[^"]+)"/g)].map(m=>m[1]);
chk('Dev sayfası <base> ile assets klasörünü gösteriyor',/<base href="\.\.\/app\/src\/main\/assets\/">/.test(dev));
chk('Dev sayfası '+(b.parts.length+2)+' web/ dosyasına bağlı',srcs.length===b.parts.length+2);
srcs.forEach(s=>chk('Dev bağlantısı var: '+s,fs.existsSync(path.resolve(assets,s))));
const order=srcs.filter(s=>s.includes('/js/')).map(s=>s.split('/js/')[1]);
chk('Dev sayfasında parçalar sıralı',JSON.stringify(order)===JSON.stringify(b.parts.map(p=>p.file.slice(3))));

// 5) Java tarafı: jeton enjeksiyonu <head> sonrası, yani birleşik dosya şart (dev.html APK'ya girmez)
chk('index.html tek parça: dış <link>/<script src="js/..."> yok',!/(?:src|href)="[^"]*web\//.test(idx));
chk("index.html içinde <head> var (Java jetonu buraya enjekte eder)",idx.includes('<head>'));
chk('APK assets içine web/ parçaları kopyalanmıyor',!fs.existsSync(path.join(A,'js'))&&!fs.existsSync(path.join(A,'style.css')));

console.log(bad.length?'BAŞARISIZ: '+bad.join(' | '):'htmlbuild.test.js: '+ok+' kontrol geçti');
process.exit(bad.length?1:0);
