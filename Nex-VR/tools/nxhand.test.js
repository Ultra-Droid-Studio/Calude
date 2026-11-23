#!/usr/bin/env node
/* Stage 74 — native el kinematiği (C++) testi: masaüstü derleyicisiyle derleyip çalıştırır.
   Android'de aynı kaynak (app/src/main/cpp) NDK/CMake ile libnxhand.so olarak derlenir.
   Ayrıca JNI köprüsü JDK başlıklarıyla derlenip dışa aktarılan işlev adları HandKin.java ile karşılaştırılır. */
const {execFileSync}=require('child_process'),fs=require('fs'),os=require('os'),path=require('path');
const ROOT=path.join(__dirname,'..'),CPP=path.join(ROOT,'app/src/main/cpp');
const cxx=['g++','clang++'].find(c=>{try{execFileSync(c,['--version'],{stdio:'ignore'});return true}catch(e){return false}});
if(!cxx){console.log('ATLANDI: C++ derleyicisi yok');process.exit(0)}
const tmp=fs.mkdtempSync(path.join(os.tmpdir(),'nxhand-'));
let fail=0;
try{
  const bin=path.join(tmp,'t');
  execFileSync(cxx,['-std=c++17','-O2','-Wall','-Wextra','-Werror','-o',bin,path.join(__dirname,'native/nxhand_test.cpp'),path.join(CPP,'hand_kinematics.cpp')],{stdio:'inherit'});
  try{process.stdout.write(execFileSync(bin,{encoding:'utf8'}))}catch(e){process.stdout.write(String(e.stdout||''));fail++}
  /* JNI köprüsü: JDK jni.h ile derle, Java tarafındaki native bildirimlerle eşleşiyor mu? */
  const jh=process.env.JAVA_HOME||(()=>{try{return path.dirname(path.dirname(fs.realpathSync(execFileSync('which',['java'],{encoding:'utf8'}).trim())))}catch(e){return ''}})();
  if(jh&&fs.existsSync(path.join(jh,'include/jni.h'))){
    const so=path.join(tmp,'libnxhand.so');
    execFileSync(cxx,['-std=c++17','-O2','-fno-exceptions','-fno-rtti','-Wall','-Wextra','-Werror','-fPIC','-shared','-I'+path.join(jh,'include'),'-I'+path.join(jh,'include/linux'),'-o',so,path.join(CPP,'hand_kinematics.cpp'),path.join(CPP,'jni_bridge.cpp')],{stdio:'inherit'});
    const syms=execFileSync('nm',['-D',so],{encoding:'utf8'}).split('\n').map(l=>l.trim().split(' ').pop()).filter(s=>s.startsWith('Java_'));
    const java=fs.readFileSync(path.join(ROOT,'app/src/main/java/com/nexus/vr/HandKin.java'),'utf8');
    const decl=[...java.matchAll(/static\s+native\s+\w+\s+(\w+)\s*\(/g)].map(m=>'Java_com_nexus_vr_HandKin_'+m[1]);
    const miss=decl.filter(d=>!syms.includes(d));
    if(decl.length&&!miss.length)console.log('PASS JNI: '+decl.length+' native işlev .so içinde dışa aktarılmış');
    else{console.log('FAIL JNI eksik: '+miss.join(', ')+' (bildirim '+decl.length+')');fail++}
    const stride=+((fs.readFileSync(path.join(CPP,'hand_kinematics.h'),'utf8').match(/O_LM = (\d+)/)||[])[1]);
    const jstride=+((java.match(/OUT_STRIDE\s*=\s*(\d+)/)||[])[1]);
    if(stride+63===jstride)console.log('PASS çıktı adımı Java ile aynı ('+jstride+')');else{console.log('FAIL çıktı adımı: C++ '+(stride+63)+' Java '+jstride);fail++}
  }else console.log('ATLANDI: JDK jni.h bulunamadı');
}finally{try{fs.rmSync(tmp,{recursive:true,force:true})}catch(e){}}
if(fail){console.log('nxhand.test.js: BAŞARISIZ');process.exit(1)}
console.log('nxhand.test.js: geçti');
