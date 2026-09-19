#pragma once
// CPU reference and regression tests for the SAME authored CUDA used by WebGPU.
// No claim of hardware GPU frame rate is made by this harness.
#include <algorithm>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <set>
#include <stdexcept>
#define __device__
#define __global__
#define __shared__
#define __syncthreads() ((void)0)
struct Index {unsigned x=0,y=0,z=0;};
thread_local Index threadIdx,blockIdx,blockDim,gridDim;
struct float2 {float x,y;};struct float3 {float x,y,z;};struct float4{float x,y,z,w;};
float2 make_float2(float x,float y){return {x,y};}float3 make_float3(float x,float y,float z){return {x,y,z};}float4 make_float4(float x,float y,float z,float w){return{x,y,z,w};}
float3 operator+(float3 a,float3 b){return{a.x+b.x,a.y+b.y,a.z+b.z};}float3 operator-(float3 a,float3 b){return{a.x-b.x,a.y-b.y,a.z-b.z};}
float3 operator*(float3 a,float b){return{a.x*b,a.y*b,a.z*b};}float3 operator*(float b,float3 a){return a*b;}float3 operator*(float3 a,float3 b){return{a.x*b.x,a.y*b.y,a.z*b.z};}
float3 operator/(float3 a,float b){return{a.x/b,a.y/b,a.z/b};}
unsigned int atomicAdd(unsigned int* p,unsigned int v){auto old=*p;*p+=v;return old;}
