/* WallArt (index.html) sınaması: sahte 2B bağlamla tüm duvar kağıtları hatasız çizilir. node tools/wallart.test.js */
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'..','app','src','main','assets','index.html'),'utf8');
const a=html.indexOf('const WallArt={'),b=html.indexOf('const WALL=[');
if(a<0||b<0)throw new Error('WallArt/WALL bulunamadı');
const WallArt=new Function(html.slice(a,b)+';return WallArt')();
const walls=[...html.slice(b,html.indexOf('const Storage={')).matchAll(/\{id:'(\w+)',n:'([^']+)',f:'(#[0-9a-f]{6})'/g)];
let fail=0;const ok=(c,m)=>{if(!c){fail++;console.log('HATA:',m)}};
ok(walls.length===WallArt.IDS.length,'WALL ve WallArt.IDS sayısı farklı: '+walls.length+'/'+WallArt.IDS.length);
walls.forEach((m,i)=>ok(m[1]===WallArt.IDS[i],'sıra/ad uyuşmuyor: '+m[1]));
['sunset','night','aurora','ocean'].forEach((id,i)=>ok(walls[i]&&walls[i][1]===id,'ilk 4 duvar kağıdı sırası değişmemeli (Ayarlar wp indeksi): '+id));
const mkCtx=()=>{const st={n:0,bad:0,img:0,stops:0};
  const ctx=new Proxy({},{get(t,k){if(k in t)return t[k];if(k==='canvas')return{};if(k==='__st')return st;
    return(...a)=>{st.n++;if(k==='createImageData')return{data:new Uint8ClampedArray(a[0]*a[1]*4)};
      if(k==='createLinearGradient'||k==='createRadialGradient')return{addColorStop(o,c){st.stops++;if(!(o>=0&&o<=1))st.bad++;if(/NaN|undefined/.test(c))st.bad++}};
      if(k==='drawImage')st.img++;if(/^(arc|ellipse)$/.test(k)&&a.slice(0,3).some(v=>!isFinite(v)))st.bad++;
      if(k==='fillRect'&&a.some(v=>!isFinite(v)))st.bad++}},set(t,k,v){if(k==='fillStyle'||k==='strokeStyle')if(typeof v==='string'&&/NaN|undefined/.test(v))st.bad++;t[k]=v;return true}});
  return ctx};
WallArt.mk=(w,h)=>{const c=mkCtx();return{width:w,height:h,getContext:()=>c}};
for(const id of WallArt.IDS.concat(['bilinmeyen'])){
  const c=mkCtx();let err=null;const t0=Date.now();
  try{WallArt.draw(id,c,2048,1024)}catch(e){err=e}
  const st=c.__st;ok(!err,id+': istisna '+(err&&err.message));ok(st.bad===0,id+': geçersiz renk/koordinat '+st.bad);ok(st.img>=1,id+': hiç tuval çizimi yok');
  console.log(id.padEnd(10),'çağrı',st.n,'gradyan durağı',st.stops,(Date.now()-t0)+' ms')
}
const th=WallArt.make('night');WallArt.keep('night',th);ok(WallArt.cache.night&&WallArt.cache.night.width===256,'küçük resim üretilemedi');
console.log(fail?fail+' HATA':'TÜM KONTROLLER GEÇTİ');process.exit(fail?1:0)
