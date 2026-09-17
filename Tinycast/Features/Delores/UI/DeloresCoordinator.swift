@MainActor
final class DeloresCoordinator {
    private let context: DeloresContextCoordinator
    private let companion: DeloresCompanionCoordinator
    private let snapping: DeloresWindowSnapCoordinator
    private let divider: DeloresSplitDividerCoordinator
    private let interactionGate = DeloresSurfaceInteractionGate()
    /// Whether the launch call has already been made, so only that one waits.
    private var hasLaunchedOnce = false
    init(settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector, aiChat: AIChatCoordinator) {
        let gate = interactionGate
        let context = DeloresContextCoordinator(settings: settings, quickActions: quickActions, injector: injector, aiChat: aiChat, interactionGate: gate)
        let companion = DeloresCompanionCoordinator(settings: settings, interactionGate: gate, onOpenContext: { [weak context] in context?.showLastCapturedSelection() })
        let snapping = DeloresWindowSnapCoordinator(settings: settings, interactionGate: gate)
        let divider = DeloresSplitDividerCoordinator(settings: settings, interactionGate: gate)
        snapping.onWindowGeometryChanged = { [weak divider] point in divider?.windowGeometryDidChange(at: point) }
        snapping.onWindowSnapped = { [weak divider] window, slot, rect, screen in divider?.registerSnappedWindow(window, slot: slot, rect: rect, screen: screen) }
        self.context = context; self.companion = companion; self.snapping = snapping; self.divider = divider
        context.onSelectionPresented = { [weak companion] text in companion?.recordSelection(text) }
        // The Companion is the bar's other home: with it on, a bar grows out of the body's inward
        // side rather than down out of the menu bar.
        context.companionHosting = DeloresContextCompanionHosting(
            anchor: { [weak companion] visibleFrame in companion?.anchorForShell(in: visibleFrame) },
            relocate: { [weak companion] center, edge in companion?.relocate(to: center, edge: edge) },
            held: { [weak companion] isHeld in
                if isHeld { companion?.holdForShell() } else { companion?.releaseShell() }
            })
        // A snap island grows out of the body the same way: with the Companion on, a window is
        // brought to the body itself, and only a display the body is not standing on still has the
        // top-centre fallback. Read-only — a drag must not move the body to meet it.
        snapping.companionAnchor = { [weak companion] screen in companion?.bodyAnchor(on: screen) }
        // A drag brought to the body stops it: the island is placed from where the body stood when
        // the drag found it, so it stands there until the drag is over.
        snapping.onBodyHoldChanged = { [weak companion] isHeld in
            if isHeld { companion?.holdForShell() } else { companion?.releaseShell() }
        }
    }

    /// The body is drawn at another step, which changes where it may stand as well as how big it is.
    func applyCompanionSize() { companion.applyCompanionSize() }
    func applyEnabled() {
        // The first call is launch, and the main actor is still digesting startup: every mouse
        // event these surfaces install lands on it, and a backlog at launch is paid in the apps
        // the reader clicks into. Give startup a beat before the surfaces go live; a settings
        // change after that still applies immediately.
        guard hasLaunchedOnce else {
            hasLaunchedOnce = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.applyEnabled()
            }
            return
        }
        context.applyEnabled(); companion.applyEnabled(); snapping.applyEnabled(); divider.applyEnabled()
    }
    var isHoldingPinnedContext: Bool { context.isHoldingPinnedContext }
    func prepareForTermination() {
        context.stop(); companion.prepareForTermination(); snapping.prepareForTermination(); divider.prepareForTermination(); interactionGate.reset()
    }
}
