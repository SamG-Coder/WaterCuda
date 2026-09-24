__device__ float3 seabedAlbedo(float3 p,float fp,const int* Origin){
 float base=seabedBase(p.x,p.z,Origin,fp);float4 reef=reefColony(p.x,p.z,base,fp,Origin);
 float ripple=0;
 // Phase uses an integer-period local coordinate to remain stable after rebasing.
 float ux=p.x-floorf(p.x/12)*12,uz=p.z-floorf(p.z/12)*12;
 ripple=sinf(ux*(2*PI/3)+uz*(2*PI/6)+bedNoise(p.x,p.z,12,Origin,1250u)*2)*weight(fp,.65f);
 float grain=bedNoise(p.x,p.z,1,Origin,1251u);
 float3 sand=make_float3(.55f,.49f,.34f)*(.92f+ripple*.07f+grain*.12f);
 float rock=smoothf(.58f,.78f,bedNoise(p.x,p.z,24,Origin,1252u))*smoothf(12,45,-base);
 sand=mix3(sand,make_float3(.18f,.22f,.17f),rock*.7f);
 // Living colonies are separate 3D objects; the substrate stays limestone/rubble.
 return mix3(sand,make_float3(.16f,.19f,.15f)*(.75f+grain*.5f),sat(reef.x*.22f));
}

