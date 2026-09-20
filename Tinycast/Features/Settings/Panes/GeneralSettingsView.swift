import SwiftUI

/// The app itself rather than any one Surface: whether Delores starts with the Mac, and whether it
/// keeps a place in the menu bar.
///
/// Everything the palette reads — its summons, its ranking, Hyper Key, its appearance and its
/// behaviour between summons — moved to the Command Surface pane, which is where a reader looking
/// for it would now expect to find it.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    // The same key `MenuBarExtra(isInserted:)` binds, so this updates the icon live.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.launchAtLogin) {
                    SettingsRowTitle(.generalGeneral, "Launch at login")
                    Text(L10n.string("Start Delores automatically when you log in."))
                }
                Toggle(isOn: $showInMenuBar) {
                    SettingsRowTitle(.generalGeneral, "Show in menu bar")
                    Text(
                        L10n.string(
                            "Keep the Delores icon in the menu bar. Shortcuts still work when hidden."
                        ))
                }
            } header: {
                SettingsSectionHeader(.generalGeneral)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.general)
    }
}
