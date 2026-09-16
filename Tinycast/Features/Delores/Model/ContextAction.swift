import Foundation

struct DeloresContextAction: Hashable, Identifiable, Sendable {
    let builtIn: BuiltInQuickAction

    init(_ builtIn: BuiltInQuickAction) {
        self.builtIn = builtIn
    }

    var id: String { builtIn.rawValue }
    var title: String { builtIn.title }
    var symbol: String { builtIn.symbol }

    static let defaults: [DeloresContextAction] = [
        DeloresContextAction(.translate),
        DeloresContextAction(.summarize),
        DeloresContextAction(.rewrite),
        DeloresContextAction(.fixGrammar)
    ]
}
