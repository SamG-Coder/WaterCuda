#pragma once
// CPU vocabulary for WebShader's independent-invocation WASM backend.
// Unsupported GPU synchronization is rejected by the compiler, never no-op'd.
#include <cmath>
#include <cstdint>
#define __device__
#define __global__
struct Index {unsigned x=0,y=0,z=0;};
thread_local Index threadIdx,blockIdx,blockDim,gridDim;
struct float2 {float x,y;};struct float3 {float x,y,z;};struct float4{float x,y,z,w;};
float2 make_float2(float x,float y){return {x,y};}float3 make_float3(float x,float y,float z){return {x,y,z};}float4 make_float4(float x,float y,float z,float w){return{x,y,z,w};}
float3 operator+(float3 a,float3 b){return{a.x+b.x,a.y+b.y,a.z+b.z};}float3 operator-(float3 a,float3 b){return{a.x-b.x,a.y-b.y,a.z-b.z};}
float3 operator*(float3 a,float b){return{a.x*b,a.y*b,a.z*b};}float3 operator*(float b,float3 a){return a*b;}float3 operator*(float3 a,float3 b){return{a.x*b.x,a.y*b.y,a.z*b.z};}
float3 operator/(float3 a,float b){return{a.x/b,a.y/b,a.z/b};}
