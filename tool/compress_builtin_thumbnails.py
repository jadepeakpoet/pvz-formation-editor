"""Compress prepared built-in PNG previews into the bundled WebP cache."""
from pathlib import Path
import sys,json,shutil,os
root=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(root/'.local-tools/python-packages'))
from PIL import Image
source=root/'build/builtin-thumbnails';output=root/'assets/original/thumbnails';output.mkdir(parents=True,exist_ok=True)
index=json.loads((source/'index.json').read_text())
selected=os.environ.get('PVZ_THUMBNAIL_PRESETS')
keys=index['keys'] if selected is None else [index['presets'][name]['key'] for name in selected.split(',')]
old=json.loads((output/'index.json').read_text()) if (output/'index.json').exists() else None
for key in keys:
    with Image.open(source/(key+'.png')) as image: image.save(output/(key+'.webp'),'WEBP',quality=88,method=5)
shutil.copy2(source/'index.json',output/'index.json')
if old:
    for key in set(old['keys'])-set(index['keys']):
        (output/(key+'.webp')).unlink(missing_ok=True)
print(f"{len(index['keys'])} compressed previews: {sum(p.stat().st_size for p in output.glob('*.webp'))/1048576:.2f} MiB")
