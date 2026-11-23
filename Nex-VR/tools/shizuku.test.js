/* Stage 56/57 — Shizuku / VR'da Android uygulama penceresi: kaynak tutarlılık testi (Stage 57: klavye + sağlamlaştırma).
   Derleme/cihaz gerektirmez; Java, AIDL, manifest, gradle ve index.html'in birbirine uyduğunu denetler. */
const fs=require('fs'),path=require('path');
const R=p=>fs.readFileSync(path.join(__dirname,'..',p),'utf8');
const html=R('app/src/main/assets/index.html'),main=R('app/src/main/java/com/nexus/vr/MainActivity.java');
const link=R('app/src/main/java/com/nexus/vr/ShizukuLink.java'),svc=R('app/src/main/java/com/nexus/vr/ShellService.java');
const mirror=R('app/src/main/java/com/nexus/vr/AppMirror.java'),aidl=R('app/src/main/aidl/com/nexus/vr/IShellService.aidl');
const man=R('app/src/main/AndroidManifest.xml'),gradle=R('app/build.gradle');
let fails=0;const ok=(n,v)=>{console.log((v?'PASS ':'FAIL ')+n);if(!v)fails++};

// 1) JS'in çağırdığı her shz* köprü yöntemi Java'da @JavascriptInterface olarak var
const used=[...new Set([...html.matchAll(/AndroidBridge\.(shz[A-Za-z]+)/g)].map(m=>m[1]))];
ok('JS en az 4 shz köprü yöntemi kullanıyor ('+used.join(',')+')',used.length>=4);
used.forEach(n=>ok('Java köprüsünde '+n,new RegExp('@JavascriptInterface\\s+public\\s+\\w+\\s+'+n+'\\(').test(main)));

