#!/usr/bin/env node
/* Nex VR — web/ parçalarını birleştirip app/src/main/assets/index.html üretir.
 *
 *   node tools/build-html.js          -> index.html ve web/dev.html'i yeniden yazar
 *   node tools/build-html.js --check  -> yazmaz; dosyalar güncel değilse hata kodu 1 ile çıkar
 *
 * Kaynaklar (düzenlediğin yer burası):
 *   web/template.html     sayfa iskeleti (@@STYLE@@, @@GUARD@@, @@MAIN@@ yer tutucuları)
 *   web/style.css         tüm CSS
 *   web/head-guard.js     <head> içindeki CanvasGradient koruması
 *   web/js/NN-*.js        ana kod, sırayla (NN sırayı belirler). Her dosya 'use strict'; ile başlar.
 *   web/wrap/head.txt     ana kodun başlık yorumu + (function(){ + 'use strict';
 *   web/wrap/tail.txt     })();
 *
 * Çıktılar:
 *   app/src/main/assets/index.html   APK'ya giren tek parça dosya (eski haliyle birebir aynı yapı)
 *   web/dev.html                     parçaları ayrı <link>/<script> ile yükleyen geliştirme sayfası:
 *                                    derlemeden tarayıcıda aç. Not: kod burada IIFE içinde değil, global kapsamda çalışır. */
const fs=require('fs'),path=require('path');
const ROOT=path.join(__dirname,'..'),WEB=path.join(ROOT,'web');
const OUT=path.join(ROOT,'app/src/main/assets/index.html'),DEV=path.join(WEB,'dev.html');
const rd=f=>fs.readFileSync(path.join(WEB,f),'utf8');

function parts(){
  return fs.readdirSync(path.join(WEB,'js')).filter(f=>/^\d+-.*\.js$/.test(f)).sort()
    .map(f=>({file:'js/'+f,text:rd('js/'+f)}));
}
function build(){
  const tpl=rd('template.html'),ps=parts();
  const strict="'use strict';\n";
  for(const p of ps)if(!p.text.startsWith(strict))throw new Error(p.file+": ilk satır 'use strict'; olmalı");
  // --- tek parça (APK) ---
  const main='<script>\n'+rd('wrap/head.txt')+ps.map(p=>p.text.slice(strict.length)).join('')+rd('wrap/tail.txt')+'</script>';
  const inline=tpl.replace('@@STYLE@@',()=>'<style>\n'+rd('style.css')+'</style>')
                  .replace('@@GUARD@@',()=>'<script>\n'+rd('head-guard.js')+'</script>')
                  .replace('@@MAIN@@',()=>main);
  // --- geliştirme sayfası ---
  const up='../../../../web/';   // <base> assets klasörü olduğu için web/'e geri dönüş yolu
  const dev=tpl.replace('<head>','<head>\n<base href="../app/src/main/assets/">')
               .replace('@@STYLE@@',()=>'<link rel="stylesheet" href="'+up+'style.css">')
               .replace('@@GUARD@@',()=>'<script src="'+up+'head-guard.js"></script>')
               .replace('@@MAIN@@',()=>ps.map(p=>'<script src="'+up+p.file+'"></script>').join('\n'));
  return{inline,dev,parts:ps};
}
module.exports={build,parts};
if(require.main===module){
  const b=build(),check=process.argv.includes('--check');
  const same=(f,t)=>fs.existsSync(f)&&fs.readFileSync(f,'utf8')===t;
  if(check){
    const bad=[[OUT,b.inline],[DEV,b.dev]].filter(([f,t])=>!same(f,t)).map(([f])=>path.relative(ROOT,f));
    if(bad.length){console.error('GÜNCEL DEĞİL: '+bad.join(', ')+'\nÇalıştır: node tools/build-html.js');process.exit(1)}
    console.log('index.html ve web/dev.html güncel');
  }else{
    fs.writeFileSync(OUT,b.inline);fs.writeFileSync(DEV,b.dev);
    console.log('yazıldı: '+path.relative(ROOT,OUT)+' ('+b.inline.length+' karakter), web/dev.html, '+b.parts.length+' parça');
  }
}
