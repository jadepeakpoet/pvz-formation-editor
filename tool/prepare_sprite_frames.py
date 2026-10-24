"""Generate lossless, content-addressed sprite frames and compact alpha masks.
Run after changing original artwork: python tool/prepare_sprite_frames.py
Requires Pillow (project-local .local-tools/python-packages is supported).
"""
from pathlib import Path
import sys, json, hashlib, zlib, re
root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / '.local-tools/python-packages'))
from PIL import Image
assets = root / 'assets/original'
output = assets / 'frames'
output.mkdir(exist_ok=True)
sprites = json.loads((assets / 'sprites.json').read_text(encoding='utf-8'))
layouts = {}
for sprite in sprites.values():
    for part in sprite['images']:
        layouts.setdefault(part['path'], part)
manifest = {}
unique = set()
raw_bytes = 0
for path, part in sorted(layouts.items()):
    with Image.open(assets / path) as original:
        image = original.convert('RGBA')
        rw, rh = int(part['rw']), int(part['rh'])
        cols, rows = int(part['cols']), int(part['rows'])
        if path.endswith('/shadow.png'):
            rw, rh, cols, rows = image.width, image.height, 1, 1
        frames = []
        for row in range(rows):
            for col in range(cols):
                frame = image.crop((col * rw, row * rh, (col+1)*rw, (row+1)*rh))
                pixels = frame.tobytes()
                digest = hashlib.sha256(f'{rw}x{rh}:'.encode()+pixels).hexdigest()[:24]
                frames.append(digest)
                if digest in unique: continue
                unique.add(digest)
                png = output / (digest+'.png')
                if not png.exists(): frame.save(png, optimize=True)
                mask = bytearray((rw*rh+7)//8)
                for pixel, alpha in enumerate(frame.getchannel('A').tobytes()):
                    if alpha >= 16: mask[pixel>>3] |= 1 << (pixel&7)
                (output / (digest+'.mask')).write_bytes(zlib.compress(mask, 9))
                raw_bytes += rw*rh*4
        manifest[path] = {'w':rw,'h':rh,'cols':cols,'rows':rows,'frames':frames}
(output / 'index.json').write_text(json.dumps(manifest, separators=(',',':'))+'\n',encoding='utf-8')
print(f'{sum(len(v["frames"]) for v in manifest.values())} frames, {len(unique)} unique; {sum(p.stat().st_size for p in output.iterdir())/1048576:.2f} MiB encoded')

catalog=json.loads((root/'assets/original_catalog.json').read_text(encoding='utf-8'))
styles={}
for template in catalog['templates']:
    name=template['id'][1:]
    light=re.search(r'\blight="([^"]+)"',template['html'])
    kind=re.search(r'\bpkind="([^"]+)"',template['html'])
    styles[name]={'light':float(light.group(1)) if light else 1.9,'kind':kind.group(1) if kind else None}
(output/'styles.json').write_text(json.dumps(styles,separators=(',',':'))+'\n')
