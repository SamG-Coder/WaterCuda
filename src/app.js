import {Engine} from './engine.js';
import {applySeaLook} from './sea-looks.js';
import {rebase,parseSeed,renderSize} from './world.js';
import {FlightInput,moveCamera,toggleHelm} from './flight.js';
import {WasmStartup} from './wasm-startup.js';
const $=id=>document.getElementById(id),canvas=$('view');
const camera=new Float32Array([340,160,100,-0.05,-0.10,0,1,-0.7,0.7,1,0,1,1.5,1,0,0,...new Array(24).fill(0)]);
const origin=new Int32Array([0,0,42,0]);
let engine,paused=false,drifting=false,speed=60,resizing=true,running=false,last=performance.now(),frames=0,lastStats=last,autoWidth=960,lastAdapt=0;
let toastTimer;
let startup,previewCanvas,gpuActive=false,startupFirst=false;
function toast(message){$('toast').textContent=message;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),3500);}
function preset(name){
 const views={ship:[682,16,612,-.70,-.035],coast:[1250,210,650,0.52,-0.10],aerial:[-300,1400,-300,0.70,-0.34],water:[1550,7,1100,0.52,0.025],shore:[1850,25,1250,0.15,-0.30],scrub:[2810.9,11.51,1131.74,0,-.20],bars:[3370,42,2770,-1.4,-.23],reef:[4377,-7,2784,0,-.12],coral:[4377,-7.3,2810.8,0,-.18],family:[4377,-6.5,2805,0,-.23]};
 const v=views[name];camera.set(v);camera[14]=name==='ship'?3:(name==='family'?2:(name==='coral'?1:0));if(name==='ship'){camera.set([650,0,650,0,0,0,0,100],16);camera[3]=-.6;camera[4]=-.18;camera[19]=camera[3];camera[32]=camera[19];camera[33]=camera[34]=0;speed=25;}else if(camera[14]>0)speed=2;origin[0]=0;origin[1]=0;rebase(camera,origin);input.clear();drifting=false;$('sail').innerHTML='Begin drift <span>→</span>';
 document.querySelectorAll('[data-view]').forEach(b=>b.classList.toggle('selected',b.dataset.view===name));
}
document.querySelectorAll('[data-view]').forEach(b=>b.onclick=()=>preset(b.dataset.view));
$('generate').onclick=()=>{try{origin[2]=parseSeed($('seed').value);preset('coast');toast('Archipelago generated · seed '+origin[2]);}catch(e){toast(e.message);}};
function syncLookControls(){
 $('wind').value=camera[6];$('windValue').value=camera[6].toFixed(1);$('sun').value=camera[8];$('sunValue').value=camera[8]<.35?'Golden hour':'Daylight';
 $('clarity').value=camera[12];$('clarityValue').value=camera[12].toFixed(2)+'×';$('azimuth').value=camera[7]*180/Math.PI;$('azimuthValue').value=Math.round(camera[7]*180/Math.PI)+'°';
}
function setLook(name){applySeaLook(camera,name);$('look').value=name;syncLookControls();}
function selectHour(hour){camera[8]=10+((hour-camera[5]/60)%24+24)%24;$('daycycle').checked=true;}
$('hour').oninput=e=>selectHour(Number(e.target.value));
$('daycycle').onchange=e=>{if(e.target.checked)selectHour(Number($('hour').value));else camera[8]=Number($('sun').value);};
$('weather').onchange=e=>{camera[15]=Number(e.target.value);};
$('look').onchange=e=>{$('daycycle').checked=false;setLook(e.target.value);toast('Sea and light updated');};
$('clarity').oninput=e=>{camera[12]=Number(e.target.value);$('clarityValue').value=camera[12].toFixed(2)+'×';};
$('azimuth').oninput=e=>{camera[7]=Number(e.target.value)*Math.PI/180;$('azimuthValue').value=e.target.value+'°';};
$('caustics').onchange=e=>camera[13]=Number(e.target.checked);
$('wind').oninput=e=>{camera[6]=Number(e.target.value);$('windValue').value=camera[6].toFixed(1);};
$('sun').oninput=e=>{$('daycycle').checked=false;camera[8]=Number(e.target.value);$('sunValue').value=camera[8]<.35?'Golden hour':'Daylight';};
$('reflections').onchange=e=>camera[9]=Number(e.target.checked);
$('debug').onchange=e=>camera[10]=Number(e.target.value);
$('quality').onchange=()=>resizing=true;window.addEventListener('resize',()=>resizing=true);
$('pause').onclick=()=>{paused=!paused;$('pause').textContent=paused?'Resume world':'Pause world';};
$('sail').onclick=()=>{drifting=!drifting;$('sail').innerHTML=drifting?'Stop drift <span>Ⅱ</span>':'Begin drift <span>→</span>';};
function toggleUI(){const clean=document.body.classList.toggle('clean');$('restore').hidden=!clean;}
$('hide').onclick=toggleUI;$('restore').onclick=toggleUI;
const input=new FlightInput(canvas,camera,{
 onShortcut:code=>{if(code==='KeyV'){toggleHelm(camera);toast(camera[14]===4?'Free flight � V to return to ship':'Ship controls');}if(code==='KeyB')preset('ship');if(code==='KeyH')toggleUI();if(code==='KeyF')input.capture();if(code==='Digit1')preset('coast');if(code==='Digit2')preset('aerial');if(code==='Digit3')preset('water');if(code==='Digit4')preset('shore');if(code==='Digit7')preset('reef');if(code==='Digit8')preset('coral');},
 onSpeed:delta=>{speed=Math.max(3,speed*Math.exp(-delta*.001));toast('Flight speed · '+Math.round(speed)+' m/s');},
 onLock:locked=>{$('fly').textContent=locked?'Flying · Esc to release':'Free camera · F';document.body.classList.toggle('exploring',locked);$('flightStatus').textContent=locked?'MOUSE LOOK · ESC TO RELEASE':'DRAG TO LOOK · F FOR MOUSE LOOK';}
});
$('fly').onclick=()=>{if(!input.capture())toast('Mouse capture unavailable here. Drag on the scene to look.');};
$('capture').onclick=async()=>{if(!gpuActive&&!startupFirst)return;try{const blob=gpuActive?await engine.capture():await startup.capture();const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='WaterCuda-'+origin[2]+'.png';a.click();setTimeout(()=>URL.revokeObjectURL(url),10000);toast('Image saved');}catch(e){toast(e.message);}};
$('validate').onclick=async()=>{if(!engine)return;$('validate').disabled=true;$('checks').textContent='Running actual GPU fixtures…';try{const result=await engine.validate();$('checks').textContent=result.checks.map(([name,ok])=>(ok?'PASS':'FAIL')+'  '+name).join('\n');document.body.dataset.gpuTests=result.checks.every(([,ok])=>ok)?'passed':'failed';window.gpuValidation=result;}catch(e){$('checks').textContent=e.stack;document.body.dataset.gpuTests='failed';}finally{$('validate').disabled=false;}};
function advance(dt){
 if(!(paused&&camera[14]===3))moveCamera(camera,origin,input.keys,dt,speed,drifting);if(input.keys.size||input.drag)document.body.classList.add('exploring');if(!paused)camera[5]+=dt;
}
function advanceTo(now){
 const dt=Math.min(.1,Math.max(0,(now-last)/1000));last=Math.max(last,now);advance(dt);
}
async function loop(now){
 if(!running)return;
 try{
  if(document.hidden){last=performance.now();requestAnimationFrame(loop);return;}
  advanceTo(performance.now());
  if(!gpuActive){
   startup?.frame(camera,origin);
   $('position').textContent='CELL '+origin[0].toLocaleString()+' / '+origin[1].toLocaleString();$('altitude').textContent='ALTITUDE '+Math.round(camera[1])+' M · SEED '+origin[2];
   if(camera[8]>=10){const hour=((camera[8]-10+camera[5]/60)%24+24)%24;$('hour').value=hour;$('hourValue').value=String(Math.floor(hour)).padStart(2,'0')+':'+String(Math.floor(hour%1*60)).padStart(2,'0');}
   $('flightStatus').dataset.position=[origin[0],origin[1],...Array.from(camera.slice(0,5))].join(',');
   requestAnimationFrame(loop);return;
  }
  if($('quality').value==='auto'&&now-lastAdapt>2000&&engine.gpuMs){lastAdapt=now;const ms=engine.gpuMs;let next=autoWidth;if(ms>18)next=Math.max(512,Math.floor(autoWidth*Math.max(.8,Math.sqrt(15/ms))/64)*64);else if(ms<11)next=Math.min(1280,autoWidth+64);if(next!==autoWidth){autoWidth=next;resizing=true;}}
  if(resizing){resizing=false;const target=$('quality').value==='auto'?autoWidth:Number($('quality').value),{width,height}=renderSize(innerWidth,innerHeight,target);await engine.resize(width,height);$('resolution').textContent=width+' × '+height+' / WEBGPU';}
  if(engine.frame(camera,origin))frames++;
  if(now-lastStats>1000){$('fps').textContent=Math.round(frames*1000/(now-lastStats))+' FPS';frames=0;lastStats=now;
   if(camera[8]>=10){const hour=((camera[8]-10+camera[5]/60)%24+24)%24;$('hour').value=hour;$('hourValue').value=String(Math.floor(hour)).padStart(2,'0')+':'+String(Math.floor(hour%1*60)).padStart(2,'0');}
   $('position').textContent='CELL '+origin[0].toLocaleString()+' / '+origin[1].toLocaleString();$('altitude').textContent='ALTITUDE '+Math.round(camera[1])+' M · SEED '+origin[2];
   $('timings').textContent=engine.timings?engine.timings.map(t=>t.name+': '+t.ms.toFixed(2)+' ms').join('\n')+'\nGPU total: '+engine.gpuMs.toFixed(2)+' ms':'GPU timestamps unavailable';
   $('flightStatus').dataset.position=[origin[0],origin[1],...Array.from(camera.slice(0,5))].join(',');}
  requestAnimationFrame(loop);
 }catch(e){running=false;$('loading').classList.remove('done');$('status').textContent=e.message;console.error(e);}
}
try{
 const url=new URL(location.href);if(url.searchParams.has('seed')){origin[2]=parseSeed(url.searchParams.get('seed'));$('seed').value=origin[2];}
 const weatherModes={auto:0,clear:1,overcast:2,rain:3,storm:4};camera[15]=weatherModes[url.searchParams.get('weather')]??0;$('weather').value=String(camera[15]);
 window.waterCuda={get engine(){return engine;},camera,origin,preset,setLook,setRenderLoop(on){if(on&&!running){running=true;last=performance.now();requestAnimationFrame(loop);}else if(!on)running=false;}};
 setLook(['coastal','golden','swell'].includes(url.searchParams.get('look'))?url.searchParams.get('look'):'coastal');
 if(url.searchParams.get('clock')!=='manual'){const hour=Number(url.searchParams.get('hour')??12);selectHour(Number.isFinite(hour)?hour:12);}else $('daycycle').checked=false;
 preset(['coast','aerial','water','shore','scrub','bars','reef','coral','family','ship'].includes(url.searchParams.get('view'))?url.searchParams.get('view'):'coast');
 if(crossOriginIsolated && typeof SharedArrayBuffer!=='undefined' && url.searchParams.get('startup')!=='gpu'){
  previewCanvas=document.createElement('canvas');previewCanvas.id='startup-preview';previewCanvas.setAttribute('aria-hidden','true');canvas.after(previewCanvas);
  startup=new WasmStartup(previewCanvas,{
   beforeFrame:()=>advanceTo(performance.now()),
   isActive:()=>running&&!gpuActive&&!document.hidden,
   onFrame:data=>{
    if(!startupFirst){$('quality').options[0].textContent='Auto · 20 FPS (CPU)';startupFirst=true;document.body.dataset.backend='wasm';document.body.dataset.previewReady='true';$('loading').classList.add('done');}
    $('timings').textContent=Object.entries(data.timings||{}).map(([name,ms])=>name+': '+ms.toFixed(2)+' ms').join('\n')+'\nCPU frame: '+data.ms.toFixed(2)+' ms';
    $('fps').textContent=Math.round(1000/(data.frameIntervalMs||data.ms))+' FPS';$('resolution').textContent=data.width+' × '+data.height+' / CPU'+(data.threads?' '+data.threads+' threads':'')+(data.checkerboard?' · checkerboard':'')+(data.nis?' · NIS 2×':'')+(url.searchParams.get('startup')==='cpu'?'':' · preparing GPU');
   },
   onError:message=>{console.warn('WASM startup:',message);toast('CPU preview unavailable · preparing GPU');}
  });
 }
 running=true;last=performance.now();requestAnimationFrame(loop);
 // Give the CPU a chance to show the scene first, without making GPU startup
 // depend on a successful WASM download or a responsive worker.
 if(startup)await Promise.race([startup.first,new Promise(resolve=>setTimeout(resolve,2500))]);
 if(url.searchParams.get('startup')==='cpu'){
  if(!startup)throw Error('CPU rendering requires cross-origin isolation');
  if(!await startup.first)throw Error('CPU renderer failed to initialize');
  document.body.dataset.ready='true';
 }else{
 engine=await new Engine().init(canvas,message=>{$('status').textContent=message;$('timings').textContent='Preparing GPU: '+message;});
 const size=renderSize(innerWidth,innerHeight,$('quality').value==='auto'?autoWidth:Number($('quality').value));
 await engine.resize(size.width,size.height);engine.frame(camera,origin);await engine.runtime.idle();
 if(engine.errors.length)throw Error(engine.errors.join('\n'));
 gpuActive=true;$('quality').options[0].textContent='Auto · 60 FPS';startup?.stop();previewCanvas?.remove();document.body.dataset.backend='webgpu';document.body.dataset.ready='true';$('loading').classList.add('done');
 engine.onError=e=>{running=false;$('loading').classList.remove('done');$('status').textContent=String(e.message||e);};
 if(url.searchParams.has('test')){document.querySelector('details').open=true;$('validate').click();}
 }
}catch(e){
 if(startupFirst){$('resolution').textContent='CPU renderer';toast('GPU unavailable · continuing on CPU');document.body.dataset.backend='wasm';}
 else $('status').textContent=e.message+' Open in a recent Chrome or Edge browser with WebGPU enabled.';
 console.error(e);
}
