#!/usr/bin/env python3
"""
Regenerate CompanionAtlas-nezuko.generated.png with natural alternating walk cycle (left & right legs).
"""
import os
import urllib.request
import zipfile
from PIL import Image

RAW_DIR = "/tmp/nezuko_raw"
os.makedirs(RAW_DIR, exist_ok=True)
zip_path = os.path.join(RAW_DIR, "zip.zip")
spritesheet_path = os.path.join(RAW_DIR, "spritesheet.webp")

if not os.path.exists(spritesheet_path):
    print("Downloading Petdex NezukoCoder asset...")
    url = "https://assets.petdex.dev/pets/nezukocoder-7d766f7c2597/zip.zip"
    urllib.request.urlretrieve(url, zip_path)
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(RAW_DIR)

im = Image.open(spritesheet_path)
cw, ch = 192, 208

cols = 5
rows = 6
cell_size = 48

tw, th = 41, 44
ox = (cell_size - tw) // 2
oy = 46 - th

def render_cell(orig_r, orig_c):
    if orig_r is None or orig_c is None:
        return Image.new('RGBA', (cell_size, cell_size), (0, 0, 0, 0))
    cell = im.crop((orig_c * cw, orig_r * ch, (orig_c + 1) * cw, (orig_r + 1) * ch))
    scaled = cell.resize((tw, th), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (cell_size, cell_size), (0, 0, 0, 0))
    canvas.paste(scaled, (ox, oy), scaled)
    return canvas

mapping = {
    0: [(0, 0), (0, 2), (0, 4), None, None],           # Row 0: idle (3 frames)
    1: [(2, 0), (2, 2), (2, 4), (2, 6), None],         # Row 1: walkLeft (4 frames: left step, left plant, right step, right plant)
    2: [(1, 0), (1, 2), (1, 4), (1, 6), None],         # Row 2: walkRight (4 frames: right step, right plant, left step, left plant)
    3: [(0, 0), (8, 2), (3, 1), (3, 3), (4, 2)],       # Row 3: reaction (glance x2, wave x2, chat)
    4: [(6, 0), (6, 1), (6, 3), (6, 5), None],         # Row 4: daze (waiting/thinking 4 frames)
    5: [(4, 0), (4, 1), (4, 2), (4, 4), None],         # Row 5: acrobatics (jump takeoff, apex, drop, land)
}

atlas = Image.new('RGBA', (cols * cell_size, rows * cell_size), (0, 0, 0, 0))

for r in range(rows):
    for c in range(cols):
        orig_r, orig_c = mapping[r][c] if mapping[r][c] is not None else (None, None)
        cell_img = render_cell(orig_r, orig_c)
        atlas.paste(cell_img, (c * cell_size, r * cell_size))

out_path = "/Users/jackdu/Documents/小工具/delores/Tinycast/Resources/CompanionAtlas-nezuko.generated.png"
atlas.save(out_path)
print("Successfully written to:", out_path)