// 2) Her shz köprü yöntemi jeton ister
[...main.matchAll(/public\s+\w+\s+(shz[A-Za-z]+)\(([^)]*)\)\s*\{\s*\n?\s*if\s*\(!tokenOk\(t\)/g)].map(m=>m[1]).length===
  [...main.matchAll(/public\s+\w+\s+shz[A-Za-z]+\(/g)].length?ok('tüm shz yöntemleri tokenOk ile başlıyor',true):ok('tüm shz yöntemleri tokenOk ile başlıyor',false);

// 3) AIDL yöntemleri ShellService'te uygulanmış ve ShizukuLink'te sarılmış
const am=[...aidl.matchAll(/\b(\w+)\([^)]*\)\s*=\s*(\d+);/g)].map(m=>[m[1],+m[2]]);
ok('AIDL: destroy=16777114 (Shizuku sabiti)',am.some(([n,c])=>n==='destroy'&&c===16777114));
const codes=am.map(a=>a[1]);ok('AIDL işlem kodları benzersiz',new Set(codes).size===codes.length);
am.forEach(([n])=>{ok('ShellService.'+n,new RegExp('public\\s+\\w+\\s+'+n+'\\(').test(svc));if(n!=='destroy')ok('ShizukuLink.'+n,new RegExp('[\\s.]'+n+'\\(').test(link))});

// 4) Keyfi komut yok: ShellService'te sabit işlemler + doğrulama; AIDL'de "shell/exec" yok
ok('AIDL keyfi komut yöntemi içermiyor',!/\b(exec|shell|runCommand|sh)\s*\(/i.test(aidl));
ok('launch: bileşen deseni doğrulanıyor',/COMP\.matcher\(component\)\.matches\(\)/.test(svc));
ok('stopPackage: paket deseni doğrulanıyor',/PKG\.matcher\(pkg\)\.matches\(\)/.test(svc));
ok('komutlar argüman dizisiyle (kabuk dizesi yok)',/new ProcessBuilder\(cmd\)/.test(svc)&&!/sh\s*-c/.test(svc));

// 5) Girdi yolları: yansıtma dalı mevcut köprü yöntemlerinde
['touchView','scrollViewBy','gazeInteractInView','gazeDoubleTapInView','gpuSize','destroy'].forEach(n=>{
  /* destroy: iç içe tarayıcı köprüsünde de aynı adda bir yöntem var; köprünün (String id, ...) imzasını ara */
  const i=main.indexOf('public '+(n==='destroy'?'void destroy(String id,':(n==='gpuSize'||n==='touchView'||n==='scrollViewBy'||n.startsWith('gaze')?'boolean '+n+'(':n+'(')));
  const body=i<0?'':main.slice(i,i+1800);
  ok(n+' yansıtma (mirrors) dalı içeriyor',/mirrors\.(get|remove)\(id\)/.test(body))});

// 6) Manifest / gradle
ok('Manifest: ShizukuProvider',/rikka\.shizuku\.ShizukuProvider/.test(man)&&/\$\{applicationId\}\.shizuku/.test(man));
ok('Manifest: Shizuku API izni',/moe\.shizuku\.manager\.permission\.API_V23/.test(man));
ok('Manifest: Shizuku paketi <queries> içinde',/<package android:name="moe\.shizuku\.privileged\.api"/.test(man));
ok('Gradle: shizuku api + provider',/dev\.rikka\.shizuku:api/.test(gradle)&&/dev\.rikka\.shizuku:provider/.test(gradle));
ok('Gradle: aidl açık',/buildFeatures\s*\{\s*aidl true\s*\}/.test(gradle));

// 7) Yasak listesi: banka / Netflix / ödeme
const deny=(link.match(/DENY_PARTS\s*=\s*\{([\s\S]*?)\};/)||[])[1]||'';
['bank','netflix','paypal','wallet'].forEach(k=>ok('Yasak listesinde '+k,deny.includes('"'+k+'"')));
// denied() davranışı (Java ile aynı mantık)
const parts=[...deny.matchAll(/"([^"]+)"/g)].map(m=>m[1]);
const denied=p=>{p=p.toLowerCase();return parts.some(d=>p.includes(d))||p==='android'||p.startsWith('com.android.systemui')||p.startsWith('com.nexus.vr')||p==='moe.shizuku.privileged.api'};
ok('com.netflix.mediaclient reddedilir',denied('com.netflix.mediaclient'));
ok('com.garanti.cepsubesi reddedilir',denied('com.garanti.cepsubesi'));
ok('com.google.android.youtube serbest',!denied('com.google.android.youtube'));
ok('com.android.chrome serbest',!denied('com.android.chrome'));
ok('com.mojang.minecraftpe serbest',!denied('com.mojang.minecraftpe'));

// 8) JS: pencere kimliği Java kare yolu desenine uyar, paket adı noktalarına rağmen
const slug=p=>String(p).replace(/[^A-Za-z0-9_]/g,'-').slice(0,60);
['com.google.android.youtube','com.mojang.minecraftpe','org.mozilla.firefox'].forEach(p=>ok('webapp-'+slug(p)+' _snap desenine uyar',/^[A-Za-z0-9_-]{1,80}$/.test('webapp-'+slug(p))));
ok('WM.spawn shz: tanımına yönleniyor',/id\.startsWith\('shz:'\)\?SHZ\.def\(id\)/.test(html));
ok('BF.get shz için GPU kümesine ekliyor',/a\.type==='shz'[\s\S]{0,1200}this\.gpu\.add\(id\)/.test(html));
ok('AND.launch önce SHZ.tryOpen, sonra gerçek ekran',/launch\(p\)\{if\(SHZ\.tryOpen\(p\)\)return;this\.real\(p\)\}/.test(html));
ok('Lobi ayarında shz anahtarı + DEF varsayılanı',/T2\('shz'/.test(html)&&/shz:true/.test(html));
ok('Açık pencere durumu geri yüklemede atlanır (APPS[shz:..] yok)',!/APPS\['shz/.test(html));

// 9) AppMirror: PUBLIC + OWN_CONTENT_ONLY bayrakları, kapatırken yalnızca başlatılmışsa force-stop
ok('AppMirror PUBLIC|OWN_CONTENT_ONLY',/VIRTUAL_DISPLAY_FLAG_PUBLIC/.test(mirror)&&/VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY/.test(mirror));
ok('AppMirror: stopApp && started koşulu',/stopApp && started/.test(mirror));

// ================= Stage 57 =================
// 10) Sürüm tutarlılığı: ShellService.API_VERSION == ShizukuLink.SERVICE_VERSION == version() dönüşü
const apiV=+(svc.match(/API_VERSION\s*=\s*(\d+)/)||[])[1],srvV=+(link.match(/SERVICE_VERSION\s*=\s*(\d+)/)||[])[1];
ok('API_VERSION ('+apiV+') = SERVICE_VERSION ('+srvV+') ve Stage 56 (1)\'den büyük',apiV===srvV&&apiV>=2);
ok('ShellService.version() API_VERSION döndürüyor',/public int version\(\)\s*\{\s*return API_VERSION;/.test(svc));
ok('ShizukuLink bağlanınca sürümü doğruluyor',/s\.version\(\)/.test(link)&&/ShellService\.API_VERSION/.test(link));
ok('AIDL: typeText=6, version=7',/typeText\([^)]*\)\s*=\s*6;/.test(aidl)&&/version\(\)\s*=\s*7;/.test(aidl));

// 11) launch dönüş kodları AIDL açıklaması, ShellService ve AppMirror arasında tutarlı
const cst=n=>+(svc.match(new RegExp(n+'\\s*=\\s*(-?\\d+)'))||[])[1];
ok('launch kodları: OK=0 FRONT=10 ERROR=11 INVALID=-2 FAIL=-1',cst('L_OK')===0&&cst('L_FRONT')===10&&cst('L_ERROR')===11&&cst('L_INVALID')===-2&&cst('L_FAIL')===-1);
ok('AIDL açıklaması aynı kodları anlatıyor',/0 = başlatıldı, 10 = başlatılmadı[\s\S]*11 =[\s\S]*-2 =[\s\S]*-1 =/.test(aidl));
ok('launch: "not started/brought to the front" çıktısı L_FRONT',/not started[\s\S]{0,120}brought to the front[\s\S]{0,60}L_FRONT/.test(svc));
ok('AppMirror görev öne alınınca force-stop + yeniden dener',/L_FRONT && !stoppedOnce[\s\S]{0,300}link\.stopPackage\(pkg\)/.test(mirror));
ok('AppMirror en çok 3 deneme',/LAUNCH_TRIES = 3/.test(mirror)&&/attempt < LAUNCH_TRIES/.test(mirror));
ok('AppMirror servisi bekliyor (waitReady)',/link\.waitReady\(/.test(mirror)&&/boolean waitReady\(/.test(link));
ok('AppMirror ilk kare zaman aşımı (noframe)',/FIRST_FRAME_MS/.test(mirror)&&/"noframe"/.test(mirror)&&/gotFrame = true/.test(mirror));

// 12) Zaman aşımı ve çıktı okuma: takılan `am` servisi dondurmamalı
ok('run(): zaman aşımı (join) + p.destroy()',/rd\.join\(timeoutMs\)/.test(svc)&&/rd\.isAlive\(\)\)\s*\{\s*p\.destroy\(\)/.test(svc));
ok('run(): API 26+ gerektiren waitFor(long,TimeUnit) KULLANILMIYOR (minSdk 24)',!/waitFor\([^)]*TimeUnit/.test(svc));
ok('am yolu /system/bin/am öncelikli',/\/system\/bin\/am/.test(svc));

// 13) Klavye: bridge + beyaz liste
const keysSet=(main.match(/SHZ_KEYS[\s\S]*?asList\(([\s\S]*?)\)\);/)||[])[1]||'';
const keys=keysSet.split(',').map(x=>+x.trim()).filter(Number.isFinite);
ok('shzKey beyaz listesi: GERİ, Enter, Sil, Tab, Boşluk içerir',[4,66,67,61,62].every(k=>keys.includes(k)));
ok('shzKey beyaz listesi: Ana ekran(3), Güç(26), Son uygulamalar(187), Ses(24,25), Menü(82) YOK',[3,26,187,24,25,82,6,5].every(k=>!keys.includes(k)));
ok('shzKey beyaz listeyi uyguluyor',/SHZ_KEYS\.contains\(keyCode\)/.test(main)&&!/keyCode != 4\)/.test(main));
ok('shzText tokenOk ile başlıyor, 64 karakter sınırı',/public int shzText\(String id, String text, String t\)\s*\{\s*if \(!tokenOk\(t\)/.test(main)&&/text\.length\(\) > 64/.test(main));
ok('ShellService.typeText: sınır + denetim karakterleri atlanıyor',/MAX_TEXT = 64/.test(svc)&&/cp < 32 \|\| cp == 127/.test(svc));
ok('Tuş olayları klavye kaynaklı (SOURCE_KEYBOARD) ve sanal klavye aygıtı',/SOURCE_KEYBOARD/.test(svc)&&/VIRTUAL_KEYBOARD/.test(svc));
ok('typeText ASCII için KeyCharacterMap + yedek tablo',/KeyCharacterMap\.load\(KeyCharacterMap\.VIRTUAL_KEYBOARD\)/.test(svc)&&/KEYCODE_PERIOD/.test(svc));
ok('Manifest: windowSoftInputMode ve izinler değişmedi (yeni izin yok)',!/permission\.(INJECT_EVENTS|WRITE_SECURE_SETTINGS)/.test(man));

// 14) Yaşam döngüsü
ok('onPause/onResume mirror setPaused',/am\.setPaused\(true\)/.test(main)&&/am\.setPaused\(false\)/.test(main)&&/if \(paused\) return;/.test(mirror));
ok('onDestroy: mirror kapanışı Shizuku kesilmeden ÖNCE beklenir',/CountDownLatch[\s\S]{0,500}latch\.await\(1500[\s\S]{0,300}shz\.stop\(\)/.test(main));
ok('Stage 64: pencere sınırı yalnızca kullanıcı ayarından (sınıf/seviye sınırı yok)',/MAX_APP_WINDOWS = 16/.test(main)&&/mirrors\.size\(\) >= maxWin/.test(main)&&/userMaxWin/.test(main)&&!/dev\.tier == 1\) return dev\.phone \? 2 : 3/.test(main));
ok('Stage 59/63: telefon orta profili (960 px, seyrek/hafif kare) korunur; sınıf×seviye profili var',/PH_MAX_W = 960/.test(mirror)&&/phone \? 2\.4f : 1\.8f/.test(mirror)&&/applyProfile\(dp\)/.test(mirror)&&/dp\.phone/.test(mirror));
ok('Stage 60: üst çubuk pencerenin dışında (skin shz, kart arka planı yok)',/skin:'shz',chrome:false/.test(html)&&/u\.skin!=='qs'&&u\.skin!=='shz'/.test(html));
ok('Stage 60: Dik/Yatay düğmesi + dik sanal ekran boyutu',/SHZ\.rotate\(m\)/.test(html)&&/rotate\(m\)\{/.test(html)&&/r\.h>r\.w\*1\.15/.test(html)&&/po\?640:1280/.test(html));
ok('Stage 60: tuval genişliği cvW ile ayarlanabilir',/u\.cvW\|\|1024/.test(html));
ok('shzLaunched neden sözcüğü doğrulanıyor (JS enjeksiyonu yok)',/why\.matches\("\[a-z\]\{0,12\}"\)/.test(main));
ok('Result.launched 3 parametreli, MainActivity eşleşiyor',/void launched\(String id, boolean ok, String why\)/.test(mirror)&&/void shzLaunched\(String id, boolean ok, String why\)/.test(main));

// 15) JS: klavye + sağlamlık
ok('JS: AndroidBridge.shzText kullanılıyor ve Java\'da var',/AndroidBridge\.shzText/.test(html)&&/public int shzText\(/.test(main));
ok('JS: SHZ.def kbdFn tanımlı (pencere çubuğu Klavye düğmesi)',/kbdFn\(\)\{SHZ\.openKb\(this\)\}/.test(html));
ok('JS: başlık çubuğunda Klavye düğmesi',/'Klavye',\(\)=>SHZ\.openKb\(u\)/.test(html));
ok('JS: BF.get shz için yeniden deneme (a.n<4)',/a\.n<4&&\(st\.s===3\|\|st\.s===4\)/.test(html)&&!/a\.tried/.test(html));
ok('JS: __nxShzLaunched neden parametresi',/__nxShzLaunched=\(id,ok,why\)/.test(html)&&/SHZ\.why\(why\)/.test(html));
const jsKeys=[...html.matchAll(/AndroidBridge\.shzKey\(([^)]*)\)/g)].map(m=>m[1]);
ok('JS shzKey çağrıları (Geri sabit 4, klavye değişken kod)',jsKeys.length>=2);

// 16) KBD.live mantığı: press() gövdesini çıkarıp sahte `this` ile çalıştır
const pi=html.indexOf('    press(v){\n      if(this.live_){');
ok('KBD.press canlı mod dalı bulundu',pi>0);
if(pi>0){
  const body=html.slice(pi+'    press(v){'.length,html.indexOf('    dwell(o,bi)',pi));
  const bi=body.lastIndexOf('}');                    // method gövdesinin kapanışı
  const fn=new Function('v','WM',body.slice(0,bi));
  const mk=()=>{const sent=[];const o={live_:(k,v)=>sent.push([k,v]),text:'',shift:false,sym:false,open:true,m:{},closed:0,close(){this.closed++},sent};return o};
  const WM={paint(){}};
  let o=mk();fn.call(o,'a',WM);ok('canlı: "a" → text a',JSON.stringify(o.sent)==='[["text","a"]]');
  o=mk();fn.call(o,'shift',WM);fn.call(o,'a',WM);ok('canlı: shift+a → text A, shift sıfırlanır',JSON.stringify(o.sent)==='[["text","A"]]'&&o.shift===false);
  o=mk();fn.call(o,'shift',WM);fn.call(o,'i',WM);ok('canlı: shift+i → İ (Türkçe büyük harf)',o.sent[0][1]==='İ');
  o=mk();fn.call(o,'shift',WM);fn.call(o,'ı',WM);ok('canlı: shift+ı → I',o.sent[0][1]==='I');
  o=mk();fn.call(o,'back',WM);ok('canlı: ⌫ → key 67 (DEL)',JSON.stringify(o.sent)==='[["key",67]]');
  o=mk();o.text='abc';fn.call(o,'ok',WM);ok('canlı: ↵ → key 66 (ENTER), pencere açık kalır, önizleme temizlenir',JSON.stringify(o.sent)==='[["key",66]]'&&o.closed===0&&o.text==='');
  o=mk();fn.call(o,'cancel',WM);ok('canlı: Kapat → close, hiçbir şey gönderilmez',o.closed===1&&o.sent.length===0);
  o=mk();fn.call(o,' ',WM);fn.call(o,'.com',WM);ok('canlı: Boşluk ve ".com" metin olarak gider',JSON.stringify(o.sent)==='[["text"," "],["text",".com"]]');
  o=mk();for(let i=0;i<80;i++)fn.call(o,'x',WM);ok('canlı: önizleme en çok 48 karakter',Array.from(o.text).length===48&&o.sent.length===80);
  o=mk();o.live_=null;o.cb=()=>{};fn.call(o,'z',WM);ok('canlı değilken eski davranış: yazı alana eklenir, gönderim yok',o.text==='z'&&o.sent.length===0);
}
// Java'daki beyaz liste ile JS'in gönderdiği kodlar uyumlu: 67, 66 ve fiziksel klavye kodları listede
[67,66,19,20,21,22,61,112,92,93,122,123].forEach(k=>ok('JS\'in gönderdiği tuş kodu '+k+' Java beyaz listesinde',keys.includes(k)));

// ================= Stage 58: güvenilir sanal ekran =================
ok('AIDL: createDisplay=8, resizeDisplay=9, releaseDisplay=10 ve Surface içe aktarılmış',/createDisplay\([^)]*in Surface[^)]*\)\s*=\s*8;/.test(aidl)&&/resizeDisplay\([^)]*in Surface[^)]*\)\s*=\s*9;/.test(aidl)&&/releaseDisplay\([^)]*\)\s*=\s*10;/.test(aidl)&&/import android\.view\.Surface;/.test(aidl));
ok('API_VERSION = SERVICE_VERSION = 3 (Stage 58)',apiV===3&&srvV===3);
ok('ShellService: TRUSTED bayrağı (Android 13+) ve DESTROY_CONTENT_ON_REMOVAL',/VIRTUAL_DISPLAY_FLAG_TRUSTED/.test(svc)&&/VIRTUAL_DISPLAY_FLAG_DESTROY_CONTENT_ON_REMOVAL/.test(svc)&&/SDK_INT < 33/.test(svc));
ok('ShellService: ekran adı/boyut/dpi/adet doğrulanıyor',/DNAME\.matcher\(name\)\.matches\(\)/.test(svc)&&/MAX_DISPLAYS = 4/.test(svc)&&/dpi < 72 \|\| dpi > 640/.test(svc)&&/surface\.isValid\(\)/.test(svc));
ok('ShellService: paket adı com.android.shell, güvenilmeyen ekrana düşmüyor (tries hep TRUSTED içerir)',/"com\.android\.shell"/.test(svc)&&/int\[\] tries[\s\S]{0,260}base \| more/.test(svc));
ok('ShellService: destroy() ekranları kapatıyor',/destroy\(\) \{\s*releaseAllDisplays\(\);/.test(svc));
const nm='NEXUS '+'x'.repeat(30);ok('Ekran adı deseni: AppMirror adı en çok 36 karakter, [A-Za-z0-9 _.-]',/^[A-Za-z0-9 _.-]{1,40}$/.test(nm)&&/id\.length\(\) > 30 \? id\.substring\(0, 30\)/.test(mirror));
ok('AppMirror: başlatmadan önce upgradeToTrusted(), sonra güncel displayId ile launch',/m\.upgradeToTrusted\(\);[\s\S]{0,120}final int did = m\.displayId;[\s\S]{0,80}launchSmart\(component, did\)/.test(mirror));
ok('AppMirror: yeni ImageReader ile geçiş, başarısızsa eski ekran korunuyor',/nr = newReader\(w, h\);[\s\S]{0,200}link\.createDisplay\([\s\S]{0,260}nid <= 0[\s\S]{0,260}nr\.close\(\);[\s\S]{0,40}return;/.test(mirror));
ok('AppMirror: uzak ekranda boyutlandırma + kapatma servis üzerinden',/link\.resizeDisplay\(/.test(mirror)&&/link\.releaseDisplay\(/.test(mirror)&&/remote/.test(mirror));
ok('AppMirror: ilk kare bekleme 20 sn (yavaş başlatıcılar erken normal ekrana atılmasın)',/FIRST_FRAME_MS = 20000/.test(mirror));
ok('ShizukuLink: createDisplay/resizeDisplay/releaseDisplay sarmalayıcıları',/int createDisplay\(/.test(link)&&/boolean resizeDisplay\(/.test(link)&&/void releaseDisplay\(/.test(link));
ok('Gradle: sürüm 1.11 / kod 12',/versionCode 12/.test(gradle)&&/versionName "1\.11"/.test(gradle));

console.log(fails?('\n'+fails+' BAŞARISIZ'):'\nTÜMÜ GEÇTİ');process.exit(fails?1:0);
