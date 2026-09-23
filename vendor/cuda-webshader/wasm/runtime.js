export class ThreadedProgram{
 constructor(module,abi,threads=4){
  this.module=module;this.kernels=new Map(abi.kernels.map(k=>[k.entry,k]));this.buffers=[];
  if(!(module.HEAPU8.buffer instanceof SharedArrayBuffer))throw Error('WASM memory is not shared');
  if(module._cw_init(threads)!==threads)throw Error('Failed to start WASM thread pool');this.threads=threads;
 }
 alloc(bytes){const ptr=this.module._malloc(bytes);if(!ptr)throw Error('WASM allocation failed');const b={ptr,bytes};this.buffers.push(b);this.module.HEAPU8.fill(0,ptr,ptr+bytes);return b;}
 write(b,view){if(view.byteLength>b.bytes)throw Error('Buffer overflow');this.module.HEAPU8.set(new Uint8Array(view.buffer,view.byteOffset,view.byteLength),b.ptr);}
 read(b){return this.module.HEAPU8.slice(b.ptr,b.ptr+b.bytes);}
 dispatch(name,groups,values){
  const k=this.kernels.get(name);if(!k)throw Error('Unknown kernel '+name);
  if(groups.length!==3||groups.some(n=>!Number.isInteger(n)||n<1)||groups.reduce((a,b)=>a*b,1)>1e8)throw Error('Invalid dispatch size');
  const args=k.params.map(p=>{const v=values[p.name];if(v===undefined)throw Error('Missing '+name+'.'+p.name);return p.pointer?v.ptr:v;});
  const code=this.module['_cw_'+name](...groups,...args);if(code)throw Error('Divergent workgroup barrier in '+name);
 }
 groups(){return Array.from({length:this.threads},(_,i)=>this.module._cw_worker_groups(i));}
 dispose(){this.module._cw_shutdown();for(const b of this.buffers)this.module._free(b.ptr);this.buffers=[];}
}
