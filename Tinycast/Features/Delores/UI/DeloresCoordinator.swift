/// The only Delores lifecycle seam exposed to AppCore.
@MainActor
final class DeloresCoordinator {
    private let context: DeloresContextCoordinator

    init(
        settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector,
        aiChat: AIChatCoordinator
    ) {
        context = DeloresContextCoordinator(
            settings: settings, quickActions: quickActions, injector: injector, aiChat: aiChat)
    }

    func applyEnabled() {
        context.applyEnabled()
    }

    /// Forwarded for the same reason `isShowingDialog` is routed through `AppCore`: a surface that
    /// lost the keyboard needs to know whether the reader is holding another one of ours.
    var isHoldingPinnedContext: Bool { context.isHoldingPinnedContext }

    func prepareForTermination() {
        context.stop()
    }
}
