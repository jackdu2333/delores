import AppKit
import SwiftUI
@MainActor
final class DeloresCompanionCoordinator {
    private let settings: AppSettings
    private let interactionGate: DeloresSurfaceInteractionGate
    private let companionMode: @MainActor () -> DeloresCompanionMode
    private var companionMonitor: Any?
    private var companionLocalMonitor: Any?
    private var companionDwellTimer: Timer?
    private var companionLeaveTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    private var isHiddenForFullscreen = false
    private var strollTimer: Timer?
    private var wakeTimer: Timer?
    private var typingWatchTimer: Timer?
    private var companion: DeloresCompanionPanel?
    private let companionMenu = DeloresCompanionMenuController()
    private var currentSelection = ""
    private var wander: DeloresCompanionWander.State?
    private var isRunning = false
    /// A shell the Companion opened is on screen, so the body stands still. A body that walked out
    /// from under the bar it opened would leave the bar hanging over nothing — and the bar is hung
    /// on the body, not on the display.
    ///
    /// Counted rather than flagged: a bar and a snap island can both be up, and whichever is
    /// dismissed first must not set the body walking while the other is still hung on it.
    private var shellHolds = 0
    private var isHoldingShell: Bool { shellHolds > 0 }
    private var lastWanderTick: TimeInterval = 0
    private var rng = SystemRandomNumberGenerator()
    /// Which way the body is looking, and how far through the walk cycle it is. A rest has neither a
    /// frame to advance nor a direction worth remembering, so both belong to the walk alone.
    ///
    /// `walkElapsed` is the pose's own clock, counted out of the ticks that move the body: the two
    /// rates are whole multiples of each other, so the cadence cannot drift.
    private var facing: DeloresCompanionFacing = .right
    private var walkFrame = 0
    private var walkElapsed: TimeInterval = 0
    var onOpenContext: (() -> Void)?
    private static let companionDwellDuration: TimeInterval = 0.25
    private static let companionLeaveDuration: TimeInterval = 0.9
    /// How often the typing pause is re-checked once the body has stood still for it. The walk's
    /// own timers are stopped for the pause, so something has to notice the typing ended.
    private static let typingWatchStep: TimeInterval = 0.5
    /// How far off the visible edge the body rides, which is its own radius: a body drawn at the
    /// larger step stands further in, or it would hang off the display.
    private var bodyRadius: CGFloat { settings.deloresCompanionSize.radius }
    /// How often the body is moved while walking.
    private static var strollStep: TimeInterval { DeloresCompanionAnimation.walkStep }
    /// Monotonic, so a clock change cannot make a rest look overdue or a step look enormous.
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    init(
        settings: AppSettings, interactionGate: DeloresSurfaceInteractionGate,
        companionMode: @escaping @MainActor () -> DeloresCompanionMode,
        onOpenContext: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.interactionGate = interactionGate
        self.companionMode = companionMode
        self.onOpenContext = onOpenContext
    }
    func applyEnabled() {
        companionMode().usesDeloresPet ? startCompanion() : stopCompanion()
    }
    func prepareForTermination() { stopCompanion() }
    func recordSelection(_ text: String) { currentSelection = text; companion?.play(.glance) }

    /// The reader is waiting on an answer, and the surface that would have said so has stepped aside
    /// for the body.
    ///
    /// Idempotent in both directions on purpose: the wait's real end is a stream, and a pose asked
    /// for twice is a pose restarted mid-cycle — which is a twitch the reader did not ask for.
    func setThinking(_ thinking: Bool) {
        guard let companion, companion.isVisible else { return }
        thinking ? companion.startThinking() : companion.stopThinking()
    }

    // MARK: - Shells the Companion opened

