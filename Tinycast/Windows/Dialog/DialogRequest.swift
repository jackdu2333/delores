import Foundation

/// One button; role decides its colour, severity living separately in `DialogTone`.
struct DialogAction {
    enum Role {
        case standard
        case destructive
        case cancel
    }

    let title: String
    var role: Role = .standard
}

/// How serious a dialog is; it tints the glyph but never picks one. See docs/ui.md.
enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}

extension DialogAction {
    /// A button whose title is chrome: an English source string that is also its catalog key.
    ///
    /// The plain initializer stays the verbatim path, so a title the reader supplied — a file name, a
    /// quicklink they named, a provider's own error — renders as written even when it happens to match
    /// a key. Which of the two a title is has to be said where it is written, because nothing
    /// downstream can tell a filename from a sentence.
    static func chrome(_ title: String, role: Role = .standard) -> DialogAction {
        DialogAction(title: L10n.text(title), role: role)
    }
}

struct DialogRequest {
    let title: String
    var message: String?
    /// Nil where the title already names the subject and a glyph would repeat it.
    let symbol: String?
    var tone: DialogTone = .neutral
    var actions: [DialogAction]
    /// The button ↵ fires, normally the primary action.
    var defaultIndex: Int
    /// Resolved when the dialog goes without a choice: Esc, or losing key status.
    var cancelIndex: Int
    /// The caller reads the result back out of the state object it passed in.
    var accessory: DialogAccessory?
}

/// A dialog carries at most one control, so the cases are exclusive by construction.
enum DialogAccessory {
    case volume(VolumeState)

    /// Whether ←/→/↑/↓ belong to the control rather than to whatever has focus inside it.
    var claimsArrowKeys: Bool {
        if case .volume = self { return true }
        return false
    }
}
