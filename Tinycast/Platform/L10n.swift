import Foundation

/// Visible chrome copy for menus and Settings. English is the source; zh-Hans comes from the catalog.
enum L10n {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// Runtime English source strings — enum titles, section names, catalog rows.
    static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    static func format(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), arguments: args)
    }
}
