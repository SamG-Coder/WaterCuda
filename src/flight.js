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
 const v=flightVector(camera[3],camera[4],forward,side,vertical);
 const boost=keys.has('ShiftLeft')||keys.has('ShiftRight'),slow=keys.has('KeyZ');
 const step=speed*dt*(boost?5:1)*(slow?.2:1);for(let i=0;i<3;i++)camera[i]+=v[i]*step;
 if(drifting&&!forward&&!side&&!vertical){camera[0]+=Math.sin(camera[3])*speed*dt*.3;camera[2]+=Math.cos(camera[3])*speed*dt*.3;}
 camera[1]=Math.max(2.6*camera[6]+.5,Math.min(12000,camera[1]));rebase(camera,origin);
}
export class FlightInput{
 constructor(canvas,camera,{onShortcut=()=>{},onSpeed=()=>{},onLock=()=>{}}={}){
  this.canvas=canvas;this.camera=camera;this.keys=new Set();this.drag=null;canvas.tabIndex=0;
  const clear=()=>{this.keys.clear();this.drag=null;};
  window.addEventListener('blur',clear);document.addEventListener('visibilitychange',()=>{if(document.hidden)clear();});
  document.addEventListener('focusin',e=>{if(isEditing(e.target))clear();});
  window.addEventListener('keydown',e=>{if(isEditing(e.target)||e.metaKey||e.altKey||e.ctrlKey)return;
   if(['KeyW','KeyA','KeyS','KeyD','KeyQ','KeyE','KeyZ','Space','ArrowUp','ArrowDown','ArrowLeft','ArrowRight','ShiftLeft','ShiftRight'].includes(e.code)){this.keys.add(e.code);e.preventDefault();}
   if(!e.repeat)onShortcut(e.code);
  });
  window.addEventListener('keyup',e=>this.keys.delete(e.code));
  document.addEventListener('pointerlockchange',()=>{clear();onLock(document.pointerLockElement===canvas);});
  document.addEventListener('pointerlockerror',()=>onLock(false));
  canvas.addEventListener('pointerdown',e=>{canvas.focus({preventScroll:true});if(document.pointerLockElement===canvas)return;this.drag={x:e.clientX,y:e.clientY};canvas.setPointerCapture(e.pointerId);});
  canvas.addEventListener('pointerup',()=>this.drag=null);canvas.addEventListener('pointercancel',clear);canvas.addEventListener('lostpointercapture',()=>this.drag=null);
  document.addEventListener('mousemove',e=>{
   let dx=0,dy=0;if(document.pointerLockElement===canvas){dx=e.movementX;dy=e.movementY;}
   else if(this.drag){dx=e.clientX-this.drag.x;dy=e.clientY-this.drag.y;this.drag={x:e.clientX,y:e.clientY};}else return;
   camera[3]=(camera[3]+dx*.0022)%(Math.PI*2);camera[4]=Math.max(-1.54,Math.min(1.54,camera[4]-dy*.0022));
  });
  canvas.addEventListener('dblclick',()=>this.capture());canvas.addEventListener('contextmenu',e=>e.preventDefault());
  canvas.addEventListener('wheel',e=>{e.preventDefault();onSpeed(e.deltaY);},{passive:false});
 }
 capture(){this.canvas.focus({preventScroll:true});if(!this.canvas.requestPointerLock)return false;try{const request=this.canvas.requestPointerLock();request?.catch(()=>{});return true;}catch{return false;}}
 clear(){this.keys.clear();this.drag=null;}
}
