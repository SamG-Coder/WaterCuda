import {WasmKernel} from './wasm-runtime.js';
let kernel;
try{kernel=await WasmKernel.load(new URL('./generated/previewWorld',import.meta.url).href);postMessage({type:'ready'});}catch(e){postMessage({type:'error',message:String(e)});}
self.onmessage=({data})=>{
 if(!kernel)return;
 try{
  const {camera,origin,width,height,id}=data,pixels=new Uint32Array(width*height),start=performance.now();
  kernel.dispatch([Math.ceil(width/8),Math.ceil(height/8),1],{C:camera,Origin:origin,Pixels:pixels,width,height});
  postMessage({type:'frame',id,width,height,pixels:pixels.buffer,ms:performance.now()-start},[pixels.buffer]);
 }catch(e){postMessage({type:'error',message:String(e)});}
};
