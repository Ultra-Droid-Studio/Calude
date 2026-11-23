/* Stage 35 — MediaPipe inference must remain outside the UI thread. */
const fs=require('fs'),path=require('path');
const html=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/index.html'),'utf8');
const worker=fs.readFileSync(path.join(__dirname,'../app/src/main/assets/mediapipe-worker.js'),'utf8');
const checks=[
  ['worker asset exists',worker.length>1000],
  ['UI creates dedicated worker',html.includes("new Worker(workerUrl)")],
  ['transferable ImageBitmap frames',html.includes('createImageBitmap(v,rso)')&&html.includes('[bitmap]')],
  ['main thread has no MediaPipe inference',!html.includes('detectForVideo(')],
  ['worker owns MediaPipe inference',worker.includes('landmarker.detectForVideo(f.bitmap,ts)')],
  ['worker tries GPU before CPU',worker.includes("['GPU','CPU']")],
  ['worker supports cached local files',worker.includes('moduleFromFiles(m.files)')],
  ['worker supports remote package fallback',worker.includes('moduleFromRemote(m.bases||[])')],
  ['in-flight limit prevents backlog',html.includes('if(this.inflight>=(this.fast()?2:1))return;')],
  ['worker keeps only the freshest frame',worker.includes('pending={bitmap')&&worker.includes("say('dropped'")],
  ['worker timestamps strictly increase',worker.includes('lastTs+.01')],
  ['turbo glide predicts by measurement age',html.includes('Turbo mod (Stage 43)')&&html.includes('s.lvx[i]')],
  ['worker is terminated on stop',html.includes('this.worker.terminate()')],
  ['camera stream is not sent to worker',!/postMessage\(\{type:\s*['\"]camera/.test(html)],
  ['adaptive inference cadence is retained',html.includes('this.ema>35')&&html.includes('this.iv=80')],
  ['video callback does not duplicate hand step',html.includes('tick(performance.now(),true)')&&html.includes('if(!videoFrame)this.step(t)')]
];
let failed=0;
for(const [name,ok] of checks){console.log((ok?'PASS ':'FAIL ')+name);if(!ok)failed++}
if(failed)process.exit(1);
console.log('mediapipe-worker.test.js: '+checks.length+' checks passed');