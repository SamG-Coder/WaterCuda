export class WasmStartup{
 constructor(canvas,{onFrame,onError}){
  this.canvas=canvas;this.context=canvas.getContext('2d');this.onFrame=onFrame;this.onError=onError;
  this.ready=false;this.busy=false;this.stopped=false;
  this.first=new Promise(resolve=>this.resolveFirst=resolve);
  this.worker=new Worker(new URL('../experiments/webshader-wasm/threaded-worker.js',import.meta.url),{type:'module'});
  this.worker.onerror=event=>this.fail(event.message);
  this.worker.onmessage=({data})=>{
   if(this.stopped)return;
   if(data.type==='ready'){this.ready=true;return;}
   if(data.type==='error'){this.fail(data.message);return;}
   if(data.type!=='frame')return;
   this.busy=false;canvas.width=data.width;canvas.height=data.height;
   this.context.putImageData(new ImageData(new Uint8ClampedArray(data.pixels),data.width,data.height),0,0);
   this.resolveFirst(true);this.onFrame(data);
  };
  const threads=Math.max(1,Math.min(4,(navigator.hardwareConcurrency||4)-2));
  const width=128,height=Math.max(32,Math.min(256,Math.round(width*innerHeight/innerWidth)));
  this.worker.postMessage({type:'init',threads,width,height});
 }
 frame(camera,origin){
  if(!this.ready||this.busy||this.stopped)return;
  this.busy=true;this.worker.postMessage({type:'frame',camera:camera.slice(),origin:origin.slice()});
 }
 fail(message){this.resolveFirst(false);this.onError(message);this.stop();}
 stop(){this.stopped=true;this.worker.terminate();}
}
