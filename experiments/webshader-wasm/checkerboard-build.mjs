import {emitThreaded} from '../../vendor/cuda-webshader/wasm/compile.mjs';
import {writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
// CPU dispatch adaptation after WebShader code generation. CUDA bodies and ABI
// remain unchanged. C[27] selects full coverage (0) or diagonal phase (1/2).
export async function compileCheckerboard(source,specs,{outDir}){
 const tile=8;
 const renderEntries=new Set(['tracePrimary','traceVegetation','reflectOcean','shadeOcean']);
 const {cpp,kernels}=await emitThreaded(source,specs.map(s=>renderEntries.has(s.entry)?{...s,workgroupSize:[tile,tile,1]}:s));
 const adapted=cpp.split('\n').map(line=>{
  const entry=/^extern "C" int cw_(\w+)\(/.exec(line)?.[1];
  if(!renderEntries.has(entry))return line;
  const count=tile*tile;
  const loop=`for(unsigned lane=0;lane<${count};lane++){threadIdx={lane%${tile},(lane/${tile})%${tile},lane/${count}};`;
  if(!line.includes(loop))throw Error('Missing CPU lane loop '+entry);
  // Compact lane numbers map directly to the selected diagonal pair. No
  // inactive pixel iteration or per-pixel parity branch reaches the kernel.
  return line.replace(loop,`const bool checker=C[27]>=1;const unsigned phase=checker?(unsigned)(C[27]-1):0;for(unsigned lane=0;lane<(checker?${count/2}:${count});lane++){const unsigned row=checker?lane/${tile/2}:lane/${tile};threadIdx={checker?(lane%${tile/2})*2+((row+phase)&1):lane%${tile},row,0};`);

 }).join('\n');
 await mkdir(outDir,{recursive:true});const file=path.join(outDir,'world.cpp');await writeFile(file,adapted);
 const exports=['_malloc','_free','_cw_init','_cw_shutdown','_cw_worker_groups',...kernels.map(k=>'_cw_'+k.entry)];
 const args=[file,'-O3','-msimd128','-std=c++20','-pthread','-sPTHREAD_POOL_SIZE=7','-sPTHREAD_POOL_SIZE_STRICT=2','-sMODULARIZE=1','-sEXPORT_ES6=1','-sENVIRONMENT=web,worker,node','-sINITIAL_MEMORY=268435456','-sMAXIMUM_MEMORY=536870912','-sALLOW_MEMORY_GROWTH=1','-sFILESYSTEM=0','-sEXPORTED_FUNCTIONS='+JSON.stringify(exports),'-sEXPORTED_RUNTIME_METHODS=["HEAPU8","HEAPF32","HEAP32"]','-o',path.join(outDir,'world.mjs')];
 const emcc=process.env.EMXX||'em++',batch=process.platform==='win32'&&/\.(bat|cmd)$/i.test(emcc);
 const result=batch?spawnSync(process.env.EMSDK_PYTHON||'python',[emcc.replace(/\.(bat|cmd)$/i,'.py'),...args],{encoding:'utf8'}):spawnSync(emcc,args,{encoding:'utf8'});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 await writeFile(path.join(outDir,'world.abi.json'),JSON.stringify({name:'world',kernels,sharedMemory:true,maxThreads:8,checkerboard:true},null,2));return kernels;
}
