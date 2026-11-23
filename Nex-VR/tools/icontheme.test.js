/* Stage 30 — iOS ikon teması: çizimler, eşleme, katalog, bağlantılar (Node, sahte canvas) */
const fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
let ok=0;const bad=[];
const chk=(n,c)=>{if(c)ok++;else bad.push(n)};

const i=html.indexOf('  const IOSI=(()=>{'),j=html.indexOf('})();',i)+5;
chk('IOSI bloğu bulundu',i>0&&j>i);
const src=html.slice(i,j);

/* sahte 2D bağlam: her şeyi kaydeder, save/restore dengesini izler */
function ctx(){
  const st={depth:0,min:0,calls:0,ops:{}};
  const grad={addColorStop(){}};
  const c=new Proxy({},{get(t,k){
    if(k==='__st')return st;
    if(k==='save')return()=>{st.depth++;st.calls++};
    if(k==='restore')return()=>{st.depth--;st.min=Math.min(st.min,st.depth);st.calls++};
    if(/^create(Linear|Radial)Gradient$/.test(k))return()=>grad;
    if(k in t)return t[k];
    return(...a)=>{st.ops[k]=(st.ops[k]||0)+1;st.calls++;for(const v of a)if(typeof v==='number'&&!isFinite(v))st.nan=true}
  },set(t,k,v){t[k]=v;return true}});
  return c;
}
const icnCalls=[];
const sandbox={rr(){},ICN(c,n){icnCalls.push(n)},URL,Math,Array,String,module:{}};
vm.createContext(sandbox);
vm.runInContext(src+';module.exports=IOSI',sandbox);
const IOSI=sandbox.module.exports;

const want=['appstore','browser','instagram','discord','android','youtube','github','spotify','whatsapp','soundcloud','wikipedia'];
chk('11 çizim',want.every(k=>IOSI.DR[k])&&Object.keys(IOSI.DR).length===11);
for(const k of want){
  const c=ctx();
  let err=null;
  try{IOSI.tile(c,{k},10,20,96,96);IOSI.tile(c,{k},0,0,260,130)}catch(e){err=e}
  chk(k+' çizilir (hata yok)',!err);
  chk(k+' save/restore dengeli',c.__st.depth===0&&c.__st.min===0);
  chk(k+' sayılar sonlu (NaN yok)',!c.__st.nan);
  chk(k+' bir şey çiziyor',c.__st.calls>20);
}
{ /* çizimsiz: harf ve glif karoları */
  const c=ctx();IOSI.tile(c,{col:['#f00','#00f'],lab:'Fg'},0,0,72,72);
  chk('harf karosu fillText',c.__st.ops.fillText===1&&c.__st.depth===0);
  icnCalls.length=0;const d=ctx();IOSI.tile(d,{col:['#f00','#00f'],ic:'gear'},0,0,72,72);
  chk('glif karosu ICN çağırır',icnCalls[0]==='gear'&&d.__st.depth===0);
  const e=ctx();IOSI.tile(e,{col:'#123456',lab:'A'},0,0,72,72);
  chk('tek renk dizi olmadan da çalışır',e.__st.depth===0);
}
/* eşleme */
const K=IOSI.keyOf;
chk('katalog youtube',K({cat:'youtube'})==='youtube');
chk('katalog ytmusic çizimsiz',K({cat:'ytmusic'})===null);
chk('katalog instagram',K({cat:'instagram'})==='instagram');
chk('katalog soundcloud',K({cat:'soundcloud'})==='soundcloud');
chk('katalog github/discord/spotify/whatsapp/wikipedia',['github','discord','spotify','whatsapp','wikipedia'].every(x=>K({cat:x})===x));
chk('adresle: instagram.com',K({url:'https://www.instagram.com/x'})==='instagram');
chk('adresle: m.youtube.com',K({url:'https://m.youtube.com'})==='youtube');
chk('adresle: music.youtube.com çizimsiz',K({url:'https://music.youtube.com'})===null);
chk('adresle: open.spotify.com',K({url:'https://open.spotify.com'})==='spotify');
chk('adresle: web.whatsapp.com',K({url:'https://web.whatsapp.com'})==='whatsapp');
chk('adresle: tr.wikipedia.org',K({url:'https://tr.wikipedia.org'})==='wikipedia');
chk('adresle: soundcloud.com',K({url:'https://soundcloud.com'})==='soundcloud');
chk('adresle: bilinmeyen site',K({url:'https://example.com'})===null);
chk('bozuk adres/boş',K({url:'not a url'})===null&&K(null)===null&&K({})===null);
chk('sistem: browser/store/device (Stage 32: App Store ikonu yeni uygulamada)',IOSI.SYSK.browser==='browser'&&IOSI.SYSK.store==='appstore'&&IOSI.SYSK.lib===undefined&&IOSI.SYSK.device==='android');

