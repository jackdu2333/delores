---
title: Commands
description: Every built-in command in the launcher.
---

Commands are things Tinycast does, reachable by name from the launcher.

## Built-in commands

Every built-in command lives in exactly one Settings pane. A feature's commands sit in that
feature's own pane, and only appear while the feature is on. The rest live in **Settings → Commands**.

| Pane                                               | Commands                                                                                                                                                                                           |
| -------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [AI](/docs/ai)                                     | AI Chat                                                                                                                                                                                            |
| [Quick Actions](/docs/ai/quick-actions)            | Fix Grammar · Rewrite · Translate · Summarize                                                                                                                                                      |
| [Clipboard](/docs/features/clipboard)              | Clipboard History                                                                                         |
| [File Search](/docs/features/file-search)          | Search Files                                                                                              |
| [Navigation](/docs/features/navigation)            | Switch Windows · Search Menu Bar Items                                                                    |
| [Window Management](/docs/features/window-layouts) | Create Window Layout · Create Layout from Current Windows                                                 |
| [Quicklinks](/docs/launcher/quicklinks)            | Create Quicklink · Search Quicklinks · Import Quicklinks · Export Quicklinks                              |
| Commands                                           | Calculator History · Export Backup · Import Backup · Import from Raycast · Settings · About Tinycast · Quit Tinycast |

Two more appear only for what you type: **Open in Browser** and **Run Shell Command**. See
[Fallbacks](/docs/launcher/fallbacks).

Each command's row has a launcher checkbox, a shortcut recorder and an alias field.

**Every built-in command can take a global shortcut**, except Open in Browser and Run Shell Command,
which need text to work on, and Quit Tinycast, so no stray key press can quit the app.

A command that opens a screen works like a toggle: press its shortcut again to close it.

**Enable Commands** at the top of Settings → Commands switches off every command listed in that pane,
along with their shortcuts. Unticking one row only hides it from search; its shortcut keeps working.
