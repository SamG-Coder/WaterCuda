// Small geometry-guided temporal resolve inspired by denoising techniques.
// This is not NVIDIA NRD. Raw checkerboard samples remain untouched.
const AX=[-1,1,0,0],AY=[0,0,-1,1],DX=[-1,1,-1,1],DY=[-1,-1,1,1];
export class CheckerboardResolve {
 resolve(pixels,hit,surface,width,height,phase,{reset=false,moved=false}={}){
  const length=width*height*4;
  if(this.width!==width||this.height!==height){this.width=width;this.height=height;this.history=new Uint8Array(length);this.output=new Uint8Array(length);reset=true;}
  const out=this.output,history=this.history;
  if(reset){out.set(pixels);}else{
   for(let y=0;y<height;y++)for(let x=0;x<width;x++){
    const b=(y*width+x)*4,fresh=((x+y)&1)===phase;
    // Four current-phase taps: axial for holes, diagonal for fresh samples.
    const dx=fresh?DX:AX,dy=fresh?DY:AY;
    let guide=b;
    if(!fresh&&moved){for(let j=0;j<4;j++){const xx=x+dx[j],yy=y+dy[j];if(xx>=0&&xx<width&&yy>=0&&yy<height){guide=(yy*width+xx)*4;break;}}}
    const material=hit[guide+1],depth=hit[guide],dynamic=material===2;
    let r=0,g=0,bl=0,total=0,loR=255,loG=255,loB=255,hiR=0,hiG=0,hiB=0;
    for(let j=0;j<4;j++){
     const xx=x+dx[j],yy=y+dy[j];if(xx<0||xx>=width||yy<0||yy>=height)continue;
     const a=(yy*width+xx)*4;if(hit[a+1]!==material)continue;
     const depthDelta=Math.abs(hit[a]-depth)/Math.max(1,Math.abs(depth)*.03);
     const dot=surface[a]*surface[guide]+surface[a+1]*surface[guide+1]+surface[a+2]*surface[guide+2];
     const normal=material===0?1:Math.max(0,Math.min(1,dot));
     const weight=1/(1+depthDelta*depthDelta)*(.05+.95*normal*normal*normal*normal);
     r+=pixels[a]*weight;g+=pixels[a+1]*weight;bl+=pixels[a+2]*weight;total+=weight;
     loR=Math.min(loR,pixels[a]);loG=Math.min(loG,pixels[a+1]);loB=Math.min(loB,pixels[a+2]);hiR=Math.max(hiR,pixels[a]);hiG=Math.max(hiG,pixels[a+1]);hiB=Math.max(hiB,pixels[a+2]);
    }
    if(total<.001){out[b]=pixels[guide];out[b+1]=pixels[guide+1];out[b+2]=pixels[guide+2];out[b+3]=255;continue;}
    r/=total;g/=total;bl/=total;
    // Preserve fresh detail. Water holes primarily use this frame, even when
    // the camera is still; waves/reflections do not share terrain motion.
    if(fresh){const mix=dynamic?.12:.025;r=pixels[b]*(1-mix)+r*mix;g=pixels[b+1]*(1-mix)+g*mix;bl=pixels[b+2]*(1-mix)+bl*mix;}
    const disagreement=Math.max(Math.abs(history[b]-r),Math.abs(history[b+1]-g),Math.abs(history[b+2]-bl));
    const trust=moved?0:(fresh?.12:(dynamic?.08:.65))*Math.max(0,1-disagreement/40);
    out[b]=Math.round(r*(1-trust)+Math.max(loR,Math.min(hiR,history[b]))*trust);
    out[b+1]=Math.round(g*(1-trust)+Math.max(loG,Math.min(hiG,history[b+1]))*trust);
    out[b+2]=Math.round(bl*(1-trust)+Math.max(loB,Math.min(hiB,history[b+2]))*trust);out[b+3]=255;
   }
  }
  this.output=history;this.history=out;return out;
 }
}
