import test from 'node:test';import assert from 'node:assert/strict';import {readFile} from 'node:fs/promises';import {createHash} from 'node:crypto';
test('vendored WebShader files match the pinned upstream source manifest',async()=>{
 const root=new URL('../vendor/cuda-webshader/',import.meta.url),manifest=JSON.parse(await readFile(new URL('UPSTREAM.json',root),'utf8'));
 assert.match(manifest.commit,/^[0-9a-f]{40}$/);assert.equal(manifest.repository,'https://github.com/SamG-Coder/cuda-webshader.git');
 for(const [name,expected]of Object.entries(manifest.files)){const source=(await readFile(new URL(name,root),'utf8')).replaceAll('\r\n','\n');assert.equal(createHash('sha256').update(source).digest('hex'),expected,name);}
});
