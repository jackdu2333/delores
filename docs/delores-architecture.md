# Delores architecture and upstream sync

## Current implementation boundary

The first vertical slice is intentionally small:

```text
selection gesture
    → DeloresCoordinator
    → DeloresContextCoordinator
    → Context Island
    ├─ native Quick Action → Quick Action result surface
    └─ explicit Ask AI → AIChatCoordinator → chat surface in the palette
```

The Context Island does not own AI, clipboard or Accessibility implementation. It presents the
minimum actions for the captured selection. The four built-in actions remain native Quick Actions:
Translate keeps Apple's Translation framework, Summarize keeps its preview, and Rewrite/Fix Grammar
keep their diff/replace semantics. Their result arrives on the existing Quick Action result surface,
regardless of whether AI Chat is enabled. This preserves one Action with one meaning across entries.

Chat is an explicit escalation, not the hidden destination of every Context Action. The `Ask AI`
action is the only Context button that grows the island and hands the captured selection to
`AIChatCoordinator`; it is the entry for follow-up turns, model switching and reasoning. The existing
handoff infrastructure still carries per-turn instructions, provider and guardrails for future
selection-aware Chat entries, but ordinary Context Actions do not pass through it.

With AI off, `Ask AI` is omitted from the Context Surface because there is nowhere to converse. The
four native actions remain available through the same Quick Action route.

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
| A native Context action press | Quick Action result surface | Execute one transformation with its native preview/replace/diff semantics |
| An explicit `Ask AI` press | Command Surface, in the chat | Escalate the captured selection for more turns, another model, or reasoning |

The Context Surface is a window of its own, not a compact mode of the palette. The palette's default
anchor is a fraction of the way down the visible frame (`paletteTopMarginFraction`), while a context
action belongs at the status bar; the two cannot share one window without moving where ⌥Space puts
the palette.

Arbitration is by the keyboard. Whichever Surface holds key answers the input, and each dismisses
itself on losing key (`PaletteWindowController.windowDidResignKey`,
`DeloresContextIslandController.windowDidResignKey`). Summoning the palette over the island drops the
island, and a fresh selection over the palette drops the palette — neither has to know the other
exists, and no single input closes both.

The one exception is a pinned Context Surface, which is a window of ours taking the keyboard on
purpose rather than the reader leaving the app. `PaletteWindowController.windowDidResignKey` asks
`AppCore.isHoldingPinnedContext` and, only then, waits a runloop turn to see whether one of our own
windows still holds key. A resign that left the application still hides the palette, so the chat is
never left floating over another app.

Escape follows the same rule, and is handled at the panel in both surfaces: the Command Surface in
`PalettePanel.sendEvent`, the Context Surface in `DeloresContextIslandPanel.sendEvent`. Escape closes
the surface that owns it and nothing else — a Quick Action still running behind the island's busy
state is not ours to cancel. While the card is opening it also cancels the press, because `onAction`
does not fire until the growth ends.

The handoff animation is now reserved for the explicit `Ask AI` escalation. Native actions leave the
Context Surface through the Quick Action admission path instead of displaying a progress card for a
Chat they never enter.

Two differences between the surfaces are recorded rather than resolved, because each direction is a
visual decision of its own:

- **Material.** The Context Surface draws with Liquid Glass (`Theme.frosted`), carried over from the
  toolbar it came from. The palette draws with `NSVisualEffectView(.hudWindow)` under a
  reader-configurable scrim. The two are on screen together only across the hand-off's fade, and
  they were left as they are on that basis.
- **Window level.** The island is at `.statusBar` so it sits over the menu bar it is anchored to; the
  palette is at `.floating`. Across the hand-off the outgoing island therefore draws over the
  incoming palette until its exit fade (`Theme.Duration.exit`) ends.

## What Pin holds

The Context Surface can be pinned from its own bar (`DeloresContextIslandController.isPinned`).
The toolbar this island came from pinned the expanded panel that was holding an answer; here the
selection is the durable object: the island stays put and the same captured text stays behind its
actions. That is the state a reader wants when they are about to press a second native action, or
when they want to escalate the same selection to `Ask AI`.

Pinned, and only while pinned:

- A new selection passes by. `DeloresContextCoordinator.captureSelection` drops the gesture before
  it reads anything, so neither the clipboard nor the recorded selection state is disturbed.
- An outside click passes by. `windowDidResignKey` is the only way this surface used to leave without
  being asked.
- A native action press does not take the bar away. The Quick Action runs against the held selection,
  and `releaseSurface()` leaves the island and captured context alone. An `Ask AI` press follows the
  handoff path; its growth exists to carry the reader *out* of the island, while the pinned island
  remains as the held context.

Escape and the close button still get out, and either one clears the pin with the panel. The toolbar
drew the same line: a pinned panel there still answered Escape.

**An `Ask AI` action pressed while the chat is already on screen joins it instead of starting over.**
A chat the reader can see is a conversation, and replacing it would take away the answer they were
reading. Only a pinned surface reaches this with the chat still up, because every other route dismissed
the palette on the way in. `AIChatCoordinator.isChatOnScreen` reports the fact; the choice stays with
`DeloresContextCoordinator`.

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
| Quick Action entry with a captured selection, and the language it translates into | `QuickActionCoordinator` | One small integration seam; the native execution path for Context actions |
| Explicit Ask AI entry carrying the current selection | `AIChatCoordinator` | One small integration seam; selection-aware prompt/provider seams remain available for a future richer handoff |
| Palette dismissal while the reader holds a pinned Context Surface | `Palette/PaletteWindowController.swift` | One guarded branch in `windowDidResignKey`, scoped to `AppCore.isHoldingPinnedContext` |
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
   `QuickActionPrompt.swift`, `QuickActionCoordinator.swift`, `PaletteWindowController.swift`,
   `project.yml` and `Info.plist`.
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
