/// The only Delores lifecycle seam exposed to AppCore.
@MainActor
final class DeloresCoordinator {
    private let context: DeloresContextCoordinator
    private let spatial: DeloresSpatialCoordinator
    /// Shared because a mouse drag belongs to exactly one surface: the window drag that Spatial
    /// claims must not also read as the selection that Context captures.
    private let interactionGate = DeloresSurfaceInteractionGate()

    init(
        settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector,
        aiChat: AIChatCoordinator
    ) {
        let gate = interactionGate
        let context = DeloresContextCoordinator(
            settings: settings, quickActions: quickActions, injector: injector, aiChat: aiChat,
            interactionGate: gate)
        let spatial = DeloresSpatialCoordinator(
            settings: settings, interactionGate: gate,
            onOpenContext: { [weak context] in
                context?.showLastCapturedSelection()
            })
        self.context = context
        self.spatial = spatial
        context.onSelectionPresented = { [weak spatial] text in
            spatial?.recordSelection(text)
        }
    }

    func applyEnabled() {
        context.applyEnabled()
        spatial.applyEnabled()
    }

    /// Forwarded for the same reason `isShowingDialog` is routed through `AppCore`: a surface that
    /// lost the keyboard needs to know whether the reader is holding another one of ours.
    var isHoldingPinnedContext: Bool { context.isHoldingPinnedContext }

    func prepareForTermination() {
        context.stop()
        spatial.prepareForTermination()
        interactionGate.reset()
    }
}
