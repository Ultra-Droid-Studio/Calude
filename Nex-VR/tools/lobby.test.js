/* Stage 34 — Açılış başlatıcı sahnesi (Lobby): bağlantılar, kanca, köprü, sözdizimi (Node, statik) */
const fs=require('fs'),vm=require('vm'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
const java=fs.readFileSync(path.join(__dirname,'../app/src/main/java/com/nexus/vr/MainActivity.java'),'utf8');
let ok=0;const bad=[];
const chk=(n,c)=>{if(c)ok++;else bad.push(n)};

const a=html.indexOf('/* LOBBY:BEGIN */'),b=html.indexOf('/* LOBBY:END */');
chk('Lobby bloğu bulundu',a>0&&b>a);
const src=html.slice(a,b);
let err=null;
try{new vm.Script('(function(){const $=0,clamp=0,Settings=0,Hand=0,Cam=0,XR=0,Diag=0,Pass=0,ACC=0,DEF=0,NX_T=0;'+src+'})')}catch(e){err=e}
chk('Lobby bloğu derleniyor',!err);
chk('CSS bloğu var',html.includes('/* LOBBY:CSS:BEGIN */')&&html.includes('/* LOBBY:CSS:END */'));

/* menü ve işlevler */
for(const t of ['Ana Menü','Ayarlar','Kalibrasyon','VR Ayarları','El Takibi','Hakkında','Çıkış','Başlat','Hızlı Erişim','VR Durumu','Uygulama Bilgisi'])chk('metin: '+t,src.includes(t));
chk('«VR Launcher» yazısı yok',!/VR Launcher/.test(src));
chk('Nex VR başlığı',src.includes('<h1>Nex VR</h1>')&&src.includes('<b>Nex VR</b>'));
chk('El takibi aç/kapa',/Hand\.on\?\(Hand\.stop\(\),null\):Hand\.start\(\)/.test(src));
chk('Kalibrasyon: Cam.reset + gyro',src.includes('Cam.reset()')&&src.includes('Cam.enableGyro()')&&src.includes('Cam.disableGyro()'));
chk('Kalibrasyon: çimdik hassasiyeti (hclk)',src.includes("'hclk'"));
chk('VR ayarları: profil + 4 değer',['vrProfile','vrEyeSep','vrFov','vrOffsetY','vrScale'].every(k=>src.includes(k)));
chk('8 gözlük profili',(src.match(/\{id:'[a-z]+',name:/g)||[]).length===8);
chk('Tema: 4 vurgu rengi döngüsü',src.includes("%4;this.set('acc'"));
chk('Çıkış köprüsü exitApp(NX_T)',src.includes('AndroidBridge.exitApp(NX_T)'));
chk('XR: WebXR kaldırıldı, Lobby XR.check() çağırmıyor (XR.support Stereo modundan ayarlanır)',!src.includes('XR.check()')&&html.includes("XR.support='Stereo/Cardboard modu'"));
chk('El → sahne: elementFromPoint + çimdik kenarı',src.includes('elementFromPoint')&&src.includes('s.pr&&!this.prev[i]'));

/* entegrasyon */
chk('Hand.arbitrate kancası',/arbitrate\(\)\{\s*if\(Lobby\.open\)\{Lobby\.hands\(this\.slots\);return\}/.test(html));
chk('boot → Lobby.show(go)',html.includes('Lobby.show(go)'));
chk('eski açılışa güvenli dönüş',html.includes('b.onclick=()=>Intro.run(go)'));
chk('Lobby, App\'ten önce tanımlı',html.indexOf('const Lobby={')<html.indexOf('  const App={'));
chk('#lobby, #hd (el çizimi) altında: z-index 45 < 46',/#lobby\{[^}]*z-index:45/.test(html)&&/#hd\{[^}]*z-index:46/.test(html));
/* id çakışması: SVG gradient/filtre kimlikleri mevcut #hv #hb #hd #lhs ile çakışmasın */
const ids=[...src.matchAll(/ id="([A-Za-z0-9_-]+)"/g)].map(m=>m[1]);
chk('SVG kimlikleri #hv/#hb/#hd ile çakışmıyor',!ids.some(i=>['hv','hb','hd','hs'].includes(i)&&/^(hv|hb|hd)$/.test(i)));

/* Java köprüsü */
chk('Java: exitApp var',/public boolean exitApp\(String t\)/.test(java));
chk('Java: token doğrulaması',/exitApp\(String t\)\s*\{\s*if \(!tokenOk\(t\)\) return false;/.test(java));
chk('Java: finishAndRemoveTask',java.includes('finishAndRemoveTask()'));

console.log(bad.length?'BAŞARISIZ: '+bad.join(' | '):'lobby.test.js: '+ok+' kontrol geçti');
process.exit(bad.length?1:0);
