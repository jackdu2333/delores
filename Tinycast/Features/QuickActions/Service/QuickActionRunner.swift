import AppKit

/// Reads the selection and transforms it; replacing the text is the coordinator's call, not this.
@MainActor
final class QuickActionRunner {
    /// The ceiling lives here, not at the provider, where it returns as an opaque context error.
    static let maxSelectionBytes = 32_768

    /// A borrowed ⌘C synthesises a keystroke into somebody's app, so it is never the first try.
    static func selection(
        in targetApp: NSRunningApplication?, using injector: TextInjector
    ) async throws -> String {
        // A shortcut press is an explicit gesture, so it may prompt, as snippet expansion does.
        guard Permissions.ensureAccessibility() else { throw QuickActionFailure.needsAccessibility }
        guard let targetApp,
            targetApp.bundleIdentifier != Bundle.main.bundleIdentifier
        else { throw QuickActionFailure.noTarget }

        let reported = AccessibilityText.read(in: targetApp)
        if case .text(let text) = reported { return try accepted(text) }
        if let copied = await injector.copySelection(from: targetApp) {
            return try accepted(copied)
        }
        // Only when Accessibility saw a text element is "nothing is selected" the honest answer.
        throw reported == .empty
            ? QuickActionFailure.noSelection
            : .unreadableApp(targetApp.localizedName ?? "That app")
    }

    private static func accepted(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickActionFailure.noSelection
        }
        guard text.utf8.count <= maxSelectionBytes else { throw QuickActionFailure.tooLong }
        return text
    }

    /// No transcript to grow, so a caller showing progress reads `onDelta` and the rest just await.
    static func run(
        _ action: QuickAction, selection: String, using provider: any AIProvider,
        translatingInto targetLanguageName: String? = nil,
        instructionOverride: String?,
        onDelta: @MainActor (String) -> Void = { _ in }
    ) async throws -> String {
        let request = AIRequest(
            instructions: QuickActionPrompt.instructions(
                for: action, override: instructionOverride,
                translatingInto: targetLanguageName),
            messages: [
                AIMessage(
                    role: .user,
                    text: QuickActionPrompt.message(for: action, selection: selection))
            ],
            maxOutputTokens: DeloresActionDefinition.outputCap(for: action.id)
                .tokens(selection: selection))
        // One session for every provider-backed action, so the cap, the stop and the empty-result
        // rule cannot differ by which id was pressed. The boundary to the transport is Delores'.
        var published = ""
        let outcome = await DeloresActionSessionRunner.run(
            stream: provider.stream(request),
            isCurrent: { true },
            onStreaming: { text in
                let delta = String(text.dropFirst(published.count))
                published = text
                if !delta.isEmpty { onDelta(delta) }
            })
        switch outcome {
        case .finished(let text, let capped):
            return capped ? text + DeloresActionOutcomeCopy.truncated : text
        case .failed(.emptyResult):
            throw AIProviderError.responseFailed(DeloresActionOutcomeCopy.emptyResult)
        case .failed(.reason(let reason)):
            throw AIProviderError.responseFailed(reason)
        case .stopped, .none:
            throw CancellationError()
        }
    }
}
