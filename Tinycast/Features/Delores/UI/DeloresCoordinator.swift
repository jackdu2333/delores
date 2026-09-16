/// The only Delores lifecycle seam exposed to AppCore.
@MainActor
final class DeloresCoordinator {
    private let context: DeloresContextCoordinator

    init(settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector) {
        context = DeloresContextCoordinator(
            settings: settings, quickActions: quickActions, injector: injector)
    }

    func applyEnabled() {
        context.applyEnabled()
    }

    func prepareForTermination() {
        context.stop()
    }
}