// A moving 384 m CUDA-generated seabed tile. Static world geometry/material is
// evaluated once per 12 m camera step, not hundreds of times per viewing ray.
// It shares the existing scene storage binding with foliage (18.73 MiB total).
__global__ void cacheReef(const float* C,const int* Origin,float* Shrubs){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),z=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=1024||z>=1024)return;
 float bx=floorf(C[0]/12)*12-192,bz=floorf(C[2]/12)*12-192;
 if(x==0&&z==0){Shrubs[REEF_CACHE]=bx;Shrubs[REEF_CACHE+1]=bz;Shrubs[REEF_CACHE+2]=1;Shrubs[REEF_CACHE+3]=0;}
 float px=bx+((float)x+.5f)*.375f,pz=bz+((float)z+.5f)*.375f;
 float h=ground(px,pz,Origin,.06f);float3 color=seabedAlbedo(make_float3(px,h,pz),.06f,Origin);
 int b=REEF_CACHE+4+(z*1024+x)*4;Shrubs[b]=h;Shrubs[b+1]=color.x;Shrubs[b+2]=color.y;Shrubs[b+3]=color.z;
 if(x<160&&z<160){
  int ix=(int)roundf(bx/2.4f)+x,iz=(int)roundf(bz/2.4f)+z;
  unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*2000u,gz=(unsigned int)iz+(unsigned int)Origin[1]*2000u;
  float seed=hash2((int)gx,(int)gz,(unsigned int)Origin[2]+2111u);
  float rx=((float)ix+.5f)*2.4f+(seed-.5f)*1.1f,rz=((float)iz+.5f)*2.4f+(hash2((int)gx,(int)gz,2112u)-.5f)*1.1f;
  float base=seabedBase(rx,rz,Origin,.06f);float4 habitat=reefColony(rx,rz,base,.06f,Origin);
  float root=base+habitat.x;
  float size=(.82f+.34f*hash2((int)gx,(int)gz,2113u))*smoothf(.10f,.24f,habitat.y);
  if(root> -3.5f)size=0;
  size=fminf(size,fmaxf(0,(-root-1.5f)/3.2f));
  // Correlated gardens: one dominant species and palette across adjacent colonies.
  float garden=bedNoise(rx,rz,24,Origin,2120u);
  float kind=garden<.43f?0:(garden<.65f?1:2);
  float palette=bedNoise(rx,rz,24,Origin,2121u);
  if(-base>24&&seed<.6f)kind=1;
  int c=CORAL_CACHE+(z*160+x)*8;
  Shrubs[c]=rx;Shrubs[c+1]=root-.08f;Shrubs[c+2]=rz;Shrubs[c+3]=size;
  Shrubs[c+4]=kind;Shrubs[c+5]=seed;Shrubs[c+6]=palette;Shrubs[c+7]=0;
 }
}
__device__ float4 reefSample(float x,float z,const int* Origin,const float* Shrubs){
 float u=(x-Shrubs[REEF_CACHE])*(8.0f/3)-.5f,v=(z-Shrubs[REEF_CACHE+1])*(8.0f/3)-.5f;
 // The 150 m optical range lies inside the nearest cache edge (180 m).
 u=clampf(u,0,1023);v=clampf(v,0,1023);
 int ix=(int)floorf(u),iz=(int)floorf(v),jx=(int)fminf((float)ix+1,1023),jz=(int)fminf((float)iz+1,1023);
 float fx=u-(float)ix,fz=v-(float)iz;
 int a=REEF_CACHE+4+(iz*1024+ix)*4,b=REEF_CACHE+4+(iz*1024+jx)*4,c=REEF_CACHE+4+(jz*1024+ix)*4,d=REEF_CACHE+4+(jz*1024+jx)*4;
 float out[4];for(int k=0;k<4;k++)out[k]=lerpf(lerpf(Shrubs[a+k],Shrubs[b+k],fx),lerpf(Shrubs[c+k],Shrubs[d+k],fx),fz);
 return make_float4(out[0],out[1],out[2],out[3]);
}
__device__ float3 reefNormal(float3 p,const int* Origin,const float* Shrubs,float fp){
 float e=fmaxf(.125f,fp);return norm3(make_float3(reefSample(p.x-e,p.z,Origin,Shrubs).x-reefSample(p.x+e,p.z,Origin,Shrubs).x,2*e,reefSample(p.x,p.z-e,Origin,Shrubs).x-reefSample(p.x,p.z+e,Origin,Shrubs).x));
}
__device__ float traceReef(float3 ro,float3 rd,const int* Origin,const float* Shrubs,float limit){
 float t=.02f,previous=t;float slope=fabsf(rd.y)+12*sqrtf(rd.x*rd.x+rd.z*rd.z);
 int budget=(int)fminf(4096,ceilf(limit/.02f)+2);
 for(int i=0;i<budget;i++){
  if(t>=limit)return -1;float3 p=ro+rd*t;if(p.y>8&&rd.y>=0)return -1;
  float gap=p.y-reefSample(p.x,p.z,Origin,Shrubs).x;
  if(gap<=0){float lo=previous,hi=t;for(int k=0;k<7;k++){float mid=(lo+hi)*.5f;float3 q=ro+rd*mid;if(q.y>reefSample(q.x,q.z,Origin,Shrubs).x)lo=mid;else hi=mid;}return (lo+hi)*.5f;}
  previous=t;t+=fmaxf(.02f,gap/fmaxf(.01f,slope));
 }
 return -1;
}
// Actual 3D intersections: disconnected silhouettes, plate undersides and branch gaps.
__device__ float4 coralEllipsoid(float3 ro,float3 rd,float3 center,float3 radius,float4 hit){
 float3 inv=make_float3(1/radius.x,1/radius.y,1/radius.z);float3 q=(ro-center)*inv,v=rd*inv;float a=dot3(v,v),b=dot3(q,v),c=dot3(q,q)-1,d=b*b-a*c;
 if(d<0)return hit;float t=(-b-sqrtf(d))/a;if(t<=.002f)t=(-b+sqrtf(d))/a;
 if(t<=.002f||t>=hit.x)return hit;float3 n=norm3((ro+rd*t-center)*inv*inv);return make_float4(t,n.x,n.y,n.z);
}
__device__ float4 coralBranch(float3 ro,float3 rd,float3 a,float3 b,float radius,float4 hit){
 float3 ba=b-a,oa=ro-a;float bb=dot3(ba,ba),br=dot3(ba,rd),bo=dot3(ba,oa),rr=dot3(rd,oa);
 // Reject the enclosing sphere before evaluating the cylinder and both caps.
 float middle=rr-br*.5f,oo=dot3(oa,oa);
 float sphereRadius2=bb*.25f+radius*sqrtf(bb)+radius*radius;
 if(oo-bo+bb*.25f-middle*middle>sphereRadius2+.00001f)return hit;
 float aa=bb-br*br,ab=bb*rr-bo*br,cc=bb*oo-bo*bo-radius*radius*bb,disc=ab*ab-aa*cc;
 if(aa>.000001f&&disc>=0){float t=(-ab-sqrtf(disc))/aa,y=bo+t*br;
  if(t>.002f&&t<hit.x&&y>0&&y<bb){float3 n=norm3(oa+rd*t-ba*(y/bb));hit=make_float4(t,n.x,n.y,n.z);}}
 hit=coralEllipsoid(ro,rd,a,make_float3(radius,radius,radius),hit);
 return coralEllipsoid(ro,rd,b,make_float3(radius,radius,radius),hit);
}
// Pixel-footprint LOD retains a branching silhouette at every level.
__device__ int coralArmStep(float fp){return fp>.15f?4:(fp>.065f?2:1);}
__device__ int coralForkCount(float fp){return fp>.065f?2:4;}
__device__ int coralTwigCount(float fp){return fp>.028f?0:(fp>.012f?1:3);}
__device__ float4 coralGeometry(float3 ro,float3 rd,float kind,float seed,float limit,float footprint){
 float4 hit=make_float4(limit,0,0,0);float phase=seed*2*PI;
 if(kind<2){
  // A spreading colony: dense, irregular radial branching, rather than upright trees.
  bool table=kind>=1;int arms=kind<0?29:17;
  int armStep=coralArmStep(footprint);float thick=sqrtf((float)armStep);
  #pragma unroll 1
  for(int i=0;i<arms;i+=armStep){
   float angle=phase+(float)i*2.399963f;
   float reach=.45f+.42f*fractf(seed*17+(float)i*.618f);
   float h=table?.48f:.25f+.35f*fractf(seed*13+(float)i*.37f);
   float3 a=make_float3(0,.04f,0),b=make_float3(cosf(angle)*reach,h,sinf(angle)*reach);
   hit=coralBranch(ro,rd,a,b,.075f*thick,hit);
   int forks=coralForkCount(footprint);
   #pragma unroll 1
   for(int f=0;f<forks;f++){
    int j=forks==2?f*2+1:f;
    float u=.35f+(float)j*.20f,turn=angle+(j%2==0?-.7f:.7f);
    float3 joint=a+(b-a)*u;
    float3 tip=joint+make_float3(cosf(turn)*.26f,(table?.18f:.24f)+fractf(seed*23+(float)(i*4+j)*.43f)*.22f,sinf(turn)*.26f);
    hit=coralBranch(ro,rd,joint,tip,(.045f+.02f*smoothf(.012f,.04f,footprint))*thick,hit);
    int twigs=coralTwigCount(footprint);
    #pragma unroll 1
    for(int k=0;k<twigs;k++){
     float theta=turn+(float)k*2.1f;float3 end=tip+make_float3(cosf(theta)*.13f,.12f+fractf(seed*29+(float)(i+j+k)*.67f)*.16f,sinf(theta)*.13f);
     hit=coralBranch(ro,rd,tip,end,.026f,hit);
    }
   }
  }
  if(table)hit=coralEllipsoid(ro,rd,make_float3(0,.43f,0),make_float3(.75f,.055f,.68f),hit);
 }else{
  // Rounded massive head with overlapping low lobes, not a bundle of fingers.
  hit=coralEllipsoid(ro,rd,make_float3(0,.34f,0),make_float3(.88f,.55f,.78f),hit);
  int lobes=17;
  for(int i=0;i<lobes;i++){
   float angle=phase+(float)i*2.399963f,r=sqrtf((float)i/17)*.8f;
   float y=.35f+.35f*sqrtf(fmaxf(0,1-r*r));
   hit=coralEllipsoid(ro,rd,make_float3(cosf(angle)*r,y,sinf(angle)*r),make_float3(.23f,.26f,.23f),hit);
  }
 }
 return hit;
}
__device__ float4 traceCorals(float3 ro,float3 rd,const float* Shrubs,float limit,float cone){
 float t=0;float4 result=make_float4(limit,0,0,-1);
 int ix=(int)floorf(ro.x/2.4f),iz=(int)floorf(ro.z/2.4f),sx=rd.x>=0?1:-1,sz=rd.z>=0?1:-1;
 float tx=fabsf(rd.x)>.000001f?(((float)ix+(sx>0?1:0))*2.4f-ro.x)/rd.x:100000;
 float tz=fabsf(rd.z)>.000001f?(((float)iz+(sz>0?1:0))*2.4f-ro.z)/rd.z:100000;
 float dtx=2.4f/fmaxf(.000001f,fabsf(rd.x)),dtz=2.4f/fmaxf(.000001f,fabsf(rd.z));
 // Increment integer cells explicitly: a sub-ULP epsilon cannot cross a far-world boundary.
 int budget=(int)fminf(192,ceilf(limit*(fabsf(rd.x)+fabsf(rd.z))/2.4f)+3);
 for(int step=0;step<budget;step++){
  if(t>=result.x)break;float end=fminf(result.x,fminf(tx,tz));
  #pragma unroll 1
  for(int oz=-1;oz<=1;oz++)for(int ox=-1;ox<=1;ox++){
  int cx=ix+ox-(int)roundf(Shrubs[REEF_CACHE]/2.4f),cz=iz+oz-(int)roundf(Shrubs[REEF_CACHE+1]/2.4f);
  if(cx>=0&&cz>=0&&cx<160&&cz<160){int c=CORAL_CACHE+(cz*160+cx)*8;float size=Shrubs[c+3];
   if(size>.05f){float3 root=make_float3(Shrubs[c],Shrubs[c+1],Shrubs[c+2]);
    float2 box=boxRay(ro,rd,root+make_float3(-1.35f*size,-.2f, -1.35f*size),root+make_float3(1.35f*size,3.1f*size,1.35f*size));
    if(box.y>fmaxf(0,box.x)&&box.x<result.x){float start=fmaxf(0,box.x-.01f);float4 h=coralGeometry((ro+rd*start-root)/size,rd,Shrubs[c+4],Shrubs[c+5],(result.x-start)/size,cone*fmaxf(1,t)/size);
     float distance=start+h.x*size;
     if(h.y*h.y+h.z*h.z+h.w*h.w>.5f&&distance<result.x){result=make_float4(distance,h.y,h.z,h.w);}}
   }
  }
  }
  if(tx<tz){t=tx;tx+=dtx;ix+=sx;}else{t=tz;tz+=dtz;iz+=sz;}
 }
 return result;
}
__device__ float3 specimenRoot(const int* Origin){return make_float3(4377-(float)Origin[0]*CELL,-10,2817-(float)Origin[1]*CELL);}
__device__ float4 traceSpecimen(float3 ro,float3 rd,const int* Origin,float limit,float study,float cone){
 float4 result=make_float4(limit,0,0,0);int count=study>1.5f?3:1;
 #pragma unroll 1
 for(int member=0;member<count;member++){
  float3 root=specimenRoot(Origin);float scale=count==1?2.2f:1.65f;
  if(count>1)root.x+=((float)member-1)*3.6f;
  float seed=member==0?.173f:(member==1?.397f:.681f);
  seed=fractf(seed+hash2(member,0,(unsigned int)Origin[2]+3121u)-hash2(member,0,4005u));
  float2 bounds=boxRay(ro,rd,root+make_float3(-3,-.2f,-3),root+make_float3(3,3,3));
  if(bounds.y<0||bounds.x>result.x)continue;
  float start=fmaxf(0,bounds.x-.01f),fp=cone*fmaxf(1,start)/scale;
  float4 h=coralGeometry((ro+rd*start-root)/scale,rd,count==1?-1:0,seed,(result.x-start)/scale,fp);
  if(h.y*h.y+h.z*h.z+h.w*h.w<.5f)continue;
  result=make_float4(start+h.x*scale,h.y,h.z,h.w);
 }
 return result;
}
__global__ void tracePrimary(const float* C,const int* Origin,const float* Waves,const float* Shrubs,float* Hit,float* Surface,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height);float cone=1.05f/(float)height;
 if((C[14]>.5f&&C[14]<2.5f)){
  float t=150,material=6;float3 n=make_float3(0,1,0);
  if(rd.y<-.0001f){float floorHit=(-10.12f-ro.y)/rd.y;if(floorHit>0&&floorHit<t){t=floorHit;material=8;}}
  float4 rock=coralEllipsoid(ro,rd,specimenRoot(Origin)+make_float3(0,-.1f,0),make_float3(.8f,.28f,.7f),make_float4(t,0,0,0));
  if(rock.x<t){t=rock.x;material=8;n=make_float3(rock.y,rock.z,rock.w);}
  Hit[b]=t;Hit[b+1]=material;Hit[b+2]=fmaxf(.002f,t*cone);Hit[b+3]=0;
  Surface[b]=n.x;Surface[b+1]=n.y;Surface[b+2]=n.z;Surface[b+3]=0;return;
 }
 // Diving uses the same CUDA terrain, now including the connected ocean floor.
 if(C[14]>=3?C[28]>.5f:ro.y<0){
  float wt=-1;if(rd.y>.0001f){wt=-ro.y/rd.y;for(int k=0;k<4;k++){float3 q=ro+rd*wt;float4 wave=ocean(q.x,q.z,fmaxf(.12f,wt*cone),Waves,Origin);wt=fmaxf(.01f,(wave.x-ro.y)/rd.y);}}
  float limit=wt>0?fminf(150,wt):150,bt=traceReef(ro,rd,Origin,Shrubs,limit);
  float t=bt>0?bt:(wt>0&&wt<150?wt:150),material=bt>0?4:(wt>0&&wt<150?5:6),fp=fmaxf(.03f,t*cone);
  float3 n=make_float3(0,1,0);if(material==4)n=reefNormal(ro+rd*t,Origin,Shrubs,fp);
  if(material==5){float3 q=ro+rd*t;float4 w=ocean(q.x,q.z,fp,Waves,Origin);n=norm3(make_float3(-w.y,1,-w.z));}
  Hit[b]=t;Hit[b+1]=material;Hit[b+2]=fp;Hit[b+3]=0;Surface[b]=n.x;Surface[b+1]=n.y;Surface[b+2]=n.z;Surface[b+3]=0;return;
 }
 float wt=waterHit(ro,rd,cone,C[6],Waves,Origin),lt=traceLandCached(ro,rd,Origin,wt>0?wt+3:FAR,cone,Shrubs);
 float t=FAR,material=0,fp=0,variance=0,depth=0;float3 n=make_float3(0,1,0);
 if(lt>0&&(wt<0||lt<wt)){t=lt;material=1;fp=fmaxf(.2f,t*cone);n=groundNormal(ro+rd*t,Origin,fp);fp=fmaxf(.005f,t*cone/fmaxf(.2f,fabsf(dot3(n,rd))));}
 else if(wt>0){t=wt;material=2;fp=fmaxf(.12f,t*cone/fmaxf(.08f,-rd.y));float3 p=ro+rd*t;float4 w=ocean(p.x,p.z,fp,Waves,Origin);n=norm3(make_float3(-w.y,1,-w.z));variance=w.w;depth=fmaxf(0,p.y-ground(p.x,p.z,Origin,fp));}
 Hit[b]=t;Hit[b+1]=material;Hit[b+2]=fp;Hit[b+3]=variance;Surface[b]=n.x;Surface[b+1]=n.y;Surface[b+2]=n.z;Surface[b+3]=depth;
}
// Keep the foliage loops out of the terrain/water traversal pipeline. This also
// makes vegetation work a separate bounded dispatch with the existing hit buffers.
__global__ void traceVegetation(const float* C,const int* Origin,const float* Shrubs,float* Hit,float* Surface,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height);float cone=1.05f/(float)height;
 if(C[14]>=3?C[28]>.5f:ro.y<0){
  float4 coral=(C[14]>.5f&&C[14]<2.5f)?traceSpecimen(ro,rd,Origin,Hit[b],C[14],cone):traceCorals(ro,rd,Shrubs,Hit[b],cone);
  if(coral.x<Hit[b]){
   float3 p=ro+rd*coral.x;Hit[b]=coral.x;Hit[b+1]=7;Hit[b+2]=fmaxf(.002f,coral.x*cone);Hit[b+3]=(C[14]>.5f&&C[14]<2.5f)?.12f:bedNoise(p.x,p.z,24,Origin,2121u);
   Surface[b]=coral.y;Surface[b+1]=coral.z;Surface[b+2]=coral.w;Surface[b+3]=0;
  }
 }else{
 float4 shrub=traceShrubs(ro,rd,Origin,Shrubs,Hit[b],C[5],C[6],cone);
 if(shrub.x<Hit[b]){Hit[b]=shrub.x;Hit[b+1]=3;Hit[b+2]=fmaxf(.005f,shrub.x*cone);Hit[b+3]=0;Surface[b]=shrub.y;Surface[b+1]=shrub.z;Surface[b+2]=shrub.w;Surface[b+3]=0;}
 }
 ShipHit ship=traceShip(ro,rd,Origin,C[5],Hit[b],cone,C);
 if(ship.part>0){Hit[b]=ship.t;Hit[b+1]=9;Hit[b+2]=fmaxf(.002f,ship.t*cone);Hit[b+3]=ship.part;Surface[b]=ship.nx;Surface[b+1]=ship.ny;Surface[b+2]=ship.nz;Surface[b+3]=0;}
}
// Trace each visible water pixel using its own normal; no half-resolution cells.
__global__ void reflectOcean(const float* C,const int* Origin,const float* Shrubs,const float* Hit,const float* Surface,float* Reflection,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;
 int px=x,py=y,b=(y*width+x)*4,o=b;
 Reflection[o]=0;Reflection[o+1]=0;Reflection[o+2]=0;Reflection[o+3]=-1;
 if(Hit[b+1]!=2||C[9]<.5f||Hit[b]>6500)return;
 float3 n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),rd=cameraRay(C,px,py,width,height),sun=sunDirection(C);
 float3 rr=rd-n*(2*dot3(rd,n)),ro=make_float3(C[0],C[1],C[2])+rd*Hit[b]+n*.3f;
 float3 reflected=weatherSky(ro,rr,sun,C[5],C[15],Origin,0);float cone=1.05f/(float)height,rt=traceLandCached(ro,rr,Origin,6500,cone,Shrubs);
 if(rt>0){float3 p=ro+rr*rt;float fp=fmaxf(.5f,(Hit[b]+rt)*cone);float3 ln=groundNormal(p,Origin,fp);float shadow=terrainShadow(p+ln*.4f,sun,Origin,fp);float3 land=shrubGround(landColor(p,ln,sun,Origin,fp),p,ln,sun,Origin,Shrubs,fp,Hit[b]+rt)*shadow;
 land=wetSandSheen(land,p,ln,rr,sun,Origin,fp,shadow);land=aerialPerspective(land,ro,rr,rt,sun);reflected=mix3(land,reflected,smoothf(4800,6500,Hit[b]));}
 if(Hit[b]<180){float4 shrub=traceShrubs(ro,rr,Origin,Shrubs,rt>0?rt:6500,C[5],C[6],cone);
  if(shrub.x<(rt>0?rt:6500)){float3 p=ro+rr*shrub.x,ln=make_float3(shrub.y,shrub.z,shrub.w);reflected=aerialPerspective(shrubColor(p,ln,rr,sun,Origin,Shrubs,fmaxf(.005f,(Hit[b]+shrub.x)*cone)),ro,rr,shrub.x,sun);}}
 ShipHit ship=traceShip(ro,rr,Origin,C[5],rt>0?rt:6500,fmaxf(cone,.004f),C);
 if(ship.part>0){float3 p=ro+rr*ship.t,ln=make_float3(ship.nx,ship.ny,ship.nz);reflected=aerialPerspective(shipShade(p,ln,rr,sun,ship.part,fmaxf(.02f,(Hit[b]+ship.t)*cone),Origin,C[5],C),ro,rr,ship.t,sun);}
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
 float stillDepth=fmaxf(0,depth-p.y),shore=1-smoothf(.35f,1.35f+wind*.35f,stillDepth);
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
// Reef material and structure share the same seeded colony descriptor. The
// palette belongs to a garden, with fine structure filtered by pixel footprint.
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
 return (focus-1)*.22f*expf(-depth*.10f)*smoothf(.05f,.8f,depth)*(1-smoothf(10,16,depth))*weight(fp,.45f)*smoothf(0,.35f,sun.y);
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
__device__ float3 underwaterShade(float3 ro,float3 rd,float3 p,float3 n,float t,float material,float fp,float3 sun,float clarity,const int* Origin,const float* Waves,const float* Shrubs,float palette,float study){
 float3 haze=make_float3(.018f,.18f,.25f)*(.45f+.55f*sat(sun.y))*expf(-fmaxf(0,-ro.y-5)*.016f);
 float3 color=haze;
 if(material==4||material==7||material==8){
  if(material==7){
   float3 local=make_float3(p.x-floorf(p.x/12)*12,p.y,p.z-floorf(p.z/12)*12);
   float e=.003f,bump=surfaceNoise(local,n,70);
   float3 gradient=make_float3(surfaceNoise(local+make_float3(e,0,0),n,70)-bump,surfaceNoise(local+make_float3(0,e,0),n,70)-bump,surfaceNoise(local+make_float3(0,0,e),n,70)-bump)/e;
   n=norm3(n-(gradient-n*dot3(gradient,n))*(.005f*weight(fp,70)));
  }
  float depth=fmaxf(0,-p.y),nl=sat(dot3(n,sun));
  float3 sunlight=waterTransmission(sunWaterPath(depth,sun.y)*.35f/clarity);
  float caustic=seabedCaustic(p,depth,fp,sun,Waves,Origin);
  float4 tex=make_float4(0,.19f,.22f,.20f);if(material==4)tex=reefSample(p.x,p.z,Origin,Shrubs);
  float grain=.78f+.32f*noise2((p.x-floorf(p.x/12)*12)*27,(p.z-floorf(p.z/12)*12)*27);
  float3 albedo=make_float3(tex.y,tex.z,tex.w)*lerpf(1,grain,weight(fp,12));
  if(material==8)albedo=make_float3(.19f,.22f,.20f)*grain;
  float shadow=1;
  if(material==7){
   albedo=make_float3(.66f,.30f,.075f);
   if(palette<.22f)albedo=make_float3(.64f,.12f,.27f);
   else if(palette<.44f)albedo=make_float3(.28f,.18f,.54f);
   else if(palette<.65f)albedo=make_float3(.055f,.42f,.48f);
   else if(palette<.82f)albedo=make_float3(.48f,.51f,.12f);
   float polyps=surfaceNoise(make_float3(p.x-floorf(p.x/12)*12,p.y,p.z-floorf(p.z/12)*12),n,32);
   albedo=albedo*lerpf(1,.55f+polyps*.85f,weight(fp,32));
   if(study>.5f)albedo=mix3(albedo,make_float3(.88f,.65f,.73f),smoothf(-8.9f,-7.55f,p.y)*.85f);
   float4 occluder=study>.5f?traceSpecimen(p+n*.025f,sun,Origin,6,study,fmaxf(.018f,fp)):traceCorals(p+n*.025f,sun,Shrubs,6,.01f);shadow=occluder.x<6?.22f:1;
  }
  if(material==8&&study>.5f){float4 shade=traceSpecimen(p+n*.025f,sun,Origin,8,study,fmaxf(.018f,fp));shadow=shade.x<8?.25f:1;}
  color=albedo*(make_float3(.12f,.19f,.22f)+sunRadiance(sun)*sunlight*(.38f*nl*shadow))*(1+caustic);
 }else if(material==5){
  float cosine=sat(dot3(rd,n)),eta=1.333f,k=1-eta*eta*(1-cosine*cosine);
  if(k>0){float3 air=norm3(rd*eta+n*(sqrtf(k)-eta*cosine));float fresnel=.02037f+.97963f*powf(1-cosine,5);color=mix3(sky(air,sun),haze*1.7f,fresnel);}
  else color=haze*(1.4f+.5f*sat(n.y));
 }
 float3 transmission=waterTransmission(t*.35f/clarity);
 // Water-column scattering plus a smooth optical horizon conceals the finite cache.
 float scatter=expf(-t*(.013f+fmaxf(0,-ro.y)*.00025f)/clarity)*(1-smoothf(95,150,t));
 transmission=transmission*scatter;
 return color*transmission+haze*(make_float3(1,1,1)-transmission);
}
__global__ void shadeOcean(const float* C,const int* Origin,const float* Shrubs,const float* Hit,const float* Surface,const float* Reflection,const float* Waves,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float t=Hit[b],material=Hit[b+1],fp=Hit[b+2];float3 p=ro+rd*t,n=make_float3(Surface[b],Surface[b+1],Surface[b+2]),color=make_float3(0,0,0);
 // Sky/cloud evaluation is only needed when it survives the material branch.
 if(material==0)color=weatherSky(ro,rd,sun,C[5],C[15],Origin,1);
 if(material==1){float shadow=terrainShadow(p+n*.4f,sun,Origin,fp)*shrubContact(p,Origin,Shrubs,fp);color=shrubGround(landColor(p,n,sun,Origin,fp),p,n,sun,Origin,Shrubs,fp,t)*shadow;color=wetSandSheen(color,p,n,rd,sun,Origin,fp,shadow);}
 if(material==3){color=shrubColor(p,n,rd,sun,Origin,Shrubs,fp)*terrainShadow(p+make_float3(0,.1f,0),sun,Origin,fp);n=norm3(make_float3(-rd.x,.6f,-rd.z));}
 if(material==2){
  float nv=sat(-dot3(n,rd)),fresnel=waterFresnel(nv);float3 rr=rd-n*(2*dot3(rd,n)),reflected=make_float3(0,0,0);
  if(C[9]>.5f&&t<6500&&Reflection[b+3]>0)reflected=filteredReflection(x,y,width,height,Hit,Surface,Reflection);
  else reflected=weatherSky(p,rr,sun,C[5],C[15],Origin,0);
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
  float bedLight=.24f+.76f*sat(sun.y);if(detail>0&&t<600)bedLight=.24f+.76f*sat(dot3(groundNormal(bp,Origin,fmaxf(.1f,fp)),sun));float caustic=C[13]>.5f?seabedCaustic(bp,bedDepth,fp,sun,Waves,Origin):0;
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
  if(C[14]>=3){float dx=p.x-C[16],dz=p.z-C[18],along=dx*sinf(C[19])+dz*cosf(C[19]),side=dx*cosf(C[19])-dz*sinf(C[19]);float spray=expf(-powf(fabsf(side)-5,2)*.09f-along*along*.002f);foam=fmaxf(foam,sat(spray*(Waves[1398121]*.3f+fabsf(C[24])*.018f)*(1-smoothf(2,10,fabsf(C[17])))));}
  float3 foamLight=make_float3(.18f,.23f,.26f)+sunRadiance(sun)*((.23f*sat(sun.y)+.04f)*beamShadow);
  color=mix3(color,foamLight,foam);
 }
 if(material==9){color=shipShade(p,n,rd,sun,Hit[b+3],fp,Origin,C[5],C);if(C[14]>=3?C[28]>.5f:ro.y<0)color=mix3(make_float3(.015f,.16f,.19f),color,expf(-t*.035f));}
 if(material>=4&&material<=8)color=underwaterShade(ro,rd,p,n,t,material,fp,sun,C[12]>0?C[12]:1,Origin,Waves,Shrubs,Hit[b+3],C[14]<3?C[14]:0);
 else if(material>0&&!(C[14]>=3?C[28]>.5f:ro.y<0))color=aerialPerspective(color,ro,rd,t,sun);
 // Dim ambient surface terms at night; direct sunlight already follows the sun.
 if(material>0&&(C[14]<.5f||C[14]>=3)){
  float day=smoothf(-.18f,.06f,sun.y);color=color*lerpf(.025f,1,day);
  if(day<1){
  float3 moon=make_float3(-sun.x,-sun.y,-sun.z);
  float cover=weatherAt(p.x,p.z,C[5],C[15],Origin).x;
  float moonlight=(1-day)*sat(moon.y)*(1-cover*.85f);
  color=color+make_float3(.004f,.007f,.012f)*(moonlight*(.25f+.75f*sat(dot3(n,moon))));
  if(material==2)color=color+make_float3(.018f,.024f,.036f)*(moonlight*waterSunLobe(n,rd,moon,Hit[b+3],C[6]));
  }
 }
 // Local weather changes with world position; rain is composited only in front
 // of the already-known visible hit. Impacts reuse that hit, never trace collisions.
 if(C[15]>=0&&(C[14]<.5f||C[14]>=3)){
  float4 local=weatherAt(ro.x,ro.z,C[5],C[15],Origin);
  if(material>0&&material<4){
   float4 w=weatherAt(p.x,p.z,C[5],C[15],Origin);
   color=color*(1-w.x*.30f-w.z*.30f);
   if(material==1||material==3){
    float wet=w.w*smoothf(.1f,.9f,n.y);color=color*(1-wet*.30f);
    float3 rr=rd-n*(2*dot3(rd,n));
    float sheen=wet*(.012f+.09f*powf(1-sat(-dot3(rd,n)),5));
    color=mix3(color,weatherSky(p,rr,sun,C[5],C[15],Origin,0),sheen);
   }
   if((material==1||material==2)&&t<160&&n.y>.4f){float impact=rainImpact(p,fp,C[5],w.y,Origin);color=color+make_float3(.055f,.070f,.085f)*impact;}
   float fog=1-expf(-t*local.y*.00028f);color=mix3(color,make_float3(.17f,.22f,.28f)*lerpf(.015f,1,smoothf(-.18f,.06f,sun.y)),fog);
  }
  if(C[14]>=3?C[28]<.5f:ro.y>=0){
   float drops=rainVisibility(ro,rd,t,1.05f/(float)height,C[5],local.y,Origin);
   color=mix3(color,make_float3(.55f,.65f,.75f)*lerpf(.025f,1,smoothf(-.18f,.06f,sun.y)),drops);
   float flash=weatherFlash(ro.x,ro.z,C[5],local.z,Origin);color=color+make_float3(.35f,.40f,.52f)*flash;if(material==0)color=color+weatherBolt(ro,rd,C[5],local.z,Origin);
  }else if(material>=4)color=color*(1-local.x*.18f-local.z*.25f);
 }
 // Bounded spray volume: water-entry impulse lifts a broken white curtain.
 if(C[14]>=3&&Waves[1398121]>.15f&&C[28]<.5f){
  float strength=Waves[1398121],sprayHeight=fminf(24,3+strength*2),alpha=0;
  float3 centre=make_float3(C[16],0,C[18]);float2 bounds=boxRay(ro-centre,rd,make_float3(-24,0,-32),make_float3(24,sprayHeight,32));
  float begin=fmaxf(.02f,bounds.x),end=fminf(t,bounds.y);
  if(end>begin)for(int k=0;k<12;k++){float at=lerpf(begin,end,((float)k+.5f)/12);float3 q=ro+rd*at-centre;
   float side=q.x*cosf(C[19])-q.z*sinf(C[19]),along=q.x*sinf(C[19])+q.z*cosf(C[19]);
   float radius=5+q.y*.35f,curtain=expf(-powf(fabsf(side)-radius,2)*.6f-along*along*.0025f)*(1-smoothf(sprayHeight*.4f,sprayHeight,q.y));
   float drops=smoothf(.43f,.72f,noise2(q.x*4+q.z*2,q.y*6-C[5]*15));alpha+=curtain*drops*(end-begin)/12*.17f*sat(strength*.3f);
  }
  color=mix3(color,make_float3(.45f,.57f,.62f)*( .35f+.65f*sat(sun.y)),1-expf(-alpha));
 }
 if(C[10]==1&&material>0){float level=log2f(fmaxf(1,fp));color=mix3(make_float3(.1f,.8f,.6f),make_float3(.9f,.25f,.12f),sat(level/6));}
 if(C[10]==2&&material>0)color=(n+make_float3(1,1,1))*.5f;
 color=color*C[11];color=make_float3(linearToDisplay(color.x),linearToDisplay(color.y),linearToDisplay(color.z));Pixels[y*width+x]=pack(color);
}
__global__ void probeWorld(const float* Points,const int* Origin,const float* Waves,float* Result,int count){
 int i=(int)(blockIdx.x*blockDim.x+threadIdx.x);if(i>=count)return;int b=i*4;
 float x=Points[b],z=Points[b+1],fp=Points[b+2];Result[b]=ground(x,z,Origin,fp);float4 w=ocean(x,z,fp,Waves,Origin);Result[b+1]=w.x;Result[b+2]=w.y;Result[b+3]=w.w;
}

