// Website only; the desktop application does not send these events.
(()=>{
  if(!['xmpvz.pages.dev'].includes(location.hostname)||navigator.globalPrivacyControl||navigator.doNotTrack==='1')return;
  const id=(store,key)=>{try{const storage=window[store];let v=storage.getItem(key);if(!v){v=crypto.randomUUID();storage.setItem(key,v);}return v;}catch{return crypto.randomUUID();}};
  const visitor=id('localStorage','pvz-visitor-v1'),session=id('sessionStorage','pvz-session-v1');
  const send=event=>{const payload={id:crypto.randomUUID(),visitor,session,event,path:location.pathname,source:document.referrer?new URL(document.referrer).origin:''};fetch('/api/collect',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload),keepalive:true,credentials:'same-origin'}).catch(()=>{});};
  send('page_view');
  document.addEventListener('click',event=>{const link=event.target.closest?.('a[href]');if(!link)return;const url=new URL(link.href);const downloadSource=url.origin===location.origin||(url.origin==='https://github.com'&&url.pathname.startsWith('/jadepeakpoet/pvz-formation-editor/releases/download/'));if(downloadSource&&/-(?:windows-x64|macos-arm64|macos-x64)\.zip$/.test(url.pathname))send('download_click');else if(url.hostname==='qm.qq.com')send('qq_click');});
})();
