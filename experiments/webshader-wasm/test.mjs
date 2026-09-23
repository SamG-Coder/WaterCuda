import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {compileWasm} from './compiler/wasm.mjs';
import {WasmKernel} from './wasm-runtime.js';
const dir=new URL('./generated/',import.meta.url);
const source=`__global__ void abiProbe(const float* A,unsigned int* B,int width,float gain){
int x=(int)(blockIdx.x*blockDim.x+threadIdx.x),y=(int)(blockIdx.y*blockDim.y+threadIdx.y),z=(int)(blockIdx.z*blockDim.z+threadIdx.z);
int i=(z*6+y)*width+x;if(x<width)B[i]=(unsigned int)(A[i]*gain)+blockIdx.x+threadIdx.y*100u+gridDim.z*1000u;}`;
await compileWasm(source,{entry:'abiProbe',workgroupSize:[4,2,2]},{outDir:fileURLToPath(dir)});
async function load(name){const {default:create}=await import(new URL(name+'.mjs',dir));return new WasmKernel(await create({wasmBinary:await readFile(new URL(name+'.wasm',dir))}),JSON.parse(await readFile(new URL(name+'.abi.json',dir),'utf8')));}
const probe=await load('abiProbe'),A=Float32Array.from({length:7*6*4},(_,i)=>i+.25),B=new Uint32Array(A.length);
probe.dispatch([2,3,2],{A,B,width:7,gain:2});
for(let z=0;z<4;z++)for(let y=0;y<6;y++)for(let x=0;x<7;x++){const i=(z*6+y)*7+x;assert.equal(B[i],Math.trunc(A[i]*2)+Math.floor(x/4)+(y%2)*100+2000);}
probe.dispose();
await assert.rejects(()=>compileWasm('__global__ void bad(float* x){__syncthreads();x[0]=1;}',{entry:'bad'},{outDir:fileURLToPath(dir)}),/independent invocations/);
const preview=await load('previewWorld'),C=new Float32Array([1850,25,1250,.15,-.30,3,1,-.7,22,1,0,1,1.5,1,0,0]),Origin=new Int32Array([0,0,884,0]);
function frame(){const Pixels=new Uint32Array(160*90),t=performance.now();preview.dispatch([20,12,1],{C,Origin,Pixels,width:160,height:90});console.log('WASM preview frame ms:',(performance.now()-t).toFixed(1));return Pixels;}
const first=frame();assert.ok(new Set(first).size>500);assert.ok(first.every(p=>(p>>>24)===255));assert.deepEqual(frame(),first);Origin[2]=42;assert.notDeepEqual(frame(),first);Origin[2]=884;C[3]+=.3;assert.notDeepEqual(frame(),first);preview.dispose();
console.log('PASS: generated ABI, 3D dispatch, scalar/buffer types, barrier rejection, deterministic preview, seed and camera changes.');
