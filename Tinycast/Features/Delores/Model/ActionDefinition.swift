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
}
