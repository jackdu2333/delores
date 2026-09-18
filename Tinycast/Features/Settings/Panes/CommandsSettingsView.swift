import SwiftUI

/// The built-in command catalogue; user-authored shell commands live in the retired pack.
struct CommandsSettingsView: View {
    var body: some View {
        Form {
            LauncherItemsSection(
                kind: .command,
                anchor: .commandsCommands,
                searchPrompt: "Search commands…")
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commands)
        .releasesFocusOnOutsideClick()
    }
}
