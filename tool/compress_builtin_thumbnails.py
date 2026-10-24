"""Compress prepared built-in PNG previews into the bundled WebP cache."""
from pathlib import Path
import sys,json,shutil
root=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(root/'.local-tools/python-packages'))
from PIL import Image
source=root/'build/builtin-thumbnails';output=root/'assets/original/thumbnails';output.mkdir(parents=True,exist_ok=True)
index=json.loads((source/'index.json').read_text())
for key in index['keys']:
    with Image.open(source/(key+'.png')) as image: image.save(output/(key+'.webp'),'WEBP',quality=88,method=5)
shutil.copy2(source/'index.json',output/'index.json')
print(f"{len(index['keys'])} compressed previews: {sum(p.stat().st_size for p in output.glob('*.webp'))/1048576:.2f} MiB")
