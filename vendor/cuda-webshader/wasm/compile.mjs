import {compile} from '../compiler/compiler.js';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
const types={f32:'float',i32:'int',u32:'unsigned int',bool:'bool','vec2<f32>':'float2','vec3<f32>':'float3','vec4<f32>':'float4'};
const strip=s=>s.replace(/\/\*[\s\S]*?\*\//g,m=>m.replace(/[^\n]/g,' ')).replace(/\/\/[^\n]*/g,m=>' '.repeat(m.length));
export async function emitThreaded(source,specs){
 if(!Array.isArray(specs)||!specs.length)throw Error('At least one kernel specification is required.');
 if(new Set(specs.map(s=>s.entry)).size!==specs.length)throw Error('Duplicate kernel entry.');
 const cleaned=strip(source);
 if(/\b(atomic\w*|__shfl\w*|__syncwarp)\b/.test(cleaned))throw Error('Atomics and warp intrinsics are not implemented by this experimental backend.');
 const kernels=[],replacements=[],wrappers=[];
 // Parse real entry points with WebShader; never derive an ABI from handwritten JS.
 for(const spec of specs){
  const artifact=compile(source,{entry:spec.entry,workgroupSize:spec.workgroupSize,optimize:'specialize'}),k=artifact.kernel;
  const params=k.params.map(p=>{if(!types[p.type]||p.reference)throw Error('Unsupported parameter '+p.name);return `${p.constant?'const ':''}${types[p.type]}${p.pointer?'*':''} ${p.name}`;});
  const match=new RegExp('\\b__global__\\s+void\\s+'+spec.entry+'\\s*\\([^)]*\\)\\s*\\{').exec(cleaned);if(!match)throw Error('Entry source not found: '+spec.entry);
  const begin=match.index,bodyBegin=begin+match[0].length;let end=bodyBegin,depth=1;for(;end<cleaned.length&&depth;end++){if(cleaned[end]==='{')depth++;if(cleaned[end]==='}')depth--;}
  let body=source.slice(bodyBegin,end-1);const shared=[];
  body=body.replace(/__shared__\s+(float[234]?|int|unsigned\s+int)\s+(\w+)\s*\[\s*(\d+)\s*\]\s*;/g,(_,type,id,size)=>{shared.push({type,id,size});return '';});
  if(/__shared__/.test(strip(body)))throw Error('Only fixed-size workgroup arrays are currently supported.');
  const cooperative=/__syncthreads\s*\(/.test(strip(body));
  if(shared.length&&!cooperative)throw Error('Shared arrays require a cooperating kernel in this prototype.');
  if(cooperative){
   // Locals survive barriers in coroutine frames. Shared arrays belong to the
   // workgroup stack and are passed to every lane of that workgroup.
   let barrier=0;body=body.replace(/__syncthreads\s*\(\s*\)\s*;/g,()=>`co_await CwBarrier{${barrier++}};`).replace(/\breturn\s*;/g,'co_return;');
   replacements.push({begin,end,text:`CwLane ${spec.entry}(${[...params,...shared.map(s=>s.type+'* '+s.id)].join(',')}){${body}\nco_return;}`});
  }
  const wg=spec.workgroupSize,n=wg[0]*wg[1]*wg[2],args=k.params.map(p=>p.name).join(',');
  const setup=`blockDim={${wg.join(',')}};gridDim={gx,gy,gz};blockIdx={index%gx,(index/gx)%gy,index/(gx*gy)};`;
  const index=`threadIdx={lane%${wg[0]},(lane/${wg[0]})%${wg[1]},lane/${wg[0]*wg[1]}};`;
  const work=cooperative?`${shared.map(s=>`${s.type} ${s.id}[${s.size}];`).join('\n')}
   cw_lane_used=0;CwLane lanes[${n}];for(unsigned lane=0;lane<${n};lane++){${index}lanes[lane]=${spec.entry}(${args}${shared.map(s=>','+s.id).join('')});}
   for(;;){unsigned finished=0;int site=-1;bool mismatch=false;for(unsigned lane=0;lane<${n};lane++){${index}auto h=lanes[lane].handle;if(!h.done())h.resume();if(h.done())finished++;else{int current=h.promise().barrier;if(site<0)site=current;else if(site!=current)mismatch=true;}}if(finished==${n})break;if(finished||mismatch){cw_fault=1;break;}}
   for(auto l:lanes)l.handle.destroy();`:`for(unsigned lane=0;lane<${n};lane++){${index}${spec.entry}(${args});}`;
  wrappers.push(`extern "C" int cw_${spec.entry}(unsigned gx,unsigned gy,unsigned gz,${params.join(',')}){return cw_parallel(gx*gy*gz,[=](unsigned index){${setup}${work}});}`);
  kernels.push({entry:spec.entry,workgroupSize:wg,cooperative,params:k.params.map(({name,type,pointer,constant})=>({name,type,pointer,constant}))});
 }
 for(const r of replacements.sort((a,b)=>b.begin-a.begin))source=source.slice(0,r.begin)+r.text+source.slice(r.end);
 if(/__shared__|__syncthreads/.test(strip(source)))throw Error('Unlowered cooperative code outside selected kernel entries.');
 const shim=await readFile(new URL('./cuda-cpu.hpp',import.meta.url),'utf8'),pool=await readFile(new URL('./thread-pool.hpp',import.meta.url),'utf8');
 return {cpp:shim+'\n'+pool+'\n'+source+'\n'+wrappers.join('\n'),kernels};
}
export async function compileThreaded(source,specs,{outDir,emcc=process.env.EMXX||'em++',name='world'}={}){
 if(!outDir||!/^[A-Za-z_]\w*$/.test(name))throw Error('Provide outDir and a simple module name.');
 const emitted=await emitThreaded(source,specs),{kernels}=emitted;
 await mkdir(outDir,{recursive:true});
 const cpp=path.join(outDir,name+'.cpp');await writeFile(cpp,emitted.cpp);
 const exports=['_malloc','_free','_cw_init','_cw_shutdown','_cw_worker_groups',...kernels.map(k=>'_cw_'+k.entry)];
 const args=[cpp,'-O3','-msimd128','-std=c++20','-pthread','-sPTHREAD_POOL_SIZE=7','-sPTHREAD_POOL_SIZE_STRICT=2','-sMODULARIZE=1','-sEXPORT_ES6=1','-sENVIRONMENT=web,worker,node','-sINITIAL_MEMORY=268435456','-sMAXIMUM_MEMORY=536870912','-sALLOW_MEMORY_GROWTH=1','-sFILESYSTEM=0','-sEXPORTED_FUNCTIONS='+JSON.stringify(exports),'-sEXPORTED_RUNTIME_METHODS=["HEAPU8","HEAPF32","HEAP32"]','-o',path.join(outDir,name+'.mjs')];
 const batch=process.platform==='win32'&&/\.(bat|cmd)$/i.test(emcc);
 const result=batch?spawnSync(process.env.EMSDK_PYTHON||'python',[emcc.replace(/\.(bat|cmd)$/i,'.py'),...args],{encoding:'utf8'}):spawnSync(emcc,args,{encoding:'utf8'});
 if(result.error||result.status!==0)throw Error(result.error?.message||result.stderr||result.stdout);
 await writeFile(path.join(outDir,name+'.abi.json'),JSON.stringify({name,kernels,sharedMemory:true,maxThreads:8},null,2));return kernels;
}
