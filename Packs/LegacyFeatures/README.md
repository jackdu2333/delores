# Legacy feature packs

These directories are intentionally outside the `Tinycast` application target. They preserve the
removed feature code, focused tests, and design notes so a future standalone pack can be built without
keeping the capabilities in Delores' core process.

Parked here:

- `RaycastExtensions/` — the Raycast-compatible JavaScriptCore runtime and extension host.
- `Snippets/` — keyword listening, Markdown snippets, and snippet-specific UI.
- `Calendar/` and `Camera/` — calendar/meeting flows and camera preview surfaces.
- `CustomCommands/` — shell commands, script import, argument forms, and output UI.
- `Updates/` — in-app updater, release feed, installer, and relaunch. Its `Service/ToolRunner.swift` is
  upstream's original, byte for byte; the active target adopted the same helper at
  `Tinycast/Platform/ToolRunner.swift`, where it has since moved on. A restore therefore takes the
  active file and drops this one rather than reviving this one — the two are deliberately no longer
  identical, and copying this version over that one would put the bugs back.
- `Notes/` — **restored to the active target on 2026-09-19** (`Tinycast/Features/Notes/`, from upstream
  tag `v0.11.3-beta.98`). This copy is the superseded snapshot the pack move parked, kept only until
  someone decides it can go: it is an older, smaller Notes than the one the app now builds.
- `Support/` — support window and automatic reminder schedule.
- `Emoji/` — emoji picker, generated catalog, pins, and search index.
- `ClipboardOCR/` — image/PDF text recognition helper, indexer, and worker.
- `Tests/` and `docs/` — verification harnesses and the feature-specific notes for those packs.

The move is reversible. User data is not removed or migrated by this source split; the active Delores
target simply no longer opens or owns these capabilities.
