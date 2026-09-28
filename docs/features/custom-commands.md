# Shell commands in Delores

## Invariants

- A saved command executes only through `CustomCommandCoordinator`, after the library and row switches
  and any required arguments or confirmation have been checked.
- The one-off fallback is controlled in Fallbacks independently of the saved-command switch.
- Argument values enter zsh as positional data, never interpolated shell syntax.
- Importing a backup never enables the executable-command capability without a local choice.

Delores' Command Surface supports two explicit ways to run shell code. A typed query may be sent to
**Run Shell Command** in the fallback section. This is a one-off command: it is not saved and is
independent of the **Enable custom commands** switch. Settings ▸ Fallbacks owns its checkbox.

Settings ▸ Commands also lets the reader save named **Custom Commands**. The library starts off. When
enabled, a saved command can be searched by name, run from its row or optional global shortcut, and
given up to three positional arguments in fields beside the search query. A command's body is not
indexed. Disabling the library removes its rows and makes existing shortcuts inert; disabling one row
preserves its text and shortcut while preventing execution.

## Execution and ownership

`AppCore` owns `CustomCommandStore` and `CustomCommandCoordinator`. The store persists in the current
bundle's `UserDefaults`; the coordinator is the sole run gate. The runner invokes `/bin/zsh` as the
current user. A saved command can opt into loading the shell environment, confirmation before running,
output display, and a working directory. Arguments are handed to zsh as positional parameters, never
inserted into shell text. The one-off fallback loads the shell environment and streams into the
reusable Command Output window. The window's Stop button is the only way Delores ends a running command.

The model, runner, output presenter, and coordinator were taken from official Tinycast `main` at
`752ebce65d92987759de2a78c2136c08ca5b1f67` (2026-09-28). Delores uses its existing Settings
sheet and inline argument controls instead of importing Tinycast's newer Settings editor framework.
The previous implementation remains as a snapshot under `Packs/LegacyFeatures/CustomCommands/`.

## Backup boundary

The native configuration backup carries saved command definitions and their shortcuts. Import asks
before applying any configuration containing shell commands. It does not carry the
`customCommandsEnabled` capability switch, so an import cannot silently turn on shell execution.

## Verification

After a cloud build, inspect a command created in Settings, search and run it, run a typed one-off
command, and confirm that both show the expected output. Verify that disabling the saved-command
library blocks its row and shortcut, while the one-off fallback remains governed by its own checkbox.
