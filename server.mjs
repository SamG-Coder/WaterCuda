import http from 'node:http';import fs from 'node:fs';import path from 'node:path';import {fileURLToPath} from 'node:url';import {spawn} from 'node:child_process';
const root=path.dirname(fileURLToPath(import.meta.url));const port=Number(process.argv.find(x=>/^\d+$/.test(x))??8090);
if(!Number.isInteger(port)||port<1||port>65535)throw Error('Port must be between 1 and 65535.');
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.cu':'text/plain; charset=utf-8','.wgsl':'text/plain; charset=utf-8','.png':'image/png','.webp':'image/webp','.md':'text/plain; charset=utf-8'};
const server=http.createServer((req,res)=>{
 if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405);res.end();return;}
 let pathname;try{pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400);res.end();return;}
 const target=path.resolve(root,'.'+(pathname.endsWith('/')?pathname+'index.html':pathname));
 if(target!==root&&!target.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
 fs.stat(target,(err,stat)=>{if(err||!stat.isFile()){res.writeHead(404);res.end('Not found');return;}
  res.writeHead(200,{'Content-Type':mime[path.extname(target)]??'application/octet-stream','Content-Length':stat.size,'Cache-Control':'no-cache','X-Content-Type-Options':'nosniff'});
  if(req.method==='HEAD')res.end();else{const stream=fs.createReadStream(target);stream.on('error',()=>res.destroy());stream.pipe(res);}
 });
});
server.on('error',e=>{console.error(e.code==='EADDRINUSE'?`Port ${port} is already in use. Try: node server.mjs ${port+1}`:e);process.exitCode=1;});
server.listen(port,'127.0.0.1',()=>{const url=`http://localhost:${port}`;console.log(`\nWaterCuda — Infinite islands.\n${url}\nKeep this terminal open. Ctrl+C stops the server.\n`);if(process.argv.includes('--open')){const command=process.platform==='win32'?'cmd':process.platform==='darwin'?'open':'xdg-open';const args=process.platform==='win32'?['/c','start','',url]:[url];const child=spawn(command,args,{detached:true,stdio:'ignore'});child.on('error',()=>{});child.unref();}});

