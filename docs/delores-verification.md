# Delores verification status

This file has two jobs: naming the checks that have run and what they said, and keeping the reason any
check could not run. Delores was developed for a long time on a machine with Command Line Tools and no
Xcode, so part of the definition of done in [testing.md](testing.md) could not be executed there; that
gap is recorded below under **Historical**. Writing it down is the point of this file — an unrun check
that is silently assumed to pass is how a broken build reaches the default branch.

It is a record, not a task list. Update the results when a check runs again; do not delete the rows
that say why something could not run, or the next person re-derives them.

**Current status, read 2026-09-22 on source baseline `b73a94ab`: Xcode is not installed.** `xcode-select -p` says
`/Library/Developer/CommandLineTools`, there is no `Xcode.app` under `/Applications`, and
`xcodebuild -version` refuses with "requires Xcode". The build therefore cannot run here, and
`./Scripts/run-tests.sh` is **48 of 53** — all five failures come from the missing SwiftUI macro
plugin (`SwiftUIMacros.EntryMacro`). The Delores context harness, the new geometry harness (20/20),
the upstream-drift regression, the product-boundary gate, the vendored Huaci harness and the purity
grep pass. SwiftLint 0.65.1 *is* installed, and lint is clean when the gate supplies the
`TOOLCHAIN_DIR` override below; the bare form still aborts. Everything below that describes Xcode 27 as installed and selected is a
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

### 2026-09-19, the subprocess helper hardened — `4ab90ece`

Came out of a review of `597cad74`, the commit that adopted `ToolRunner` from the parked Updates pack
for Apple Shortcuts. The review read the baseline as `run-tests.sh` **49 of 53** with four harnesses
failing on missing SwiftUI macros — that is the Command Line Tools machine described at the top of this
file, not this one. The four pass here, and this section is the live count.

Both hangs it named were reproduced against the pre-fix helper before anything was changed, and one of
them turned out not to be the review's:

| Command | Result |
| --- | --- |
| The old helper, a tool that traps SIGTERM, `timeout: 1` | **✗ never returned.** Read 6 s later, still waiting — the timeout sent the signal and then waited on an exit that was never coming |
| The old helper, `sh -c "sleep 30 & echo done"`, **no timeout at all** | **✗ never returned either.** The second path, and the review did not have it: the drain's `readToEnd()` waits for every writer to close, including a child the tool left behind |
| `sh -c "sleep 2 & echo done"`, exit versus end of file | child exited at **0.076 s**, the pipe reached end of file at **2.088 s** — the gap a descendant holds open, and the measurement that explains the row above |
| `xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug build` | **✓ BUILD SUCCEEDED**, 0 errors, 0 Swift warnings |
| `./Scripts/run-tests.sh` | **✓ 56 of 56** in 22s — the 55 of the sections above plus `tool-runner-test` |
| `./Scripts/run-tests.sh tool-runner-test` | **✓ 33 assertions**, 11 s. Written against the fixed helper but exercised against the old one first: the two reproduction cases are permanent rows in it, so a regression re-hangs the suite rather than passing quietly |
| `appearance-test`, `interface-size-test`, `palette-placement-test`, `callout-test` | **✓ all four pass here**, 0.3 s each. The review reported these as CLT/SwiftUI-macro environment failures; on this machine they are green, so nothing about them was inherited from `597cad74` |
| `./Scripts/run-delores-tests.sh` | **✓ Delores context tests passed** |
| `node Scripts/check-settings-search.js` | **✓ exit 0** |
| `node Scripts/check-localization.js` | **✓ 357 keys, 538 entries, all translated, 31 unreachable** — untouched by this work |
| `./Scripts/format.sh --check` | **✗ 43 files**, every one already dirty before this work. The new harness was flagged on first write and **was formatted**; the three files this work edits are not among the 43 |
| `./Scripts/lint.sh` | **cannot run** — SwiftLint is not installed on this machine |
| `./Scripts/check-upstream-drift.sh` | unchanged from the row above — nothing here edits an upstream-owned file's content. `Platform/ToolRunner.swift` is not an upstream path |
| A genuinely wedged `/usr/bin/shortcuts` in the running app | **not done.** The hang is proven at the helper, with the coordinator's `refreshTask` as the read reason it mattered; producing a real wedged `shortcuts` tool is not something this machine can arrange |

