// Execute the exact CUDA atlas kernels in the native reference harness.
inline void buildShrubAtlas(float* data){
 blockDim={1,1,1};threadIdx={0,0,0};
 for(int t=0;t<8;t++)for(int y=0;y<128;y++)for(int x=0;x<128;x++){blockIdx={(unsigned)x,(unsigned)y,(unsigned)t};generateShrubAtlas(data);}
 for(int level=1;level<8;level++)for(int t=0;t<8;t++)for(int y=0;y<(128>>level);y++)for(int x=0;x<(128>>level);x++){blockIdx={(unsigned)x,(unsigned)y,(unsigned)t};mipShrubAtlas(data,level);}
}
