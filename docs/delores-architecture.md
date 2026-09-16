# Delores architecture and upstream sync

## Current implementation boundary

The first vertical slice is intentionally small:

```text
selection gesture
    → DeloresCoordinator
    → DeloresContextCoordinator
    → Context Island
    → AIChatCoordinator
    → the chat surface in the palette
```

The Context Island does not own AI, clipboard or Accessibility implementation. It presents the
actions; a press makes it grow in place and only then hands the captured selection over, so the
answer arrives on the surface that already has follow-up turns, model switching and a reasoning
channel. The action keeps its own instructions, model and guardrails on that trip: `QuickActionPrompt`
wraps the selection as material rather than instructions, and `QuickActionCoordinator.provider(for:)`
resolves the model the reader bound to the action together with the permissive guardrails a
transformation of their own text needs. The chat's default provider would judge that text as the
chat's own question and, on the on-device model, refuse it outright.

With AI off there is nowhere to converse, so the action falls through to the Quick Action route and
its own result surface — the behaviour a selection gesture had before the chat took the action over.

During this first slice, `quickActionsEnabled` is also the opt-in boundary for the Context Surface:
both capabilities need the same Accessibility permission. A separate Context Surface setting should
only be introduced when the product needs independent control, so the consent semantics do not split
prematurely.

## The two entry points

One capability set sits behind two summons, and each summon gets the Surface that fits the input
rather than one surface with swapped contents. `CONTEXT.md` already names the rule under
*Surface Arbitration* and *Action*; this is where it is carried out.

| Summon | Surface | What it is for |
| --- | --- | --- |
| ⌥Space, or any hotkey bound to the palette | Command Surface | Summoning, searching, starting a task the reader has in mind |
| A selection gesture | Context Surface | The minimum actions for text the reader has already selected |
| A Context action press | Command Surface, in the chat | Following the answer up: more turns, another model, a reasoning channel |

The Context Surface is a window of its own, not a compact mode of the palette. The palette's default
anchor is a fraction of the way down the visible frame (`paletteTopMarginFraction`), while a context
action belongs at the status bar; the two cannot share one window without moving where ⌥Space puts
the palette.

Arbitration is by the keyboard. Whichever Surface holds key answers the input, and each dismisses
itself on losing key (`PaletteWindowController.windowDidResignKey`,
`DeloresContextIslandController.windowDidResignKey`). Summoning the palette over the island drops the
island, and a fresh selection over the palette drops the palette — neither has to know the other
exists, and no single input closes both.

Escape follows the same rule, and is handled at the panel in both surfaces: the Command Surface in
`PalettePanel.sendEvent`, the Context Surface in `DeloresContextIslandPanel.sendEvent`. Escape closes
the surface that owns it and nothing else — a Quick Action still running behind the island's busy
state is not ours to cancel. While the card is opening it also cancels the press, because `onAction`
does not fire until the growth ends.

Two differences between the surfaces are recorded rather than resolved, because each direction is a
visual decision of its own:

- **Material.** The Context Surface draws with Liquid Glass (`Theme.frosted`), carried over from the
  toolbar it came from. The palette draws with `NSVisualEffectView(.hudWindow)` under a
  reader-configurable scrim. The two are on screen together only across the hand-off's fade.
- **Window level.** The island is at `.statusBar` so it sits over the menu bar it is anchored to; the
  palette is at `.floating`. Across the hand-off the outgoing island therefore draws over the
  incoming palette until its exit fade (`Theme.Duration.exit`) ends.

## Phase 1.5 boundary

`AppCore` now exposes only `DeloresCoordinator`. The coordinator owns the current Context Surface
implementation and is the place where future Surface arbitration will live.

Selection gesture admission uses a window snapshot policy: only visible windows that accept mouse
events block selection detection. HUDs and drop guides remain pass-through. Quick Action admission
returns `started`, `busy` or `disabled`; the Context Island closes only for `started` and shows an
explicit busy state otherwise.

### Ownership map

