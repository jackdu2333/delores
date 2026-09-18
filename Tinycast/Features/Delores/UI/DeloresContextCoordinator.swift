import AppKit
import Observation

/// The Companion, as the Context Surface sees it.
///
/// Deliberately not a reference to the Companion: the bar only ever needs to ask where to hang, to
/// report that the body had to move, and to say whether a shell is on screen. Without one of these
/// the bar hangs from the menu bar, which is its ordinary home, so every part of this is optional as
/// a whole rather than piece by piece.
struct DeloresContextCompanionHosting {
    /// Where a shell opened on the display whose visible area is this should hang. Nil sends the bar
    /// to the menu bar — the Companion is off, or its body is not on screen.
    var anchor: (CGRect) -> DeloresCompanionAnchor?
    /// A shell did not fit where the body was standing, and the body had to slide along its edge.
    var relocate: (CGPoint, DeloresCompanionEdge) -> Void
    /// A shell hung off the body came on screen, or went away. While one is up the body stands
    /// still: a body that walked out from under the bar it opened leaves the bar over nothing.
    var held: (Bool) -> Void
}

/// Routes a captured selection to whatever the reader pressed.
@MainActor
@Observable
final class DeloresContextCoordinator {
    private let settings: AppSettings
    private let quickActions: QuickActionCoordinator
    private let injector: TextInjector
    private let aiChat: AIChatCoordinator
    private let island: DeloresContextIslandController
    private let gestureMonitor: SelectionGestureMonitor
    private let interactionGate: DeloresSurfaceInteractionGate

    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var actionTask: Task<Void, Never>?
    @ObservationIgnored private var captureGeneration = UUID()
    /// Names the selection an in-flight answer belongs to. A model keeps writing after the reader has
    /// moved on, and that answer must not land on the selection that replaced it.
    @ObservationIgnored private var actionGeneration = UUID()
    @ObservationIgnored private var conversation = DeloresActionConversation()
    /// The action and the text it was asked about, so 重试 and a follow-up need not go back to the app
    /// holding the selection — by the time either is wanted, the reader has clicked away from it.
    @ObservationIgnored private var lastRun: (action: DeloresContextAction, selection: String, path: RunPath)?
    @ObservationIgnored private var lastFingerprint: DeloresSelectionFingerprint?
    @ObservationIgnored private var lastSelectionUptime = -Double.infinity
    @ObservationIgnored private var targetApplication: NSRunningApplication?
    private var lastCapturedSelection: (text: String, target: NSRunningApplication, point: CGPoint, timestamp: Date)?

    /// The card is re-hosted on every update, which is cheap but not free, and a model emits deltas
    /// far faster than anyone reads them. Coalescing keeps the answer visibly growing without
    /// rebuilding the surface two hundred times for one paragraph.
    private static let streamingInterval: Duration = .milliseconds(160)

    /// Which lane answered one press. 重试 repeats the lane the reader saw rather than choosing again:
    /// a retry is the same question asked once more, not a new one about a backend that has moved.
    private enum RunPath: Equatable { case model, translationFramework }

    private(set) var context: InvocationContext?
    private(set) var isMonitoring = false
    var onSelectionPresented: ((String) -> Void)?
    /// Set when the Companion is the thing a bar should hang from. Nil is a bar on the menu bar.
    @ObservationIgnored var companionHosting: DeloresContextCompanionHosting?

    /// True while the reader is holding a selection on the Context Surface. A surface behind it reads
    /// this to tell "the keyboard moved to the reader's own pinned bar" apart from "the reader left".
    var isHoldingPinnedContext: Bool { island.isPinned && island.isVisible }

    init(
        settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector,
        aiChat: AIChatCoordinator, interactionGate: DeloresSurfaceInteractionGate
    ) {
        self.settings = settings
        self.quickActions = quickActions
        self.injector = injector
        self.aiChat = aiChat
        self.interactionGate = interactionGate

        self.island = DeloresContextIslandController()
        self.gestureMonitor = SelectionGestureMonitor { point in
            DeloresOwnSurfaceHitTester.containsInteractiveSurface(at: point)
        }
        self.gestureMonitor.onGesture = { [weak self] gesture in
            self?.captureSelection(after: gesture)
        }
    }

