import Foundation

/// The answer a card is accumulating, and the ceiling it accumulates against.
///
/// A reply arrives one delta at a time, and the card that holds it outlives the reply: it stays on
/// screen while the reader reads it, decides whether to copy it or write it back, and possibly pins
/// the whole surface. A model that runs away therefore grows a string nobody can stop from inside
/// the card, which is why the toolbar this island came from put a ceiling on exactly this and said
/// so when it was reached. That protection did not survive the move — the coordinator appended every
/// delta straight onto a local string — so it lives here instead.
///
/// `Sendable`, and importing nothing beyond `Foundation`, because deciding how much of a reply
/// survives is a policy rather than a view concern — and this is the layer the harness compiles.
struct DeloresAnswerAccumulator: Equatable, Sendable {
    /// How much of a reply the card keeps. A well-behaved model never gets here: the widest reply
    /// this catalog asks for is 2,048 tokens, which is well under a fifth of this even in Chinese.
    static let maxCharacters = 32_768

    /// Appended once, so a capped answer says it stopped rather than quietly losing its tail.
    static let truncationNotice = "\n…（内容过长，已停止累积）"

    private(set) var text = ""
    private(set) var isCapped = false

    mutating func append(_ delta: String) {
        guard !isCapped else { return }
        let room = Self.maxCharacters - text.count
        guard room > 0 else {
            capOff()
            return
        }
        guard delta.count > room else {
            text += delta
            return
        }
        // The delta that crosses the line is cut at the line rather than dropped: the reader keeps
        // what there is room for, and the notice is what marks it as partial.
        text += String(delta.prefix(room))
        capOff()
    }

    private mutating func capOff() {
        guard !isCapped else { return }
        isCapped = true
        text += Self.truncationNotice
    }
}
