import {trimWgsl} from './wgsl-trim.js';import {SPECS,compilerOptions} from './kernel-specs.js';import {COMPILER_STAMP} from './compiler-stamp.js';
export class KernelLoader{
 constructor(runtime,onProgress=()=>{}){this.runtime=runtime;this.onProgress=onProgress;this.sources=new Map();this.loaded=new Map();this.timings=[];this.workers=[];this.nextWorker=0;this.nextId=0;this.pending=new Map();this.workerCount=Math.max(2,Math.min(6,Number(globalThis.navigator?.hardwareConcurrency||4)-1));}
 emit(event){this.onProgress(event);}
 getWorker(){
  if(typeof Worker==='undefined')return null;
  if(this.workers.length<this.workerCount){const worker=new Worker(new URL('./compiler-worker.js',import.meta.url),{type:'module'});worker._busy=0;
   worker.onmessage=({data})=>{const p=this.pending.get(data.id);if(!p)return;this.pending.delete(data.id);worker._busy=Math.max(0,worker._busy-1);data.error?p.reject(Error(data.error)):p.resolve(data.artifact);};
   worker.onerror=e=>{for(const [id,p]of this.pending){if(p.worker===worker){this.pending.delete(id);p.reject(Error(e.message||'Compiler worker failed'));}}worker._busy=0;};
   this.workers.push(worker);
  }
  let best=this.workers[0];for(const w of this.workers)if(w._busy<best._busy)best=w;return best;
 }
 async text(name){if(!this.sources.has(name))this.sources.set(name,(async()=>{const r=await fetch(new URL('../kernels/'+name+'.cu',import.meta.url),{cache:'no-cache'});if(!r.ok)throw Error('Missing CUDA source '+name);return r.text();})());return this.sources.get(name);}
 async compile(source,spec){
  const worker=this.getWorker();if(!worker){const {compile}=await import('../vendor/cuda-webshader/compiler/compiler.js');const {ast,kernel,...a}=compile(source,compilerOptions(spec));return a;}
  return new Promise((resolve,reject)=>{const id=++this.nextId;worker._busy++;this.pending.set(id,{resolve,reject,worker});worker.postMessage({id,source,spec});});
 }
 async load(entry,progress=0){
  if(this.loaded.has(entry))return this.loaded.get(entry);
  const spec=SPECS.find(s=>s.entry===entry);if(!spec)throw Error('Unknown kernel '+entry);
  const begun=performance.now(),source=(await Promise.all(spec.dependencies.map(n=>this.text(n)))).join('\n'),lines=source.split('\n').length,bytesLength=new TextEncoder().encode(source).byteLength;
  this.emit({type:'queued',entry,message:'Source ready',progress,lines,bytes:bytesLength});
  const bytes=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(COMPILER_STAMP+'|specialize|'+entry+'|'+spec.workgroupSize.join(',')+'|'+source)));
  const hash=Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join(''),cacheURL=new URL('../.city-shader-cache/'+hash+'.json',import.meta.url);let artifact,origin='runtime',cache=null;
  try{if(globalThis.caches)cache=await caches.open('stratum-city-shaders-v2-specialize');const hit=await cache?.match(cacheURL);if(hit){const a=await hit.json();if(a.stratumHash===hash){artifact=a;origin='browser cache';}}}catch{/* Private-mode/quota failures cannot block startup. */}
  if(!artifact){try{const r=await fetch(new URL('../generated/'+entry+'.json',import.meta.url),{cache:'no-cache'});if(r.ok){const a=await r.json();if(a.stratumHash===hash&&a.compilerStamp===COMPILER_STAMP){artifact=a;origin='verified build';}}}catch{/* generated/ is an optional boot accelerator, not a dependency. */}}
  if(!artifact){this.emit({type:'compile-start',entry,message:'CUDA → WGSL',progress,lines,bytes:bytesLength});artifact=await this.compile(source,spec);this.emit({type:'compile-done',entry,message:'WGSL ready',progress,lines,bytes:bytesLength});artifact.stratumHash=hash;artifact.compilerStamp=COMPILER_STAMP;}
  if(!artifact.metadata||artifact.metadata.bindings.length>8||artifact.metadata.workgroupStorageBytes>16384)throw Error('Invalid portable shader budget for '+entry);
  try{await cache?.put(cacheURL,new Response(JSON.stringify(artifact),{headers:{'Content-Type':'application/json'}}));}catch{}
  const translated=performance.now(),rawWgslBytes=artifact.wgsl?.length||0,trimBegun=performance.now(),trimmed=trimWgsl(artifact),trimMs=performance.now()-trimBegun;artifact=trimmed.artifact;
  const trimStats={...trimmed.stats,trimMs};this.emit({type:'trim-done',entry,message:'WGSL trimmed',progress,lines,bytes:bytesLength,trim:trimStats});
  this.emit({type:'pipeline-start',entry,message:'GPU pipeline · '+origin,progress,lines,bytes:bytesLength,trim:trimStats});
  const kernel=await this.runtime.kernel(artifact);this.loaded.set(entry,kernel);const timing={entry,source:origin,loadOrTranslateMs:translated-begun,trimMs,pipelineMs:performance.now()-translated};this.timings.push(timing);this.emit({type:'done',entry,message:origin,progress,timing,lines,bytes:bytesLength,trim:trimStats});return kernel;
 }
 dispose(){for(const w of this.workers)w.terminate();this.workers=[];for(const p of this.pending.values())p.reject(Error('Compiler disposed'));this.pending.clear();}
}