    func applyEnabled() {
        guard settings.quickActionsEnabled else {
            stop()
            return
        }
        start()
    }

    func start() {
        guard !isMonitoring, settings.quickActionsEnabled else { return }
        isMonitoring = true
        gestureMonitor.start()
    }

    func stop() {
        isMonitoring = false
        gestureMonitor.stop()
        captureTask?.cancel()
        captureTask = nil
        cancelAnswer()
        island.dismiss(notifying: false)
        clearContext()
        // The Companion reopens "the last selection", and a selection captured before the feature
        // was switched off is not one the reader can still be reading.
        lastCapturedSelection = nil
        lastFingerprint = nil
        lastSelectionUptime = -Double.infinity
    }

    private func captureSelection(after gesture: SelectionGestureMonitor.Gesture) {
        // A pinned island is holding a selection of its own, and the gesture that would replace it is
        // dropped before it reads anything: the read would paste over the reader's clipboard to no
        // purpose, and the selection state stays untouched rather than reporting text nobody sees.
        guard !(island.isVisible && (island.isPinned || island.isGenerating)) else { return }

        // A window drag or a divider drag is one gesture that belongs to Spatial. Releasing a mouse
        // button at the end of either is not a selection, and reading the target app for text would
        // put a Context bar under a window the reader is still moving.
        guard !interactionGate.blocksSelection else { return }

        guard settings.quickActionsEnabled, Permissions.isAccessibilityTrusted(),
            let target = NSWorkspace.shared.frontmostApplication,
            target.bundleIdentifier != Bundle.main.bundleIdentifier
        else { return }

        captureTask?.cancel()
        let generation = UUID()
        captureGeneration = generation
        let injector = injector
        captureTask = Task { @MainActor [weak self] in
            var rawText = AccessibilityText.selection(in: target)
            if rawText == nil {
                // Synthesizing ⌘C is dangerous if the target app is Finder or the gesture was a double-click
                // on a non-text item (e.g. opening files in Finder), which interrupts double-click delivery.
                let isFinder = target.bundleIdentifier == "com.apple.finder"
                let allowClipboardFallback = !isFinder && gesture.kind == .drag
                if allowClipboardFallback {
                    rawText = await injector.copySelection(from: target)
                }
            }
            guard let rawText,
                let prepared = DeloresSelectionContextPolicy.prepare(rawText),
                let self,
                generation == self.captureGeneration,
                self.isMonitoring,
                self.settings.quickActionsEnabled,
                !Task.isCancelled,
                !DeloresSelectionContextPolicy.isDuplicate(
                    prepared.fingerprint,
                    previous: self.lastFingerprint,
                    elapsed: gesture.uptime - self.lastSelectionUptime)
            else { return }

            self.lastFingerprint = prepared.fingerprint
            self.lastSelectionUptime = gesture.uptime
            self.present(
                prepared,
                from: target,
                at: gesture.screenPoint,
                timestamp: gesture.timestamp)
        }
    }

    /// What the bar offers: the rows Delores ships, the rows the reader wrote in Settings, and the
    /// reader's own wording for any built-in whose prompt they replaced there.
    ///
    /// Asked for on every presentation rather than cached, because both halves change while the
    /// island is away: a row written in Settings belongs on the very next selection, and Settings is
    /// the only place either list is edited.
    private func barActions() -> [DeloresContextAction] {
        DeloresContextAction
            .available(
                aiEnabled: settings.aiEnabled, customActions: quickActions.customQuickActionRows)
            .map { $0.applying(quickActions.instructionOverride(forActionID: $0.id)) }
    }

