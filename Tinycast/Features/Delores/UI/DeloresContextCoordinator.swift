import AppKit
import Observation

/// Routes a captured selection to the shared Quick Action capability.
@MainActor
@Observable
final class DeloresContextCoordinator {
    private let settings: AppSettings
    private let quickActions: QuickActionCoordinator
    private let injector: TextInjector
    private let island: DeloresContextIslandController
    private let gestureMonitor: SelectionGestureMonitor

    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private var captureGeneration = UUID()
    @ObservationIgnored private var lastFingerprint: DeloresSelectionFingerprint?
    @ObservationIgnored private var lastSelectionUptime = -Double.infinity
    @ObservationIgnored private var targetApplication: NSRunningApplication?

    private(set) var context: InvocationContext?
    private(set) var isMonitoring = false

    init(settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector) {
        self.settings = settings
        self.quickActions = quickActions
        self.injector = injector

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
        island.dismiss(notifying: false)
        clearContext()
    }

    private func captureSelection(after gesture: SelectionGestureMonitor.Gesture) {
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

        island.present(
            context: selection,
            actions: DeloresContextAction.defaults,
            metrics: settings.interfaceSize.metrics,
            onAction: { [weak self] action in self?.run(action) },
            onDismiss: { [weak self] in self?.surfaceDismissed() })
    }

    private func run(_ action: DeloresContextAction) {
        guard case .selection(let selection) = context, let targetApplication else { return }
        let result = quickActions.run(
            .builtIn(action.builtIn),
            selection: selection.text,
            target: targetApplication)
        switch result {
        case .started:
            island.dismiss(notifying: false)
            clearContext()
        case .busy:
            island.showBusy(metrics: settings.interfaceSize.metrics)
        case .disabled:
            island.dismiss(notifying: false)
            clearContext()
        }
    }

    private func surfaceDismissed() {
        clearContext()
    }

    private func clearContext() {
        context = nil
        targetApplication = nil
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
