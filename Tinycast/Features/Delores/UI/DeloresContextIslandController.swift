import AppKit
import Carbon.HIToolbox
import SwiftUI

private final class DeloresFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class DeloresContextIslandPanel: NSPanel {
    /// Escape. Handled at the panel for the same reason the palette handles it there: it is the one
    /// key the window owns itself, and a hosted view has no field editor to route it through.
    /// Nil means this surface does not answer it and the event carries on.
    var onEscape: (() -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Escape,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onEscape?() == true
        {
            return
        }
        super.sendEvent(event)
    }
}

/// Owns the Context Surface window; feature policy stays in `DeloresContextCoordinator`.
///
/// Every state change goes through `render` rather than being spelled out per state. There are four
/// of them now — the bar, a card opening, a card waiting, a card with an answer — and building each
/// one separately is how they drift apart.
@MainActor
final class DeloresContextIslandController: NSObject, NSWindowDelegate {
    /// What the bar was opened with. Held rather than threaded through every redraw, so a state
    /// change can re-render the surface without the caller restating the selection behind it.
    private struct Presented {
        let context: SelectionInvocation
        let actions: [DeloresContextAction]
        let metrics: InterfaceMetrics
        let onAction: (DeloresContextAction) -> Void
        let onReplaceAnswer: (String) -> Void
        let onStopAnswer: () -> Void
        let onRetryAnswer: () -> Void
        let onFollowUp: (String) -> Void
        let onDismiss: () -> Void
    }

    private var panel: DeloresContextIslandPanel?
    private var presented: Presented?
    private var answer: DeloresContextIslandAnswer?

    /// The reader's hold on this surface. While it is set the island keeps its selection: it does not
    /// answer an outside click, and the coordinator lets a new selection pass by rather than replace
    /// it. Escape and the close button still get out, which is where the toolbar this came from drew
    /// the line too.
    private(set) var isPinned = false

    /// The selection this bar was opened for, kept so the bar's copy button copies the text the
    /// reader is looking at rather than reaching back to the app for it a second time.
    private var selectionText = ""

    /// The display this bar was placed on. Held rather than re-resolved, because the bar is anchored
    /// to a menu bar and there is one of those per display.
    private var screen: InvocationScreen?

    /// The bar's width, measured once while the bar is the only thing in the panel.
    ///
    /// Never re-measured: a card holds a paragraph, whose ideal width is the length of its longest
    /// line rather than the width of anything a reader wants to look at.
    ///
    /// Two of them, because the bar does not always carry the same controls: collapsed and unpinned
    /// it is the catalog and the copy button, and pin and close join it only once the reader has
    /// pinned the surface or opened a card. Measuring one width and reusing it for the other state
    /// would squeeze the two controls that state just added.
    private var barWidth: CGFloat = 0
    private var barWidthWithExits: CGFloat = 0

    /// The state the panel is showing, kept so a control that changes the *width* — the pin — can
    /// re-render without the caller restating what is on screen.
    private var lastMode: DeloresContextIslandMode = .actions

    /// The reader put the card away without putting the selection away. The answer is kept, so the
    /// same action brings it straight back rather than asking the model again.
    private var isCardCollapsed = false

    /// Names the panel an asynchronous step belongs to. The opening card hands its action over after
    /// an animation, and a press outlives the panel whenever a new selection replaces it meanwhile.
    private var panelGeneration = UUID()

    var isVisible: Bool { panel?.isVisible == true }
    var isGenerating: Bool { answer?.isRunning == true }

    /// The card's opening. The bar grows where it stands and only then hands the answer over, so the
    /// hand-off reads as one downward gesture instead of a window swap.
    private enum Card {
        /// Long enough to be read as a gesture, short enough not to sit between press and answer.
        static let growth: TimeInterval = 0.20
    }

    // MARK: - Lifecycle

    /// The question being typed under an answer, kept here rather than in the view: every token of a
    /// reply rebuilds the card above it, and a draft held in the view would be discarded on every one
    /// of them — mid-sentence, mid-keystroke.
    private var followUpDraft = ""

