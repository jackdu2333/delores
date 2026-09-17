import Foundation
struct DeloresActionSession: Equatable, Sendable {
    enum Step: Equatable, Sendable { case streaming(String); case capped }
    enum Outcome: Equatable, Sendable { case finished(String); case failed(String); case stopped(String?) }
    static let emptyResult = "模型没有返回任何内容。"
    private var accumulator = DeloresAnswerAccumulator()
    private var terminal: Outcome?
    mutating func ingest(_ delta: String) -> Step? {
        guard terminal == nil else { return nil }
        accumulator.append(delta)
        return accumulator.isCapped ? .capped : .streaming(accumulator.text)
    }
    mutating func complete() -> Outcome { settle(terminal ?? finishedFromAccumulator()) }
    mutating func fail(_ reason: String) -> Outcome { settle(terminal ?? .failed(reason)) }
    mutating func stop() -> Outcome { settle(terminal ?? stoppedFromAccumulator()) }
    private mutating func settle(_ outcome: Outcome) -> Outcome { terminal = outcome; return outcome }
    private func finishedFromAccumulator() -> Outcome {
        let trimmed = accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .failed(Self.emptyResult) : .finished(trimmed)
    }
    private func stoppedFromAccumulator() -> Outcome {
        let kept = accumulator.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return .stopped(kept.isEmpty ? nil : kept)
    }
}
