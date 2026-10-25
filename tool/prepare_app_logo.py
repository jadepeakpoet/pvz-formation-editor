"""Resize the approved master for the 96px in-app logo; keep native icons intact."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(root / '.local-tools/python-packages'))
from PIL import Image

with Image.open(root / 'assets/branding/source/app-logo.png') as source:
    image = source.convert('RGBA')
    image.thumbnail((256, 256), Image.Resampling.LANCZOS)
    image.save(root / 'assets/branding/app-logo.png', optimize=True)