    func present(
        context: SelectionInvocation,
        actions: [DeloresContextAction],
        metrics: InterfaceMetrics,
        onAction: @escaping (DeloresContextAction) -> Void,
        onReplaceAnswer: @escaping (String) -> Void,
        onStopAnswer: @escaping () -> Void,
        onRetryAnswer: @escaping () -> Void,
        onFollowUp: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss(notifying: false)

        screen = context.screen
        selectionText = context.text
        answer = nil
        isCardCollapsed = false
        // A panel replaces the one before it, so the hold on that one dies with it.
        isPinned = false
        panelGeneration = UUID()
        presented = Presented(
            context: context, actions: actions, metrics: metrics, onAction: onAction,
            onReplaceAnswer: onReplaceAnswer, onStopAnswer: onStopAnswer,
            onRetryAnswer: onRetryAnswer, onFollowUp: onFollowUp, onDismiss: onDismiss)
        // A new selection brings a new conversation, so yesterday's half-typed question goes with it.
        followUpDraft = ""

        let wish = DeloresContextIslandView.preferredSize(for: metrics)
        // The height the bar is actually given, not the wish: the menu bar caps it, and content laid
        // out against the uncapped wish is what clipped the pills.
        let height = DeloresContextIslandPlacement.collapsedHeight(
            preferred: wish.height, in: context.screen)
        barWidth = measuredBarWidth(
            root: makeRoot(.actions), metrics: metrics, wish: wish, in: context.screen)
        // Measured against a card-opening state, because that is the state that also carries the
        // collapse control. A hand-off card's own width is its label's, which is narrower than the
        // bar, so what comes back is the bar's.
        barWidthWithExits = measuredBarWidth(
            root: makeRoot(.handoff(progressTitle: "正在打开 AI 对话"), pinned: true),
            metrics: metrics, wish: wish, in: context.screen)
        lastMode = .actions
        let size = CGSize(width: barWidth, height: height)

        // Hosted only after the measurement, because the row is pinned to the width that measurement
        // returned — and a row told its own width cannot report one.
        let hosting = DeloresFirstMouseHostingView(
            rootView: hosted(makeRoot(.actions, rowWidth: barWidth), size: size, metrics: metrics))
        hosting.sizingOptions = []
        hosting.setFrameSize(NSSize(width: size.width, height: size.height))

        let panel = DeloresContextIslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.delegate = self
        panel.contentView = hosting
        panel.setFrame(
            DeloresContextIslandPlacement.collapsedFrame(in: context.screen, size: size),
            display: false)
        // Escape closes what this surface put up, and nothing else: an action still running behind the
        // card is cancelled with the surface that asked for it, which the coordinator does on the way
        // out. While the card is opening it cancels the press as well, because `onAction` does not
        // fire until the growth ends — the same generation token that guards a replaced panel guards
        // this.
        panel.onEscape = { [weak self] in
            guard let self, self.isVisible else { return false }
            // Escape walks back one step at a time. An open card closes first, and only the bare bar
            // closes the surface. One press that took both away would leave a reader who only wanted
            // the answer out of the way without their selection as well — and the bar they were
            // reading from is one press away again either way.
            if self.lastMode.opensCard {
                self.collapseCard()
            } else {
                self.dismiss()
            }
            return true
        }
        self.panel = panel

        // The bar condenses out of the menu bar rather than fading in where it stands: it is put
        // `enterSlide` too high and animated down onto its resting place while it comes up to full
        // opacity, one eased 180ms action for both. A bare fade reads as a window switching on; this
        // reads as the bar settling, which is what the toolbar this came from did.
        let resting = DeloresContextIslandPlacement.collapsedFrame(in: context.screen, size: size)
        panel.setFrame(
            resting.offsetBy(dx: 0, dy: DeloresContextIslandPlacement.enterSlide), display: false)
        panel.alphaValue = 0
        // Ordered in before the animation starts, or there is nothing on screen for it to run on.
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { animation in
            animation.duration = Theme.Duration.enter
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(resting, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // AppKit runs the handler on the main thread; the parameter just isn't typed for it.
            MainActor.assumeIsolated { self?.panel?.invalidateShadow() }
        }
    }

    func dismiss(notifying: Bool = true) {
        guard let closing = panel else {
            if notifying { presented?.onDismiss() }
            return
        }
        panel = nil
        panelGeneration = UUID()
        let callback = presented?.onDismiss
        presented = nil
        answer = nil
        isPinned = false
        selectionText = ""
        screen = nil
        barWidth = 0
        barWidthWithExits = 0
        lastMode = .actions
        closing.delegate = nil
        closing.onEscape = nil
        if notifying { callback?() }
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    /// An outside click, which is the one way this surface used to leave without being asked. A
    /// pinned island sits it out — the reader said to hold this selection, and clicking away to read
    /// the answer is exactly the case that was meant.
    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        // While a pinned selection is held OR while the model is still generating an answer,
        // clicking outside does NOT dismiss the island.
        guard !isPinned, !isGenerating else { return }
        dismiss()
    }

    // MARK: - The card

    /// Swaps the card under the bar. The bar itself never changes: it stays live so the reader can
    /// run a second action on the same selection without closing this one first.
    func showAnswer(_ next: DeloresContextIslandAnswer, animated: Bool = true) {
        guard let panel, panel.isVisible else { return }
        answer = next
        // A fresh press is the reader asking for the card; a reply that lands while they have it
        // collapsed is not, and must not pop it back open over whatever they moved on to reading.
        if next.isRunning { isCardCollapsed = false }
        guard !isCardCollapsed else { return }
        render(.result(next), animated: animated)
    }

    /// Puts the card away where it stands. The bar stays live and the selection stays held, so the
    /// answer is one press away again — this is the reader making room, not dismissing anything.
    private func collapseCard() {
        guard answer != nil, !isCardCollapsed else { return }
        isCardCollapsed = true
        render(.actions, animated: true)
    }

    /// Adds a line to the card without replacing the answer in it — for something that happened
    /// around the answer, such as a write-back that could not land.
    func note(_ note: String) {
        guard var current = answer else { return }
        current.note = note
        showAnswer(current, animated: false)
    }

    private func copyAnswer() {
        guard let text = answer?.text, !text.isEmpty else { return }
        Paster.copyPlainText(text)
    }

    /// Writing back is the coordinator's job: it holds the target application and the injector, and
    /// this controller deliberately knows about neither.
    private func replaceAnswer() {
        guard let text = answer?.text, !text.isEmpty else { return }
        presented?.onReplaceAnswer(text)
    }

    // MARK: - Rendering

    private func makeRoot(
        _ mode: DeloresContextIslandMode, pinned: Bool? = nil, rowWidth: CGFloat = 0
    ) -> DeloresContextIslandView {
        let actions = presented?.actions ?? []
        let metrics = presented?.metrics ?? .standard
        let screen = self.screen
        let barHeight = screen.map {
            DeloresContextIslandPlacement.collapsedHeight(
                preferred: DeloresContextIslandView.preferredSize(for: metrics).height, in: $0)
        } ?? DeloresContextIslandView.preferredSize(for: metrics).height
        return DeloresContextIslandView(
            actions: actions,
            mode: mode,
            isPinned: pinned ?? isPinned,
            barHeight: barHeight,
            pinnedBarWidth: rowWidth,
            onAction: { [weak self] action in
                guard let self else { return }
                if action.requiresChatHandoff {
                    self.handOff(action)
                } else {
                    self.presented?.onAction(action)
                }
            },
            onCopy: { [weak self] in self?.copySelection() },
            onCopyAnswer: { [weak self] in self?.copyAnswer() },
            onReplaceAnswer: { [weak self] in self?.replaceAnswer() },
            onTogglePin: { [weak self] pinned in
                guard let self else { return }
                self.isPinned = pinned
                // Pinning adds the two controls that were only being held back while the surface
                // could still be dismissed by clicking away — so it changes the bar's width, and
                // the vessel has to be rebuilt for it rather than squeezing them in.
                self.render(self.lastMode, animated: true)
            },
            onCollapseAnswer: { [weak self] in self?.collapseCard() },
            onStopAnswer: { [weak self] in self?.presented?.onStopAnswer() },
            onRetryAnswer: { [weak self] in self?.presented?.onRetryAnswer() },
            onFollowUp: { [weak self] question in self?.presented?.onFollowUp(question) },
            followUpInput: Binding(
                get: { [weak self] in self?.followUpDraft ?? "" },
                set: { [weak self] in self?.followUpDraft = $0 }),
            onDismiss: { [weak self] in self?.dismiss() })
    }

    /// The view as the panel will host it: told the size of the vessel it is going into.
    ///
    /// This is not belt-and-braces. A hosting view installed in a window also *sizes* that window:
    /// SwiftUI's `windowDidLayout` runs `updateAnimatedWindowSize` and animates the panel to the
    /// ideal size of whatever it is hosting, the frame the controller already set included. Measured
    /// on this machine: a bar the controller set to 497pt came back as 428pt, and the bar then laid
    /// itself out at 428, where every title collapses to an ellipsis — and, a truncated bar being a
    /// narrower bar, the size SwiftUI then aimed for was the truncated one. Pinning the content to
    /// the vessel breaks that loop: what the panel is and what the content believes it has become
    /// the same number, so there is nothing left for the window to resize to.
    ///
    /// The measurement deliberately does not go through here — a view told its own width cannot
    /// report what width it needs.
    private func hosted(
        _ root: DeloresContextIslandView, size: CGSize, metrics: InterfaceMetrics
    ) -> some View {
        root
            .frame(width: size.width, height: size.height)
            .environment(\.metrics, metrics)
    }

    /// The one place a frame is set. The card's height and width are decided here from the mode, so a
    /// new card state cannot forget to ask for the room it needs.
    private func render(_ mode: DeloresContextIslandMode, animated: Bool) {
        guard let panel, panel.isVisible, let presented else { return }
        let screen = presented.context.screen
        let metrics = presented.metrics
        let wish = DeloresContextIslandView.preferredSize(for: metrics)
        let barHeight = DeloresContextIslandPlacement.collapsedHeight(
            preferred: wish.height, in: screen)
        // Which bar this state draws decides how wide the vessel has to be.
        let row = isPinned || mode.opensCard ? barWidthWithExits : barWidth
        // The row is drawn at the collapsed bar's width in every state, so a wider row is room the
        // vessel has to hold rather than a reason to move the catalog. See `vesselWidth`.
        let vessel = DeloresContextIslandPlacement.vesselWidth(
            row: row, pinned: barWidth, in: screen)
        let size: CGSize
        if mode.opensCard {
            let width = DeloresContextIslandPlacement.resultWidth(barWidth: vessel, in: screen)
            // The reading height, not the content's height. An opened card is a page: it is the same
            // size whether the answer is one line or ten, so the growth is one gesture the reader can
            // predict, and the text is set in a column that does not change width mid-read. A card
            // sized to its own text makes a four-word answer a strip and a paragraph a slab, and the
            // two look like different surfaces.
            let targetHeight = mode.isWorking
                ? metrics.scaled(DeloresContextIslandPlacement.preferredWorkingHeight)
                : metrics.scaled(DeloresContextIslandPlacement.preferredExpandedHeight)
            size = CGSize(
                width: width,
                height: mode.isWorking
                    ? targetHeight
                    : DeloresContextIslandPlacement.expandedHeight(
                        preferred: targetHeight,
                        in: screen))
        } else {
            size = CGSize(width: vessel, height: barHeight)
        }
        lastMode = mode

        // Laid out for the card it becomes before the frame animates, so the growth reveals the card
        // rather than stretching the bar.
        let root = makeRoot(mode, rowWidth: barWidth)
        let hosting = DeloresFirstMouseHostingView(
            rootView: hosted(root, size: size, metrics: metrics))
        hosting.sizingOptions = []
        hosting.setFrameSize(NSSize(width: size.width, height: size.height))
        let anchored = panel.frame
        panel.contentView = hosting
        let target = DeloresContextIslandPlacement.expandedFrame(
            keepingTopEdgeOf: anchored, size: size, in: screen)

        guard animated, target != anchored else {
            panel.setFrame(target, display: true)
            panel.invalidateShadow()
            return
        }
        // The width is taken at once and only the height is animated.
        //
        // The row is pinned to the bar's own width, so the controls a card adds spill past the row's
        // trailing edge, and the vessel is only wide enough for that spill once it has finished
        // growing. Animating the width as well would carry those controls outside the glass for the
        // length of the animation. Taking the width first puts the room there before the controls are
        // drawn in it; growing downward is the gesture, and the width is only the room for it.
        //
        // Nothing moves sideways by doing this: the panel is centred on its display, so widening it
        // symmetrically leaves the pinned row exactly where it was.
        let widened = CGRect(
            x: target.minX, y: anchored.minY, width: target.width, height: anchored.height)
        if widened != anchored {
            panel.setFrame(widened, display: true)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Card.growth
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            // AppKit runs the handler on the main thread; the parameter just isn't typed for it.
            // A shadow is cached from the frame it was first drawn at, so a frame that changed
            // without a new one would keep the old outline.
            MainActor.assumeIsolated { self?.panel?.invalidateShadow() }
        }
    }

    /// The card's opening for an answer that lands elsewhere. Its own buttons are inert: one press is
    /// the whole gesture.
    private func handOff(_ action: DeloresContextAction) {
        // A pinned island is staying, so there is nowhere for the growth to carry the reader out of.
        // It exists to hand them to the chat and take the bar away behind them; here the bar stays,
        // and the press is the whole gesture either way.
        guard !isPinned, panel?.isVisible == true else {
            presented?.onAction(action)
            return
        }
        let generation = panelGeneration
        render(.handoff(progressTitle: action.progressTitle), animated: true)
        // Waited out rather than run from the animation's own completion handler: that handler is not
        // main-actor typed, and handing it a callback from here is the data race the compiler is
        // right to refuse. The growth still gets to finish before the bar is taken away, which is the
        // whole point of opening it first.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Card.growth))
            // A new selection may have replaced this panel while the card was opening, and its own
            // press is the one that should run — this step stops rather than answer for it.
            guard let self, self.panelGeneration == generation else { return }
            self.presented?.onAction(action)
            self.dismiss(notifying: false)
        }
    }

