import AppKit
import Observation

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
    /// What the card most recently asked and answered, held so the next question can carry it.
    @ObservationIgnored private var currentTurn: (question: String, answer: String)?
    /// The exchanges already settled under this card, oldest first. The question asked now is appended
    /// at send time and joins only once its answer has landed.
    @ObservationIgnored private var answeredTurns: [AIMessage] = []
    /// The action and the text it was asked about, so 重试 and a follow-up need not go back to the app
    /// holding the selection — by the time either is wanted, the reader has clicked away from it.
    @ObservationIgnored private var lastRun: (action: DeloresContextAction, selection: String)?
    @ObservationIgnored private var lastFingerprint: DeloresSelectionFingerprint?
    @ObservationIgnored private var lastSelectionUptime = -Double.infinity
    @ObservationIgnored     private var targetApplication: NSRunningApplication?
    private var lastCapturedSelection: (text: String, target: NSRunningApplication, point: CGPoint, timestamp: Date)?

    /// The card is re-hosted on every update, which is cheap but not free, and a model emits deltas
    /// far faster than anyone reads them. Coalescing keeps the answer visibly growing without
    /// rebuilding the surface two hundred times for one paragraph.
    private static let streamingInterval: Duration = .milliseconds(160)

    private(set) var context: InvocationContext?
    private(set) var isMonitoring = false
    var onSelectionPresented: ((String) -> Void)?

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
        guard !(island.isVisible && island.isPinned) else { return }

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
                rawText = await injector.copySelection(from: target)
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

        island.present(
            context: selection,
            actions: barActions(),
            metrics: settings.interfaceSize.metrics,
            onAction: { [weak self] action in self?.run(action) },
            onReplaceAnswer: { [weak self] text in self?.replace(with: text) },
            onStopAnswer: { [weak self] in self?.stopAnswering() },
            onRetryAnswer: { [weak self] in self?.askAgain() },
            onFollowUp: { [weak self] question in self?.followUp(question) },
            onDismiss: { [weak self] in self?.surfaceDismissed() })
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
            answer(action, selection: selection.text)
        }
    }

    // MARK: - Answering in the island

    /// Runs the action's own prompt on the route bound to it, and writes the reply into the card.
    ///
    /// The bar stays up, and so does the selection: the reader came here to read this text, and the
    /// next thing they usually want is a second action on the same text.
    ///
    /// `question` is what the reader typed; nil means the first turn, whose question is the selection
    /// itself. `carried` is what has already been said under this card, oldest first.
    private func answer(
        _ action: DeloresContextAction,
        selection: String,
        question: String? = nil,
        carried: [AIMessage] = []
    ) {
        cancelAnswer()
        let provider: any AIProvider
        do {
            // The action's own route, never the chat's. The reader bound a model to this id, and
            // answering with whatever chat happens to be running is exactly the silent substitution
            // this seam exists to prevent.
            provider = try quickActions.provider(forActionID: action.id)
        } catch {
            island.showAnswer(.failed(action, reason: error.localizedDescription))
            return
        }

        let asked = question ?? action.message(selection: selection)
        let generation = UUID()
        actionGeneration = generation
        lastRun = (action, selection)
        currentTurn = (question: asked, answer: "")
        island.showAnswer(.running(action))

        let request = AIRequest(
            instructions: action.instructions,
            messages: carried + [AIMessage(role: .user, text: asked)],
            maxOutputTokens: action.maxOutputTokens(selection: selection))
        actionTask = Task { @MainActor [weak self] in
            var answer = DeloresAnswerAccumulator()
            var published = ContinuousClock.now
            do {
                for try await event in provider.stream(request) {
                    guard case .text(let delta) = event else { continue }
                    answer.append(delta)
                    guard let self, self.actionGeneration == generation else { return }
                    // Capped is the end of the reply as far as this card is concerned. Breaking here
                    // also abandons the stream, which is what stops the transport: a model that has
                    // already run past 32k characters has nothing left to say to this card.
                    guard !answer.isCapped else { break }
                    let now = ContinuousClock.now
                    guard now - published >= Self.streamingInterval else { continue }
                    published = now
                    self.island.showAnswer(
                        .partial(action, text: answer.text), animated: false)
                }
            } catch is CancellationError {
                // The reader pressed stop, which is the one cancellation that still has something to
                // show: whatever arrived before it. The generation is deliberately still valid here —
                // `cancelAnswer` is what invalidates it, and it is what a *replaced* card uses to say
                // nothing more; stopping is not replacing.
                guard let self, self.actionGeneration == generation else { return }
                let kept = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.currentTurn?.answer = kept
                guard !kept.isEmpty else {
                // Nothing had landed yet, so there is nothing to keep — but the card still has to say
                // why it is waiting rather than reading as a press that did nothing.
                self.island.showAnswer(.stopped(action, text: nil), animated: false)
                return
                }
                self.island.showAnswer(.stopped(action, text: kept), animated: false)
                return
            } catch {
                guard let self, self.actionGeneration == generation else { return }
                self.island.showAnswer(.failed(action, reason: error.localizedDescription))
                return
            }
            guard let self, self.actionGeneration == generation else { return }
            let trimmed = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.island.showAnswer(.failed(action, reason: "模型没有返回任何内容。"))
                return
            }
            // Kept as the conversation's other half: the next question carries it, so asking "and for
            // Windows?" about a translation gets an answer about that translation.
            self.currentTurn?.answer = trimmed
            self.island.showAnswer(.partial(action, text: trimmed), animated: false)
        }
    }

    // MARK: - Stop, retry and follow-up

    /// Ends a reply that is still arriving, keeping what it produced.
    ///
    /// Cancelling the task is the whole mechanism: the loop above recognises cancellation and settles
    /// the card itself, so there is one place that decides what a stopped answer looks like.
    private func stopAnswering() {
        guard let actionTask else { return }
        actionTask.cancel()
        self.actionTask = nil
    }

    /// Asks the same action about the same text once more, for answers that came back broken or cut
    /// short. The conversation restarts: carrying a half-answer back into the request would ask the
    /// model to continue one, which is not what pressing 重试 means.
    private func askAgain() {
        guard let (action, selection) = lastRun else { return }
        answeredTurns = []
        currentTurn = nil
        answer(action, selection: selection)
    }

    /// Answers a further question about this card, on the same action and the same selection.
    ///
    /// One answer deep is where most of this stops, but asking "shorter" or "for Windows" should not
    /// mean selecting the text again — and should not lose what was already said, which is what the
    /// carried turns are for.
    private func followUp(_ question: String) {
        guard let (action, selection) = lastRun else { return }
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }

        if let settled = currentTurn, !settled.answer.isEmpty {
            answeredTurns.append(AIMessage(role: .user, text: settled.question))
            answeredTurns.append(AIMessage(role: .assistant, text: settled.answer))
            answeredTurns = Self.kept(answeredTurns)
        }
        answer(action, selection: selection, question: asked, carried: answeredTurns)
    }

    /// The carried conversation, trimmed to a size worth sending.
    ///
    /// Ten exchanges is ten times further than a reading surface should be asked to go, and a single
    /// turn longer than eight thousand characters is more context than it is conversation — dropped
    /// oldest-first, in pairs, because an unpaired question teaches a model to answer questions nobody
    /// asked.
    private static let maxTurnMessages = 20
    private static let maxTurnCharacters = 8_000

    private static func kept(_ turns: [AIMessage]) -> [AIMessage] {
        let clipped = turns.map { message in
            AIMessage(
                role: message.role,
                text: message.text.count > maxTurnCharacters
                    ? String(message.text.prefix(maxTurnCharacters))
                    : message.text)
        }
        let excess = clipped.count - maxTurnMessages
        guard excess > 0 else { return clipped }
        return Array(clipped.dropFirst(excess % 2 == 0 ? excess : excess + 1))
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
        guard !island.isPinned else { return }
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
        context = nil
        targetApplication = nil
        // Closing out the surface closes out the conversation with it: a question typed under one
        // selection has no business answering another.
        answeredTurns = []
        currentTurn = nil
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