    /// Where a shell opened on the display whose visible area is `visibleFrame` should hang: off the
    /// body, on whichever edge it is riding. Nil when there is no body to hang one from, which is
    /// the ordinary case and sends the bar back to the menu bar.
    ///
    /// The body comes to that display first if it is not already on it. A bar grown beside a body on
    /// another display is a bar nobody can see, and the reason for hanging it off the body is that
    /// it appears where the reader already is.
    func anchorForShell(in visibleFrame: CGRect) -> DeloresCompanionAnchor? {
        guard isRunning, !isHiddenForFullscreen, let companion, companion.isVisible else { return nil }
        // The display the shell is being grown on, found from the visible frame it was asked about.
        guard let screen = DeloresWindowGeometry.screenContaining(
            CGPoint(x: visibleFrame.midX, y: visibleFrame.midY))
        else { return nil }
        let loop = loop(on: screen)
        guard !loop.isEmpty else { return nil }
        var center = wander?.center ?? companion.center
        let standing = DeloresWindowGeometry.screenContaining(center)
        // Same-display includes the menu bar; `visibleFrame.contains` does not.
        if !DeloresCompanionShell.isOnSameDisplay(
            bodyScreenFrame: standing?.frame, shellScreenFrame: screen.frame)
        {
            center = DeloresCompanionWander.project(
                CGPoint(x: center.x, y: visibleFrame.midY), into: loop)
            companion.move(to: center)
            wander = DeloresCompanionWander.settled(at: center, in: loop, at: now, using: &rng)
            syncWanderTimers()
        }
        return (
            center,
            DeloresCompanionWander.edge(for: center, in: companionBounds(on: screen)),
            bodyRadius
        )
    }

    /// The body's standing point on `screen`, if it is standing on that screen at all. Unlike
    /// `anchorForShell(in:)` this never moves the body: a drag brought near it is not a wish for it
    /// to travel across displays, and an island beside where the body stands is already beside it.
    func bodyAnchor(on screen: NSScreen) -> DeloresCompanionAnchor? {
        guard isRunning, !isHiddenForFullscreen, let companion, companion.isVisible else { return nil }
        let center = wander?.center ?? companion.center
        guard let standing = DeloresWindowGeometry.screenContaining(center),
            standing.frame == screen.frame
        else { return nil }
        return (
            center,
            DeloresCompanionWander.edge(for: center, in: companionBounds(on: standing)),
            bodyRadius
        )
    }

    /// Drawn at the other step. The body keeps the point it stands on and grows about it; where it
    /// may stand is its own radius, so a larger body has to be brought back inside the display.
    func applyCompanionSize() {
        guard let companion, companion.isVisible else { return }
        companion.applySize(settings.deloresCompanionSize)
        let center = wander?.center ?? companion.center
        guard let screen = DeloresWindowGeometry.screenContaining(center) else { return }
        let landed = DeloresCompanionWander.project(center, into: loop(on: screen))
        companion.move(to: landed)
        settle(at: landed, on: screen)
    }

    func applyCompanionKind() {
        guard let companion, companion.isVisible else { return }
        companion.applyKind(settings.deloresCompanionKind)
    }

    /// Stands the body still while a shell it opened is on screen.
    func holdForShell() {
        shellHolds += 1
        stopWanderTimers()
        walkElapsed = 0
        walkFrame = 0
        if let wander { companion?.move(to: wander.center) }
        companion?.rest()
    }

    /// The shell is gone, so the body may walk again — once nothing else is holding it.
    func releaseShell() {
        guard shellHolds > 0 else { return }
        shellHolds -= 1
        guard !isHoldingShell else { return }
        let center = wander?.center ?? companion?.center
        guard isRunning, let companion, companion.isVisible, let center,
            let screen = DeloresWindowGeometry.screenContaining(center)
        else { return }
        settle(at: center, on: screen)
    }

