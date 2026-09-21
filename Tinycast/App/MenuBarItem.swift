import SwiftUI

/// Delores's own menu-bar item. It carries no feature state, so no feature can hide or reshape it.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image("DeloresMenuBarIcon")
            .renderingMode(.template)
            .accessibilityLabel(appName)
    }
}

struct MenuBarMenu: View {
    let appName: String

    var body: some View {
        Button(L10n.format("Open %@", appName)) {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        // Read through Observation, so switching the feature off takes the row with it.
        if AppCore.shared.settings.clipboardEnabled {
            Button(L10n.string("Clipboard History")) {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
        }
        Divider()
        Button(L10n.string("Settings...")) { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
        Button(L10n.format("Quit %@", appName)) { NSApp.terminate(nil) }
    }
}
