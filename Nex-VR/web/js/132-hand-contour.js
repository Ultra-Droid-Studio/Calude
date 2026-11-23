'use strict';
  /* ---------- Stage 74: içi boş siyah parmak konturları (GPU, işaretli uzaklık alanı) ----------
     Her el için TEK bir dörtgen (2 üçgen) çizilir; tüm şekil fragment shader'da analitik olarak hesaplanır:
       • her parmak kendi eklem zincirinin (taban→eklem→eklem→uç) inceltilmiş kapsüllerinin birleşimi → AYRI kontur;
         parmaklar birbirine değse de tek bir lekeye dönüşmez (her parmağın halkası ayrı çizilir),
       • avuç: bilek + parmak tabanlarından çokgen, daha ince çizgi; parmakların içinden geçen kısmı çizilmez,
       • yalnızca |uzaklık| < kalınlık/2 olan pikseller boyanır → içi tamamen boş (kamera görüntüsü / sahne görünür),
       • kenar yumuşatma piksel boyutundan (fwidth) → kalınlık her mesafede ve iki gözde aynı ve net.
     Kare başına CPU işi: 21 nokta + 21 yarıçap uniform'u yazmak (ayırma yok). Geometri/malzeme bir kez oluşturulur.
     Dörtgen kameranın çocuğudur: stereo modda iki göze de aynı (tutarlı) çizilir. Parmak başına sınır çemberiyle
     pikselin uzak olduğu parmaklar atlanır (GPU maliyeti el kutusu × birkaç parmak). */
  const HandContour={
    ok:null,geo:null,m:[],
    VS:'uniform vec2 uC;uniform vec2 uS;uniform float uD;varying vec2 vL;'+
      'void main(){vec2 p=uC+position.xy*uS;vL=p;gl_Position=projectionMatrix*modelViewMatrix*vec4(p,-uD,1.0);}',
    FS:[
      'uniform vec2 uP[21];uniform float uR[21];uniform vec3 uFB[5];uniform float uTh;uniform float uPTh;uniform float uA;uniform vec3 uCol;varying vec2 vL;',
      'float cap(vec2 p,vec2 a,vec2 b,float ra,float rb){vec2 pa=p-a,ba=b-a;float h=clamp(dot(pa,ba)/max(dot(ba,ba),1e-12),0.0,1.0);return length(pa-ba*h)-mix(ra,rb,h);}',
      'float ring(float d,float th,float w){return 1.0-smoothstep(th*0.5-w,th*0.5+w,abs(d));}',
      'float segd(vec2 p,vec2 a,vec2 b){vec2 pa=p-a,ba=b-a;float h=clamp(dot(pa,ba)/max(dot(ba,ba),1e-12),0.0,1.0);return length(pa-ba*h);}',
      /* GLSL ES 1.0: uniform dizisi indeksleri sabit olmalı → parmaklar açık yazılır */
      '#define FING(o,a,b,c,e,k) if(distance(p,uFB[k].xy)<uFB[k].z){float d=min(min(cap(p,uP[a],uP[b],uR[a],uR[b]),cap(p,uP[b],uP[c],uR[b],uR[c])),cap(p,uP[c],uP[e],uR[c],uR[e]));o=max(o,ring(d,uTh,w));inF=inF||d<0.0;}',
      'void main(){',
      ' vec2 p=vL;float w=length(fwidth(vL))*0.75;float o=0.0;bool inF=false;',
      ' FING(o,1,2,3,4,0) FING(o,5,6,7,8,1) FING(o,9,10,11,12,2) FING(o,13,14,15,16,3) FING(o,17,18,19,20,4)',
      /* avuç çokgeni: 0-1-5-9-13-17 (ince çizgi), parmak içinde kalan parçası çizilmez */
      ' if(!inF){float dp=min(min(min(segd(p,uP[0],uP[1]),segd(p,uP[1],uP[5])),min(segd(p,uP[5],uP[9]),segd(p,uP[9],uP[13]))),min(segd(p,uP[13],uP[17]),segd(p,uP[17],uP[0])));',
      '  o=max(o,0.8*(1.0-smoothstep(uPTh*0.5-w,uPTh*0.5+w,dp)));}',
      ' float al=o*uA;if(al<0.01)discard;gl_FragColor=vec4(uCol,al);',
      '}'].join('\n'),
    /* yarıçap çarpanları (avuç uzunluğuna göre): başparmak kalın, uçlara doğru incelir, serçe ince */
    RK:[.13,.135,.12,.105,.092, .108,.097,.087,.078, .11,.099,.089,.08, .104,.094,.085,.076, .092,.083,.075,.068],
    init(T,parent){
      if(this.ok!==null)return this.ok;
      try{
        this.geo=new T.PlaneGeometry(2,2);
        for(let i=0;i<2;i++){
          const P=[],R=new Float32Array(21),FB=[];
          for(let k=0;k<21;k++)P.push(new T.Vector2());
          for(let k=0;k<5;k++)FB.push(new T.Vector3());
          const mat=new T.ShaderMaterial({
            uniforms:{uP:{value:P},uR:{value:R},uFB:{value:FB},uTh:{value:.002},uPTh:{value:.0012},uA:{value:0},uCol:{value:new T.Color(0,0,0)},
              uC:{value:new T.Vector2()},uS:{value:new T.Vector2(.1,.1)},uD:{value:.5}},
            vertexShader:this.VS,fragmentShader:this.FS,transparent:true,depthTest:false,depthWrite:false,
            extensions:{derivatives:true}});
          const mesh=new T.Mesh(this.geo,mat);
          mesh.frustumCulled=false;mesh.renderOrder=998;mesh.visible=false;mesh.matrixAutoUpdate=false;
          parent.add(mesh);
          this.m.push({mesh,mat,U:mat.uniforms,a:0,vis:false});
        }
        this.ok=true
      }catch(e){console.warn('El konturu kurulamadı',e);this.ok=false}
      return this.ok
    },
    /* i: yuva; pts: 21 nokta ekran-normalize (x,y ∈ 0..1, y aşağı); d: düzlem derinliği (m); cam: perspektif kamera;
       pxTh: parmak çizgi kalınlığı (CSS piksel); alpha: 0..1 */
    place(i,pts,d,cam,pxTh,alpha){
      const c=this.m[i];if(!c)return;
      const e=cam.projectionMatrix.elements,U=c.U,P=U.uP.value,R=U.uR.value,FB=U.uFB.value,H=Math.max(1,innerHeight);
      const sx=d/e[0],sy=d/e[5];
      let x0=1e9,y0=1e9,x1=-1e9,y1=-1e9;
      for(let k=0;k<21;k++){
        const q=pts[k],x=(q.x*2-1)*sx,y=-(q.y*2-1)*sy;P[k].set(x,y);
        if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y
      }
      const L=Math.max(Math.hypot(P[9].x-P[0].x,P[9].y-P[0].y),Math.hypot(P[5].x-P[17].x,P[5].y-P[17].y)*1.15,1e-4);
      for(let k=0;k<21;k++)R[k]=this.RK[k]*L;
      const mpp=2*sy/H,th=Math.max(1,pxTh)*mpp;            /* metre/piksel (bu derinlikte) */
      U.uTh.value=th;U.uPTh.value=th*.6;
      const CH=HandFeat.CH;
      for(let f=0;f<5;f++){
        const ch=CH[f],a=P[ch[0]],b=P[ch[3]];
        let r=0;for(let j=0;j<4;j++){const q=P[ch[j]];r=Math.max(r,Math.hypot(q.x-(a.x+b.x)/2,q.y-(a.y+b.y)/2)+R[ch[j]])}
        FB[f].set((a.x+b.x)/2,(a.y+b.y)/2,r+th*2+mpp*2)
      }
      const pad=L*.16+th*2+mpp*2;
      U.uC.value.set((x0+x1)/2,(y0+y1)/2);U.uS.value.set((x1-x0)/2+pad,(y1-y0)/2+pad);U.uD.value=d;
      U.uA.value=alpha;c.a=alpha;
      if(!c.vis){c.mesh.visible=true;c.vis=true}
    },
    hide(i){const c=this.m[i];if(c&&c.vis){c.mesh.visible=false;c.vis=false;c.a=0;return true}return false},
    hideAll(){let ch=false;for(let i=0;i<this.m.length;i++)ch=this.hide(i)||ch;return ch}
  };
