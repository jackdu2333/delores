import SwiftUI

/// The Companion Surface: the body that is simply there.
///
/// It is a Surface, not a second workspace, so this pane holds no actions, no history and no model
/// of its own — the footer says so out loud, because that is the boundary a future change is most
/// likely to cross by accident.
struct CompanionSurfaceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.deloresCompanionEnabled) {
                    SettingsRowTitle(.companionSurfaceCompanion, "Enable desktop companion")
                    Text(
                        L10n.string(
                            "The companion that is simply there: it wanders the edge of the display, and reopens your last selection when you double-click it. "
                        ))
                }
                Picker(selection: $settings.deloresCompanionSize) {
                    Text(L10n.string("Regular")).tag(DeloresCompanionShell.Size.regular)
                    Text(L10n.string("Large")).tag(DeloresCompanionShell.Size.large)
                } label: {
                    SettingsRowTitle(.companionSurfaceCompanion, "Size")
                    // Why there are two and no slider: the sprite is authored at a fixed size and drawn
                    // at a whole number of its own pixels. Anything between the two would put a
                    // fractional number of screen pixels under one drawn pixel, which is what shimmers.
                    Text(
                        L10n.string(
                            "Two sizes only, because it is drawn at a whole number of its own pixels."))
                }
                .settingsEnabled(settings.deloresCompanionEnabled)

                Picker(selection: $settings.deloresCompanionKind) {
                    ForEach(DeloresCompanionShell.Kind.allCases, id: \.self) { kind in
                        Text(L10n.text(kind.displayName)).tag(kind)
                    }
                } label: {
                    SettingsRowTitle(.companionSurfaceCompanion, "Pet Creature")
                    Text(
                        L10n.string("Choose which companion creature accompanies you around your display.")
                    )
                }
                .settingsEnabled(settings.deloresCompanionEnabled)
            } header: {
                SettingsSectionHeader(.companionSurfaceCompanion)
            } footer: {
                Text(
                    L10n.string(
                        "The companion is a Surface, not a second chat client: it has no actions, history or model of its own. It hands you to the Context or Command Surface, which own those."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.companionSurface)
    }
}
