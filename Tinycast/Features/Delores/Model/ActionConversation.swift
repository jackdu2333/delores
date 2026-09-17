import Foundation
struct DeloresActionConversation: Equatable, Sendable {
    static let maxTurnMessages = 20
    static let maxTurnCharacters = 8_000
    struct Turn: Equatable, Sendable {
        enum Role: Equatable, Sendable { case user, assistant }
        var role: Role; var text: String
    }
    struct CurrentTurn: Equatable, Sendable { var question: String; var answer: String }
    private(set) var current: CurrentTurn?
    private(set) var settled: [Turn] = []
    mutating func begin(question: String) { current = CurrentTurn(question: question, answer: "") }
    mutating func noteAnswer(_ text: String) { current?.answer = text }
    mutating func restart() { settled = []; current = nil }
    mutating func commitForFollowUp() {
        guard let current, !current.answer.isEmpty else { return }
        settled.append(Turn(role: .user, text: current.question))
        settled.append(Turn(role: .assistant, text: current.answer))
        settled = Self.kept(settled)
    }
    static func kept(_ turns: [Turn]) -> [Turn] {
        let clipped = turns.map { Turn(role: $0.role, text: $0.text.count > maxTurnCharacters ? String($0.text.prefix(maxTurnCharacters)) : $0.text) }
        let excess = clipped.count - maxTurnMessages
        guard excess > 0 else { return clipped }
        return Array(clipped.dropFirst(excess % 2 == 0 ? excess : excess + 1))
    }
}
