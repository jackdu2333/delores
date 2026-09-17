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
    private var snapGhost: DeloresSnapGhostPanel?
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
    /// The handle is exactly as wide as the hover tolerance on both sides. Anything narrower would
    /// let the pointer leave the panel while still inside the tolerance, and the overlay would flicker
    /// on and off at its edge.
    private static let dividerHoverTolerance: CGFloat = DeloresDividerPanel.width / 2
    private static let dividerPairGap: CGFloat = 12
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
        snapGhost?.hide(); snapGhost = nil
        snapHoveredSlot = nil
        snapCandidate = nil
        snapIsActive = false
        snapMonitorStart = .zero
        if snapHasClaimedGate {
            snapHasClaimedGate = false
            interactionGate.release(.snapping)
        }
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
            if point.y >= screen.visibleFrame.maxY - Self.snapIslandRevealInset {
                snapIsActive = true
                snapIsland = snapIsland ?? DeloresSnapIslandPanel()
                snapIsland?.show(on: screen)
                showSnapGhost(for: snapIsland?.slot(at: point), on: screen)
            } else if snapIsActive {
                snapIsActive = false
                snapIsland?.hide()
                showSnapGhost(for: nil, on: screen)
            }
        case .leftMouseUp:
            defer { releaseSnap() }
            guard snapIsActive, let candidate = snapCandidate, let snapIsland,
                  let screen = screenContaining(point),
                  let slot = snapIsland.slot(at: point) else { return }
            setWindowFrame(candidate.window, rect: slot.rect(in: screen.visibleFrame))
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

    /// Shows where the window will land while a card is under the pointer.
    ///
    /// The island without this is four pictures and no answer to "and if I let go here?". The
    /// reference drew the same preview, and releasing outside a card does nothing by design — so
    /// without it the whole feature reads as broken rather than as unaimed.
    private func showSnapGhost(for slot: DeloresSnapSlot?, on screen: NSScreen) {
        guard slot != snapHoveredSlot else { return }
        snapHoveredSlot = slot
        guard let slot else {
            snapGhost?.hide()
            return
        }
        let panel = snapGhost ?? DeloresSnapGhostPanel()
        snapGhost = panel
        panel.show(rect: slot.rect(in: screen.visibleFrame))
    }

    // MARK: Split divider

    private func startDivider() {
        guard dividerMonitor == nil else { return }
        let panel = divider ?? DeloresDividerPanel()
        divider = panel
        // The overlay is live over the seam and transparent everywhere else, so a press on the
        // handle is taken here and never reaches the window underneath.
        panel.onMouseDown = { [weak self] point in self?.beginDivider(at: point) }
        panel.onMouseDragged = { [weak self] point in self?.dragDivider(to: point) }
        panel.onMouseUp = { [weak self] in self?.endDivider() }
        panel.onPointerExit = { [weak self] in self?.dividerPointerExited() }
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
        interactionGate.release(.divider)
    }

    private func hideDivider() {
        splitPair = nil
        divider?.hide()
    }

    private func dividerPointerExited() {
        guard dividerStart == nil else { return }
        hideDivider()
    }

    private func refreshDivider(at point: CGPoint) {
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
    }

    private func endDivider() {
        dividerStart = nil
        lastDividerScan = .distantPast
        interactionGate.release(.divider)
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
    init() {
        let hosting = NSHostingView(rootView: DeloresSnapIslandView())
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
    func show(on screen: NSScreen) {
        activeScreen = screen
        setFrame(CGRect(x: screen.frame.midX - islandSize.width / 2,
                        y: screen.visibleFrame.maxY - islandSize.height - 8,
                        width: islandSize.width, height: islandSize.height), display: true)
        orderFrontRegardless()
    }
    func hide() { ignoresMouseEvents = true; orderOut(nil) }
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
                return ratio <= 2.0 / 3.0 ? .mainWorkspace : .sideWorkspace
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
    enum Card: CaseIterable { case halfSplit, mainSide, quarter, thirds }
    static let size = CGSize(width: 620, height: 88)
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let gap: CGFloat = 12
    static let cardWidth: CGFloat = 140
    static let cardHeight: CGFloat = 72
    static let bounds = CGRect(origin: .zero, size: size)
    static let quarterCenterY = verticalPadding + cardHeight / 2

    static func rect(for card: Card) -> CGRect {
        let index = CGFloat(Card.allCases.firstIndex(of: card) ?? 0)
        return CGRect(
            x: horizontalPadding + index * (cardWidth + gap), y: verticalPadding,
            width: cardWidth, height: cardHeight)
    }
}

private struct DeloresSnapIslandView: View {
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
        .background(DeloresVisualEffectView(material: .popover, blending: .behindWindow).clipShape(Capsule()))
    }

    @ViewBuilder
    private func card(_ card: SnapIslandGeometry.Card) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.primary.opacity(0.72), lineWidth: 1.5)
            switch card {
            case .halfSplit:
                divider(.vertical)
            case .mainSide:
                HStack(spacing: 0) {
                    Color.clear.frame(width: SnapIslandGeometry.cardWidth * 2.0 / 3.0 - 0.75)
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            case .quarter:
                VStack(spacing: 0) { divider(.horizontal); divider(.horizontal) }
                HStack(spacing: 0) { divider(.vertical); divider(.vertical) }
            case .thirds:
                HStack(spacing: 0) { divider(.vertical); divider(.vertical) }
            }
        }
        .frame(width: SnapIslandGeometry.cardWidth, height: SnapIslandGeometry.cardHeight)
    }

    private func divider(_ axis: Axis) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.72))
            .frame(width: axis == .vertical ? 1.5 : nil, height: axis == .horizontal ? 1.5 : nil)
    }

    private enum Axis { case horizontal, vertical }
}

