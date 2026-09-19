import {Engine} from './engine.js';
import {applySeaLook} from './sea-looks.js';
import {rebase,parseSeed,renderSize} from './world.js';
import {FlightInput,moveCamera} from './flight.js';
const $=id=>document.getElementById(id),canvas=$('view');
const camera=new Float32Array([340,160,100,-0.05,-0.10,0,1,-0.7,0.7,1,0,1,1.5,1,0,0]);
const origin=new Int32Array([0,0,42,0]);
let engine,paused=false,drifting=false,speed=60,resizing=true,running=false,last=performance.now(),frames=0,lastStats=last,autoWidth=960,lastAdapt=0;
let toastTimer;
function toast(message){$('toast').textContent=message;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),3500);}
function preset(name){
 const views={coast:[1250,210,650,0.52,-0.10],aerial:[-300,1400,-300,0.70,-0.34],water:[1550,7,1100,0.52,0.025],shore:[1850,25,1250,0.15,-0.30]};
 const v=views[name];camera.set(v);origin[0]=0;origin[1]=0;rebase(camera,origin);input.clear();drifting=false;$('sail').innerHTML='Begin drift <span>→</span>';
 document.querySelectorAll('[data-view]').forEach(b=>b.classList.toggle('selected',b.dataset.view===name));
}
document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>preset(b.dataset.view));
$('generate').onclick=()=>{try{origin[2]=parseSeed($('seed').value);preset('coast');toast('Archipelago generated · seed '+origin[2]);}catch(e){toast(e.message);}};
function syncLookControls(){
 $('wind').value=camera[6];$('windValue').value=camera[6].toFixed(1);$('sun').value=camera[8];$('sunValue').value=camera[8]<.35?'Golden hour':'Daylight';
 $('clarity').value=camera[12];$('clarityValue').value=camera[12].toFixed(2)+'×';$('azimuth').value=camera[7]*180/Math.PI;$('azimuthValue').value=Math.round(camera[7]*180/Math.PI)+'°';
}
function setLook(name){applySeaLook(camera,name);$('look').value=name;syncLookControls();}
$('look').onchange=e=>{setLook(e.target.value);toast('Sea and light updated · compiled pipelines reused');};
$('clarity').oninput=e=>{camera[12]=Number(e.target.value);$('clarityValue').value=camera[12].toFixed(2)+'×';};
$('azimuth').oninput=e=>{camera[7]=Number(e.target.value)*Math.PI/180;$('azimuthValue').value=e.target.value+'°';};
$('caustics').onchange=e=>camera[13]=Number(e.target.checked);
$('wind').oninput=e=>{camera[6]=Number(e.target.value);$('windValue').value=camera[6].toFixed(1);};
$('sun').oninput=e=>{camera[8]=Number(e.target.value);$('sunValue').value=camera[8]<.35?'Golden hour':'Daylight';};
$('reflections').onchange=e=>camera[9]=Number(e.target.checked);
$('debug').onchange=e=>camera[10]=Number(e.target.value);
$('quality').onchange=()=>resizing=true;window.addEventListener('resize',()=>resizing=true);
$('pause').onclick=()=>{paused=!paused;$('pause').textContent=paused?'Resume ocean':'Pause ocean';};
$('sail').onclick=()=>{drifting=!drifting;$('sail').innerHTML=drifting?'Stop drift <span>Ⅱ</span>':'Begin drift <span>→</span>';};
function toggleUI(){const clean=document.body.classList.toggle('clean');$('restore').hidden=!clean;}
$('hide').onclick=toggleUI;$('restore').onclick=toggleUI;
const input=new FlightInput(canvas,camera,{
 onShortcut:code=>{if(code==='KeyH')toggleUI();if(code==='KeyF')input.capture();if(code==='Digit1')preset('coast');if(code==='Digit2')preset('aerial');if(code==='Digit3')preset('water');if(code==='Digit4')preset('shore');},
 onSpeed:delta=>{speed=Math.max(3,Math.min(1000,speed*Math.exp(-delta*.001)));toast('Flight speed · '+Math.round(speed)+' m/s');},
 onLock:locked=>{$('fly').textContent=locked?'Flying · Esc to release':'Free camera · F';document.body.classList.toggle('exploring',locked);$('flightStatus').textContent=locked?'MOUSE LOOK · ESC TO RELEASE':'DRAG TO LOOK · F FOR MOUSE LOOK';}
});
$('fly').onclick=()=>{if(!input.capture())toast('Mouse capture unavailable here. Drag on the scene to look.');};
$('capture').onclick=async()=>{if(!engine)return;try{const blob=await engine.capture();const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='WaterCuda-'+origin[2]+'.png';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);toast('Image saved');}catch(e){toast(e.message);}};
$('validate').onclick=async()=>{if(!engine)return;$('validate').disabled=true;$('checks').textContent='Running actual GPU fixtures…';try{const result=await engine.validate();$('checks').textContent=result.checks.map(([name,ok])=>(ok?'PASS':'FAIL')+'  '+name).join('\n');document.body.dataset.gpuTests=result.checks.every(([,ok])=>ok)?'passed':'failed';window.gpuValidation=result;}catch(e){$('checks').textContent=e.stack;document.body.dataset.gpuTests='failed';}finally{$('validate').disabled=false;}};
function advance(dt){
 moveCamera(camera,origin,input.keys,dt,speed,drifting);if(input.keys.size||input.drag)document.body.classList.add('exploring');if(!paused)camera[5]+=dt;
}
async function loop(now){
 if(!running)return;
 try{
  const dt=Math.min(.1,(now-last)/1000);last=now;
  if(document.hidden){requestAnimationFrame(loop);return;}
  advance(dt);
  if($('quality').value==='auto'&&now-lastAdapt>2000&&engine.gpuMs){lastAdapt=now;const ms=engine.gpuMs;let next=autoWidth;if(ms>18)next=Math.max(512,Math.floor(autoWidth*Math.max(.8,Math.sqrt(15/ms))/64)*64);else if(ms<11)next=Math.min(1280,autoWidth+64);if(next!==autoWidth){autoWidth=next;resizing=true;}}
  if(resizing){resizing=false;const target=$('quality').value==='auto'?autoWidth:Number($('quality').value),{width,height}=renderSize(innerWidth,innerHeight,target);await engine.resize(width,height);$('resolution').textContent=width+' × '+height+' / WEBGPU';}
  if(engine.frame(camera,origin))frames++;
  if(now-lastStats>1000){$('fps').textContent=Math.round(frames*1000/(now-lastStats))+' FPS';frames=0;lastStats=now;
   $('position').textContent='CELL '+origin[0].toLocaleString()+' / '+origin[1].toLocaleString();$('altitude').textContent='ALTITUDE '+Math.round(camera[1])+' M · SEED '+origin[2];
   $('timings').textContent=engine.timings?engine.timings.map(t=>t.name+': '+t.ms.toFixed(2)+' ms').join('\n')+'\nGPU total: '+engine.gpuMs.toFixed(2)+' ms':'GPU timestamps unavailable';
   $('flightStatus').dataset.position=[origin[0],origin[1],...Array.from(camera.slice(0,5))].join(',');}
  requestAnimationFrame(loop);
 }catch(e){running=false;$('loading').classList.remove('done');$('status').textContent=e.message;console.error(e);}
}
try{
 const url=new URL(location.href);if(url.searchParams.has('seed')){origin[2]=parseSeed(url.searchParams.get('seed'));$('seed').value=origin[2];}
 engine=await new Engine().init(canvas,message=>$('status').textContent=message);engine.onError=e=>{running=false;$('loading').classList.remove('done');$('status').textContent=String(e.message||e);};
 window.waterCuda={engine,camera,origin,preset,setLook,setRenderLoop(on){if(on&&!running){running=true;last=performance.now();requestAnimationFrame(loop);}else if(!on)running=false;}};setLook(['coastal','golden','swell'].includes(url.searchParams.get('look'))?url.searchParams.get('look'):'coastal');preset(['coast','aerial','water','shore'].includes(url.searchParams.get('view'))?url.searchParams.get('view'):'coast');running=true;last=performance.now();await loop(last);await engine.runtime.idle();if(!running)throw Error('Renderer failed to produce its first frame.');$('loading').classList.add('done');document.body.dataset.ready='true';
 if(url.searchParams.has('test')){document.querySelector('details').open=true;$('validate').click();}
}catch(e){$('status').textContent=e.message+' Open in a recent Chrome or Edge browser with WebGPU enabled.';console.error(e);}