    /// A shell did not fit where the body was standing and the body had to be moved along its edge
    /// to make room for it. The shell has already decided where; this only puts the body there.
    func relocate(to center: CGPoint, edge: DeloresCompanionEdge) {
        guard let companion,
            let screen = DeloresWindowGeometry.screenContaining(center)
        else { return }
        companion.move(to: center)
        wander = DeloresCompanionWander.settled(at: center, in: loop(on: screen), at: now, using: &rng)
        syncWanderTimers()
    }
    private func captureCompanion(_ captured: Bool) {
        guard let companion else { return }
        if captured {
            guard interactionGate.claim(.companion) else { return }
            companion.setCaptured(true)
            stopWanderTimers()
            walkElapsed = 0
            walkFrame = 0
            if let wander { companion.move(to: wander.center) }
            companion.rest()
        } else {
            companion.setCaptured(false)
            interactionGate.release(.companion)
            let center = wander?.center ?? companion.center
            guard isRunning, let screen = DeloresWindowGeometry.screenContaining(center) else { return }
            settle(at: center, on: screen)
        }
    }
    private func startCompanion() {
        guard companionMonitor == nil, companionLocalMonitor == nil else { return }
        guard let screen = DeloresWindowGeometry.activeScreen() else { return }
        isRunning = true
        let panel = companion ?? DeloresCompanionPanel(size: settings.deloresCompanionSize, kind: settings.deloresCompanionKind)
        panel.applyKind(settings.deloresCompanionKind)
        companion = panel
        panel.onSingleClick = { [weak self] in self?.companionSingleClick() }
        panel.onDoubleClick = { [weak self] in self?.companionDoubleClick() }
        panel.onAccessibilityPress = { [weak self] in self?.companionDoubleClick() }
        panel.onLongPress = { [weak self] in self?.companion?.showBubble() }
        panel.onDrag = { [weak self] point in self?.dragCompanion(to: point) }
        panel.onDragEnded = { [weak self] point in self?.dropCompanion(at: point) }
        panel.onRightClick = { [weak self] in self?.companionRightClick() }
        companionMenu.onClose = { [weak self] in self?.releaseShell() }
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
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateFullscreenPresence()
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.evaluateFullscreenPresence()
            }
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateFullscreenPresence()
            }
        }
        evaluateFullscreenPresence()
    }

    private func evaluateFullscreenPresence() {
        guard isRunning else { return }
        let fullscreen = AXWindowAccess.isFrontmostAppFullscreen()
        if fullscreen && !isHiddenForFullscreen {
            isHiddenForFullscreen = true
            stopWanderTimers()
            companionMenu.hide()
            companion?.hide()
        } else if !fullscreen && isHiddenForFullscreen {
            isHiddenForFullscreen = false
            guard let companion else { return }
            var center = wander?.center ?? companion.center
            let screen = DeloresWindowGeometry.screenContaining(center)
                ?? DeloresWindowGeometry.activeScreen()
            guard let screen else { return }
            let bounds = companionBounds(on: screen)
            if !bounds.insetBy(dx: -1, dy: -1).contains(center) {
                center = spawnPoint(on: screen)
            }
            companion.present(at: center)
            settle(at: center, on: screen)
        }
    }

    private func stopCompanion() {
        isRunning = false
        // Anything the body opened goes with it, the menu included.
        companionMenu.hide()
        // The Companion is going away, so nothing it was holding itself still for survives it.
        shellHolds = 0
        if let companionMonitor { NSEvent.removeMonitor(companionMonitor); self.companionMonitor = nil }
        if let companionLocalMonitor { NSEvent.removeMonitor(companionLocalMonitor); self.companionLocalMonitor = nil }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver); self.spaceObserver = nil }
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver); self.appObserver = nil }
        isHiddenForFullscreen = false
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

    /// The two things a reader asks about the body itself: which creature it is, and whether it is
    /// there at all. Both rows write the keys the Settings pane writes, so this is an entry point to
    /// two settings rather than a configuration surface the body grew of its own.
    private func companionRightClick() {
        guard let companion, companion.isVisible else { return }
        holdForShell()
        let center = wander?.center ?? companion.center
        guard let screen = DeloresWindowGeometry.screenContaining(center) else { return }
        let anchor = DeloresCompanionMenuController.Anchor(
            petCenter: center,
            petFrame: companion.frame,
            edge: DeloresCompanionWander.edge(for: center, in: companionBounds(on: screen)),
            bodyRadius: bodyRadius,
            visibleFrame: screen.visibleFrame)
        let landed = companionMenu.show(
            companionMenuItems(), anchoredTo: anchor, metrics: settings.interfaceSize.metrics)
        guard landed != center else { return }
        companion.move(to: landed)
    }

    private func companionMenuItems() -> [PopoverMenuItem] {
        let creatures = DeloresCompanionShell.Kind.allCases.map { kind in
            PopoverMenuItem.chrome(
                title: kind.displayName, icon: .blank,
                detail: kind == settings.deloresCompanionKind ? "Current" : nil,
                action: { [weak self] in self?.settings.deloresCompanionKind = kind })
        }
        return creatures + [
            PopoverMenuItem.chrome(
                title: "Turn off the companion", icon: .symbol("eye.slash"), startsSection: true,
                detail: "Bring the menu bar back",
                action: { [weak self] in self?.settings.deloresCompanionMode = .off }),
        ]
    }

    /// Resting runs no frames at all: one wake is scheduled for the moment the rest ends. Walking is
    /// the only phase that costs a timer, which is the whole of the Companion's idle budget.
    private func syncWanderTimers() {
        // A body with nowhere to go is idle: being dragged, being held, or simply stopped.
        guard isRunning, !isHoldingShell, let wander else {
            stopWanderTimers(); companion?.rest(); return
        }
        // The single arming point, so nowhere arms a walk while the reader is typing.
        guard !readerIsTyping() else { pauseWanderForTyping(); return }
        switch wander.phase {
        case .strolling:
            wakeTimer?.invalidate(); wakeTimer = nil
            guard strollTimer == nil else { return }
            lastWanderTick = now
            let timer = Timer(timeInterval: Self.strollStep, repeats: true) { [weak self] _ in
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
        typingWatchTimer?.invalidate(); typingWatchTimer = nil
    }

    /// Whether the reader is typing. CGEventSource reports how long ago the last keypress landed
    /// rather than the keys themselves, so it observes no events and needs no permission the
    /// Companion does not already run under.
    private func readerIsTyping() -> Bool {
        DeloresCompanionWander.readerIsTyping(
            secondsSinceLastKey: CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: .keyDown))
    }

    /// The body stands still while the reader types, wherever it was — a pet strolling the menu
    /// bar while a sentence is being written reads as a distraction, not a companion. The wander
    /// state is left alone, so the body resumes the very trip it was frozen in.
    private func pauseWanderForTyping() {
        stopWanderTimers()
        companion?.rest()
        let timer = Timer(timeInterval: Self.typingWatchStep, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.watchForTypingEnd() }
        }
        typingWatchTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// The typing has ended, so the body may walk again.
    private func watchForTypingEnd() {
        guard !readerIsTyping() else { return }
        typingWatchTimer?.invalidate(); typingWatchTimer = nil
        syncWanderTimers()
    }

    private func settle(at point: CGPoint, on screen: NSScreen) {
        walkElapsed = 0
        walkFrame = 0
        wander = DeloresCompanionWander.settled(
            at: point, in: loop(on: screen), at: now, using: &rng)
        syncWanderTimers()
    }

    private func advanceWander() {
        guard isRunning, !isHiddenForFullscreen, !isHoldingShell, let companion, companion.isVisible, let state = wander
        else { return }
        // The timers call here without passing through sync, so the pause is guarded at the gate too.
        guard !readerIsTyping() else { pauseWanderForTyping(); return }
        let center = state.center
        guard let screen = DeloresWindowGeometry.screenContaining(center) else { return }
        let tick = now
        let elapsed = tick - lastWanderTick
        lastWanderTick = tick
        let from = state.center
        if case .resting = state.phase {
            let next = DeloresCompanionWander.advance(
                state, elapsed: elapsed, now: tick, in: loop(on: screen), using: &rng)
            wander = next
            syncWanderTimers()
            guard case .strolling = next.phase else { return }
            walkElapsed = 0
            walkFrame = 0
            facing = DeloresCompanionAnimation.facing(from: from, to: next.center, fallback: facing)
            companion.step(frame: 0, facing: facing)
            companion.move(to: next.center)
            return
        }
        let currentFrame = walkFrame % DeloresCompanionAnimation.walkFrameCount
        let isPushOff = (currentFrame == 1 || currentFrame == 3)
        let gaitWeight: Double = isPushOff ? 1.3 : 0.7
        let effectiveElapsed = elapsed * gaitWeight
        let next = DeloresCompanionWander.advance(
            state, elapsed: effectiveElapsed, now: tick, in: loop(on: screen), using: &rng)
        wander = next
        syncWanderTimers()
        guard case .strolling = next.phase else {
            walkElapsed = 0
            walkFrame = 0
            companion.move(to: next.center)
            return
        }
        walkElapsed += elapsed
        if walkElapsed >= DeloresCompanionAnimation.walkFrame {
            let framesAdvanced = Int(walkElapsed / DeloresCompanionAnimation.walkFrame)
            walkElapsed = walkElapsed.truncatingRemainder(dividingBy: DeloresCompanionAnimation.walkFrame)
            walkFrame += framesAdvanced
        }
        let displayFrame = walkFrame % DeloresCompanionAnimation.walkFrameCount
        facing = DeloresCompanionAnimation.facing(from: from, to: next.center, fallback: facing)
        companion.step(frame: displayFrame, facing: facing)
        var displayCenter = next.center
        let isBobbingFrame = displayFrame == 1 || displayFrame == 3
        if isBobbingFrame, abs(next.center.x - from.x) > 0.0001 {
            displayCenter.y += 1.5
        }
        companion.move(to: displayCenter)
    }

    private func handleCompanionPointer(at point: CGPoint) {
        guard !isHiddenForFullscreen, let companion, companion.isVisible else { return }
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
        companion.move(to: DeloresCompanionWander.project(point, into: loop(on: screen)))
    }

    /// A drop stays where it was let go and stands there a beat, which is also what makes the drop
    /// read as having landed.
    private func dropCompanion(at point: CGPoint) {
        guard let companion, let screen = DeloresWindowGeometry.screenContaining(point) else { return }
        let landed = DeloresCompanionWander.project(point, into: loop(on: screen))
        companion.move(to: landed)
        settle(at: landed, on: screen)
    }

    private func relocateCompanion() {
        evaluateFullscreenPresence()
        guard let companion, companion.isVisible else { return }
        let center = wander?.center ?? companion.center
        guard let screen = DeloresWindowGeometry.screenContaining(center) else { return }
        // A body on the perimeter is on the boundary of its bounds, which `contains` excludes.
        guard !companionBounds(on: screen).insetBy(dx: -1, dy: -1).contains(center) else { return }
        let point = spawnPoint(on: screen)
        companion.move(to: point)
        settle(at: point, on: screen)
    }

    /// The loop the body rides: the display's whole frame, not its visible area.
    ///
    /// `visibleFrame` is the screen minus the menu bar and the Dock, which is why the body used to
    /// walk under one and above the other. It walks on the menu bar now and along the bottom of the
    /// screen, drawn over both — which is why its panel is at `.statusBar`, since a window below that
    /// level is simply covered by the menu bar. What it must still keep off is the path's business,
    /// not the frame's.
    private func companionBounds(on screen: NSScreen) -> CGRect {
        screen.frame.insetBy(dx: bodyRadius, dy: bodyRadius)
    }

    private func spawnPoint(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.maxX - bodyRadius, y: screen.frame.midY)
    }

    /// What the body may walk on `screen`.
    ///
    /// The whole frame, less the two things it must not walk through: the Dock, which it goes around,
    /// and the ends of the menu bar, which is where the icons live. Both are read off the display
    /// rather than asked of anyone — see `deloresMenuBarRuns` for why that is the choice.
    private func loop(on screen: NSScreen) -> DeloresCompanionLoop {
        DeloresCompanionLoop.around(
            screen.frame,
            bodyRadius: bodyRadius,
            walkingAround: screen.deloresDockZone,
            topRuns: screen.deloresMenuBarRuns)
    }
}

