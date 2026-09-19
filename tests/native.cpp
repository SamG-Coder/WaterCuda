#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "terrain-reference.hpp"
#include "../kernels/ocean.cu"
#include "../kernels/render.cu"
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
 // Compare closed-form height haze against independent midpoint integration.
 for(int i=0;i<100;i++){
  double a=(i%10)*170.0,b=(i/10)*110.0,length=100+i*170.0,sum=0;
  for(int j=0;j<1024;j++){double h=a+(b-a)*(j+.5)/1024;sum+=.000015+.000085*std::exp(-h/350);}
  double expected=sum*length/1024,actual=hazeOpticalDepth((float)a,(float)b,(float)length);
  if(fabs(actual-expected)>std::max(.000002,expected*.0001))return 28;
  float reverse=hazeOpticalDepth((float)b,(float)a,(float)length);
  float split=hazeOpticalDepth((float)a,(float)((a+b)/2),(float)(length/2))+hazeOpticalDepth((float)((a+b)/2),(float)b,(float)(length/2));
  if(fabs(actual-reverse)>.00001f||fabs(actual-split)>.00001f)return 29;
 }
 if(hazeOpticalDepth(0,0,1000)<=hazeOpticalDepth(1400,1400,1000)||hazeOpticalDepth(0,0,0)!=0)return 30;
 {float3 ro={0,1400,0},rd=norm3(make_float3(.2f,-.05f,1)),sun=norm3(make_float3(.2f,.7f,1));
  auto atLimit=aerialPerspective(make_float3(.05f,.1f,.2f),ro,rd,FAR,sun),background=sky(rd,sun);
  if(fabsf(atLimit.x-background.x)>.00001f||fabsf(atLimit.y-background.y)>.00001f||fabsf(atLimit.z-background.z)>.00001f)return 31;
 }
 std::cout<<"Height haze: 100 numerical integral comparisons, segment splitting and altitude falloff passed\n";
 // Reflection filtering preserves constant fields and rejects unrelated surfaces.
 {std::vector<float> hit(36,0),surface(36,0),reflection(36,0);
  for(int i=0;i<9;i++){hit[i*4]=100;hit[i*4+1]=2;surface[i*4+1]=1;reflection[i*4]=.2f;reflection[i*4+1]=.3f;reflection[i*4+2]=.4f;reflection[i*4+3]=100;}
  for(int y=0;y<3;y++)for(int x=0;x<3;x++){auto c=filteredReflection(x,y,3,3,hit.data(),surface.data(),reflection.data());if(fabsf(c.x-.2f)>.00001f||fabsf(c.z-.4f)>.00001f)return 25;}
  reflection[16]=1;auto c=filteredReflection(1,1,3,3,hit.data(),surface.data(),reflection.data());if(c.x<=.2f||c.x>=1)return 26;
  reflection[16]=.2f;
  for(int mode=0;mode<3;mode++){
   for(int i=0;i<9;i++){if(i==4)continue;reflection[i*4]=100;hit[i*4+1]=mode==0?1:2;hit[i*4]=mode==1?1000:100;surface[i*4+1]=mode==2?-1:1;}
   auto out=filteredReflection(1,1,3,3,hit.data(),surface.data(),reflection.data());if(fabsf(out.x-.2f)>.00001f)return 27;
  }
  std::cout<<"Reflection filter: constant preservation, impulse smoothing and edge rejection passed\n";
 }
 // A linear field must sample at the same physical coordinate at every mip.
 // Explicit averaged values are an independent oracle for mip centre registration.
 {std::vector<float> testWaves(OCEAN_TEXELS*4,0);
  for(int level=0;level<=8;level++){int n=256>>level,step=1<<level;
   for(int z=0;z<n;z++)for(int x=0;x<n;x++)testWaves[(mipOffset(level)+z*n+x)*4]=x*step+(step-1)*.5f+2*(z*step+(step-1)*.5f);
  }
  for(int level=0;level<8;level++){
   auto value=oceanSample(128.25f/256,90.75f/256,0,level,testWaves.data());
   if(fabsf(value.x-309.75f)>.0001f)return 23;
   auto left=oceanSample(-.00001f,.37f,0,level,testWaves.data()),right=oceanSample(.99999f,.37f,0,level,testWaves.data());
   if(fabsf(left.x-right.x)>.002f)return 24;
  }
  std::cout<<"Wave mip levels: physical sample centres and periodic wrapping passed\n";
 }
 // Compare optimized terrain against the frozen previous implementation.
 for(int seed:{42,884,12345}){
  int o[4]={0,0,seed,0};
  for(int i=0;i<2000;i++){
   float x=hash2(i,0,117)*CELL,z=hash2(i,1,911)*CELL;
   if(i%8==0)x=(i%16==0?CELL-.05f:.05f);
   float fp=(i%7==0?800.0f:(i%5==0?128.0f:.2f));float3 p={x,0,z};
   float h=ground(x,z,o,fp),expected=referenceGround(x,z,o,fp);
   auto n=groundNormal(p,o,fp),old=referenceGroundNormal(p,o,fp);
   if(fabsf(h-expected)>.00001f||fabsf(n.x-old.x)>.00001f||fabsf(n.y-old.y)>.00001f||fabsf(n.z-old.z)>.00001f)return 22;
  }
 }
 std::cout<<"6000 terrain/normal samples match the frozen pre-optimization evaluator\n";
 // Two-way bed lighting must dim monotonically and lose red before blue.
 {auto zero=waterTransmission(0);if(zero.x!=1||zero.y!=1||zero.z!=1)return 15;
  if(fabsf(sunWaterPath(10,1)-10)>.0001f||sunWaterPath(10,0)>15.2f)return 20;
  if(bedDetailWeight(45,45,1)!=0)return 21;
  float previous=1;
  for(int d=1;d<=200;d++){
   auto t=waterTransmission((float)d);if(t.x<0||t.x>t.y||t.y>t.z||t.z>previous)return 16;previous=t.z;
   float high=bedDetailWeight((float)d,(float)d,1),low=bedDetailWeight((float)d,(float)d,.1f);
   if(!std::isfinite(low)||low>high||low<0||high>1)return 17;
  }
  if(bedDetailWeight(60,45,.6f)!=0||bedDetailWeight(2,1,.6f)<.99f)return 18;
  for(int i=0;i<2000;i++){float d=i*.05f;if(fabsf(bedDetailWeight(d,d,.6f)-bedDetailWeight(d+.001f,d+.001f,.6f))>.001f)return 19;}
  std::cout<<"Water optics: attenuation ordering, solar depth, deep-detail cutoff and continuity passed\n";
 }
 // Odd-sized reflection targets exercise the final row/column and padded dispatch.
 {const int width=5,height=3,count=width*height*4;float c[16]={0,600,0,0,-.6f,0,1,-.7f,.7f,1,0,1};int o[4]={0,0,42,0};
  std::vector<float> hit(count,0),surface(count,0),ref(count+8,-999);
  for(int i=0;i<width*height;i++){hit[i*4]=10;hit[i*4+1]=2;surface[i*4+1]=1;}
  blockIdx={0,0,0};blockDim={8,8,1};
  for(int y=0;y<8;y++)for(int x=0;x<8;x++){threadIdx={(unsigned)x,(unsigned)y,0};reflectOcean(c,o,hit.data(),surface.data(),ref.data(),width,height);}
  for(int i=0;i<width*height;i++){if(ref[i*4+3]!=10||!std::isfinite(ref[i*4]))return 9;}
  for(int i=count;i<count+8;i++)if(ref[i]!=-999)return 10;
  c[9]=0;
  for(int y=0;y<8;y++)for(int x=0;x<8;x++){threadIdx={(unsigned)x,(unsigned)y,0};reflectOcean(c,o,hit.data(),surface.data(),ref.data(),width,height);}
  for(int i=0;i<width*height;i++)if(ref[i*4+3]!=-1)return 11;
  std::cout<<"Per-pixel reflections: odd target coverage, dispatch guards and disabled state passed\n";
 }
 // Foam phase must be continuous across both ordinary and remote origin shifts.
 for(int remote:{0,100000000,-100000000}){
  int origin[4]={remote,-remote,884,0},rebased[4]={remote+1,-remote-1,884,0};
  for(int i=0;i<100;i++){
   float3 p={4790+i*.25f,.8f,-10+i*.125f};float3 n=norm3(make_float3(.4f,1,.2f));
   float f=waterFoam(p,n,1.2f,.1f,3,1,origin);
   float shifted=waterFoam(p+make_float3(-CELL,0,CELL),n,1.2f,.1f,3,1,rebased);
   if(!std::isfinite(f)||f<0||f>1||fabsf(f-shifted)>.002f)return 12;
   if(waterFoam(make_float3(p.x,-1,p.z),n,45,.1f,3,1,origin)!=0)return 13;
  }
 }
 {int o[4]={0,0,884,0};float a=waterFoam(make_float3(1,0,2),make_float3(0,1,0),1,8,0,1,o),b=waterFoam(make_float3(300,0,900),make_float3(0,1,0),1,8,300,1,o);if(fabsf(a-b)>.0001f)return 14;}
 std::cout<<"300 foam samples: rebasing, range, trough rejection and distant coverage passed\n";
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
