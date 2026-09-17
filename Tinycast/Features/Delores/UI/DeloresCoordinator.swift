@MainActor
final class DeloresCoordinator {
    private let context: DeloresContextCoordinator
    private let companion: DeloresCompanionCoordinator
    private let snapping: DeloresWindowSnapCoordinator
    private let divider: DeloresSplitDividerCoordinator
    private let interactionGate = DeloresSurfaceInteractionGate()
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
    }
    func applyEnabled() { context.applyEnabled(); companion.applyEnabled(); snapping.applyEnabled(); divider.applyEnabled() }
    var isHoldingPinnedContext: Bool { context.isHoldingPinnedContext }
    func prepareForTermination() {
        context.stop(); companion.prepareForTermination(); snapping.prepareForTermination(); divider.prepareForTermination(); interactionGate.reset()
    }
}
