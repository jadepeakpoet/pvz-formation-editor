import {readFile} from 'node:fs/promises';
import {DatabaseSync} from 'node:sqlite';
import {randomUUID, pbkdf2Sync} from 'node:crypto';
import assert from 'node:assert/strict';
import vm from 'node:vm';
const source=await readFile(new URL('./analytics-worker.js',import.meta.url),'utf8');
const {fetch:run}=await import('data:text/javascript;base64,'+Buffer.from(source+'\nexport const fetch=analyticsFetch;').toString('base64'));
const db=new DatabaseSync(':memory:');db.exec(await readFile(new URL('./migrations/0001_analytics.sql',import.meta.url),'utf8'));
class Statement {
  constructor(sql,args=[]){this.sql=sql;this.args=args;}
  bind(...args){return new Statement(this.sql,args);}
  async first(){return db.prepare(this.sql).get(...this.args)||null;}
  async all(){return {results:db.prepare(this.sql).all(...this.args)};}
  async run(){return db.prepare(this.sql).run(...this.args);}
}
const password='test-only-generated-password', salt='test-salt';
const env={DB:{prepare:sql=>new Statement(sql),batch:async statements=>{db.exec('BEGIN');try{const out=[];for(const s of statements)out.push(await s.run());db.exec('COMMIT');return out;}catch(e){db.exec('ROLLBACK');throw e;}}},SESSION_SECRET:'test-only-session-secret-with-32-characters',ADMIN_PASSWORD_HASH:'pbkdf2-sha256$'+salt+'$'+pbkdf2Sync(password,salt,100000,32,'sha256').toString('hex')};
const base='https://xmpvz.pages.dev';
async function call(path,{method='GET',body,cookie,origin=base,ip='test-ip'}={}) {
  const headers={'User-Agent':'Mozilla/5.0','CF-Connecting-IP':ip};if(origin)headers.Origin=origin;if(body!==undefined)headers['Content-Type']='application/json';if(cookie)headers.Cookie=cookie;
  const request=new Request(base+path,{method,headers,body:body!==undefined?JSON.stringify(body):undefined});Object.defineProperty(request,'cf',{value:{country:'CN'}});return run(request,env);
}
assert.equal((await call('/api/admin/report')).status,401);
assert.equal((await call('/api/admin/login',{method:'POST',body:{password},origin:'https://other.example'})).status,403);
assert.equal((await call('/api/admin/login',{method:'POST',body:{password:'wrong'}})).status,401);
const login=await call('/api/admin/login',{method:'POST',body:{password}});assert.equal(login.status,200);
const setCookie=login.headers.get('Set-Cookie');assert.match(setCookie,/HttpOnly; Secure; SameSite=Strict/);const cookie=setCookie.split(';')[0];
assert.equal((await call('/api/admin/report',{cookie:cookie.slice(0,-1)+'x'})).status,401);
const visitor=randomUUID(),session=randomUUID();
const event={id:randomUUID(),visitor,session,event:'page_view',path:'/',source:'https://example.com/private?q=secret'};
assert.equal((await call('/api/collect',{method:'POST',body:event})).status,200);
await call('/api/collect',{method:'POST',body:event}); // Network retries must not double count.
await call('/api/collect',{method:'POST',body:{...event,id:randomUUID(),path:'/docs/'}});
await call('/api/collect',{method:'POST',body:{...event,id:randomUUID(),event:'download_click'}});
await call('/api/collect',{method:'POST',body:{...event,id:randomUUID(),visitor:randomUUID(),session:randomUUID()}});
assert.equal((await call('/api/collect',{method:'POST',body:{...event,path:'/admin/'}})).status,400);
assert.equal((await call('/api/collect',{method:'POST',body:{...event,path:'/?secret=1'}})).status,400);
assert.equal((await call('/api/collect',{method:'POST',body:{...event,ip:'must not accept'}})).status,400);
assert.equal((await call('/api/collect',{method:'POST',body:event,origin:'https://other.example'})).status,403);
const report=await(await call('/api/admin/report?days=7',{cookie})).json();
assert.equal(report.pageViews,3);assert.equal(report.visitors,2);assert.equal(report.sessions,2);assert.equal(report.actions[0].count,1);assert.equal(report.sources[0].label,'example.com');assert.equal(report.countries[0].label,'CN');assert.ok(report.startedAt);
assert.equal((await call('/api/admin/report?days=999',{cookie})).status,400);
for(let i=0;i<5;i++)await call('/api/admin/login',{method:'POST',body:{password:'wrong'},ip:'limited'});
assert.equal((await call('/api/admin/login',{method:'POST',body:{password},ip:'limited'})).status,429);
assert.equal((await call('/api/admin/logout',{method:'POST',cookie})).headers.get('Set-Cookie').includes('Max-Age=0'),true);
const stored=db.prepare('SELECT * FROM events').all();assert.ok(!JSON.stringify(stored).includes('secret'));assert.ok(!JSON.stringify(stored).includes('test-ip'));
// A 30-day UV is distinct across days, rather than the sum of daily visitors.
const yesterday=new Date(Date.now()-86400000+28800000).toISOString().slice(0,10);
db.prepare('INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?)').run(randomUUID(),yesterday,new Date().toISOString(),visitor,session,'page_view','/','direct','CN');
const multi=await(await call('/api/admin/report?days=7',{cookie})).json();assert.equal(multi.visitors,2);assert.equal(multi.pageViews,4);
// Client respects opt-out and stays functional if browser storage is blocked.
const client=await readFile(new URL('./telemetry.js',import.meta.url),'utf8');
function simulate(opt={}){const sent=[],storage=new Map();const context={location:{hostname:'xmpvz.pages.dev',origin:base,pathname:'/'},navigator:opt,crypto:globalThis.crypto,URL,document:{referrer:'',addEventListener(){}},fetch:(path,init)=>{sent.push(JSON.parse(init.body));return Promise.resolve();}};context.window={};for(const key of ['localStorage','sessionStorage'])Object.defineProperty(context.window,key,{get(){if(opt.blocked)throw Error('denied');return{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)};}});vm.runInNewContext(client,context);return sent;}
assert.equal(simulate({doNotTrack:'1'}).length,0);assert.equal(simulate({globalPrivacyControl:true}).length,0);assert.equal(simulate({blocked:true}).length,1);assert.equal(simulate().length,1);
console.log('Analytics passed: auth, signed cookies, origin, deduplication, date/UV reports, sanitization, rate limits, opt-out, blocked storage.');
