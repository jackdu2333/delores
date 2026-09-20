# Delores

**Delores is one native macOS intent layer that appears in the form the task needs.** It has one
shared capability core and three user-facing surfaces — the right one appears where the user's task
begins:

```text
one core → three surfaces → many capabilities

⌥ Space        → Command Surface    → search, commands, Chat, Settings   (the most complete)
select text    → Context Surface    → Translate / Explain / Summarize / Search, in a card
always there   → Companion Surface  → a glance, the last selection, a hand-off
```

<p align="center">
  <img src="docs/delores-architecture.svg" alt="Delores architecture: one core, three surfaces" width="100%" />
</p>

Delores openly builds on Tinycast's mature launcher and search foundation. The Delores contribution is
the product design around that foundation: **one shared core, three forms, and capabilities that
appear in the smallest useful surface for the user's current context.**

If you remember one thing: **Delores is not three separate apps, and the Companion is not the product
itself.** Context, Companion and Command are three ways into the same core. The Companion is optional;
users choose whether to use it and which supported pet to show.

`CONTEXT.md` defines the vocabulary. The shape of it: a **Surface** is where the reader is, a
**Capability** is what gets done, and no surface owns the capability behind it. Window snapping and
the split divider are capabilities with a transient affordance, not a fourth form.

Product intent and long-term boundaries: [docs/delores-product.md](docs/delores-product.md).

## The three surfaces

| Surface | You start with | What Delores does there |
| --- | --- | --- |
| **Context** | You have already selected something | Offers the smallest useful actions — Translate, Explain, Summarize or Search — close to the selection. |
| **Companion** | You want Delores nearby | Stays on the desktop, remembers the last selection and offers a lightweight hand-off back into Context. |
| **Command** | You press `⌥ Space` or another hotkey | Opens the complete command layer for search, commands, Chat, Settings and longer-running tasks. |

### Command Surface — the Tinycast-derived foundation

The Command Surface is the most complete form of Delores. It deliberately keeps Tinycast's mature
launcher/search experience as its foundation while Context and Companion extend the same core into
the user's current context.

<p align="center">
  <img src="docs/screenshot.png" alt="Delores Command Surface showing the launcher and search experience" width="920" />
</p>

The repository includes a Command Surface capture. The architecture diagram above is the source of
truth for Context and Companion until fresh captures are taken from a build with their live windows
visible.

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

The Companion is optional and its pet is user-selectable. Delores supports pets from the open-source
Petdex sources listed in [NOTICE.md](NOTICE.md); users may choose a supported pet or turn the
Companion off, and Delores does not require a pet created by this project.

The local branch is `main`, with the official Tinycast repository registered as
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

Which checks have run, which are still owed, and what the manual sweep on real displays has to cover:
[docs/delores-verification.md](docs/delores-verification.md).

## Upstream

Use the read-only drift check before and after every upstream sync:

```sh
./Scripts/check-upstream-drift.sh
```

The app uses a Delores bundle ID, so the inherited Tinycast updater treats local builds as development
builds and will not install Tinycast releases.

## License

Delores contains code derived from Tinycast and remains under the GNU Affero General Public License
v3 or later. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
