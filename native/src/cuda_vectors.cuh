// Native vector operators only. Scene algorithms stay in the shared kernels/ files.
#pragma once
#include <cuda_runtime.h>
__host__ __device__ inline float3 operator+(float3 a,float3 b){return make_float3(a.x+b.x,a.y+b.y,a.z+b.z);}
__host__ __device__ inline float3 operator-(float3 a,float3 b){return make_float3(a.x-b.x,a.y-b.y,a.z-b.z);}
__host__ __device__ inline float3 operator*(float3 a,float b){return make_float3(a.x*b,a.y*b,a.z*b);}
__host__ __device__ inline float3 operator*(float b,float3 a){return a*b;}
__host__ __device__ inline float3 operator*(float3 a,float3 b){return make_float3(a.x*b.x,a.y*b.y,a.z*b.z);}
__host__ __device__ inline float3 operator/(float3 a,float b){return make_float3(a.x/b,a.y/b,a.z/b);}