    /// Re-opens the card the reader last had, for the Companion's double-click. The feature it
    /// depends on has to still be on, and the grant it depends on still held: without either, the
    /// card would come back over text nothing can be done with.
    func showLastCapturedSelection() {
        guard settings.quickActionsEnabled, Permissions.isAccessibilityTrusted(),
            let lastCapturedSelection, isMonitoring
        else { return }
        let prepared = DeloresPreparedSelection(
            text: lastCapturedSelection.text,
            fingerprint: DeloresSelectionFingerprint(
                hash: lastCapturedSelection.text.hashValue,
                length: lastCapturedSelection.text.count))
        present(prepared, from: lastCapturedSelection.target, at: lastCapturedSelection.point, timestamp: lastCapturedSelection.timestamp)
    }

    private func present(
        _ prepared: DeloresPreparedSelection,
        from target: NSRunningApplication,
        at point: CGPoint,
        timestamp: Date
    ) {
        let screen = resolveScreen(for: point)
        let selection = SelectionInvocation(
            text: prepared.text,
            targetApplication: InvocationApplication(
                processIdentifier: target.processIdentifier,
                bundleIdentifier: target.bundleIdentifier,
                displayName: target.localizedName),
            screenPoint: point,
            screen: screen,
            timestamp: timestamp)
        context = .selection(selection)
        targetApplication = target
        lastCapturedSelection = (prepared.text, target, point, timestamp)
        onSelectionPresented?(prepared.text)
        // The bar is being replaced, and with it the selection the last answer was about.
        cancelAnswer()

        // Hung off the Companion when the Companion is what the reader is looking at, and off the
        // menu bar otherwise. The body is asked where it is standing before the bar is built,
        // because the bar's own size is what decides whether the body then has to move.
        let pet = companionHosting?.anchor(screen.visibleFrame)
        island.onCompanionRelocated = { [weak self] center, edge in
            self?.companionHosting?.relocate(center, edge)
        }
        // Told either way rather than only when there is one: the bar before this one may have been
        // holding the body still, and a replacement that went to the menu bar has to let it go.
        companionHosting?.held(pet != nil)

        island.present(
            context: selection,
            actions: barActions(),
            metrics: settings.interfaceSize.metrics,
            onAction: { [weak self] action in self?.run(action) },
            onReplaceAnswer: { [weak self] text in self?.replace(with: text) },
            onStopAnswer: { [weak self] in self?.stopAnswering() },
            onRetryAnswer: { [weak self] in self?.askAgain() },
            onFollowUp: { [weak self] question in self?.followUp(question) },
            onDismiss: { [weak self] in self?.surfaceDismissed() },
            companion: pet)
    }

    private func run(_ action: DeloresContextAction) {
        guard case .selection(let selection) = context else { return }
        switch action.kind {
        case .search:
            // No model and no card: the browser is the result surface for this one, and it opens in
            // the reader's own app rather than in a window of ours.
            guard let url = action.searchURL(selection: selection.text) else { return }
            NSWorkspace.shared.open(url)
            releaseSurface()
        case .ask:
            // Chat is an explicit escalation, not the hidden destination of every small action.
            let prompt = action.message(selection: selection.text)
            let continuing = aiChat.isChatOnScreen
            releaseSurface()
            if continuing {
                _ = aiChat.send(prompt)
            } else {
                aiChat.ask(prompt)
            }
        case .ai:
            beginAnswer(action, selection: selection.text)
        }
    }