The review's fourth finding, two physical copies of `ToolRunner.swift`, is answered in
`Packs/LegacyFeatures/README.md` and [delores-architecture.md](delores-architecture.md) rather than by
the `diff` check it proposed. The two copies are **meant** to differ now — the pack keeps upstream's
original byte for byte so it stays diffable, and the active file has moved on — so a check asserting
they match would assert the wrong thing. The invariant worth protecting is the opposite one, and it is
written where a restore would read it.

### 2026-09-19, the hardened build installed — `82b9787f`

Pushed, built and put where the Release channel lives.

| Command | Result |
| --- | --- |
| `./Scripts/build-delores-dmg.sh` | **✓ BUILD SUCCEEDED**, `verify-signature.sh` green, `build/Delores-0.2.0.dmg` (9.2 MB) |
| `PlistBuddy` on the app inside it | `CFBundleShortVersionString` **0.2.0**, `CFBundleVersion` **685** — equal to `git rev-list --count HEAD` at `82b9787f`, which is the number naming the source it was built from |
| `lipo -archs` on that binary | **x86_64 arm64** — the local Release lane is universal, unlike the CI artifact |
| `codesign -dv` after installing | `Identifier=com.jackdu.delores`, `flags=0x10000(runtime)`, `Authority=HuaciGongju CodeSign` |
| `/Applications/Delores.app`, before and after | **0.1.0 / 1 → 0.2.0 / 685.** The old bundle went to the Trash and the new one in with `ditto`, never `cp -R` |
| The designated requirement, old bundle versus new | **byte-identical** — `identifier "com.jackdu.delores" and certificate root = H"86a60938…"`. That is why the accessibility grant survives a version change, and it was checked against the old bundle in the Trash rather than assumed from the certificate name |
| `spctl -a -t exec` | **rejected**, expected: the local identity is not notarized. The app carries no quarantine attribute, so it launches |
| `.github/workflows/ci.yml` on the pushed commit | **✗ failure, and no step ran.** Run `35431737378` failed in **7 s** with an empty step list — `test: failure` and nothing under it. `--log-failed` answers `log not found`. The check-run annotation is the only place the reason appears: *"The job was not started because recent account payments have failed or your spending limit needs to be increased."* The repo is **private**, so Actions minutes are metered. **This commit is therefore not independently verified by CI**, which is the fact worth keeping — the run at `07:26Z` was green in 1m53s and this one at `08:20Z` never started, so what changed is the account, not the code |

The Debug readings in the section above are unaffected: this lane builds Release, and the two share
every source file. **The installed build number was 685 while `git rev-list --count HEAD` was one
higher** at the moment this was written, because recording it pushed the count — the property working
rather than drifting, and why `delores-versioning.md` refuses to write a count down. That is also why
this paragraph gives no current count, having been burned once: `/Applications/Delores.app` reports
**0.2.0 / 688**, which is `git rev-list --count HEAD` at `c6988efa`, the commit it was built from —
while the count itself has moved on with every commit since, including the ones that wrote this
sentence. Committing moves the count and installing moves the app, so the two agree only in the
instant after an install and drift by however many commits land after it, which makes "one behind" a
coincidence rather than a rule.

**The CI failure needs a cutoff, not a row per push.** The last run that executed anything is
`d18d143d` at `07:26Z`; every push after it got no runner at all — this one, and `d189a441` and
`c6988efa` at `11:43Z`. So on those commits the CI column reads *unverified*, which is neither red for
a reason nor green, and enumerating more pushes would not add information: the annotation names the
account's billing, so nothing in this repository changes it. There is nothing to re-run and nothing to
fix in the code.

What must not be lost in that: **CI is the second executor of this file's gates, not the packaging
channel.** The DMG above was built, signed, and installed while CI was down, so a red CI cell does not
mean a blocked release. It means the commit has one fewer independent reader than a green one, which is
the thing worth writing down — `delores-versioning.md` calls the Build the shortest path from a user's
sentence to source, and a Build with no CI behind it is a path with a gap in the middle.

### 2026-09-19, the Build derived at build time — `e43b62e9`

