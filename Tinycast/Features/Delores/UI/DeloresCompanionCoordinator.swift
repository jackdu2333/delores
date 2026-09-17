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
    private var strollTimer: Timer?
    private var wakeTimer: Timer?
    private var companion: DeloresCompanionPanel?
    private var currentSelection = ""
    private var wander: DeloresCompanionWander.State?
    private var isRunning = false
    /// A shell the Companion opened is on screen, so the body stands still. A body that walked out
    /// from under the bar it opened would leave the bar hanging over nothing — and the bar is hung
    /// on the body, not on the display.
    private var isHoldingShell = false
    private var lastWanderTick: TimeInterval = 0
    private var rng = SystemRandomNumberGenerator()
    /// Which way the body is looking, and how far through the walk cycle it is. A rest has neither a
    /// frame to advance nor a direction worth remembering, so both belong to the walk alone.
    private var facing: DeloresCompanionFacing = .right
    private var walkFrame = 0
    var onOpenContext: (() -> Void)?
    private static let companionDwellDuration: TimeInterval = 0.25
    private static let companionLeaveDuration: TimeInterval = 0.9
    /// How far off the visible edge the body rides, which is its own radius: a body drawn at the
    /// larger step stands further in, or it would hang off the display.
    private var bodyRadius: CGFloat { settings.deloresCompanionSize.radius }
    /// Frames while walking. A rest runs none at all, so this is the only frame cost there is — and
    /// the sprite's second ruling makes it the walk's frame rate too: one timer, step and frame both.
    private static var strollFrame: TimeInterval { DeloresCompanionAnimation.walkFrame }
    /// Monotonic, so a clock change cannot make a rest look overdue or a step look enormous.
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    init(settings: AppSettings, interactionGate: DeloresSurfaceInteractionGate, onOpenContext: (() -> Void)? = nil) {
        self.settings = settings; self.interactionGate = interactionGate; self.onOpenContext = onOpenContext
    }
    func applyEnabled() { settings.deloresCompanionEnabled ? startCompanion() : stopCompanion() }
    func prepareForTermination() { stopCompanion() }
    func recordSelection(_ text: String) { currentSelection = text; companion?.play(.glance) }

    // MARK: - Shells the Companion opened

    /// Where a shell opened on the display whose visible area is `visibleFrame` should hang: off the
    /// body, on whichever edge it is riding. Nil when there is no body to hang one from, which is
    /// the ordinary case and sends the bar back to the menu bar.
    ///
    /// The body comes to that display first if it is not already on it. A bar grown beside a body on
    /// another display is a bar nobody can see, and the reason for hanging it off the body is that
    /// it appears where the reader already is.
    func anchorForShell(in visibleFrame: CGRect) -> DeloresCompanionAnchor? {
        guard isRunning, let companion, companion.isVisible else { return nil }
        let bounds = visibleFrame.insetBy(dx: bodyRadius, dy: bodyRadius)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        var center = companion.center
        // A body on the perimeter is on the boundary of its bounds, which `contains` excludes.
        if !bounds.insetBy(dx: -1, dy: -1).contains(center) {
            // Carried across at the new display's middle height and the old body's own horizontal
            // preference, which `project` then lands on the edge nearest where the body came from —
            // the short way round, rather than a jump to a corner.
            center = DeloresCompanionWander.project(
                CGPoint(x: center.x, y: visibleFrame.midY), into: bounds)
            companion.move(to: center)
            wander = DeloresCompanionWander.settled(at: center, in: bounds, at: now, using: &rng)
            syncWanderTimers()
        }
        return (center, DeloresCompanionWander.edge(for: center, in: bounds), bodyRadius)
    }

    /// The body's standing point on `screen`, if it is standing on that screen at all. Unlike
    /// `anchorForShell(in:)` this never moves the body: a drag brought near it is not a wish for it
    /// to travel across displays, and an island beside where the body stands is already beside it.
    func bodyAnchor(on screen: NSScreen) -> DeloresCompanionAnchor? {
        guard isRunning, let companion, companion.isVisible else { return nil }
        guard let standing = DeloresWindowGeometry.screenContaining(companion.center),
            standing.frame == screen.frame
        else { return nil }
        return (
            companion.center,
            DeloresCompanionWander.edge(for: companion.center, in: companionBounds(on: standing)),
            bodyRadius
        )
    }

    /// Drawn at the other step. The body keeps the point it stands on and grows about it; where it
    /// may stand is its own radius, so a larger body has to be brought back inside the display.
    func applyCompanionSize() {
        guard let companion, companion.isVisible else { return }
        companion.applySize(settings.deloresCompanionSize)
        guard let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        let landed = DeloresCompanionWander.project(
            companion.center, into: companionBounds(on: screen))
        companion.move(to: landed)
        settle(at: landed, on: screen)
    }

    /// Stands the body still while a shell it opened is on screen.
    func holdForShell() {
        isHoldingShell = true
        stopWanderTimers()
        // It is standing still for as long as the shell is up, so it is idle rather than mid-step.
        companion?.rest()
    }

    /// The shell is gone, so the body may walk again.
    func releaseShell() {
        guard isHoldingShell else { return }
        isHoldingShell = false
        guard isRunning, let companion, companion.isVisible,
            let screen = DeloresWindowGeometry.screenContaining(companion.center)
        else { return }
        settle(at: companion.center, on: screen)
    }

    /// A shell did not fit where the body was standing and the body had to be moved along its edge
    /// to make room for it. The shell has already decided where; this only puts the body there.
    func relocate(to center: CGPoint, edge: DeloresCompanionEdge) {
        guard let companion,
            let screen = DeloresWindowGeometry.screenContaining(center)
        else { return }
        companion.move(to: center)
        wander = DeloresCompanionWander.settled(
            at: center, in: companionBounds(on: screen), at: now, using: &rng)
        syncWanderTimers()
    }
    private func captureCompanion(_ captured: Bool) {
        guard let companion else { return }
        if captured {
            guard interactionGate.claim(.companion) else { return }
            companion.setCaptured(true)
            stopWanderTimers()
            // Being picked up is not walking: the body stands in the reader's hand.
            companion.rest()
        } else {
            companion.setCaptured(false)
            interactionGate.release(.companion)
            guard isRunning, let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
            settle(at: companion.center, on: screen)
        }
    }
    private func startCompanion() {
        guard companionMonitor == nil, companionLocalMonitor == nil else { return }
        guard let screen = DeloresWindowGeometry.activeScreen() else { return }
        isRunning = true
        let panel = companion ?? DeloresCompanionPanel(size: settings.deloresCompanionSize)
        companion = panel
        panel.onSingleClick = { [weak self] in self?.companionSingleClick() }
        panel.onDoubleClick = { [weak self] in self?.companionDoubleClick() }
        panel.onLongPress = { [weak self] in self?.companion?.showBubble() }
        panel.onDrag = { [weak self] point in self?.dragCompanion(to: point) }
        panel.onDragEnded = { [weak self] point in self?.dropCompanion(at: point) }
        panel.ignoresMouseEvents = true
        let start = spawnPoint(on: screen)
        panel.present(at: start)
        settle(at: start, on: screen)

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
    }

    private func stopCompanion() {
        isRunning = false
        // The Companion is going away, so nothing it was holding itself still for survives it.
        isHoldingShell = false
        if let companionMonitor { NSEvent.removeMonitor(companionMonitor); self.companionMonitor = nil }
        if let companionLocalMonitor { NSEvent.removeMonitor(companionLocalMonitor); self.companionLocalMonitor = nil }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        companionDwellTimer?.invalidate(); companionDwellTimer = nil
        companionLeaveTimer?.invalidate(); companionLeaveTimer = nil
        stopWanderTimers()
        self.captureCompanion(false)
        companion?.hide(); companion = nil
        wander = nil
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

    /// Resting runs no frames at all: one wake is scheduled for the moment the rest ends. Walking is
    /// the only phase that costs a timer, which is the whole of the Companion's idle budget.
    private func syncWanderTimers() {
        // A body with nowhere to go is idle: being dragged, being held, or simply stopped.
        guard isRunning, let wander else { stopWanderTimers(); companion?.rest(); return }
        switch wander.phase {
        case .strolling:
            wakeTimer?.invalidate(); wakeTimer = nil
            guard strollTimer == nil else { return }
            lastWanderTick = now
            let timer = Timer(timeInterval: Self.strollFrame, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.advanceWander() }
            }
            strollTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .resting(let until):
            strollTimer?.invalidate(); strollTimer = nil
            wakeTimer?.invalidate()
            // Standing still is the idle row, and the breathing loop is a Core Animation animation:
            // it starts once and runs without the main thread, so a rest costs only the wake below.
            companion?.rest()
            let timer = Timer(timeInterval: max(0, until - now), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.advanceWander() }
            }
            wakeTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopWanderTimers() {
        strollTimer?.invalidate(); strollTimer = nil
        wakeTimer?.invalidate(); wakeTimer = nil
    }

    private func settle(at point: CGPoint, on screen: NSScreen) {
        wander = DeloresCompanionWander.settled(
            at: point, in: companionBounds(on: screen), at: now, using: &rng)
        syncWanderTimers()
    }

    private func advanceWander() {
        guard isRunning, !isHoldingShell, let companion, companion.isVisible, let state = wander
        else { return }
        guard let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        let tick = now
        let elapsed = tick - lastWanderTick
        lastWanderTick = tick
        let from = companion.center
        let next = DeloresCompanionWander.advance(
            state, elapsed: elapsed, now: tick, in: companionBounds(on: screen), using: &rng)
        wander = next
        companion.move(to: next.center)
        syncWanderTimers()
        guard case .strolling = next.phase else { return }
        // Ruling 3: the facing reads off the step's horizontal component, and a step with none keeps
        // what it had — a body on a vertical edge must not flip sides every frame.
        facing = DeloresCompanionAnimation.facing(from: from, to: next.center, fallback: facing)
        walkFrame += 1
        companion.step(frame: walkFrame % DeloresCompanionAnimation.walkFrameCount, facing: facing)
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

    private func dragCompanion(to point: CGPoint) {
        guard let companion, let screen = DeloresWindowGeometry.screenContaining(point) else { return }
        stopWanderTimers()
        wander = nil
        companion.move(to: DeloresCompanionWander.project(point, into: companionBounds(on: screen)))
    }

    /// A drop stays where it was let go and stands there a beat, which is also what makes the drop
    /// read as having landed.
    private func dropCompanion(at point: CGPoint) {
        guard let companion, let screen = DeloresWindowGeometry.screenContaining(point) else { return }
        let landed = DeloresCompanionWander.project(point, into: companionBounds(on: screen))
        companion.move(to: landed)
        settle(at: landed, on: screen)
    }

    private func relocateCompanion() {
        guard let companion, companion.isVisible else { return }
        guard let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        // A body on the perimeter is on the boundary of its bounds, which `contains` excludes.
        guard !companionBounds(on: screen).insetBy(dx: -1, dy: -1).contains(companion.center) else { return }
        let point = spawnPoint(on: screen)
        companion.move(to: point)
        settle(at: point, on: screen)
    }

    private func companionBounds(on screen: NSScreen) -> CGRect {
        screen.visibleFrame.insetBy(dx: bodyRadius, dy: bodyRadius)
    }

    private func spawnPoint(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.visibleFrame.maxX - bodyRadius, y: screen.visibleFrame.midY)
    }
}
