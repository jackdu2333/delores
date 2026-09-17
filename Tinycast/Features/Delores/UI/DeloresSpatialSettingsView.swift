import Combine
import SwiftUI

/// The Delores pane: the Companion Surface, and the two window capabilities behind it.
struct DeloresSpatialSettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.deloresCompanionEnabled) {
                    SettingsRowTitle(.deloresCompanion, "Enable desktop companion")
                    Text(
                        "The companion that is simply there: patrols the edge of the display, and "
                            + "reopens your last selection when you double-click it. While it is on, "
                            + "window snapping and the split divider stay off."
                    )
                }
            } header: {
                SettingsSectionHeader(.deloresCompanion)
            } footer: {
                Text(
                    "The companion is a Surface, not a second chat client: it has no actions, "
                        + "history or model of its own. It hands you to the Context or Command "
                        + "Surface, which own those."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                if needsAccessibility {
                    SettingsRow(
                        title: "Accessibility permission required",
                        subtitle: needsAccessibilitySubtitle
                    ) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.destructive)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    }
                }
                Toggle(isOn: snappingBinding) {
                    SettingsRowTitle(.deloresSpatial, "Enable window snapping")
                    Text(
                        "Drag a window up to the island at the top of the display, and drop it on "
                            + "the layout you want."
                    )
                }
                .disabled(settings.deloresCompanionEnabled)
                Toggle(isOn: dividerBinding) {
                    SettingsRowTitle(.deloresSpatial, "Enable split divider")
                    Text(
                        "Move the pointer onto the seam between two tiled windows to resize them "
                            + "together."
                    )
                }
                .disabled(settings.deloresCompanionEnabled)
            } header: {
                SettingsSectionHeader(.deloresSpatial)
            } footer: {
                Text(
                    "Both read and move other apps' windows through the same Accessibility "
                        + "permission Tinycast uses to paste. Neither is enabled by default, and "
                        + "neither is restored from a settings backup."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.delores)
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
            : "Tinycast can't read or move other apps' windows until it is granted."
    }
}
