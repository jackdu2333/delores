import Foundation

/// Ordered like a bare backspace: a screen is only left once the search field is empty.
enum PaletteEscapeAction: Equatable {
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case goBack
    case hidePalette

    static func resolve(
        menuOpen: Bool, argumentFocused: Bool, query: String, mode: PaletteMode,
        canGoBack: Bool, behavior: EscapeKeyBehavior
    ) -> Self {
        if menuOpen { return .closeMenu }
        // An argument field is a step deeper than the query, so it is left before anything clears.
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        guard behavior == .navigateBackOrClose else { return .hidePalette }
        return canGoBack ? .goBack : .hidePalette
    }
}
