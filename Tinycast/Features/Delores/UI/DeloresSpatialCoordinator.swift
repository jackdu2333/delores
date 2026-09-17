import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices
import SwiftUI

/// Delores-owned adapter for the optional Companion and Spatial surfaces.
/// The vendored Huaci application entry point is intentionally not used; its geometry and panel
/// behaviour are the reference this implementation is aligned with.
@MainActor
final class DeloresSpatialCoordinator {
    private let settings: AppSettings
    /// Shared with the Context Surface, so one mouse gesture belongs to one surface.
    private let interactionGate: DeloresSurfaceInteractionGate

    private var companionMonitor: Any?
    private var companionLocalMonitor: Any?
    private var companionDwellTimer: Timer?
    private var companionLeaveTimer: Timer?
    private var snapMonitor: Any?
    private var dividerMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var patrolTimer: Timer?
    private var companion: DeloresCompanionPanel?
    private var snapIsland: DeloresSnapIslandPanel?
    private var divider: DeloresDividerPanel?
    private var currentSelection = ""

    var onOpenContext: (() -> Void)?

    // Companion patrol
    private var lastPatrolTick = Date()
    private var patrolEdge: DeloresCompanionEdge = .right
    private var patrolDirection: CGFloat = 1

    // Window snapping
    private var snapMonitorStart = CGPoint.zero
    private var snapCandidate: SnapCandidate?
    private var snapIsActive = false
    private var snapHasClaimedGate = false
    /// The card the pointer is over, so the ghost only redraws when the answer changes.
    private var snapHoveredSlot: DeloresSnapSlot?

    // Split divider
    private var splitPair: SplitPair?
    private var dividerStart: DividerDrag?
    private var lastDividerScan = Date.distantPast
    /// Where the pointer was last answered, so a pointer at rest costs nothing at all. See
    /// `refreshDivider`.
    private var lastDividerMouseLocation = CGPoint.zero
    /// Halves placed by snapping, kept just long enough to be joined. See `registerSnappedWindow`.
    private var recentLeftSnap: DeloresSnapRecord?
    private var recentRightSnap: DeloresSnapRecord?

    private static let companionDwellDuration: TimeInterval = 0.25
    private static let companionLeaveDuration: TimeInterval = 0.9
    /// The Companion's visible radius. Its hit area is larger; the drawn circle is not.
    private static let companionVisibleRadius: CGFloat = 14
    private static let companionPatrolSpeed: CGFloat = 30
    /// A press that has moved this far is a drag, not a click.
    private static let snapDragThreshold: CGFloat = 8
    /// How far the window itself has to have moved before this is a window drag at all. A text
    /// selection moves the pointer the same distance without moving any window.
    private static let snapWindowThreshold: CGFloat = 20
    private static let snapIslandRevealInset: CGFloat = 110
    /// Only the center area of the top screen triggers the snap island, avoiding left menus and right status bar icons.
    private static let snapTopCenterTriggerWidth: CGFloat = 660
    /// The handle is exactly as wide as the hover tolerance on both sides. Anything narrower would
    /// let the pointer leave the panel while still inside the tolerance, and the overlay would flicker
    /// on and off at its edge.
    private static let dividerHoverTolerance: CGFloat = DeloresDividerPanel.width / 2
    private static let dividerPairGap: CGFloat = 12
    /// Below this, the pointer has not moved. Sub-pixel jitter from a resting hand would otherwise
    /// keep the seam scan alive while nothing is happening.
    private static let dividerMouseEpsilon: CGFloat = 0.5
    /// The seam scan walks every on-screen window, so it runs on a timer rather than per event.
    private static let dividerScanInterval: TimeInterval = 0.08

    private struct SnapCandidate {
        let window: AXUIElement
        let app: NSRunningApplication
        /// AX coordinates, taken at the press, so a drag can be told from a selection.
        let initialFrame: CGRect
    }

    private struct SplitPair {
        let left: AXUIElement
        let right: AXUIElement
        var leftRect: CGRect
        var rightRect: CGRect
        let screen: NSScreen
        var dividerX: CGFloat { (leftRect.maxX + rightRect.minX) / 2 }
        var y: CGFloat { max(leftRect.minY, rightRect.minY) }
        var height: CGFloat { max(0, min(leftRect.maxY, rightRect.maxY) - y) }
    }

    private struct DividerDrag {
        let pair: SplitPair
        let startX: CGFloat
    }

    /// A window snapped moments ago, and where it was put.
    private struct DeloresSnapRecord {
        let window: AXUIElement
        let rect: CGRect
        let when: TimeInterval
    }

    init(
        settings: AppSettings, interactionGate: DeloresSurfaceInteractionGate,
        onOpenContext: (() -> Void)? = nil
    ) {
        self.settings = settings
        self.interactionGate = interactionGate
        self.onOpenContext = onOpenContext
    }

    func applyEnabled() {
        if settings.deloresCompanionEnabled {
            stopSnapping()
            stopDivider()
            startCompanion()
        } else {
            stopCompanion()
            settings.deloresWindowSnappingEnabled ? startSnapping() : stopSnapping()
            settings.deloresSplitDividerEnabled ? startDivider() : stopDivider()
        }
    }

    func prepareForTermination() {
        stopCompanion()
        stopSnapping()
        stopDivider()
        interactionGate.reset()
    }

    func recordSelection(_ text: String) {
        currentSelection = text
        companion?.play(.glance)
    }

    // MARK: Companion

