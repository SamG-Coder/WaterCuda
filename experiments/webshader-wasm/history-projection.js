// Match the renderer's ray convention without changing CUDA source.
const basis=c=>{
 const sy=Math.sin(c[3]),cy=Math.cos(c[3]),sp=Math.sin(c[4]),cp=Math.cos(c[4]);
 return [sy*cp,sp,cy*cp,cy,0,-sy,-sy*sp,cp,-cy*sp];
};
export function projectHistory(previous,current,depth,material,valid,width,height,indices,distances){
 indices.fill(-1);distances.fill(Infinity);
 const p=basis(previous),c=basis(current),ox=previous[0]-current[0],oy=previous[1]-current[1],oz=previous[2]-current[2];
 for(let y=0;y<height;y++)for(let x=0;x<width;x++){
  const i=y*width+x,m=material[i];if(!valid[i]||!(m===1||(m>=4&&m<=8))||!(depth[i]>0))continue;
  const sx=(x+.5-width*.5)/height*1.05,sy=-(y+.5-height*.5)/height*1.05;
  const scale=depth[i]/Math.sqrt(1+sx*sx+sy*sy);
  const px=ox+(p[0]+p[3]*sx+p[6]*sy)*scale,py=oy+(p[1]+p[4]*sx+p[7]*sy)*scale,pz=oz+(p[2]+p[5]*sx+p[8]*sy)*scale;
  const z=px*c[0]+py*c[1]+pz*c[2];if(z<=0)continue;
  const xx=Math.round((px*c[3]+py*c[4]+pz*c[5])/z*height/1.05+width*.5-.5),yy=Math.round(-(px*c[6]+py*c[7]+pz*c[8])/z*height/1.05+height*.5-.5);
  if(xx<0||xx>=width||yy<0||yy>=height)continue;
  const j=yy*width+xx,d=Math.sqrt(px*px+py*py+pz*pz);if(d<distances[j]){distances[j]=d;indices[j]=i;}
 }
}
