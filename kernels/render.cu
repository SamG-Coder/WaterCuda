__global__ void tracePrimary(const float* C,const int* Origin,const float* Waves,float* Hit,float* Surface,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height);float cone=1.05f/(float)height;
 float wt=waterHit(ro,rd,cone,C[6],Waves,Origin),lt=traceLand(ro,rd,Origin,wt>0?wt+3:FAR,cone);
 float t=FAR,material=0,fp=0,variance=0,depth=0;float3 n=make_float3(0,1,0);
 if(lt>0&&(wt<0||lt<wt)){t=lt;material=1;fp=fmaxf(.2f,t*cone);n=groundNormal(ro+rd*t,Origin,fp);fp=fmaxf(.005f,t*cone/fmaxf(.2f,fabsf(dot3(n,rd))));}
 else if(wt>0){t=wt;material=2;fp=fmaxf(.12f,t*cone/fmaxf(.08f,-rd.y));float3 p=ro+rd*t;float4 w=ocean(p.x,p.z,fp,Waves,Origin);n=norm3(make_float3(-w.y,1,-w.z));variance=w.w;depth=fmaxf(0,p.y-ground(p.x,p.z,Origin,fp));}
 Hit[b]=t;Hit[b+1]=material;Hit[b+2]=fp;Hit[b+3]=variance;Surface[b]=n.x;Surface[b+1]=n.y;Surface[b+2]=n.z;Surface[b+3]=depth;
}
// One-quarter as many reflection rays; preserve coastline and normal discontinuities.
__global__ void reflectOcean(const float* C,const int* Origin,const float* Hit,const float* Surface,float* Reflection,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),rw=(width+1)/2,rh=(height+1)/2;if(x>=rw||y>=rh)return;
 int px=(int)fminf((float)(x*2+1),(float)(width-1)),py=(int)fminf((float)(y*2+1),(float)(height-1)),b=(py*width+px)*4,o=(y*rw+x)*4;
 Reflection[o]=0;Reflection[o+1]=0;Reflection[o+2]=0;Reflection[o+3]=-1;
 if(Hit[b+1]!=2||C[9]<.5f||Hit[b]>6500)return;
 float3 n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),rd=cameraRay(C,px,py,width,height),sun=sunDirection(C);
 float3 rr=rd-n*(2*dot3(rd,n)),ro=make_float3(C[0],C[1],C[2])+rd*Hit[b]+n*.3f;
 float3 reflected=sky(rr,sun);float cone=2.1f/(float)height,rt=traceLand(ro,rr,Origin,6500,cone);
 if(rt>0){float3 p=ro+rr*rt;float fp=fmaxf(.5f,(Hit[b]+rt)*cone);float3 land=landColor(p,groundNormal(p,Origin,fp),sun,Origin,fp);float fade=fmaxf(smoothf(4800,6500,Hit[b]),1-expf(-rt*.00008f));reflected=mix3(land,reflected,fade);}
 Reflection[o]=reflected.x;Reflection[o+1]=reflected.y;Reflection[o+2]=reflected.z;Reflection[o+3]=Hit[b];
}
__device__ float3 gatherReflection(int x,int y,int width,int height,float t,float3 n,float3 fallback,const float* Surface,const float* Reflection){
 int rw=(width+1)/2,rh=(height+1)/2;float3 sum=make_float3(0,0,0);float weights=0;
 float gx=((float)x-1)*.5f,gy=((float)y-1)*.5f,fx=fractf(gx),fy=fractf(gy);
 for(int k=0;k<4;k++){
  int xx=(int)clampf(floorf(gx)+(float)(k%2),0,(float)(rw-1)),yy=(int)clampf(floorf(gy)+(float)(k/2),0,(float)(rh-1));int j=(yy*rw+xx)*4;
  int px=(int)fminf((float)(xx*2+1),(float)(width-1)),py=(int)fminf((float)(yy*2+1),(float)(height-1)),hb=(py*width+px)*4;
  float dep=Reflection[j+3];float3 nn=make_float3(Surface[hb],Surface[hb+1],Surface[hb+2]);
  float tolerance=fmaxf(3,t*.04f),compatibility=smoothf(.65f,.98f,dot3(n,nn));
  float bilinear=(k%2==0?1-fx:fx)*(k/2==0?1-fy:fy);
  if(dep>0){float w=bilinear*compatibility*(1-smoothf(0,tolerance,fabsf(dep-t)));sum=sum+make_float3(Reflection[j],Reflection[j+1],Reflection[j+2])*w;weights+=w;}
 }
 // Preserve continuous coverage: rejected samples fade to sky instead of snapping
 // from a renormalized island reflection to sky at a half-resolution cell boundary.
 return sum+fallback*(1-sat(weights));
}
__global__ void shadeOcean(const float* C,const int* Origin,const float* Hit,const float* Surface,const float* Reflection,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float t=Hit[b],material=Hit[b+1],fp=Hit[b+2];float3 p=ro+rd*t,n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),color=sky(rd,sun);
 if(material==1)color=landColor(p,n,sun,Origin,fp)*terrainShadow(p+n*.4f,sun,Origin,fp);
 if(material==2){
  float nv=sat(-dot3(n,rd)),fresnel=.0204f+.9796f*powf(1-nv,5);float3 rr=rd-n*(2*dot3(rd,n)),reflected=sky(rr,sun);
  if(C[9]>.5f&&t<6500)reflected=gatherReflection(x,y,width,height,t,n,reflected,Surface,Reflection);
  float depth=Surface[b+3],eta=.75019f,k=1-eta*eta*(1-nv*nv);float3 refracted=rd*eta+n*(eta*nv-sqrtf(fmaxf(0,k)));
  float travel=fminf(200,depth/fmaxf(.15f,-refracted.y));float3 bp=p+refracted*travel,bottom=make_float3(.34f,.30f,.20f);
  if(depth<60){
   // Follow the refracted ray onto the sloping shelf, then fade bed detail smoothly.
   for(int i=0;i<3;i++){float bed=ground(bp.x,bp.z,Origin,fp);travel=lerpf(travel,clampf((p.y-bed)/fmaxf(.15f,-refracted.y),0,200),.65f);bp=p+refracted*travel;}
   bp.y=ground(bp.x,bp.z,Origin,fp);bottom=mix3(bottom,landColor(bp,make_float3(0,1,0),sun,Origin,fp),1-smoothf(35,60,depth));
  }
  float3 absorption=make_float3(expf(-travel*.19f),expf(-travel*.075f),expf(-travel*.038f));
  float3 scatter=make_float3(.006f,.065f,.092f)*(0.55f+0.45f*sun.y),under=bottom*absorption+scatter*(make_float3(1,1,1)-absorption);
  // Warped noise contours avoid the crossing sine lattice of the old caustics.
  // Use island-local coordinates so the pattern survives world-origin rebasing.
  if(depth<18&&fp<3){
   Island bedIsland=describeIsland((int)floorf(bp.x/CELL),(int)floorf(bp.z/CELL),Origin);
   float u=(bp.x-bedIsland.x)*.32f,v=(bp.z-bedIsland.z)*.32f;
   float drift=C[5]*.14f,wx=noise2(u*.41f+drift,v*.41f+bedIsland.seed),wz=noise2(u*.41f+19,v*.41f-drift);
   float contour=noise2(u+wx*2.8f+drift,v+wz*2.8f);
   float caustic=powf(sat(1-fabsf(contour-.5f)*16),3)*.11f*expf(-depth*.20f)*(1-smoothf(10,18,depth))*weight(fp,.45f);
   under=under+make_float3(.45f,.65f,.48f)*caustic;
  }
  color=mix3(under,reflected,fresnel);
  // GGX with Smith visibility and unresolved wave slope variance.
  float3 hv=norm3(sun-rd);float nl=sat(dot3(n,sun)),nh=sat(dot3(n,hv)),vh=sat(-dot3(rd,hv));
  float rough=.085f+.018f*C[6]+sqrtf(Hit[b+3])*.6f,a2=rough*rough,den=nh*nh*(a2-1)+1;
  float D=a2/(PI*den*den),gv=2*nv/(nv+sqrtf(a2+(1-a2)*nv*nv)+.0001f),gl=2*nl/(nl+sqrtf(a2+(1-a2)*nl*nl)+.0001f),F=.0204f+.9796f*powf(1-vh,5);
  color=color+make_float3(1,.85f,.65f)*(D*gv*gl*F/(4*fmaxf(nv,.03f)))*1.9f;
  float shore=1-smoothf(.15f,3.2f,depth),pattern=noise2(p.x*.32f+C[5]*.18f,p.z*.32f)*.65f+noise2(p.x*.9f,p.z*.9f)*.35f;
  float pulse=sinf(depth*2.1f-C[5]*1.6f+pattern*3),foam=shore*smoothf(.25f,.9f,pulse)*smoothf(.25f,.7f,pattern);
  float slope=sqrtf(n.x*n.x+n.z*n.z)/fmaxf(n.y,.1f);foam+=smoothf(.3f,.55f,slope)*smoothf(.5f,.8f,pattern)*.24f;
  color=mix3(color,make_float3(.62f,.71f,.68f),sat(foam));
 }
 if(material>0)color=mix3(color,sky(norm3(make_float3(rd.x,.018f,rd.z)),sun),1-expf(-t*.000042f));
 if(C[10]==1&&material>0){float level=log2f(fmaxf(1,fp));color=mix3(make_float3(.1f,.8f,.6f),make_float3(.9f,.25f,.12f),sat(level/6));}
 if(C[10]==2&&material>0)color=(n+make_float3(1,1,1))*.5f;
 color=color*C[11];color=make_float3(powf(aces(color.x),.4545f),powf(aces(color.y),.4545f),powf(aces(color.z),.4545f));Pixels[y*width+x]=pack(color);
}
__global__ void probeWorld(const float* Points,const int* Origin,const float* Waves,float* Result,int count){
 int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=count)return;int b=i*4;
 float x=Points[b],z=Points[b+1],fp=Points[b+2];Result[b]=ground(x,z,Origin,fp);float4 w=ocean(x,z,fp,Waves,Origin);Result[b+1]=w.x;Result[b+2]=w.y;Result[b+3]=w.w;
}

