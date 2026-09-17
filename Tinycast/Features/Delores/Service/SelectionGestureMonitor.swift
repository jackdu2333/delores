import AppKit

/// Detects a completed selection gesture without reading the target app.
@MainActor
final class SelectionGestureMonitor {
    struct Gesture: Sendable {
        let screenPoint: CGPoint
        let timestamp: Date
        let uptime: TimeInterval
        let kind: DeloresSelectionGesturePolicy.Kind
    }

    typealias Handler = @MainActor (Gesture) -> Void

    var onGesture: Handler?

    private let shouldIgnorePoint: @MainActor (CGPoint) -> Bool
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var pendingCapture: Task<Void, Never>?
    private var mouseDownPoint: CGPoint = .zero
    private var hasMouseDown = false
    private var lastMouseUpPoint: CGPoint = .zero
    private var lastMouseUpUptime = -Double.infinity
    private(set) var isRunning = false

    init(shouldIgnorePoint: @escaping @MainActor (CGPoint) -> Bool) {
        self.shouldIgnorePoint = shouldIgnorePoint
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.recordMouseDown(at: point)
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            let point = NSEvent.mouseLocation
            let uptime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                self?.recordMouseUp(at: point, uptime: uptime)
            }
        }
    }

    func stop() {
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        if let mouseUpMonitor {
            NSEvent.removeMonitor(mouseUpMonitor)
            self.mouseUpMonitor = nil
        }
        pendingCapture?.cancel()
        pendingCapture = nil
        mouseDownPoint = .zero
        lastMouseUpPoint = .zero
        lastMouseUpUptime = -Double.infinity
        hasMouseDown = false
        isRunning = false
    }

    private func recordMouseDown(at point: CGPoint) {
        guard isRunning else { return }
        mouseDownPoint = point
        hasMouseDown = true
    }

    private func recordMouseUp(at point: CGPoint, uptime: TimeInterval) {
        guard isRunning else { return }
        let dragDistance = hasMouseDown
            ? hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            : 0
        let previousReleaseDistance: CGFloat? = lastMouseUpUptime == -Double.infinity
            ? nil
            : hypot(point.x - lastMouseUpPoint.x, point.y - lastMouseUpPoint.y)
        let gestureKind = DeloresSelectionGesturePolicy.qualifies(
            dragDistance: dragDistance,
            previousReleaseDistance: previousReleaseDistance,
            elapsedSincePreviousRelease: lastMouseUpUptime == -Double.infinity
                ? nil
                : uptime - lastMouseUpUptime)

        hasMouseDown = false
        lastMouseUpPoint = point
        lastMouseUpUptime = uptime

        guard let gestureKind, !shouldIgnorePoint(point) else { return }

        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.onGesture?(
                Gesture(
                    screenPoint: point,
                    timestamp: Date(),
                    uptime: uptime,
                    kind: gestureKind))
        }
    }
}
