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
                Picker(selection: $settings.deloresCompanionMode) {
                    Text(L10n.string("Off")).tag(DeloresCompanionMode.off)
                    Text(L10n.string("Delores desktop pet")).tag(DeloresCompanionMode.delores)
                    Text(L10n.string("Codex desktop pet")).tag(DeloresCompanionMode.codex)
                } label: {
                    SettingsRowTitle(.companionSurfaceCompanion, "Desktop companion mode")
                    Text(L10n.string("Choose which desktop pet anchors Delores on your screen."))
                }
                Text(
                    L10n.string(
                        "Codex mode uses the Codex pet as an external anchor; hidden pets fall back to the menu bar."
                    ))
                .font(.caption)
                .foregroundStyle(.secondary)

                Group {
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
                }
                .settingsEnabled(settings.deloresCompanionMode == .delores)
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
