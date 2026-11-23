/* NEXUS VR — MediaPipe inference worker.
 * All model/WASM initialization and detectForVideo work happens off the UI thread.
 * Camera frames arrive as transferable ImageBitmap objects; no camera stream is exposed to this worker.
 */
'use strict';
let landmarker=null, closed=false, busy=false, pending=null, lastTs=0, objectUrls=[];
const say=(type,data={})=>self.postMessage(Object.assign({type},data));
const valid=m=>m&&m.HandLandmarker&&m.FilesetResolver;
function blobUrl(data,type){
  const u=URL.createObjectURL(new Blob([data],{type:type||'application/octet-stream'}));
  objectUrls.push(u);return u;
}
async function moduleFromFiles(files){
  const find=re=>files.find(f=>re.test(f.name));
  const bundle=find(/^vision_bundle\.(cjs|mjs)$/i);
  const loader=find(/^vision_wasm_internal\.js$/i)||find(/^vision_wasm_nosimd_internal\.js$/i);
  const wasm=find(/^vision_wasm_internal\.wasm$/i)||find(/^vision_wasm_nosimd_internal\.wasm$/i);
  const model=find(/\.task$/i);
  if(!bundle||!loader||!wasm||!model)throw new Error('Yerel MediaPipe dosyaları eksik');
  const loaderUrl=blobUrl(loader.buffer,'text/javascript');
  const wasmUrl=blobUrl(wasm.buffer,'application/wasm');
  let mod;
  if(/\.mjs$/i.test(bundle.name)){
    mod=await import(blobUrl(bundle.buffer,'text/javascript'));
  }else{
    const previousModule=self.module,previousExports=self.exports;
    const m={exports:{}};self.module=m;self.exports=m.exports;
    try{importScripts(blobUrl(bundle.buffer,'text/javascript'));mod=m.exports}
    finally{if(previousModule===undefined)delete self.module;else self.module=previousModule;
      if(previousExports===undefined)delete self.exports;else self.exports=previousExports}
  }
  if(!valid(mod))throw new Error('Yerel MediaPipe kitaplığı geçersiz');
  return {mod,fileset:{wasmLoaderPath:loaderUrl,wasmBinaryPath:wasmUrl},
    model:{modelAssetBuffer:new Uint8Array(model.buffer)}};
}
async function moduleFromRemote(bases){
  const errors=[];
  for(const base of bases){
    for(const kind of ['module','classic']){
      try{
        say('status',{message:'Worker MediaPipe kitaplığı yükleniyor: '+new URL(base).hostname});
        let mod;
        if(kind==='module')mod=await import(base+'/vision_bundle.mjs');
        else{
          const response=await fetch(base+'/vision_bundle.cjs',{mode:'cors',credentials:'omit'});
          if(!response.ok)throw new Error('HTTP '+response.status);
          const code=await response.text();
          const previousModule=self.module,previousExports=self.exports;
          const m={exports:{}};self.module=m;self.exports=m.exports;
          try{importScripts(blobUrl(code,'text/javascript'));mod=m.exports}
          finally{
            if(previousModule===undefined)delete self.module;else self.module=previousModule;
            if(previousExports===undefined)delete self.exports;else self.exports=previousExports;
          }
        }
        if(valid(mod))return {mod,wasmBase:base+'/wasm'};
        throw new Error('MediaPipe dışa aktarımı bulunamadı');
      }catch(e){errors.push((e&&e.message)||String(e))}
    }
  }
  throw new Error('MediaPipe kitaplığı Worker içinde yüklenemedi: '+errors.slice(0,3).join(' | '));
}
async function init(m){
  closed=false;
  say('status',{message:'MediaPipe Worker başlatılıyor…'});
  let loaded;
  if(m.files&&m.files.length){
    try{loaded=await moduleFromFiles(m.files)}
    catch(e){say('status',{message:'Yerel önbellek kullanılamadı; çevrimiçi kaynak deneniyor…'})}
  }
  if(!loaded)loaded=await moduleFromRemote(m.bases||[]);
  const wasmCandidates=loaded.fileset?[loaded.fileset]:[loaded.wasmBase];
  const modelCandidates=loaded.model?[loaded.model]:[{modelAssetPath:m.modelUrl}];
  const errors=[];
  for(const wasm of wasmCandidates){
    let fileset;
    try{fileset=typeof wasm==='string'?await loaded.mod.FilesetResolver.forVisionTasks(wasm):wasm}
    catch(e){errors.push((e&&e.message)||String(e));continue}
    for(const model of modelCandidates){
      for(const delegate of ['GPU','CPU']){
        try{
          say('status',{message:'MediaPipe modeli Worker içinde hazırlanıyor ('+delegate+')…'});
          landmarker=await loaded.mod.HandLandmarker.createFromOptions(fileset,{
            baseOptions:Object.assign({delegate},model),...(m.options||{})
          });
          say('ready',{delegate});return;
        }catch(e){errors.push(delegate+': '+((e&&e.message)||String(e)))}
      }
    }
  }
  throw new Error('MediaPipe modeli başlatılamadı: '+errors.slice(0,4).join(' | '));
}
self.onmessage=async e=>{
  const m=e.data||{};
  if(m.type==='close'){closed=true;if(pending){try{pending.bitmap.close()}catch(_){}pending=null}try{landmarker&&landmarker.close()}catch(_){}landmarker=null;return}
  if(m.type==='init'){
    try{await init(m)}catch(err){say('init-error',{message:(err&&err.message)||String(err)})}
    return;
  }
  if(m.type==='frame'){
    /* Yalnızca EN TAZE kare tutulur: bekleyen eski kare atılır (ana iş parçacığına 'dropped' bildirilir),
       böylece iki kare yoldayken bile gecikme birikmez ve Worker hiç boşta kalmaz. */
    const bitmap=m.bitmap;
    if(closed||!landmarker){try{bitmap&&bitmap.close()}catch(_){}say('dropped',{seq:m.seq});return}
    if(pending){try{pending.bitmap.close()}catch(_){}say('dropped',{seq:pending.seq})}
    pending={bitmap,timestamp:m.timestamp,seq:m.seq};
    if(!busy)drain();
  }
};
async function drain(){
  busy=true;
  try{
    while(pending){
      const f=pending;pending=null;
      if(closed||!landmarker){try{f.bitmap.close()}catch(_){}say('dropped',{seq:f.seq});continue}
      /* MediaPipe VIDEO modu kesin artan zaman damgası ister. */
      const ts=f.timestamp>lastTs?f.timestamp:lastTs+.01;lastTs=ts;
      const start=performance.now();
      try{
        const result=landmarker.detectForVideo(f.bitmap,ts);
        say('result',{result,duration:performance.now()-start,timestamp:f.timestamp,seq:f.seq});
      }catch(err){say('frame-error',{message:(err&&err.message)||String(err),seq:f.seq})}
      finally{try{f.bitmap.close()}catch(_){}}
      /* Olay döngüsüne bir nefes: sırada bekleyen yeni kareler 'pending' üzerine yazılsın. */
      await new Promise(r=>setTimeout(r,0));
    }
  }finally{busy=false}
}