    /// Where one press goes, before any card is on screen.
    ///
    /// 翻译 is the one row that can be answered from two places — Apple's translator unless the reader has
    /// given that id a model — so the choice is made here, once, rather than inside the run: a card that
    /// changed backend halfway through would be one nobody could read.
    private func beginAnswer(_ action: DeloresContextAction, selection: String) {
        guard action.definition.backend == .translationFramework else {
            answer(action, selection: selection, path: .model)
            return
        }
        let generation = UUID()
        actionGeneration = generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let route = await self.quickActions.translateRoute(
                for: selection, to: self.quickActions.targetLanguage)
            guard self.actionGeneration == generation else { return }
            switch route {
            case .languageModel: self.answer(action, selection: selection, path: .model)
            case .translationFramework:
                self.answerWithTheTranslationFramework(action, selection: selection)
            }
        }
    }

    // MARK: - Answering in the island

    private func answer(
        _ action: DeloresContextAction, selection: String, path: RunPath, question: String? = nil
    ) {
        cancelAnswer()
        let provider: any AIProvider
        do { provider = try quickActions.provider(forActionID: action.id) }
        catch { island.showAnswer(.failed(action, reason: error.localizedDescription)); return }
        let asked = question ?? action.message(selection: selection)
        let generation = UUID()
        actionGeneration = generation
        lastRun = (action, selection, path)
        conversation.begin(question: asked)
        island.showAnswer(.running(action))
        let request = AIRequest(instructions: action.instructions, messages: Self.messages(from: conversation.settled) + [AIMessage(role: .user, text: asked)], maxOutputTokens: action.maxOutputTokens(selection: selection))
        actionTask = Task { @MainActor [weak self] in
            var published = ContinuousClock.now
            let outcome = await DeloresActionSessionRunner.run(
                stream: provider.stream(request),
                isCurrent: { [weak self] in self?.actionGeneration == generation },
                onStreaming: { [weak self] text in
                    guard let self else { return }
                    let now = ContinuousClock.now
                    guard now - published >= Self.streamingInterval else { return }
                    published = now
                    self.island.showAnswer(.partial(action, text: text), animated: false)
                })
            guard let self, self.actionGeneration == generation, let outcome else { return }
            self.show(outcome, for: action)
        }
    }

    /// Apple's translator, in the card the reader is already looking at.
    ///
    /// No provider and nothing to stream: the framework hands back one finished string, so the card goes
    /// up as running and then holds the whole translation. The answer joins the conversation either way,
    /// because a follow-up question about it is still a model's turn.
    private func answerWithTheTranslationFramework(
        _ action: DeloresContextAction, selection: String
    ) {
        cancelAnswer()
        let generation = UUID()
        actionGeneration = generation
        lastRun = (action, selection, .translationFramework)
        conversation.begin(question: action.message(selection: selection))
        island.showAnswer(.running(action))
        let target = quickActions.targetLanguage
        actionTask = Task { @MainActor [weak self] in
            do {
                let text = try await TextTranslator.translate(selection, to: target)
                guard let self, self.actionGeneration == generation else { return }
                guard !Task.isCancelled else {
                    self.abandon(action)
                    return
                }
                self.conversation.noteAnswer(text)
                self.island.showAnswer(.partial(action, text: text), animated: false)
            } catch is CancellationError {
                guard let self, self.actionGeneration == generation else { return }
                self.abandon(action)
            } catch {
                guard let self, self.actionGeneration == generation else { return }
                self.island.showAnswer(.failed(action, reason: error.localizedDescription))
            }
        }
    }

    /// The card for a framework run that ended without an answer, because the reader stopped it. It is
    /// a stopped card rather than a dismissal so the press can be repeated, and the generation check
    /// above is what tells a Stop apart from the surface having been replaced under it.
    private func abandon(_ action: DeloresContextAction) {
        conversation.noteAnswer("")
        island.showAnswer(.stopped(action, text: nil), animated: false)
    }

    private func show(_ outcome: DeloresActionSession.Outcome, for action: DeloresContextAction) {
        switch outcome {
        case .finished(let text):
            conversation.noteAnswer(text)
            island.showAnswer(.partial(action, text: text), animated: false)
        case .failed(let reason):
            island.showAnswer(.failed(action, reason: reason))
        case .stopped(let text):
            conversation.noteAnswer(text ?? "")
            island.showAnswer(.stopped(action, text: text), animated: false)
        }
    }

    private static func messages(from turns: [DeloresActionConversation.Turn]) -> [AIMessage] {
        turns.map { AIMessage(role: $0.role == .user ? .user : .assistant, text: $0.text) }
    }

    // MARK: - Stop, retry and follow-up

    private func stopAnswering() {
        guard let actionTask else { return }
        actionTask.cancel()
        self.actionTask = nil
    }
    private func askAgain() {
        guard let (action, selection, path) = lastRun else { return }
        conversation.restart()
        switch path {
        case .model: answer(action, selection: selection, path: .model)
        case .translationFramework: answerWithTheTranslationFramework(action, selection: selection)
        }
    }
    private func followUp(_ question: String) {
        guard let (action, selection, _) = lastRun else { return }
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }
        conversation.commitForFollowUp()
        // A follow-up asks about the answer, so it is a model's turn whatever produced that answer.
        answer(action, selection: selection, path: .model, question: asked)
    }

    private func cancelAnswer() {
        actionTask?.cancel()
        actionTask = nil
        actionGeneration = UUID()
    }

    /// Puts the answer where the selection was, which is what 翻译 and 总结 are for.
    ///
    /// The document is only rewritten once the injection reports it landed. A refused write leaves the
    /// answer on the clipboard and says so in the card, rather than replacing nothing and reporting
    /// nothing — this is the one step here that can destroy text the reader cannot get back.
    private func replace(with text: String) {
        guard let targetApplication else { return }
        injector.replaceSelection(
            with: text, in: targetApplication,
            onDelivered: { [weak self] in self?.island.note("已写回原文。") },
            onFailed: { [weak self] in
                Paster.copyPlainText(text)
                self?.island.note("写回失败，答案已复制到剪贴板。")
            })
    }

    /// Lets go of the captured selection, unless the reader pinned it. Then the island stays put and
    /// the next press lands on the same text, which is the whole of what pinning is for.
    private func releaseSurface() {
        guard !island.isPinned, !island.isGenerating else { return }
        island.dismiss(notifying: false)
        clearContext()
    }

    private func surfaceDismissed() {
        // Closing the surface closes the question with it: an answer that arrives for a card nobody
        // is looking at is a token bill with nothing to show for it.
        cancelAnswer()
        clearContext()
    }

    private func clearContext() {
        // Nothing of ours is on screen, so nothing is holding the Companion still any more.
        companionHosting?.held(false)
        context = nil
        targetApplication = nil
        // Closing out the surface closes out the conversation with it: a question typed under one
        // selection has no business answering another.
        conversation.restart()
        lastRun = nil
    }

    private func resolveScreen(for point: CGPoint) -> InvocationScreen {
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let menuBarFrame = CGRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.maxY,
            width: screen.frame.width,
            height: menuBarHeight)
        let rightArea = screen.safeAreaInsets.top > 0
            ? screen.auxiliaryTopRightArea
            : nil
        return InvocationScreen(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            menuBarFrame: menuBarFrame,
            auxiliaryTopRightArea: rightArea)
    }
}

