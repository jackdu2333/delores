---
title: Backup & restore
description: Save your setup to one file, choose what goes in and what comes back, and what a backup will never do.
---

**Settings → Backup**

A backup is one `.delores` file. You tick what goes into it, and you tick again what comes back out
when you import. The two choices are separate, so a file with everything in it can still restore only
your clipboard history.

| Category             | What travels                                                                            |
| -------------------- | --------------------------------------------------------------------------------------- |
| Settings & Shortcuts | Shortcuts, quicklinks, window layouts, favorites, aliases, preferences |
| Clipboard History    | Text and image clips with their images, and references to copied files |
| Launcher Learning    | What the launcher learned you reach for, plus calculator history       |
| Notes                | Every note, as the plain Markdown file it already is                   |

The launcher has **Export Backup** and **Import Backup** commands too. They take everything, since
there is no room for checkboxes there.

## Read this before relying on it

**The format belongs to Delores and may change between versions. The only promise is that a backup
imports into the same version that made it.**

The file records which version wrote it. A build that does not recognize it says so clearly,
instead of importing half of it. A backup is for moving your setup to another Mac today, or restoring
after a reinstall. It is not a long-term archive.

A file written before the app was renamed from Tinycast still imports: the old `.tinycast` type is
declared as an imported one, so it opens in the same picker. New backups are always `.delores`.

## Imports are never silent

An import always shows a summary of what it did, category by category.

Imports add rather than overwrite. A note whose name is taken gets a number added, never replaces
yours. Importing the same file twice does not give you two of everything.

Launcher Learning is the exception. It replaces what is there, because mixing two Macs' habits
describes neither.

A copied file in clipboard history travels as its path, not its contents. On import, entries for files
this Mac does not have are left out.

## A backup can never grant a capability

This is the important part.

Some switches are left out of every backup **on purpose**, because turning them on is a decision you
make, not a preference:

- **Quick Actions**: agrees to typing into other apps
- **AI** and **MCP servers**: agree to sending text to a model and running server code
- **Fallback order and checkboxes**: could put a shell command runner in your launcher

So a backup someone sent you cannot type into other apps or reach an AI provider. You turn those on
yourself, in the app, after reading what they do.

## Other things left out on purpose

| Left out                                                        | Why                                                           |
| --------------------------------------------------------------- | ------------------------------------------------------------- |
| AI chats, API keys, and every AI and MCP setting          | Conversations and keys stay on the Mac that had them          |
| Quick Actions model, prompts, language and custom actions | An import must never change what a shortcut does to your text |
| Palette position, auto-switch input source                | They belong to this Mac's screens and hardware                |
| Anything cached, like currency rates                      | It comes back on its own                                      |

Clipboard images are stored inside the backup by name, not by where they sat on your Mac. The one
kind of path a backup does carry is a copied file's location, because that is what the entry is.

**Launch at login** and **Show in menu bar** are read from their live state, so they come back as you
had them.

## Where your data actually lives

Everything a backup carries is also an ordinary file, in `~/Library/Application Support/com.jackdu.delores/`:

| What                                          | Where                                          |
| --------------------------------------------- | ---------------------------------------------- |
| [Quicklinks](/docs/launcher/quicklinks)       | `quicklinks.sqlite3`, with its own JSON export |
| [Clipboard history](/docs/features/clipboard) | `clipboard.sqlite3`, with images beside it     |
| [Notes](/docs/features/notes)                 | `Notes/`, one `.md` file per note              |
| [AI chats](/docs/ai)                          | `ai-chats.sqlite3`, never in a backup          |

Notes are plain Markdown. Copying that folder is a perfectly good backup, and you can read the files
without Delores. That is the point of keeping them that way.
