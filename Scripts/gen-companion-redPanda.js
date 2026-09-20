#!/usr/bin/env node
// Generate Red Panda (小熊猫) pixel atlas (5 columns x 6 rows)
// Tinycast/Resources/CompanionAtlas-redPanda.generated.png
"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const CELL = 24;
const SCALE = 2;
const COLUMNS = 5;
const ROWS = 6;
const FRAME_PX = CELL * SCALE;

const TRANSPARENT = 0;
const OUTLINE = 1;      // Dark warm charcoal #241c1a
const COAT_RUSSET = 2;  // Rich reddish-brown / russet coat #c44f24
const BELLY_BLACK = 3;  // Dark espresso belly & legs #2e2422
const WHITE_MARK = 4;   // White ears, tear tracks & muzzle #f8f6f0
const TAIL_RING = 5;    // Pale ginger tail rings #e68d53
const EYE_BLACK = 6;    // Black eyes #181210
const NOSE_PINK = 7;    // Soft pink nose & blush #ff8c82

const PALETTE = [
  [0, 0, 0, 0],
  [36, 28, 26, 255],
  [196, 79, 36, 255],
  [46, 36, 34, 255],
  [248, 246, 240, 255],
  [230, 141, 83, 255],
  [24, 18, 16, 255],
  [255, 140, 130, 255],
];

const grid = () => new Uint8Array(CELL * CELL);
const put = (g, x, y, v) => {
  x = Math.round(x);
  y = Math.round(y);
  if (x >= 0 && x < CELL && y >= 0 && y < CELL) g[y * CELL + x] = v;
};

function rect(g, x, y, w, h, v) {
  for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) put(g, x + i, y + j, v);
}

function disc(g, cx, cy, rx, ry, v) {
  for (let y = 0; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) {
      const dx = (x + 0.5 - cx) / rx;
      const dy = (y + 0.5 - cy) / ry;
      if (dx * dx + dy * dy <= 1) put(g, x, y, v);
    }
  }
}

function outline(g) {
  const drawn = Uint8Array.from(g);
  for (let y = 0; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) {
      if (drawn[y * CELL + x] !== TRANSPARENT) continue;
      const touching =
        drawn[y * CELL + Math.min(x + 1, CELL - 1)] !== TRANSPARENT ||
        drawn[y * CELL + Math.max(x - 1, 0)] !== TRANSPARENT ||
        drawn[Math.min(y + 1, CELL - 1) * CELL + x] !== TRANSPARENT ||
        drawn[Math.max(y - 1, 0) * CELL + x] !== TRANSPARENT;
      if (touching) g[y * CELL + x] = OUTLINE;
    }
  }
}

