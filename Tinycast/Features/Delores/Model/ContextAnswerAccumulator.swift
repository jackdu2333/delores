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
/// Reaching the ceiling is *reported* rather than written into the answer: `isCapped` is a fact, and
/// the sentence that states it is chrome, so it belongs to the surface that draws the card rather
/// than to the text the reader may copy out of it.
///
/// `Sendable`, and importing nothing beyond `Foundation`, because deciding how much of a reply
/// survives is a policy rather than a view concern — and this is the layer the harness compiles.
struct DeloresAnswerAccumulator: Equatable, Sendable {
    /// How much of a reply the card keeps. A well-behaved model never gets here: the widest reply
    /// this catalog asks for is 2,048 tokens, which is well under a fifth of this even in Chinese.
    static let maxCharacters = 32_768

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
        // what there is room for, and `isCapped` is what marks it as partial.
        text += String(delta.prefix(room))
        capOff()
    }

    private mutating func capOff() {
        isCapped = true
    }
}
