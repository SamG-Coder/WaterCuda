// Frozen 2d22d90 final shading for lazy-sky equivalence checks.
__global__ void referenceShadeOcean(const float* C,const int* Origin,const float* Hit,const float* Surface,const float* Reflection,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float t=Hit[b],material=Hit[b+1],fp=Hit[b+2];float3 p=ro+rd*t,n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),color=sky(rd,sun);
 if(material==1)color=landColor(p,n,sun,Origin,fp)*terrainShadow(p+n*.4f,sun,Origin,fp);
 if(material==2){
  float nv=sat(-dot3(n,rd)),fresnel=.0204f+.9796f*powf(1-nv,5);float3 rr=rd-n*(2*dot3(rd,n)),reflected=sky(rr,sun);
  if(C[9]>.5f&&t<6500){if(Reflection[b+3]>0)reflected=filteredReflection(x,y,width,height,Hit,Surface,Reflection);}
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