// Red Panda traits:
// Fluffy striped ringed tail, white ear rim and white tear masks, russet back + espresso belly,
// cute stand-up paws-up "threat" pose.
function redPanda({
  breathe = 0,
  lift = 0,
  lean = 0,
  step = null,
  blink = false,
  gaze = 0,
  threat = false,   // Famous "hands up" pose
  pose = "stand",   // "stand", "dangle" (belly flop on branch)
  mouth = "closed"
}) {
  const g = grid();

  // Pose: paws up threat pose (super cute!)
  if (threat) {
    const cx = 11.5;
    const cy = 13 + breathe;
    // Upright body
    disc(g, cx, cy + 1, 6.0, 7.5, COAT_RUSSET);
    // Dark belly
    disc(g, cx, cy + 2, 4.0, 5.0, BELLY_BLACK);
    // Big fluffy tail to right
    disc(g, cx - 6, cy + 3, 4.5, 4.0, COAT_RUSSET);
    rect(g, cx - 7, cy + 2, 2, 3, TAIL_RING);
    // Head
    disc(g, cx, cy - 5, 5.5, 5.0, COAT_RUSSET);
    // White ears with black tips
    rect(g, cx - 5, cy - 9, 3, 2, WHITE_MARK);
    rect(g, cx + 2, cy - 9, 3, 2, WHITE_MARK);
    put(g, cx - 4, cy - 10, BELLY_BLACK);
    put(g, cx + 3, cy - 10, BELLY_BLACK);
    // White tear stripes
    put(g, cx - 3, cy - 4, WHITE_MARK);
    put(g, cx + 2, cy - 4, WHITE_MARK);
    // Black eyes
    rect(g, cx - 3, cy - 5, 2, 2, EYE_BLACK);
    rect(g, cx + 1, cy - 5, 2, 2, EYE_BLACK);
    // Nose
    put(g, cx - 1, cy - 3, NOSE_PINK);
    // Paws UP high!
    rect(g, cx - 7, cy - 6, 3, 3, BELLY_BLACK);
    rect(g, cx + 4, cy - 6, 3, 3, BELLY_BLACK);
    // Feet below
    rect(g, cx - 3, cy + 8, 3, 2, BELLY_BLACK);
    rect(g, cx + 1, cy + 8, 3, 2, BELLY_BLACK);
    outline(g);
    return g;
  }

  // Pose: dangle / branch flop nap
  if (pose === "dangle") {
    const cx = 11.5 + lean;
    const cy = 15 + breathe;
    // Flat body
    disc(g, cx, cy + 1, 8.5, 4.5, COAT_RUSSET);
    // Belly dark underside
    for (let x = cx - 5; x <= cx + 5; x++) put(g, x, cy + 4, BELLY_BLACK);
    // Head resting on edge
    disc(g, cx + 4, cy - 2, 5.2, 4.2, COAT_RUSSET);
    // White cheeks & ears
    put(g, cx + 3, cy - 5, WHITE_MARK);
    put(g, cx + 7, cy - 5, WHITE_MARK);
    rect(g, cx + 4, cy - 1, 2, 1, EYE_BLACK);
    rect(g, cx + 7, cy - 1, 2, 1, EYE_BLACK);
    // Huge striped tail draped over left edge
    disc(g, cx - 7, cy + 2, 4.0, 5.0, COAT_RUSSET);
    rect(g, cx - 8, cy + 1, 3, 2, TAIL_RING);
    rect(g, cx - 7, cy + 4, 3, 2, TAIL_RING);
    // Limp dangling paws
    rect(g, cx - 3, cy + 5, 2, 3, BELLY_BLACK);
    rect(g, cx + 2, cy + 5, 2, 3, BELLY_BLACK);
    outline(g);
    return g;
  }

  const cy = 13 + breathe + lift;
  const cx = 11.5 + lean;

  // Huge bushy striped tail
  disc(g, cx - 7, cy - 1, 4.5, 5.2, COAT_RUSSET);
  rect(g, cx - 8, cy - 3, 3, 2, TAIL_RING);
  rect(g, cx - 8, cy + 1, 3, 2, TAIL_RING);

  // Body: Russet back
  disc(g, cx - 1, cy + 2, 6.8, 5.5, COAT_RUSSET);
  // Espresso dark belly
  for (let y = cy + 3; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) {
      if (g[y * CELL + x] === COAT_RUSSET && y >= cy + 4) {
        g[y * CELL + x] = BELLY_BLACK;
      }
    }
  }

  // Head
  const headY = cy - 3;
  disc(g, cx + 3 + gaze, headY, 5.5, 4.8, COAT_RUSSET);

  // Big White Ears with dark tips
  const earX = cx + 3 + gaze;
  rect(g, earX - 3, headY - 5, 3, 2, WHITE_MARK);
  put(g, earX - 2, headY - 6, BELLY_BLACK);
  rect(g, earX + 2, headY - 5, 3, 2, WHITE_MARK);
  put(g, earX + 3, headY - 6, BELLY_BLACK);

  // White face tear patches & muzzle
  rect(g, earX + 1, headY + 1, 4, 2, WHITE_MARK);
  put(g, earX + 2, headY - 1, WHITE_MARK);

  // Dark paws
  const footY = 20;
  const paws = {
    0: { l: [-5, 0], r: [2, 0] },
    1: { l: [1, -4], r: [3, 0] },
    2: { l: [-3, 0], r: [5, 0] },
    3: { l: [-4, 0], r: [2, -4] },
  }[step] || { l: [0, 0], r: [0, 0] };
  rect(g, cx - 4 + paws.l[0], footY + paws.l[1], 3, 2, BELLY_BLACK);
  rect(g, cx + 2 + paws.r[0], footY + paws.r[1], 3, 2, BELLY_BLACK);

  // Eyes & Nose
  const eyeX = cx + 4 + gaze;
  const eyeY = headY - 1;
  if (blink) {
    rect(g, eyeX, eyeY + 1, 2, 1, EYE_BLACK);
  } else {
    rect(g, eyeX, eyeY, 2, 3, EYE_BLACK);
  }

  // Pink nose
  put(g, cx + 6 + gaze, headY + 1, NOSE_PINK);
  if (mouth === "open") {
    put(g, cx + 6 + gaze, headY + 2, NOSE_PINK);
  }

  outline(g);
  return g;
}

const mirror = (g) => {
  const out = grid();
  for (let y = 0; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) out[y * CELL + x] = g[y * CELL + (CELL - 1 - x)];
  }
  return out;
};

