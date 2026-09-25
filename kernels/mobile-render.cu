// Mobile-only surface renderer. Deliberately excludes weather, reefs, shrubs,
// ships, secondary reflection rays, caustics and underwater material grammars.
// It keeps the same terrain cache and spectral ocean data as the full renderer.

__device__ float3 mobileSky(float3 rd,float3 sun){
 float h=sat(rd.y*.5f+.5f);
 float3 horizon=make_float3(.43f,.66f,.79f),zenith=make_float3(.075f,.23f,.43f);
 float3 c=mix3(horizon,zenith,powf(h,.55f));
 float disk=powf(sat(dot3(rd,sun)),900.0f);
 float glow=powf(sat(dot3(rd,sun)),18.0f);
 return c+make_float3(1.0f,.72f,.38f)*(disk*7.0f+glow*.12f);
}
__device__ float mobileLandHeight(float x,float z,const int* Origin,float fp){
 int cx=(int)floorf(x/CELL),cz=(int)floorf(z/CELL);
 return islandHeight(x,z,describeIsland(cx,cz,Origin),fp);
}
__device__ float3 mobileLandNormal(float3 p,const int* Origin,float fp){
 float e=fmaxf(.7f,fp);
 float l=mobileLandHeight(p.x-e,p.z,Origin,fp),r=mobileLandHeight(p.x+e,p.z,Origin,fp);
 float d=mobileLandHeight(p.x,p.z-e,Origin,fp),u=mobileLandHeight(p.x,p.z+e,Origin,fp);
 return norm3(make_float3(l-r,2*e,d-u));
}
__device__ float3 mobileLandColor(float3 p,float3 n,float3 sun){
 float beach=1-smoothf(3,14,p.y),grass=smoothf(2,22,p.y)*(1-smoothf(150,330,p.y));
 float3 sand=make_float3(.50f,.43f,.28f),green=make_float3(.12f,.27f,.105f),rock=make_float3(.24f,.25f,.22f);
 float3 base=mix3(sand,green,grass);base=mix3(base,rock,smoothf(.45f,.82f,1-n.y)*(1-beach*.7f));
 float light=.22f+.78f*sat(dot3(n,sun));return base*light;
}
__global__ void traceMobile(const float* C,const int* Origin,const float* Waves,const float* Terrain,float* Hit,float* Surface,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;
 int b=(y*width+x)*4;float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height);float cone=1.05f/(float)height;
 float wt=waterHit(ro,rd,cone,C[6],Waves,Origin),lt=traceLandCached(ro,rd,Origin,wt>0?wt+2:FAR,cone,Terrain);
 float t=FAR,material=0,fp=1,variance=0,depth=0;float3 n=make_float3(0,1,0);
 if(lt>0&&(wt<0||lt<wt)){t=lt;material=1;fp=fmaxf(.35f,t*cone);float3 p=ro+rd*t;n=mobileLandNormal(p,Origin,fp);}
 else if(wt>0){t=wt;material=2;fp=fmaxf(.18f,t*cone/fmaxf(.10f,-rd.y));float3 p=ro+rd*t;float4 w=ocean(p.x,p.z,fp,Waves,Origin);n=norm3(make_float3(-w.y,1,-w.z));variance=w.w;depth=fmaxf(0,p.y-mobileLandHeight(p.x,p.z,Origin,fp));}
 Hit[b]=t;Hit[b+1]=material;Hit[b+2]=fp;Hit[b+3]=variance;Surface[b]=n.x;Surface[b+1]=n.y;Surface[b+2]=n.z;Surface[b+3]=depth;
}
__global__ void shadeMobile(const float* C,const int* Origin,const float* Waves,const float* Hit,const float* Surface,unsigned int* Pixels,int width,int height){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y);if(x>=width||y>=height)return;int b=(y*width+x)*4;
 float3 ro=make_float3(C[0],C[1],C[2]),rd=cameraRay(C,x,y,width,height),sun=sunDirection(C);
 float t=Hit[b],material=Hit[b+1],fp=Hit[b+2],variance=Hit[b+3];float3 n=make_float3(Surface[b],Surface[b+1],Surface[b+2]);
 float3 color=mobileSky(rd,sun);
 if(material==1){float3 p=ro+rd*t;color=mobileLandColor(p,n,sun);float haze=1-expf(-t*.00018f);color=mix3(color,mobileSky(rd,sun),haze);}
 else if(material==2){
  float3 p=ro+rd*t,rr=rd-n*(2*dot3(rd,n));float nv=sat(-dot3(n,rd));
  float fresnel=.02f+.98f*powf(1-nv,5);float depth=Surface[b+3],clarity=C[12]>0?C[12]:1;
  float3 reflected=mobileSky(rr,sun),deep=make_float3(.008f,.075f,.105f),shallow=make_float3(.035f,.24f,.23f);
  float shallowMix=expf(-depth/(7.0f*clarity));float3 under=mix3(deep,shallow,shallowMix);
  float sparkle=powf(sat(dot3(rr,sun)),96.0f)/(1+variance*18.0f);color=mix3(under,reflected,fresnel)+make_float3(1,.78f,.46f)*sparkle*.8f;
  float shore=(1-smoothf(.25f,1.7f,depth))*smoothf(.18f,.55f,.5f+.5f*sinf(depth*3.1f+C[5]*1.25f));
  color=mix3(color,make_float3(.72f,.78f,.74f),shore*.55f);
 }
 color=color*C[11];color=make_float3(linearToDisplay(color.x),linearToDisplay(color.y),linearToDisplay(color.z));Pixels[y*width+x]=pack(color);
}
