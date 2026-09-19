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
 float3 reflected=sky(rr,sun);float cone=1.05f/(float)height,rt=traceLand(ro,rr,Origin,6500,cone);
 if(rt>0){float3 p=ro+rr*rt;float fp=fmaxf(.5f,(Hit[b]+rt)*cone);float3 land=landColor(p,groundNormal(p,Origin,fp),sun,Origin,fp);land=aerialPerspective(land,ro,rr,rt,sun);reflected=mix3(land,reflected,smoothf(4800,6500,Hit[b]));}
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
__device__ float waterFoam(float3 p,float3 n,float depth,float fp,float time,float wind,const int* Origin){
 float broad=.5f,fine=.5f,wb=weight(fp,.25f),wf=weight(fp,1);
 if(wb>0)broad+=(foamNoise(p.x+time*.45f,p.z,4,Origin)-.5f)*wb;
 if(wf>0)fine+=(foamNoise(p.x,p.z-time*.22f,1,Origin)-.5f)*wf;
 float pattern=broad*.7f+fine*.3f;
 float shore=1-smoothf(.15f,2.4f+wind*.8f,depth);
 float pulse=sinf(depth*2.1f-time*1.6f+pattern*3);
 float wash=smoothf(.25f,.9f,pulse)*smoothf(.25f,.7f,pattern);
 // Fade nonlinear foam detail toward average coverage when it becomes subpixel.
 wash=lerpf(.14f,wash,weight(fp,.25f));
 float slope=sqrtf(n.x*n.x+n.z*n.z)/fmaxf(n.y,.1f);
 float crest=smoothf(.25f*wind,1.1f*wind+.1f,p.y)*smoothf(.30f,.55f,slope);
 float breaking=crest*lerpf(.22f,smoothf(.45f,.75f,pattern),wb)*.32f;
 return sat(shore*wash+breaking);
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
__global__ void shadeOcean(const float* C,const int* Origin,const float* Hit,const float* Surface,const float* Reflection,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float t=Hit[b],material=Hit[b+1],fp=Hit[b+2];float3 p=ro+rd*t,n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),color=make_float3(0,0,0);
 // Sky/cloud evaluation is only needed when it survives the material branch.
 if(material!=1&&material!=2)color=sky(rd,sun);
 if(material==1)color=landColor(p,n,sun,Origin,fp)*terrainShadow(p+n*.4f,sun,Origin,fp);
 if(material==2){
  float nv=sat(-dot3(n,rd)),fresnel=.0204f+.9796f*powf(1-nv,5);float3 rr=rd-n*(2*dot3(rd,n)),reflected=make_float3(0,0,0);
  if(C[9]>.5f&&t<6500&&Reflection[b+3]>0)reflected=filteredReflection(x,y,width,height,Hit,Surface,Reflection);
  else reflected=sky(rr,sun);
  float depth=Surface[b+3],eta=.75019f,k=1-eta*eta*(1-nv*nv);float3 refracted=rd*eta+n*(eta*nv-sqrtf(fmaxf(0,k)));
  float travel=fminf(200,depth/fmaxf(.15f,-refracted.y)),initialTravel=travel;
  float detail=bedDetailWeight(travel,depth,sun.y);
  float3 bp=p+refracted*travel,bottom=make_float3(.34f,.30f,.20f);
  if(detail>0){
   // Expensive shelf/material lookup is unnecessary once two-way light is absorbed.
   for(int i=0;i<3;i++){float bed=ground(bp.x,bp.z,Origin,fp);travel=lerpf(travel,clampf((p.y-bed)/fmaxf(.15f,-refracted.y),0,200),.65f);bp=p+refracted*travel;}
   travel=lerpf(initialTravel,travel,detail);bp=p+refracted*travel;
   bp.y=ground(bp.x,bp.z,Origin,fp);bottom=mix3(bottom,landColor(bp,make_float3(0,1,0),sun,Origin,fp),detail);
  }
  float bedDepth=lerpf(depth,fmaxf(0,p.y-bp.y),detail);
  float3 absorption=waterTransmission(travel),bedTransmission=waterTransmission(travel+sunWaterPath(bedDepth,sun.y));
  float3 scatter=make_float3(.006f,.065f,.092f)*(0.55f+0.45f*sun.y),under=bottom*bedTransmission+scatter*(make_float3(1,1,1)-absorption);
  // Warped noise contours avoid the crossing sine lattice of the old caustics.
  // Use island-local coordinates so the pattern survives world-origin rebasing.
  if(depth<18&&fp<3){
   Island bedIsland=describeIsland((int)floorf(bp.x/CELL),(int)floorf(bp.z/CELL),Origin);
   float u=(bp.x-bedIsland.x)*.32f,v=(bp.z-bedIsland.z)*.32f;
   float drift=C[5]*.14f,wx=noise2(u*.41f+drift,v*.41f+bedIsland.seed),wz=noise2(u*.41f+19,v*.41f-drift);
   float contour=noise2(u+wx*2.8f+drift,v+wz*2.8f);
   float caustic=powf(sat(1-fabsf(contour-.5f)*16),3)*.11f*expf(-depth*.20f)*(1-smoothf(10,18,depth))*weight(fp,.45f);
   under=under+make_float3(.45f,.65f,.48f)*caustic*bedTransmission;
  }
  color=mix3(under,reflected,fresnel);
  // GGX with Smith visibility and unresolved wave slope variance.
  float3 hv=norm3(sun-rd);float nl=sat(dot3(n,sun)),nh=sat(dot3(n,hv)),vh=sat(-dot3(rd,hv));
  float rough=.085f+.018f*C[6]+sqrtf(Hit[b+3])*.6f,a2=rough*rough,den=nh*nh*(a2-1)+1;
  float D=a2/(PI*den*den),gv=2*nv/(nv+sqrtf(a2+(1-a2)*nv*nv)+.0001f),gl=2*nl/(nl+sqrtf(a2+(1-a2)*nl*nl)+.0001f),F=.0204f+.9796f*powf(1-vh,5);
  color=color+make_float3(1,.85f,.65f)*(D*gv*gl*F/(4*fmaxf(nv,.03f)))*1.9f;
  float foam=waterFoam(p,n,depth,fp,C[5],C[6],Origin);
  color=mix3(color,make_float3(.62f,.71f,.68f),sat(foam));
 }
 if(material>0)color=aerialPerspective(color,ro,rd,t,sun);
 if(C[10]==1&&material>0){float level=log2f(fmaxf(1,fp));color=mix3(make_float3(.1f,.8f,.6f),make_float3(.9f,.25f,.12f),sat(level/6));}
 if(C[10]==2&&material>0)color=(n+make_float3(1,1,1))*.5f;
 color=color*C[11];color=make_float3(powf(aces(color.x),.4545f),powf(aces(color.y),.4545f),powf(aces(color.z),.4545f));Pixels[y*width+x]=pack(color);
}
__global__ void probeWorld(const float* Points,const int* Origin,const float* Waves,float* Result,int count){
 int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=count)return;int b=i*4;
 float x=Points[b],z=Points[b+1],fp=Points[b+2];Result[b]=ground(x,z,Origin,fp);float4 w=ocean(x,z,fp,Waves,Origin);Result[b+1]=w.x;Result[b+2]=w.y;Result[b+3]=w.w;
}

