(() => {
  const key='xmpvz-language';
  let preference='auto';
  try {preference=localStorage.getItem(key)||'auto';} catch {}
  if(!['auto','zh','en'].includes(preference)) preference='auto';
  const resolve=value=>value==='auto' ? ((navigator.language||'zh').toLowerCase().startsWith('zh')?'zh':'en') : value;
  const target=value=>{
    const url=new URL(location.href);
    const page=url.pathname.replace(/^\/en(?=\/|$)/,'')||'/';
    url.pathname=(resolve(value)==='en'?'/en':'')+(page==='/'?'/':page);
    return url;
  };
  const initial=target(preference);
  if(initial.pathname!==location.pathname){location.replace(initial.href);return;}
  addEventListener('DOMContentLoaded',()=>{
    const picker=document.querySelector('#language-picker');
    if(!picker)return;
    picker.value=preference;
    picker.addEventListener('change',()=>{
      preference=picker.value;
      try{localStorage.setItem(key,preference);}catch{}
      const destination=target(preference);
      if(destination.pathname!==location.pathname)location.assign(destination.href);
    });
  });
})();
