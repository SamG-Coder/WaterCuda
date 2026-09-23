import create from './generated/world.mjs';
import {ThreadedProgram,WasmWorld} from './threaded-runtime.js';
let program,world;
self.onmessage=async({data})=>{
 try{
  if(data.type==='init'){
   if(!crossOriginIsolated)throw Error('Shared WASM threads require COOP/COEP. Run this experiment\'s server.mjs on port 8091.');
   const [wasmBinary,abi]=await Promise.all([fetch('./generated/world.wasm').then(r=>r.arrayBuffer()),fetch('./generated/world.abi.json').then(r=>r.json())]);
   program=new ThreadedProgram(await create({wasmBinary}),abi,data.threads);
   world=new WasmWorld(program,data.width,data.height,s=>postMessage({type:'progress',message:s}));postMessage({type:'ready',threads:program.threads});return;
  }
  if(data.type==='frame'){
   const result=world.frame(data.camera,data.origin),pixels=new Uint8Array(result.pixels);postMessage({type:'frame',...result,pixels:pixels.buffer,width:world.width,height:world.height},[pixels.buffer]);
  }
 }catch(e){postMessage({type:'error',message:String(e.stack||e)});}
};
