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
@MainActor
final class DeloresContextIslandController: NSObject, NSWindowDelegate {
    private var panel: DeloresContextIslandPanel?
    private var onAction: ((DeloresContextAction) -> Void)?
    private var onDismiss: (() -> Void)?

    /// The reader's hold on this surface. While it is set the island keeps its selection: it does not
    /// answer an outside click, and the coordinator lets a new selection pass by rather than replace
    /// it. Escape and the close button still get out, which is where the toolbar this came from drew
    /// the line too.
    private(set) var isPinned = false

    /// Names the panel an asynchronous step belongs to. The opening card hands its action over after
    /// an animation, and a press outlives the panel whenever a new selection replaces it meanwhile.
    private var panelGeneration = UUID()

    var isVisible: Bool { panel?.isVisible == true }

    func present(
        context: SelectionInvocation,
        actions: [DeloresContextAction],
        mode: DeloresContextIslandMode = .actions,
        metrics: InterfaceMetrics,
        onAction: @escaping (DeloresContextAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss(notifying: false)

        let size = DeloresContextIslandView.preferredSize(for: metrics)
        let root = DeloresContextIslandView(
            actions: actions,
            mode: mode,
            barHeight: size.height,
            onAction: { [weak self] action in
                self?.handOff(action, actions: actions, in: context.screen, metrics: metrics)
            },
            onTogglePin: { [weak self] pinned in self?.isPinned = pinned },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosted = root.environment(\.metrics, metrics)
        let hosting = DeloresFirstMouseHostingView(rootView: hosted)
        hosting.sizingOptions = []
        hosting.setFrameSize(size)

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

        let frame = DeloresContextIslandPlacement.collapsedFrame(in: context.screen, size: size)
        panel.setFrame(NSRect(origin: frame.origin, size: frame.size), display: false)
        // Escape closes what this surface put up, and nothing else: a Quick Action still running
        // behind `.busy` is not ours to cancel, so this only ever drops the island. While the card
        // is opening it cancels the press as well, because `onAction` does not fire until the
        // growth ends — the same generation token that guards a replaced panel guards this.
        panel.onEscape = { [weak self] in
            guard let self, self.isVisible else { return false }
            self.dismiss()
            return true
        }
        self.panel = panel
        self.onAction = onAction
        self.onDismiss = onDismiss
        // A panel replaces the one before it, so the hold on that one dies with it.
        isPinned = false
        panelGeneration = UUID()

        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    func showBusy(metrics: InterfaceMetrics) {
        guard let panel, panel.isVisible else { return }
        let size = DeloresContextIslandView.preferredSize(for: metrics)
        let root = DeloresContextIslandView(
            actions: [],
            mode: .busy,
            isPinned: isPinned,
            barHeight: size.height,
            onAction: { _ in },
            onTogglePin: { [weak self] pinned in self?.isPinned = pinned },
            onDismiss: { [weak self] in self?.dismiss() })
        let hosting = DeloresFirstMouseHostingView(rootView: root.environment(\.metrics, metrics))
        hosting.sizingOptions = []
        hosting.setFrameSize(size)
        let anchored = panel.frame
        panel.contentView = hosting
        panel.setFrame(
            DeloresContextIslandPlacement.frame(keepingTopEdgeOf: anchored, height: size.height),
            display: true)
    }

    /// The card's opening. The bar grows where it stands and only then hands the answer over, so the
    /// hand-off reads as one downward gesture instead of a window swap.
    ///
    /// The answer itself lands on the chat surface, which is a window of its own — its rectangle is
    /// the chat's to decide, so what this buys is the gesture, not geometric continuity.
    private enum Handoff {
        /// Long enough to be read as a gesture, short enough not to sit between press and answer.
        static let growth: TimeInterval = 0.20
    }

    private func handOff(
        _ action: DeloresContextAction,
        actions: [DeloresContextAction],
        in screen: InvocationScreen,
        metrics: InterfaceMetrics
    ) {
        // A pinned island is staying, so there is nowhere for the growth to carry the reader out of.
        // It exists to hand them to the chat and take the bar away behind them; here the bar stays,
        // and the press is the whole gesture either way.
        guard !isPinned else {
            onAction?(action)
            return
        }
        guard let panel, panel.isVisible else {
            onAction?(action)
            return
        }
        let generation = panelGeneration
        let anchored = panel.frame
        let height = DeloresContextIslandPlacement.expandedHeight(
            preferred: metrics.scaled(DeloresContextIslandPlacement.preferredExpandedHeight),
            in: screen)

        // Laid out for the card it becomes before the frame animates, so the growth reveals the card
        // rather than stretching the bar. Its own buttons are inert: one press is the whole gesture.
        let root = DeloresContextIslandView(
            actions: actions,
            mode: .handoff(progressTitle: action.progressTitle),
            barHeight: anchored.height,
            onAction: { _ in },
            onDismiss: { [weak self] in self?.dismiss() })
        let hosting = DeloresFirstMouseHostingView(rootView: root.environment(\.metrics, metrics))
        hosting.sizingOptions = []
        hosting.setFrameSize(NSSize(width: anchored.width, height: height))
        panel.contentView = hosting

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Handoff.growth
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(
                DeloresContextIslandPlacement.frame(keepingTopEdgeOf: anchored, height: height),
                display: true)
        } completionHandler: { [weak self] in
            // AppKit runs the handler on the main thread; the parameter just isn't typed for it.
            MainActor.assumeIsolated {
                // A new selection may have replaced this panel while the card was opening, and its
                // own press is the one that should run — this step stops rather than answer for it.
                guard let self, self.panelGeneration == generation else { return }
                // A shadow is cached from the frame it was first drawn at, so the one the bar grew
                // with is the bar's. Rebuild it before the card starts fading.
                self.panel?.invalidateShadow()
                self.onAction?(action)
                self.dismiss(notifying: false)
            }
        }
    }

    func dismiss(notifying: Bool = true) {
        guard let closing = panel else {
            if notifying { onDismiss?() }
            return
        }
        panel = nil
        panelGeneration = UUID()
        let callback = onDismiss
        onAction = nil
        onDismiss = nil
        isPinned = false
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
        guard !isPinned else { return }
        dismiss()
    }
}
