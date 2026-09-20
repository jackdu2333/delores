import SwiftUI

/// The product's own page: what Delores is, and the three ways it can be reached.
///
/// It exists because Settings used to open on the launcher's shortcut, which read as "Delores is a
/// launcher". Everything here states a fact and offers a way to the pane that owns the switch —
/// **no setting lives in this file.** A row that could be toggled here would be a second place to
/// change something, and the panes below are the only owners.
///
/// The copy speaks to the reader's situation, not to the design. A previous pass described each
/// form by what it is made of — "the smallest useful set of actions", "a capability belongs to
/// Delores rather than to a form" — which is a specification, and tells a reader nothing about
/// when they would want it.
struct DeloresOverviewView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Form {
            Section {
                surface(
                    tab: .commandSurface, symbol: "command",
                    title: L10n.string("Command Surface"),
                    subtitle: L10n.string(
                        "A thought crosses your mind — find something, open something, just ask. Press the shortcut and it is there; it leaves when you are done."
                    ),
                    state: L10n.string("Always available"))
                surface(
                    tab: .contextSurface, symbol: "text.cursor",
                    title: L10n.string("Context Surface"),
                    subtitle: L10n.string(
                        "You are reading something you do not quite follow. Select it — a few actions appear at the top of the screen, and the answer lands right where you are."
                    ),
                    state: settings.quickActionsEnabled ? L10n.string("On") : L10n.string("Off"))
                surface(
                    tab: .companionSurface, symbol: "pawprint",
                    title: L10n.string("Companion Surface"),
                    subtitle: L10n.string(
                        "It is simply there, and it never asks you for anything. The moment you remember it, double-click and your last selection comes back."
                    ),
                    state: settings.deloresCompanionEnabled
                        ? L10n.string("On") : L10n.string("Off"))
            } header: {
                SettingsSectionHeader(.deloresSurfaces)
            } footer: {
                Text(
                    L10n.string(
                        "Three ways in, one Delores. You never have to pick one — what you are doing has already picked it for you."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.delores)
    }

    /// A statement about one Surface, and the way to the pane that owns its switches.
    private func surface(
        tab: SettingsTab, symbol: String, title: String, subtitle: String, state: String
    ) -> some View {
        Button {
            navigation.select(tab)
        } label: {
            SettingsRow(title: title, subtitle: subtitle, subtitleLineLimit: 4) {
                SymbolImage(name: symbol, size: Theme.Size.settingsRowIcon)
                    .frame(width: Theme.Size.settingsRowIcon)
            } trailing: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(state)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityHint(L10n.format("Opens the %@ settings", title))
    }
}
