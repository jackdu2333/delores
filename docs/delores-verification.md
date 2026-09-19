# Delores verification status

This file has two jobs: naming the checks that have run and what they said, and keeping the reason any
check could not run. Delores was developed for a long time on a machine with Command Line Tools and no
Xcode, so part of the definition of done in [testing.md](testing.md) could not be executed there; that
gap is recorded below under **Historical**. Writing it down is the point of this file — an unrun check
that is silently assumed to pass is how a broken build reaches the default branch.

It is a record, not a task list. Update the results when a check runs again; do not delete the rows
that say why something could not run, or the next person re-derives them.

**Current status, read 2026-09-19 on source baseline `0fa06c93`: Xcode is not installed.** `xcode-select -p` says
`/Library/Developer/CommandLineTools`, there is no `Xcode.app` under `/Applications`, and
`xcodebuild -version` refuses with "requires Xcode". The build therefore cannot run here, and
`./Scripts/run-tests.sh` is **49 of 53** — all four failures are the missing SwiftUI macros. The
Delores harness, the upstream-drift regression and the purity grep all pass. SwiftLint 0.65.1 *is*
installed, and `./Scripts/lint.sh` is lint-clean, but only with the `TOOLCHAIN_DIR` override below;
the bare form still aborts. Everything below that describes Xcode 27 as installed and selected is a
historical reading, kept because it is what the `BUILD SUCCEEDED` and 73/73 rows were recorded
against — not a fact about this machine now. Check `xcode-select -p` before trusting any row.

## The machine this was recorded on

Recorded 2026-09-18 on the Delores development machine, at `f45beac`.

