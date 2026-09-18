import SwiftUI
import UniformTypeIdentifiers

struct ClipboardSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var confirmingClear = false

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.clipboardEnabled) {
                    SettingsRowTitle(.clipboardClipboard, "Enable Clipboard History")
                    Text(L10n.string("Record what you copy, so you can paste anything back from the browser."))
                }
            } header: {
                SettingsSectionHeader(.clipboardClipboard)
            }

            FeatureCommandsSection(owner: .clipboard, anchor: .clipboardCommands)
                .settingsEnabled(settings.clipboardEnabled)

            Section {
                Picker(selection: $settings.clipboardRetention) {
                    ForEach(ClipboardRetention.allCases) { retention in
                        Text(L10n.text(retention.title)).tag(retention)
                    }
                } label: {
                    SettingsRowTitle(.clipboardHistory, "Keep history for")
                    Text(L10n.string("Entries older than this are deleted automatically."))
                }
                .onChange(of: settings.clipboardRetention) {
                    core.clipboardCoordinator.applyRetention(settings.clipboardRetention)
                }
                Picker(selection: $settings.clipboardDefaultAction) {
                    ForEach(ClipboardDefaultAction.allCases) { action in
                        Text(L10n.text(action.title)).tag(action)
                    }
                } label: {
                    SettingsRowTitle(.clipboardHistory, "Default action")
                    Text(L10n.string("What ↵ does on an entry; ⌘↵ does the other one."))
                }
            } header: {
                SettingsSectionHeader(.clipboardHistory)
            }
            .settingsEnabled(settings.clipboardEnabled)

            DisabledApplicationsSection(
                bundleIDs: $settings.clipboardDisabledApps,
                anchor: .clipboardDisabledApplications,
                footer: "Clipboard changes from these apps won't be recorded."
            )
            .settingsEnabled(settings.clipboardEnabled)

            Section {
                LabeledContent {
                    Button(L10n.string("Clear…"), role: .destructive) { confirmingClear = true }
                } label: {
                    SettingsRowTitle(.clipboardDisabledApplications, "Clear history")
                    Text(L10n.string("Permanently remove every saved clip and image."))
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.clipboard)
        .confirmationDialog(
            L10n.string("Clear clipboard history?"),
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Clear History"), role: .destructive) {
                core.clipboardCoordinator.clearHistory()
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("This can't be undone."))
        }
    }
}
