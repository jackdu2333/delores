# Delores documentation

This is the engineering documentation for Delores. Delores keeps Tinycast's source tree and upstream
conventions so the Command Surface can continue to build on its launcher and search foundation. That
provenance is intentional; the product model documented here is Delores' one core, three surfaces,
and many capabilities.

Start with [`AGENTS.md`](../AGENTS.md) at the repo root — it is the short version, and it links here for
anything that needs more than a line.

Each document below has one job and one trigger: the change that obliges you to edit it. A document that
contradicts the code is a defect, so fix it in the commit that made it wrong.

| Document | Covers | Edit it when |
| --- | --- | --- |
| [architecture.md](architecture.md) | How the app is wired: the layers, who owns what, the windows, the Observation model, the folder tree | a layer boundary, an owner, or the tree changes |
| [standards.md](standards.md) | How code here is written: posture, naming, style, concurrency, performance budgets, comments | a convention changes, or a check is added |
| [testing.md](testing.md) | How to verify a change: the definition of done, the harnesses, purity checks, budgets, the manual sweep | a harness moves, or a budget changes |
| [development.md](development.md) | The local loop: setup, build, dev channel, editor, format/lint, generated data | the local toolchain changes |
| [release.md](release.md) | How a build reaches a user: packaging, CI, releases, the Homebrew tap, the website | the pipeline changes |
| [signing.md](signing.md) | The self-signed identity and the two CI secrets | the signing setup changes |
| [ui.md](ui.md) | The design system: tokens, panel chrome, row grammar, glass, dialogs and HUDs | a token or a presentation rule changes |

## Features

One document per feature, covering its invariants and internals. A few span more than one source
folder — `palette.md` covers `Tinycast/Palette/`, `backup.md` covers two. Every one of them **must**
open with an `## Invariants` section; read it before changing anything in that area.

[palette](features/palette.md) ·
[launcher](features/launcher.md) ·
[AI providers and chat](features/ai.md) ·
[quick actions](features/quick-actions.md) ·
[clipboard](features/clipboard.md) ·
[calculator](features/calculator.md) ·
[file search](features/file-search.md) ·
[notes](features/notes.md) ·
[menu search](features/menu-search.md) ·
[quicklinks](features/quicklinks.md) ·
[Apple Shortcuts](features/apple-shortcuts.md) ·
[hotkeys](features/hotkeys.md) ·
[navigation](features/navigation.md) ·
[archived window management](features/window-management.md) ·
[archived window layouts](features/window-layouts.md) ·
[uninstall](features/uninstall.md) ·
[backup](features/backup.md) ·
[Raycast import](features/raycast-import.md) ·

Raycast Extensions, Snippets, Calendar/Meeting/Camera, Custom Commands, Updates, Support
reminders, the Emoji picker and Clipboard OCR are preserved as parked feature packs under
[`Packs/LegacyFeatures/`](../Packs/LegacyFeatures/README.md), but are not part of the active Delores
target. Notes was parked with them and has since been brought back — see
[features/notes.md](features/notes.md).

Menu bar and Settings chrome are localized. English is the source string; Simplified Chinese lives in
`Tinycast/Resources/Localizable.xcstrings`. Launcher command names stay English until a later pass.


## Contributing

[`CONTRIBUTING.md`](../CONTRIBUTING.md) covers the workflow — what to open, what to test, what a PR needs.
[`SECURITY.md`](../SECURITY.md) covers vulnerability reports.
