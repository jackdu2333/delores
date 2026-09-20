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
    private var spaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    private var isHiddenForFullscreen = false
    private var strollTimer: Timer?
    private var wakeTimer: Timer?
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
        guard isRunning, !isHiddenForFullscreen, let companion, companion.isVisible else { return nil }
        // The display the shell is being grown on, found from the visible frame it was asked about.
        guard let screen = DeloresWindowGeometry.screenContaining(
            CGPoint(x: visibleFrame.midX, y: visibleFrame.midY))
        else { return nil }
        let loop = loop(on: screen)
        guard !loop.isEmpty else { return nil }
        var center = companion.center
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
        let landed = DeloresCompanionWander.project(companion.center, into: loop(on: screen))
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
        // It is standing still for as long as the shell is up, so it is idle rather than mid-step.
        companion?.rest()
    }

    /// The shell is gone, so the body may walk again — once nothing else is holding it.
    func releaseShell() {
        guard shellHolds > 0 else { return }
        shellHolds -= 1
        guard !isHoldingShell else { return }
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
        wander = DeloresCompanionWander.settled(at: center, in: loop(on: screen), at: now, using: &rng)
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
        let fullscreen = isFrontmostAppFullscreen()
        if fullscreen && !isHiddenForFullscreen {
            isHiddenForFullscreen = true
            stopWanderTimers()
            companionMenu.hide()
            companion?.hide()
        } else if !fullscreen && isHiddenForFullscreen {
            isHiddenForFullscreen = false
            guard let companion else { return }
            let screen = DeloresWindowGeometry.screenContaining(companion.center)
                ?? DeloresWindowGeometry.activeScreen()
            guard let screen else { return }
            let bounds = companionBounds(on: screen)
            var center = companion.center
            if !bounds.insetBy(dx: -1, dy: -1).contains(center) {
                center = spawnPoint(on: screen)
            }
            companion.present(at: center)
            settle(at: center, on: screen)
        }
    }

    private func isFrontmostAppFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        let appElement = AXWindowAccess.application(for: app.processIdentifier)
        if let target = AXWindowAccess.targetWindow(in: appElement), AXWindowAccess.isFullScreen(target) {
            return true
        }
        let windows = AXWindowAccess.windows(in: appElement)
        return windows.contains(where: { AXWindowAccess.isFullScreen($0) })
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
        guard let companion, companion.isVisible,
            let screen = DeloresWindowGeometry.screenContaining(companion.center)
        else { return }
        let anchor = DeloresCompanionMenuController.Anchor(
            petCenter: companion.center,
            petFrame: companion.frame,
            edge: DeloresCompanionWander.edge(for: companion.center, in: companionBounds(on: screen)),
            bodyRadius: bodyRadius,
            visibleFrame: screen.visibleFrame)
        let landed = companionMenu.show(
            companionMenuItems(), anchoredTo: anchor, metrics: settings.interfaceSize.metrics)
        // Held while it is up: the menu hangs off the body, and a body that walked out from under it
        // would leave it hanging over nothing.
        holdForShell()
        guard landed != companion.center else { return }
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
                action: { [weak self] in self?.settings.deloresCompanionEnabled = false }),
        ]
    }

    /// Resting runs no frames at all: one wake is scheduled for the moment the rest ends. Walking is
    /// the only phase that costs a timer, which is the whole of the Companion's idle budget.
    private func syncWanderTimers() {
        // A body with nowhere to go is idle: being dragged, being held, or simply stopped.
        guard isRunning, !isHoldingShell, let wander else {
            stopWanderTimers(); companion?.rest(); return
        }
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
            at: point, in: loop(on: screen), at: now, using: &rng)
        syncWanderTimers()
    }

    private func advanceWander() {
        guard isRunning, !isHiddenForFullscreen, !isHoldingShell, let companion, companion.isVisible, let state = wander
        else { return }
        guard let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        let tick = now
        let elapsed = tick - lastWanderTick
        lastWanderTick = tick
        // Read from the wander rather than from the window: the window origin is snapped to whole
        // points for the artwork's sake, and that rounding must not colour which way the body turns.
        let from = state.center
        // Weight and sprite share this frame: a plant that still travels is what reads as a slide.
        if case .strolling = state.phase {
            walkFrame += 1
        }
        let frame = walkFrame % DeloresCompanionAnimation.walkFrameCount
        let next = DeloresCompanionWander.advance(
            state, elapsed: elapsed, now: tick, in: loop(on: screen), stepFrame: frame, using: &rng)
        wander = next
        companion.move(to: next.center)
        syncWanderTimers()
        guard case .strolling = next.phase else { return }
        // Ruling 3: the facing reads off the step's horizontal component, and a step with none keeps
        // what it had — a body on a vertical edge must not flip sides every frame.
        facing = DeloresCompanionAnimation.facing(from: from, to: next.center, fallback: facing)
        companion.step(frame: frame, facing: facing)
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
        guard let screen = DeloresWindowGeometry.screenContaining(companion.center) else { return }
        // A body on the perimeter is on the boundary of its bounds, which `contains` excludes.
        guard !companionBounds(on: screen).insetBy(dx: -1, dy: -1).contains(companion.center) else { return }
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
