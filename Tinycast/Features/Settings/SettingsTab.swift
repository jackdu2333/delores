enum SettingsTab: CaseIterable, Identifiable {
    // Declaration order carries no meaning: `SettingsSection` states the sidebar's order. The
    // cases are grouped here only so a reader can see which side of the product each one serves —
    // the three Surfaces, search-box configuration, then the app itself.
    case delores, commandSurface, contextSurface, companionSurface,
        applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts, fallbacks,
        splitScreen, clipboard, notes, fileSearch, navigation,
        general, permissions, backup, about
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        // The pane answers "what is Delores", so it is named for that rather than for the group.
        case .delores: return L10n.string("Overview")
        case .commandSurface: return L10n.string("Search Box")
        case .contextSurface: return L10n.string("Context Surface")
        case .companionSurface: return L10n.string("Companion Surface")
        case .applications: return L10n.string("Applications")
        case .systemSettings: return L10n.string("System Settings")
        case .systemActions: return L10n.string("System Actions")
        case .commands: return L10n.string("Commands")
        case .quicklinks: return L10n.string("Quicklinks")
        case .appleShortcuts: return L10n.string("Apple Shortcuts")
        case .fallbacks: return L10n.string("Fallbacks")
        // Named for what the reader is trying to do: it is the pane that answers 分屏, and the
        // window management it used to share the pane with is no longer offered at all.
        case .splitScreen: return L10n.string("Split Screen")
        case .clipboard: return L10n.string("Clipboard")
        case .notes: return L10n.string("Notes")
        case .fileSearch: return L10n.string("File Search")
        case .navigation: return L10n.string("Navigation")
        case .general: return L10n.string("General")
        case .permissions: return L10n.string("Permissions")
        case .backup: return L10n.string("Backup")
        case .about: return L10n.string("About")
        }
    }

    /// One symbol per pane, and no two panes share one.
    var systemImage: String {
        switch self {
        case .delores: return "house"
        case .commandSurface: return "command"
        case .contextSurface: return "text.cursor"
        case .companionSurface: return "pawprint"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d"
        case .fallbacks: return "arrow.turn.down.right"
        case .splitScreen: return "rectangle.split.2x1"
        case .clipboard: return "doc.on.clipboard"
        case .notes: return "text.page"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .navigation: return "arrow.left.arrow.right"
        case .general: return "switch.2"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

/// Declaration order is display order; not `.Section`, which would shadow SwiftUI's `Section`.
///
/// The axis is the reader's situation, not the code's ownership. The three Surfaces lead, and every
/// search-box extension sits under one configuration block rather than competing with them.
enum SettingsSection: CaseIterable, Identifiable {
    case delores, context, companion, searchBox, system
    /// See `SettingsTab.id`: distinct types keep the two namespaces from colliding.
    var id: Self { self }

    var title: String {
        switch self {
        case .delores: return L10n.string("Overview")
        case .context: return L10n.string("Context Surface")
        case .companion: return L10n.string("Companion Surface")
        case .searchBox: return L10n.string("Search Box Settings")
        case .system: return L10n.string("System")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .delores:
            return [.delores]
        case .searchBox:
            return [
                .commandSurface, .applications, .systemSettings, .systemActions, .commands,
                .quicklinks, .appleShortcuts, .fallbacks,
                .splitScreen, .clipboard, .notes, .fileSearch, .navigation
            ]
        case .context:
            return [.contextSurface]
        case .companion:
            return [.companionSurface]
        case .system:
            return [.general, .permissions, .backup, .about]
        }
    }
}
