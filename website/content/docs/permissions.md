---
title: Permissions
description: What Tinycast asks for, why, and the moment it asks.
---

Tinycast asks for a permission **only when you use a feature that needs it**, never at launch. The
launcher, the calculator and search all work with no permission at all.

**Settings → Permissions** shows whether Accessibility is granted, and opens the right System
Settings pane for you.

## Accessibility

macOS calls this "control your computer". In Tinycast it lets the app read from, and write to, the
window you were using before the palette opened.

Grant it in **System Settings → Privacy & Security → Accessibility**, or from
**Settings → Permissions**.

### What needs it

| Feature                                                                       | Why                                                  |
| ----------------------------------------------------------------------------- | ---------------------------------------------------- |
| [Clipboard](/docs/features/clipboard) paste                       | Puts the item into the app you came from             |
| [Quick Actions](/docs/ai/quick-actions)                           | Reads your selected text and replaces it             |
| [Window management](/docs/features/window-management) and layouts | Reads and sets other apps' window frames             |
| [Navigation](/docs/features/navigation)                           | Lists open windows and presses menu bar items        |
| [Hyper key](/docs/reference/hotkeys#hyper-key)                    | Turns one physical key into a modifier chord         |
| Double-tap modifier shortcuts                                     | Notices the tap pattern                              |
| <kbd>⌘</kbd><kbd>esc</kbd> back to the root search                | macOS keeps this chord for itself unless we catch it |

## Automation and Bluetooth

A few actions trigger their own macOS prompt the first time you run them:

- **Show Info in Finder** in the [uninstaller](/docs/launcher/uninstall), and some
  [system actions](/docs/launcher/system-actions), drive other apps through Apple Events. That raises
  the standard Automation prompt.
- **Toggle Bluetooth** raises the Bluetooth prompt.

If you say no, Tinycast tells you and links to the right System Settings pane instead of silently
doing nothing.

## Full Disk Access

Tinycast **checks** for Full Disk Access but **never asks** for it.

The [uninstaller](/docs/launcher/uninstall) checks quietly to work out which files it can move.
Without the grant, protected places like `~/Library/Containers`, `~/Library/Group Containers` and
`~/Library/Cookies` show as locked rows instead. The worst case is a row you clear by hand.

## What Tinycast never needs

- **File access for File Search.** [File Search](/docs/features/file-search) reads the Spotlight
  index macOS already keeps. If Spotlight has not indexed something, you get fewer results, not a
  prompt.
- **Screen Recording.** The window switcher reads window titles through Accessibility.
 - **Location.** The calculator picks your currency from your Mac's region setting.
 - **Input Monitoring.** Nothing in the current app listens to keystrokes that way.
