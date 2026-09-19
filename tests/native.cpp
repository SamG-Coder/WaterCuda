#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "../kernels/ocean.cu"
#include <complex>
#include <iomanip>
// Independent CPU complex transform, compared with GPU samples by the browser checks.
void cpuInverse(std::vector<std::complex<double>>& a){
 for(int i=1,j=0;i<256;i++){int bit=128;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)std::swap(a[i],a[j]);}
 for(int n=2;n<=256;n*=2){auto root=std::polar(1.0,2*3.141592653589793/n);for(int base=0;base<256;base+=n){std::complex<double>w=1;for(int j=0;j<n/2;j++){auto u=a[base+j],v=a[base+j+n/2]*w;a[base+j]=u+v;a[base+j+n/2]=u-v;w*=root;}}}
}
std::vector<float> cpuOcean(){
 std::vector<float2> spatial(4*65536);std::vector<std::complex<double>> line(256);
 for(int layer=0;layer<4;layer++)for(int y=0;y<256;y++)for(int x=0;x<256;x++)spatial[layer*65536+y*256+x]=evolveSpectrum(x,y,layer,3,1,42);
 for(int axis=0;axis<2;axis++)for(int layer=0;layer<4;layer++)for(int row=0;row<256;row++){
  for(int i=0;i<256;i++){int ix=layer*65536+(axis==0?row*256+i:i*256+row);line[i]={spatial[ix].x,spatial[ix].y};}
  cpuInverse(line);for(int i=0;i<256;i++){int ix=layer*65536+(axis==0?row*256+i:i*256+row);spatial[ix]={(float)line[i].real(),(float)line[i].imag()};}
 }
 double sum=0;float maxH=0,maxImag=0;for(const auto&v:spatial){sum+=v.x*v.x;maxH=fmaxf(maxH,fabsf(v.x));maxImag=fmaxf(maxImag,fabsf(v.y));}
 std::cout<<"Spectral ocean: cascade RMS="<<sqrt(sum/spatial.size())<<", peak="<<maxH<<", imaginary residual="<<maxImag<<"\n";
 if(maxImag>.0001f||maxH<.1f||!std::isfinite(maxH))throw std::runtime_error("Invalid Fourier ocean");
 std::vector<float> waves(4*OCEAN_TEXELS*4);blockDim={1,1,1};
 for(int layer=0;layer<4;layer++){blockIdx={0,0,(unsigned)layer};for(int y=0;y<256;y++)for(int x=0;x<256;x++){threadIdx={(unsigned)x,(unsigned)y,0};packOcean(spatial.data(),waves.data());}}
 for(int level=1;level<=8;level++){int n=256>>level;for(int layer=0;layer<4;layer++){blockIdx={0,0,(unsigned)layer};for(int y=0;y<n;y++)for(int x=0;x<n;x++){threadIdx={(unsigned)x,(unsigned)y,0};oceanMip(waves.data(),level);}}}
 return waves;
}
int main(){
 // Enlarged islands must stay inside their cells and the traversal height cap.
 for(int seed=0;seed<100;seed++){
  int o[4]={0,0,seed,0};Island a=describeIsland(0,0,o);
  if(a.x-a.radius<0||a.z-a.radius<0||a.x+a.radius>CELL||a.z+a.radius>CELL||a.peak+32>=500)return 4;
  for(int z=0;z<=20;z++)for(int x=0;x<=20;x++){
   float h=islandHeight(a.x-a.radius+x*a.radius/10,a.z-a.radius+z*a.radius/10,a,.2f);
   if(!std::isfinite(h)||h< -45.001f||h>a.peak+32)return 6;
  }
  for(int i=0;i<=16;i++){float z=CELL*i/16;if(ground(CELL-.01f,z,o,.2f)!=ground(CELL+.01f,z,o,.2f))return 5;}
 }
 std::cout<<"100 island seeds: bounds and cell-edge seabed continuity passed\n";
 // Near-surface material detail must survive rebasing and fade under minification.
 float detailDifference=0;int matOrigin[4]={0,0,42,0},shiftOrigin[4]={1,-1,42,0};
 for(int i=0;i<60;i++){
  float3 p={2200+i*.17f,70+i*.11f,2300+i*.13f};float3 n=norm3(make_float3(.7f,1,.3f)),sun=norm3(make_float3(.3f,1,.4f));
  auto close=landColor(p,n,sun,matOrigin,.005f),far=landColor(p,n,sun,matOrigin,2);
  auto shifted=landColor(p+make_float3(-CELL,0,CELL),n,sun,shiftOrigin,.005f);
  if(!std::isfinite(close.x)||fabsf(close.x-shifted.x)>.003f||fabsf(close.y-shifted.y)>.003f)return 7;
  detailDifference+=fabsf(close.x-far.x)+fabsf(close.y-far.y);
 }
 if(detailDifference<.01f)return 8;
 std::cout<<"60 close material samples: finite, rebasing-stable, and detail LOD active\n";
 int tested=0,misses=0;float worst=0;
 for(int seed:{42,12345,7654}){
  int origin[4]={0,0,seed,0};Island island=describeIsland(0,0,origin);
  for(int cell=1;island.peak==0&&cell<20;cell++)island=describeIsland(cell,0,origin);
  for(int i=0;i<64;i++){
   float angle=i*2*PI/64;float3 ro={island.x+cosf(angle)*island.radius*1.3f,40+(i%7)*40.0f,island.z+sinf(angle)*island.radius*1.3f};
   float3 rd=norm3(make_float3(island.x,15+(i%3)*30,island.z)-ro);
   float reference=-1,limit=rd.y<0?fminf(4500,-ro.y/rd.y):4500;
   for(float t=.1f;t<limit;t+=.25f){float3 p=ro+rd*t;if(p.y<ground(p.x,p.z,origin,.2f)){reference=t;break;}}
   float traced=traceLand(ro,rd,origin,limit,0);
   if((reference<0)!=(traced<0)){misses++;std::cerr<<"Hit mismatch seed="<<seed<<" ray="<<i<<" dense="<<reference<<" traced="<<traced<<"\n";}
   if(reference>0&&traced>0)worst=std::max(worst,fabsf(reference-traced));tested++;
  }
 }
 std::cout<<tested<<" terrain rays vs 0.25 m dense traversal; mismatches="<<misses<<", maximum distance error="<<worst<<" m\n";
 if(misses||worst>2)return 1;
 int lowMisses=0;float lowError=0;int lowOrigin[4]={0,0,884,0};
 for(int i=0;i<200;i++){
  float3 ro={1550,7,1100},rd=norm3(make_float3(sinf(.2f+i*.005f),.08f+(i%20)*.012f,cosf(.2f+i*.005f)));float reference=-1;
  for(float t=.1f;t<4000;t+=.25f){auto p=ro+rd*t;if(p.y<ground(p.x,p.z,lowOrigin,.2f)){reference=t;break;}}
  float traced=traceLand(ro,rd,lowOrigin,4000,0);if((traced<0)!=(reference<0))lowMisses++;if(traced>0&&reference>0)lowError=fmaxf(lowError,fabsf(traced-reference));
 }
 std::cout<<"200 near-waterline hillside rays: mismatches="<<lowMisses<<", maximum distance error="<<lowError<<" m\n";if(lowMisses||lowError>3)return 3;
 int origin[4]={0,0,42,0};float residual=0;auto waves=cpuOcean();const float* Waves=waves.data();
 for(int i=0;i<100;i++){
  float3 ro={340,4+(i%10)*25.0f,100};float3 rd=norm3(make_float3(.3f,-.015f-(i%13)*.04f,1));
  float t=waterHit(ro,rd,1.05f/720,1,Waves,origin);if(t<0)continue;
  float3 p=ro+rd*t;float4 w=ocean(p.x,p.z,fmaxf(.12f,t*(1.05f/720)/fmaxf(.08f,-rd.y)),Waves,origin);
  if(!std::isfinite(t))return 2;residual=std::max(residual,fabsf(p.y-w.x));
 }
 std::cout<<"100 displaced-water rays; maximum surface residual="<<residual<<" m\n";
 std::ofstream fixture("tests/ocean-reference.json");fixture<<std::setprecision(9)<<"[";float points[16]={2400,2400,.2f,0,4799.9f,1000,.2f,0,2000,2000,.2f,0,2400,2400,128,0};
 for(int i=0;i<4;i++){float x=points[i*4],z=points[i*4+1],fp=points[i*4+2];auto w=ocean(x,z,fp,Waves,origin);if(i)fixture<<",";fixture<<ground(x,z,origin,fp)<<","<<w.x<<","<<w.y<<","<<w.w;}fixture<<"]\n";
 return residual>.1f?2:0;
}
