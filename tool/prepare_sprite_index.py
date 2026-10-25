"""Generate pixel-deduplication metadata for runtime sprite extraction.
Run after changing original artwork: python tool/prepare_sprite_index.py
Requires Pillow (project-local .local-tools/python-packages is supported).
"""
from pathlib import Path
import sys, json, hashlib, re
root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / '.local-tools/python-packages'))
from PIL import Image
assets = root / 'assets/original'
sprites = json.loads((assets / 'sprites.json').read_text(encoding='utf-8'))
layouts = {}
for sprite in sprites.values():
    for part in sprite['images']:
        layouts.setdefault(part['path'], part)
manifest = {}
unique = set()
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
        manifest[path] = {'w':rw,'h':rh,'cols':cols,'rows':rows,'frames':frames}
(assets / 'frame_index.json').write_text(json.dumps(manifest, separators=(',',':'))+'\n',encoding='utf-8')
print(f'{sum(len(v["frames"]) for v in manifest.values())} frames, {len(unique)} unique; metadata only')

catalog=json.loads((root/'assets/original_catalog.json').read_text(encoding='utf-8'))
styles={}
for template in catalog['templates']:
    name=template['id'][1:]
    light=re.search(r'\blight="([^"]+)"',template['html'])
    kind=re.search(r'\bpkind="([^"]+)"',template['html'])
    styles[name]={'light':float(light.group(1)) if light else 1.9,'kind':kind.group(1) if kind else None}
(assets/'sprite_styles.json').write_text(json.dumps(styles,separators=(',',':'))+'\n')
