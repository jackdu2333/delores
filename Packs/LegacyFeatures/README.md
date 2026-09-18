# Legacy feature packs

These directories are intentionally outside the `Tinycast` application target. They preserve the
removed feature code, focused tests, and design notes so a future standalone pack can be built without
keeping the capabilities in Delores' core process.

Parked here:

- `RaycastExtensions/` — the Raycast-compatible JavaScriptCore runtime and extension host.
- `Snippets/` — keyword listening, Markdown snippets, and snippet-specific UI.
- `Calendar/` and `Camera/` — calendar/meeting flows and camera preview surfaces.
- `CustomCommands/` — shell commands, script import, argument forms, and output UI.
- `Tests/` and `docs/` — verification harnesses and the feature-specific notes for those packs.

The move is reversible. User data is not removed or migrated by this source split; the active Delores
target simply no longer opens or owns these capabilities.
