import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case fileSearch
    case menuSearch
    case switchWindows
    case uninstall
    case quicklinks

    var id: String { rawValue }

    /// One value at a time into the search field, so ↵ still acts with no rows to select.
    var isArgumentForm: Bool { false }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .uninstall: return "trash"
        case .quicklinks: return Quicklink.sfSymbol
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .ai: return "Ask anything…"
        case .aiHistory: return "Search chats…"
        case .calculatorHistory: return "Do math, convert units, or search your past calculations…"
        case .fileSearch: return "Search files and folders…"
        case .menuSearch: return "Search menu bar items…"
        case .switchWindows: return "Search open windows…"
        case .uninstall: return "Filter files and folders by name…"
        case .quicklinks: return "Search quicklinks…"
        }
    }
}

/// The app a paste lands in, resolved once per show so nothing re-reads it per render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}
