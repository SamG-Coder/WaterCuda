export const CELL=4800;
// Keep integer identity separate from the local floating-point render position.
export function rebase(camera,origin){
 for(const axis of [0,2]){
  const shift=Math.floor(camera[axis]/CELL);
  if(!shift)continue;
  const slot=axis===0?0:1,next=origin[slot]+shift;
  if(next < -2147480000 || next > 2147480000)throw Error('World coordinate limit reached.');
  camera[axis]-=shift*CELL;origin[slot]=next;
 }
}
export function parseSeed(value){const n=Number(value);if(!Number.isInteger(n)||n<0||n>2147483647)throw Error('Use a whole-number seed between 0 and 2147483647.');return n;}
export function renderSize(viewWidth,viewHeight,targetWidth){
 const width=Math.max(320,Math.ceil(Math.min(viewWidth,targetWidth)/64)*64);
 const height=Math.max(192,Math.round(width*Math.max(0.35,Math.min(2,viewHeight/viewWidth))/8)*8);
 return {width,height};
}
