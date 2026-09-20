#!/usr/bin/env python3
"""Rebuild Petdex companion walk rows: full-cycle frames, ground-aligned, nearest neighbour.

Idle / reaction / daze / acrobatics cells are left as they are. Only the walk rows change.
"""
from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Tinycast/Resources"
CACHE = Path("/tmp/delores-petdex-cache")
CELL = 48
WALK_LEFT_ROW = 1
WALK_RIGHT_ROW = 2
PAD = 3

PETS = [
    ("CompanionAtlas-nezuko.generated.png", "https://assets.petdex.dev/pets/nezukocoder-7d766f7c2597/sprite.webp"),
    ("CompanionAtlas-ddoZvzo.generated.png", "https://assets.petdex.dev/pets/ddo-zvzo-49f5c2067af6/sprite.webp"),
    ("CompanionAtlas-whaledou.generated.png", "https://assets.petdex.dev/pets/whaledou-c4cb6b24fb56/sprite.webp"),
    ("CompanionAtlas-xiaoHei.generated.png", "https://assets.petdex.dev/pets/nightleaf-3ffbd69b2946/sprite.webp"),
    ("CompanionAtlas-gugugaga.generated.png", "https://assets.petdex.dev/pets/gugugaga-cedf2dac1434/sprite.webp"),
    ("CompanionAtlas-lillia.generated.png", "https://assets.petdex.dev/pets/snow-plum-lillia-2a5fc9e46017/sprite.webp"),
    ("CompanionAtlas-dog.generated.png", "https://assets.petdex.dev/pets/aka-shiba-5758e3fbe12c/sprite.webp"),
]


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 1000:
        return
    req = urllib.request.Request(url, headers={"User-Agent": "DeloresCompanion/1.0"})
    with urllib.request.urlopen(req, timeout=30) as response, dest.open("wb") as out:
        out.write(response.read())


def occupied_cols(sheet, row, fw, fh):
    cols = []
    for col in range(sheet.width // fw):
        cell = sheet.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
        if cell.getbbox():
            cols.append(col)
    return cols


def pick_walk_cols(cols):
    if len(cols) >= 8:
        return [cols[0], cols[2], cols[4], cols[6]]
    if len(cols) >= 4:
        last = len(cols) - 1
        return [cols[round(i * last / 3)] for i in range(4)]
    raise SystemExit("walk row has %d frames; need at least 4" % len(cols))


def ground_frames(cells):
    boxes = [cell.getbbox() for cell in cells]
    if any(box is None for box in boxes):
        raise SystemExit("walk frame is empty")
    max_w = max(box[2] - box[0] for box in boxes)
    max_h = max(box[3] - box[1] for box in boxes)
    scale = min((CELL - 2 * PAD) / max_w, (CELL - 2 * PAD) / max_h)
    ground = CELL - PAD
    frames = []
    for cell, box in zip(cells, boxes):
        cropped = cell.crop(box)
        size = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
        scaled = cropped.resize(size, Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        px = (CELL - scaled.width) // 2
        py = max(0, ground - scaled.height)
        frame.paste(scaled, (px, py), scaled)
        frames.append(frame)
    return frames


def replace_walk(atlas, frames, row):
    empty = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for col in range(5):
        atlas.paste(empty, (col * CELL, row * CELL))
    for col, frame in enumerate(frames):
        atlas.paste(frame, (col * CELL, row * CELL), frame)


def rebuild(name, url):
    dest = RESOURCES / name
    if not dest.exists():
        raise SystemExit("missing atlas %s" % dest)
    cache = CACHE / (dest.stem + Path(url).suffix)
    download(url, cache)
    sheet = Image.open(cache).convert("RGBA")
    fw, fh = sheet.width // 8, sheet.height // 9
    cols = occupied_cols(sheet, 1, fw, fh)
    picked = pick_walk_cols(cols)
    cells = [sheet.crop((col * fw, 1 * fh, (col + 1) * fw, 2 * fh)) for col in picked]
    right = ground_frames(cells)
    if right[0].tobytes() == right[2].tobytes():
        raise SystemExit("%s: walk frames 0 and 2 are identical" % name)
    left = [frame.transpose(Image.FLIP_LEFT_RIGHT) for frame in right]
    atlas = Image.open(dest).convert("RGBA")
    replace_walk(atlas, left, WALK_LEFT_ROW)
    replace_walk(atlas, right, WALK_RIGHT_ROW)
    atlas.save(dest)
    print("%s: walk cols %s" % (name, picked))


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    for name, url in PETS:
        rebuild(name, url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
