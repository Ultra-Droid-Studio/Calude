'use strict';
  /* Not: 0.10.22 kararlı sürümü npm'de bulunmuyor olabilir (yalnızca 0.10.22-rc...); adresler 404 dönüyordu.
     Bu yüzden bilinen sürümler sırayla denenir. Paket ve wasm her zaman aynı sürümden alınır. */
  const MP_VERS=['0.10.21','0.10.20','0.10.18','latest'];
  const MP_HOSTS=[
    v=>'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@'+v,
    v=>'https://fastly.jsdelivr.net/npm/@mediapipe/tasks-vision@'+v,
    v=>'https://gcore.jsdelivr.net/npm/@mediapipe/tasks-vision@'+v,
    v=>'https://unpkg.com/@mediapipe/tasks-vision@'+v,
    v=>'https://registry.npmmirror.com/@mediapipe/tasks-vision/'+v+'/files',
    v=>'https://npm.elemecdn.com/@mediapipe/tasks-vision@'+v
  ];
  const mpBuild=hs=>MP_VERS.flatMap(v=>hs.map(h=>h(v)));
  let MP_BASES=mpBuild(MP_HOSTS);
  const MPLocal={mod:null,fileset:null,model:null,base:null,files:null};
  /* Sunuculara ulaşım testi: ulaşılamayanlar atlanır, hızlı olan 3 sunucu kullanılır. */
  async function probeMediaPipeHosts(onStatus){
    onStatus('Sunucu erişimi test ediliyor…');
    const t0=performance.now();
    const test=async u=>{
      const c=new AbortController(),t=setTimeout(()=>c.abort(),7000);
      try{await fetch(u,{mode:'no-cors',cache:'no-store',signal:c.signal});return performance.now()-t0}
      catch(e){return null}finally{clearTimeout(t)}
    };
    const r=await Promise.all(MP_HOSTS.map(h=>test(h(MP_VERS[0])+'/package.json')));
    const okH=MP_HOSTS.map((h,i)=>({h,t:r[i]})).filter(x=>x.t!==null).sort((a,b)=>a.t-b.t).map(x=>x.h);
    const hn=h=>new URL(h(MP_VERS[0])).hostname;
    MPLocal.probe={ok:okH.map(hn),bad:MP_HOSTS.filter((h,i)=>r[i]===null).map(hn)};
    if(okH.length)MP_BASES=mpBuild(okH.slice(0,3));
    return MPLocal.probe
  }
  const MEDIAPIPE_HAND_MODEL='https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task';
  const MPdb={
    open(){return new Promise((res,rej)=>{const r=indexedDB.open('nexus-mp',1);r.onupgradeneeded=()=>r.result.createObjectStore('f');r.onsuccess=()=>res(r.result);r.onerror=()=>rej(r.error)})},
    async put(k,v){try{const d=await this.open();await new Promise((res,rej)=>{const t=d.transaction('f','readwrite');t.objectStore('f').put(v,k);t.oncomplete=res;t.onerror=()=>rej(t.error)})}catch(e){}},
    async get(k){try{const d=await this.open();return await new Promise((res,rej)=>{const q=d.transaction('f').objectStore('f').get(k);q.onsuccess=()=>res(q.result);q.onerror=()=>rej(q.error)})}catch(e){return null}}
  };
  async function fetchTimeout(url,ms){
    const c=new AbortController(),t=setTimeout(()=>c.abort(),ms);
    try{const r=await fetch(url,{signal:c.signal,mode:'cors',credentials:'omit'});if(!r.ok)throw new Error('HTTP '+r.status);return await r.blob()}
    finally{clearTimeout(t)}
  }
  /* Dosyaları kendisi indirir, IndexedDB'ye kaydeder; sonraki açılışlarda internet gerekmez. */
  async function autoDownloadMediaPipe(onStatus){
    let model=null;
    for(const b of MP_BASES){
      const host=new URL(b).hostname,ver=(b.match(/@([^/]+)$/)||b.match(/tasks-vision\/([^/]+)\/files/)||[])[1]||'';
      const parts=[['vision_bundle.cjs','/vision_bundle.cjs'],['vision_wasm_internal.js','/wasm/vision_wasm_internal.js'],['vision_wasm_internal.wasm','/wasm/vision_wasm_internal.wasm']];
      const files=[];let ok=true;
      for(let i=0;i<parts.length;i++){
        try{onStatus('İndiriliyor ('+(i+1)+'/4) '+parts[i][0]+' — '+host+' '+ver);files.push(new File([await fetchTimeout(b+parts[i][1],60000)],parts[i][0]))}
        catch(e){ok=false;break}
      }
      if(!ok)continue;
      try{
        if(!model){onStatus('İndiriliyor (4/4) hand_landmarker.task');model=new File([await fetchTimeout(MEDIAPIPE_HAND_MODEL,60000)],'hand_landmarker.task')}
        files.push(model);
        await applyLocalFiles(files);
        await MPdb.put('files',files);
        return true
      }catch(e){}
    }
    throw new Error('İndirilemedi')
  }
  /* APK içine derleme sırasında gömülmüş MediaPipe dosyaları (assets/mediapipe/). Varsa internet gerekmez; yoksa sessizce atlanır. */
  async function loadBundledMediaPipe(onStatus){
    const base=new URL('mediapipe/',document.baseURI).href,names=['vision_bundle.cjs','vision_wasm_internal.js','vision_wasm_internal.wasm','hand_landmarker.task'],files=[];
    for(const n of names){
      onStatus('Uygulama içi dosya okunuyor: '+n);
      const b=await fetchTimeout(base+n,30000);
      if(!b||b.size<20000)throw new Error('Gömülü dosya eksik: '+n);
      files.push(new File([b],n))
    }
    await applyLocalFiles(files);
    await MPdb.put('files',files);
    return true
  }
  async function applyLocalFiles(files){
    const by=n=>files.find(f=>n.test(f.name));
    const bundle=by(/^vision_bundle\.(cjs|mjs)$/i);
    const loader=files.find(f=>/^vision_wasm_internal\.js$/i.test(f.name))||by(/^vision_wasm_nosimd_internal\.js$/i);
    const wasm=files.find(f=>/^vision_wasm_internal\.wasm$/i.test(f.name))||by(/^vision_wasm_nosimd_internal\.wasm$/i);
    const model=by(/\.task$/i);
    if(!bundle||!loader||!wasm||!model)throw new Error('Eksik dosya. Gerekenler: vision_bundle.cjs (veya .mjs), vision_wasm_internal.js, vision_wasm_internal.wasm, hand_landmarker.task');
    /* MediaPipe dosyaları ana iş parçacığında çalıştırılmaz; Worker'a aktarılmak üzere tutulur. */
    MPLocal.files=files;
    MPLocal.localReady=true
  }
  let BAR=58;
  const TB=18, ACC=['#2f7bff','#19d3c5','#b06bff','#ff9a2e'];
