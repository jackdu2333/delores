import Foundation
struct DeloresActionDefinition: Equatable, Hashable, Sendable, Identifiable {
    enum Backend: Equatable, Hashable, Sendable {
        case languageModel; case translationFramework; case urlTemplate(String)
    }
    enum OutputCap: Equatable, Hashable, Sendable {
        case scaled(max: Int); case compact(max: Int)
        func tokens(selection: String) -> Int {
            let approx = max(selection.count / 3, 64)
            switch self {
            case .scaled(let max): return min(approx * 2, max)
            case .compact(let max): return min(approx, max)
            }
        }
    }
    let id: String; var title: String; var symbol: String; var backend: Backend
    var prompt: String; var rewritesSelection: Bool; var outputCap: OutputCap
    func maxOutputTokens(selection: String) -> Int { outputCap.tokens(selection: selection) }

    /// The reply budget, decided once because both catalogues ask for it and the reader cannot tell
    /// which surface answered them. A digest is asked for short; an answer about the text may take
    /// the room it needs. A ceiling exists at all because the on-device window counts the prompt and
    /// the reply against one budget, so the model needs a share of it named in advance.
    static func outputCap(for id: String) -> OutputCap {
        id == "summarize" ? .compact(max: 512) : .scaled(max: 2_048)
    }
}
