import SwiftUI

@main
struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only on change, avoiding a scene ⇄ binding loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // Channel-aware: "Tinycast", "Tinycast Dev", or "Tinycast Beta".
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L10n.format("About %@", appName)) { AppCore.shared.settingsCoordinator.showAbout() }
        }
        CommandGroup(replacing: .appSettings) {
            Button(L10n.string("Settings…")) { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button(L10n.string("Close Settings")) { AppCore.shared.settingsCoordinator.closeSettings() }
                .keyboardShortcut("q")
        }
    }
}