    private func startCompanion() {
        guard companionMonitor == nil, companionLocalMonitor == nil else { return }
        guard let screen = activeScreen() else { return }
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
        companion?.setCaptured(false)
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
        guard dt > 0, let screen = screenContaining(companion.center) else { return }
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
                    companion.setCaptured(true)
                }
            }
            companionDwellTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            companionDwellTimer?.invalidate(); companionDwellTimer = nil
            guard companion.isCaptured, companionLeaveTimer == nil else { return }
            let timer = Timer(timeInterval: Self.companionLeaveDuration, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let companion = self.companion else { return }
                    companion.setCaptured(false)
                    self.companionLeaveTimer = nil
                }
            }
            companionLeaveTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func moveCompanion(to point: CGPoint) {
        guard let companion, let screen = screenContaining(point) else { return }
        companion.move(to: snapPoint(point, edge: nearestEdge(point, screen.visibleFrame), in: companionBounds(on: screen)))
    }

    private func relocateCompanion() {
        guard let companion, companion.isVisible else { return }
        guard let screen = screenContaining(companion.center) else { return }
        guard !companionBounds(on: screen).contains(companion.center) else { return }
        companion.move(to: spawnPoint(on: screen))
    }

    // MARK: Window snap

    private func startSnapping() {
        guard snapMonitor == nil else { return }
        let watched: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        snapMonitor = NSEvent.addGlobalMonitorForEvents(matching: watched) { [weak self] event in
            let type = event.type
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handleSnap(type, at: point) }
        }
    }

    private func stopSnapping() {
        if let snapMonitor { NSEvent.removeMonitor(snapMonitor); self.snapMonitor = nil }
        releaseSnap()
    }

    /// Everything a snap run leaves behind, cleared in one place so a stop mid-drag cannot leave the
    /// island up or the interaction gate clamped shut.
    private func releaseSnap() {
        snapIsland?.hide(); snapIsland = nil
        snapHoveredSlot = nil
        snapCandidate = nil
        snapIsActive = false
        snapMonitorStart = .zero
        if snapHasClaimedGate {
            snapHasClaimedGate = false
            interactionGate.release(.snapping)
        }
        // A window stopped moving, which is the discrete signal that every cached seam may now be
        // wrong. Not guessed from a mouse-up: the press that moved it belongs to another app.
        windowGeometryDidChange(at: NSEvent.mouseLocation)
    }

    /// Every cached seam is stale now, so discovery runs again on the next opportunity rather than
    /// on its own clock.
    private func windowGeometryDidChange(at point: CGPoint) {
        lastDividerScan = .distantPast
        lastDividerMouseLocation = point
        guard settings.deloresSplitDividerEnabled, dividerStart == nil else { return }
        splitPair = nil
        refreshDivider(at: point)
    }

    /// Remembers which side of the seam a window was just snapped to.
    ///
    /// Ported from the reference, and it is the answer to a seam nobody can summon. Discovery walks
    /// the window list and asks whether two rectangles happen to touch, which is both expensive and
    /// approximate; but the instant one half has been placed we already know its identity and side,
    /// so if the other half arrived recently the pair can simply be named. No window list, and no
    /// dependence on the pointer crossing the seam while a scan happens to land.
    private func registerSnappedWindow(
        _ window: AXUIElement, slot: DeloresSnapSlot, rect: CGRect, screen: NSScreen
    ) {
        guard settings.deloresSplitDividerEnabled else { return }
        let now = Date().timeIntervalSince1970
        let placed = DeloresSnapRecord(window: window, rect: rect, when: now)
        let other = slot.isLeftOfSeam ? recentRightSnap : recentLeftSnap
        if slot.isLeftOfSeam { recentLeftSnap = placed } else { recentRightSnap = placed }

        // Within five minutes: long enough to take in a neighbour put beside it by hand afterwards,
        // short enough that a half-pair left before lunch is not still waiting to be completed.
        guard let other, !CFEqual(other.window, window), now - other.when <= 300 else { return }
        let left = slot.isLeftOfSeam ? placed : other
        let right = slot.isLeftOfSeam ? other : placed
        guard let pair = pairJoining(left: left, right: right, screen: screen) else { return }
        splitPair = pair
        divider?.show(x: pair.dividerX, y: pair.y, height: pair.height)
    }

    /// Whether two recently placed windows still sit seam to seam, decided by reading their frames
    /// back rather than by trusting the rectangles we last asked them for.
    private func pairJoining(
        left: DeloresSnapRecord, right: DeloresSnapRecord, screen: NSScreen
    ) -> SplitPair? {
        let geometry = AXGeometry(screens: NSScreen.screens)
        guard let leftFrame = AXWindowAccess.frame(of: left.window),
              let rightFrame = AXWindowAccess.frame(of: right.window),
              AXWindowAccess.isSettable(kAXPositionAttribute, on: left.window),
              AXWindowAccess.isSettable(kAXPositionAttribute, on: right.window)
        else { return nil }
        let l = geometry.flip(leftFrame)
        let r = geometry.flip(rightFrame)
        guard abs(r.minX - l.maxX) <= Self.dividerPairGap else { return nil }
        let pair = SplitPair(
            left: left.window, right: right.window, leftRect: l, rightRect: r, screen: screen)
        guard pair.height >= 120 else { return nil }
        return pair
    }

    private func handleSnap(_ type: NSEvent.EventType, at point: CGPoint) {
        guard settings.deloresWindowSnappingEnabled, !settings.deloresCompanionEnabled else { return }
        switch type {
        case .leftMouseDown:
            snapMonitorStart = point
            snapCandidate = snapCandidate(at: point)
            snapIsActive = false
        case .leftMouseDragged:
            guard hypot(point.x - snapMonitorStart.x, point.y - snapMonitorStart.y) >= Self.snapDragThreshold else { return }
            // The gate is claimed only once a window has actually moved. Claiming it on pointer
            // distance alone would swallow the ordinary text selection this gesture might be.
            if !snapHasClaimedGate {
                guard let candidate = snapCandidate, hasMoved(candidate) else { return }
                guard interactionGate.claim(.snapping) else { return }
                snapHasClaimedGate = true
            }
            guard let screen = screenContaining(point) else { return }
            let isNearTop = point.y >= screen.visibleFrame.maxY - Self.snapIslandRevealInset
            let halfCenterWidth = Self.snapTopCenterTriggerWidth / 2.0
            let isInCenterTop = abs(point.x - screen.frame.midX) <= halfCenterWidth

            if isNearTop && (isInCenterTop || snapIsActive) {
                snapIsActive = true
                snapIsland = snapIsland ?? DeloresSnapIslandPanel()
                snapIsland?.show(on: screen)
                let slot = snapIsland?.slot(at: point)
                snapIsland?.setHoveredSlot(slot)
            } else if snapIsActive {
                snapIsActive = false
                snapIsland?.hide()
            }
        case .leftMouseUp:
            defer { releaseSnap() }
            guard snapIsActive, let candidate = snapCandidate, let snapIsland,
                  let screen = screenContaining(point),
                  let slot = snapIsland.slot(at: point) else { return }
            let target = slot.rect(in: screen.visibleFrame)
            // Only a window that really went there is worth remembering: see `registerSnappedWindow`.
            if setWindowFrame(candidate.window, rect: target) {
                registerSnappedWindow(candidate.window, slot: slot, rect: target, screen: screen)
            }
        default:
            break
        }
    }

    /// The window the drag would move, read at the press. Delores' own surfaces are not targets.
    private func snapCandidate(at point: CGPoint) -> SnapCandidate? {
        guard Permissions.isAccessibilityTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = focusedWindow(of: app),
              let frame = AXWindowAccess.frame(of: window)
        else { return nil }
        return SnapCandidate(window: window, app: app, initialFrame: frame)
    }

    /// Whether the candidate window itself has moved, which is what separates a window drag from a
    /// selection made by dragging across text.
    private func hasMoved(_ candidate: SnapCandidate) -> Bool {
        guard let current = AXWindowAccess.frame(of: candidate.window) else { return false }
        return abs(current.minX - candidate.initialFrame.minX) >= Self.snapWindowThreshold
            || abs(current.minY - candidate.initialFrame.minY) >= Self.snapWindowThreshold
    }

    // MARK: Split divider

    private func startDivider() {
        guard dividerMonitor == nil else { return }
        let panel = divider ?? DeloresDividerPanel()
        divider = panel
        // The overlay is live over the seam and transparent everywhere else, so a press on the
        // handle is taken here and never reaches the window underneath. Whether it appears at all is
        // still decided below, which is why the view's own enter and exit only answer "is the reader
        // on the grip" and never "should this band exist".
        panel.onMouseDown = { [weak self] point in self?.beginDivider(at: point) }
        panel.onMouseDragged = { [weak self] point in self?.dragDivider(to: point) }
        panel.onMouseUp = { [weak self] in self?.endDivider() }
        panel.onDoubleClick = { [weak self] in self?.resetToFiftyFifty() }
        panel.hide()
        dividerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.refreshDivider(at: point) }
        }
    }

    private func stopDivider() {
        if let dividerMonitor { NSEvent.removeMonitor(dividerMonitor); self.dividerMonitor = nil }
        divider?.hide(); divider = nil
        splitPair = nil; dividerStart = nil
        lastDividerScan = .distantPast
        // Nothing left to pair: the halves were only meaningful while it was running, and a feature
        // that is off should not be holding windows in memory to join them later.
        recentLeftSnap = nil
        recentRightSnap = nil
        interactionGate.release(.divider)
    }

    private func hideDivider() {
        splitPair = nil
        divider?.hideRatio()
        divider?.hide()
    }

    /// The halves back to equal, which is almost always where a pair started and rarely where a
    /// drag leaves it. Double-click rather than a button: the grip is the whole control, and there
    /// is nowhere on it to put a second one.
    private func resetToFiftyFifty() {
        guard Permissions.isAccessibilityTrusted() else { return }
        guard let pair = splitPair ?? findSplitPair(near: NSEvent.mouseLocation) else { return }
        let total = pair.leftRect.width + pair.rightRect.width
        let half = total / 2
        let left = CGRect(
            x: pair.leftRect.minX, y: pair.leftRect.minY, width: half, height: pair.leftRect.height)
        let right = CGRect(
            x: pair.leftRect.minX + half, y: pair.rightRect.minY,
            width: total - half, height: pair.rightRect.height)
        let leftApplied = setWindowFrame(pair.left, rect: left)
        let rightApplied = setWindowFrame(pair.right, rect: right)
        // Same rule a refused drag follows: nothing half-applied stays on the screen.
        guard leftApplied, rightApplied else {
            if leftApplied { setWindowFrame(pair.left, rect: pair.leftRect) }
            if rightApplied { setWindowFrame(pair.right, rect: pair.rightRect) }
            return
        }
        splitPair = refreshedPair(pair)
        if let reloaded = splitPair {
            divider?.show(x: reloaded.dividerX, y: reloaded.y, height: reloaded.height)
        }
    }

    private func refreshDivider(at point: CGPoint) {
        // A pointer at rest must cost nothing. This is above every other test on purpose: whether
        // or not anything else wants to answer, an unmoved pointer has no new information to give,
        // and the seam scan below walks every window on the screen.
        let moved = hypot(point.x - lastDividerMouseLocation.x, point.y - lastDividerMouseLocation.y)
        lastDividerMouseLocation = point
        guard moved > Self.dividerMouseEpsilon else { return }

        guard !settings.deloresCompanionEnabled, Permissions.isAccessibilityTrusted() else {
            hideDivider()
            return
        }
        // A drag owns the overlay until the button is released.
        guard dividerStart == nil else { return }

        if let pair = splitPair {
            if !isNearDivider(point, pair: pair) {
                hideDivider()
                return
            }
            if let refreshed = refreshedPair(pair) {
                splitPair = refreshed
                divider?.show(x: refreshed.dividerX, y: refreshed.y, height: refreshed.height)
                return
            }
            hideDivider()
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastDividerScan) >= Self.dividerScanInterval else { return }
        lastDividerScan = now
        guard let pair = findSplitPair(near: point) else {
            hideDivider()
            return
        }
        splitPair = pair
        divider?.show(x: pair.dividerX, y: pair.y, height: pair.height)
    }

    private func beginDivider(at point: CGPoint) {
        guard Permissions.isAccessibilityTrusted() else { return }
        guard let pair = splitPair ?? findSplitPair(near: point), isNearDivider(point, pair: pair),
              interactionGate.claim(.divider) else { return }
        splitPair = pair
        dividerStart = DividerDrag(pair: pair, startX: point.x)
        reportRatio(leftWidth: pair.leftRect.width, total: pair.leftRect.width + pair.rightRect.width)
    }

    /// The proportions about to be let go of. Reported from the press rather than the first movement
    /// so the numbers are already there to move away from; rounding to whole percent because "47%
    /// : 53%" is read at a glance where "46.8% : 53.2%" has to be looked at.
    private func reportRatio(leftWidth: CGFloat, total: CGFloat) {
        guard total > 0 else { return }
        let left = Int((leftWidth / total * 100).rounded())
        divider?.updateRatio(left: left, right: 100 - left)
    }

    private func isNearDivider(_ point: CGPoint, pair: SplitPair) -> Bool {
        abs(point.x - pair.dividerX) <= Self.dividerHoverTolerance
            && point.y >= pair.y && point.y <= pair.y + pair.height
    }

    /// Reads the two cached windows back, so a pair that drifted apart stops being a seam. Cheaper
    /// than re-walking the window list, which is why the cache is preferred while it holds.
    private func refreshedPair(_ pair: SplitPair) -> SplitPair? {
        let geometry = AXGeometry(screens: NSScreen.screens)
        guard let leftAX = AXWindowAccess.frame(of: pair.left),
              let rightAX = AXWindowAccess.frame(of: pair.right)
        else { return nil }
        let left = geometry.flip(leftAX)
        let right = geometry.flip(rightAX)
        let leftIsLeft = left.minX <= right.minX
        let l = leftIsLeft ? left : right
        let r = leftIsLeft ? right : left
        guard abs(r.minX - l.maxX) <= Self.dividerPairGap else { return nil }
        var refreshed = pair
        refreshed.leftRect = l
        refreshed.rightRect = r
        guard refreshed.height >= 120 else { return nil }
        return refreshed
    }

    private func dragDivider(to point: CGPoint) {
        guard let start = dividerStart else { return }
        let total = start.pair.leftRect.width + start.pair.rightRect.width
        let minWidth: CGFloat = 250
        guard total >= minWidth * 2 else { return }
        let leftWidth = min(max(start.pair.leftRect.width + point.x - start.startX, minWidth), total - minWidth)
        let delta = leftWidth - start.pair.leftRect.width
        let left = CGRect(
            x: start.pair.leftRect.minX, y: start.pair.leftRect.minY,
            width: leftWidth, height: start.pair.leftRect.height)
        let right = CGRect(
            x: start.pair.rightRect.minX + delta, y: start.pair.rightRect.minY,
            width: total - leftWidth, height: start.pair.rightRect.height)
        let leftApplied = setWindowFrame(start.pair.left, rect: left)
        let rightApplied = setWindowFrame(start.pair.right, rect: right)
        guard leftApplied, rightApplied else {
            // One half moving and the other refusing is the one outcome that must never be left on
            // screen: put whichever moved back where the drag started.
            if leftApplied { setWindowFrame(start.pair.left, rect: start.pair.leftRect) }
            if rightApplied { setWindowFrame(start.pair.right, rect: start.pair.rightRect) }
            return
        }
        divider?.show(x: (left.maxX + right.minX) / 2, y: start.pair.y, height: start.pair.height)
        reportRatio(leftWidth: leftWidth, total: total)
    }

    private func endDivider() {
        dividerStart = nil
        lastDividerScan = .distantPast
        interactionGate.release(.divider)
        // The badge is about a gesture, so it goes when the gesture does — leaving it up would make
        // it read as a property of the windows.
        divider?.hideRatio()
        refreshDivider(at: NSEvent.mouseLocation)
    }

    // MARK: AX and geometry

    private func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXWindowAccess.application(for: app.processIdentifier)
        guard let window = AXWindowAccess.targetWindow(in: appElement),
              AXWindowAccess.isEligible(window) else { return nil }
        // Per element, never inherited from the application element.
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        return window
    }

    @discardableResult
    private func setWindowFrame(_ window: AXUIElement, rect: CGRect) -> Bool {
        let geometry = AXGeometry(screens: NSScreen.screens)
        guard AXWindowAccess.isEligible(window), !AXWindowAccess.isFullScreen(window),
              let current = AXWindowAccess.frame(of: window),
              AXWindowAccess.isSettable(kAXPositionAttribute, on: window) else { return false }
        let canResize = AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
        let axRect = geometry.flip(rect)
        guard AXWindowAccess.write(
            axRect, anchor: WindowPlacementEngine.Anchor.topLeading, to: window,
            current: current, canResize: canResize, canvas: nil) != nil,
              let validated = AXWindowAccess.frame(of: window) else { return false }
        let tolerance = AXWindowAccess.clampTolerance
        return abs(validated.minX - axRect.minX) <= tolerance
            && abs(validated.minY - axRect.minY) <= tolerance
            && (!canResize || (abs(validated.width - axRect.width) <= tolerance
                && abs(validated.height - axRect.height) <= tolerance))
    }

    /// The two on-screen windows that meet at the seam under `point`, if any. Only the seam is
    /// interesting, so the scan keeps just the windows spanning the pointer's height.
    private func findSplitPair(near point: CGPoint) -> SplitPair? {
        guard let screen = screenContaining(point) else { return nil }
        let geometry = AXGeometry(screens: NSScreen.screens)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let listed = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        let infos = listed ?? []
        var candidates: [(pid: pid_t, rect: CGRect)] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat, let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat,
                  width >= 250, height >= 300 else { continue }
            let rect = geometry.flip(CGRect(x: x, y: y, width: width, height: height))
            guard screen.visibleFrame.intersects(rect),
                  point.y >= rect.minY, point.y <= rect.maxY else { continue }
            candidates.append((pid, rect))
        }

        var best: (pair: SplitPair, distance: CGFloat)?
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                let a = candidates[i], b = candidates[j]
                let left = a.rect.minX < b.rect.minX ? a : b
                let right = a.rect.minX < b.rect.minX ? b : a
                let gap = abs(right.rect.minX - left.rect.maxX)
                let seamY = max(left.rect.minY, right.rect.minY)
                let seamHeight = max(0, min(left.rect.maxY, right.rect.maxY) - seamY)
                let dividerX = (left.rect.maxX + right.rect.minX) / 2
                guard gap <= Self.dividerPairGap,
                      seamHeight / min(left.rect.height, right.rect.height) >= 0.7 else { continue }
                let distance = abs(point.x - dividerX)
                guard distance <= Self.dividerHoverTolerance,
                      point.y >= seamY, point.y <= seamY + seamHeight else { continue }
                // Nearest seam wins: two overlapping pairs must not make the handle jump.
                if let best, distance >= best.distance { continue }
                guard let leftWindow = window(pid: left.pid, near: left.rect),
                      let rightWindow = window(pid: right.pid, near: right.rect),
                      AXWindowAccess.isSettable(kAXPositionAttribute, on: leftWindow),
                      AXWindowAccess.isSettable(kAXPositionAttribute, on: rightWindow)
                else { continue }
                best = (
                    SplitPair(
                        left: leftWindow, right: rightWindow, leftRect: left.rect,
                        rightRect: right.rect, screen: screen),
                    distance)
            }
        }
        return best?.pair
    }

    private func window(pid: pid_t, near rect: CGRect) -> AXUIElement? {
        let app = AXWindowAccess.application(for: pid)
        let geometry = AXGeometry(screens: NSScreen.screens)
        return AXWindowAccess.windows(in: app).first { window in
            guard AXWindowAccess.isEligible(window), let axFrame = AXWindowAccess.frame(of: window) else {
                return false
            }
            AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
            let candidate = geometry.flip(axFrame)
            return abs(candidate.midX - rect.midX) < 20 && abs(candidate.midY - rect.midY) < 20
        }
    }

    /// A headless or mid-reconfiguration Mac can report no screens at all; there is no surface to
    /// place then, so every caller treats a missing screen as "do nothing".
    private func activeScreen() -> NSScreen? { NSScreen.main ?? NSScreen.screens.first }
    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? activeScreen()
    }
    private func companionBounds(on screen: NSScreen) -> CGRect {
        screen.visibleFrame.insetBy(dx: Self.companionVisibleRadius, dy: Self.companionVisibleRadius)
    }
    private func spawnPoint(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.visibleFrame.maxX - Self.companionVisibleRadius, y: screen.visibleFrame.midY)
    }
}