    /// The bar's width, measured the way the toolbar it came from measured itself: lay the content
    /// out, then read the ideal width off a hosting view that is allowed to publish one.
    ///
    /// Measuring happens on a probe, never on the real view — a hosting view with `sizingOptions`
    /// emptied reports a fitting size of zero (measured), and the real one needs `sizingOptions`
    /// empty so this controller owns its frame. `barWidth` reads a zero as "no measurement" and
    /// falls back, so a probe that fails to report costs a wide bar rather than a clipped one.
    private func measuredBarWidth(
        root: DeloresContextIslandView, metrics: InterfaceMetrics, wish: CGSize,
        in screen: InvocationScreen
    ) -> CGFloat {
        let probe = NSHostingView(rootView: root.environment(\.metrics, metrics))
        probe.setFrameSize(NSSize(width: wish.width, height: wish.height))
        probe.layoutSubtreeIfNeeded()
        return DeloresContextIslandPlacement.barWidth(
            hugging: probe.fittingSize.width, in: screen)
    }

    /// The selection, not a result: this bar hangs over a selection, and copying it is the one thing
    /// a reader expects the bar itself to do. Results own their own copy button where they land.
    private func copySelection() {
        guard !selectionText.isEmpty else { return }
        Paster.copyPlainText(selectionText)
    }
}
