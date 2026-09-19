import Foundation

enum QuickAction: Hashable, Identifiable, Sendable {
    case builtIn(BuiltInQuickAction)
    case custom(CustomQuickAction)

    static let fixGrammar = QuickAction.builtIn(.fixGrammar)
    static let rewrite = QuickAction.builtIn(.rewrite)
    static let translate = QuickAction.builtIn(.translate)
    static let summarize = QuickAction.builtIn(.summarize)

    static let allBuiltIn: [QuickAction] = BuiltInQuickAction.allCases.map(QuickAction.builtIn)

    var id: String {
        switch self {
        case .builtIn(let action): return action.rawValue
        case .custom(let action): return action.entryID
        }
    }

    var builtInAction: BuiltInQuickAction? {
        guard case .builtIn(let action) = self else { return nil }
        return action
    }

    var customAction: CustomQuickAction? {
        guard case .custom(let action) = self else { return nil }
        return action
    }

    var title: String {
        switch self {
        case .builtIn(let action): return action.title
        case .custom(let action): return action.name
        }
    }

    var symbol: String {
        switch self {
        case .builtIn(let action): return action.symbol
        case .custom(let action): return action.symbol
        }
    }

    var progressTitle: String {
        switch self {
        case .builtIn(let action): return action.progressTitle
        case .custom(let action): return action.name + "…"
        }
    }

    var alwaysPreviews: Bool { builtInAction?.alwaysPreviews ?? false }

    var showsDiff: Bool { builtInAction?.showsDiff ?? false }

    var usesTranslationFramework: Bool { builtInAction?.usesTranslationFramework ?? false }

    /// The descriptor for either kind, so a caller learns an action's backend, budget and result
    /// facts from one type instead of branching on which catalogue the row came from.
    func definition(
        override: String? = nil, translatingInto targetLanguageName: String? = nil
    ) -> DeloresActionDefinition {
        switch self {
        case .builtIn(let action):
            return action.definition(override: override, translatingInto: targetLanguageName)
        case .custom(let action):
            return DeloresActionDefinition(
                id: action.entryID, title: action.name, symbol: action.symbol,
                backend: DeloresActionDefinition.defaultBackend(for: action.entryID),
                prompt: QuickActionPrompt.instructions(
                    for: self, override: override, translatingInto: targetLanguageName),
                // The reader wrote instructions, not permission to overwrite their document. Same
                // answer the Context catalogue gives a row they wrote.
                rewritesSelection: false,
                outputCap: DeloresActionDefinition.outputCap(for: action.entryID))
        }
    }
}
