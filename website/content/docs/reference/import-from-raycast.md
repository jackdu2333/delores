---
title: Import from Raycast
description: Read a Raycast export and bring your shortcuts, favorites, quicklinks and history across.
---

Tinycast reads Raycast's own export file directly, in **Settings → Backup → Raycast Export**, or in
the welcome screen the first time you open Tinycast.

## Which exports it reads

**Raycast v2.0 and newer only.** Tinycast reads the `.rayconfig` file that Raycast v2.0 and later
write, and nothing else. Check your Raycast version in **Raycast → Settings → About** before you
export.

**Raycast v1.x exports are not supported.** That format was dropped in **Tinycast v0.10.5**, along with
the Raycast X beta format — both were deleted rather than carried. If your file will not open, export
it again from a current Raycast.

## Steps

1. In Raycast, export your settings and data, and note the passphrase.
2. In Tinycast, go to **Settings → Backup → Raycast Export** and choose the file.
3. Type the passphrase, tick the things you want, and import.
4. **Quit Tinycast and open it again.**

**Quit and reopen Tinycast once the import finishes.** Not all of what you brought across takes effect
in the running app, so a full restart is what makes the whole import live. Quit from the menu-bar icon
— closing the Settings window is not enough — then open Tinycast again.

Tinycast recognizes the file **before** you type the passphrase, so a wrong passphrase is reported as
a wrong passphrase, not as "this is not a Raycast file".

## About that passphrase

**Raycast encrypts the export even if you never set a password.** It makes one up and keeps it in
your login Keychain.

You can see it in **Raycast → Settings → Extensions → Export Settings & Data**, or in Keychain Access
under the service `Raycast` and account `export_passphrase`.

**Tinycast never reads your Keychain.** You paste the passphrase in yourself.

## What comes across

| Category            | Notes                                                      |
| ------------------- | ---------------------------------------------------------- |
| Shortcuts           | App shortcuts, command shortcuts, and your Hyper key setup |
| Favorites           | From Raycast's pinned items                                |
| Aliases             | App aliases                                                |
| Clipboard history   | Text, and images whose files still exist                   |
| Quicklinks          | Name, link and the app it opens with                       |
| Compact mode        | From Raycast's window mode                                 |
| Pop to root         | Only when the timing matches one Tinycast offers           |
| Launch at login     |                                                            |
| Menu bar visibility | From Raycast's menu bar icon setting                       |

The list of apps kept out of clipboard history comes across with Clipboard history.

A shortcut with a modifier Tinycast does not recognize is **skipped whole**, rather than imported as
something slightly different from what you had.

## Clipboard history

Images come across only if their files still exist on this Mac. The summary tells you how many were
missing, rather than dropping them silently.

## Quicklinks

Quicklinks are added to your library, never replacing it, and duplicates are skipped just like a
[quicklink import](/docs/launcher/quicklinks#import-and-export). Raycast's `{Query}` becomes
`{argument}`.

Importing at least one quicklink turns the Quicklinks feature on.

## Afterwards

There is a **Quit Raycast** button in the pane, for when you are ready.

Nothing in Tinycast needs Raycast to be installed once the import is done.
