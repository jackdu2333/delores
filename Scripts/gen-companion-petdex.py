#!/usr/bin/env python3
"""Rebuild Petdex companion walk rows: full-cycle frames, ground-aligned, nearest neighbour.

Idle / reaction / daze / acrobatics cells are left as they are. Only the walk rows change.
"""
from __future__ import annotations

import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Tinycast/Resources"
CACHE = Path("/tmp/delores-petdex-cache")
CELL = 48
WALK_LEFT_ROW = 1
WALK_RIGHT_ROW = 2
PAD = 3


@dataclass(frozen=True)
class PetSpec:
    name: str
    url: str
    frames: list[int] | None = None
    center_v: bool = False


PETS = [
    PetSpec(
        "CompanionAtlas-nezuko.generated.png",
        "https://assets.petdex.dev/pets/nezukocoder-7d766f7c2597/sprite.webp",
        frames=[0, 2, 4, 6],
        center_v=False,
    ),
    PetSpec(
        "CompanionAtlas-ddoZvzo.generated.png",
        "https://assets.petdex.dev/pets/ddo-zvzo-49f5c2067af6/sprite.webp",
        frames=[0, 2, 4, 6],
        center_v=False,
    ),
    PetSpec(
        "CompanionAtlas-whaledou.generated.png",
        "https://assets.petdex.dev/pets/whaledou-c4cb6b24fb56/sprite.webp",
        frames=[0, 2, 4, 6],
        center_v=True,
    ),
    PetSpec(
        "CompanionAtlas-xiaoHei.generated.png",
        "https://assets.petdex.dev/pets/nightleaf-3ffbd69b2946/sprite.webp",
        frames=[0, 3, 4, 7],
        center_v=False,
    ),
    PetSpec(
        "CompanionAtlas-gugugaga.generated.png",
        "https://assets.petdex.dev/pets/gugugaga-cedf2dac1434/sprite.webp",
        frames=[0, 1, 4, 5],
        center_v=False,
    ),
    PetSpec(
        "CompanionAtlas-lillia.generated.png",
        "https://assets.petdex.dev/pets/snow-plum-lillia-2a5fc9e46017/sprite.webp",
        frames=[0, 2, 4, 6],
        center_v=False,
    ),
    PetSpec(
        "CompanionAtlas-dog.generated.png",
        "https://assets.petdex.dev/pets/aka-shiba-5758e3fbe12c/sprite.webp",
        frames=[1, 3, 5, 7],
        center_v=False,
    ),
]


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 1000:
        return
    req = urllib.request.Request(url, headers={"User-Agent": "DeloresCompanion/1.0"})
    with urllib.request.urlopen(req, timeout=30) as response, dest.open("wb") as out:
        out.write(response.read())


def occupied_cols(sheet: Image.Image, row: int, fw: int, fh: int) -> list[int]:
    cols = []
    for col in range(sheet.width // fw):
        cell = sheet.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
        if cell.getbbox():
            cols.append(col)
    return cols


def pick_walk_cols(cols: list[int], frames: list[int] | None = None) -> list[int]:
    if frames is not None:
        if len(frames) != 4:
            raise SystemExit("walk frames must contain exactly 4 frames, got %d" % len(frames))
        if any(i < 0 or i >= len(cols) for i in frames):
            raise SystemExit("frame index out of range for cols (len=%d): %s" % (len(cols), frames))
        return [cols[i] for i in frames]
    if len(cols) >= 8:
        return [cols[0], cols[2], cols[4], cols[6]]
    if len(cols) >= 4:
        last = len(cols) - 1
        return [cols[round(i * last / 3)] for i in range(4)]
    raise SystemExit("walk row has %d frames; need at least 4" % len(cols))


def ground_frames(cells: list[Image.Image], center_v: bool = False) -> list[Image.Image]:
    boxes = [cell.getbbox() for cell in cells]
    if any(box is None for box in boxes):
        raise SystemExit("walk frame is empty")
    union_left = min(b[0] for b in boxes)
    union_top = min(b[1] for b in boxes)
    union_right = max(b[2] for b in boxes)
    union_bottom = max(b[3] for b in boxes)
    union_w = union_right - union_left
    union_h = union_bottom - union_top
    scale = min((CELL - 2 * PAD) / union_w, (CELL - 2 * PAD) / union_h)
    target_w = max(1, round(union_w * scale))
    target_h = max(1, round(union_h * scale))
    ground = CELL - PAD
    frames = []
    for cell in cells:
        cropped = cell.crop((union_left, union_top, union_right, union_bottom))
        scaled = cropped.resize((target_w, target_h), Image.Resampling.NEAREST)
        frame = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        px = (CELL - target_w) // 2
        py = (CELL - target_h) // 2 if center_v else max(0, ground - target_h)
        frame.paste(scaled, (px, py), scaled)
        frames.append(frame)
    return frames


def replace_walk(atlas: Image.Image, frames: list[Image.Image], row: int) -> None:
    empty = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for col in range(5):
        atlas.paste(empty, (col * CELL, row * CELL))
    for col, frame in enumerate(frames):
        atlas.paste(frame, (col * CELL, row * CELL), frame)


def rebuild(spec: PetSpec) -> None:
    dest = RESOURCES / spec.name
    if not dest.exists():
        raise SystemExit("missing atlas %s" % dest)
    cache = CACHE / (dest.stem + Path(spec.url).suffix)
    download(spec.url, cache)
    sheet = Image.open(cache).convert("RGBA")
    fw, fh = sheet.width // 8, sheet.height // 9
    cols = occupied_cols(sheet, 1, fw, fh)
    picked = pick_walk_cols(cols, spec.frames)
    cells = [sheet.crop((col * fw, 1 * fh, (col + 1) * fw, 2 * fh)) for col in picked]
    right = ground_frames(cells, center_v=spec.center_v)
    if any(right[i].tobytes() == right[(i + 1) % 4].tobytes() for i in range(4)):
        raise SystemExit("%s: walk cycle has adjacent identical frames" % spec.name)
    if right[0].tobytes() == right[2].tobytes():
        raise SystemExit("%s: walk frames 0 and 2 are identical" % spec.name)
    tops = [f.getbbox()[1] for f in right if f.getbbox()]
    if max(tops) - min(tops) > 3:
        raise SystemExit("%s: top jitter exceeds 3px (got %dpx)" % (spec.name, max(tops) - min(tops)))
    left = [frame.transpose(Image.FLIP_LEFT_RIGHT) for frame in right]
    atlas = Image.open(dest).convert("RGBA")
    replace_walk(atlas, left, WALK_LEFT_ROW)
    replace_walk(atlas, right, WALK_RIGHT_ROW)
    atlas.save(dest)
    print("%s: walk cols %s, center_v=%s" % (spec.name, picked, spec.center_v))


def main() -> int:
    CACHE.mkdir(parents=True, exist_ok=True)
    for spec in PETS:
        rebuild(spec)
    return 0


if __name__ == "__main__":
    sys.exit(main())
