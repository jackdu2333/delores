import Combine
import SwiftUI

/// The window-placement capabilities that answer a gesture rather than a summon: snapping and the
/// split divider.
struct WindowSnappingSection: View {
    @Environment(AppSettings.self) private var settings
    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var settings = settings
        return Section {
                if needsAccessibility {
                    SettingsRow(
                        title: L10n.string("Accessibility permission required"),
                        subtitle: needsAccessibilitySubtitle
                    ) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.destructive)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        Button(L10n.string("Open System Settings")) {
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
                Toggle(isOn: snappingBinding) {
                    SettingsRowTitle(.windowSnappingCapabilities, "Enable window snapping")
                    Text(
                        L10n.string(
                            "Drag a window up to the island at the top of the display, and drop it on the split you want."
                        ))
                }
                Toggle(isOn: dividerBinding) {
                    SettingsRowTitle(.windowSnappingCapabilities, "Enable split divider")
                    Text(
                        L10n.string(
                            "Move the pointer onto the seam between two tiled windows to resize them together."
                        ))
                }
            } header: {
                SettingsSectionHeader(.windowSnappingCapabilities)
            } footer: {
                    Text(
                        L10n.string(
                            "Both read and move other apps' windows through the same Accessibility permission Delores uses to paste. Neither is enabled by default, and neither is restored from a settings backup."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        .onReceive(refreshTimer) { _ in isTrusted = Permissions.isAccessibilityTrusted() }
    }

    /// The window capabilities write window frames, so the grant is asked for where the reader turns
    /// them on — an explicit gesture — rather than at launch.
    private var snappingBinding: Binding<Bool> {
        Binding(
            get: { settings.deloresWindowSnappingEnabled },
            set: { enabled in
                guard enabled else {
                    settings.deloresWindowSnappingEnabled = false
                    return
                }
                guard Permissions.ensureAccessibility() else { return }
                settings.deloresWindowSnappingEnabled = true
            })
    }

    private var dividerBinding: Binding<Bool> {
        Binding(
            get: { settings.deloresSplitDividerEnabled },
            set: { enabled in
                guard enabled else {
                    settings.deloresSplitDividerEnabled = false
                    return
                }
                guard Permissions.ensureAccessibility() else { return }
                settings.deloresSplitDividerEnabled = true
            })
    }

    private var needsAccessibility: Bool {
        !isTrusted && (settings.deloresWindowSnappingEnabled || settings.deloresSplitDividerEnabled)
    }

    private var needsAccessibilitySubtitle: String {
        isTrusted
            ? ""
            : L10n.string("Delores can't read or move other apps' windows until it is granted.")
    }
}