private enum DeloresCompanionExpression { case idle, glance, chat }

private final class DeloresCompanionPanel: NSPanel {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    private var down = CGPoint.zero
    private var dragged = false
    private var longPressTimer: Timer?
    private(set) var isCaptured = false
    private var hosting: NSHostingView<DeloresCompanionView>!
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 44, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .floating; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true; isReleasedWhenClosed = false; canHide = false
        becomesKeyOnlyIfNeeded = true
        hosting = NSHostingView(rootView: DeloresCompanionView())
        contentView = hosting
    }

    /// Never takes the keyboard away from the app being used; the panel only needs the pointer.
    override var canBecomeKey: Bool { true }

    func present(at center: CGPoint) { move(to: center); orderFrontRegardless() }
    func move(to center: CGPoint) { setFrameOrigin(CGPoint(x: center.x - 22, y: center.y - 22)) }
    func hide() { setCaptured(false); orderOut(nil); longPressTimer?.invalidate() }
    func setCaptured(_ captured: Bool) {
        isCaptured = captured
        ignoresMouseEvents = !captured
    }
    func play(_ expression: DeloresCompanionExpression) { hosting.rootView = DeloresCompanionView(expression: expression) }
    func showBubble() { play(.chat) }

    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation; dragged = false
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onLongPress?() }
        }
        if let longPressTimer { RunLoop.main.add(longPressTimer, forMode: .common) }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard hypot(point.x - down.x, point.y - down.y) >= 4 else { return }
        dragged = true; longPressTimer?.invalidate(); move(to: point); onDrag?(point)
    }
    override func mouseUp(with event: NSEvent) {
        longPressTimer?.invalidate(); longPressTimer = nil
        guard !dragged else { return }
        event.clickCount >= 2 ? onDoubleClick?() : onSingleClick?()
    }
}

