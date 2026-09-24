import {rebase} from './world.js';
export const isEditing=element=>!!element&&(element.isContentEditable||/^(INPUT|SELECT|TEXTAREA)$/.test(element.tagName));
export function flightVector(yaw,pitch,forward,side,vertical){
 const cp=Math.cos(pitch),v=[Math.sin(yaw)*cp*forward+Math.cos(yaw)*side,Math.sin(pitch)*forward+vertical,Math.cos(yaw)*cp*forward-Math.sin(yaw)*side];
 const length=Math.hypot(...v);return length>1?v.map(n=>n/length):v;
}
export function moveCamera(camera,origin,keys,dt,speed,drifting=false){
 const forward=Number(keys.has('KeyW')||keys.has('ArrowUp'))-Number(keys.has('KeyS')||keys.has('ArrowDown'));
 const side=Number(keys.has('KeyD')||keys.has('ArrowRight'))-Number(keys.has('KeyA')||keys.has('ArrowLeft'));
 const vertical=Number(keys.has('KeyE')||keys.has('Space'))-Number(keys.has('KeyQ'));
 if(camera[14]===3){
  camera[29]=camera[16];camera[30]=camera[17];camera[31]=camera[18];camera[26]=dt;
  const immersed=Math.max(0,Math.min(1,-camera[17]/8));
  const targetSpeed=forward*speed/(1+immersed*(2+speed*.035))*(keys.has('ShiftLeft')||keys.has('ShiftRight')?3:1)*(keys.has('KeyZ')?.2:1);
  const response=1-Math.exp(-dt*(forward?1.8:1.15));camera[24]+=(targetSpeed-camera[24])*response;
  camera[32]+=side*dt*.65;
  const turn=Math.atan2(Math.sin(camera[32]-camera[19]),Math.cos(camera[32]-camera[19]));
  camera[19]+=Math.max(-dt*.8,Math.min(dt*.8,turn*(1-Math.exp(-dt*4))));
  const surfaceAssist=camera[34]<.5&&Math.abs(camera[17])<3;
  if(surfaceAssist)camera[33]=0;
  const pitchTarget=Math.abs(camera[33])<.035?0:Math.max(-1,Math.min(1,camera[33]));camera[25]+=(pitchTarget-camera[25])*(1-Math.exp(-dt*3));
  if(camera[34]>.5){const yawDelta=Math.atan2(Math.sin(camera[19]-camera[3]),Math.cos(camera[19]-camera[3]));camera[3]+=yawDelta*(1-Math.exp(-dt*3));camera[4]+=(camera[25]-.18-camera[4])*(1-Math.exp(-dt*3));}
  const velocity=camera[24];
  const step=velocity*dt;camera[16]+=Math.sin(camera[19])*Math.cos(camera[25])*step;camera[18]+=Math.cos(camera[19])*Math.cos(camera[25])*step;
  camera[17]=Math.max(-110,Math.min(12000,surfaceAssist?camera[17]*Math.exp(-dt*3):camera[17]+Math.sin(camera[25])*step));
  const distance=camera[23],pitch=camera[4];camera[0]=camera[16]-Math.sin(camera[3])*Math.cos(pitch)*distance;camera[1]=camera[17]+10-Math.sin(pitch)*distance;camera[2]=camera[18]-Math.cos(camera[3])*Math.cos(pitch)*distance;rebase(camera,origin);return;
 }
 const v=flightVector(camera[3],camera[4],forward,side,vertical);
 const boost=keys.has('ShiftLeft')||keys.has('ShiftRight'),slow=keys.has('KeyZ');
 const step=speed*dt*(boost?5:1)*(slow?.2:1);for(let i=0;i<3;i++)camera[i]+=v[i]*step;
 if(drifting&&!forward&&!side&&!vertical){camera[0]+=Math.sin(camera[3])*speed*dt*.3;camera[2]+=Math.cos(camera[3])*speed*dt*.3;}
 camera[1]=Math.max(-110,Math.min(12000,camera[1]));rebase(camera,origin);
}
export class FlightInput{
 constructor(canvas,camera,{onShortcut=()=>{},onSpeed=()=>{},onLock=()=>{}}={}){
  this.canvas=canvas;this.camera=camera;this.keys=new Set();this.drag=null;canvas.tabIndex=0;
  const clear=()=>{this.keys.clear();this.drag=null;camera[34]=0;};
  window.addEventListener('blur',clear);document.addEventListener('visibilitychange',()=>{if(document.hidden)clear();});
  document.addEventListener('focusin',e=>{if(isEditing(e.target))clear();});
  window.addEventListener('keydown',e=>{if(isEditing(e.target)||e.metaKey||e.altKey||e.ctrlKey)return;
   if(['KeyW','KeyA','KeyS','KeyD','KeyQ','KeyE','KeyZ','Space','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','ShiftLeft','ShiftRight'].includes(e.code)){this.keys.add(e.code);e.preventDefault();}
   if(!e.repeat)onShortcut(e.code);
  });
  window.addEventListener('keyup',e=>this.keys.delete(e.code));
  document.addEventListener('pointerlockchange',()=>{clear();onLock(document.pointerLockElement===canvas);});
  document.addEventListener('pointerlockerror',()=>onLock(false));
  canvas.addEventListener('pointerdown',e=>{canvas.focus({preventScroll:true});if(document.pointerLockElement===canvas)return;this.drag={x:e.clientX,y:e.clientY,button:e.button};camera[34]=e.button===2?1:0;canvas.setPointerCapture(e.pointerId);});
  canvas.addEventListener('pointerup',()=>{this.drag=null;camera[34]=0;});canvas.addEventListener('pointercancel',clear);canvas.addEventListener('lostpointercapture',()=>{this.drag=null;camera[34]=0;});
  document.addEventListener('mousemove',e=>{
   let dx=0,dy=0;if(document.pointerLockElement===canvas){dx=e.movementX;dy=e.movementY;}
   else if(this.drag){dx=e.clientX-this.drag.x;dy=e.clientY-this.drag.y;this.drag={x:e.clientX,y:e.clientY,button:this.drag.button};}else return;
   if(camera[14]===3&&(document.pointerLockElement===canvas||this.drag?.button===2)){camera[34]=1;camera[32]+=dx*.0022;camera[33]=Math.max(-1,Math.min(1,camera[33]-dy*.0022));return;}
   camera[3]=(camera[3]+dx*.0022)%(Math.PI*2);camera[4]=Math.max(-1.54,Math.min(1.54,camera[4]-dy*.0022));
  });
  canvas.addEventListener('dblclick',()=>this.capture());canvas.addEventListener('contextmenu',e=>e.preventDefault());
  canvas.addEventListener('wheel',e=>{e.preventDefault();onSpeed(e.deltaY);},{passive:false});
 }
 capture(){this.canvas.focus({preventScroll:true});if(!this.canvas.requestPointerLock)return false;try{const request=this.canvas.requestPointerLock();request?.catch(()=>{});return true;}catch{return false;}}
 clear(){this.keys.clear();this.drag=null;this.camera[34]=0;}
}

// V detaches at the current chase view; the ship remains where it was left.
export function toggleHelm(camera){
 if(camera[14]===3){camera[14]=4;camera[24]=0;}
 else if(camera[14]===4){camera[14]=3;camera[3]=camera[19];camera[4]=camera[25]-.18;camera[32]=camera[19];camera[33]=camera[25];}
}

export function correctShip(camera,requested,pose){
 if(camera[14]!==requested[14]||camera[14]<3)return;
 for(const i of [16,17,18])camera[i]+=pose[i]-requested[i];
 if(pose[24]===0&&requested[24]!==0)camera[24]=0;
}
