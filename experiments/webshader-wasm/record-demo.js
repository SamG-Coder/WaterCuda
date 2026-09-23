// Records the actual WASM/GPU canvases, with explanatory captions. No generated
// stand-in footage. The local experiment server receives the finished recording.
export function recordDemo(scene,state){
 const canvas=document.createElement('canvas');canvas.width=1280;canvas.height=720;
 const ctx=canvas.getContext('2d'),chunks=[],stream=canvas.captureStream(30);
 const mime=['video/webm;codecs=vp9','video/webm;codecs=vp8'].find(t=>MediaRecorder.isTypeSupported(t));
 if(!mime)throw Error('WebM recording is unavailable');
 const recorder=new MediaRecorder(stream,{mimeType:mime,videoBitsPerSecond:3500000}),start=performance.now();let handover=null,ended=false;
 const badge=document.createElement('div');Object.assign(badge.style,{position:'fixed',right:'16px',top:'16px',background:'#102c36',color:'white',padding:'12px',zIndex:9});badge.textContent='Recording real startup + handover';document.body.append(badge);
 recorder.ondataavailable=e=>{if(e.data.size)chunks.push(e.data);};
 recorder.onstop=async()=>{
  for(const t of stream.getTracks())t.stop();badge.textContent='Saving recorded video…';
  try{const blob=new Blob(chunks,{type:'video/webm'}),meta={...state(),recordingSeconds:(performance.now()-start)/1000,handoverSeconds:handover===null?null:(handover-start)/1000};delete meta.camera;
   const res=await fetch('/__demo-video',{method:'POST',headers:{'Content-Type':'video/webm','X-Demo-Metadata':JSON.stringify(meta)},body:blob});if(!res.ok)throw Error(await res.text());badge.textContent='Recording saved · '+(blob.size/1048576).toFixed(1)+' MiB';badge.dataset.saved='true';
  }catch(e){badge.textContent='Recording save failed: '+e.message;}
 };
 recorder.start(1000);
 function draw(now){
  const s=state(),seconds=(now-start)/1000;if(s.handed&&handover===null)handover=now;
  const after=handover===null?-1:(now-handover)/1000;
  ctx.fillStyle='#081d28';ctx.fillRect(0,0,1280,720);const source=scene();if(source.width&&source.height)ctx.drawImage(source,0,0,1280,720);
  const top=ctx.createLinearGradient(0,0,0,205);top.addColorStop(0,'#061723ed');top.addColorStop(1,'#06172300');ctx.fillStyle=top;ctx.fillRect(0,0,1280,205);
  ctx.fillStyle='#69e4c5';ctx.font='600 19px Segoe UI';ctx.fillText('WATERCUDA / CUDA WEBSHADER',42,43);
  ctx.fillStyle='white';ctx.font='600 36px Segoe UI';ctx.fillText(s.handed?'WebGPU takes over.':'Run the world while shaders compile.',42,91);
  ctx.font='18px Segoe UI';ctx.fillStyle='#d8e8ed';ctx.fillText(s.handed?'GPU · same seed, camera and world time':'WASM · full pipeline · 4 shared-memory CPU threads',44,128);
  ctx.fillStyle='#071d2ded';ctx.fillRect(0,559,1280,161);ctx.fillStyle='#fff';ctx.font='600 27px Segoe UI';
  let caption=seconds<8?'One set of .cu files. CPU threads or GPU shaders.':seconds<16?'Terrain, FFT waves, weather, foliage and reflections.':seconds<24?'The WASM backend shares memory across CPU threads.':'The world keeps running while WebGPU compiles.';
  let detail=seconds<8?'WebShader generates both targets from the CUDA source.':seconds<16?'All 17 production kernels run in WebAssembly.':seconds<24?'Workgroups run in parallel. FFT lanes synchronize at barriers.':'This is actual browser footage; the long wait is trimmed in the edit.';
  if(after>=0){caption=after<6?'The GPU is ready. No camera reset.':after<12?'Same world. Higher resolution.':'One source. WASM, WebGPU and native CUDA.';detail=after<6?'The completed GPU frame replaces WASM, then the CPU workers stop.':after<12?'128×72 CPU startup → 640×360 WebGPU in this experiment.':'github.com/SamG-Coder/WaterCuda  ·  github.com/SamG-Coder/cuda-webshader';}
  ctx.fillText(caption,42,609);ctx.font='19px Segoe UI';ctx.fillStyle='#bfdae2';ctx.fillText(detail,43,646);
  ctx.font='16px Consolas';ctx.fillStyle='#74dfc9';ctx.fillText(`Seed 884  |  elapsed ${seconds.toFixed(1)}s  |  ${s.handed?'WebGPU active':'WASM frame '+s.previewMs.toFixed(1)+' ms'}`,43,686);
  if(!ended&&(after>18||seconds>720)){ended=true;recorder.stop();return;}requestAnimationFrame(draw);
 }requestAnimationFrame(draw);
}