private struct DeloresCompanionView: View {
    var expression = DeloresCompanionExpression.idle
    private var symbol: String {
        switch expression { case .idle: return "sparkles"; case .glance: return "eye"; case .chat: return "bubble.left" }
    }
    var body: some View {
        ZStack {
            DeloresVisualEffectView(material: .popover, blending: .behindWindow).clipShape(Circle())
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 28, height: 28)
        .frame(width: 44, height: 44)
    }
}

private enum DeloresSnapSlot {
    case left, right, mainWorkspace, sideWorkspace
    case leftThird, centerThird, rightThird
    case topLeft, topRight, bottomLeft, bottomRight

    /// Which side of the seam it shares with its neighbour, for pairing. The quarters and the centre
    /// third answer `false` because neither has one neighbour to pair with: a quarter is stacked, so
    /// its seam is horizontal and not something this divider resizes, and the centre third has
    /// something either side of it.
    var isLeftOfSeam: Bool {
        switch self {
        case .left, .mainWorkspace, .leftThird: return true
        case .right, .sideWorkspace, .rightThird: return false
        case .centerThird, .topLeft, .topRight, .bottomLeft, .bottomRight: return false
        }
    }

    func rect(in frame: CGRect) -> CGRect {
        let margin: CGFloat = 6
        let gap: CGFloat = 8
        let usableWidth = frame.width - margin * 2
        let usableHeight = frame.height - margin * 2
        let halfWidth = (usableWidth - gap) / 2
        let halfHeight = (usableHeight - gap) / 2
        switch self {
        case .left:
            return CGRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: halfWidth, height: usableHeight)
        case .right:
            return CGRect(x: frame.midX + gap / 2, y: frame.minY + margin,
                          width: halfWidth, height: usableHeight)
        case .mainWorkspace:
            let mainWidth = (usableWidth - gap) * 2 / 3
            return CGRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: mainWidth, height: usableHeight)
        case .sideWorkspace:
            let mainWidth = (usableWidth - gap) * 2 / 3
            let sideWidth = usableWidth - gap - mainWidth
            return CGRect(x: frame.maxX - margin - sideWidth, y: frame.minY + margin,
                          width: sideWidth, height: usableHeight)
        case .leftThird, .centerThird, .rightThird:
            let thirdWidth = (usableWidth - gap * 2) / 3
            let index: CGFloat = self == .leftThird ? 0 : (self == .centerThird ? 1 : 2)
            return CGRect(x: frame.minX + margin + index * (thirdWidth + gap),
                          y: frame.minY + margin, width: thirdWidth, height: usableHeight)
        case .topLeft:
            return CGRect(x: frame.minX + margin, y: frame.midY + gap / 2,
                          width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: frame.midX + gap / 2, y: frame.midY + gap / 2,
                          width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: frame.midX + gap / 2, y: frame.minY + margin,
                          width: halfWidth, height: halfHeight)
        }
    }
}

