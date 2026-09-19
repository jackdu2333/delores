#!/usr/bin/env node
// The string catalogs and their call sites must agree.
//
// Three failures this catches that nothing else does. A key missing its zh-Hans value compiles and
// silently renders English on a Chinese Mac. A `L10n` key that is not in the catalog is the same
// failure one typo away, and it is invisible because `String(localized:)` returns its input. A
// catalog entry no source names is a reword that left its translation behind, so the next reader
// edits a value nothing reaches.
//
// It also keeps `L10n` out of `Features/*/Model/`. That layer has to stay language-free — the
// harnesses compile it without the catalog — and the AppKit/SwiftUI purity grep CI already runs does
// not cover it, because a Foundation-only localization call sidesteps that rule entirely while
// breaking the same boundary.
//
// Usage: node Scripts/check-localization.js   (run by ./Scripts/lint.sh)
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const APP = path.join(ROOT, "Tinycast");
const CATALOGS = ["Tinycast/Resources/Localizable.xcstrings", "Tinycast/Resources/InfoPlist.xcstrings"];

function swiftSources(dir, found = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) swiftSources(full, found);
    else if (entry.name.endsWith(".swift")) found.push(full);
  }
  return found;
}

const sources = swiftSources(APP).map((file) => ({
  file: path.relative(ROOT, file),
  text: fs.readFileSync(file, "utf8"),
}));
const allSource = sources.map((s) => s.text).join("\n");
const problems = [];

// 1. Every entry carries a usable zh-Hans value.
const catalogKeys = new Set();
for (const relative of CATALOGS) {
  const absolute = path.join(ROOT, relative);
  let catalog;
  try {
    catalog = JSON.parse(fs.readFileSync(absolute, "utf8"));
  } catch (error) {
    problems.push(relative + " — not valid JSON: " + error.message);
    continue;
  }
  for (const [key, entry] of Object.entries(catalog.strings || {})) {
    catalogKeys.add(key);
    const unit = entry.localizations && entry.localizations["zh-Hans"] &&
      entry.localizations["zh-Hans"].stringUnit;
    if (!unit || unit.state !== "translated" || !String(unit.value || "").trim()) {
      problems.push(relative + " — " + JSON.stringify(key) + " has no translated zh-Hans value");
    }
  }
}

// 2. Every literal key a call site names is in the catalog.
//    Only `L10n.string` and `L10n.format` are checked. Both take a literal by definition, so a
//    literal handed to one is a key. `L10n.text` takes a runtime String on purpose — that is the
//    entry point for a value that reaches a localizable position without being chrome, such as the
//    placeholder naming a command or a URL — and a literal there is not evidence of a catalog key.
const L10N = /L10n\.(?:string|format)\(\s*("(?:[^"\\]|\\.)*")/g;
const L10N_USE = /L10n\.(?:string|text|format)\s*\(/;
let literalUses = 0;
for (const { file, text } of sources) {
  for (const match of text.matchAll(L10N)) {
    literalUses += 1;
    let key;
    try {
      key = JSON.parse(match[1]);
    } catch {
      continue;
    }
    if (!catalogKeys.has(key)) {
      problems.push(file + " — L10n key not in the catalog: " + JSON.stringify(key));
    }
  }
}

// 3. No Model file may reach for the catalog.
for (const { file, text } of sources) {
  if (!/^Tinycast\/Features\/[^/]+\/Model\//.test(file)) continue;
  if (L10N_USE.test(text)) problems.push(file + " — a Model file must not use L10n");
}

// 4. A key nothing names is *usually* a translation nothing reaches, and it is reported rather than
//    failed on. Two shapes of legitimate key cannot be found by looking for their text: one the
//    extractor derived from an interpolation — `Text("\(name) · Ready")` is catalogued as
//    `"%@ · Ready"` — and one whose source spells an escape the parsed key no longer has, such as the
//    newline leading the truncation notice. Failing on those would fail on correct code, so the count
//    is printed and a reword to check by hand starts here.
const unreachable = [...catalogKeys].filter((key) => !allSource.includes(key));

if (problems.length) {
  console.error("✗ localization");
  for (const problem of problems) console.error("  " + problem);
  process.exit(1);
}
console.log(
  "  localization: " + literalUses + " literal L10n key(s), " + catalogKeys.size +
    " catalog entr(ies), all translated" +
    (unreachable.length ? "; unreachable: " + unreachable.length : ""));