extension NSScreen {
    /// Where the Dock stands on this display.
    ///
    /// Its *height* is what the system tells us: the strip the visible frame gives up along the bottom.
    /// Its *width* has to be worked out, because no public API answers that and the two that could —
    /// the window list, Accessibility — sit behind permissions this feature does not otherwise ask
    /// for. So the Dock's own preferences are read instead, which is close enough to walk around.
    ///
    /// A hidden Dock gives up no height, so it gets no detour at all: the body crosses the bottom of
    /// the screen where the Dock will later appear, and that is the honest answer rather than a guess.
    var deloresDockZone: CGRect? {
        let height = visibleFrame.minY - frame.minY
        guard height > 0 else { return nil }
        let width = min(frame.width, dockStripWidth)
        return CGRect(
            x: frame.midX - width / 2, y: frame.minY,
            width: width, height: height)
    }

    /// How wide the Dock's strip of tiles is, read from the Dock's own settings.
    ///
    /// Falls back to the whole bottom edge, which is wrong in the harmless direction: a body that goes
    /// around more of the screen than it had to still never walks through the Dock.
    private var dockStripWidth: CGFloat {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return frame.width }
        let tile = CGFloat(dock.integer(forKey: "tilesize"))
        let apps = dock.array(forKey: "persistent-apps")?.count ?? 0
        let others = dock.array(forKey: "persistent-others")?.count ?? 0
        guard tile > 0, apps + others > 0 else { return frame.width }
        // Finder and the Trash are on every Dock and appear in neither list; the slack covers the gaps
        // between tiles and the margin at each end.
        let tiles = CGFloat(apps + others + 2)
        return tile * tiles * 1.2
    }

    /// The stretches of the menu bar the body is allowed on: beside the notch where there is one, and
    /// across the middle of the bar where there is not. Never the ends, which is where the icons are.
    ///
    /// A rule rather than a measurement, on purpose. Reading where the icons actually are needs
    /// either screen recording or Accessibility, and asking for a permission so that a pet can avoid
    /// a battery icon is out of proportion to what it buys.
    var deloresMenuBarRuns: [ClosedRange<CGFloat>] {
        let reach: CGFloat = 240
        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            return [
                (left.maxX - reach)...left.maxX,
                right.minX...(right.minX + reach),
            ]
        }
        return [(frame.midX - reach)...(frame.midX + reach)]
    }
}