private final class DeloresSnapIslandPanel: NSPanel {
    private let islandSize = SnapIslandGeometry.size
    private var activeScreen: NSScreen?
    private let hosting: NSHostingView<DeloresSnapIslandView>
    private let state = DeloresSnapIslandState()
    /// How far above its resting place the island starts, from the reference's own numbers.
    private static let enterSlide: CGFloat = 14
    private static let enterDuration: TimeInterval = 0.24

    init() {
        let hosting = NSHostingView(rootView: DeloresSnapIslandView(state: state))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: islandSize)
        self.hosting = hosting
        super.init(
            contentRect: CGRect(origin: .zero, size: islandSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .popUpMenu; ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hosting
    }
    override var canBecomeKey: Bool { false }
    /// The island drops into place from just above where it will rest, on the reference's own
    /// numbers — 14pt over 240ms — and its contents come up on a spring inside that. Arriving is
    /// most of what makes it read as something that appeared *for this drag* rather than as a strip
    /// that had been sitting there.
    ///
    /// Already up on the same display is not re-flown. Dragging near the top fires repeatedly, and
    /// restarting the animation on every frame would leave the island permanently mid-arrival.
    func show(on screen: NSScreen) {
        if isVisible, activeScreen?.frame == screen.frame { return }
        activeScreen = screen
        let width = islandSize.width
        let height = islandSize.height
        let resting = CGRect(
            x: round(screen.frame.midX - width / 2),
            y: max(screen.visibleFrame.maxY - height - 6, screen.frame.maxY - height - 8),
            width: width, height: height)
        setFrame(resting.offsetBy(dx: 0, dy: Self.enterSlide), display: false)
        alphaValue = 0
        orderFrontRegardless()

        state.isAppearing = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            state.isAppearing = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.enterDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            animator().setFrame(resting, display: true)
            animator().alphaValue = 1
        }
    }
    func setHoveredSlot(_ slot: DeloresSnapSlot?) {
        guard state.hoveredSlot != slot else { return }
        state.hoveredSlot = slot
    }
    func hide() {
        ignoresMouseEvents = true
        state.hoveredSlot = nil
        orderOut(nil)
    }
    func slot(at point: CGPoint) -> DeloresSnapSlot? {
        guard activeScreen != nil, frame.contains(point) else { return nil }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        guard SnapIslandGeometry.bounds.contains(local) else { return nil }
        for card in SnapIslandGeometry.Card.allCases {
            let rect = SnapIslandGeometry.rect(for: card)
            guard rect.contains(local) else { continue }
            let ratio = (local.x - rect.minX) / rect.width
            switch card {
            case .halfSplit:
                return ratio <= 0.5 ? .left : .right
            case .mainSide:
                return ratio <= SnapIslandGeometry.mainSideSplitRatio ? .mainWorkspace : .sideWorkspace
            case .quarter:
                let isLeft = ratio <= 0.5
                let isTop = local.y >= SnapIslandGeometry.quarterCenterY
                if isTop { return isLeft ? .topLeft : .topRight }
                return isLeft ? .bottomLeft : .bottomRight
            case .thirds:
                if ratio <= 1.0 / 3.0 { return .leftThird }
                if ratio <= 2.0 / 3.0 { return .centerThird }
                return .rightThird
            }
        }
        return nil
    }
}

