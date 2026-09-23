// Experimental CUDA-WebShader build-time backend. The existing frontend validates
// CUDA and supplies the ABI; Emscripten/LLVM lowers the same CUDA bodies to WASM.
import {compile} from '../compiler/compiler.js';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
const types={f32:'float',i32:'int',u32:'unsigned int',bool:'bool'};
export async function compileWasm(source,options,{outDir,emcc=process.env.EMXX||'em++'}={}){
 // Sequential invocation cannot emulate workgroup cooperation. Fail closed.
 const code=source.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,'');
 if(/\b(__shared__|__syncthreads|atomic\w*|__shfl\w*|__syncwarp)\b/.test(code))throw Error('WASM prototype supports independent invocations only; shared memory, barriers and atomics are unsupported.');
 const artifact=compile(source,options),{kernel}=artifact;
 const params=kernel.params.map(p=>{
  if(!types[p.type]||p.reference)throw Error('Unsupported WASM parameter '+p.name);
  return `${p.constant?'const ':''}${types[p.type]}${p.pointer?'*':''} ${p.name}`;
 });
 const wg=options.workgroupSize||[1,1,1];
 const shim=await readFile(new URL('./cuda-cpu.hpp',import.meta.url),'utf8');
 const wrapper=`\nextern "C" void cw_dispatch(unsigned gx,unsigned gy,unsigned gz,${params.join(',')}){\nblockDim={${wg.join(',')}};gridDim={gx,gy,gz};\nfor(unsigned bz=0;bz<gz;bz++)for(unsigned by=0;by<gy;by++)for(unsigned bx=0;bx<gx;bx++){blockIdx={bx,by,bz};\nfor(unsigned tz=0;tz<${wg[2]};tz++)for(unsigned ty=0;ty<${wg[1]};ty++)for(unsigned tx=0;tx<${wg[0]};tx++){threadIdx={tx,ty,tz};${kernel.name}(${kernel.params.map(p=>p.name).join(',')});}}}\n`;
 await mkdir(outDir,{recursive:true});
 const cpp=path.join(outDir,options.entry+'.cpp'),js=path.join(outDir,options.entry+'.mjs');
 await writeFile(cpp,shim+'\n'+source+wrapper);
 const args=[cpp,'-O3','-msimd128','-std=c++17','-fno-exceptions','-sMODULARIZE=1','-sEXPORT_ES6=1','-sENVIRONMENT=web,worker,node','-sALLOW_MEMORY_GROWTH=1','-sFILESYSTEM=0','-sEXPORTED_FUNCTIONS=["_cw_dispatch","_malloc","_free"]','-sEXPORTED_RUNTIME_METHODS=["HEAPU8","HEAPF32","HEAP32"]','-o',js];
 // Invoke the Python driver directly on Windows: no shell argument rewriting.
 const batch=process.platform==='win32'&&/\.(bat|cmd)$/i.test(emcc);
 const result=batch?spawnSync(process.env.EMSDK_PYTHON||'python',[emcc.replace(/\.(bat|cmd)$/i,'.py'),...args],{encoding:'utf8'}):spawnSync(emcc,args,{encoding:'utf8'});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 const {ast,kernel:unused,...portable}=artifact;
 await writeFile(path.join(outDir,options.entry+'.json'),JSON.stringify(portable));
 await writeFile(path.join(outDir,options.entry+'.abi.json'),JSON.stringify({entry:kernel.name,workgroupSize:wg,params:kernel.params.map(({name,type,pointer,constant})=>({name,type,pointer,constant}))},null,2));
 return portable;
}

