// First-party website analytics. Never stores raw IPs, query strings or form input.
const encoder = new TextEncoder();
const hex = bytes => Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2,'0')).join('');
const day = time => new Date(time + 28800000).toISOString().slice(0,10);
const json = (data, status=200, extra={}) => new Response(JSON.stringify(data), {status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff',...extra}});
const fail = (message,status=400) => {throw Object.assign(new Error(message),{status});};
async function hmac(value, secret) {
  const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return hex(await crypto.subtle.sign('HMAC',key,encoder.encode(value)));
}
function equal(a,b) {let diff=a.length^b.length;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^(b.charCodeAt(i)||0);return diff===0;}
function sameOrigin(req) {if(req.headers.get('Origin')!==new URL(req.url).origin)fail('请求来源无效',403);}
async function body(req) {
  if(!req.headers.get('Content-Type')?.includes('application/json'))fail('需要 JSON 请求',415);
  const reader=req.body?.getReader();if(!reader)fail('缺少请求体');
  const chunks=[];let size=0;
  for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>4096){await reader.cancel();fail('请求过大',413);}chunks.push(value);}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  try {const data=JSON.parse(new TextDecoder().decode(bytes));if(!data||Array.isArray(data)||typeof data!=='object')fail('JSON 无效');return data;}catch{fail('JSON 无效');}
}
async function limit(req,env,kind,max) {
  const now=Date.now(), bucket=Math.floor(now/60000);
  const key=await hmac(`${kind}:${bucket}:${req.headers.get('CF-Connecting-IP')||'local'}`,env.SESSION_SECRET);
  const row=await env.DB.prepare('INSERT INTO rate_limits VALUES (?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1 RETURNING count').bind(key,now+120000).first();
  if(row.count>max)fail('请求过于频繁，请稍后再试',429);
}
const cookie=(value,maxAge)=>`__Host-pvz_admin=${value}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAge}`;
async function authenticated(req,env) {
  const token=req.headers.get('Cookie')?.match(/(?:^|;\s*)__Host-pvz_admin=([0-9]+\.[a-f0-9]{32}\.[a-f0-9]{64})(?:;|$)/)?.[1];
  if(!token)fail('请先登录',401);
  const [expires,nonce,signature]=token.split('.');
  if(Number(expires)<Date.now()||Number(expires)>Date.now()+8*3600000+60000||!equal(signature,await hmac(`${expires}.${nonce}`,env.SESSION_SECRET)))fail('登录已过期',401);
}
async function login(req,env) {
  sameOrigin(req);await limit(req,env,'login',5);const value=await body(req);
  if(typeof value.password!=='string'||value.password.length>128)fail('密码错误',401);
  const [scheme,salt,expected]=env.ADMIN_PASSWORD_HASH?.split('$')||[];
  if(scheme!=='pbkdf2-sha256'||!salt||!expected)fail('管理员密码未配置',503);
  const key=await crypto.subtle.importKey('raw',encoder.encode(value.password),'PBKDF2',false,['deriveBits']);
  const result=hex(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:encoder.encode(salt),iterations:100000},key,256));
  if(!equal(result,expected))fail('密码错误',401);
  const data=`${Date.now()+8*3600000}.${hex(crypto.getRandomValues(new Uint8Array(16)))}`;
  return json({ok:true},200,{'Set-Cookie':cookie(`${data}.${await hmac(data,env.SESSION_SECRET)}`,28800)});
}
const paths=new Set(['/','/en/','/docs/','/en/docs/']);
const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
async function collect(req,env) {
  sameOrigin(req);
  if(/bot|crawler|spider|headless/i.test(req.headers.get('User-Agent')||''))return json({ok:true,ignored:true});
  await limit(req,env,'collect',120);const v=await body(req);
  if(Object.keys(v).some(k=>!['id','visitor','session','event','path','source'].includes(k))||![v.id,v.visitor,v.session].every(uuid)||!paths.has(v.path)||!['page_view','download_click','qq_click'].includes(v.event))fail('统计字段无效');
  let source='direct';
  if(v.source){try{source=new URL(v.source).hostname;if(source.length>253)fail('来源无效');}catch{fail('来源无效');}}
  const country=/^[A-Z]{2}$/.test(req.cf?.country||'')?req.cf.country:'unknown';
  const now=Date.now();
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO events VALUES (?,?,?,?,?,?,?,?,?)').bind(v.id.toLowerCase(),day(now),new Date(now).toISOString(),v.visitor.toLowerCase(),v.session.toLowerCase(),v.event,v.path,source,country),
    env.DB.prepare('DELETE FROM rate_limits WHERE expires<?').bind(now),
    env.DB.prepare('DELETE FROM events WHERE day<?').bind(day(now-400*86400000))
  ]);
  return json({ok:true});
}
async function report(req,env) {
  await authenticated(req,env);
  const days=Number(new URL(req.url).searchParams.get('days')||30);
  if(![7,30,90].includes(days))fail('时间范围无效');
  const from=day(Date.now()-(days-1)*86400000), to=day(Date.now());
  const rows=async(sql,...args)=>(await env.DB.prepare(sql).bind(...args).all()).results;
  const [summary,daily,pages,sources,countries,actions,started]=await Promise.all([
    env.DB.prepare("SELECT COUNT(*) pageViews,COUNT(DISTINCT visitor) visitors,COUNT(DISTINCT session) sessions FROM events WHERE day>=? AND event='page_view'").bind(from).first(),
    rows("SELECT day,COUNT(*) pageViews,COUNT(DISTINCT visitor) visitors FROM events WHERE day>=? AND event='page_view' GROUP BY day ORDER BY day",from),
    rows("SELECT path label,COUNT(*) count FROM events WHERE day>=? AND event='page_view' GROUP BY path ORDER BY count DESC LIMIT 20",from),
    rows("SELECT source label,COUNT(*) count FROM events WHERE day>=? AND event='page_view' GROUP BY source ORDER BY count DESC LIMIT 20",from),
    rows("SELECT country label,COUNT(DISTINCT visitor) count FROM events WHERE day>=? AND event='page_view' GROUP BY country ORDER BY count DESC LIMIT 20",from),
    rows("SELECT event label,COUNT(*) count FROM events WHERE day>=? AND event!='page_view' GROUP BY event ORDER BY count DESC",from),
    env.DB.prepare("SELECT value FROM settings WHERE key='started_at'").first()
  ]);
  return json({from,to,timezone:'Asia/Shanghai',startedAt:started?.value,...summary,daily,pages,sources,countries,actions});
}
async function analyticsFetch(req,env) {
  try {
    if(!env.DB||!env.SESSION_SECRET||env.SESSION_SECRET.length<32)fail('统计服务尚未配置',503);
    const path=new URL(req.url).pathname;
    if(path==='/api/collect'&&req.method==='POST')return await collect(req,env);
    if(path==='/api/admin/login'&&req.method==='POST')return await login(req,env);
    if(path==='/api/admin/logout'&&req.method==='POST'){sameOrigin(req);return json({ok:true},200,{'Set-Cookie':cookie('',0)});}
    if(path==='/api/admin/report'&&req.method==='GET')return await report(req,env);
    return json({error:'接口不存在'},404);
  } catch(error) {return json({error:error.status?error.message:'统计服务暂时不可用'},error.status||500);}
}
