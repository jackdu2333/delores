enum SettingsTab: CaseIterable, Identifiable {
    // Declaration order carries no meaning: `SettingsSection` states the sidebar's order. The
    // cases are grouped here only so a reader can see which side of the product each one serves —
    // the three Surfaces, what the launcher lists, the shared capabilities, then the app itself.
    case delores, commandSurface, contextSurface, companionSurface,
        applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts, fallbacks,
        windowManagement, windowSnapping, ai, quickActions, clipboard, notes, fileSearch, navigation,
        general, permissions, backup, about
    /// The case, never an index: a selectable `List` flattens section and row IDs together.
    var id: Self { self }

    var title: String {
        switch self {
        // The pane answers "what is Delores", so it is named for that rather than for the group.
        case .delores: return L10n.string("Overview")
        case .commandSurface: return L10n.string("Command Surface")
        case .contextSurface: return L10n.string("Context Surface")
        case .companionSurface: return L10n.string("Companion Surface")
        case .applications: return L10n.string("Applications")
        case .systemSettings: return L10n.string("System Settings")
        case .systemActions: return L10n.string("System Actions")
        case .commands: return L10n.string("Commands")
        case .quicklinks: return L10n.string("Quicklinks")
        case .appleShortcuts: return L10n.string("Apple Shortcuts")
        case .fallbacks: return L10n.string("Fallbacks")
        case .windowManagement: return L10n.string("Window Management")
        case .windowSnapping: return L10n.string("Window Snapping")
        case .ai: return L10n.string("AI")
        case .quickActions: return L10n.string("Quick Actions")
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

    /// One symbol per pane, and no two panes share one: the Overview and AI both used to draw
    /// `sparkles`, so the sidebar had no way to tell them apart.
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
        case .windowManagement: return "macwindow"
        case .windowSnapping: return "rectangle.split.2x1"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
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
/// The axis is the reader's situation, not the code's ownership. The three Surfaces *are* the
/// product, so they lead and the Overview answers "what is this" before any switch does. A
/// capability belongs to the core rather than to a Surface, so it is listed once under one heading
/// instead of being copied into whichever pane happens to expose it. What the launcher lists is the
/// Command Surface's own contents, which is why the category panes sit inside it rather than
/// beside the capabilities they read.
enum SettingsSection: CaseIterable, Identifiable {
    case delores, command, context, companion, capabilities, system
    /// See `SettingsTab.id`: distinct types keep the two namespaces from colliding.
    var id: Self { self }

    var title: String {
        switch self {
        case .delores: return L10n.string("Delores")
        case .command: return L10n.string("Command Surface")
        case .context: return L10n.string("Context Surface")
        case .companion: return L10n.string("Companion Surface")
        case .capabilities: return L10n.string("Capabilities")
        case .system: return L10n.string("System")
        }
    }

    var tabs: [SettingsTab] {
        switch self {
        case .delores:
            return [.delores]
        case .command:
            return [
                .commandSurface, .applications, .systemSettings, .systemActions, .commands,
                .quicklinks, .appleShortcuts, .fallbacks
            ]
        case .context:
            return [.contextSurface]
        case .companion:
            return [.companionSurface]
        case .capabilities:
            return [
                .windowManagement, .windowSnapping, .ai, .quickActions, .clipboard, .notes,
                .fileSearch, .navigation
            ]
        case .system:
            return [.general, .permissions, .backup, .about]
        }
    }
}