| Fact | How it was read | Value |
| --- | --- | --- |
| Active developer directory | `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Xcode installed | `xcodebuild -version` | Xcode 27.0, build `27A266a` |
| Swift | `swift --version` | 6.4 (swiftlang-6.4.0.34.1), target `arm64-apple-macosx27.0.0` |
| SDK | `xcrun --show-sdk-path --sdk macosx` | Xcode's `MacOSX27.0.sdk` |
| SwiftUI macro plugin | find `/Applications/Xcode.app` for `libSwiftUIMacros*` | present |
| SwiftLint | `swiftlint version` | **not installed** |

## Recorded results

### 2026-09-19, `597cad74` + Notes restored in the working tree — Xcode 27 machine

Read while bringing Notes back from upstream tag `v0.11.3-beta.98`. This is the other machine from the
top of this file: `xcode-select -p` is `/Applications/Xcode.app/Contents/Developer`, `xcodebuild
-version` answers Xcode 27.0, and the app target builds here. The reading is of the working tree, not
of a commit — the restore had not been committed when these numbers were taken.

| Command | Result |
| --- | --- |
| `xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug build` | **✓ BUILD SUCCEEDED**, 0 errors. One warning, and it is not from Swift: `appintentsmetadataprocessor` reports "Metadata extraction skipped, no AppIntents.framework dependency found" |
| `./Scripts/run-tests.sh` | **✓ 55 of 55** in 21s — the 53 this suite queued before, plus `notes-test` and `notes-editor-test` |
| `./Scripts/run-delores-tests.sh` | **✓ Delores context tests passed** |
| `./Scripts/check-upstream-drift.sh` | runs; merge-base `4735cab9`, **666 ahead / 608 not merged** — the pre-existing divergence, unchanged by this work |
| `node Scripts/check-settings-search.js` | **✓ passes** — the restored pane's rows are all in `SettingsSearchCatalog` |
| `./Scripts/format.sh --check` | **✗ 43 files need formatting.** All 43 were already dirty at `597cad74`, including the three this work edited (`AppSettings.swift`, `SettingsAnchor.swift`, `SettingsSearchCatalog.swift`); the added lines are themselves format-clean |
| `./Scripts/lint.sh` | **cannot run** — SwiftLint is not installed on this machine either |
| Notes accepted by eye in the running app | **not done.** The editor, the switcher, the formatting bar and the Markdown rendering are UI-layer work with no harness, and this machine cannot screenshot its own screen, so nothing about their appearance is claimed here |

### 2026-09-19, source baseline `0fa06c93` — Command Line Tools only

First read at `2addf5db`, re-run at `b0270ede` and again at `0fa06c93` after the localization,
product-identity, documentation, action-descriptor and website fixes; every number below is identical
in all three readings.

The suite shrank between this reading and the one below it. Notes, Emoji, Extensions, Snippets,
Calendar, Camera, Updates, Support and Custom Commands moved out of `Tests/` with their packs to
`Packs/LegacyFeatures/Tests/`, which this suite does not run, so it now queues 53 harnesses rather
than 73.

| Command | Result |
| --- | --- |
| `./Scripts/run-tests.sh` | **✓ 49 of 53.** 4 fail — `appearance-test`, `interface-size-test`, `palette-placement-test`, `callout-test` — every one "did not compile", all from the same missing `SwiftUIMacros.EntryMacro` |
| `./Scripts/run-delores-tests.sh` | **✓ passed** |
| `./Tests/upstream-drift-test.sh` | **✓ passed** |
| purity grep over `Tinycast/Features/*/Model/` | no output — the pure-layer boundary holds |
| `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools ./Scripts/lint.sh` | **✓ lint-clean** (warnings do not fail the job) |
| the app target build | **cannot run here** — no Xcode; this is the check CI exists to cover |
| `cd website && npm ci && npm run build` | **✓ 37 prerendered doc paths.** A new check here, and it had been failing: two preview components in `website/src/components/feature-previews.tsx` lost the `FeaturePreview` case that rendered them when the parked features left the site's navigation, and `noUnusedLocals` stopped the build at the type check. `0fa06c93` removed them |

`ext-icon-test`, `notes-editor-test` and `ext-test` are no longer among the failures because they
are no longer in this suite; their rows below belong to the pack they moved with.

### 2026-09-18, `f45beac`, with the sprite work in the working tree

| Command | Result |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug clean build` | **✓ BUILD SUCCEEDED.** Two warnings, both upstream — see below |
| `./Scripts/run-tests.sh` | **✓ 73/73** |
| `./Scripts/run-delores-tests.sh` | **passed** |
| purity grep over `Tinycast/Features/*/Model/` | no output — the pure-layer boundary holds |
| `./Scripts/lint.sh` | does not run: `swiftlint not found` |

### A clean build is the only build that means anything

An **incremental** build once reported `BUILD SUCCEEDED, no warnings` on this tree and was wrong on
both counts: it had recompiled only the files that had changed, so warnings carried by untouched files
never surfaced, and it skipped a file pair that no longer agreed — `DeloresWindowSnapCoordinator`
calling a `show(on:)` that `DeloresSpatialPanels` had meanwhile replaced with `showAtTopCenter` and
`showBesideBody`. The next full build failed on it.

Treat "it built" as a claim only when it comes from `clean build`. The two warnings a clean build does
report are both at `ClipboardView.swift:284` (`IsolatedConformances`, on `Content` and `Placeholder`)
— upstream code that no Delores change has touched.

### `ext-test` can fail on load alone

`ext-test` has since moved to `Packs/LegacyFeatures/Tests/` with the Extensions pack and this suite no
longer runs it. The note is kept because the same load-sensitivity appears in any harness that waits
on a timer.

`ext-test` asserts that timer callbacks scheduled by a second extension run still fire. It has failed
inside the full parallel run (`count=0`) and passed every time it was run on its own — three for three,
at 6.7–7.1 s each — and it also passed as part of a whole-suite run that had the machine to itself
(73/73 in 44 s). A whole-suite run compiles and runs 73 harnesses back to back, so under load the
timer simply does not get a slot.

`ext-test` shares no source file with `Features/Delores/`. Treat a lone `ext-test` failure in a full
run as noise, and re-run it alone before believing it.

## Historical: Command Line Tools only

Recorded 2026-09-17 at `e79171b`, before Xcode was installed. Kept because it explains why several
checks were unknown for months, and because the SwiftLint override below is still the one to use on a
CLT-only machine.

| Fact | Value then |
| --- | --- |
| Active developer directory | `/Library/Developer/CommandLineTools` |
| Xcode installed | none |
| `xcodebuild` | fails: "requires Xcode, but active developer directory … is a command line tools instance" |
| SDK | Command Line Tools `MacOSX.sdk`, 27.0 |
| SwiftUI macro plugin | not present |
| SwiftLint | 0.65.1 (present) |

The missing macro plugin was the cause of every compile failure then: `@Entry`, `@State` and
`@FocusState` are external macros whose implementation ships inside Xcode, not in Command Line Tools.

| Command | Result then |
| --- | --- |
| `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools ./Scripts/lint.sh` | **✓ lint-clean**, including the settings-anchor check |
| `./Scripts/lint.sh` (no override) | abort: SwiftLint's SourceKitten cannot load `sourcekitdInProc.framework` |
| `./Scripts/run-tests.sh` | **66 of 73 pass.** 7 fail: `appearance-test`, `interface-size-test`, `palette-placement-test`, `callout-test`, `ext-icon-test`, `notes-editor-test`, `ext-test` |
| `./Scripts/run-delores-tests.sh` | **passed** |
| node settings-anchor check | **passed** |
| `./Tests/upstream-drift-test.sh` | **passed** |
| `swiftc -swift-version 6 -typecheck …/Model/CompanionWander.swift` | **passed** |
| `swiftc -parse` on `DeloresCompanionCoordinator.swift`, `DeloresSpatialPanels.swift` | **passed** |

The seven failures all reported the same six errors — `external macro implementation type`
`'SwiftUIMacros.EntryMacro' could not be found` and its `StateMacro` sibling. Everything else they
reported was a downstream consequence of the macro not expanding.

They were **not** caused by any Delores change. Verified by extracting a pre-change commit into a
scratch directory and running two of them there:

```sh
git archive 062ef85 | tar -x -C "$(mktemp -d)/delores-pristine"
# in that copy:  ./Scripts/run-tests.sh appearance-test  → FAILED, identical 6 errors
#                ./Scripts/run-tests.sh ext-test         → FAILED, identical 6 errors
```

Note that `ext-test` appears in both the old failure list and the current one, for different reasons:
then it was the macro, now it is timer scheduling under load. Same name, unrelated cause.

### The SwiftLint override

SwiftLint locates its `sourcekitd` through `TOOLCHAIN_DIR`. Pointing that at Command Line
Tools was enough to run the whole script there:

```sh
TOOLCHAIN_DIR=/Library/Developer/CommandLineTools ./Scripts/lint.sh
```

`DYLD_FRAMEWORK_PATH` also starts a directly-invoked `swiftlint`, but not one started by
the script: macOS strips `DYLD_*` when exec'ing a platform binary, and the script's interpreter
is `/bin/bash`. A plain environment variable survives, which is why `TOOLCHAIN_DIR` is the
one to use.

**That part was the 2026-09-17 reading.** SwiftLint is installed again as of the 2026-09-18 status at
the top, so the `TOOLCHAIN_DIR` form runs and is lint-clean. The bare form still aborts:
`sourcekitdInProc.framework` ships inside Xcode, and there is none to load.

## What CI is for

The step list lives in [release.md](release.md#continuous-integration), which owns the description of
`.github/workflows/ci.yml`. What matters here is that CI is now the **only** place the app target is
compiled when this machine cannot: every harness compiles a subset of the shipped sources, so a green
suite says nothing about target membership, a missing resource, a macro that needs the app's flags or
a broken generated project. Adding a Swift file is the case to watch — `project.yml` and the
committed `Tinycast.xcodeproj` decide membership, so a new file that no harness names has to be
registered by running `xcodegen generate` and committing both.

## Manual acceptance on real displays

The Companion's wander is a pure model, asserted from a fixed seed in
`Tests/delores-context-test.swift` — but a unit test cannot see a window. Enable the companion in
`Companion & Windows` and watch it. What to look for:

| Situation | Expected |
| --- | --- |
| Watch it for about five minutes on a normal display | Long still stretches between trips; one constant speed per trip; it rides a screen edge and never cuts across the middle; more than one edge gets used; never still for longer than a minute |
| Drag it somewhere and let go | It stays where it landed and stands there a beat before setting off, rather than resuming the trip it was on |
| Rest the pointer on it, counting to one | The first 0.25s is still click-through, so a click there belongs to the app underneath; after that the click is the companion's, and the app you were typing in should not lose keyboard focus |
| Rest the pointer on it again, then right-click | A menu beside the body: the creatures with `Current` beside the one in use, then `Turn off the companion` · `Bring the menu bar back`. A press on a creature changes it at once; the last row takes the body away, and the Context bar's home goes back to the menu bar. A click anywhere else closes the menu, and it must never take the keyboard from the app you were in |
| Drag a window onto a pet standing on the bottom edge, with the Dock showing | The island appears immediately above the pet, and the pointer can climb onto it without the island vanishing on the way. Before this was fixed the island was placed a Dock's height above the body — 69pt of dead space on the 1920×1080 display here, and on a pet riding the Dock's own top the placement lifted it 24pt as well — so the drag left the target on the way up and the run was torn down under it |
| Change the display arrangement while it is walking | It stays on screen. It must not jump to the right-hand edge at mid-height, which is what a screen change used to do |
| Enter a full-screen space (video, slides) | The body hides while the frontmost window is full screen and comes back when it leaves. `39d99893` added the suppression this row used to record as an accepted gap |
| Idle cost, companion on and resting | No periodic work between trips; a rest schedules one wake rather than running a frame timer |

## Known gaps carried by the Companion

Product decisions waiting on a decision, not verification items. Listed so they are not mistaken for
regressions during the manual pass above. The full inventory of designed-but-unbuilt work, with
evidence per item, lives in [delores-backlog.md](delores-backlog.md); this section stays scoped to
what the manual pass above has to cover.

- The top edge is still inside the wander's range, so the companion can occupy the same strip as the
  Context Island and the snap island. The collision itself is now decided rather than open: both
  surfaces grow out of the pet beside its body, so the strip is shared by design, not contested.
- Pausing while the reader is typing is not implemented. The signal it would use,
  `CGEventSource.secondsSinceLastEventType`, needs no new permission.
- The companion has no accessibility label and no menu-bar entry, so a keyboard-only reader cannot
  reach it. Double-clicking it to reopen the last selection is also gated on Accessibility permission.
- Its reactions drop back to the idle pose on their own — `react` writes the idle frame first, so a
  one-shot animation returns to it without a timer — but the capture change is not signalled to the
  reader, and the no-selection double-click shows no bubble.
- The menu on the body is pointer-only by construction: it takes no key, so it leaves on a click away
  rather than Escape and has no keyboard navigation. A keyboard-only reader cannot open it at all,
  which is the same gap the accessibility label above is waiting on.