/* katalog */
const cat=html.match(/const CATALOG=\[([\s\S]*?)\n  \];/)[1];
const items=[...cat.matchAll(/\{k:'(\w+)',n:'([^']+)',u:'([^']+)',g:'([^']+)',gl:'([^']+)',c:\['(#\w+)','(#\w+)'\]\}/g)];
chk('katalog 40 uygulama (Stage 32)',items.length===40);
chk('katalog anahtarları benzersiz',new Set(items.map(x=>x[1])).size===items.length);
const grp=['Medya','Google','Sohbet','Üretkenlik','Tasarım','Keşif'];
chk('katalog grupları geçerli',items.every(x=>grp.includes(x[4])));
chk('katalog adresleri https',items.every(x=>/^https:\/\//.test(x[3])));
const byk=Object.fromEntries(items.map(x=>[x[1],x]));
chk('Instagram katalogda',byk.instagram&&byk.instagram[3]==='https://www.instagram.com');
chk('SoundCloud katalogda',byk.soundcloud&&byk.soundcloud[3]==='https://soundcloud.com');
chk('çizimli her web uygulaması katalogda',['youtube','spotify','discord','whatsapp','github','wikipedia','instagram','soundcloud'].every(k=>byk[k]));

/* bağlantılar */
chk('ATILE IOSI kullanır',/function ATILE\([^)]*key,ico\)[\s\S]*?IOSI\.tile\(/.test(html));
chk('katalog ATILE anahtar geçer',html.includes('it.gl,IOSI.keyOf({cat:it.k})'));
chk('Uygulamalarım ATILE anahtar geçer',html.includes('a.gl,IOSI.keyOf(a),a.ico)'));
chk('HTILE ik parametresi',html.includes('function HTILE(c,n,cx,cy,s,rot,seed,lab,col,pkg,id,ik,im)'));
chk('dock HTILE ik geçer',html.includes('a[4],a[5]&&a[5].ik,a[5]&&a[5].img);'));
chk('appInfo web ik',html.includes('web:true,ik:IOSI.keyOf(a)'));
chk('appInfo sistem ik',html.includes('ik:IOSI.SYSK[id]'));
chk('Library IOSI kullanır',html.includes('IOSI.tile(c,{k:a.ik,col:qcol(a.id,a.col,a.ic)'));
chk('Android uygulama ikonları değişmedi',html.includes('const im=AND.icon(a.pkg);\n          if(im.complete&&im.naturalWidth)c.drawImage(im,x,y,ts,ts);')&&html.includes('if(pkg){\n      const im=AND.icon(pkg);'));
chk('kamera dock rengi',html.includes("qcam:['#ff8fab','#e24a7c']"));

console.log(bad.length?'BAŞARISIZ:\n - '+bad.join('\n - '):'');
console.log('icontheme.test.js: '+ok+' kontrol geçti'+(bad.length?', '+bad.length+' başarısız':''));
process.exit(bad.length?1:0);
