#!/usr/bin/env node
// Generate Cat pixel atlas (5 columns x 6 rows)
// Tinycast/Resources/CompanionAtlas-cat.generated.png
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
const OUTLINE = 1;     // Dark slate outline #25222e
const FUR_MAIN = 2;    // Warm cream / white fur #fbf8f2
const FUR_ORANGE = 3;  // Ginger orange patches (calico/tabby) #e88c38
const FUR_SHADE = 4;   // Muted cream shadow #dfd7cb
const NOSE_PINK = 5;   // Cute pink nose & ear inner #f59aa8
const EYE_GREEN = 6;   // Emerald cat eyes #43b581
const EYE_DARK = 7;    // Slit pupil / dark outline #1e1b24

const PALETTE = [
  [0, 0, 0, 0],
  [37, 34, 46, 255],
  [251, 248, 242, 255],
  [232, 140, 56, 255],
  [223, 215, 203, 255],
  [245, 154, 168, 255],
  [67, 181, 129, 255],
  [30, 27, 36, 255],
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

// Draw cute cat:
// Pointy triangular ears with pink inners, round head, whiskers, arched tail, loafing paws.
function cat({
  breathe = 0,
  lift = 0,
  lean = 0,
  step = null,
  blink = false,
  gaze = 0,
  paw = "down",      // "down", "groom", "stretch"
  tail = "up",       // "up", "tip", "curled", "twitch"
  pose = "stand",    // "stand", "loaf", "bellyUp", "yawn"
}) {
  const g = grid();

  // Pose: belly up (flip rolling)
  if (pose === "bellyUp") {
    // Curled body lying on back
    disc(g, 11.5, 14, 8.0, 5.5, FUR_MAIN);
    // Belly patch
    disc(g, 11.5, 13, 5.0, 3.5, FUR_SHADE);
    // Paws in air
    rect(g, 7, 10, 2, 3, FUR_MAIN);
    rect(g, 14, 10, 2, 3, FUR_MAIN);
    rect(g, 7, 10, 2, 1, NOSE_PINK);
    rect(g, 14, 10, 2, 1, NOSE_PINK);
    // Head upside down on right
    disc(g, 17, 15, 4.5, 4.5, FUR_MAIN);
    // Ears
    put(g, 19, 12, FUR_ORANGE);
    put(g, 20, 11, FUR_ORANGE);
    // Closed happy eyes ^ ^
    put(g, 16, 15, EYE_DARK);
    put(g, 18, 15, EYE_DARK);
    outline(g);
    return g;
  }

  // Pose: loaf (tucked paws)
  if (pose === "loaf") {
    const cy = 14 + breathe;
    const cx = 11.5 + lean;
    // Oval loaf body
    disc(g, cx, cy + 2, 8.5, 5.0, FUR_MAIN);
    disc(g, cx - 2, cy + 1, 4.5, 3.5, FUR_ORANGE); // orange back patch
    // Head resting low
    disc(g, cx + 3, cy - 2, 5.5, 4.8, FUR_MAIN);
    // Ears
    put(g, cx + 1, cy - 7, FUR_MAIN);
    put(g, cx + 2, cy - 6, NOSE_PINK);
    put(g, cx + 5, cy - 7, FUR_ORANGE);
    put(g, cx + 6, cy - 6, NOSE_PINK);
    // Sleeping/blinking eyes
    rect(g, cx + 3, cy - 2, 2, 1, EYE_DARK);
    rect(g, cx + 7, cy - 2, 2, 1, EYE_DARK);
    // Cute pink nose
    put(g, cx + 5, cy - 1, NOSE_PINK);
    // Curled tail around side
    rect(g, cx - 8, cy + 3, 3, 2, FUR_ORANGE);
    outline(g);
    return g;
  }

  const cy = 13 + breathe + lift;
  const cx = 11.5 + lean;

  // Tail
  if (tail === "up") {
    rect(g, cx - 7, cy - 3, 2, 5, FUR_ORANGE);
    put(g, cx - 6, cy - 4, FUR_ORANGE);
    put(g, cx - 5, cy - 5, FUR_ORANGE);
  } else if (tail === "twitch") {
    rect(g, cx - 7, cy - 1, 2, 4, FUR_ORANGE);
    put(g, cx - 5, cy - 2, FUR_ORANGE);
    put(g, cx - 4, cy - 2, FUR_ORANGE);
  } else {
    // low tail
    rect(g, cx - 7, cy + 2, 3, 2, FUR_ORANGE);
  }

  // Body
  disc(g, cx - 1, cy + 2, 6.5, 5.5, FUR_MAIN);
  // Ginger patch on back
  disc(g, cx - 3, cy + 1, 3.5, 3.0, FUR_ORANGE);

  // Head
  const headY = cy - 3;
  disc(g, cx + 3 + gaze, headY, 5.2, 4.8, FUR_MAIN);

  // Pointy Ears (triangle)
  const earX = cx + 3 + gaze;
  // Left ear
  put(g, earX - 2, headY - 5, FUR_MAIN);
  put(g, earX - 3, headY - 4, FUR_MAIN);
  put(g, earX - 2, headY - 4, NOSE_PINK);
  // Right ear (ginger patch)
  put(g, earX + 2, headY - 5, FUR_ORANGE);
  put(g, earX + 3, headY - 4, FUR_ORANGE);
  put(g, earX + 2, headY - 4, NOSE_PINK);

  // Four little paws. Both swing about the body's centre line so the cycle is symmetric, and the
  // off-side paw stays in shade whichever of the two is in front: seen from the side, a contact and
  // its opposite are otherwise the same pair of rectangles with their labels swapped, and the cycle
  // then has no way at all to show that it ever changed feet.
  const footY = 20;
  const paws = {
    0: { l: [-5, 0], r: [5, 0] },
    1: { l: [-1, -2], r: [1, 0] },
    2: { l: [5, 0], r: [-5, 0] },
    3: { l: [1, 0], r: [-1, -2] },
  }[step] || { l: [-4, 0], r: [2, 0] };
  const plant = (paw, isOffSide) => {
    const x = cx + paw[0], y = footY + paw[1];
    // A lifted paw is drawn inside the body, which is the same colour: without an outline of its own
    // the paw vanishes, and the pose reads as a cat with a leg missing.
    if (paw[1] !== 0) rect(g, x - 1, y - 1, 5, 4, OUTLINE);
    rect(g, x, y, 3, 2, isOffSide ? FUR_SHADE : FUR_MAIN);
  };
  plant(paws.l, true);
  plant(paws.r, false);

  // Eyes & Whiskers
  const eyeX = cx + 4 + gaze;
  const eyeY = headY - 1;
  if (blink || pose === "yawn") {
    rect(g, eyeX, eyeY + 1, 2, 1, EYE_DARK);
  } else {
    rect(g, eyeX, eyeY, 2, 3, EYE_GREEN);
    put(g, eyeX, eyeY + 1, EYE_DARK); // cat slit pupil
  }

  // Pink nose & mouth
  const noseX = cx + 6 + gaze;
  put(g, noseX, headY + 1, NOSE_PINK);
  if (pose === "yawn") {
    rect(g, noseX, headY + 2, 2, 2, NOSE_PINK);
  }

  // Whiskers (white / subtle)
  put(g, noseX + 2, headY + 1, FUR_SHADE);
  put(g, noseX + 2, headY + 2, FUR_SHADE);

  // Paw actions: grooming or waving
  if (paw === "groom") {
    disc(g, noseX, headY, 2.0, 2.0, FUR_MAIN);
  } else if (paw === "stretch") {
    rect(g, cx + 5, footY - 1, 3, 2, FUR_MAIN);
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

const CAT_WALK = [
  { lift: 0, lean: 1, step: 0, tail: "up" },
  { lift: -1, lean: 1, step: 1, tail: "twitch" },
  { lift: 0, lean: 1, step: 2, tail: "up" },
  { lift: -1, lean: 1, step: 3, tail: "tip" },
];

function frame(row, col) {
  switch (row) {
    case 0:
      if (col === 0) return cat({});
      if (col === 1) return cat({ breathe: 1 });
      if (col === 2) return cat({ blink: true });
      return grid();
    case 1:
      return col < CAT_WALK.length ? mirror(cat({ ...CAT_WALK[col], gaze: 1 })) : grid();
    case 2:
      return col < CAT_WALK.length ? cat({ ...CAT_WALK[col], gaze: 1 }) : grid();
    case 3:
      if (col === 0) return cat({ gaze: -1, tail: "twitch" });
      if (col === 1) return cat({ gaze: 1, paw: "groom" });
      if (col === 2) return cat({ paw: "groom" });
      if (col === 3) return cat({ paw: "stretch" });
      return cat({ pose: "yawn" });
    case 4:
      // Daze: yawn -> stretch -> loaf (tucked cat loaf nap)
      if (col === 0) return cat({ pose: "yawn", blink: true });
      if (col === 1) return cat({ paw: "stretch", tail: "twitch" });
      if (col === 2) return cat({ pose: "loaf", breathe: 0 });
      if (col === 3) return cat({ pose: "loaf", breathe: 1 });
      return grid();
    default:
      // Acrobatics: pounce crouch -> mid-air leap -> belly roll -> standing stretch
      if (col === 0) return cat({ lift: 2, tail: "twitch" });
      if (col === 1) return cat({ lift: -4, paw: "stretch", tail: "up" });
      if (col === 2) return cat({ pose: "bellyUp" });
      if (col === 3) return cat({ paw: "groom", blink: true });
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
const pngPath = path.join(ROOT, "Tinycast/Resources/CompanionAtlas-cat.generated.png");
fs.writeFileSync(pngPath, encodePNG());
console.log("Cat atlas written: " + ATLAS_W + "x" + ATLAS_H + "px -> " + pngPath);
