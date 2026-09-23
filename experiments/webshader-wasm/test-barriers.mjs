import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {fileURLToPath} from 'node:url';
import {compileThreaded} from './compiler/threaded.mjs';import {ThreadedProgram} from './threaded-runtime.js';
const source=`
__global__ void reduction(unsigned int* Output){
 __shared__ unsigned int values[8];__shared__ unsigned int offsets[8];
 int lane=(int)threadIdx.x;values[lane]=(unsigned int)lane+1u;offsets[lane]=blockIdx.x*100u;__syncthreads();
 for(int step=4;step>0;step>>=1){if(lane<step)values[lane]+=values[lane+step];__syncthreads();}
 if(lane==0)Output[blockIdx.x]=values[0]+offsets[7];
}
__global__ void divergent(unsigned int* Output){
 if(threadIdx.x==0)return;__syncthreads();Output[blockIdx.x*8+threadIdx.x]=1u;
}`;
const outDir=fileURLToPath(new URL('./generated/',import.meta.url));await compileThreaded(source,[{entry:'reduction',workgroupSize:[8,1,1]},{entry:'divergent',workgroupSize:[8,1,1]}],{outDir,name:'barriers'});
const {default:create}=await import('./generated/barriers.mjs'),abi=JSON.parse(await readFile(new URL('./generated/barriers.abi.json',import.meta.url),'utf8'));
const p=new ThreadedProgram(await create({wasmBinary:await readFile(new URL('./generated/barriers.wasm',import.meta.url))}),abi,4);
try{const Output=p.alloc(4096*8*4);p.dispatch('reduction',[4096,1,1],{Output});const a=new Uint32Array(p.read(Output).buffer);for(let i=0;i<4096;i++)assert.equal(a[i],36+i*100);assert.ok(p.groups().filter(n=>n>0).length>1);assert.throws(()=>p.dispatch('divergent',[2,1,1],{Output}),/Divergent/);console.log('PASS: generic shared arrays, repeated barriers, local-state preservation, isolated workgroups, real parallel workers, divergent barrier detection.');p.dispose();process.exit(0);}catch(e){console.error(e);p.dispose();process.exit(1);}