extension DeloresContextIslandAnswer {
    /// The card while the answer is still on its way. A card rather than a bare bar, so the growth
    /// happens once, at the press, instead of once more whenever the first token arrives.
    fileprivate static func running(_ action: DeloresContextAction) -> Self {
        DeloresContextIslandAnswer(
            actionTitle: action.title, actionID: action.id, symbol: action.symbol,
            rewritesSelection: action.rewritesSelection)
    }

    /// The same card with whatever has arrived so far. Its own constructor rather than a mutation,
    /// because every one of these is a new value handed to a view that has already been built once.
    fileprivate static func partial(_ action: DeloresContextAction, text: String) -> Self {
        DeloresContextIslandAnswer(
            actionTitle: action.title, actionID: action.id, symbol: action.symbol,
            rewritesSelection: action.rewritesSelection,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The card for a run the reader stopped. Nil text means they stopped before the first token, so
    /// there is nothing to keep and the whole of what was asked still to do.
    fileprivate static func stopped(
        _ action: DeloresContextAction, text: String?
    ) -> Self {
        DeloresContextIslandAnswer(
            actionTitle: action.title, actionID: action.id, symbol: action.symbol,
            rewritesSelection: action.rewritesSelection,
            text: text, isStopped: true)
    }

    /// The card for a run that produced no answer at all.
    ///
    /// Still a card rather than a dismissal: a surface that closed on failure would leave the reader
    /// with nothing to read, nothing to retry on, and no way to tell the press from a misclick.
    fileprivate static func failed(_ action: DeloresContextAction, reason: String) -> Self {
        DeloresContextIslandAnswer(
            actionTitle: action.title, actionID: action.id, symbol: action.symbol,
            rewritesSelection: action.rewritesSelection, failure: reason)
    }
}
