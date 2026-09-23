export class CpuResolution{
 constructor(){this.width=128;this.samples=0;this.ms=0;}
 observe(ms){
  if(!Number.isFinite(ms)||ms<=0)return;
  if(++this.samples<=3)return;
  this.ms=this.ms?this.ms*.85+ms*.15:ms;
  if(this.samples<30)return;
  let next=this.width;
  if(this.ms<35)next=Math.min(320,this.width+32);
  else if(this.ms>65)next=Math.max(96,this.width-32);
  if(next!==this.width){this.width=next;this.samples=0;this.ms=0;}
 }
 size(w,h){return {width:this.width,height:Math.max(32,Math.min(640,Math.round(this.width*h/Math.max(1,w))))};}
}
