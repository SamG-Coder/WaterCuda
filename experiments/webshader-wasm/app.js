import {FlightInput,moveCamera} from '../../src/flight.js';
import {parseSeed} from '../../src/world.js';
const $=id=>document.getElementById(id),query=new URLSearchParams(location.search),start=performance.now();
const camera=new Float32Array([1850,25,1250,.15,-.30,0,1,-.7,22,1,0,1,1.5,1,0,0]);
const origin=new Int32Array([0,0,parseSeed(query.get('seed')??884),0]);$('seed').value=origin[2];
if(query.get('target')==='preview')$('target').value='preview';
let speed=60,paused=false,busy=false,ready=false,engine=null,gpuPreview=null,handed=false,first=null,lastFrame=0,previewMs=0,sequence=0,last=performance.now(),gpuStarted=false,previewState=null,sentState=null;
const metrics={};const note=s=>{$('events').textContent+=`${((performance.now()-start)/1000).toFixed(2)}s ${s}\n`;$('events').scrollTop=$('events').scrollHeight;};
if(query.has('record'))import('./record-demo.js').then(({recordDemo})=>recordDemo(()=>handed?$('gpu'):$('cpu'),()=>({handed,first,previewMs,...metrics}))).catch(e=>note(e.message));
const input=new FlightInput($('input'),camera,{onSpeed:d=>speed=Math.max(3,speed*Math.exp(-d*.001))});
const threaded=query.get('cpu')!=='preview';
if(threaded){$('target').value='full';$('target').disabled=true;}
const threads=Math.max(1,Math.min(8,Number(query.get('threads')||4)|0));
const worker=new Worker(new URL(threaded?'./threaded-worker.js':'./worker.js',import.meta.url),{type:'module'}),ctx=$('cpu').getContext('2d');
const width=threaded?Math.max(64,Math.min(384,Math.round((Number(query.get('width'))||128)/64)*64)):160,height=Math.round(width*9/16);
if(threaded)worker.postMessage({type:'init',width,height,threads});
let stage='Loading WASM',lastTimings={};
worker.onerror=e=>note('Worker error: '+e.message);
worker.onmessage=({data})=>{
 if(data.type==='ready'){ready=true;note('Generated WASM loaded'+(threaded?` · ${data.threads} shared-memory threads`:''));return;}
 if(data.type==='progress'){stage=data.message;return;}
 if(data.type==='error'){busy=false;note('WASM error: '+data.message);return;}
 busy=false;previewMs=data.ms;lastTimings=data.timings||{};if(handed)return;
 $('cpu').width=data.width;$('cpu').height=data.height;ctx.putImageData(new ImageData(new Uint8ClampedArray(data.pixels),data.width,data.height),0,0);
 previewState={...sentState,pixels:new Uint8Array(data.pixels)};
 if(first===null){first=performance.now()-start;metrics.firstPreviewMs=first;note('First WASM image');if(query.get('auto')!=='0')startGpu();}
};
$('apply').onclick=()=>{try{origin[2]=parseSeed($('seed').value);note('Seed '+origin[2]);}catch(e){note(e.message);}};
$('scene').onchange=()=>{const name=$('scene').value;camera.set({shore:[1850,25,1250,.15,-.30],aerial:[-300,1400,-300,.70,-.34],reef:[4377,-7,2784,0,-.12],coral:[4377,-7.3,2810.8,0,-.18]}[name]);origin[0]=origin[1]=0;camera[14]=name==='coral'?1:0;note('Scene '+name);};
$('weather').onchange=()=>camera[15]=Number($('weather').value);
$('freeze').onclick=()=>{paused=!paused;$('freeze').textContent=paused?'Resume time':'Pause time';};
$('start').onclick=startGpu;
async function startGpu(){
 if(gpuStarted)return;gpuStarted=true;$('start').disabled=true;$('target').disabled=true;const begun=performance.now();note('GPU compilation started');
 try{
  if($('target').value==='full'){
   const {Engine}=await import('../../src/engine.js');engine=await new Engine().init($('gpu'),s=>{$('start').textContent=s;});
   engine.onError=e=>note('GPU error: '+e);
   if(threaded){
    const snap=previewState;await engine.resize(width,height);engine.frame(snap.camera,snap.origin);await engine.runtime.idle();
    const actual=await engine.readPixels();let sum=0,max=0,large=0;
    for(let i=0;i<actual.length;i++){const d=Math.abs(actual[i]-snap.pixels[i]);sum+=d;max=Math.max(max,d);if(d>10)large++;}
    metrics.parity={meanChannelError:sum/actual.length,maxChannelError:max,channelsOver10:large};
    $('parity').textContent=`Full pipeline parity: mean ${metrics.parity.meanChannelError.toFixed(3)}/255; max ${max}; channels >10: ${large}.`;
   }
   await engine.resize(640,360);
  }else{
   const {GpuRuntime}=await import('../../vendor/cuda-webshader/runtime/runtime.js');const {trimWgsl}=await import('../../src/wgsl-trim.js');
   const runtime=await GpuRuntime.create({onError:e=>note(String(e))});
   const artifact=await fetch('./generated/previewWorld.json').then(r=>r.json());
   const kernel=await runtime.kernel(trimWgsl(artifact).artifact),C=runtime.createBuffer(64),Origin=runtime.createBuffer(16),Pixels=runtime.createBuffer(256*144*4);
   const call=kernel.bind({C,Origin,Pixels},{width:256,height:144});
   $('gpu').width=256;$('gpu').height=144;const context=$('gpu').getContext('webgpu');context.configure({device:runtime.device,format:'rgba8unorm',usage:GPUTextureUsage.COPY_DST|GPUTextureUsage.RENDER_ATTACHMENT,alphaMode:'opaque'});
   gpuPreview={runtime,C,Origin,Pixels,call,context};
   // Compare the two compiler targets using exactly the last completed CPU state.
   const snap=previewState,check=runtime.createBuffer(width*height*4);
   runtime.write(C,snap.camera);runtime.write(Origin,snap.origin);
   runtime.batch().dispatch(kernel.bind({C,Origin,Pixels:check},{width,height}),[Math.ceil(width/8),Math.ceil(height/8)]).submit();
   const actual=new Uint8Array((await runtime.read(check,Uint32Array)).buffer);let sum=0,max=0,large=0;
   for(let i=0;i<actual.length;i++){const delta=Math.abs(actual[i]-snap.pixels[i]);sum+=delta;max=Math.max(max,delta);if(delta>10)large++;}
   metrics.parity={meanChannelError:sum/actual.length,maxChannelError:max,channelsOver10:large};
   $('parity').textContent=`Same .cu parity: mean ${metrics.parity.meanChannelError.toFixed(3)}/255; max ${max}; channels >10: ${large}.`;
   runtime.destroyBuffer(check);
  }
  metrics.gpuCompileMs=performance.now()-begun;note('GPU ready; preparing first frame');
  // Continue latest camera/time; never reset state to the first preview image.
  renderGPU();await (engine?.runtime||gpuPreview.runtime).idle();if(engine?.errors.length)throw Error(engine.errors.join('\n'));
  handed=true;metrics.handoverMs=performance.now()-start;worker.terminate();$('gpu').style.opacity=1;$('start').textContent='GPU active';note('Handover complete; WASM worker stopped');document.body.dataset.ready='true';
 }catch(e){engine=null;gpuPreview=null;gpuStarted=false;$('start').disabled=false;$('target').disabled=false;$('start').textContent='Retry GPU';note('GPU failed; retaining WASM: '+e.message);}
}
function renderGPU(){
 if(engine){engine.frame(camera,origin);return;}
 const {runtime,C,Origin,Pixels,call,context}=gpuPreview;runtime.write(C,camera);runtime.write(Origin,origin);const batch=runtime.batch().dispatch(call,[32,18]);batch.endPass();batch.encoder.copyBufferToTexture({buffer:Pixels.gpuBuffer,bytesPerRow:256*4,rowsPerImage:144},{texture:context.getCurrentTexture()},[256,144]);batch.submit();
}
function loop(now){
 const dt=Math.min(.1,(now-last)/1000);last=now;
 if(!document.hidden){moveCamera(camera,origin,input.keys,dt,speed);if(!paused)camera[5]+=dt;
  if(handed){if(query.has('record'))camera[3]+=dt*.012;renderGPU();}
  else if(ready&&!busy&&now-lastFrame>(threaded?33:125)){busy=true;lastFrame=now;sentState={camera:camera.slice(),origin:origin.slice()};worker.postMessage({type:'frame',...sentState,width,height,id:++sequence});}
 }
 $('stats').textContent=`Backend: ${handed?'WebGPU':threaded?'WASM full pipeline · '+threads+' threads':'WASM CPU preview'}\nStage: ${stage}\nFirst image: ${first===null?'…':first.toFixed(0)+' ms'}\nLast WASM frame: ${previewMs.toFixed(1)} ms · ${width}×${height}\nGPU compile: ${metrics.gpuCompileMs?.toFixed(0)??'…'} ms\nHandover: ${metrics.handoverMs?.toFixed(0)??'…'} ms\nSeed: ${origin[2]} · cell ${origin[0]},${origin[1]}\nCamera: ${Array.from(camera.slice(0,3),v=>v.toFixed(1)).join(', ')}\n${Object.entries(lastTimings).map(([k,v])=>k+': '+v.toFixed(1)+' ms').join('\n')}`;
 requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
