enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts,
        fallbacks, ai, quickActions, fileSearch, navigation, windowManagement, delores,
        clipboard, permissions, backup, about
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return L10n.string("General")
        case .applications: return L10n.string("Applications")
        case .systemSettings: return L10n.string("System Settings")
        case .systemActions: return L10n.string("System Actions")
        case .commands: return L10n.string("Commands")
        case .quicklinks: return L10n.string("Quicklinks")
        case .appleShortcuts: return L10n.string("Apple Shortcuts")
        case .fallbacks: return L10n.string("Fallbacks")
        case .ai: return L10n.string("AI")
        case .quickActions: return L10n.string("Quick Actions")
        case .fileSearch: return L10n.string("File Search")
        case .navigation: return L10n.string("Navigation")
        case .windowManagement: return L10n.string("Window Management")
        case .delores: return L10n.string("Delores")
        case .clipboard: return L10n.string("Clipboard")
        case .permissions: return L10n.string("Permissions")
        case .backup: return L10n.string("Backup")
        case .about: return L10n.string("About")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d"
        case .fallbacks: return "arrow.turn.down.right"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .delores: return "sparkles"
        case .clipboard: return "doc.on.clipboard"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

/// Declaration order is display order; not `.Section`, which would shadow SwiftUI's `Section`.
enum SettingsSection: CaseIterable, Identifiable {
    case general, launcher, features, advanced
    /// See `SettingsTab.id`: distinct types keep the two namespaces from colliding.
    var id: Self { self }

    var title: String {
        switch self {
        case .general: return L10n.string("General")
        case .launcher: return L10n.string("Launcher")
        case .features: return L10n.string("Features")
        case .advanced: return L10n.string("Advanced")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .permissions]
        case .launcher:
            return [
                .applications, .systemSettings, .systemActions, .commands, .quicklinks,
                .appleShortcuts, .fallbacks
            ]
        case .features:
            return [
                .ai, .quickActions, .fileSearch, .navigation,
                .windowManagement, .delores, .clipboard
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
