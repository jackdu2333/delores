#!/usr/bin/env node
// Generate the Companion's sprite sheet:
//   Tinycast/Resources/CompanionAtlas.generated.png
//   Tinycast/Features/Delores/Model/CompanionAtlas.generated.swift
//
// Usage: node Scripts/gen-companion-atlas.js
// No input, no network: the output is byte-identical on every run, so a re-run is the check.
//
// The art is drawn here rather than imported, so the pipeline — atlas geometry, palette PNG, generated
// constants — can be proven before any artist is involved. Replacing `frame()` with a read of source
// frames changes nothing downstream: the geometry and the constants are all a consumer ever sees.
"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

// A cell is authored on a 24×24 grid and written at 2×, so one authored pixel is a 2×2 block: the
// sheet stays 1x art and the reader's eye still gets a chunky pixel rather than a hairline.
const CELL = 24;
const SCALE = 2;
const COLUMNS = 5;
const ROWS = 6;
const FRAME_PX = CELL * SCALE;

const TRANSPARENT = 0;
const OUTLINE = 1;
const BODY = 2;
const SHADE = 3;
const EYE = 4;
const MOUTH = 5;
const ACCENT = 6;

// The outline is dark and the body is light: the pet has no glass behind it any more, so on a pale
// wallpaper it is the outline alone that keeps it from disappearing.
const PALETTE = [
  [0, 0, 0, 0],
  [38, 35, 52, 255],
  [238, 235, 247, 255],
  [199, 193, 216, 255],
  [40, 38, 56, 255],
  [138, 131, 158, 255],
  [124, 199, 176, 255],
];

// MARK: - The grid

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

// One pixel of outline around everything drawn so far. Added last, so it wraps the finished pose
// rather than every shape inside it.
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

// MARK: - The poses

