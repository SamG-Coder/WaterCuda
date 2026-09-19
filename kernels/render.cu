__global__ void tracePrimary(const float* C,const int* Origin,const float* Waves,float* Hit,float* Surface,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height);float cone=1.05f/(float)height;
 float wt=waterHit(ro,rd,cone,C[6],Waves,Origin),lt=traceLand(ro,rd,Origin,wt>0?wt+3:FAR,cone);
 float t=FAR,material=0,fp=0,variance=0,depth=0;float3 n=make_float3(0,1,0);
 if(lt>0&&(wt<0||lt<wt)){t=lt;material=1;fp=fmaxf(.2f,t*cone);n=groundNormal(ro+rd*t,Origin,fp);fp=fmaxf(.005f,t*cone/fmaxf(.2f,fabsf(dot3(n,rd))));}
 else if(wt>0){t=wt;material=2;fp=fmaxf(.12f,t*cone/fmaxf(.08f,-rd.y));float3 p=ro+rd*t;float4 w=ocean(p.x,p.z,fp,Waves,Origin);n=norm3(make_float3(-w.y,1,-w.z));variance=w.w;depth=fmaxf(0,p.y-ground(p.x,p.z,Origin,fp));}
 Hit[b]=t;Hit[b+1]=material;Hit[b+2]=fp;Hit[b+3]=variance;Surface[b]=n.x;Surface[b+1]=n.y;Surface[b+2]=n.z;Surface[b+3]=depth;
}
// Trace each visible water pixel using its own normal; no half-resolution cells.
__global__ void reflectOcean(const float* C,const int* Origin,const float* Hit,const float* Surface,float* Reflection,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;
 int px=x,py=y,b=(y*width+x)*4,o=b;
 Reflection[o]=0;Reflection[o+1]=0;Reflection[o+2]=0;Reflection[o+3]=-1;
 if(Hit[b+1]!=2||C[9]<.5f||Hit[b]>6500)return;
 float3 n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),rd=cameraRay(C,px,py,width,height),sun=sunDirection(C);
 float3 rr=rd-n*(2*dot3(rd,n)),ro=make_float3(C[0],C[1],C[2])+rd*Hit[b]+n*.3f;
 float3 reflected=skyReflection(rr,sun,Hit[b+3]);float cone=1.05f/(float)height,rt=traceLand(ro,rr,Origin,6500,cone);
 if(rt>0){float3 p=ro+rr*rt;float fp=fmaxf(.5f,(Hit[b]+rt)*cone);float3 ln=groundNormal(p,Origin,fp);float shadow=terrainShadow(p+ln*.4f,sun,Origin,fp);float3 land=landColor(p,ln,sun,Origin,fp)*shadow;
 land=wetSandSheen(land,p,ln,rr,sun,Origin,fp,shadow);land=aerialPerspective(land,ro,rr,rt,sun);reflected=mix3(land,reflected,smoothf(4800,6500,Hit[b]));}
 Reflection[o]=reflected.x;Reflection[o+1]=reflected.y;Reflection[o+2]=reflected.z;Reflection[o+3]=Hit[b];
}
// Small same-frame reconstruction filter; no temporal history or extra ray queries.
// Keep land/sky, separate surfaces and differently oriented wave faces out of the sum.
__device__ float3 filteredReflection(int x,int y,int width,int height,const float* Hit,const float* Surface,const float* Reflection){
 int b=(y*width+x)*4;float t=Hit[b];float3 centre=make_float3(Reflection[b],Reflection[b+1],Reflection[b+2]);
 float3 n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),sum=centre*4;float total=4;
 for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
  if(dx==0&&dy==0)continue;int xx=x+dx,yy=y+dy;
  if(xx<0||yy<0||xx>=width||yy>=height)continue;int j=(yy*width+xx)*4;
  if(Hit[j+1]!=2||Reflection[j+3]<=0)continue;
  float3 nn=make_float3(Surface[j],Surface[j+1],Surface[j+2]);
  float depthWeight=1-smoothf(0,fmaxf(2,t*.025f),fabsf(Hit[j]-t));
  float normalWeight=smoothf(.85f,.995f,dot3(n,nn));
  float spatial=(dx==0||dy==0)?2.0f:1.0f,w=spatial*depthWeight*normalWeight;
  sum=sum+make_float3(Reflection[j],Reflection[j+1],Reflection[j+2])*w;total+=w;
 }
 float strength=clampf(.45f+sqrtf(fmaxf(0,Hit[b+3]))*2,.45f,.75f);
 return mix3(centre,sum/total,strength);
}
// Integer world lattice keeps foam fixed to the world during origin rebasing.
// Wavelengths divide CELL exactly; integer hashing never sees huge float positions.
__device__ float foamNoise(float x,float z,int wavelength,const int* Origin){
 float u=x/(float)wavelength,v=z/(float)wavelength,fx=fractf(u),fz=fractf(v);
 unsigned int stride=(unsigned int)(CELL/(float)wavelength);
 unsigned int ix=(unsigned int)(int)floorf(u)+(unsigned int)Origin[0]*stride;
 unsigned int iz=(unsigned int)(int)floorf(v)+(unsigned int)Origin[1]*stride;
 unsigned int seed=(unsigned int)Origin[2]+673u;
 fx=fx*fx*(3-2*fx);fz=fz*fz*(3-2*fz);
 return lerpf(lerpf(hash2((int)ix,(int)iz,seed),hash2((int)(ix+1u),(int)iz,seed),fx),lerpf(hash2((int)ix,(int)(iz+1u),seed),hash2((int)(ix+1u),(int)(iz+1u),seed),fx),fz);
}
// Bounded, analytical shoreline wash, not a fluid/foam simulation. The seabed
// contour anchors each incoming front; lacy breakup and trailing wash avoid white
// rings glued to the coastline. All lattice coordinates survive integer rebasing.
__device__ float waterFoam(float3 p,float3 n,float depth,float fp,float time,float wind,const int* Origin){
 float wb=weight(fp,.25f),wf=weight(fp,1),broad=.5f,fine=.5f;
 if(wb>0)broad+=(foamNoise(p.x+time*.32f,p.z-time*.13f,4,Origin)-.5f)*wb;
 if(wf>0)fine+=(foamNoise(p.x-time*.18f,p.z+time*.24f,1,Origin)-.5f)*wf;
 float stillDepth=fmaxf(0,depth-p.y),shore=1-smoothf(.35f,3.2f+wind*.65f,stillDepth);
 float phase=stillDepth*2.35f+time*1.22f+(broad-.5f)*2.3f;
 float front=powf(sat(.5f+.5f*sinf(phase)),10);
 float backwash=powf(sat(.5f+.5f*sinf(phase-1.05f)),3)*.32f;
 float lace=smoothf(.25f,.69f,broad*.58f+fine*.42f);
 float wash=(front+backwash)*lace;
 wash=lerpf(.13f,wash,wb);
 float contact=(1-smoothf(.02f,.32f,depth))*(.25f+fine*.40f);
 float slope=sqrtf(n.x*n.x+n.z*n.z)/fmaxf(n.y,.1f);
 float crest=smoothf(.24f*wind,1.1f*wind+.1f,p.y)*smoothf(.30f,.62f,slope);
 float whitecap=crest*lerpf(.18f,smoothf(.42f,.76f,broad*.65f+fine*.35f),wb)*.40f;
 return sat(shore*wash+contact+whitecap);
}
// Filtered ripples and sparse seabed patches are materials only. They never change
// the terrain/shoreline or insert mesh/image assets into the world.
__device__ float3 seabedAlbedo(float3 p,float fp,const int* Origin){
 Island a=describeIsland((int)floorf(p.x/CELL),(int)floorf(p.z/CELL),Origin);
 float u=p.x-a.x,v=p.z-a.z,patch=noise2(u*.035f+a.seed,v*.035f);
 float ripple=0,wr=weight(fp,.65f);if(wr>0){float warp=noise2(u*.10f,v*.10f)*1.9f;ripple=sinf(u*3.1f+v*.8f+warp)*wr;}
 float3 sand=make_float3(.54f,.48f,.32f)*(.96f+ripple*.075f);
 float reef=smoothf(.63f,.81f,patch)*smoothf(1.5f,9,-p.y)*.65f;
 return mix3(sand,make_float3(.13f,.19f,.105f),reef);
}
// Project a solar ray refracted by the ACTUAL FFT slopes onto a local horizontal
// receiver. This compact lens approximation is not a full photon/caustic solver.
__device__ float2 sunLanding(float x,float z,float bedY,float fp,float3 sun,const float* Waves,const int* Origin){
 float4 w=ocean(x,z,fp,Waves,Origin);float3 n=norm3(make_float3(-w.y,1,-w.z));
 float cosI=sat(dot3(n,sun)),eta=.75019f,k=1-eta*eta*(1-cosI*cosI);
 float3 ray=sun*(-eta)+n*(eta*cosI-sqrtf(fmaxf(0,k)));
 float path=fmaxf(0,w.x-bedY)/fmaxf(.15f,-ray.y);
 return make_float2(x+ray.x*path,z+ray.z*path);
}
__device__ float seabedCaustic(float3 p,float depth,float fp,float3 sun,const float* Waves,const int* Origin){
 if(depth>=16||depth<=.05f||fp>=2.2f||sun.y<=0)return 0;
 float eta=.75019f,dy=sqrtf(1-eta*eta*(1-sun.y*sun.y));
 float x=p.x+sun.x*eta*depth/dy,z=p.z+sun.z*eta*depth/dy;
 float e=fmaxf(.24f,fp*1.4f),sampleFp=fmaxf(fp,.22f);
 float2 a=sunLanding(x,z,p.y,sampleFp,sun,Waves,Origin),b=sunLanding(x+e,z,p.y,sampleFp,sun,Waves,Origin),c=sunLanding(x,z+e,p.y,sampleFp,sun,Waves,Origin);
 float determinant=((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))/(e*e);
 float focus=clampf(1/fmaxf(.18f,fabsf(determinant)),.55f,2.8f);
 return (focus-1)*.48f*expf(-depth*.10f)*smoothf(.05f,.8f,depth)*(1-smoothf(10,16,depth))*weight(fp,.45f)*smoothf(0,.35f,sun.y);
}
// Beer-Lambert attenuation for both the sun-to-bed and bed-to-camera paths.
__device__ float3 waterTransmission(float distance){
 distance=fmaxf(0,distance);
 return make_float3(expf(-distance*.19f),expf(-distance*.075f),expf(-distance*.038f));
}
__device__ float sunWaterPath(float depth,float sunY){
 float cosine=sat(sunY),eta=.75019f;
 return fmaxf(0,depth)/sqrtf(1-eta*eta*(1-cosine*cosine));
}
__device__ float bedDetailWeight(float viewPath,float depth,float sunY){
 float path=fmaxf(0,viewPath)+sunWaterPath(depth,sunY);
 return smoothf(.04f,.12f,expf(-path*.038f));
}
__global__ void shadeOcean(const float* C,const int* Origin,const float* Hit,const float* Surface,const float* Reflection,const float* Waves,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float t=Hit[b],material=Hit[b+1],fp=Hit[b+2];float3 p=ro+rd*t,n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),color=make_float3(0,0,0);
 // Sky/cloud evaluation is only needed when it survives the material branch.
 if(material!=1&&material!=2)color=sky(rd,sun);
 if(material==1){float shadow=terrainShadow(p+n*.4f,sun,Origin,fp);color=landColor(p,n,sun,Origin,fp)*shadow;color=wetSandSheen(color,p,n,rd,sun,Origin,fp,shadow);}
 if(material==2){
  float nv=sat(-dot3(n,rd)),fresnel=waterFresnel(nv);float3 rr=rd-n*(2*dot3(rd,n)),reflected=make_float3(0,0,0);
  if(C[9]>.5f&&t<6500&&Reflection[b+3]>0)reflected=filteredReflection(x,y,width,height,Hit,Surface,Reflection);
  else reflected=skyReflection(rr,sun,Hit[b+3]);
  float depth=Surface[b+3],eta=.75019f,k=1-eta*eta*(1-nv*nv);float3 refracted=rd*eta+n*(eta*nv-sqrtf(fmaxf(0,k)));
  float clarity=C[12]>0?clampf(C[12],.35f,2.5f):1;
  float travel=fminf(300,depth/fmaxf(.15f,-refracted.y)),initialTravel=travel;
  float detail=bedDetailWeight(travel/clarity,depth/clarity,sun.y);
  float3 bp=p+refracted*travel,bottom=make_float3(.34f,.30f,.20f);
  if(detail>0){
   // Expensive shelf/material lookup is unnecessary once two-way light is absorbed.
   for(int i=0;i<3;i++){float bed=ground(bp.x,bp.z,Origin,fp);travel=lerpf(travel,clampf((p.y-bed)/fmaxf(.15f,-refracted.y),0,300),.65f);bp=p+refracted*travel;}
   travel=lerpf(initialTravel,travel,detail);bp=p+refracted*travel;
   bp.y=ground(bp.x,bp.z,Origin,fp);bottom=mix3(bottom,seabedAlbedo(bp,fp,Origin),detail);
  }
  float bedDepth=lerpf(depth,fmaxf(0,p.y-bp.y),detail);
  float3 absorption=waterTransmission(travel/clarity),bedTransmission=waterTransmission((travel+sunWaterPath(bedDepth,sun.y))/clarity);
  float nl=sat(dot3(n,sun)),daylight=smoothf(-.04f,.12f,sun.y);
  float beamShadow=1;
  if(depth<18&&t<4500)beamShadow=sat((terrainShadow(p+n*.3f,sun,Origin,fmaxf(fp,.5f))-.38f)/.62f);
  float bedLight=.24f+.76f*sat(sun.y),caustic=C[13]>.5f?seabedCaustic(bp,bedDepth,fp,sun,Waves,Origin):0;
  float3 bedIrradiance=make_float3(.10f,.14f,.18f)+sunRadiance(sun)*(bedLight*.28f*beamShadow);
  float3 scatter=make_float3(.006f,.058f,.075f)*(.50f+daylight*.50f);
  // More turquoise light escapes thin wave crests. It is gated by depth and
  // backlighting, not an additive cyan coat over the entire ocean.
  float forward=powf(sat(dot3(rd,sun)),5),crest=smoothf(.05f,1.35f*C[6],p.y);
  scatter=scatter+make_float3(.003f,.021f,.016f)*(forward*crest*daylight);
  float3 under=bottom*bedIrradiance*bedTransmission*(1+caustic)+scatter*(make_float3(1,1,1)-absorption);
  color=mix3(under,reflected,fresnel);
  // Use the same solar radiance as the sky and land, once (not a reflected disk
  // plus a second specular light). Mip variance broadens unresolved sun glitter.
  color=color+sunRadiance(sun)*(waterSunLobe(n,rd,sun,Hit[b+3],C[6])*beamShadow);
  float foam=waterFoam(p,n,depth,fp,C[5],C[6],Origin);
  float3 foamLight=make_float3(.18f,.23f,.26f)+sunRadiance(sun)*((.23f*sat(sun.y)+.04f)*beamShadow);
  color=mix3(color,foamLight,foam);
 }
 if(material>0)color=aerialPerspective(color,ro,rd,t,sun);
 if(C[10]==1&&material>0){float level=log2f(fmaxf(1,fp));color=mix3(make_float3(.1f,.8f,.6f),make_float3(.9f,.25f,.12f),sat(level/6));}
 if(C[10]==2&&material>0)color=(n+make_float3(1,1,1))*.5f;
 color=color*C[11];color=make_float3(linearToDisplay(color.x),linearToDisplay(color.y),linearToDisplay(color.z));Pixels[y*width+x]=pack(color);
}
__global__ void probeWorld(const float* Points,const int* Origin,const float* Waves,float* Result,int count){
 int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=count)return;int b=i*4;
 float x=Points[b],z=Points[b+1],fp=Points[b+2];Result[b]=ground(x,z,Origin,fp);float4 w=ocean(x,z,fp,Waves,Origin);Result[b+1]=w.x;Result[b+2]=w.y;Result[b+3]=w.w;
}