private struct SnapIslandGeometry {
    enum Card: CaseIterable {
        case halfSplit, mainSide, quarter, thirds

        var glyphSize: CGSize {
            switch self {
            case .halfSplit: return CGSize(width: 108, height: 64)
            case .mainSide:  return CGSize(width: 110, height: 64)
            case .quarter:   return CGSize(width: 106, height: 64)
            case .thirds:    return CGSize(width: 112, height: 64)
            }
        }
    }

    static let size = CGSize(width: 620, height: 88)
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let gap: CGFloat = 12
    static let cardWidth: CGFloat = 140
    static let cardHeight: CGFloat = 72
    static let bounds = CGRect(origin: .zero, size: size)
    static let quarterCenterY = verticalPadding + cardHeight / 2
    /// Matches the reference, where both were settled against rendered output: thick enough to see
    /// against its own pane, thin enough to read as an edge of it rather than a line on it.
    static let glyphDividerWidth: CGFloat = 1.4
    static let glyphCornerRadius: CGFloat = 4.5

    static func rect(for card: Card) -> CGRect {
        let index = CGFloat(Card.allCases.firstIndex(of: card) ?? 0)
        return CGRect(
            x: horizontalPadding + index * (cardWidth + gap), y: verticalPadding,
            width: cardWidth, height: cardHeight)
    }

    static var mainSideSplitRatio: CGFloat {
        let glyphW = Card.mainSide.glyphSize.width
        let inset = (cardWidth - glyphW) / 2
        let available = glyphW - glyphDividerWidth
        let mainWidth = available * (2.0 / 3.0)
        return (inset + mainWidth + glyphDividerWidth / 2) / cardWidth
    }
}

/// The panels arrive rather than appear, which needs something observable to animate against —
/// the frame and the alpha are driven from AppKit, but the contents come up on their own curve.
private final class DeloresSnapIslandState: ObservableObject {
    @Published var isAppearing = false
    @Published var hoveredSlot: DeloresSnapSlot? = nil
}

