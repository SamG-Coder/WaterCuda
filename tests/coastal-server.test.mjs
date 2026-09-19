import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {createCoastalServer} from '../tools/coastal-server.mjs';

test('browser validation serves a directory URL with its native trailing separator', async t=>{
 const server=createCoastalServer(fileURLToPath(new URL('../',import.meta.url)));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 t.after(()=>new Promise(resolve=>server.close(resolve)));
 const base=`http://127.0.0.1:${server.address().port}`;
 const index=await fetch(base+'/WaterCuda/');
 assert.equal(index.status,200);
 assert.match(await index.text(),/id="view"/);
 assert.equal(index.headers.get('content-type'),'text/html');
 const source=await fetch(base+'/WaterCuda/src/app.js');
 assert.equal(source.status,200);
 assert.equal(source.headers.get('content-type'),'text/javascript');
 assert.equal(source.headers.get('cache-control'),'no-store');
 assert.equal((await fetch(base+'/WaterCuda/missing-file')).status,404);
 assert.equal((await fetch(base+'/other-prefix/')).status,404);
});
