#define OCEAN_N 256
#define OCEAN_LAYERS 4
#define OCEAN_TEXELS 87381
__device__ float oceanPeriod(int layer){return (float)(32 << (layer*2));}
__device__ int mipOffset(int level){return (262144-(262144 >> (2*level)))/3;}
// Phillips directional spectrum, integrated over each Fourier cell. Four overlapping
// wavelength bands remove the small set of coherent directions in the old wave sum.
__device__ float2 initialSpectrum(int ix,int iz,int layer,int seed){
 int nx=ix<128?ix:ix-256,nz=iz<128?iz:iz-256;if((nx==0&&nz==0)||ix==128||iz==128)return make_float2(0,0);
 float dk=2*PI/oceanPeriod(layer),kx=(float)nx*dk,kz=(float)nz*dk,k2=kx*kx+kz*kz,k=sqrtf(k2),lambda=2*PI/k;
 float low=layer==0?.35f:3.0f*powf(4.0f,(float)(layer-1)),high=3.0f*powf(4.0f,(float)layer);
 float band=smoothf(low*.8f,low*1.2f,lambda)*(1-smoothf(high*.8f,high*1.2f,lambda));
 float direction=(kx*.9f+kz*.43589f)/k;
 float P=.0010f*expf(-1/(k2*22.0f*22.0f))/(k2*k2)*(.18f+.82f*direction*direction)*expf(-k2*.012f*.012f)*band;
 if(direction<0)P*=.25f;
 float r1=fmaxf(.000001f,hash2(ix+layer*997,iz,(unsigned int)seed+371u)),r2=hash2(ix+layer*997,iz,(unsigned int)seed+911u);
 float radius=sqrtf(-2*logf(r1))*sqrtf(P*.5f)*dk,phase=2*PI*r2;return make_float2(radius*cosf(phase),radius*sinf(phase));
}
__device__ float2 evolveSpectrum(int ix,int iz,int layer,float time,float wind,int seed){
 int nx=ix<128?ix:ix-256,nz=iz<128?iz:iz-256;float dk=2*PI/oceanPeriod(layer),k=dk*sqrtf((float)(nx*nx+nz*nz));
 float2 a=initialSpectrum(ix,iz,layer,seed),b=initialSpectrum((256-ix)%256,(256-iz)%256,layer,seed);
 float phase=sqrtf(9.81f*k)*time,c=cosf(phase),s=sinf(phase);
 return make_float2(((a.x+b.x)*c-(a.y+b.y)*s)*wind,((a.x-b.x)*s+(a.y-b.y)*c)*wind);
}
__global__ void seedOcean(const float* C,const int* Origin,float2* Spectrum){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),layer=(int)blockIdx.z;
 if(x>=256||y>=256||layer>=4)return;Spectrum[layer*65536+y*256+x]=evolveSpectrum(x,y,layer,C[5],C[6],Origin[2]);
}
// Unnormalised inverse FFT. One workgroup owns an entire row/column, with explicit
// shared-memory barriers at every butterfly stage. No CPU-generated ocean maps.
__global__ void oceanFft(const float2* Input,float2* Output,int axis){
 __shared__ float2 values[256];
 int lane=(int)threadIdx.x,line=(int)blockIdx.x,layer=(int)blockIdx.y;
 for(int i=lane;i<256;i+=128){int reverse=0,v=i;for(int bit=0;bit<8;bit++){reverse=(reverse<<1)|(v&1);v>>=1;}int index=layer*65536+(axis==0?line*256+i:i*256+line);values[reverse]=Input[index];}
 __syncthreads();
 for(int size=2;size<=256;size<<=1){int half=size>>1,j=lane&(half-1),base=(lane/half)*size;float angle=2*PI*(float)j/(float)size;
  float2 a=values[base+j],b=values[base+j+half];float c=cosf(angle),s=sinf(angle),rx=b.x*c-b.y*s,ry=b.x*s+b.y*c;
  values[base+j]=make_float2(a.x+rx,a.y+ry);values[base+j+half]=make_float2(a.x-rx,a.y-ry);__syncthreads();
 }
 for(int i=lane;i<256;i+=128){int index=layer*65536+(axis==0?line*256+i:i*256+line);Output[index]=values[i];}
}
__global__ void packOcean(const float* C,const float2* Spatial,float* Waves){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),layer=(int)blockIdx.z;if(x>=256||y>=256||layer>=4)return;
 int base=layer*65536,index=base+y*256+x,b=(layer*OCEAN_TEXELS+y*256+x)*4;
 float spacing=oceanPeriod(layer)/256;
 float dx=(Spatial[base+y*256+(x+1)%256].x-Spatial[base+y*256+(x+255)%256].x)/(2*spacing);
 float dz=(Spatial[base+((y+1)%256)*256+x].x-Spatial[base+((y+255)%256)*256+x].x)/(2*spacing);
 if(x==0&&y==0&&layer==0){Waves[1398096]=C[5];Waves[1398097]=C[15]>=0?1:0;Waves[1398098]=C[15];Waves[1398099]=0;}
 Waves[b]=Spatial[index].x;Waves[b+1]=dx;Waves[b+2]=dz;Waves[b+3]=dx*dx+dz*dz;
}
__global__ void oceanMip(float* Waves,int level){
 int n=256>>level,x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),layer=(int)blockIdx.z;if(x>=n||y>=n||layer>=4)return;
 int dst=(layer*OCEAN_TEXELS+mipOffset(level)+y*n+x)*4,src=(layer*OCEAN_TEXELS+mipOffset(level-1)+(y*2)*(n*2)+x*2)*4;
 for(int c=0;c<4;c++)Waves[dst+c]=(Waves[src+c]+Waves[src+4+c]+Waves[src+n*8+c]+Waves[src+n*8+4+c])*.25f;
}
__device__ float4 oceanSample(float u,float v,int layer,int level,const float* Waves){
 // A level-L texel averages 2^L base samples, centred at (2^L-1)/2.
 // Register every mip to the same world positions before trilinear blending.
 int n=256>>level;float centre=.5f*(1-(float)n/256);
 float x=fractf(u)*(float)n-centre,z=fractf(v)*(float)n-centre;
 int ix=((int)floorf(x)+n)%n,iz=((int)floorf(z)+n)%n,jx=(ix+1)%n,jz=(iz+1)%n;
 float fx=fractf(x),fz=fractf(z);int start=layer*OCEAN_TEXELS+mipOffset(level),a=(start+iz*n+ix)*4,b=(start+iz*n+jx)*4,c=(start+jz*n+ix)*4,d=(start+jz*n+jx)*4;
 float h=lerpf(lerpf(Waves[a],Waves[b],fx),lerpf(Waves[c],Waves[d],fx),fz);
 float dx=lerpf(lerpf(Waves[a+1],Waves[b+1],fx),lerpf(Waves[c+1],Waves[d+1],fx),fz);
 float dz=lerpf(lerpf(Waves[a+2],Waves[b+2],fx),lerpf(Waves[c+2],Waves[d+2],fx),fz);
 float e=lerpf(lerpf(Waves[a+3],Waves[b+3],fx),lerpf(Waves[c+3],Waves[d+3],fx),fz);return make_float4(h,dx,dz,e);
}
// Local hull displacement and Kelvin-style wake compose with the spectral surface.
// Keeping this local avoids repeating a ship disturbance across the periodic FFT tiles.
__device__ float shipWakeHeight(float side,float along,float speed,float time){
 float behind=fmaxf(0,-along),reach=clampf(speed*4,35,260),tail=(1-smoothf(reach*.65f,reach,behind))*smoothf(-4,6,behind);
 float arm=fabsf(side)-behind*.35f,band=expf(-arm*arm/(2+behind*.12f));
 float ripples=sinf(behind*.65f-time*3)*expf(-fabsf(side)/(3+behind*.16f));
 float hull=-.55f*expf(-side*side*.1f-along*along*.007f);
 float bow=.7f*expf(-side*side*.06f-(along-18)*(along-18)*.12f);
 return (hull+bow+tail*(band*.45f+ripples*.14f))*smoothf(0,12,speed)*clampf(speed/20,.2f,2);
}
__device__ float wakeCell(const float* Waves,int bank,int x,int z,int component){
 if(x<0||z<0||x>=128||z>=128)return 0;
 return Waves[1398144+bank*32768+(z*128+x)*2+component];
}
__device__ float wakeSurface(float x,float z,const float* Waves){
 float u=(x-Waves[1398108])/2,v=(z-Waves[1398109])/2;int ix=(int)floorf(u),iz=(int)floorf(v),bank=(int)Waves[1398107];
 return lerpf(lerpf(wakeCell(Waves,bank,ix,iz,0),wakeCell(Waves,bank,ix+1,iz,0),fractf(u)),lerpf(wakeCell(Waves,bank,ix,iz+1,0),wakeCell(Waves,bank,ix+1,iz+1,0),fractf(u)),fractf(v));
}
__device__ float4 ocean(float x,float z,float fp,const float* Waves,const int* Origin){
 float h=0,dx=0,dz=0,variance=0;
 for(int layer=0;layer<4;layer++){
  int period=32<<(layer*2);unsigned int mask=(unsigned int)(period-1),ox=((unsigned int)Origin[0]*4800u)&mask,oz=((unsigned int)Origin[1]*4800u)&mask;
  float u=(x+(float)ox)/(float)period,v=(z+(float)oz)/(float)period;
  float lod=clampf(log2f(fmaxf(1,fp*256/(float)period)),0,8);int level=(int)floorf(lod);float blend=lod-(float)level;
  float4 a=oceanSample(u,v,layer,level,Waves),b=a;if(level<8&&blend>.001f)b=oceanSample(u,v,layer,level+1,Waves);
  float sx=lerpf(a.y,b.y,blend),sz=lerpf(a.z,b.z,blend);h+=lerpf(a.x,b.x,blend);dx+=sx;dz+=sz;
  variance+=fmaxf(0,lerpf(a.w,b.w,blend)-sx*sx-sz*sz);
 }
 float gain=Waves[1398097]>.5f?weatherWaveGain(x,z,Waves[1398096],Waves[1398098],Origin):1;
 h*=gain;dx*=gain;dz*=gain;variance*=gain*gain;
 if(Waves[1398099]>.5f){
  float speed=fabsf(Waves[1398103]),wet=1-smoothf(1,6,fabsf(Waves[1398104]));
  float px=x-Waves[1398100],pz=z-Waves[1398101];
  if(speed>.05f&&wet>0&&fabsf(px)<300&&fabsf(pz)<300){
   float yaw=Waves[1398102],sx=sinf(yaw),sz=cosf(yaw),direction=Waves[1398103]<0?-1.0f:1.0f;
   float side=px*sz-pz*sx,along=(px*sx+pz*sz)*direction,time=Waves[1398105];
   float amount=wet*weight(fp,.15f),e=.25f,w=shipWakeHeight(side,along,speed,time);
   float ds=(shipWakeHeight(side+e,along,speed,time)-shipWakeHeight(side-e,along,speed,time))/(2*e),dl=(shipWakeHeight(side,along+e,speed,time)-shipWakeHeight(side,along-e,speed,time))/(2*e);
   h+=w*amount;dx+=(ds*sz+dl*sx*direction)*amount;dz+=(-ds*sx+dl*sz*direction)*amount;variance+=(ds*ds+dl*dl)*amount*.12f;
  }
 }
 if(Waves[1398099]>.5f&&Waves[1398106]>.5f){
  float localX=x-Waves[1398108],localZ=z-Waves[1398109];
  if(localX>2&&localZ>2&&localX<252&&localZ<252){float fade=weight(fp,.12f);h+=wakeSurface(x,z,Waves)*fade;dx+=(wakeSurface(x+1,z,Waves)-wakeSurface(x-1,z,Waves))*.5f*fade;dz+=(wakeSurface(x,z+1,Waves)-wakeSurface(x,z-1,Waves))*.5f*fade;}
 }
 return make_float4(h,dx,dz,variance);
}
__device__ float waterHit(float3 ro,float3 rd,float cone,float wind,const float* Waves,const int* Origin){
 if(rd.y>=-0.00001f)return -1;float t=-ro.y/rd.y;if(t>FAR)return -1;
 float lo=fmaxf(.05f,(ro.y-15*wind)/(-rd.y)),hi=fminf(FAR,(ro.y+15*wind)/(-rd.y));
 for(int i=0;i<12;i++){
  float3 p=ro+rd*t;float4 w=ocean(p.x,p.z,fmaxf(.12f,t*cone/fmaxf(.08f,-rd.y)),Waves,Origin);float gap=p.y-w.x;if(fabsf(gap)<.004f)break;
  if(gap>0)lo=t;else hi=t;float denom=rd.y-w.y*rd.x-w.z*rd.z,next=fabsf(denom)>.02f?t-gap/denom:(lo+hi)*.5f;t=next>lo&&next<hi?next:(lo+hi)*.5f;
 }
 return t;
}
// Seed-dependent Gaussian Fourier coefficients do not change with time or wind.
// Build them once per world seed on the GPU; the animated pass is just dispersion
// and complex phase rotation. The original seedOcean remains the regression oracle.
__global__ void cacheOceanSpectrum(const int* Origin,float4* Initial){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),layer=(int)blockIdx.z;
 if(x>=256||y>=256||layer>=4)return;
 float2 a=initialSpectrum(x,y,layer,Origin[2]),b=initialSpectrum((256-x)%256,(256-y)%256,layer,Origin[2]);
 Initial[layer*65536+y*256+x]=make_float4(a.x,a.y,b.x,b.y);
}
__global__ void advanceOceanSpectrum(const float* C,const float4* Initial,float2* Spectrum){
 int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),layer=(int)blockIdx.z;
 if(x>=256||y>=256||layer>=4)return;int i=layer*65536+y*256+x;
 int nx=x<128?x:x-256,nz=y<128?y:y-256;
 float k=(2*PI/oceanPeriod(layer))*sqrtf((float)(nx*nx+nz*nz));
 float phase=sqrtf(9.81f*k)*C[5],c=cosf(phase),s=sinf(phase);float4 a=Initial[i];
 Spectrum[i]=make_float2(((a.x+a.z)*c-(a.y+a.w)*s)*C[6],((a.x-a.z)*s+(a.y-a.w)*c)*C[6]);
}