| Area | Owner | Sync posture |
| --- | --- | --- |
| Palette, AI providers, Keychain, TextInjector, window engine | Tinycast | Inherit upstream |
| Selection gesture and Context Surface | `Features/Delores/` | Delores-owned |
| Shared task snapshot | `Features/Delores/Model/InvocationContext.swift` | Stable seam |
| Quick Action entry with a captured selection, and the language it translates into | `QuickActionCoordinator` | One small integration seam; the AI-off fallback for a context action |
| Chat entry carrying a captured selection's instructions | `AIChatCoordinator`, `QuickActionPrompt` | One small integration seam |
| App lifecycle wiring | `AppCore`, `DeloresCoordinator` | One small integration seam |
| Own-surface event admission | `OwnSurfaceHitPolicy`, `OwnSurfaceHitTester` | Interactive windows only; pass-through overlays remain transparent |
| Quick Action admission | `QuickActionStartResult`, `QuickActionCoordinator` | Shared capability returns an explicit start result |
| Product identity and build metadata | `project.yml`, generated project, `Info.plist` | Delores-owned seam |
| Delores model gate | `.github/workflows/ci.yml`, `Scripts/run-delores-tests.sh` | Delores-owned seam |
| Local packaging and release gate | `Scripts/build-delores-dmg.sh`, `docs/delores-release.md`, release workflow guard | Delores-owned seam |
| Latest Huaci source and regression harness | `Integrations/HuaciGongju/`, `Scripts/run-huaci-integration-tests.sh` | Vendored integration; explicit adapter required |
| Quick Actions consent copy | `Features/QuickActions/Settings/QuickActionsSettingsView.swift` | Delores-owned seam |

Do not rename the upstream `Tinycast/` directory, upstream source files, or the generated project
structure merely to make the product name look uniform. That creates avoidable conflicts on every
upstream update.

## Upstream workflow

`upstream` points to the official Tinycast repository, `https://github.com/abue-ammar/tinycast`.
`integration/delores` is the product branch. The repository currently starts from Tinycast commit
`79d380aa96072ad54e1259448a316d9e34d2a73b`.

Before syncing:

```sh
git status --short
./Scripts/check-upstream-drift.sh
```

The working tree must be clean. Then use an isolated sync branch so conflict resolution is reviewable:

```sh
git fetch upstream
git switch integration/delores
git switch -c codex/upstream-sync-YYYYMMDD
git merge --no-ff upstream/main
```

Resolve conflicts in this order:

1. Keep upstream changes in Tinycast-owned files unless they conflict with a listed seam.
2. Reconcile only the Delores seams in `AppCore.swift`, `AIChatCoordinator.swift`,
   `QuickActionPrompt.swift`, `QuickActionCoordinator.swift`, `project.yml` and `Info.plist`.
3. Never copy a Delores file over an upstream file to resolve a conflict.
4. Regenerate the Xcode project with XcodeGen after `project.yml` is settled.
5. Run the upstream harnesses, the Delores model harness and the available Debug build checks.
6. Merge the verified sync branch back into `integration/delores`.

If an upstream change makes a seam unnecessary, delete the seam and update this document in the same
change. If an upstream feature overlaps a Delores feature, stop and record the ownership decision
before merging; do not silently keep two implementations.

The lifecycle and admission trade-off is recorded in
[ADR 0003](adr/0003-single-delores-lifecycle-seam.md).

## Huaci integration workflow

The latest local Huaci project is vendored at `Integrations/HuaciGongju/`. It is deliberately not
compiled into the Tinycast application target yet: Huaci's app delegate, LLM service, selection
monitor and settings store would otherwise become a second owner of existing Delores capabilities.
The source and its tests are still part of the Delores repository and run independently:

```sh
./Scripts/run-huaci-integration-tests.sh
```

The source boundary and update procedure are recorded in
[ADR 0002](adr/0002-vendor-huaci-latest-project.md). The next runtime step is an explicit adapter
for the Spatial Surface, with a Delores-owned consent setting and lifecycle; it is not a silent
activation of Huaci's global monitors.

## Verification after every sync

```sh
./Scripts/check-upstream-drift.sh
./Scripts/run-delores-tests.sh
./Scripts/run-tests.sh
./Scripts/run-huaci-integration-tests.sh
```

On a machine with Xcode 26 and SwiftLint installed, also run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug build
./Scripts/lint.sh
```

The current development bundle ID is not one of Tinycast's release channels, so the inherited updater
must not install Tinycast releases. A Delores release feed is a separate future decision.
