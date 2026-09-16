# Delores architecture and upstream sync

## Current implementation boundary

The first vertical slice is intentionally small:

```text
selection gesture
    → SelectionGestureMonitor
    → DeloresContextCoordinator
    → Context Island
    → Tinycast QuickActionCoordinator
    → existing Quick Action result surface
```

The Context Island does not own AI, clipboard or Accessibility implementation. It only presents
actions and hands a captured selection snapshot to the existing Quick Action route.

During this first slice, `quickActionsEnabled` is also the opt-in boundary for the Context Surface:
both capabilities need the same Accessibility permission. A separate Context Surface setting should
only be introduced when the product needs independent control, so the consent semantics do not split
prematurely.

### Ownership map

| Area | Owner | Sync posture |
| --- | --- | --- |
| Palette, AI providers, Keychain, TextInjector, window engine | Tinycast | Inherit upstream |
| Selection gesture and Context Surface | `Features/Delores/` | Delores-owned |
| Shared task snapshot | `Features/Delores/Model/InvocationContext.swift` | Stable seam |
| Quick Action entry with a captured selection | `QuickActionCoordinator` | One small integration seam |
| App lifecycle wiring | `AppCore` | One small integration seam |
| Product identity and build metadata | `project.yml`, generated project, `Info.plist` | Delores-owned seam |
| Delores model gate | `.github/workflows/ci.yml`, `Scripts/run-delores-tests.sh` | Delores-owned seam |
| Local packaging and release gate | `Scripts/build-delores-dmg.sh`, `docs/delores-release.md`, release workflow guard | Delores-owned seam |
| Latest Huaci source and regression harness | `Integrations/HuaciGongju/`, `Scripts/run-huaci-integration-tests.sh` | Vendored integration; explicit adapter required |
| Quick Actions consent copy | `Features/QuickActions/Settings/QuickActionsSettingsView.swift` | Delores-owned seam |

Do not rename the upstream `Tinycast/` directory, upstream source files, or the generated project
structure merely to make the product name look uniform. That creates avoidable conflicts on every
upstream update.

## Upstream workflow

`upstream` points to the official Tinycast repository. `integration/delores` is the product branch.
The repository currently starts from Tinycast commit `79d380aa96072ad54e1259448a316d9e34d2a73b`.

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
2. Reconcile only the Delores seams in `AppCore.swift`, `QuickActionCoordinator.swift`, `project.yml`
   and `Info.plist`.
3. Never copy a Delores file over an upstream file to resolve a conflict.
4. Regenerate the Xcode project with XcodeGen after `project.yml` is settled.
5. Run the upstream harnesses, the Delores model harness and the available Debug build checks.
6. Merge the verified sync branch back into `integration/delores`.

If an upstream change makes a seam unnecessary, delete the seam and update this document in the same
change. If an upstream feature overlaps a Delores feature, stop and record the ownership decision
before merging; do not silently keep two implementations.

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