// `breathe` sinks the body and leaves the feet planted, which is what makes it read as breathing
// rather than as a hop; `lift` moves the whole thing, feet included, which is what a step needs.
// `lean` shifts it toward the direction of travel and `step` picks which foot is forward.
function creature({ breathe = 0, lift = 0, lean = 0, step = 0, blink = false, gaze = 0, mouth = "dot", arm = null }) {
  const g = grid();
  const cy = 13 + breathe + lift;
  const cx = 11.5 + lean;

  disc(g, cx - 5, cy - 5, 2, 2.6, BODY);
  disc(g, cx + 5, cy - 5, 2, 2.6, BODY);
  disc(g, cx, cy, 7.5, 6.8, BODY);

  // Feet: one forward, one back, and on `step` 0 they are level — the pose a trip both starts and
  // ends on, so a walk cycle reads as a cycle rather than as a lurch.
  const feet = [
    [step === 1 ? -1 : 0, step === 1 ? -1 : 0],
    [step === 3 ? -1 : 0, step === 3 ? -1 : 0],
  ];
  const footY = 19 + lift;
  rect(g, 8 + lean + feet[0][0], footY + feet[0][1], 3, 2, BODY);
  rect(g, 13 + lean + feet[1][0], footY + feet[1][1], 3, 2, BODY);

  // Light falls from above, so the underside is the shaded half.
  for (let y = 0; y < CELL; y++) {
    for (let x = 0; x < CELL; x++) {
      if (g[y * CELL + x] === BODY && y >= cy + 3) g[y * CELL + x] = SHADE;
    }
  }

  const eyeY = cy - 3;
  if (blink) {
    rect(g, 7 + lean + gaze, eyeY + 1, 3, 1, EYE);
    rect(g, 14 + lean + gaze, eyeY + 1, 3, 1, EYE);
  } else {
    rect(g, 7 + lean + gaze, eyeY, 2, 3, EYE);
    rect(g, 14 + lean + gaze, eyeY, 2, 3, EYE);
  }

  if (mouth === "open") {
    rect(g, 10 + lean, cy + 1, 4, 2, MOUTH);
    rect(g, 11 + lean, cy + 1, 2, 1, ACCENT);
  } else {
    rect(g, 11 + lean, cy + 1, 2, 1, MOUTH);
  }

  if (arm !== null) {
    disc(g, cx + 8, cy - 3 - arm, 1.8, 2.2, BODY);
    rect(g, 19 + lean, cy - 3 - arm, 2, 1, OUTLINE);
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

// The walk cycle: four frames, one up-and-down per cycle. Four and not five, because a cycle comes
// back to where it started — a fifth frame could only repeat the first, and a repeated frame reads as
// a limp rather than as a step. Written once and mirrored, so the two directions cannot drift apart.
//
// Every frame leans into the direction of travel by the same amount. A lean that came and went would
// snap the body back two pixels once per cycle, which the eye reads as a twitch.
const WALK = [
  { lift: 0, lean: 1, step: 0 },
  { lift: -1, lean: 1, step: 1 },
  { lift: 0, lean: 1, step: 2 },
  { lift: 1, lean: 1, step: 3 },
];

function frame(row, col) {
  switch (row) {
    // Breathing is two frames and a blink third. The rest of the row is padding and stays empty: a
    // padding cell that was drawn would look like a plausible frame to a caller reading past the
    // end, which is exactly the bug the check in `blit` below exists to catch.
    case 0:
      if (col === 0) return creature({});
      if (col === 1) return creature({ breathe: 1 });
      if (col === 2) return creature({ blink: true });
      return grid();
    // Walking looks where it is going, which is also what keeps the two directions apart on screen:
    // without it the mirror is only a shift of the feet.
    case 1:
      return col < WALK.length ? creature({ ...WALK[col], gaze: 1 }) : grid();
    case 2:
      return col < WALK.length ? mirror(creature({ ...WALK[col], gaze: 1 })) : grid();
    case 3:
      // Reaction: glance (2), wave (2), chat (1).
      if (col < 2) return creature({ gaze: col === 0 ? -1 : 1 });
      if (col < 4) return creature({ arm: col === 2 ? 0 : 2 });
      return creature({ mouth: "open" });
    case 4:
      // Daze / Restful: yawn, stretch, flop/nap.
      if (col === 0) return creature({ mouth: "open", blink: true });
      if (col === 1) return creature({ lift: -1, lean: 2, arm: 0 });
      if (col === 2) return creature({ lift: 2, blink: true });
      if (col === 3) return creature({ lift: 2, blink: true, breathe: 1 });
      return grid();
    default:
      // Acrobatics / Jump & Roll.
      if (col === 0) return creature({ lift: 2, step: 0 });
      if (col === 1) return creature({ lift: -3, lean: 1, step: 1 });
      if (col === 2) return creature({ lift: 1, lean: 1, mouth: "open" });
      if (col === 3) return creature({ lift: 0, lean: 0, blink: true });
      return grid();
  }
}

// MARK: - The sheet

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

// How many cells of each row carry a frame. The generated Swift states these too, from this one
// list, so the sheet and the constants cannot disagree about where a row ends.
const FRAMES_PER_ROW = [3, 4, 4, 5, 4, 4];

for (let row = 0; row < ROWS; row++) {
  for (let col = 0; col < COLUMNS; col++) {
    const cell = frame(row, col);
    const drawn = cell.some((v) => v !== TRANSPARENT);
    // A padding cell that gained a frame is invisible in the output and wrong at the call site, so
    // the generator refuses rather than shipping a sheet with a plausible frame hidden past the end.
    if (drawn !== col < FRAMES_PER_ROW[row]) {
      throw new Error(
        `cell ${col},${row} is ${drawn ? "drawn" : "empty"} but should be ${drawn ? "empty" : "drawn"}`
      );
    }
    blit(cell, col, row);
  }
}

// MARK: - PNG

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

// Indexed 8-bit PNG with a tRNS chunk: seven colours, so a palette is most of the saving, and the
// alpha it carries is what lets the pet sit on any wallpaper.
function encodePNG() {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(ATLAS_W, 0);
  ihdr.writeUInt32BE(ATLAS_H, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 3; // colour type: indexed
  const plte = Buffer.concat(PALETTE.map(([r, g, b]) => Buffer.from([r, g, b])));
  const trns = Buffer.from(PALETTE.map(([, , , a]) => a));

  const raw = Buffer.alloc(ATLAS_H * (ATLAS_W + 1));
  for (let y = 0; y < ATLAS_H; y++) {
    const at = y * (ATLAS_W + 1);
    raw[at] = 0; // filter: none — the sheet is tiny and deflate does the work
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

// MARK: - The constants

function swiftSource() {
  return `// Generated by Scripts/gen-companion-atlas.js — do not edit by hand.
import CoreGraphics

/// The Companion's sprite sheet: one decoded image, \`columns\` × \`rows\` cells of \`frameWidth\` each.
/// A frame is a rectangle into that one image, never an image of its own — which is why a pose
/// change costs a CGRect and not a decode.
enum CompanionAtlas {
    static let frameWidth: CGFloat = ${FRAME_PX}
    static let frameHeight: CGFloat = ${FRAME_PX}
    static let columns = ${COLUMNS}
    static let rows = ${ROWS}

    static var imageSize: CGSize { CGSize(width: frameWidth * CGFloat(columns), height: frameHeight * CGFloat(rows)) }

    enum Row: Int, CaseIterable, Sendable {
        case idle = 0
        case walkLeft = 1
        case walkRight = 2
        case reaction = 3
        case daze = 4
        case acrobatics = 5

        /// How many of the row's cells carry a frame. The rest are padding, and asking for one is
        /// a caller bug rather than something to clamp here.
        var frameCount: Int {
            switch self {
            case .idle: return ${FRAMES_PER_ROW[0]}
            case .walkLeft, .walkRight: return ${FRAMES_PER_ROW[1]}
            case .reaction: return ${FRAMES_PER_ROW[3]}
            case .daze: return ${FRAMES_PER_ROW[4]}
            case .acrobatics: return ${FRAMES_PER_ROW[5]}
            }
        }
    }

    /// The reaction row's poses, by the column each one starts at. The walk rows have no names for
    /// their cells: they are one cycle, and the cell *is* the position in it.
    enum Reaction: Int, CaseIterable, Sendable {
        case glance = 0
        case wave = 2
        case chat = 4

        var frameCount: Int { self == .chat ? 1 : 2 }
    }
}
`;
}

// MARK: - Write

const ROOT = path.resolve(__dirname, "..");
const pngPath = path.join(ROOT, "Tinycast/Resources/CompanionAtlas.generated.png");
const swiftPath = path.join(ROOT, "Tinycast/Features/Delores/Model/CompanionAtlas.generated.swift");

fs.writeFileSync(pngPath, encodePNG());
fs.writeFileSync(swiftPath, swiftSource());

const used = new Set(atlas).size;
console.log(
  `CompanionAtlas: ${ATLAS_W}×${ATLAS_H}px, ${COLUMNS}×${ROWS} cells of ${FRAME_PX}px, ${used} palette entries`
);
console.log(`  ${path.relative(ROOT, pngPath)}`);
console.log(`  ${path.relative(ROOT, swiftPath)}`);
