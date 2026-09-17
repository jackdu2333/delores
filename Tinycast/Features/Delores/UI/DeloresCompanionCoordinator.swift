import AppKit
import SwiftUI
@MainActor
final class DeloresCompanionCoordinator {
    private let settings: AppSettings
    private let interactionGate: DeloresSurfaceInteractionGate
    private var companionMonitor: Any?
    private var companionLocalMonitor: Any?
    private var companionDwellTimer: Timer?
    private var companionLeaveTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var patrolTimer: Timer?
    private var companion: DeloresCompanionPanel?
    private var currentSelection = ""
    var onOpenContext: (() -> Void)?
    private var lastPatrolTick = Date()
    private var patrolEdge: DeloresCompanionEdge = .right
    private var patrolDirection: CGFloat = 1
    private static let companionDwellDuration: TimeInterval = 0.25
    private static let companionLeaveDuration: TimeInterval = 0.9
    private static let companionVisibleRadius: CGFloat = 14
    private static let companionPatrolSpeed: CGFloat = 30
    init(settings: AppSettings, interactionGate: DeloresSurfaceInteractionGate, onOpenContext: (() -> Void)? = nil) {
        self.settings = settings; self.interactionGate = interactionGate; self.onOpenContext = onOpenContext
    }
    func applyEnabled() { settings.deloresCompanionEnabled ? startCompanion() : stopCompanion() }
    func prepareForTermination() { stopCompanion() }
    func recordSelection(_ text: String) { currentSelection = text; companion?.play(.glance) }
    private func captureCompanion(_ captured: Bool) {
        guard let companion else { return }
        if captured {
            guard interactionGate.claim(.companion) else { return }
            companion.setCaptured(true)
        } else {
            companion.setCaptured(false)
            interactionGate.release(.companion)
        }
    }
    private func startCompanion() {
        guard companionMonitor == nil, companionLocalMonitor == nil else { return }
        guard let screen = DeloresWindowGeometry.activeScreen() else { return }
        let panel = companion ?? DeloresCompanionPanel()
        companion = panel
        panel.onSingleClick = { [weak self] in self?.companionSingleClick() }
        panel.onDoubleClick = { [weak self] in self?.companionDoubleClick() }
        panel.onLongPress = { [weak self] in self?.companion?.showBubble() }
        panel.onDrag = { [weak self] point in self?.moveCompanion(to: point) }
        panel.ignoresMouseEvents = true
        panel.present(at: spawnPoint(on: screen))
        lastPatrolTick = Date()

        companionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handleCompanionPointer(at: point) }
        }
        companionLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handleCompanionPointer(at: point) }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.relocateCompanion() }
        }
        patrolTimer?.invalidate()
        patrolTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.patrolCompanion() }
        }
        if let patrolTimer { RunLoop.main.add(patrolTimer, forMode: .common) }
    }

    private func stopCompanion() {
        if let companionMonitor { NSEvent.removeMonitor(companionMonitor); self.companionMonitor = nil }
        if let companionLocalMonitor { NSEvent.removeMonitor(companionLocalMonitor); self.companionLocalMonitor = nil }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        companionDwellTimer?.invalidate(); companionDwellTimer = nil
        companionLeaveTimer?.invalidate(); companionLeaveTimer = nil
        patrolTimer?.invalidate(); patrolTimer = nil
        self.captureCompanion(false)
        companion?.hide(); companion = nil
        currentSelection = ""
    }

    private func companionSingleClick() { companion?.play(.glance) }

    private func companionDoubleClick() {
        if currentSelection.isEmpty {
            companion?.showBubble()
        } else {
            onOpenContext?()
        }
    }

    private func patrolCompanion() {
        guard let companion, companion.isVisible, !companion.isCaptured else { return }
        let now = Date()
        let dt = min(0.25, now.timeIntervalSince(lastPatrolTick))
        lastPatrolTick = now
        guard dt > 0, let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        let bounds = companionBounds(on: screen)
        let edge = nearestEdge(companion.center, bounds)
        if edge != patrolEdge {
            patrolEdge = edge
            patrolDirection = 1
        }
        let step = Self.companionPatrolSpeed * CGFloat(dt) * patrolDirection
        var point = companion.center
        switch edge {
        case .left, .right: point.y += step
        case .top, .bottom: point.x += step
        }
        let settled = snapPoint(point, edge: edge, in: bounds)
        // The clamp is the corner: turn around rather than sit there grinding against the edge.
        if settled != point { patrolDirection *= -1 }
        companion.move(to: settled)
    }

    private func handleCompanionPointer(at point: CGPoint) {
        guard let companion, companion.isVisible else { return }
        let isInside = companion.frame.contains(point)
        if isInside {
            companionLeaveTimer?.invalidate(); companionLeaveTimer = nil
            guard !companion.isCaptured, companionDwellTimer == nil else { return }
            let timer = Timer(timeInterval: Self.companionDwellDuration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.companionDwellTimer = nil
                    guard let companion = self.companion, companion.isVisible,
                          companion.frame.contains(NSEvent.mouseLocation) else { return }
                    self.captureCompanion(true)
                }
            }
            companionDwellTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            companionDwellTimer?.invalidate(); companionDwellTimer = nil
            guard companion.isCaptured, companionLeaveTimer == nil else { return }
            let timer = Timer(timeInterval: Self.companionLeaveDuration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.companion != nil else { return }
                    self.captureCompanion(false)
                    self.companionLeaveTimer = nil
                }
            }
            companionLeaveTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func moveCompanion(to point: CGPoint) {
        guard let companion, let screen = DeloresWindowGeometry.screenContaining(point) else { return }
        companion.move(to: snapPoint(point, edge: nearestEdge(point, screen.visibleFrame), in: companionBounds(on: screen)))
    }

    private func relocateCompanion() {
        guard let companion, companion.isVisible else { return }
        guard let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        guard !companionBounds(on: screen).contains(companion.center) else { return }
        companion.move(to: spawnPoint(on: screen))
    }
    private func companionBounds(on screen: NSScreen) -> CGRect {
        screen.visibleFrame.insetBy(dx: Self.companionVisibleRadius, dy: Self.companionVisibleRadius)
    }
    private func spawnPoint(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.visibleFrame.maxX - Self.companionVisibleRadius, y: screen.visibleFrame.midY)
    }
    private func nearestEdge(_ point: CGPoint, _ frame: CGRect) -> DeloresCompanionEdge {
        let distances: [(DeloresCompanionEdge, CGFloat)] = [
            (.left, abs(point.x - frame.minX)),
            (.right, abs(frame.maxX - point.x)),
            (.top, abs(frame.maxY - point.y)),
            (.bottom, abs(point.y - frame.minY)),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    /// Puts a point onto the given edge, keeping its position along that edge.
    private func snapPoint(
        _ point: CGPoint, edge: DeloresCompanionEdge, in frame: CGRect
    ) -> CGPoint {
        let x = min(max(point.x, frame.minX), frame.maxX)
        let y = min(max(point.y, frame.minY), frame.maxY)
        switch edge {
        case .left: return CGPoint(x: frame.minX, y: y)
        case .right: return CGPoint(x: frame.maxX, y: y)
        case .top: return CGPoint(x: x, y: frame.maxY)
        case .bottom: return CGPoint(x: x, y: frame.minY)
        }
    }
}
