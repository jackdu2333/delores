# Delores verification status

This file has two jobs: naming the checks that have run and what they said, and keeping the reason any
check could not run. Delores was developed for a long time on a machine with Command Line Tools and no
Xcode, so part of the definition of done in [testing.md](testing.md) could not be executed there; that
gap is recorded below under **Historical**. Writing it down is the point of this file — an unrun check
that is silently assumed to pass is how a broken build reaches the default branch.

It is a record, not a task list. Update the results when a check runs again; do not delete the rows
that say why something could not run, or the next person re-derives them.

**The machine changed on 2026-09-17**: Xcode 27.0 is installed and selected, so the build and the
SwiftUI-macro harnesses now run here. SwiftLint is *not* currently installed, so `lint.sh` is the one
check that cannot.

## The machine this was recorded on

Recorded 2026-09-17 on the Delores development machine, at `39f5d13`.

| Fact | How it was read | Value |
| --- | --- | --- |
| Active developer directory | `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| Xcode installed | `xcodebuild -version` | Xcode 27.0, build `27A266a` |
| Swift | `swift --version` | 6.4 (swiftlang-6.4.0.34.1), target `arm64-apple-macosx27.0.0` |
| SDK | `xcrun --show-sdk-path --sdk macosx` | Xcode's `MacOSX27.0.sdk` |
| SwiftUI macro plugin | find `/Applications/Xcode.app` for `libSwiftUIMacros*` | present |
| SwiftLint | `swiftlint version` | **not installed** |

## Recorded results

2026-09-17, `39f5d13`, with the Companion Shell work in the working tree.

| Command | Result |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug build` | **✓ BUILD SUCCEEDED, no warnings** |
| `./Scripts/run-tests.sh` | **172 passed, 1 failed.** The one failure is `ext-test`, "the second run's timers still fire" |
| `./Scripts/run-tests.sh ext-test` (three times, alone) | **✓ passed 3/3** — see below |
| `./Scripts/run-delores-tests.sh` | **passed** |
| purity grep over `Tinycast/Features/*/Model/` | no output — the pure-layer boundary holds |
| `./Scripts/lint.sh` | does not run: `swiftlint not found` |

### The one `run-tests.sh` failure is load-dependent, not a regression

`ext-test` asserts that timer callbacks scheduled by a second extension run still fire. It fails only
inside the full parallel run (`count=0`) and passes every time it is run on its own — three for three,
at 6.7–7.1 s each, with the machine otherwise idle. A whole-suite run compiles and runs 73 harnesses
in 81 s, so the timer simply does not get a slot.

`ext-test` shares no source file with `Features/Delores/`, so it is not reachable from the Companion
Shell work. Treat a lone `ext-test` failure in a full run as noise, and re-run it alone before
believing it.

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

SwiftLint is not installed on this machine as of 2026-09-17, so neither form currently runs.
Reinstall it with `brew install swiftlint` before relying on the lint half of the definition of done.

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
- Its expressions do not fall back to idle, the capture change is not signalled to the reader, and the
  no-selection double-click shows no bubble.
