import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';

export function createCoastalServer(directory){
 const root=path.resolve(directory);
const prefix='/WaterCuda',mime={'.js':'text/javascript','.json':'application/json','.html':'text/html','.css':'text/css','.cu':'text/plain'};
const server=http.createServer(async(req,res)=>{try{
 const u=new URL(req.url,'http://localhost');if(!u.pathname.startsWith(prefix+'/')){res.writeHead(404).end();return;}
 let p=decodeURIComponent(u.pathname.slice(prefix.length));if(p.endsWith('/'))p+='index.html';
 const file=path.resolve(root,'.'+p);if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 res.setHeader('Content-Type',mime[path.extname(file)]||'application/octet-stream');res.setHeader('Cache-Control','no-store');res.end(await fs.readFile(file));
}catch{res.writeHead(404).end();}});
 return server;
}
