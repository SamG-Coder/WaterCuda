import {correctShip} from './flight.js';
import {CpuResolution} from './cpu-resolution.js';
export class WasmStartup{
 constructor(canvas,{onFrame,onError}){
  this.canvas=canvas;this.context=canvas.getContext('2d');this.onFrame=onFrame;this.onError=onError;
  this.ready=false;this.busy=false;this.stopped=false;
  this.resolution=new CpuResolution();
  this.first=new Promise(resolve=>this.resolveFirst=resolve);
  this.worker=new Worker(new URL('../experiments/webshader-wasm/threaded-worker.js',import.meta.url),{type:'module'});
  this.worker.onerror=event=>this.fail(event.message);
  this.worker.onmessage=({data})=>{
   if(this.stopped)return;
   if(data.type==='ready'){this.ready=true;return;}
   if(data.type==='error'){this.fail(data.message);return;}
   if(data.type!=='frame')return;
   if(data.shipPose&&this.camera)correctShip(this.camera,this.requested,data.shipPose);
   this.busy=false;canvas.width=data.width;canvas.height=data.height;
   this.context.putImageData(new ImageData(new Uint8ClampedArray(data.pixels),data.width,data.height),0,0);
   this.resolution.observe(data.ms);
   const nis=this.presenter?.draw(data)||false;
   this.resolveFirst(true);this.onFrame({...data,nis});
   if(!this.presentationStarted&&typeof document!=='undefined'){
    this.presentationStarted=true;
    import('./nis-presenter.js').then(async({NisPresenter})=>{
     if(this.stopped)return;this.presenter=new NisPresenter();await this.presenter.init(canvas);
    }).catch(error=>{console.warn('NIS unavailable; keeping canvas scaling.',error);this.presenter?.dispose();});
   }
  };
  const threads=Math.max(1,Math.min(4,(navigator.hardwareConcurrency||4)-2));
  const width=128,height=Math.max(32,Math.min(256,Math.round(width*innerHeight/innerWidth)));
  this.worker.postMessage({type:'init',threads,width,height});
 }
 frame(camera,origin){
  if(!this.ready||this.busy||this.stopped)return;
  this.camera=camera;this.requested=camera.slice();this.busy=true;this.worker.postMessage({type:'frame',camera:camera.slice(),origin:origin.slice(),...this.resolution.size(innerWidth,innerHeight)});
 }
 fail(message){this.resolveFirst(false);this.onError(message);this.stop();}
 capture(){return this.presenter?.last&&!this.presenter.lost&&!this.presenter.stopped?this.presenter.capture():new Promise(resolve=>this.canvas.toBlob(resolve));}
 stop(){this.stopped=true;this.worker.terminate();this.presenter?.dispose();}
}
