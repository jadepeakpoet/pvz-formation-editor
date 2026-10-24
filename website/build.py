from pathlib import Path
import shutil, json, hashlib
root=Path(__file__).resolve().parent
dist=root/'dist';dist.mkdir(exist_ok=True)
for name in ['index.html','404.html','style.css','site.js','language.js','telemetry.js','admin','docs','en']:
    src=root/name;dst=dist/name
    if src.is_dir(): shutil.copytree(src,dst,dirs_exist_ok=True)
    else: shutil.copy2(src,dst)
for page in dist.rglob('*.html'):
    if 'admin' in page.relative_to(dist).parts or page.name == '404.html': continue
    html=page.read_text(encoding='utf-8')
    html=html.replace('</head>','<script src="/telemetry.js" defer></script></head>')
    privacy=('<p class="note">First-party anonymous analytics measure visits and download clicks. Raw IPs and URL query strings are not stored. <a href="/en/docs/#website-analytics">Analytics information</a></p>' if 'en' in page.relative_to(dist).parts else '<p class="note">本站使用第一方匿名标识统计访问与下载点击，不保存原始 IP 或网址查询参数。<a href="/docs/#website-analytics">统计说明</a></p>')
    if '<footer>' in html: html=html.replace('</footer>',privacy+'</footer>')
    page.write_text(html,encoding='utf-8')
shutil.copy2(root.parent/'LICENSE',dist/'license.txt')
(dist/'assets').mkdir(exist_ok=True)
shutil.copy2(root.parent/'assets/branding/app-logo.png',dist/'assets/app-logo.png')
(dist/'downloads').mkdir(exist_ok=True)
parts_dir=dist/'downloads/parts'
if parts_dir.exists():
    for stale in parts_dir.glob('*.bin'): stale.unlink()
for src in (root.parent/'release/1.0.0').glob('*'):
    if not src.is_file() or src.name.endswith('-source.zip'): continue
    if src.suffix != '.zip':
        shutil.copy2(src,dist/'downloads'/src.name)
        continue
    data=src.read_bytes();sha=hashlib.sha256(data).hexdigest();part_size=8*1024*1024
    parts=dist/'downloads/parts';parts.mkdir(exist_ok=True)
    for index,offset in enumerate(range(0,len(data),part_size)):
        (parts/f'{sha}-{index}.bin').write_bytes(data[offset:offset+part_size])
    release={'name':src.name,'path':'/downloads/'+src.name,'size':len(data),'partSize':part_size,'sha256':sha}
    worker=(root/'download-worker.js').read_text(encoding='utf-8').replace('__RELEASE__',json.dumps(release))
    worker=worker.replace('// __ANALYTICS__',(root/'analytics-worker.js').read_text(encoding='utf-8'))
    (dist/'_worker.js').write_text(worker,encoding='utf-8')
    (dist/'_routes.json').write_text(json.dumps({'version':1,'include':[release['path'],'/api/*'],'exclude':[]}),encoding='utf-8')
    (dist/'release.json').write_text(json.dumps(release,indent=2),encoding='utf-8')
    # Remove a stale direct ZIP from an earlier local build, if present.
    direct=dist/'downloads'/src.name
    if direct.exists(): direct.unlink()
(dist/'_headers').write_text('/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  X-Frame-Options: DENY\n',encoding='utf-8')
source_zip=dist/'downloads/PvZ-Formation-Editor-1.0.0-source.zip'
if source_zip.exists(): source_zip.unlink()
checksums=dist/'downloads/SHA256SUMS.txt'
if checksums.exists():
    lines=[line for line in checksums.read_text(encoding='ascii').splitlines() if not line.endswith('-source.zip')]
    checksums.write_text('\n'.join(lines)+'\n',encoding='ascii')
print(dist)
