# Delores verification status

This file has two jobs: naming the checks that still have to run on a machine with Xcode, and keeping
the evidence for the ones that have already run. Delores is developed on a machine with Command Line
Tools and no Xcode, so part of the definition of done in [testing.md](testing.md) cannot be executed
there. Writing that gap down is the point of this file — an unrun check that is silently assumed to
pass is how a broken build reaches the default branch.

It is a record, not a task list. Update the results when a check finally runs; do not delete the rows
that say why something could not run here, or the next person re-derives them.

## The machine this was recorded on

Recorded 2026-09-17 on the Delores development machine, at `e79171b`.

| Fact | How it was read | Value |
| --- | --- | --- |
| Active developer directory | `xcode-select -p` | `/Library/Developer/CommandLineTools` |
| Xcode installed | `ls /Applications/Xcode*.app` | none |
| `xcodebuild` | `xcodebuild -version` | fails: "requires Xcode, but active developer directory … is a command line tools instance" |
| Swift | `swift --version` | 6.4 (swiftlang-6.4.0.34.1), target `arm64-apple-macosx27.0.0` |
| SDK | `xcrun --show-sdk-path --sdk macosx` | Command Line Tools `MacOSX.sdk`, 27.0 |
| SwiftLint | `swiftlint version` | 0.65.1 (present) |
| SwiftUI macro plugin | find `/Library/Developer` for `libSwiftUIMacros*` | not present |

The missing macro plugin is the single cause of every compile failure below: `@Entry`,
`@State` and `@FocusState` are external macros whose implementation ships inside Xcode,
not in Command Line Tools.

## Still to run, on a machine with Xcode

None of these has ever run for this repository on this machine. They are not known to fail — they are
unknown, which is the state this table exists to make visible.

| Check | Command | Why it cannot run here |
| --- | --- | --- |
| Debug build, zero new warnings | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug CODE_SIGNING_ALLOWED=NO build` | `xcodebuild` refuses to run without Xcode |
| Whole-app compile | the same build | `swiftc -typecheck` over the shipped sources aborts at `DesignSystem/InterfaceMetrics.swift:192` on `@Entry` |
| The seven SwiftUI-macro harnesses | `./Scripts/run-tests.sh` | needs `libSwiftUIMacros.dylib` |
| Lint exactly as documented | `./Scripts/lint.sh` | SwiftLint aborts before reading a file: `sourcekitdInProc.framework` is not where it expects under a CLT-only install. The override below is what does run here |
| Release build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Release CODE_SIGNING_ALLOWED=NO build` | same |

## Recorded results

2026-09-17, `e79171b`, Command Line Tools only.

| Command | Result |
| --- | --- |
| `TOOLCHAIN_DIR=/Library/Developer/CommandLineTools ./Scripts/lint.sh` | **✓ lint-clean**, including the settings-anchor check at the end of the script |
| `./Scripts/lint.sh` (no override) | abort: SwiftLint's SourceKitten cannot load `sourcekitdInProc.framework` |
| `./Scripts/run-tests.sh` | **66 of 73 pass.** 7 fail: `appearance-test`, `interface-size-test`, `palette-placement-test`, `callout-test`, `ext-icon-test`, `notes-editor-test`, `ext-test` |
| `./Scripts/run-delores-tests.sh` | **passed** |
| node settings-anchor check | **passed** |
| `./Tests/upstream-drift-test.sh` | **passed** |
| purity grep over `Tinycast/Features/*/Model/` | no output — the pure-layer boundary holds |
| `swiftc -swift-version 6 -typecheck Tinycast/Features/Delores/Model/CompanionWander.swift` | **passed** |
| `swiftc -parse` on `DeloresCompanionCoordinator.swift`, `DeloresSpatialPanels.swift` | **passed** |

The seven failures all report the same six errors — `external macro implementation type`
`'SwiftUIMacros.EntryMacro' could not be found` and its `StateMacro` sibling. Everything
else they report (`extensions must not contain stored properties`, `cannot assign to property: 'self' is immutable`) is a downstream consequence of the macro not expanding.

They are **not** caused by any Delores change. Verified by extracting a pre-change commit into a
scratch directory and running two of them there:

```sh
git archive 062ef85 | tar -x -C "$(mktemp -d)/delores-pristine"
# in that copy:  ./Scripts/run-tests.sh appearance-test  → FAILED, identical 6 errors
#                ./Scripts/run-tests.sh ext-test         → FAILED, identical 6 errors
```

The seven harnesses share no source file with `Features/Delores/`, and
`DesignSystem/InterfaceMetrics.swift` — untouched by this work — fails the same way when
typechecked on its own.

### The lint override

SwiftLint locates its `sourcekitd` through `TOOLCHAIN_DIR`. Pointing that at Command Line
Tools is enough to run the whole script here:

```sh
TOOLCHAIN_DIR=/Library/Developer/CommandLineTools ./Scripts/lint.sh
```

`DYLD_FRAMEWORK_PATH` also starts a directly-invoked `swiftlint`, but not one started by
the script: macOS strips `DYLD_*` when exec'ing a platform binary, and the script's interpreter
is `/bin/bash`. A plain environment variable survives, which is why `TOOLCHAIN_DIR` is the
one to use.

## Manual acceptance on real displays

The Companion's wander is a pure model, asserted from a fixed seed in
`Tests/delores-context-test.swift` — but a unit test cannot see a window. Enable the companion in
`Companion & Windows` and watch it. What to look for:

| Situation | Expected |
| --- | --- |
| Watch it for about five minutes on a normal display | Long still stretches between trips; one constant speed per trip; it rides a screen edge and never cuts across the middle; more than one edge gets used; never still for longer than a minute |
| Drag it somewhere and let go | It stays where it landed and stands there a beat before setting off, rather than resuming the trip it was on |
| Rest the pointer on it, counting to one | The first 0.25s is still click-through, so a click there belongs to the app underneath; after that the click is the companion's, and the app you were typing in should not lose keyboard focus |
| Change the display arrangement while it is walking | It stays on screen. It must not jump to the right-hand edge at mid-height, which is what a screen change used to do |
| Enter a full-screen space (video, slides) | Record what actually happens. Delores has no full-screen suppression yet, so the companion is expected to still be visible; that is an accepted gap, not a pass |
| Idle cost, companion on and resting | No periodic work between trips; a rest schedules one wake rather than running a frame timer |

## Known gaps carried by the Companion

Product decisions waiting on a decision, not verification items. Listed so they are not mistaken for
regressions during the manual pass above.

- The top edge is still inside the wander's range, so the companion can occupy the same strip as the
  Context Island and the snap island.
- Pausing while the reader is typing is not implemented. The signal it would use,
  `CGEventSource.secondsSinceLastEventType`, needs no new permission.
- The companion has no accessibility label and no menu-bar entry, so a keyboard-only reader cannot
  reach it. Double-clicking it to reopen the last selection is also gated on Accessibility permission.
- Its expressions do not fall back to idle, the capture change is not signalled to the reader, and the
  no-selection double-click shows no bubble.

