import Foundation

enum DeloresContextAction: Hashable, Identifiable, Sendable {
    case quickAction(BuiltInQuickAction)
    case ask

    init(_ builtIn: BuiltInQuickAction) {
        self = .quickAction(builtIn)
    }

    var builtIn: BuiltInQuickAction? {
        guard case .quickAction(let builtIn) = self else { return nil }
        return builtIn
    }

    var id: String {
        switch self {
        case .quickAction(let builtIn): return builtIn.rawValue
        case .ask: return "ask"
        }
    }

    var title: String {
        switch self {
        case .quickAction(let builtIn): return builtIn.title
        case .ask: return "Ask AI"
        }
    }

    var symbol: String {
        switch self {
        case .quickAction(let builtIn): return builtIn.symbol
        case .ask: return "sparkles"
        }
    }

    /// Only an explicit Ask action grows into the Command Surface. Built-in actions stay native.
    var requiresChatHandoff: Bool {
        if case .ask = self { return true }
        return false
    }

    /// What the opened card says while the answer is still on its way.
    var progressTitle: String {
        switch self {
        case .quickAction(let builtIn): return builtIn.progressTitle
        case .ask: return "Opening AI Chat"
        }
    }

    static let defaults: [DeloresContextAction] = [
        DeloresContextAction(.translate),
        DeloresContextAction(.summarize),
        DeloresContextAction(.rewrite),
        DeloresContextAction(.fixGrammar),
        .ask
    ]

    /// The first catalog slice is fixed order; only the explicit Chat escalation depends on AI.
    static func available(aiEnabled: Bool) -> [Self] {
        defaults.filter { aiEnabled || !$0.requiresChatHandoff }
    }
}
