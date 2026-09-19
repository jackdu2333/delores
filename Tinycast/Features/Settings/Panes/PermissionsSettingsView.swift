import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        accessibilityTrusted ? L10n.string("Granted") : L10n.string("Not granted"),
                        systemImage: accessibilityTrusted
                            ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
                } label: {
                    SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                    Text(L10n.string("Lets Delores paste a clipboard item into the app you were using."))
                }

                LabeledContent {
                    Button(accessibilityTrusted ? L10n.string("Open…") : L10n.string("Grant Access…")) {
                        Permissions.openAccessibilitySettings()
                    }
                } label: {
                    Text(accessibilityTrusted ? L10n.string("Manage in System Settings") : L10n.string("Grant access"))
                    Text(L10n.string("Opens Privacy & Security › Accessibility."))
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            } footer: {
                Text(L10n.string("Access Delores needs to work with other apps."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
    }
}
