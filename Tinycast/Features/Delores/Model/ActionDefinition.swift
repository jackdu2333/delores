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
    /// A hint about presenting the reply, and nothing more: the Context Surface ignores every one of
    /// them, and none says what an action *is*. They sit here only so the Command catalogue has one
    /// place to state them, and they are all facts a setting cannot move.
    enum Presentation: Hashable, Sendable {
        /// Shown for reading before it can be applied, and the reader cannot turn that off.
        case alwaysPreviews
        /// Worth a diff before it lands, since it rewrites prose the reader wrote.
        case showsDiff
    }
    let id: String; var title: String; var symbol: String; var backend: Backend
    /// The whole of what is sent, the rules that cannot be dropped included — not just the task
    /// sentence. Both catalogues fill it with what their own execution would send, so taking a
    /// descriptor and sending it cannot quietly leave the safety rules behind.
    var prompt: String
    var outputCap: OutputCap
    var presentation: Set<Presentation> = []
    func maxOutputTokens(selection: String) -> Int { outputCap.tokens(selection: selection) }

    /// The reply budget, decided once because both catalogues ask for it and the reader cannot tell
    /// which surface answered them. A digest is asked for short; an answer about the text may take
    /// the room it needs. A ceiling exists at all because the on-device window counts the prompt and
    /// the reply against one budget, so the model needs a share of it named in advance.
    static func outputCap(for id: String) -> OutputCap {
        id == "summarize" ? .compact(max: 512) : .scaled(max: 2_048)
    }

    /// The backend an id runs on when nothing has chosen otherwise.
    ///
    /// `translate` is the one id both catalogues ship that Apple's translator can perform, and it is
    /// the default because that translator is free and better at the job; a model answers it only when
    /// the reader binds one to the id. Every other id is a prompt, so only a model can answer it.
    static func defaultBackend(for id: String) -> Backend {
        id == "translate" ? .translationFramework : .languageModel
    }

    /// One id, two backends: which of them answers `translate` on this Mac.
    ///
    /// The reader's own binding wins. Otherwise Apple's translator answers whenever it has the pair —
    /// a pair it merely supports counts, because falling through to a provider here would bill the
    /// reader for a language they can download for nothing.
    static func translationRoute(
        hasModelBinding: Bool, availability: DeloresTranslationAvailability
    ) -> DeloresTranslationRoute {
        guard !hasModelBinding else { return .languageModel }
        switch availability {
        case .installed, .supported: return .translationFramework
        case .unsupported, .undetectable: return .languageModel
        }
    }
}

/// What Apple's translator says about one pair, asked before anything runs.
///
/// `Translation`'s own status cannot come into `Model/`, so the router is handed the part of it that
/// decides: whether the pair is ready, merely available, or beyond the framework — and whether the
/// text's own language could be told at all, which is a case the framework reports as nothing.
enum DeloresTranslationAvailability: Equatable, Sendable {
    case installed, supported, unsupported, undetectable
}

/// Which of the two answers one press.
enum DeloresTranslationRoute: Equatable, Sendable {
    case translationFramework, languageModel
}
