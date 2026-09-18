#!/usr/bin/env node
// Generate Shiba Inu (Dog) pixel atlas (5 columns x 6 rows)
// Tinycast/Resources/CompanionAtlas-dog.generated.png
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
const OUTLINE = 1;      // Dark charcoal outline #2d2420
const COAT_ORANGE = 2;  // Classic Shiba golden sesame coat #e58826
const WHITE_CHEEK = 3;  // Urajiro white cheeks & chest #fdfcf7
const SHADE_TAN = 4;    // Tan shadow #bf6c16
const NOSE_BLACK = 5;   // Black button nose & eyes #1a1614
const TONGUE_PINK = 6;  // Blep / panting pink tongue #ff7597
const BLUSH_RED = 7;    // Cheerful blush #ff9980

const PALETTE = [
  [0, 0, 0, 0],
  [45, 36, 32, 255],
  [229, 136, 38, 255],
  [253, 252, 247, 255],
  [191, 108, 22, 255],
  [26, 22, 20, 255],
  [255, 117, 151, 255],
  [255, 153, 128, 255],
];

const grid = () => new Uint8Array(CELL * CELL);
const put = (g, x, y, v) => {
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

// Shiba Inu traits:
// Pricked triangular ears, chubby cheeks with white urajiro fur, curly donut tail, wagging butt, blep tongue.
function dog({
  breathe = 0,
  lift = 0,
  lean = 0,
  step = 0,
  blink = false,
  gaze = 0,
  mouth = "smile",   // "smile", "open", "yawn", "blep"
  tail = "curl",     // "curl", "wagHigh", "wagLow"
  pose = "stand",    // "stand", "sploot", "playBow"
}) {
  const g = grid();

  // Pose: sploot (flat on belly, back legs stretched out)
  if (pose === "sploot") {
    const cy = 15 + breathe;
    const cx = 11.5 + lean;
    // Flat chubby body
    disc(g, cx, cy + 2, 8.5, 4.5, COAT_ORANGE);
    // White chest & belly
    disc(g, cx + 1, cy + 3, 5.0, 2.5, WHITE_CHEEK);
    // Head flat on paws
    disc(g, cx + 4, cy - 1, 5.2, 4.2, COAT_ORANGE);
    disc(g, cx + 5, cy, 3.5, 2.8, WHITE_CHEEK);
    // Ears drooping back
    rect(g, cx + 1, cy - 4, 3, 2, COAT_ORANGE);
    rect(g, cx + 6, cy - 4, 3, 2, COAT_ORANGE);
    // Closed happy/sleepy eyes
    rect(g, cx + 4, cy - 1, 2, 1, NOSE_BLACK);
    rect(g, cx + 7, cy - 1, 2, 1, NOSE_BLACK);
    // Black button nose
    put(g, cx + 8, cy, NOSE_BLACK);
    // Back legs splooted outward behind
    rect(g, cx - 8, cy + 3, 3, 2, WHITE_CHEEK);
    // Tail lying low
    rect(g, cx - 7, cy + 1, 2, 2, COAT_ORANGE);
    outline(g);
    return g;
  }

  const cy = 13 + breathe + lift;
  const cx = 11.5 + lean;

  // Curly donut tail
  if (tail === "curl") {
    disc(g, cx - 7, cy - 2, 3.2, 3.2, COAT_ORANGE);
    put(g, cx - 7, cy - 2, TRANSPARENT); // hole in donut tail
  } else if (tail === "wagHigh") {
    rect(g, cx - 8, cy - 4, 3, 3, COAT_ORANGE);
    rect(g, cx - 6, cy - 2, 2, 2, WHITE_CHEEK);
  } else {
    rect(g, cx - 8, cy - 1, 3, 2, COAT_ORANGE);
  }

  // Round body
  disc(g, cx, cy + 2, 7.0, 5.8, COAT_ORANGE);
  // White chest / Urajiro
  disc(g, cx + 3, cy + 3, 3.5, 4.0, WHITE_CHEEK);

  // Head
  const headY = cy - 3;
  disc(g, cx + 3 + gaze, headY, 5.5, 5.0, COAT_ORANGE);
  // White cheek puff
  disc(g, cx + 5 + gaze, headY + 1, 3.8, 3.2, WHITE_CHEEK);

  // Pricked Ears
  const earX = cx + 3 + gaze;
  put(g, earX - 2, headY - 5, COAT_ORANGE);
  put(g, earX - 1, headY - 4, COAT_ORANGE);
  put(g, earX + 3, headY - 5, COAT_ORANGE);
  put(g, earX + 2, headY - 4, COAT_ORANGE);

  // Four short paws
  const footY = 19 + lift;
  const f1 = (step === 1) ? -1 : 0;
  const f2 = (step === 3) ? -1 : 0;
  rect(g, cx - 4, footY + f1, 3, 2, WHITE_CHEEK);
  rect(g, cx + 2, footY + f2, 3, 2, WHITE_CHEEK);

  // Black Eye & White Eyebrow dots (classic Shiba maro eyebrows!)
  const eyeX = cx + 4 + gaze;
  const eyeY = headY - 1;
  // White eyebrow dots
  put(g, eyeX - 1, eyeY - 2, WHITE_CHEEK);
  put(g, eyeX + 2, eyeY - 2, WHITE_CHEEK);

  if (blink || pose === "playBow") {
    rect(g, eyeX, eyeY + 1, 2, 1, NOSE_BLACK);
  } else {
    rect(g, eyeX, eyeY, 2, 3, NOSE_BLACK);
  }

  // Black Nose & Mouth
  const noseX = cx + 7 + gaze;
  put(g, noseX, headY + 1, NOSE_BLACK);

  if (mouth === "blep" || mouth === "open") {
    put(g, noseX, headY + 2, TONGUE_PINK);
    put(g, noseX + 1, headY + 2, TONGUE_PINK);
  } else if (mouth === "yawn") {
    rect(g, noseX - 1, headY + 2, 2, 2, TONGUE_PINK);
  }

  // Cute blush
  rect(g, eyeX - 1, eyeY + 2, 2, 1, BLUSH_RED);

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

const DOG_WALK = [
  { lift: 0, lean: 1, step: 0, tail: "curl" },
  { lift: -1, lean: 1, step: 1, tail: "wagHigh" },
  { lift: 0, lean: 1, step: 2, tail: "curl" },
  { lift: -1, lean: 1, step: 3, tail: "wagLow" },
];

function frame(row, col) {
  switch (row) {
    case 0:
      if (col === 0) return dog({ mouth: "smile" });
      if (col === 1) return dog({ breathe: 1, mouth: "blep" });
      if (col === 2) return dog({ blink: true, mouth: "smile" });
      return grid();
    case 1:
      return col < DOG_WALK.length ? mirror(dog({ ...DOG_WALK[col], gaze: 1, mouth: "blep" })) : grid();
    case 2:
      return col < DOG_WALK.length ? dog({ ...DOG_WALK[col], gaze: 1, mouth: "blep" }) : grid();
    case 3:
      // Reaction: tilt head (1), wag tail high (1), big panting smile (2), bark (1)
      if (col === 0) return dog({ gaze: -1, mouth: "blep", tail: "wagHigh" });
      if (col === 1) return dog({ gaze: 1, mouth: "open", tail: "wagLow" });
      if (col === 2) return dog({ tail: "wagHigh", mouth: "blep" });
      if (col === 3) return dog({ tail: "wagLow", mouth: "open" });
      return dog({ mouth: "open", lift: -1, tail: "wagHigh" });
    case 4:
      // Daze: big yawn -> stretch head down -> sploot nap (2)
      if (col === 0) return dog({ mouth: "yawn", blink: true });
      if (col === 1) return dog({ lift: 1, mouth: "blep", tail: "wagLow" });
      if (col === 2) return dog({ pose: "sploot", breathe: 0 });
      if (col === 3) return dog({ pose: "sploot", breathe: 1 });
      return grid();
    default:
      // Acrobatics: play bow crouch -> bounce leap -> spin roll -> proud tail wag
      if (col === 0) return dog({ lift: 2, tail: "wagHigh", mouth: "open" });
      if (col === 1) return dog({ lift: -4, mouth: "blep", tail: "wagHigh" });
      if (col === 2) return dog({ lift: 1, mouth: "smile", tail: "curl" });
      if (col === 3) return dog({ lift: 0, mouth: "blep", blink: true });
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
const pngPath = path.join(ROOT, "Tinycast/Resources/CompanionAtlas-dog.generated.png");
fs.writeFileSync(pngPath, encodePNG());
console.log("Dog atlas written: " + ATLAS_W + "x" + ATLAS_H + "px -> " + pngPath);
