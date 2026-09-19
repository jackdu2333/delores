---
title: Settings
description: Every Settings pane, what it holds, and its defaults.
---

Open Settings with <kbd>⌘</kbd><kbd>,</kbd> from the palette, the **Settings** command, or the menu bar
icon. It is a normal, resizable window.

**The search field finds any setting by name**, and also by words that are not in its title:
`caps lock` finds **Hyper Key**. Picking a result jumps straight to that row.

There are 18 panes in four groups.

## General

### General

| Setting      | Default  |
| ------------ | -------- |
| App Launcher | **None** |

| Setting                           | Options                                                                       | Default                           |
| --------------------------------- | ----------------------------------------------------------------------------- | --------------------------------- |
| Learned ranking                   | **Reset…** clears everything learned                                          | —                                 |
| Hyper Key                         | None · Caps Lock · Right Control · Right Shift · Right Option · Right Command | **None**                          |
| Quick Press                       | Does Nothing · the original key · Trigger Escape                              | **Does Nothing**                  |
| Include Shift (⇧)                 | On · Off                                                                      | **On**                            |
| Theme                             | System · Light · Dark                                                         | **System**                        |
| Interface size                    | Default · Large · Larger                                                      | **Default**                       |
| Background transparency           | Less to More, with Reset                                                      | Middle                            |
| Compact mode                      | On · Off                                                                      | Off                               |
| Show favorites in compact mode    | On · Off                                                                      | **On**                            |
| Follow the cursor across displays | On · Off                                                                      | **On**                            |
| Drag to reposition                | On · Off                                                                      | Off                               |
| Launch at login                   | On · Off                                                                      | Off                               |
| Show in menu bar                  | On · Off                                                                      | **On**                            |
| Pop to Root Search                | Immediately · After 5, 15, 30, 60 or 90 seconds                               | **Immediately**                   |
| Escape Key Behavior               | Navigate back or close window · Close window and pop to root                  | **Navigate back or close window** |
| Auto-switch input source          | None, or any keyboard input source you have                                   | **None**                          |

See [The palette](/docs/palette), [Learned ranking](/docs/launcher#learned-ranking) and
[Hotkeys](/docs/reference/hotkeys#hyper-key).

### Permissions

Shows whether **Accessibility** is granted, and opens the right System Settings
pane. See [Permissions](/docs/permissions).

## Launcher

| Pane            | What is in it                                                                                                   |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| Applications    | [Search Scopes](/docs/launcher#search-scopes), **Enable Applications**, and a row per app                       |
| System Settings | **Enable System Settings**, and a row per pane                                                                  |
| System Actions  | **Enable System Actions**, and a row per action                                                                 |
| Commands        | **Enable Commands**, and a row per built-in command                                                             |
| Quicklinks      | [Quicklinks](/docs/launcher/quicklinks) switch, its commands, behavior, import and export                       |
| Apple Shortcuts | Enable Apple Shortcuts, and a row per shortcut                                                                  |
| Fallbacks       | Which [fallbacks](/docs/launcher/fallbacks) show under a search, and their order                                |

A row usually has a launcher checkbox, a shortcut recorder and an [alias](/docs/launcher/aliases)
field. Long lists have a filter field.

The **Enable …** switch at the top of a pane turns off every row **and** every shortcut in it. A row's
checkbox only hides that row from search.

## Features

Everything here ships **off**, except Clipboard.

| Pane                                                  | Switch                            | Other settings                                                                                                                                                                                                                                |
| ----------------------------------------------------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [AI](/docs/ai)                                        | Enable AI                         | Providers, Default model, Reasoning effort, Web search, Opens to, Start a new conversation after, Keep conversations, System prompt, [MCP servers](/docs/ai/mcp), AI commands                                                                 |
| [Quick Actions](/docs/ai/quick-actions)               | Enable Quick Actions              | Actions (Replace or Preview, shortcut, prompt, model), Add Quick Action, Model, Translate to                                                                                                                                                  |
| [File Search](/docs/features/file-search)             | Enable File Search                | Commands, Search Scopes, Ignore Patterns                                                                                              |
| [Navigation](/docs/features/navigation)               | Enable navigation                 | Commands, Show Apple menu items (**Off**), Disabled Applications                                                                      |
| [Window Management](/docs/features/window-management) | Enable window management          | Show in launcher, Cycling (**None**), Gap between windows (**0**), window commands, [Window Layouts](/docs/features/window-layouts) |
| Delores                                              | Enable desktop companion          | Context bar actions, companion size and creature, window snapping                                                                     |
| [Clipboard](/docs/features/clipboard)                 | Enable Clipboard History (**On**) | Clipboard commands, Keep history for (**3 Months**), Default action (**Paste**), Disabled Applications, Clear history                 |

## Advanced

**Backup.** Export a backup, import one, or
[import from Raycast](/docs/reference/import-from-raycast). See [Backup & restore](/docs/reference/backup).

**About.** Version, license, and links to the project.