const PANDA_WALK = [
  { lift: 0, lean: 1, step: 0 },
  { lift: -1, lean: 1, step: 1 },
  { lift: 0, lean: 1, step: 2 },
  { lift: -1, lean: 1, step: 3 },
];

function frame(row, col) {
  switch (row) {
    case 0:
      if (col === 0) return redPanda({});
      if (col === 1) return redPanda({ breathe: 1 });
      if (col === 2) return redPanda({ blink: true });
      return grid();
    case 1:
      return col < PANDA_WALK.length ? mirror(redPanda({ ...PANDA_WALK[col], gaze: 1 })) : grid();
    case 2:
      return col < PANDA_WALK.length ? redPanda({ ...PANDA_WALK[col], gaze: 1 }) : grid();
    case 3:
      // Reaction: glance (1), wave tail (1), paws-up surprise (2), happy smile (1)
      if (col === 0) return redPanda({ gaze: -1 });
      if (col === 1) return redPanda({ gaze: 1, mouth: "open" });
      if (col === 2) return redPanda({ threat: true, breathe: 0 });
      if (col === 3) return redPanda({ threat: true, breathe: 1 });
      return redPanda({ mouth: "open" });
    case 4:
      // Daze: yawn -> tail curl -> dangle branch nap (2)
      if (col === 0) return redPanda({ mouth: "open", blink: true });
      if (col === 1) return redPanda({ lift: 1, blink: true });
      if (col === 2) return redPanda({ pose: "dangle", breathe: 0 });
      if (col === 3) return redPanda({ pose: "dangle", breathe: 1 });
      return grid();
    default:
      // Acrobatics: crouch -> big tail hop -> full hands-up intimidation -> land
      if (col === 0) return redPanda({ lift: 2 });
      if (col === 1) return redPanda({ lift: -4, mouth: "open" });
      if (col === 2) return redPanda({ threat: true });
      if (col === 3) return redPanda({ lift: 0, blink: true });
      return grid();
  }
}

const ATLAS_W = COLUMNS * FRAME_PX;
const ATLAS_H = ROWS * FRAME_PX;
const atlas = new Uint8Array(ATLAS_W * ATLAS_H);

function blit(cell, col, row) {
  for (let y = 0; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) {
      const v = cell[y * CELL + x];
      for (let sy = 0; sy < SCALE; sy++) {
        for (let sx = 0; sx < SCALE; sx++) {
          atlas[((row * CELL + y) * SCALE + sy) * ATLAS_W + (col * CELL + x) * SCALE + sx] = v;
        }
      }
    }
  }
}

const FRAMES_PER_ROW = [3, 4, 4, 5, 4, 4];

for (let row = 0; row < ROWS; row++) {
  for (let col = 0; col < COLUMNS; col++) {
    const cell = frame(row, col);
    const drawn = cell.some((v) => v !== TRANSPARENT);
    if (drawn !== col < FRAMES_PER_ROW[row]) {
      throw new Error("cell " + col + "," + row + " mismatch");
    }
    blit(cell, col, row);
  }
}

const walkPoses = [0, 1, 2, 3].map((col) => frame(2, col));
const samePose = (a, b) => a.every((v, i) => v === b[i]);
if (samePose(walkPoses[0], walkPoses[2]) || samePose(walkPoses[1], walkPoses[3])) {
  throw new Error("walk cycle repeats a pose");
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([length, body, crc]);
}

function encodePNG() {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(ATLAS_W, 0);
  ihdr.writeUInt32BE(ATLAS_H, 4);
  ihdr[8] = 8;
  ihdr[9] = 3;
  const plte = Buffer.concat(PALETTE.map(([r, g, b]) => Buffer.from([r, g, b])));
  const trns = Buffer.from(PALETTE.map(([, , , a]) => a));

  const raw = Buffer.alloc(ATLAS_H * (ATLAS_W + 1));
  for (let y = 0; y < ATLAS_H; y++) {
    const at = y * (ATLAS_W + 1);
    raw[at] = 0;
    for (let x = 0; x < ATLAS_W; x++) raw[at + 1 + x] = atlas[y * ATLAS_W + x];
  }

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("PLTE", plte),
    chunk("tRNS", trns),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

const ROOT = path.resolve(__dirname, "..");
const pngPath = path.join(ROOT, "Tinycast/Resources/CompanionAtlas-redPanda.generated.png");
fs.writeFileSync(pngPath, encodePNG());
console.log("Red Panda atlas written: " + ATLAS_W + "x" + ATLAS_H + "px -> " + pngPath);
