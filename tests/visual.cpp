// Offline reference image of the actual CUDA functions, not a second renderer.
#include "cuda_compat.hpp"
#include "../kernels/common.cu"
#include "../kernels/terrain.cu"
#include "../kernels/ocean.cu"
#include "../kernels/render.cu"
#include "cpu-ocean.hpp"
int main(int argc,char**argv){try{
 if(argc<3){std::cerr<<"usage: visual OUTPUT.ppm coast|water|aerial|sunset [width] [seed]\n";return 1;}
 std::string view=argv[2];int width=argc>3?std::stoi(argv[3]):768,height=width*9/16,seed=argc>4?std::stoi(argv[4]):884;
 if(width<128||width>2560||seed<0)throw std::runtime_error("Width must be 128..2560 and seed nonnegative.");
 if(view!="coast"&&view!="water"&&view!="aerial"&&view!="sunset")throw std::runtime_error("Unknown view.");
 if(argc>5&&argc<10)throw std::runtime_error("A custom camera requires x y z yaw pitch.");
 float C[16]={1250,210,650,.52f,-.10f,3,1,-.7f,.7f,1,0,1,1,1,0,0};int O[4]={0,0,seed,0};
 if(view=="aerial"){C[0]=-300;C[1]=1400;C[2]=-300;C[3]=.70;C[4]=-.34;}
 if(view=="water"){C[0]=1550;C[1]=7;C[2]=1100;C[3]=.52;C[4]=.025;}
 if(view=="sunset"){C[7]=1.05;C[8]=.16;C[6]=.65;}
 if(argc>5){C[0]=std::stof(argv[5]);C[1]=std::stof(argv[6]);C[2]=std::stof(argv[7]);C[3]=std::stof(argv[8]);C[4]=std::stof(argv[9]);}
 auto waves=cpuOcean(C[5],C[6],seed);int count=width*height;std::vector<float> hit(count*4),surface(count*4),reflection(count*4);std::vector<unsigned int> pixels(count);
 #pragma omp parallel for
 for(int y=0;y<height;y++){blockDim={1,1,1};threadIdx={0,0,0};for(int x=0;x<width;x++){blockIdx={(unsigned)x,(unsigned)y,0};tracePrimary(C,O,waves.data(),hit.data(),surface.data(),width,height);}}
 #pragma omp parallel for
 for(int y=0;y<height;y++){blockDim={1,1,1};threadIdx={0,0,0};for(int x=0;x<width;x++){blockIdx={(unsigned)x,(unsigned)y,0};reflectOcean(C,O,hit.data(),surface.data(),reflection.data(),width,height);}}
 #pragma omp parallel for
 for(int y=0;y<height;y++){blockDim={1,1,1};threadIdx={0,0,0};for(int x=0;x<width;x++){blockIdx={(unsigned)x,(unsigned)y,0};shadeOcean(C,O,hit.data(),surface.data(),reflection.data(),waves.data(),pixels.data(),width,height);}}
 std::ofstream out(argv[1],std::ios::binary);if(!out)throw std::runtime_error("Cannot open image output.");out<<"P6\n"<<width<<" "<<height<<"\n255\n";
 for(auto p:pixels){char b[3]={(char)(p&255),(char)((p>>8)&255),(char)((p>>16)&255)};out.write(b,3);}std::cout<<"Rendered "<<argv[1]<<" (CPU reference)\n";
 return 0;
}catch(const std::exception& error){std::cerr<<error.what()<<"\n";return 1;}
}
