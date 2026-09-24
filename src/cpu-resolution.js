export class CpuResolution{
 constructor(){this.width=128;this.samples=0;this.ms=0;this.limit=1920;}
 observe(ms){
  if(!Number.isFinite(ms)||ms<=0)return;
  if(++this.samples<=3)return;
  this.ms=this.ms?this.ms*.85+ms*.15:ms;
  if(this.samples<30)return;
  let next=this.width;
  if(this.ms<45)next=Math.min(this.limit,this.width+32);
  else if(this.ms>55)next=Math.max(96,this.width-32);
  if(next!==this.width){this.width=next;this.samples=0;this.ms=0;}
 }
 size(w,h){
  const aspect=Math.max(1,h)/Math.max(1,w);
  this.limit=Math.max(96,Math.floor(Math.min(Math.max(96,w),Math.sqrt(1920*1080/aspect))/32)*32);
  this.width=Math.min(this.width,this.limit);
  return {width:this.width,height:Math.max(1,Math.floor(this.width*aspect))};
 }
}
