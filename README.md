# Delores

**One tool, three forms, on top of Tinycast's core.** Delores keeps the mature Tinycast command and
capability core and adds the forms that are needed around a selection and on the desktop itself:

```text
one core → three surfaces → many capabilities

⌥ Space        → Command Surface    → search, commands, Chat, Settings   (the most complete)
select text    → Context Surface    → Translate / Explain / Summarize / Search, in a card
always there   → Companion Surface  → a glance, the last selection, a hand-off
```

`CONTEXT.md` defines the vocabulary. The shape of it: a **Surface** is where the reader is, a
**Capability** is what gets done, and no surface owns the capability behind it. Window snapping and
the split divider are capabilities with a transient affordance, not a fourth form.

## Current slice

```text
select text → Context Island → Translate / Explain / Summarize / Search
                                      ↓
                          streamed answer, copy, write back, one follow-up
```

The island owns its own action catalogue and streams its own answers, reading only the model route,
the prompt overrides and the custom rows from Quick Actions. It does not create a second AI service,
a second text-injection path or a second Keychain.

## Project structure

Tinycast remains the upstream source tree so future updates can be merged without a whole-tree rename.
Delores-owned code lives under `Tinycast/Features/Delores/`; the ownership and sync rules are in
[docs/delores-architecture.md](docs/delores-architecture.md).

The latest local Huaci project is preserved at `Integrations/HuaciGongju/` as a separately tested
integration source. It is not compiled into the Tinycast application target yet; runtime activation
will go through an explicit Delores adapter so Huaci does not create a second AppDelegate, LLM or
selection pipeline. See [ADR 0002](docs/adr/0002-vendor-huaci-latest-project.md).

The local branch is `integration/delores`, with the official Tinycast repository registered as
`upstream`. See [CONTEXT.md](CONTEXT.md) and
[docs/adr/0001-keep-tinycast-as-upstream-overlay.md](docs/adr/0001-keep-tinycast-as-upstream-overlay.md)
for the vocabulary and the non-obvious integration decision.

## Build and verify

The app targets macOS 26 and requires Xcode 26. Generate the Xcode project from `project.yml`, then
open `Tinycast.xcodeproj` and choose the `Delores` scheme in Xcode. The project and target keep their
upstream names solely to make future generated-project merges smaller. The current machine can run
the pure Delores model harness with:

```sh
./Scripts/run-delores-tests.sh
./Scripts/run-huaci-integration-tests.sh
```

With Xcode 26 and the local signing identity available, a signed local DMG can be packaged with:

```sh
./Scripts/build-delores-dmg.sh
```

The public release lane is intentionally not configured yet; its boundary is documented in
[docs/delores-release.md](docs/delores-release.md).

The inherited Tinycast harnesses remain available through `./Scripts/run-tests.sh`. Some of them
require Xcode's SwiftUI macro plugin and cannot run under Command Line Tools alone.

## Upstream

Use the read-only drift check before and after every upstream sync:

```sh
./Scripts/check-upstream-drift.sh
```

The app uses a Delores bundle ID, so the inherited Tinycast updater treats local builds as development
builds and will not install Tinycast releases.

## License

Delores contains code derived from Tinycast and remains under the GNU Affero General Public License v3.
See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
