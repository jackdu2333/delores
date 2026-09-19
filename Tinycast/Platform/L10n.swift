import Foundation

/// Visible chrome copy for menus and Settings. English is the source; zh-Hans comes from the catalog.
///
/// Two entry points, and the difference is what they promise. `string` and `format` take a literal and
/// state that the literal *is* a catalog key — so a missing entry is a defect, and
/// `./Scripts/check-localization.js` fails on one. `text` takes a String that may or may not be a key,
/// which is what a caller needs when the value only exists at runtime, or when it is not chrome at all
/// and merely has to reach a localizable position unchanged.
enum L10n {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    /// A value that reaches a localizable position without being a literal: an enum's title, a catalog
    /// row's name arriving as a String, or a placeholder naming a command or a URL. Resolved the same
    /// way, so a value that is not a key renders exactly as given.
    static func text(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    static func format(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), arguments: args)
    }
}
