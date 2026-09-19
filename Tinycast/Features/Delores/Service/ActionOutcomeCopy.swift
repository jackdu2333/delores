import Foundation

/// The sentences a surface puts around a shared outcome.
///
/// Chrome, and chrome only. That the ceiling cut a reply short, and that a run came back empty, are
/// facts the pure layer records; the wording that reports either of them belongs here, where `L10n` is
/// reachable and the reader's language is known. One home rather than one per surface, because both
/// surfaces that run an action draw the same answer.
enum DeloresActionOutcomeCopy {
    /// Appended to an answer the ceiling cut short. Kept out of the answer itself so copying the
    /// answer out of the card does not carry the notice with it.
    static var truncated: String { L10n.string("\n… truncated — the answer stopped here") }

    /// What a run that produced no answer at all reports, on either surface.
    static var emptyResult: String { L10n.string("The model returned nothing.") }
}
