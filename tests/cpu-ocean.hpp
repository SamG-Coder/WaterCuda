#pragma once
#include <complex>
#include <iomanip>
// Independent CPU complex transform, compared with GPU samples by the browser checks.
void cpuInverse(std::vector<std::complex<double>>& a){
 for(int i=1,j=0;i<256;i++){int bit=128;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)std::swap(a[i],a[j]);}
 for(int n=2;n<=256;n*=2){auto root=std::polar(1.0,2*3.141592653589793/n);for(int base=0;base<256;base+=n){std::complex<double>w=1;for(int j=0;j<n/2;j++){auto u=a[base+j],v=a[base+j+n/2]*w;a[base+j]=u+v;a[base+j+n/2]=u-v;w*=root;}}}
}
std::vector<float> cpuOcean(float time=3,float wind=1,int seed=42){
 std::vector<float2> spatial(4*65536);std::vector<std::complex<double>> line(256);
 for(int layer=0;layer<4;layer++)for(int y=0;y<256;y++)for(int x=0;x<256;x++)spatial[layer*65536+y*256+x]=evolveSpectrum(x,y,layer,time,wind,seed);
 for(int axis=0;axis<2;axis++)for(int layer=0;layer<4;layer++)for(int row=0;row<256;row++){
  for(int i=0;i<256;i++){int ix=layer*65536+(axis==0?row*256+i:i*256+row);line[i]={spatial[ix].x,spatial[ix].y};}
  cpuInverse(line);for(int i=0;i<256;i++){int ix=layer*65536+(axis==0?row*256+i:i*256+row);spatial[ix]={(float)line[i].real(),(float)line[i].imag()};}
 }
 double sum=0;float maxH=0,maxImag=0;for(const auto&v:spatial){sum+=v.x*v.x;maxH=fmaxf(maxH,fabsf(v.x));maxImag=fmaxf(maxImag,fabsf(v.y));}
 std::cout<<"Spectral ocean: cascade RMS="<<sqrt(sum/spatial.size())<<", peak="<<maxH<<", imaginary residual="<<maxImag<<"\n";
 if(maxImag>.0001f||maxH<.1f||!std::isfinite(maxH))throw std::runtime_error("Invalid Fourier ocean");
 float controls[16]={};controls[5]=time;controls[15]=-1;
 std::vector<float> waves(4*OCEAN_TEXELS*4+4);blockDim={1,1,1};
 for(int layer=0;layer<4;layer++){blockIdx={0,0,(unsigned)layer};for(int y=0;y<256;y++)for(int x=0;x<256;x++){threadIdx={(unsigned)x,(unsigned)y,0};packOcean(controls,spatial.data(),waves.data());}}
 for(int level=1;level<=8;level++){int n=256>>level;for(int layer=0;layer<4;layer++){blockIdx={0,0,(unsigned)layer};for(int y=0;y<n;y++)for(int x=0;x<n;x++){threadIdx={(unsigned)x,(unsigned)y,0};oceanMip(waves.data(),level);}}}
 return waves;
}
