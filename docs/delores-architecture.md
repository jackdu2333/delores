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
actions. That is the state a reader wants when they are about to press a second action on the same
text.

Pinned, and only while pinned:

- A new selection passes by. `DeloresContextCoordinator.captureSelection` drops the gesture before
  it reads anything, so neither the clipboard nor the recorded selection state is disturbed.
- An outside click passes by. `windowDidResignKey` is the only way this surface used to leave without
  being asked.
- An action press does not take the bar away. Every catalog action answers in the island's own card
  (`DeloresContextCoordinator.answer`), so `releaseSurface()` has nothing to do and the held selection
  stays behind the bar. A press on the chat hand-off route is the one exception: its growth exists to
  carry the reader *out* of the island, while the pinned island remains as the held context.

Escape and the close button still get out, and either one clears the pin with the panel. The toolbar
drew the same line: a pinned panel there still answered Escape.

**The chat hand-off joins a chat that is already on screen instead of starting over.** A chat the
reader can see is a conversation, and replacing it would take away the answer they were reading.
`AIChatCoordinator.isChatOnScreen` reports the fact; the choice stays with `DeloresContextCoordinator`.
No catalog row reaches this today — 问 AI was retired as a duplicate of 解释 — so what follows is the
behaviour of a live seam rather than of a button, kept because it is the island's only route into Chat.

## Asking again

A card can be asked for more than one answer, which is most of why it is a card rather than a toast.

- **Stop** ends a reply that is still arriving and keeps what it produced. Cancelling the task is the
  whole mechanism — the streaming loop recognises the cancellation and settles the card itself, so there
  is one place that decides what a stopped reply looks like. `cancelAnswer()` is a different thing and
  stays that way: it invalidates the generation, so a card the reader has left behind never writes to the
  surface that replaced it.
- **Retry** asks the same action about the same text again, from the first turn. Carrying a half-answer
  back into the request would ask the model to continue one, which is not what the press means.
- **Follow-up** asks a further question on the same action and the same selection, carrying the exchanges
  already settled. It stops at ten exchanges, and at eight thousand characters a turn, trimmed
  oldest-first and in pairs: an unpaired question teaches a model to answer something nobody asked.

None of them leave the island. The selection stays behind the bar, so a second go never means going back
and selecting the text again — which is the same thing Pin is for, one press shorter.

## Sizing the Context Island

The bar hugs its controls, so its width is measured from its content — and that measurement is taken on
a copy of the view that is never handed a frame, because a view told its own width cannot report what
width it needs.

The frame the controller then chooses is *imposed on the content*, not merely applied to the panel, and
that is load-bearing rather than defensive. An `NSHostingView` installed in a window also sizes that
window: SwiftUI's `windowDidLayout` runs `updateAnimatedWindowSize` and animates the panel to the ideal
size of whatever it is hosting, the controller's frame included, and `sizingOptions = []` does not stop
it. Measured on this machine before the fix: the controller set the panel to 497pt, the window server
reported 428pt, the bar laid itself out at 428 where every title collapses to an ellipsis — and, a
truncated bar being a narrower bar, the size SwiftUI then aimed for was the truncated one. Pinning the
content to the vessel makes the two numbers identical, so there is nothing left to resize to.

No unit test covers this: the island's UI layer is outside the harness's compile list. The check that
does cover it is reading the panel's real bounds from outside the process
(`CGWindowListCopyWindowInfo`) and comparing them with the size the controller chose.

## Phase 1.5 boundary

`AppCore` now exposes only `DeloresCoordinator`. The coordinator owns the current Context Surface
implementation and is the place where future Surface arbitration will live.

Selection gesture admission uses a window snapshot policy: only visible windows that accept mouse
events block selection detection. HUDs and drop guides remain pass-through. Quick Action admission
returns `started`, `busy` or `disabled`; the Context Island closes only for `started` and shows an
explicit busy state otherwise.

### Ownership map

### Spatial / Companion adapter (Delores-owned)

`Tinycast/Features/Delores/UI/DeloresSpatialCoordinator.swift` is the only runtime adapter for the vendored
Companion and Spatial capabilities. It owns lazy `start/stop` for the desktop companion, window snapping and
split divider; `AppCore` observes the three persisted switches and reprojects the adapter on every change.
Companion mode is mutually exclusive with the two ghost window features. The adapter does not compile Huaci's
`AppDelegate`, `ConfigManager`, `SelectionMonitor`, `LLMService`, or `main.swift`; Context remains owned by
`DeloresCoordinator`, with the adapter receiving the latest captured selection and handing companion double-click
back to the Context Surface. Settings live under the `Delores Spatial` pane. The first implementation is a
Delores-owned vertical slice; visual/material parity with the vendored Huaci reference still requires manual
acceptance, and Accessibility permission is required for cross-app window movement.


| Area | Owner | Sync posture |
| --- | --- | --- |
| Palette, AI providers, Keychain, TextInjector, window engine | Tinycast | Inherit upstream |
| Selection gesture and Context Surface | `Features/Delores/` | Delores-owned |
| Shared task snapshot | `Features/Delores/Model/InvocationContext.swift` | Stable seam |
| Quick Action entry with a captured selection | `QuickActionCoordinator` | **Withdrawn**: the selection-aware `run` overload and its `begin(selectionOverride:)` were removed when the Context Surface stopped executing native Quick Actions — its catalog is its own, and the whole overload had no remaining caller |
| Per-action route for a Context Surface action that no Quick Action backs | `AppCore.quickActionProvider(forActionID:)`, `QuickActionSettingsStore.model(forActionID:)`, `QuickActionCoordinator.provider(forActionID:)` | One small integration seam. Id-keyed, so a per-action model binding survives a catalog Delores owns; `quickActionProvider(for:)` and `model(for:)` now delegate to these, so no behaviour moved |
| Reader-replaceable per-action prompt, reached by id | `QuickActionCoordinator.instructionOverride(forActionID:)`, `QuickActionSettings.instructionOverride(forActionID:)` | The Context Surface applies it to any catalog row whose id is also a `BuiltInQuickAction`, so a prompt rewritten in Settings reaches the bar. Id-keyed for the same reason the model route is: the two catalogues overlap without agreeing. `provider(for:)` and `targetLanguage` are **still unreferenced** — delete them the next time the chat handoff is designed and they remain unused |
| Custom Quick Actions on the Context Surface | `QuickActionCoordinator.customQuickActionRows`, `DeloresContextAction.available(aiEnabled:customActions:)` | One-way: the bar copies the rows Settings owns and never writes one, so neither catalogue can be changed by the surface that borrowed it. The row's entry id is its binding key, so a model bound in Settings survives the trip |
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
