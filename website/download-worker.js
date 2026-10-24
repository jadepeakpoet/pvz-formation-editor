// Pages advanced-mode worker. Stream an ordinary ZIP from bounded static parts.
const releases = __RELEASES__;
// __ANALYTICS__
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if(url.pathname.startsWith('/api/')) return analyticsFetch(request,env);
    const release=releases.find(item=>item.path===url.pathname);
    if (!release) return env.ASSETS.fetch(request);
    if (!['GET', 'HEAD'].includes(request.method)) return new Response(null, {status:405,headers:{Allow:'GET, HEAD'}});
    const headers = new Headers({
      'Content-Type':'application/zip',
      'Content-Disposition':`attachment; filename="${release.name}"`,
      'Accept-Ranges':'bytes', 'ETag':`"${release.sha256}"`,
      'Cache-Control':'public, max-age=3600', 'X-Content-Type-Options':'nosniff'
    });
    let start=0, end=release.size-1, status=200;
    const range=request.headers.get('Range');
    if (range && (!request.headers.has('If-Range') || request.headers.get('If-Range')===headers.get('ETag'))) {
      const match=/^bytes=(\d*)-(\d*)$/.exec(range);
      if (!match || (!match[1]&&!match[2])) return new Response(null,{status:416,headers:{'Content-Range':`bytes */${release.size}`}});
      if (!match[1]) start=Math.max(0,release.size-Number(match[2]));
      else { start=Number(match[1]); if(match[2]) end=Math.min(end,Number(match[2])); }
      if(start>end || start>=release.size) return new Response(null,{status:416,headers:{'Content-Range':`bytes */${release.size}`}});
      status=206;headers.set('Content-Range',`bytes ${start}-${end}/${release.size}`);
    }
    headers.set('Content-Length',String(end-start+1));
    if(request.method==='HEAD') return new Response(null,{status,headers});
    let position=start, reader=null, skip=0, remaining=0;
    const body=new ReadableStream({
      async pull(controller) {
        try {
          while(true) {
            if(!reader) {
              if(position>end){controller.close();return;}
              const index=Math.floor(position/release.partSize);
              const partEnd=Math.min(end,(index+1)*release.partSize-1);
              const partURL=new URL(`/downloads/parts/${release.sha256}-${index}.bin`,url);
              const res=await env.ASSETS.fetch(new Request(partURL));
              skip=position-index*release.partSize; remaining=partEnd-position+1;
              if(!res.ok || !res.body) throw new Error('Download part unavailable');
              reader=res.body.getReader(); position=partEnd+1;
            }
            const item=await reader.read();
            if(item.done) throw new Error('Incomplete download part');
            let value=item.value;
            if(skip>=value.byteLength){skip-=value.byteLength;continue;}
            value=value.subarray(skip);skip=0;
            if(value.byteLength>remaining) value=value.subarray(0,remaining);
            remaining-=value.byteLength;
            if(remaining===0){await reader.cancel();reader.releaseLock();reader=null;}
            controller.enqueue(value);return;
          }
        } catch(error) {controller.error(error);}
      },
      cancel(reason){return reader?.cancel(reason);}
    });
    return new Response(body,{status,headers});
  }
};
