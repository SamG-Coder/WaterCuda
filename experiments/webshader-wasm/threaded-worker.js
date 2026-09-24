import create from './generated/world.mjs';
import {ThreadedProgram,WasmWorld} from './threaded-runtime.js';
let program,world;
self.onmessage=async({data})=>{
 try{
  if(data.type==='init'){
   if(!crossOriginIsolated)throw Error('Shared WASM threads require cross-origin isolation.');
   const load=async(name,json)=>{const response=await fetch(new URL('./generated/'+name,import.meta.url));if(!response.ok)throw Error('WASM asset failed: '+response.status);return json?response.json():response.arrayBuffer();};
   const [wasmBinary,abi]=await Promise.all([load('world.wasm'),load('world.abi.json',true)]);
   program=new ThreadedProgram(await create({wasmBinary}),abi,data.threads);
   world=new WasmWorld(program,data.width,data.height,s=>postMessage({type:'progress',message:s}));postMessage({type:'ready',threads:program.threads});return;
  }
  if(data.type==='frame'){
   if(data.width&&data.height)world.resize(data.width,data.height);
   const result=world.frame(data.camera,data.origin,true),pixels=new Uint8Array(result.pixels);postMessage({type:'frame',...result,threads:program.threads,pixels:pixels.buffer,width:world.width,height:world.height},[pixels.buffer]);
  }
 }catch(e){postMessage({type:'error',message:String(e.stack||e)});}
};
