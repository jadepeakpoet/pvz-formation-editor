import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const dir=new URL('./dist/',import.meta.url);
const meta=JSON.parse(await readFile(new URL('release.json',dir)));
const source=await readFile(new URL('_worker.js',dir),'utf8');
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const env={ASSETS:{async fetch(request){
  const path=new URL(request.url).pathname.slice(1);
  try{return new Response(await readFile(new URL(path,dir)));}catch{return new Response(null,{status:404});}
}}};
const run=(headers={},method='GET')=>worker.fetch(new Request('https://example.com'+meta.path,{headers,method}),env);
const full=await run();const bytes=Buffer.from(await full.arrayBuffer());
assert.equal(createHash('sha256').update(bytes).digest('hex'),meta.sha256);
const resumeAt=Math.min(30000000,Math.floor(bytes.length*.7));
for(const [range,start,end] of [['bytes=0-50',0,50],['bytes=8388580-8388630',8388580,8388630],['bytes=-21',bytes.length-21,bytes.length-1],[`bytes=${resumeAt}-`,resumeAt,bytes.length-1]]){
 const response=await run({Range:range});assert.equal(response.status,206);
 const part=Buffer.from(await response.arrayBuffer());assert.deepEqual(part,bytes.subarray(start,end+1));
 assert.equal(Number(response.headers.get('Content-Length')),part.length);
}
assert.equal((await run({Range:'bytes=999999999-'})).status,416);
assert.equal((await run({Range:'bytes=-0'})).status,416);
const head=await run({},'HEAD');assert.equal((await head.arrayBuffer()).byteLength,0);
assert.equal(Number(head.headers.get('Content-Length')),bytes.length);
assert.equal((await run({},'POST')).status,405);
console.log('Download stream: full SHA256, cross-part ranges, suffix, invalid ranges and HEAD passed.');