// Persistent local wave equation: two 128x128 height/velocity banks, 2m spacing.
// Each invocation reads only the old bank, avoiding inter-workgroup races.
__global__ void stepShipWater(const float* C,float* Waves){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),z=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=128||z>=128)return;
 int bank=(int)Waves[1398107],old=1-bank,ox=x+(int)Waves[1398110],oz=z+(int)Waves[1398111];float dt=Waves[1398112],h=0,v=0,lap=0;
 if(Waves[1398116]<.5f){h=wakeCell(Waves,old,ox,oz,0);v=wakeCell(Waves,old,ox,oz,1);lap=(wakeCell(Waves,old,ox+1,oz,0)+wakeCell(Waves,old,ox-1,oz,0)+wakeCell(Waves,old,ox,oz+1,0)+wakeCell(Waves,old,ox,oz-1,0)-4*h)*.25f;}
 float px=Waves[1398108]+(float)x*2-C[16],pz=Waves[1398109]+(float)z*2-C[18],sx=sinf(C[19]),sz=cosf(C[19]);
 float side=px*sz-pz*sx,along=px*sx+pz*sz;
 float mask=expf(-side*side*.10f-along*along*.004f),contact=1-smoothf(2,9,fabsf(C[17]));
 float target=-(2.4f+fminf(2,fabsf(C[24])*.04f))*mask*contact;
 float ring=expf(-powf(fabsf(side)-5,2)*.22f-along*along*.003f);
 v+=Waves[1398121]*(ring-mask*.7f)*dt*18;
 v=(v+(64*lap+(target-h)*mask*contact*18)*dt)*expf(-dt*.65f);
 h=clampf(h+v*dt,-5,6);float edge=smoothf(0,10,(float)x)*smoothf(0,10,(float)z)*(1-smoothf(117,127,(float)x))*(1-smoothf(117,127,(float)z));
 int i=1398144+bank*32768+(z*128+x)*2;Waves[i]=h*edge;Waves[i+1]=clampf(v,-24,24)*edge;
}
// Conservative samples across the rotated hull's keel and lower sides.
__device__ float shipTerrainFloor(float x,float z,const float* C,const int* Origin){
 float floorHeight=-10000;
 for(int iz=0;iz<11;iz++){float along=-18+(float)iz*3.8f;
  for(int side=-1;side<=1;side++){float3 q=shipRotate(make_float3((float)side*shipBeam(along)*.9f,-3.3f+.10f*fabsf(along),along),C[5],-1,C);
   floorHeight=fmaxf(floorHeight,ground(x+q.x,z+q.z,Origin,.5f)-q.y+.3f);
  }
 }return floorHeight;
}
// One invocation per frame, after the ocean FFT. No wave readback or per-pixel buoyancy.
// C[16..19]: ship x / clearance above water / z / heading.
// C[20..22]: wave roll / pitch / height. C[23]: chase distance. C[14]==3 enables helm.
__global__ void updateShip(float* C,const int* Origin,float* Waves){
 Waves[1398099]=0;
 if(C[14]<3)return;
 float x=C[16],z=C[18],yaw=C[19],sx=sinf(yaw),sz=cosf(yaw);
 float front=ocean(x+sx*13,z+sz*13,4,Waves,Origin).x,back=ocean(x-sx*13,z-sz*13,4,Waves,Origin).x;
 float left=ocean(x-sz*3.8f,z+sx*3.8f,4,Waves,Origin).x,right=ocean(x+sz*3.8f,z-sx*3.8f,4,Waves,Origin).x;
 float wet=1-smoothf(0,5,fabsf(C[17]));
 C[20]=clampf((right-left)/7.6f,-.18f,.18f)*wet;
 C[21]=clampf((back-front)/26,-.15f,.15f)*wet-C[25];
 float waveHeight=(front+back+left+right)*.25f*wet;
 float response=1-expf(-clampf(C[5]-Waves[1398113],0,.1f)*3);
 if(Waves[1398106]>.5f&&C[5]>=Waves[1398113]){waveHeight=lerpf(Waves[1398122],waveHeight,response)*wet;C[20]=lerpf(Waves[1398123],C[20],response)*wet;}
 Waves[1398122]=waveHeight;Waves[1398123]=C[20];C[22]=waveHeight+C[17];
 // Sweep in short intervals, then clamp descent to the supporting seabed.
 float waveOffset=C[22]-C[17],startX=C[26]>0?C[29]:x,startZ=C[26]>0?C[31]:z,startY=C[26]>0?C[30]+waveOffset:C[22];
 float mx=x-startX,mz=z-startZ,length=sqrtf(mx*mx+mz*mz);int steps=(int)clampf(ceilf(length/2),1,128);
 float travel=fminf(1,256/fmaxf(1,length));float safeX=startX,safeZ=startZ;
 for(int step=1;step<=128;step++){if(step>steps)break;float f=(float)step/(float)steps*travel,tx=startX+mx*f,tz=startZ+mz*f,ty=lerpf(startY,C[22],f);
  float floorHeight=shipTerrainFloor(tx,tz,C,Origin);
  if(length>.01f&&floorHeight>ty+.15f){C[24]=0;break;}safeX=tx;safeZ=tz;
 }
 x=safeX;z=safeZ;C[16]=x;C[18]=z;C[22]=fmaxf(C[22],shipTerrainFloor(x,z,C,Origin));C[17]=C[22]-waveOffset;
 // Camera follows the water height but stays level while the hull rolls.
 Waves[1398099]=1;Waves[1398100]=x;Waves[1398101]=z;Waves[1398102]=yaw;Waves[1398103]=C[24];Waves[1398104]=C[17];Waves[1398105]=C[5];
 if(C[14]==3){
 float distance=fmaxf(40,C[23]);C[4]=clampf(C[4],-1.1f,1.1f);
 C[0]=x-sinf(C[3])*cosf(C[4])*distance;
 C[1]=C[22]+10-sinf(C[4])*distance;
 C[2]=z-cosf(C[3])*cosf(C[4])*distance;
 }
 C[28]=C[1]<ocean(C[0],C[2],1,Waves,Origin).x?1:0;
 float bx=floorf(x/2)*2-128,bz=floorf(z/2)*2-128;
 float dx=(bx-Waves[1398108]+((float)Origin[0]-Waves[1398114])*CELL)/2,dz=(bz-Waves[1398109]+((float)Origin[1]-Waves[1398115])*CELL)/2;
 float reset=Waves[1398106]<.5f||C[5]<Waves[1398113]||fabsf(dx)>100||fabsf(dz)>100||Waves[1398117]!=(float)Origin[2]?1:0;
 float impactDt=clampf(C[5]-Waves[1398113],.001f,.1f),contact=1-smoothf(0,5,C[17]);
 float entry=reset>.5f?0:fmaxf(0,contact-Waves[1398120])/impactDt;
 Waves[1398121]=fmaxf(reset>.5f?0:Waves[1398121]*expf(-impactDt*2.8f),clampf(entry*.7f,0,12));Waves[1398120]=contact;
 Waves[1398112]=clampf(C[5]-Waves[1398113],0,.04f);Waves[1398113]=C[5];Waves[1398116]=reset;
 Waves[1398110]=dx;Waves[1398111]=dz;Waves[1398114]=(float)Origin[0];Waves[1398115]=(float)Origin[1];Waves[1398117]=(float)Origin[2];
 Waves[1398108]=bx;Waves[1398109]=bz;Waves[1398107]=1-Waves[1398107];Waves[1398106]=1;
}
