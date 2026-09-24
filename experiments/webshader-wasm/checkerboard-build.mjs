import {emitThreaded} from '../../vendor/cuda-webshader/wasm/compile.mjs';
import {writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
// CPU dispatch adaptation after WebShader code generation. CUDA bodies and ABI
// remain unchanged. C[27] selects full coverage (0) or diagonal phase (1/2).
export async function compileCheckerboard(source,specs,{outDir}){
 const {cpp,kernels}=await emitThreaded(source,specs);
 const entries=new Set(['tracePrimary','traceVegetation','reflectOcean','shadeOcean']);
 const adapted=cpp.split('\n').map(line=>{
  const entry=/^extern "C" int cw_(\w+)\(/.exec(line)?.[1];
  if(!entries.has(entry))return line;
  const call=entry+'(';const at=line.lastIndexOf(call);
  if(at<0)throw Error('Missing CPU wrapper '+entry);
  return line.slice(0,at)+'if(C[27]<1 || ((blockIdx.x*blockDim.x+threadIdx.x+blockIdx.y*blockDim.y+threadIdx.y)&1)==(unsigned)(C[27]-1))'+line.slice(at);
 }).join('\n');
 await mkdir(outDir,{recursive:true});const file=path.join(outDir,'world.cpp');await writeFile(file,adapted);
 const exports=['_malloc','_free','_cw_init','_cw_shutdown','_cw_worker_groups',...kernels.map(k=>'_cw_'+k.entry)];
 const args=[file,'-O3','-msimd128','-std=c++20','-pthread','-sPTHREAD_POOL_SIZE=7','-sPTHREAD_POOL_SIZE_STRICT=2','-sMODULARIZE=1','-sEXPORT_ES6=1','-sENVIRONMENT=web,worker,node','-sINITIAL_MEMORY=268435456','-sMAXIMUM_MEMORY=536870912','-sALLOW_MEMORY_GROWTH=1','-sFILESYSTEM=0','-sEXPORTED_FUNCTIONS='+JSON.stringify(exports),'-sEXPORTED_RUNTIME_METHODS=["HEAPU8","HEAPF32","HEAP32"]','-o',path.join(outDir,'world.mjs')];
 const emcc=process.env.EMXX||'em++',batch=process.platform==='win32'&&/\.(bat|cmd)$/i.test(emcc);
 const result=batch?spawnSync(process.env.EMSDK_PYTHON||'python',[emcc.replace(/\.(bat|cmd)$/i,'.py'),...args],{encoding:'utf8'}):spawnSync(emcc,args,{encoding:'utf8'});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 await writeFile(path.join(outDir,'world.abi.json'),JSON.stringify({name:'world',kernels,sharedMemory:true,maxThreads:8,checkerboard:true},null,2));return kernels;
}