/// The outline of where the window will land, over the real desktop, while a card is hovered.
///
/// Click-through on purpose: it is drawn across the whole target area, which is where the pointer and
/// the dragged window are, so taking mouse events would break the drag it is describing.
private final class DeloresSnapGhostPanel: NSPanel {
    private let hosting: NSHostingView<DeloresSnapGhostView>

    init() {
        let hosting = NSHostingView(rootView: DeloresSnapGhostView())
        hosting.sizingOptions = []
        self.hosting = hosting
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .popUpMenu; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true; isReleasedWhenClosed = false; canHide = false
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }

    func show(rect: CGRect) {
        setFrame(rect, display: true)
        orderFrontRegardless()
    }
    func hide() { orderOut(nil) }
}

private struct DeloresSnapGhostView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.accentColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])))
    }
}

private final class DeloresDividerPanel: NSPanel {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?
    var onPointerExit: (() -> Void)?
    private let handle = DeloresDividerView()
    /// The hover tolerance is derived from this, so the two cannot drift apart.
    static let width: CGFloat = 36

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .floating; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true; isReleasedWhenClosed = false; canHide = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        handle.owner = self
        handle.autoresizingMask = [.width, .height]
        contentView = handle
    }

    /// Live only over the seam. Everywhere else the panel is hidden and click-through, so the app
    /// underneath keeps its own pointer.
    override var canBecomeKey: Bool { true }

    func show(x: CGFloat, y: CGFloat, height: CGFloat) {
        setFrame(
            CGRect(x: x - Self.width / 2, y: y, width: Self.width, height: max(30, height)),
            display: true)
        ignoresMouseEvents = false
        orderFrontRegardless()
    }
    func hide() { ignoresMouseEvents = true; orderOut(nil) }
}

private final class DeloresDividerView: NSView {
    weak var owner: DeloresDividerPanel?
    private var dragging = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .cursorUpdate],
                owner: self, userInfo: nil))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) {
        guard !dragging else { return }
        owner?.onPointerExit?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: bounds.midX - 2, y: 0, width: 4, height: bounds.height),
            xRadius: 2, yRadius: 2
        ).fill()
    }

    override func mouseDown(with event: NSEvent) { dragging = true; owner?.onMouseDown?(NSEvent.mouseLocation) }
    override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        owner?.onMouseDragged?(NSEvent.mouseLocation)
    }
    override func mouseUp(with event: NSEvent) { dragging = false; owner?.onMouseUp?() }
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
