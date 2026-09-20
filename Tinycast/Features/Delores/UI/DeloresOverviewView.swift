import SwiftUI

/// The product's own page: what Delores is, and the three ways it can be reached.
///
/// It exists because Settings used to open on the launcher's shortcut, which read as "Delores is a
/// launcher". Everything here states a fact and offers a way to the pane that owns the switch —
/// **no setting lives in this file.** A row that could be toggled here would be a second place to
/// change something, and the panes below are the only owners.
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
                        "Summoned by its shortcut when you want to start or find something. It is the most complete form: search, commands, Chat and Settings."
                    ),
                    state: L10n.string("Always available"))
                surface(
                    tab: .contextSurface, symbol: "text.cursor",
                    title: L10n.string("Context Surface"),
                    subtitle: L10n.string(
                        "Appears at the top of the screen for the text you have already selected, and offers the smallest useful set of actions for it."
                    ),
                    state: settings.quickActionsEnabled ? L10n.string("On") : L10n.string("Off"))
                surface(
                    tab: .companionSurface, symbol: "pawprint",
                    title: L10n.string("Companion Surface"),
                    subtitle: L10n.string(
                        "Stays on the desktop so Delores can be found without being summoned: a glance, your last selection, a hand-off."
                    ),
                    state: settings.deloresCompanionEnabled
                        ? L10n.string("On") : L10n.string("Off"))
            } header: {
                SettingsSectionHeader(.deloresSurfaces)
            } footer: {
                Text(
                    L10n.string(
                        "One core, three forms. A capability belongs to Delores rather than to a form, so it is configured once however many forms can reach it."
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
            SettingsRow(title: title, subtitle: subtitle, subtitleLineLimit: 3) {
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
