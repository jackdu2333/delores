#!/usr/bin/env node
// Generate Duck pixel atlas (5 columns x 6 rows)
// Tinycast/Resources/CompanionAtlas-duck.generated.png
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
const OUTLINE = 1;      // Dark outline #2e261d
const FEATHER = 2;      // Warm butter duck yellow #fedc56
const SHADE = 3;        // Amber shadow #e0b832
const BEAK = 4;         // Bright orange beak & feet #ff8811
const EYE = 5;          // Dark eye #201a15
const EYE_WHITE = 6;    // Eye highlight #ffffff
const BLUSH = 7;        // Cheek blush #ff9e80

const PALETTE = [
  [0, 0, 0, 0],
  [46, 38, 29, 255],
  [254, 220, 86, 255],
  [224, 184, 50, 255],
  [255, 136, 17, 255],
  [32, 26, 21, 255],
  [255, 255, 255, 255],
  [255, 158, 128, 255],
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

function duck({
  breathe = 0,
  lift = 0,
  lean = 0,
  waddle = 0,
  blink = false,
  gaze = 0,
  mouth = "closed",
  wing = "rest",
  sleeping = false
}) {
  const g = grid();
  const cy = 13 + breathe + lift;
  const cx = 11.5 + lean;

  // Tail fluff
  disc(g, cx - 6, cy + 1, 3.5, 3.0, FEATHER);

  // Body
  disc(g, cx, cy + 2, 7.5, 6.0, FEATHER);

  // Head
  const headY = cy - 3;
  disc(g, cx + 2 + gaze, headY, 5.5, 5.0, FEATHER);

  // Shading
  for (let y = 0; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) {
      if (g[y * CELL + x] === FEATHER && y >= cy + 4) {
        g[y * CELL + x] = SHADE;
      }
    }
  }

  // Wing
  if (wing === "flap") {
    disc(g, cx - 1, cy, 4.0, 5.5, SHADE);
    disc(g, cx - 1, cy - 2, 3.5, 4.0, FEATHER);
  } else if (wing === "wave") {
    disc(g, cx + 4, cy - 2, 3.5, 4.0, FEATHER);
  } else {
    disc(g, cx - 1, cy + 2, 4.0, 3.2, SHADE);
  }

  // Paddle feet
  const footY = 19 + lift;
  if (!sleeping) {
    if (waddle === 1) {
      rect(g, cx - 3, footY - 1, 3, 2, BEAK);
      rect(g, cx + 2, footY, 3, 2, BEAK);
    } else if (waddle === -1) {
      rect(g, cx - 3, footY, 3, 2, BEAK);
      rect(g, cx + 2, footY - 1, 3, 2, BEAK);
    } else {
      rect(g, cx - 3, footY, 3, 2, BEAK);
      rect(g, cx + 2, footY, 3, 2, BEAK);
    }
  }

  // Eye & Blush
  const eyeX = cx + 4 + gaze;
  const eyeY = headY - 1;
  if (blink || sleeping) {
    rect(g, eyeX, eyeY + 1, 3, 1, EYE);
  } else {
    rect(g, eyeX, eyeY, 2, 3, EYE);
    put(g, eyeX, eyeY, EYE_WHITE);
  }
  rect(g, eyeX - 2, eyeY + 2, 2, 1, BLUSH);

  // Orange Beak
  const beakX = cx + 6 + gaze;
  const beakY = headY + 1;
  if (mouth === "quack" || mouth === "yawn") {
    rect(g, beakX, beakY - 1, 4, 1, BEAK);
    rect(g, beakX, beakY + 1, 3, 1, BEAK);
  } else {
    rect(g, beakX, beakY, 4, 2, BEAK);
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

const DUCK_WALK = [
  { lift: 0, lean: 1, waddle: 0 },
  { lift: -1, lean: 1, waddle: 1 },
  { lift: 0, lean: 1, waddle: 0 },
  { lift: -1, lean: 1, waddle: -1 },
];

function frame(row, col) {
  switch (row) {
    case 0:
      if (col === 0) return duck({});
      if (col === 1) return duck({ breathe: 1 });
      if (col === 2) return duck({ blink: true });
      return grid();
    case 1:
      return col < DUCK_WALK.length ? mirror(duck({ ...DUCK_WALK[col], gaze: 1 })) : grid();
    case 2:
      return col < DUCK_WALK.length ? duck({ ...DUCK_WALK[col], gaze: 1 }) : grid();
    case 3:
      if (col === 0) return duck({ gaze: -1 });
      if (col === 1) return duck({ gaze: 1, wing: "flap" });
      if (col === 2) return duck({ wing: "wave" });
      if (col === 3) return duck({ wing: "flap", mouth: "quack" });
      return duck({ mouth: "quack", wing: "flap" });
    case 4:
      if (col === 0) return duck({ mouth: "yawn", blink: true });
      if (col === 1) return duck({ wing: "flap", blink: true });
      if (col === 2) return duck({ lift: 2, sleeping: true, breathe: 0 });
      if (col === 3) return duck({ lift: 2, sleeping: true, breathe: 1 });
      return grid();
    default:
      if (col === 0) return duck({ lift: 2, waddle: 0 });
      if (col === 1) return duck({ lift: -4, wing: "flap", mouth: "quack" });
      if (col === 2) return duck({ lift: 1, wing: "flap", mouth: "quack" });
      if (col === 3) return duck({ lift: 0, wing: "wave", blink: true });
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
const pngPath = path.join(ROOT, "Tinycast/Resources/CompanionAtlas-duck.generated.png");
fs.writeFileSync(pngPath, encodePNG());
console.log("Duck atlas written: " + ATLAS_W + "x" + ATLAS_H + "px -> " + pngPath);
