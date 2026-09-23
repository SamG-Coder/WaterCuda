// Dedicated isolated origin; production server and deployment headers unchanged.
import http from 'node:http';import fs from 'node:fs';import path from 'node:path';import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../../',import.meta.url)),port=Number(process.argv[2]||8091);
const mime={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.json':'application/json','.wasm':'application/wasm','.css':'text/css','.cu':'text/plain'};
http.createServer((req,res)=>{
 if(req.method==='POST'&&req.url==='/__demo-video'){
  if(!['http://localhost:'+port,'http://127.0.0.1:'+port].includes(req.headers.origin)){res.writeHead(403);return res.end();}
  const output=path.join(root,'artifacts/video');fs.mkdirSync(output,{recursive:true});const sink=fs.createWriteStream(path.join(output,'wasm-handover-source.webm'));let bytes=0;
  req.on('data',chunk=>{bytes+=chunk.length;if(bytes>350*1048576){sink.destroy();req.destroy();}});req.pipe(sink);
  sink.on('finish',()=>{fs.writeFileSync(path.join(output,'wasm-handover-source.json'),req.headers['x-demo-metadata']||'{}');res.writeHead(200);res.end('saved');});sink.on('error',()=>{res.writeHead(500);res.end('save failed');});return;
 }
 if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);return res.end();}
 let p;try{p=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400);return res.end();}
 if(p==='/')p='/experiments/webshader-wasm/';
 const target=path.resolve(root,'.'+(p.endsWith('/')?p+'index.html':p));
 if(!target.startsWith(path.resolve(root)+path.sep)){res.writeHead(403);return res.end();}
 fs.stat(target,(e,s)=>{if(e||!s.isFile()){res.writeHead(404);return res.end();}res.writeHead(200,{'Content-Type':mime[path.extname(target)]||'application/octet-stream','Content-Length':s.size,'Cache-Control':'no-store','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp','Cross-Origin-Resource-Policy':'same-origin','X-Content-Type-Options':'nosniff'});if(req.method==='HEAD')res.end();else fs.createReadStream(target).pipe(res);});
}).listen(port,'127.0.0.1',()=>console.log('Shared-memory experiment: http://localhost:'+port+'/experiments/webshader-wasm/'));
