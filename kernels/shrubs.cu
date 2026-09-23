// Stateless six-metre vegetation cells. Canopies remain inside their own cells,
// so a ray visits only the cells it crosses; no world-sized instance list exists.
struct Shrub {float3 root;float size;float seed;};
__device__ Shrub describeShrub(int ix,int iz,const int* Origin){
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*800u;
 unsigned int gz=(unsigned int)iz+(unsigned int)Origin[1]*800u;
 unsigned int seed=(unsigned int)Origin[2]+971u;
 Shrub s;s.seed=hash2((int)gx,(int)gz,seed);s.size=0;
 int cx=(int)floorf((float)ix/800),cz=(int)floorf((float)iz/800);
 s.root=make_float3(((float)(ix-cx*800)+.5f)*6,0,((float)(iz-cz*800)+.5f)*6);
 if(s.seed<.42f)return s;
 s.root.x+=(hash2((int)gx,(int)gz,seed+1)-.5f)*2.4f;
 s.root.z+=(hash2((int)gx,(int)gz,seed+2)-.5f)*2.4f;
 int habitat[4]={Origin[0]+cx,Origin[1]+cz,Origin[2],0};
 Island a=describeIsland(0,0,habitat);
 s.root.y=islandHeight(s.root.x,s.root.z,a,.2f);
 float3 local=s.root;s.root.x+=(float)cx*CELL;s.root.z+=(float)cz*CELL;
 if(s.root.y<4.5f||s.root.y>155)return s;
 float dx=islandHeight(local.x-.4f,local.z,a,.5f)-islandHeight(local.x+.4f,local.z,a,.5f);
 float dz=islandHeight(local.x,local.z-.4f,a,.5f)-islandHeight(local.x,local.z+.4f,a,.5f);
 float ny=.8f/sqrtf(.64f+dx*dx+dz*dz);if(ny<.86f)return s;
 float patch=noise2((local.x-a.x)/38+a.seed,(local.z-a.z)/38);
 if(patch<.38f||s.seed<lerpf(.72f,.42f,smoothf(5,18,s.root.y)))return s;
 s.size=.75f+hash2((int)gx,(int)gz,seed+3)*.65f;
 return s;
}
// A bounded 64 KiB patch replaces habitat evaluation in every viewing ray.
__global__ void cacheShrubs(const float* C,const int* Origin,float* Shrubs){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),z=(int)(blockIdx.y*blockDim.y+threadIdx.y);
 if(x>=64||z>=64)return;
 int bx=(int)floorf(C[0]/6)-32,bz=(int)floorf(C[2]/6)-32;
 if(x==0&&z==0){Shrubs[0]=(float)bx;Shrubs[1]=(float)bz;Shrubs[2]=ground(C[0],C[2],Origin,1);Shrubs[3]=0;}
 Shrub s=describeShrub(bx+x,bz+z,Origin);int b=4+(z*64+x)*4;
 Shrubs[b]=s.root.x;Shrubs[b+1]=s.root.y;Shrubs[b+2]=s.root.z;Shrubs[b+3]=s.size;
}
__device__ Shrub cachedShrub(int ix,int iz,const int* Origin,const float* Shrubs){
 Shrub s;s.root=make_float3(0,0,0);s.size=0;s.seed=0;
 int x=ix-(int)Shrubs[0],z=iz-(int)Shrubs[1];if(x<0||z<0||x>=64||z>=64)return s;
 int b=4+(z*64+x)*4;s.root=make_float3(Shrubs[b],Shrubs[b+1],Shrubs[b+2]);s.size=Shrubs[b+3];
 unsigned int gx=(unsigned int)ix+(unsigned int)Origin[0]*800u,gz=(unsigned int)iz+(unsigned int)Origin[1]*800u;
 s.seed=hash2((int)gx,(int)gz,(unsigned int)Origin[2]+971u);return s;
}
// Eight 128px tiles: four side views and matching overhead crowns. Premultiplied
// RGBA and all eight mip levels live after the bounded habitat cache (2.73 MiB).
#define REEF_CACHE 715428
#define CORAL_CACHE 4909736
#define SHRUB_FLOATS 5114536
__device__ int shrubTexel(int tile,int level,int x,int y){
 int n=128>>level;return 16388+(tile*21845+(16384-n*n)*4/3+y*n+x)*4;
}
__global__ void generateShrubAtlas(float* Shrubs){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),tile=(int)blockIdx.z;
 if(x>=128||y>=128||tile>=8)return;
 float u=((float)x+.5f)/128,v=((float)y+.5f)/128,alpha=0;float3 color=make_float3(0,0,0);
 int variant=tile%4;
 // The same seeded 3D leaf positions are projected into side/overhead textures.
 int leaves=180+variant*19;
 for(int k=0;k<leaves;k++){
  float angle=hash2(k,variant,712)*2*PI,r=sqrtf(hash2(k,variant,713))*.37f;
  float lx=.5f+cosf(angle)*r,lz=.5f+sinf(angle)*r;
  float ly=.19f+hash2(k,variant,714)*.61f*(1-r*.8f);
  float cx=lx,cy=tile<4?ly:lz;
  float a=hash2(k,variant,715)*PI,dx=u-cx,dy=v-cy;
  float xx=(dx*cosf(a)+dy*sinf(a))/.038f,yy=(-dx*sinf(a)+dy*cosf(a))/.015f;
  float mask=1-smoothf(.75f,1.2f,xx*xx+yy*yy);
  float shade=.6f+hash2(k,variant,716)*.7f;
  float3 leaf=mix3(make_float3(.040f,.085f,.020f),make_float3(.18f,.24f,.067f),hash2(k,variant,717))*shade;
  leaf=leaf*(1-.18f*expf(-yy*yy*80));
  color=color*(1-mask)+leaf*mask;alpha=alpha+(1-alpha)*mask;
 }
 if(tile<4){float stem=(1-smoothf(.008f,.016f,fabsf(u-.5f)))*(1-smoothf(.20f,.35f,v));
  color=color+make_float3(.13f,.085f,.04f)*(stem*(1-alpha));alpha=alpha+stem*(1-alpha);}
 int b=shrubTexel(tile,0,x,y);Shrubs[b]=color.x;Shrubs[b+1]=color.y;Shrubs[b+2]=color.z;Shrubs[b+3]=alpha;
}
__global__ void mipShrubAtlas(float* Shrubs,int level){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),tile=(int)blockIdx.z;
 int n=128>>level;if(x>=n||y>=n||tile>=8)return;
 int b=shrubTexel(tile,level,x,y),a=shrubTexel(tile,level-1,x*2,y*2),c=shrubTexel(tile,level-1,x*2,y*2+1);
 for(int k=0;k<4;k++)Shrubs[b+k]=(Shrubs[a+k]+Shrubs[a+4+k]+Shrubs[c+k]+Shrubs[c+4+k])*.25f;
}
__device__ float4 shrubTextureLevel(float u,float v,int tile,int level,const float* Shrubs){
 int n=128>>level;
 float xx=clampf(u*(float)n-.5f,0,(float)n-1),yy=clampf(v*(float)n-.5f,0,(float)n-1);
 int x=(int)xx,y=(int)yy,x1=(int)fminf((float)x+1,(float)n-1),y1=(int)fminf((float)y+1,(float)n-1);
 int a=shrubTexel(tile,level,x,y),b=shrubTexel(tile,level,x1,y),c=shrubTexel(tile,level,x,y1),d=shrubTexel(tile,level,x1,y1);
 float out[4];for(int k=0;k<4;k++)out[k]=lerpf(lerpf(Shrubs[a+k],Shrubs[b+k],xx-x),lerpf(Shrubs[c+k],Shrubs[d+k],xx-x),yy-y);
 return make_float4(out[0],out[1],out[2],out[3]);
}
__device__ float4 shrubTexture(float u,float v,int tile,float footprint,const float* Shrubs){
 float lod=clampf(log2f(fmaxf(1,footprint*128)),0,7);int level=(int)lod;
 float4 a=shrubTextureLevel(u,v,tile,level,Shrubs);
 if(level==7)return a;
 float4 b=shrubTextureLevel(u,v,tile,level+1,Shrubs);float t=lod-(float)level;
 return make_float4(lerpf(a.x,b.x,t),lerpf(a.y,b.y,t),lerpf(a.z,b.z,t),lerpf(a.w,b.w,t));
}
__device__ float shrubGroundBlend(float distance){return smoothf(65,125,distance);}
// Two crossed alpha-tested cards. Hit payload stores UV and tile, not a normal.
__device__ float4 hitShrub(float3 ro,float3 rd,Shrub s,const float* Shrubs,float limit,float time,float wind,float cone){
 float4 best=make_float4(limit,0,0,0);float3 q=ro-s.root;
 float distance=sqrtf(dot3(q,q)),coverage=1-shrubGroundBlend(distance);
 if(coverage<=0)return best;
 for(int plane=0;plane<2;plane++){
  float a=s.seed*PI+(float)plane*PI*.5f;float3 side=make_float3(cosf(a),0,sinf(a)),normal=make_float3(-sinf(a),0,cosf(a));
  float denom=dot3(rd,normal);if(fabsf(denom)<.001f)continue;
  float t=-dot3(q,normal)/denom;if(t<.02f||t>=best.x)continue;
  float3 p=q+rd*t;float v=p.y/(s.size*1.8f);
  float sway=sinf(time*1.3f+s.seed*53)*.035f*fminf(wind,2.5f)*v;
  float u=dot3(p,side)/(s.size*2.2f)+.5f-sway;
  if(u<0||u>1||v<0||v>1)continue;
  int tile=(int)(s.seed*4);float4 tex=shrubTexture(u,v,tile,cone*t/(s.size*1.8f),Shrubs);
  float threshold=hash2((int)(u*128),(int)(v*128),31u+(unsigned int)tile);
  if(tex.w*coverage>fmaxf(.08f,threshold))best=make_float4(t,u,v,(float)tile);
 }
 return best;
}
__device__ float4 traceShrubs(float3 ro,float3 rd,const int* Origin,const float* Shrubs,float limit,float time,float wind,float cone){
 float stop=fminf(limit,125),start=.02f;
 // Aerial/distant views use terrain coverage, avoiding a second full-world march.
 if(stop<=.02f||ro.y>165)return make_float4(limit,0,1,0);
 if(limit<220)start=fmaxf(.02f,limit-8/fmaxf(.08f,fabsf(rd.y)));
 float4 best=make_float4(limit,0,1,0);
 int budget=(int)fminf(64,ceilf(stop*(fabsf(rd.x)+fabsf(rd.z))/6)+3);
 for(int cell=0;cell<budget;cell++){
  if(start>=stop||start>=best.x)break;
  float3 p=ro+rd*start;int ix=(int)floorf(p.x/6),iz=(int)floorf(p.z/6);
  float tx=fabsf(rd.x)>1e-6f?(((float)ix+(rd.x>=0?1:0))*6-p.x)/rd.x:1e9f;
  float tz=fabsf(rd.z)>1e-6f?(((float)iz+(rd.z>=0?1:0))*6-p.z)/rd.z:1e9f;
  float end=fminf(stop,start+fmaxf(0,fminf(tx,tz)));
  Shrub s=cachedShrub(ix,iz,Origin,Shrubs);
  if(s.size>0){float2 bounds=boxRay(ro,rd,s.root+make_float3(-1.65f,-.1f,-1.65f),s.root+make_float3(1.65f,2.4f,1.65f));
   if(bounds.y>=start&&bounds.x<=end&&bounds.x<best.x){float4 hit=hitShrub(ro,rd,s,Shrubs,best.x,time,wind,cone);if(hit.x<best.x)best=hit;}}
  start=end+.001f;
 }
 return best;
}
__device__ float shrubContact(float3 p,const int* Origin,const float* Shrubs,float fp){
 if(p.y<4||p.y>157||fp>1)return 1;
 Shrub s=cachedShrub((int)floorf(p.x/6),(int)floorf(p.z/6),Origin,Shrubs);
 if(s.size==0)return 1;
 float dx=p.x-s.root.x,dz=p.z-s.root.z;
 return 1-.38f*expf(-(dx*dx+dz*dz)/(s.size*s.size*.55f))*weight(fp,1);
}
__device__ float3 shrubColor(float3 p,float3 uv,float3 rd,float3 sun,const int* Origin,const float* Shrubs,float fp){
 Shrub s=cachedShrub((int)floorf(p.x/6),(int)floorf(p.z/6),Origin,Shrubs);
 float4 tex=shrubTexture(uv.x,uv.y,(int)uv.z,fp/fmaxf(.1f,s.size*1.8f),Shrubs);
 float3 albedo=make_float3(tex.x,tex.y,tex.z)/fmaxf(.001f,tex.w);
 return albedo*(make_float3(.20f,.25f,.28f)+sunRadiance(sun)*(.20f+.13f*sat(sun.y)+.12f*powf(sat(dot3(rd,sun)),3)));
}
// Beyond the card range the exact same plants remain in the terrain material.
// At subpixel sizes integrate coverage instead of dropping vegetation altogether.
__device__ float3 shrubGround(float3 color,float3 p,float3 n,float3 sun,const int* Origin,const float* Shrubs,float fp,float distance){
 float blend=shrubGroundBlend(distance);if(blend<=0||p.y<4.5f||p.y>155||n.y<.86f)return color;
 int ix=(int)floorf(p.x/6),iz=(int)floorf(p.z/6);
 Shrub s=describeShrub(ix,iz,Origin);
 float4 tex=make_float4(0,0,0,0);
 if(s.size>0){float a=s.seed*PI,dx=p.x-s.root.x,dz=p.z-s.root.z;
  float u=(dx*cosf(a)+dz*sinf(a))/(s.size*2.2f)+.5f,v=(-dx*sinf(a)+dz*cosf(a))/(s.size*2.2f)+.5f;
  if(u>=0&&u<=1&&v>=0&&v<=1)tex=shrubTexture(u,v,4+(int)(s.seed*4),fp/(s.size*2.2f),Shrubs);
 }
 float filtered=smoothf(1.5f,6,fp);
 // Fully unresolved cells converge to habitat-weighted average crown coverage.
 Island island=describeIsland((int)floorf(p.x/CELL),(int)floorf(p.z/CELL),Origin);
 float patch=noise2((p.x-island.x)/38+island.seed,(p.z-island.z)/38);
 float density=smoothf(.35f,.45f,patch)*(.28f+.30f*smoothf(5,18,p.y))*.065f;
 float alpha=lerpf(tex.w,density,filtered)*blend;
 float3 albedo=mix3(make_float3(tex.x,tex.y,tex.z)/fmaxf(.001f,tex.w),make_float3(.085f,.14f,.035f),filtered);
 float3 lighting=make_float3(.20f,.25f,.28f)+sunRadiance(sun)*(.20f+.13f*sat(sun.y));
 return mix3(color,albedo*lighting,alpha);
}
