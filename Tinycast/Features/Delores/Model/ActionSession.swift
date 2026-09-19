import Foundation
struct DeloresActionSession: Equatable, Sendable {
    enum Step: Equatable, Sendable { case streaming(String); case capped }
    /// Why a run ended without an answer.
    ///
    /// Typed rather than a sentence: the pure layer carries no language, and the caller that has to
    /// tell "the model said nothing" from what a provider reported can say so without comparing copy.
    enum Failure: Equatable, Sendable {
        /// The reply came back empty once trimmed.
        case emptyResult
        /// The provider or the transport said so, in its own words.
        case reason(String)
    }
    /// Where `capped` is set, the ceiling cut the reply short, so the surface that draws it can mark
    /// it partial in the reader's language rather than the answer carrying the notice itself.
    enum Outcome: Equatable, Sendable {
        case finished(String, capped: Bool); case failed(Failure); case stopped(String?)
    }
    private var accumulator = DeloresAnswerAccumulator()
    private var terminal: Outcome?
    mutating func ingest(_ delta: String) -> Step? {
        guard terminal == nil else { return nil }
        accumulator.append(delta)
        return accumulator.isCapped ? .capped : .streaming(accumulator.text)
    }
    mutating func complete() -> Outcome { settle(terminal ?? finishedFromAccumulator()) }
    mutating func fail(_ reason: String) -> Outcome { settle(terminal ?? .failed(.reason(reason))) }
    mutating func stop() -> Outcome { settle(terminal ?? stoppedFromAccumulator()) }
    private mutating func settle(_ outcome: Outcome) -> Outcome { terminal = outcome; return outcome }
    private func finishedFromAccumulator() -> Outcome {
        let trimmed = accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? .failed(.emptyResult) : .finished(trimmed, capped: accumulator.isCapped)
    }
    private func stoppedFromAccumulator() -> Outcome {
        let kept = accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .stopped(kept.isEmpty ? nil : kept)
    }
}
