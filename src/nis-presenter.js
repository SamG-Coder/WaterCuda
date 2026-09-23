import fragment from './nis-fragment.js';
// A separate WebGL2 presentation pass, independent of world compilation.
export class NisPresenter{
 async init(source){
  this.canvas=document.createElement('canvas');this.canvas.id='nis-preview';this.canvas.setAttribute('aria-hidden','true');
  const gl=this.gl=this.canvas.getContext('webgl2',{alpha:false,antialias:false,depth:false,stencil:false});
  if(!gl)throw Error('WebGL2 unavailable');
  this.canvas.addEventListener('webglcontextlost',()=>{this.lost=true;this.canvas.remove();});
  const compile=(type,code)=>{const s=gl.createShader(type);gl.shaderSource(s,code);gl.compileShader(s);return s;};
  const vertex=compile(gl.VERTEX_SHADER,'#version 300 es\nvoid main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);gl_Position=vec4(p*2.0-1.0,0,1);}');
  const pixel=compile(gl.FRAGMENT_SHADER,fragment);const program=this.program=gl.createProgram();
  gl.attachShader(program,vertex);gl.attachShader(program,pixel);gl.linkProgram(program);
  const parallel=gl.getExtension('KHR_parallel_shader_compile');
  if(parallel)while(!gl.getProgramParameter(program,parallel.COMPLETION_STATUS_KHR)){
   if(this.stopped)return;await new Promise(resolve=>setTimeout(resolve,16));
  }
  if(this.stopped)return;
  if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getShaderInfoLog(pixel)||gl.getProgramInfoLog(program));
  gl.deleteShader(vertex);gl.deleteShader(pixel);gl.useProgram(program);
  this.texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,this.texture);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
  this.output=gl.getUniformLocation(program,'outputSize');this.ready=true;this.source=source;
 }
 draw(data){
  if(!this.ready||this.stopped||this.lost)return false;
  this.last=data;
  const gl=this.gl,{width,height}=data;
  if(this.canvas.width!==width*2||this.canvas.height!==height*2){this.canvas.width=width*2;this.canvas.height=height*2;}
  gl.bindTexture(gl.TEXTURE_2D,this.texture);
  if(this.width!==width||this.height!==height){gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA8,width,height,0,gl.RGBA,gl.UNSIGNED_BYTE,null);this.width=width;this.height=height;}
  gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,width,height,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array(data.pixels));
  gl.viewport(0,0,width*2,height*2);gl.useProgram(this.program);gl.uniform2f(this.output,width*2,height*2);gl.drawArrays(gl.TRIANGLES,0,3);
  if(!this.canvas.isConnected)this.source.after(this.canvas);return true;
 }
 capture(){this.draw(this.last);return new Promise(resolve=>this.canvas.toBlob(resolve));}
 dispose(){this.stopped=true;this.canvas?.remove();if(this.gl){this.gl.deleteTexture(this.texture);this.gl.deleteProgram(this.program);this.gl.getExtension('WEBGL_lose_context')?.loseContext();}}
}
