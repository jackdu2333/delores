/// One `Section` inside a pane, named once so the catalog and the pane cannot disagree: the search
/// result carries the anchor, the pane's `.settingsAnchor(_:)` marks the section it scrolls to.
struct SettingsAnchor: Hashable, Sendable {
    let tab: SettingsTab
    /// The `Section`'s own header text, which is also what a result's breadcrumb reads.
    let title: String
}

// Named `<pane><Section>` throughout, so the constant for a section is always guessable from it.
extension SettingsAnchor {
    /// Everything the palette itself reads: its summons, its ranking, its keys and how it is drawn.
    /// It was the whole of "General", which meant the pane that named the product's everyday
    /// settings was in fact the launcher's.
    static let commandSurfaceGlobalShortcuts = Self(
        tab: .commandSurface, title: "Global Shortcuts")
    static let commandSurfaceSearch = Self(tab: .commandSurface, title: "Search")
    static let commandSurfaceHyperKey = Self(tab: .commandSurface, title: "Hyper Key")
    static let commandSurfaceAppearance = Self(tab: .commandSurface, title: "Appearance")
    /// What the palette does between summons: where it returns to, how it leaves, which keyboard.
    static let commandSurfaceBehaviour = Self(tab: .commandSurface, title: "Behaviour")

    /// The app itself rather than any one Surface: whether it starts, and whether it is in the bar.
    static let generalGeneral = Self(tab: .general, title: "General")

    static let applicationsSearchScopes = Self(tab: .applications, title: "Search Scopes")
    static let applicationsApplications = Self(tab: .applications, title: "Applications")

    static let systemSettingsSystemSettings = Self(tab: .systemSettings, title: "System Settings")

    static let systemActionsSystemActions = Self(tab: .systemActions, title: "System Actions")

    static let commandsCommands = Self(tab: .commands, title: "Commands")

    static let quicklinksQuicklinks = Self(tab: .quicklinks, title: "Quicklinks")
    static let quicklinksCommands = Self(tab: .quicklinks, title: "Commands")
    static let quicklinksBehaviour = Self(tab: .quicklinks, title: "Behaviour")
    static let quicklinksImportExport = Self(tab: .quicklinks, title: "Import & Export")

    static let appleShortcutsAppleShortcuts = Self(tab: .appleShortcuts, title: "Apple Shortcuts")
    static let appleShortcutsShortcuts = Self(tab: .appleShortcuts, title: "Shortcuts")

    static let fallbacksFallbacks = Self(tab: .fallbacks, title: "Fallbacks")

    // These sections belong to the shared Core capability pane, even when one of their consumers is
    // a Surface. The anchor names preserve the feature vocabulary used by their owning views.
    static let aiAI = Self(tab: .aiAndActions, title: "AI")
    static let aiProviders = Self(tab: .aiAndActions, title: "Providers")
    static let aiDefault = Self(tab: .aiAndActions, title: "Default")
    static let aiChat = Self(tab: .aiAndActions, title: "Chat")
    static let aiConversations = Self(tab: .aiAndActions, title: "Conversations")
    static let aiSystemPrompt = Self(tab: .aiAndActions, title: "System prompt")
    static let aiInstalledAI = Self(tab: .aiAndActions, title: "Installed AI")
    static let aiAPIConnections = Self(tab: .aiAndActions, title: "API Connections")
    static let aiMCPServers = Self(tab: .aiAndActions, title: "MCP Servers")
    static let aiCommands = Self(tab: .aiAndActions, title: "Commands")

    static let quickActionsModel = Self(tab: .aiAndActions, title: "Answering model")
    static let quickActionsTranslate = Self(tab: .aiAndActions, title: "Translate")

    static let fileSearchFileSearch = Self(tab: .fileSearch, title: "File Search")
    static let fileSearchCommands = Self(tab: .fileSearch, title: "Commands")
    static let fileSearchSearchScopes = Self(tab: .fileSearch, title: "Search Scopes")
    static let fileSearchIgnorePatterns = Self(tab: .fileSearch, title: "Ignore Patterns")

    static let notesNotes = Self(tab: .notes, title: "Notes")
    static let notesLocation = Self(tab: .notes, title: "Location")
    static let notesCommands = Self(tab: .notes, title: "Commands")

    static let navigationNavigation = Self(tab: .navigation, title: "Navigation")
    static let navigationCommands = Self(tab: .navigation, title: "Commands")
    static let navigationMenuSearch = Self(tab: .navigation, title: "Search Menu Bar Items")

    // Retired window-management commands have no anchors here; Delores keeps only shared placement
    // geometry because Spatial Snap asks it for gap and frame calculations.

    /// The Overview's opening statement, then the three forms; every switch lives in its own pane.
    static let deloresIdentity = Self(tab: .delores, title: "What it is")
    static let deloresSurfaces = Self(tab: .delores, title: "Three ways in")

    /// Keep the enable section's anchor distinct from the action list; its localized display name
    /// is still Selection Toolbar.
    static let contextSurfaceEnable = Self(tab: .contextSurface, title: "Context Surface")
    static let contextSurfaceContextBar = Self(tab: .contextSurface, title: "Selection Toolbar")

    static let companionSurfaceCompanion = Self(tab: .companionSurface, title: "Companion")

    /// Snapping and the divider are the two ways a drag splits a screen, so the pane is named for
    /// what the reader is trying to do rather than for the mechanism that does it. "Window
    /// Snapping" named the mechanism and left a reader looking for 分屏 with nowhere to land.
    static let windowSnappingCapabilities = Self(
        tab: .splitScreen, title: "Split Screen")

    static let clipboardClipboard = Self(tab: .clipboard, title: "Clipboard")
    static let clipboardCommands = Self(tab: .clipboard, title: "Commands")
    static let clipboardHistory = Self(tab: .clipboard, title: "History")
    static let clipboardDisabledApplications = Self(
        tab: .clipboard, title: "Disabled Applications")


    static let permissionsAccessibility = Self(tab: .permissions, title: "Accessibility")

    static let backupExport = Self(tab: .backup, title: "Export")
    static let backupImport = Self(tab: .backup, title: "Import")
    static let backupImportFromRaycast = Self(tab: .backup, title: "Import from Raycast")

    static let aboutAbout = Self(tab: .about, title: "About")
    static let aboutLinks = Self(tab: .about, title: "Links")
}

/// Where a search result lands: a whole section, or one row inside it.
enum SettingsTarget: Hashable, Sendable {
    case section(SettingsAnchor)
    /// The row's visible title, which is also the catalog entry's — they are the same string.
    case row(SettingsAnchor, String)

    var anchor: SettingsAnchor {
        switch self {
        case .section(let anchor), .row(let anchor, _): return anchor
        }
    }

    var tab: SettingsTab { anchor.tab }
}

/// One jump asked for by a search result. The token is what makes picking the same result twice
/// scroll and pulse again, rather than comparing equal and doing nothing.
struct SettingsScrollRequest: Equatable, Sendable {
    let target: SettingsTarget
    let token: Int
}