Added because a document described a rule the code did not implement. `delores-versioning.md` said the
Build was `git rev-list --count HEAD`; neither lane that produces an installable build passed
`CURRENT_PROJECT_VERSION` at all, so both shipped `project.yml`'s hand-written `2` — one number for
every commit, which is the thing the number exists not to be. Read on the Xcode machine the section
below describes, not the Command Line Tools one at the top of this file.

| Command | Result |
| --- | --- |
| `./Scripts/build-delores-dmg.sh` | **✓ BUILD SUCCEEDED**, `verify-signature.sh` green, `build/Delores-0.2.0.dmg` (9.6 MB) written |
| `PlistBuddy` on the `Delores.app` from that DMG | `CFBundleShortVersionString` **0.2.0**, `CFBundleVersion` **681** — equal to `git rev-list --count HEAD` at `d18d143d`, the tree it was built from. `e43b62e9` itself moved the count to 682, which is the property working rather than drifting: the number names source, so committing changes it. The script's own assertion passed for that reason and not by never being reached |
| `codesign -dv --verbose=2` on the same app | `Identifier=com.jackdu.delores`, `flags=0x10000(runtime)`, `Authority=HuaciGongju CodeSign` — the Release channel's bundle ID and the local identity, which is what `verify-signature.sh` asserts |
| `xcodebuild -showBuildSettings … CURRENT_PROJECT_VERSION=9999` | resolves to `CURRENT_PROJECT_VERSION = 9999` while `MARKETING_VERSION` stays `0.2.0` — the override reaches the setting, which is the mechanism both lanes now depend on |
| `bash -n Scripts/build-delores-dmg.sh` | **✓** parses |
| `build-app.yml` parsed as YAML | **✓ 8 steps**; the checkout carries `fetch-depth: 0`, and the build step carries both the shallow-history guard and the post-build assertion |
| `build-app.yml` executed | **not done.** The workflow is `workflow_dispatch` only, so that half of the change is read rather than run. It asserts the same property the local script does, which is why running it is not load-bearing for the claim above |
| A Debug build | **unchanged, and deliberately not fixed.** A build that skips both lanes — Xcode's Run button, or a hand-run `xcodebuild` — still reports `project.yml`'s `2`. That value is now documented as a fallback rather than a version, which is what the `64078751` row below observed without yet having the vocabulary for it |

### 2026-09-19, Notes restored — `ebdaeaec` and `64078751`

Read while bringing Notes back from upstream tag `v0.11.3-beta.98`. This is the other machine from the
top of this file: `xcode-select -p` is `/Applications/Xcode.app/Contents/Developer`, `xcodebuild
-version` answers Xcode 27.0, and the app target builds here.

Two commits, one event, because a restored feature is not shipped until the documents that describe it
agree. `ebdaeaec` is the restore; `64078751` is the release-doc and version pass that followed it. The
restore was first read against the working tree before it was committed, and the numbers are identical
at the commit, so the first table below is `ebdaeaec`'s.

`ebdaeaec`:

| Command | Result |
| --- | --- |
| `xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug build` | **✓ BUILD SUCCEEDED**, 0 errors, 0 Swift warnings. The only line the grep keeps is the toolchain's own `appintentsmetadataprocessor` notice, "Metadata extraction skipped, no AppIntents.framework dependency found" |
| `./Scripts/run-tests.sh` | **✓ 55 of 55** in 21s — the 53 this suite queued before, plus `notes-test` and `notes-editor-test`. `notes-editor-performance` is registered `index`-only and is not in the set |
| `./Scripts/run-delores-tests.sh` | **✓ Delores context tests passed** |
| `./Scripts/check-upstream-drift.sh` | runs; merge-base `4735cab9`, **666 ahead / 608 not merged** — the pre-existing divergence, unchanged by this work |
| `node Scripts/check-settings-search.js` | **✓ passes** — the restored pane's rows are all in `SettingsSearchCatalog` |
| `./Scripts/format.sh --check` | **✗ 43 files need formatting.** All 43 were already dirty at `597cad74`, including the three this work edited (`AppSettings.swift`, `SettingsAnchor.swift`, `SettingsSearchCatalog.swift`); the added lines are themselves format-clean |
| `./Scripts/lint.sh` | **cannot run** — SwiftLint is not installed on this machine either |
| Notes accepted by eye in the running app | **not done.** The editor, the switcher, the formatting bar and the Markdown rendering are UI-layer work with no harness, and this machine cannot screenshot its own screen, so nothing about their appearance is claimed here |

