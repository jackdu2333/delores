import Foundation
import SwiftUI

/// Where the notes live. The folder is a setting, and switching it moves the pointer rather than the
/// files — what was already in the old folder stays there — so the footer says that out loud instead
/// of leaving someone to discover it by looking for notes that never arrived.
///
/// One `SettingsRow`, not a `LabeledContent` with a trailing `HStack`: the row carries three controls
/// of its own, which is what `SettingsRow` is for, and the path it shows is the row's subtitle, so it
/// gets the shared middle truncation and its own tooltip for free.
struct NotesLocationSection: View {
    @Environment(AppCore.self) private var core
    /// Recomputed on appear and on change: a `fileExists` per body render is too much for one row.
    @State private var isMissing = false

    private var directory: URL { core.notesCoordinator.notesDirectory }
    private var isDefault: Bool { core.notesCoordinator.isUsingDefaultNotesDirectory }
    private var displayPath: String { (directory.path as NSString).abbreviatingWithTildeInPath }

    var body: some View {
        Section {
            SettingsRow(
                title: "Notes Folder",
                subtitle: displayPath,
                anchor: .notesLocation
            ) {
                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(L10n.string("This location no longer exists."))
                } else {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                HStack(spacing: Theme.Spacing.lg) {
                    Button(L10n.string("Choose…"), action: core.notesCoordinator.chooseNotesDirectory)
                    Button(
                        L10n.string("Reveal in Finder"),
                        action: core.notesCoordinator.revealNotesDirectory)
                    if !isDefault {
                        Button(
                            L10n.string("Restore Default"),
                            action: core.notesCoordinator.restoreDefaultNotesDirectory)
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.notesLocation)
        } footer: {
            Text(
                L10n.string(
                    "Markdown files in one folder, one note per file. Changing the folder moves no files."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: directory) { _, _ in refreshMissing() }
    }

    /// Only a chosen folder can go missing — the default one is created the first time it is used.
    private func refreshMissing() {
        isMissing = !isDefault && !FileManager.default.fileExists(atPath: directory.path)
    }
}
