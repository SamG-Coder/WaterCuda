#include "renderer.hpp"
#include "cuda_vectors.cuh"
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
// These are the exact files compiled to WebGPU by the browser app.
#include "../../kernels/common.cu"
#include "../../kernels/weather.cu"
#include "../../kernels/terrain.cu"
#include "../../kernels/shrubs.cu"
#include "../../kernels/ocean.cu"
#include "../../kernels/render.cu"
namespace {
void check(cudaError_t code,const char* operation){if(code!=cudaSuccess)throw std::runtime_error(std::string(operation)+": "+cudaGetErrorString(code));}
#define CUDA(call) check((call),#call)
template<class T> struct Buffer {
 T* p=nullptr;size_t count=0;
 ~Buffer(){if(p)cudaFree(p);}
 void alloc(size_t n){if(p){CUDA(cudaFree(p));p=nullptr;}count=n;CUDA(cudaMalloc(reinterpret_cast<void**>(&p),n*sizeof(T)));}
 void put(const T* data){CUDA(cudaMemcpy(p,data,count*sizeof(T),cudaMemcpyHostToDevice));}
 std::vector<T> read(){std::vector<T> out(count);CUDA(cudaMemcpy(out.data(),p,count*sizeof(T),cudaMemcpyDeviceToHost));return out;}
};
struct Event {cudaEvent_t value{};Event(){CUDA(cudaEventCreate(&value));}~Event(){cudaEventDestroy(value);}};
void launchCheck(){CUDA(cudaGetLastError());}
}
struct Renderer::Impl {
 Buffer<float> camera,waves,shrubs,hit,surface,reflection;
 Buffer<int> origin;Buffer<float4> initial;Buffer<float2> spectrum,ping;Buffer<unsigned int> pixels;
 Event begin,end,stages[5];std::array<float,5> stageTimes{};std::vector<std::uint32_t> host;int width=0,height=0,seed=-1;
 std::array<int,5> reefPatch{};bool reefValid=false;
 std::array<int,5> patch{};bool patchValid=false,oceanValid=false;float time=0,wind=0,weather=0,ms=0;
 std::string name;
 Impl(){
  int count=0;CUDA(cudaGetDeviceCount(&count));if(!count)throw std::runtime_error("No CUDA-capable NVIDIA GPU found.");
  CUDA(cudaSetDevice(0));cudaDeviceProp prop{};CUDA(cudaGetDeviceProperties(&prop,0));name=prop.name;
  camera.alloc(16);origin.alloc(4);waves.alloc(4*OCEAN_TEXELS*4+4);shrubs.alloc(SHRUB_FLOATS);
  initial.alloc(4*65536);spectrum.alloc(4*65536);ping.alloc(4*65536);
  generateShrubAtlas<<<dim3(16,16,8),dim3(8,8)>>>(shrubs.p);launchCheck();
  for(int level=1;level<8;level++){int groups=((128>>level)+7)/8;mipShrubAtlas<<<dim3(groups,groups,8),dim3(8,8)>>>(shrubs.p,level);launchCheck();}
  CUDA(cudaDeviceSynchronize());
 }
 void ocean(const Scene& s){
  camera.put(s.camera.data());origin.put(s.origin.data());
  if(seed!=s.origin[2]){cacheOceanSpectrum<<<dim3(32,32,4),dim3(8,8)>>>(origin.p,initial.p);launchCheck();seed=s.origin[2];oceanValid=false;}
  if(!oceanValid||time!=s.camera[5]||wind!=s.camera[6]||weather!=s.camera[15]){
   advanceOceanSpectrum<<<dim3(32,32,4),dim3(8,8)>>>(camera.p,initial.p,spectrum.p);launchCheck();
   oceanFft<<<dim3(256,4),128>>>(spectrum.p,ping.p,0);launchCheck();
   oceanFft<<<dim3(256,4),128>>>(ping.p,spectrum.p,1);launchCheck();
   packOcean<<<dim3(32,32,4),dim3(8,8)>>>(camera.p,spectrum.p,waves.p);launchCheck();
   for(int level=1;level<=8;level++){int g=((256>>level)+7)/8;oceanMip<<<dim3(g,g,4),dim3(8,8)>>>(waves.p,level);launchCheck();}
   time=s.camera[5];wind=s.camera[6];weather=s.camera[15];oceanValid=true;
  }
 }
};
Renderer::Renderer():impl(std::make_unique<Impl>()){}
Renderer::~Renderer()=default;
std::string Renderer::deviceName()const{return impl->name;}
float Renderer::gpuMs()const{return impl->ms;}
std::array<float,5> Renderer::stageMs()const{return impl->stageTimes;}
void Renderer::resize(int w,int h){
 if(w<64||h<64||w>7680||h>4320)throw std::runtime_error("Render dimensions must be 64..7680 by 64..4320.");
 auto& r=*impl;if(r.width==w&&r.height==h)return;CUDA(cudaDeviceSynchronize());
 size_t n=size_t(w)*h;r.hit.alloc(n*4);r.surface.alloc(n*4);r.reflection.alloc(n*4);r.pixels.alloc(n);r.host.resize(n);r.width=w;r.height=h;
}
const std::vector<std::uint32_t>& Renderer::render(const Scene& s){
 auto& r=*impl;if(!r.width)throw std::runtime_error("Call resize before render.");
 CUDA(cudaEventRecord(r.begin.value));r.ocean(s);
 std::array<int,5> patch{int(std::floor(s.camera[0]/6)),int(std::floor(s.camera[2]/6)),s.origin[0],s.origin[1],s.origin[2]};
 if(!r.patchValid||patch!=r.patch){cacheShrubs<<<dim3(8,8),dim3(8,8)>>>(r.camera.p,r.origin.p,r.shrubs.p);launchCheck();r.patch=patch;r.patchValid=true;}
 std::array<int,5> reefPatch{int(std::floor(s.camera[0]/12)),int(std::floor(s.camera[2]/12)),s.origin[0],s.origin[1],s.origin[2]};
 if(s.camera[1]<0&&s.camera[14]<.5f&&(!r.reefValid||reefPatch!=r.reefPatch)){cacheReef<<<dim3(128,128),dim3(8,8)>>>(r.camera.p,r.origin.p,r.shrubs.p);launchCheck();r.reefPatch=reefPatch;r.reefValid=true;}
 CUDA(cudaEventRecord(r.stages[0].value));
 dim3 groups((r.width+7)/8,(r.height+7)/8),threads(8,8);
 tracePrimary<<<groups,threads>>>(r.camera.p,r.origin.p,r.waves.p,r.shrubs.p,r.hit.p,r.surface.p,r.width,r.height);launchCheck();CUDA(cudaEventRecord(r.stages[1].value));
 traceVegetation<<<groups,threads>>>(r.camera.p,r.origin.p,r.shrubs.p,r.hit.p,r.surface.p,r.width,r.height);launchCheck();CUDA(cudaEventRecord(r.stages[2].value));
 reflectOcean<<<groups,threads>>>(r.camera.p,r.origin.p,r.shrubs.p,r.hit.p,r.surface.p,r.reflection.p,r.width,r.height);launchCheck();CUDA(cudaEventRecord(r.stages[3].value));
 shadeOcean<<<groups,threads>>>(r.camera.p,r.origin.p,r.shrubs.p,r.hit.p,r.surface.p,r.reflection.p,r.waves.p,r.pixels.p,r.width,r.height);launchCheck();CUDA(cudaEventRecord(r.stages[4].value));
 CUDA(cudaEventRecord(r.end.value));CUDA(cudaMemcpy(r.host.data(),r.pixels.p,r.host.size()*4,cudaMemcpyDeviceToHost));
 CUDA(cudaEventElapsedTime(&r.ms,r.begin.value,r.end.value));
 for(int i=0;i<5;i++)CUDA(cudaEventElapsedTime(&r.stageTimes[i],i?r.stages[i-1].value:r.begin.value,r.stages[i].value));return r.host;
}
void Renderer::selfTest(){
 auto& r=*impl;Scene s;s.camera[15]=-1;s.origin[2]=42;s.camera[5]=3;s.camera[6]=1;
 Buffer<float> points,result;points.alloc(16);result.alloc(16);
 float p[16]={2400,2400,.2f,0,4799.9f,1000,.2f,0,2000,2000,.2f,0,2400,2400,128,0};
 auto probe=[&](){r.ocean(s);points.put(p);probeWorld<<<1,64>>>(points.p,r.origin.p,r.waves.p,result.p,4);launchCheck();return result.read();};
 auto a=probe(),b=probe();if(a!=b)throw std::runtime_error("Repeated native GPU samples differ.");
 std::ifstream file(std::string(WATER_SOURCE_DIR)+"/tests/ocean-reference.json");if(!file)throw std::runtime_error("Cannot open shared CPU reference fixture.");
 std::string json((std::istreambuf_iterator<char>(file)),{});for(char& c:json)if(c=='['||c==']'||c==',')c=' ';std::istringstream in(json);
 for(int i=0;i<16;i++){float expected;if(!(in>>expected)||!std::isfinite(a[i])||std::abs(a[i]-expected)>(i%4==0?.02f:.005f))throw std::runtime_error("Native GPU / CPU fixture mismatch at sample "+std::to_string(i));}
 for(int i=0;i<4;i++){p[i*4]-=4800;p[i*4+1]+=4800;}s.origin[0]=1;s.origin[1]=-1;auto shifted=probe();
 for(int i=0;i<16;i++)if(std::abs(a[i]-shifted[i])>.005f)throw std::runtime_error("Native origin rebasing mismatch.");
 auto atlas=r.shrubs.read();for(int tile=0;tile<8;tile++){int base=16388+tile*21845*4;double sum=0;for(int i=0;i<16384;i++)sum+=atlas[base+i*4+3];float average=atlas[base+21844*4+3];if(!std::isfinite(average)||average<.08f||average>.8f||std::abs(sum/16384-average)>1e-5)throw std::runtime_error("Native atlas mip coverage mismatch.");}
 std::cout<<"PASS: native GPU determinism, shared CPU ocean/terrain fixture, origin rebasing, foliage mip coverage\n";
}
