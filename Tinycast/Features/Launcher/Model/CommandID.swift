import Foundation

/// Built-in launcher actions, surfaced alongside the user-authored ones.
enum CommandID: String, CaseIterable, Sendable {
    case aiChat = "command:ai-chat"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case openInBrowser = "command:open-in-browser"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case settings = "command:settings"
    case about = "command:about"
    case quit = "command:quit"

    var name: String {
        switch self {
        case .aiChat: return "AI Chat"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.title
        case .rewrite: return BuiltInQuickAction.rewrite.title
        case .translate: return BuiltInQuickAction.translate.title
        case .summarize: return BuiltInQuickAction.summarize.title
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .openInBrowser: return "Open in Browser"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .settings: return "Settings"
        case .about: return "About Delores"
        case .quit: return "Quit Delores"
        }
    }

    var sfSymbol: String {
        switch self {
        case .aiChat: return "sparkles"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.symbol
        case .rewrite: return BuiltInQuickAction.rewrite.symbol
        case .translate: return BuiltInQuickAction.translate.symbol
        case .summarize: return BuiltInQuickAction.summarize.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .openInBrowser: return "globe"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .quit: return "power"
        }
    }

    /// Exhaustive, so a fifth shipped action cannot reach the launcher without a row here.
    init(_ action: BuiltInQuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .translate: self = .translate
        case .summarize: self = .summarize
        }
    }

    var builtInQuickAction: BuiltInQuickAction? {
        switch self {
        case .fixGrammar: return .fixGrammar
        case .rewrite: return .rewrite
        case .translate: return .translate
        case .summarize: return .summarize
        default: return nil
        }
    }

    /// Common descriptions that remain useful until the user has chosen a competing result.
    var boostedTerms: Set<String> {
        self == .aiChat ? ["ai", "chat"] : []
    }

    /// Built-ins that may fill empty-query Suggestions when no recent use has filled them.
    var suggestionPriority: Int? {
        switch self {
        case .aiChat: 90
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .createNote: 60
        case .switchWindows: 50
        case .searchMenuItems: 40
        case .createQuicklink: 30
        case .searchNotes: 20
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