`64078751` (`project.yml` 0.1.0/1 → **0.2.0/2**, the internal docs, and the website pages):

| Command | Result |
| --- | --- |
| `xcodegen generate` | **✓ 4 lines change in `project.pbxproj`** — `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, in both configurations and nothing else, so the regeneration is still deterministic |
| `xcodebuild … -configuration Debug build` | **✓ BUILD SUCCEEDED**, 0 errors, 0 Swift warnings |
| `PlistBuddy` on the built `Delores Dev.app` | `CFBundleShortVersionString` **0.2.0**, `CFBundleVersion` **2** — the version reaches the product, not just the project file |
| `./Scripts/run-tests.sh` | **✓ 55 of 55** |
| `cd website && npm ci && npm run build` | **✓ 79 static pages, 37 prerendered doc paths.** The doc count is **unchanged**, not incremented: the Notes page file already existed as a parked stub, so putting it back into `features/meta.json` returns it to the sidebar without adding a route. `noUnusedLocals` passes, so the `notes` icon reference in `features.ts` type-checks against `feature-icons.ts` |
| The restored page in the exported HTML, not just in the build | **✓ `out/docs/features/notes/index.html` exists**, the sidebar on that page links to `/tinycast/docs/features/notes/`, the site home carries the "Floating notes" card, and `out/docs/reference/settings/index.html` contains "Enable Notes" |
| Website copy read against the tag | `website/content/docs/features/notes.md` is byte-identical to `v0.11.3-beta.98`'s page except the removed Snippets sentence, verified by `diff` |
| `npx prettier --check` on the ten edited website files | **✗ 3 fail — `launcher/commands.md`, `reference/backup.md`, `reference/settings.md`.** All three fail on their **`HEAD` version too**, so the style was already there and this work neither caused nor fixed it; the website workflow builds but never runs `prettier`, which is why it survives. Not reformatted: `prettier --write` on those files would re-pad rows this task never touched |
| Anything about how the site *looks* | **not done.** The export proves the page prerenders and the nav entry resolves; nobody has looked at the rendered page |
| `.github/workflows/ci.yml` on the pushed commit | **✓ success**, run `35429189803` at `e1c32012` |
| `.github/workflows/website.yml` on the pushed commit | **✗ failure, and it is not this work's.** Run `35429189821` at `e1c32012`: the **`build` job succeeds** — checkout, `npm ci`, build, `upload-pages-artifact` all green — and the **`deploy` job fails** at `actions/deploy-pages@v5` with `Failed to create deployment (status: 404) … Ensure GitHub Pages has been enabled`. GitHub Pages is not enabled on `jackdu2333/delores`, so the site builds and cannot publish. Enabling Pages is a repository setting, and this file records the reason rather than acting on it |
| The three website runs before it | `35417991741` and `35309627215` failed the same way — `build` green, `deploy` 404 at the same step. **`35413710422` did not**: its `build` job failed at **Install & build**, so `deploy` was skipped. That is the park commit `2addf5db`, where dropping the parked features from the site left `feature-previews.tsx` with components nothing rendered and `noUnusedLocals` stopped the type check; `0fa06c93` removed them and the lane went back to failing only at the deploy step. Worth keeping distinct: a red run on this workflow is usually the missing Pages setting, but it can be a real build break, and only the job name tells them apart |

### 2026-09-19, source baseline `0fa06c93` — Command Line Tools only

First read at `2addf5db`, re-run at `b0270ede` and again at `0fa06c93` after the localization,
product-identity, documentation, action-descriptor and website fixes; every number below is identical
in all three readings.

The suite shrank between this reading and the one below it. Notes, Emoji, Extensions, Snippets,
Calendar, Camera, Updates, Support and Custom Commands moved out of `Tests/` with their packs to
`Packs/LegacyFeatures/Tests/`, which this suite does not run, so it now queues 53 harnesses rather
than 73. **Notes has since been restored, and the subprocess helper has gained a harness of its own,
so the live count is 56** — this paragraph describes the suite as it stood at `0fa06c93`, and the
sections above it carry the current number.

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
`Tests/delores-context-test.swift` — but a unit test cannot see a window. Select the Delores desktop
pet mode in `Companion & Windows` and watch it. What to look for:

| Situation | Expected |
| --- | --- |
| Watch it for about five minutes on a normal display | Long still stretches between trips; one constant speed per trip; it rides a screen edge and never cuts across the middle; more than one edge gets used; never still for longer than a minute |
| Drag it somewhere and let go | It stays where it landed and stands there a beat before setting off, rather than resuming the trip it was on |
| Rest the pointer on it, counting to one | The first 0.25s is still click-through, so a click there belongs to the app underneath; after that the click is the companion's, and the app you were typing in should not lose keyboard focus |
| Rest the pointer on it again, then right-click | A menu beside the body: the creatures with `Current` beside the one in use, then `Turn off the companion` · `Bring the menu bar back`. A press on a creature changes it at once; the last row takes the body away, and the Context bar's home goes back to the menu bar. A click anywhere else closes the menu, and it must never take the keyboard from the app you were in |
| Select text while the Companion stands on a vertical screen edge, then press Explain or Summarize | The working card opens beside the body, the full action strip remains visible (including Search and the exit controls), and Stop is reachable without a clipped bottom row |
| Drag a window onto a pet standing on the bottom edge, with the Dock showing | The island appears immediately above the pet, and the pointer can climb onto it without the island vanishing on the way. Before this was fixed the island was placed a Dock's height above the body — 69pt of dead space on the 1920×1080 display here, and on a pet riding the Dock's own top the placement lifted it 24pt as well — so the drag left the target on the way up and the run was torn down under it |
| Change the display arrangement while it is walking | It stays on screen. It must not jump to the right-hand edge at mid-height, which is what a screen change used to do |
| Enter a full-screen space (video, slides) | The body hides while the frontmost window is full screen and comes back when it leaves. `39d99893` added the suppression this row used to record as an accepted gap |
| Type in a document while the body is walking | It stands still while the keys are going, and sets off again about two seconds after they stop, resuming the trip it was frozen in. `CGEventSource.secondsSinceLastEventType` is the signal — state, not events, so no permission the Companion did not already run under |
| Select Codex pet mode while the Codex pet is hidden, or while its loopback overlay bridge is unavailable | The native Delores pet stays off; selection and window-snap fall back to the menu bar/top-centre affordance, with no Codex main window treated as a pet |
| Show the Codex pet, then select text on either display or drag a window onto it | The Context toolbar grows beside the Codex pet, including when the selection is on the other display; the top-centre snap trigger is suppressed while the Codex pet is visible, and the existing Snap Island grows beside it. A drag that starts on the Codex pet is ignored by Delores. If the pet cannot be uniquely resolved, the safe fallback above wins |
| Focus the Companion with VoiceOver and press it | The sprite body exposes a localized button label and its press action reopens the last selection, or shows the existing empty-selection reaction |
| Idle cost, companion on and resting | No periodic work between trips; a rest schedules one wake rather than running a frame timer |

## Known gaps carried by the Companion

Product decisions waiting on a decision, not verification items. Listed so they are not mistaken for
regressions during the manual pass above. The full inventory of designed-but-unbuilt work, with
evidence per item, lives in [delores-backlog.md](delores-backlog.md); this section stays scoped to
what the manual pass above has to cover.

- The top edge is still inside the wander's range, so the companion can occupy the same strip as the
  Context Island and the snap island. The collision itself is now decided rather than open: both
  surfaces grow out of the pet beside its body, so the strip is shared by design, not contested.
- The Companion now exposes a localized accessibility button label and press action. It still has no
  menu-bar entry; that remains a product decision, and the body menu itself remains pointer-only.
- Its reactions drop back to the idle pose on their own — `react` writes the idle frame first, so a
  one-shot animation returns to it without a timer — but the capture change is not signalled to the
  reader, and the no-selection double-click shows no bubble.
- The menu on the body is pointer-only by construction: it takes no key, so it leaves on a click away
  rather than Escape and has no keyboard navigation. The body itself is now reachable as a button;
  opening the settings menu remains pointer-only pending a product decision about a menu-bar entry.
