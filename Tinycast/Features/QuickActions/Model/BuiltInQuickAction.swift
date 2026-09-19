import Foundation

enum BuiltInQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixGrammar
    case rewrite
    case translate
    case summarize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        }
    }

    var symbol: String {
        switch self {
        case .fixGrammar: return "textformat"
        case .rewrite: return "wand.and.sparkles"
        case .translate: return "translate"
        case .summarize: return "text.line.3.summary"
        }
    }

    var progressTitle: String {
        switch self {
        case .fixGrammar: return "Fixing Grammar…"
        case .rewrite: return "Rewriting…"
        case .translate: return "Translating…"
        case .summarize: return "Summarizing…"
        }
    }

    /// The presentation hints that are facts about the row rather than preferences. `replacesDirectly
    /// ByDefault` is deliberately not one: it is a starting point the reader can move, which is why
    /// it stays a read of its own.
    private var presentation: Set<DeloresActionDefinition.Presentation> {
        var found: Set<DeloresActionDefinition.Presentation> = []
        if self == .summarize { found.insert(.alwaysPreviews) }
        if self == .fixGrammar || self == .rewrite { found.insert(.showsDiff) }
        return found
    }

    var alwaysPreviews: Bool { presentation.contains(.alwaysPreviews) }

    var replacesDirectlyByDefault: Bool { self == .fixGrammar }

    var showsDiff: Bool { presentation.contains(.showsDiff) }

    /// Apple's translator answers this id unless the reader bound a model to it. Read off the shared
    /// policy rather than restated, so the two catalogues cannot disagree about the default.
    var usesTranslationFramework: Bool {
        DeloresActionDefinition.defaultBackend(for: id) == .translationFramework
    }

    /// The same descriptor the Context catalogue's rows produce: one id, one backend, one budget,
    /// whichever surface asked.
    ///
    /// The prompt is an argument, because the Command Surface may be holding a reader's override or a
    /// target language the Context Surface never has. Everything else is the shared policy, which is
    /// the point of producing a descriptor rather than reading the same flags per surface.
    func definition(
        override: String? = nil, translatingInto targetLanguageName: String? = nil
    ) -> DeloresActionDefinition {
        DeloresActionDefinition(
            id: id, title: title, symbol: symbol,
            backend: DeloresActionDefinition.defaultBackend(for: id),
            prompt: QuickActionPrompt.instructions(
                for: self, override: override, translatingInto: targetLanguageName),
            outputCap: DeloresActionDefinition.outputCap(for: id),
            presentation: presentation)
    }
}