private struct DeloresSnapIslandView: View {
    @ObservedObject var state: DeloresSnapIslandState
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: SnapIslandGeometry.gap) {
            card(.halfSplit)
            card(.mainSide)
            card(.quarter)
            card(.thirds)
        }
        .padding(.horizontal, SnapIslandGeometry.horizontalPadding)
        .padding(.vertical, SnapIslandGeometry.verticalPadding)
        .frame(width: SnapIslandGeometry.size.width, height: SnapIslandGeometry.size.height)
        .background(
            DeloresVisualEffectView(material: .popover, blending: .behindWindow)
                .clipShape(Capsule()))
        .scaleEffect(state.isAppearing ? 1 : 0.96)
        .opacity(state.isAppearing ? 1 : 0)
    }

    /// A line that takes the light along its top edge and falls into shadow along its bottom.
    ///
    /// Ported from the reference's pane rim, whose comment is worth carrying: a stroke of one
    /// uniform colour around a card is exactly what makes that card read as *stroked* rather than as
    /// a pane of something. Every edge in these cards is this instead.
    private var paneRim: some ShapeStyle {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isDark ? 0.24 : 0.85), location: 0),
                .init(color: Color.black.opacity(isDark ? 0.05 : 0.06), location: 0.55),
                .init(color: Color.black.opacity(isDark ? 0.16 : 0.10), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// The middle stop on its own, for edges too short for the gradient to read along.
    private var paneMidTone: Color {
        Color.black.opacity(isDark ? 0.05 : 0.06)
    }

    @ViewBuilder
    private func highlightCell(_ slot: DeloresSnapSlot) -> some View {
        if state.hoveredSlot == slot {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor.opacity(isDark ? 0.35 : 0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isDark ? 0.8 : 0.6), lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func card(_ card: SnapIslandGeometry.Card) -> some View {
        let geometry = SnapIslandGeometry.self
        let size = card.glyphSize
        ZStack {
            // Interactive slot highlights
            switch card {
            case .halfSplit:
                HStack(spacing: geometry.glyphDividerWidth) {
                    highlightCell(.left)
                    highlightCell(.right)
                }
                .padding(geometry.glyphDividerWidth)
            case .mainSide:
                let mainW = (size.width - geometry.glyphDividerWidth) * (2.0 / 3.0)
                HStack(spacing: geometry.glyphDividerWidth) {
                    highlightCell(.mainWorkspace).frame(width: mainW)
                    highlightCell(.sideWorkspace).frame(maxWidth: .infinity)
                }
                .padding(geometry.glyphDividerWidth)
            case .quarter:
                VStack(spacing: geometry.glyphDividerWidth) {
                    HStack(spacing: geometry.glyphDividerWidth) {
                        highlightCell(.topLeft)
                        highlightCell(.topRight)
                    }
                    HStack(spacing: geometry.glyphDividerWidth) {
                        highlightCell(.bottomLeft)
                        highlightCell(.bottomRight)
                    }
                }
                .padding(geometry.glyphDividerWidth)
            case .thirds:
                HStack(spacing: geometry.glyphDividerWidth) {
                    highlightCell(.leftThird)
                    highlightCell(.centerThird)
                    highlightCell(.rightThird)
                }
                .padding(geometry.glyphDividerWidth)
            }

            // Outer rim and inner dividers
            RoundedRectangle(cornerRadius: geometry.glyphCornerRadius, style: .continuous)
                .strokeBorder(paneRim, lineWidth: geometry.glyphDividerWidth)
            switch card {
            case .halfSplit:
                divider(.vertical)
            case .mainSide:
                HStack(spacing: 0) {
                    Color.clear.frame(width: (size.width - geometry.glyphDividerWidth) * (2.0 / 3.0))
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            case .quarter:
                VStack(spacing: 0) {
                    Color.clear.frame(maxHeight: .infinity)
                    divider(.horizontal)
                    Color.clear.frame(maxHeight: .infinity)
                }
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            case .thirds:
                let colW = (size.width - geometry.glyphDividerWidth * 2) / 3.0
                HStack(spacing: 0) {
                    Color.clear.frame(width: colW)
                    divider(.vertical)
                    Color.clear.frame(width: colW)
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(width: geometry.cardWidth, height: geometry.cardHeight)
    }

    @ViewBuilder
    private func divider(_ axis: Axis) -> some View {
        let thickness = SnapIslandGeometry.glyphDividerWidth
        switch axis {
        case .vertical:
            // Vertical, so light has somewhere to fall along it.
            Rectangle()
                .fill(paneRim)
                .frame(width: thickness)
        case .horizontal:
            // Seen edge-on: a single row of pixels has no room for a gradient to read, so the
            // middle stop is used flat. Grading it anyway would darken the whole line unevenly.
            Rectangle()
                .fill(paneMidTone)
                .frame(height: thickness)
        }
    }

    private enum Axis { case horizontal, vertical }
}

/// The overlay over the seam between two tiled windows.
///
/// Ported rather than redrawn. The width is the interesting part: 100pt of nothing is centred on the
/// seam, and none of it is opaque — the drawing only appears once the pointer is inside a few points
/// of the middle, and the panel takes the pointer only there too (`hitTest`, below). What the extra
/// width buys is room: the ratio badge is 72pt across and the grip carries a blur shadow, and at the
/// width this needed to be before, both were clipped at the edges. It costs the two windows
/// underneath nothing, because every point outside the hover zone is passed straight through them.
private final class DeloresDividerPanel: NSPanel {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private let seam = DeloresDividerView()

    /// Derived into `dividerHoverTolerance`, so the two cannot drift apart: a tolerance wider than
    /// the band would leave the pointer outside the panel while still wanting it shown, which is
    /// exactly how an overlay learns to flicker at its own edge.
    static let width: CGFloat = 100

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .floating; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false; canHide = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        seam.owner = self
        seam.autoresizingMask = [.width, .height]
        contentView = seam
    }

    override var canBecomeKey: Bool { true }

    func show(x: CGFloat, y: CGFloat, height: CGFloat) {
        let width = Self.width
        setFrame(
            CGRect(x: floor(x - width / 2), y: y, width: width, height: max(30, height)),
            display: true)
        orderFrontRegardless()
        // Reported the moment the band appears. Without it the grip stays invisible until the
        // pointer happens to move again, which reads as the whole seam being dead.
        seam.checkInitialHover()
    }

    func hide() {
        seam.resetState()
        orderOut(nil)
    }

    func updateRatio(left: Int, right: Int) { seam.showRatio(left: left, right: right) }
    func hideRatio() { seam.hideRatio() }
}

/// What the seam is made of.
///
/// Everything here sits at zero opacity until the pointer arrives, because most of the time nobody
/// is resizing anything and there should be nothing on the screen to say otherwise. The three parts
/// answer three questions in the order a reader asks them: *is there a seam here* (the guide track,
/// dissolving at both ends so it reads as belonging to what is behind it), *can I take hold of it*
/// (the grip capsule), and *what am I about to get* (the ratio badge, live while dragging).
private final class DeloresDividerView: NSView {
    weak var owner: DeloresDividerPanel?

    private static let trackWidth: CGFloat = 1.5
    private static let handleWidth: CGFloat = 24
    private static let handleHeight: CGFloat = 36
    private static let handleCornerRadius: CGFloat = 12
    private static let badgeWidth: CGFloat = 72
    private static let badgeHeight: CGFloat = 24

    private let guideTrackLayer = CAGradientLayer()
    private let gripHandleLayer = CALayer()
    private let leftBarLayer = CALayer()
    private let rightBarLayer = CALayer()
    private let ratioBadgeLayer = CALayer()
    private let ratioTextLayer = CATextLayer()

    private var isHovered = false
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        guideTrackLayer.cornerRadius = 0.75
        guideTrackLayer.startPoint = CGPoint(x: 0.5, y: 0)
        guideTrackLayer.endPoint = CGPoint(x: 0.5, y: 1)
        guideTrackLayer.locations = [0, 0.08, 0.5, 0.92, 1]
        guideTrackLayer.shadowColor = NSColor.black.cgColor
        guideTrackLayer.shadowOpacity = 0.15
        guideTrackLayer.shadowOffset = .zero
        guideTrackLayer.shadowRadius = 1.5
        guideTrackLayer.opacity = 0
        layer?.addSublayer(guideTrackLayer)

        gripHandleLayer.cornerRadius = Self.handleCornerRadius
        gripHandleLayer.borderWidth = 0.75
        gripHandleLayer.shadowColor = NSColor.black.cgColor
        gripHandleLayer.shadowOpacity = 0.20
        gripHandleLayer.shadowOffset = CGSize(width: 0, height: 2)
        gripHandleLayer.shadowRadius = 8
        gripHandleLayer.opacity = 0
        gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        layer?.addSublayer(gripHandleLayer)

        leftBarLayer.cornerRadius = 1
        gripHandleLayer.addSublayer(leftBarLayer)
        rightBarLayer.cornerRadius = 1
        gripHandleLayer.addSublayer(rightBarLayer)

        ratioBadgeLayer.cornerRadius = 12
        ratioBadgeLayer.backgroundColor = NSColor(white: 0.12, alpha: 0.75).cgColor
        ratioBadgeLayer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        ratioBadgeLayer.borderWidth = 0.75
        ratioBadgeLayer.shadowColor = NSColor.black.cgColor
        ratioBadgeLayer.shadowOpacity = 0.22
        ratioBadgeLayer.shadowOffset = CGSize(width: 0, height: 2)
        ratioBadgeLayer.shadowRadius = 6
        ratioBadgeLayer.opacity = 0

        ratioTextLayer.fontSize = 11.5
        ratioTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        ratioTextLayer.foregroundColor = NSColor.white.cgColor
        ratioTextLayer.alignmentMode = .center
        ratioTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        ratioBadgeLayer.addSublayer(ratioTextLayer)

        layer?.addSublayer(ratioBadgeLayer)

        updateVisualStyles()
    }

    private func updateVisualStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guideTrackLayer.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor(white: 1, alpha: isDark ? 0.25 : 0.22).cgColor,
            NSColor(white: 1, alpha: isDark ? 0.38 : 0.35).cgColor,
            NSColor(white: 1, alpha: isDark ? 0.25 : 0.22).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        gripHandleLayer.backgroundColor = NSColor(
            white: isDark ? 0.22 : 1, alpha: isDark ? 0.72 : 0.76).cgColor
        gripHandleLayer.borderColor = NSColor.white.withAlphaComponent(0.65).cgColor
        // Read against the grip, so they invert with it: light bars on the dark grip, dark on light.
        let bar = NSColor(white: isDark ? 0.88 : 0.28, alpha: isDark ? 0.85 : 0.75).cgColor
        leftBarLayer.backgroundColor = bar
        rightBarLayer.backgroundColor = bar
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualStyles()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSublayers()
        CATransaction.commit()
    }

    private func layoutSublayers() {
        let trackX = round((bounds.width - Self.trackWidth) / 2)
        let insetY: CGFloat = 4
        guideTrackLayer.frame = CGRect(
            x: trackX, y: insetY,
            width: Self.trackWidth, height: max(0, bounds.height - insetY * 2))

        let handleX = round((bounds.width - Self.handleWidth) / 2)
        let handleY = round((bounds.height - Self.handleHeight) / 2)
        gripHandleLayer.frame = CGRect(
            x: handleX, y: handleY, width: Self.handleWidth, height: Self.handleHeight)

        // The two bars that say "this one moves sideways": 2pt wide, 12pt tall, 3pt apart.
        let barWidth: CGFloat = 2
        let barHeight: CGFloat = 12
        let barSpacing: CGFloat = 3
        let startBarX = round((Self.handleWidth - (barWidth * 2 + barSpacing)) / 2)
        let barY = round((Self.handleHeight - barHeight) / 2)
        leftBarLayer.frame = CGRect(x: startBarX, y: barY, width: barWidth, height: barHeight)
        rightBarLayer.frame = CGRect(
            x: startBarX + barWidth + barSpacing, y: barY, width: barWidth, height: barHeight)

        // Above the grip by preference, below it when there is no room above — it must never be
        // clipped, and the panel is exactly as tall as the seam it sits on.
        let badgeX = round((bounds.width - Self.badgeWidth) / 2)
        let above = handleY + Self.handleHeight + 8
        let badgeY =
            above + Self.badgeHeight <= bounds.height - 4
            ? above
            : max(4, handleY - Self.badgeHeight - 8)
        ratioBadgeLayer.frame = CGRect(
            x: badgeX, y: badgeY, width: Self.badgeWidth, height: Self.badgeHeight)
        ratioTextLayer.frame = CGRect(
            x: 0, y: 4, width: Self.badgeWidth, height: Self.badgeHeight - 8)
    }

    /// The grip's rectangle, grown a little — a target the size of the drawing itself is small enough
    /// that taking hold of it feels like aiming.
    private var handleRect: CGRect {
        let x = round((bounds.width - Self.handleWidth) / 2)
        let y = round((bounds.height - Self.handleHeight) / 2)
        return CGRect(x: x, y: y, width: Self.handleWidth, height: Self.handleHeight)
            .insetBy(dx: -4, dy: -4)
    }

    // MARK: Taking or passing the pointer

    /// Whether this point belongs to the seam. The narrow strip either side catches a pointer that
    /// has not reached the grip yet, so approaching it from the side works as well as landing on it.
    private func isPointInHoverZone(_ point: NSPoint) -> Bool {
        abs(point.x - bounds.width / 2) <= 6 || handleRect.contains(point)
    }

    /// A slightly-wider grip is a fairer target than the drawing.
    ///
    /// Returning `nil` is what makes the hundred-point band free: the pointer goes to whichever
    /// window is underneath, so the seam can be wide without being in the way. During a drag it takes
    /// everything instead, because letting one go mid-gesture would drop the drag.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isDragging { return self }
        return isPointInHoverZone(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways,
                          .inVisibleRect],
                owner: self, userInfo: nil))
    }

    /// Only once the grip is actually visible. A resize cursor over nothing would announce a seam
    /// that, from the reader's side, has not appeared.
    override func resetCursorRects() {
        super.resetCursorRects()
        if isHovered { addCursorRect(handleRect, cursor: .resizeLeftRight) }
    }

    override func cursorUpdate(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if isPointInHoverZone(localPoint) { NSCursor.resizeLeftRight.set() }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if isPointInHoverZone(convert(event.locationInWindow, from: nil)) { setHovered(true) }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let inZone = isPointInHoverZone(convert(event.locationInWindow, from: nil))
        if inZone && !isHovered {
            setHovered(true)
        } else if !inZone && isHovered && !isDragging {
            setHovered(false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if !isDragging && isHovered { setHovered(false) }
    }

    /// Whether the pointer is already on the seam when the band appears, which it is whenever the
    /// reader has driven the pointer *to* the seam rather than past it.
    func checkInitialHover() {
        guard let window, window.frame.contains(NSEvent.mouseLocation) else { return }
        // Twice translated: screen to the window, then the window to this view, whose bounds are
        // what `handleRect` is written against. Spelled out rather than nested, because Swift reads
        // `convert(_:from:)` against both points and rectangles and picks the rectangle.
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        if isPointInHoverZone(localPoint) { setHovered(true) }
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        window?.invalidateCursorRects(for: self)
        animateHoverState(hovered: hovered)
    }

    private func animateHoverState(hovered: Bool) {
        CATransaction.begin()
        if hovered {
            CATransaction.setAnimationDuration(0.20)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1))
            guideTrackLayer.opacity = 1
            gripHandleLayer.opacity = 1
            gripHandleLayer.transform = CATransform3DIdentity
        } else {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            guideTrackLayer.opacity = 0
            gripHandleLayer.opacity = 0
            gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        }
        CATransaction.commit()
    }

    // MARK: The ratio badge

    func showRatio(left: Int, right: Int) {
        ratioTextLayer.string = "\(left)% : \(right)%"
        guard ratioBadgeLayer.opacity < 0.1 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        ratioBadgeLayer.opacity = 1
        CATransaction.commit()
    }

    func hideRatio() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        ratioBadgeLayer.opacity = 0
        CATransaction.commit()
    }

    // MARK: Gestures

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            springPulse()
            owner?.onDoubleClick?()
            return
        }
        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        owner?.onMouseDown?(dragStartMouseLocation)
        // Taken hold of: a small swell, answered by an equally small settle on release.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        gripHandleLayer.transform = CATransform3DMakeScale(1.06, 1.06, 1)
        CATransaction.commit()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        owner?.onMouseDragged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        owner?.onMouseUp?()
        hideRatio()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        gripHandleLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func springPulse() {
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 0.88, 1.12, 1]
        pulse.keyTimes = [0, 0.35, 0.70, 1]
        pulse.duration = 0.20
        gripHandleLayer.add(pulse, forKey: "doubleClickPulse")
    }

    func resetState() {
        isHovered = false
        isDragging = false
        window?.invalidateCursorRects(for: self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideTrackLayer.opacity = 0
        gripHandleLayer.opacity = 0
        gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        ratioBadgeLayer.opacity = 0
        CATransaction.commit()
    }
}

private struct DeloresVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private enum DeloresCompanionEdge { case top, bottom, left, right }

/// The edge of `frame` the point is closest to. Ties go to the right edge, which is where the
/// companion starts.
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
