import AppKit
@preconcurrency import ApplicationServices
@MainActor
final class DeloresSplitDividerCoordinator {
    private let settings: AppSettings
    private let interactionGate: DeloresSurfaceInteractionGate
    private var dividerMonitor: Any?
    private var divider: DeloresDividerPanel?
    private var splitPair: SplitPair?
    private var dividerStart: DividerDrag?
    private var lastDividerScan = Date.distantPast
    private var lastDividerMouseLocation = CGPoint.zero
    private var recentLeftSnap: DeloresSnapRecord?
    private var recentRightSnap: DeloresSnapRecord?
    private static let dividerHoverTolerance: CGFloat = DeloresDividerPanel.width / 2
    private static let dividerPairGap: CGFloat = 12
    private static let dividerMouseEpsilon: CGFloat = 0.5
    private static let dividerScanInterval: TimeInterval = 0.08
    private struct SplitPair {
        let left: AXUIElement; let right: AXUIElement
        var leftRect: CGRect; var rightRect: CGRect; let screen: NSScreen
        var dividerX: CGFloat { (leftRect.maxX + rightRect.minX) / 2 }
        var y: CGFloat { max(leftRect.minY, rightRect.minY) }
        var height: CGFloat { max(0, min(leftRect.maxY, rightRect.maxY) - y) }
    }
    private struct DividerDrag { let pair: SplitPair; let startX: CGFloat }
    private struct DeloresSnapRecord { let window: AXUIElement; let rect: CGRect; let when: TimeInterval }
    init(settings: AppSettings, interactionGate: DeloresSurfaceInteractionGate) { self.settings = settings; self.interactionGate = interactionGate }
    func applyEnabled() { settings.deloresSplitDividerEnabled ? startDivider() : stopDivider() }
    func prepareForTermination() { stopDivider() }
    func windowGeometryDidChange(at point: CGPoint) {
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
    func registerSnappedWindow(
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
        let leftApplied = DeloresWindowGeometry.setWindowFrame(pair.left, rect: left)
        let rightApplied = DeloresWindowGeometry.setWindowFrame(pair.right, rect: right)
        // Same rule a refused drag follows: nothing half-applied stays on the screen.
        guard leftApplied, rightApplied else {
            if leftApplied { DeloresWindowGeometry.setWindowFrame(pair.left, rect: pair.leftRect) }
            if rightApplied { DeloresWindowGeometry.setWindowFrame(pair.right, rect: pair.rightRect) }
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

        guard Permissions.isAccessibilityTrusted(), interactionGate.owner == nil || interactionGate.owner == .divider else {
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
        let leftApplied = DeloresWindowGeometry.setWindowFrame(start.pair.left, rect: left)
        let rightApplied = DeloresWindowGeometry.setWindowFrame(start.pair.right, rect: right)
        guard leftApplied, rightApplied else {
            // One half moving and the other refusing is the one outcome that must never be left on
            // screen: put whichever moved back where the drag started.
            if leftApplied { DeloresWindowGeometry.setWindowFrame(start.pair.left, rect: start.pair.leftRect) }
            if rightApplied { DeloresWindowGeometry.setWindowFrame(start.pair.right, rect: start.pair.rightRect) }
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


    private func findSplitPair(near point: CGPoint) -> SplitPair? {
        guard let screen = DeloresWindowGeometry.screenContaining(point) else { return nil }
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

}
