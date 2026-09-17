import Combine
import SwiftUI

/// The Spatial half of Delores: the Companion, window snapping and the split divider.
struct DeloresSpatialSettingsView: View {
    @Environment(AppSettings.self) private var settings

    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle("Enable desktop companion", isOn: $settings.deloresCompanionEnabled)
                    .settingsAnchor(.deloresCompanion)
                Text(
                    "Shows the small companion on the desktop. While it is on it takes over the "
                        + "Spatial surface, and window snapping and the split divider stop."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Companion")
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
                Toggle("Enable window snapping", isOn: snappingBinding)
                    .disabled(settings.deloresCompanionEnabled)
                Toggle("Enable split divider", isOn: dividerBinding)
                    .disabled(settings.deloresCompanionEnabled)
                    .settingsAnchor(.deloresSpatial)
                Text(
                    "Drag a window to the top-center island to choose a layout. Move the pointer "
                        + "onto the seam between two tiled windows to resize them together."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Spatial")
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

    /// Snap and divider both write window frames, so the grant is asked for where the reader turns
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
