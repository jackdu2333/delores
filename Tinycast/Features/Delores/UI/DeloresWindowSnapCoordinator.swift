import AppKit
@preconcurrency import ApplicationServices
@MainActor
final class DeloresWindowSnapCoordinator {
    private let settings: AppSettings
    private let interactionGate: DeloresSurfaceInteractionGate
    private var snapMonitor: Any?
    private var snapIsland: DeloresSnapIslandPanel?
    private var snapMonitorStart = CGPoint.zero
    private var snapStartedOnIgnoredSurface = false
    private var snapCandidate: SnapCandidate?
    /// Whether the candidate still has to be read. Reading it costs a burst of accessibility
    /// calls into the app that was pressed, and a press that never becomes a drag — the
    /// reader's every ordinary click — must not pay for a drag it did not make.
    private var snapNeedsCandidate = false
    private var snapIsActive = false
    private var snapHasClaimedGate = false
    private let additionalIgnoredPoint: (@MainActor (CGPoint) -> Bool)?
    var onWindowGeometryChanged: ((CGPoint) -> Void)?
    var onWindowSnapped: ((AXUIElement, DeloresSnapSlot, CGRect, NSScreen) -> Void)?
    private static let snapDragThreshold: CGFloat = 8
    private static let snapWindowThreshold: CGFloat = 20
    private struct SnapCandidate { let window: AXUIElement; let app: NSRunningApplication; let initialFrame: CGRect }
    init(
        settings: AppSettings, interactionGate: DeloresSurfaceInteractionGate,
        additionalIgnoredPoint: (@MainActor (CGPoint) -> Bool)? = nil
    ) {
        self.settings = settings
        self.interactionGate = interactionGate
        self.additionalIgnoredPoint = additionalIgnoredPoint
    }
    func applyEnabled() { settings.deloresWindowSnappingEnabled ? startSnapping() : stopSnapping() }
    func prepareForTermination() { stopSnapping() }
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
        snapCandidate = nil
        snapNeedsCandidate = false
        snapIsActive = false
        snapMonitorStart = .zero
        snapStartedOnIgnoredSurface = false
        // Only a drag that actually moved a window can have moved a seam, and only a claimed
        // gate means one did. Notifying on every release made the divider walk every window
        // on the screen on the reader's every click — a burst of accessibility traffic into
        // whatever app was clicked, for a geometry that had not changed.
        let movedAWindow = snapHasClaimedGate
        if snapHasClaimedGate {
            snapHasClaimedGate = false
            interactionGate.release(.snapping)
        }
        if movedAWindow {
            // A window stopped moving, which is the discrete signal that every cached seam may
            // now be wrong. Not guessed from a mouse-up: the press that moved it belongs to
            // another app.
            onWindowGeometryChanged?(NSEvent.mouseLocation)
        }
    }

    /// Every cached seam is stale now, so discovery runs again on the next opportunity rather than
    /// on its own clock.
    private func handleSnap(_ type: NSEvent.EventType, at point: CGPoint) {
        guard settings.deloresWindowSnappingEnabled else { return }
        switch type {
        case .leftMouseDown:
            snapMonitorStart = point
            snapStartedOnIgnoredSurface = additionalIgnoredPoint?(point) == true
            // The candidate is not read yet: see `snapNeedsCandidate`. Reading it here put
            // accessibility calls into the pressed app before anything knew whether the press
            // was a drag at all.
            snapCandidate = nil
            snapNeedsCandidate = true
            snapIsActive = false
        case .leftMouseDragged:
            guard !snapStartedOnIgnoredSurface else { return }
            guard hypot(point.x - snapMonitorStart.x, point.y - snapMonitorStart.y) >= Self.snapDragThreshold else { return }
            if snapNeedsCandidate {
                snapNeedsCandidate = false
                snapCandidate = snapCandidate(at: point)
            }
            // The gate is claimed only once a window has actually moved. Claiming it on pointer
            // distance alone would swallow the ordinary text selection this gesture might be.
            if !snapHasClaimedGate {
                guard let candidate = snapCandidate, hasMoved(candidate) else { return }
                guard interactionGate.claim(.snapping) else { return }
                snapHasClaimedGate = true
            }
            guard let screen = DeloresWindowGeometry.screenContaining(point) else { return }
            let revealFrame = DeloresSnapTriggerGeometry.revealFrame(
                screenFrame: screen.frame, visibleFrame: screen.visibleFrame)
            let topEdgeBand = DeloresSnapTriggerGeometry.topEdgeBand(
                screenFrame: screen.frame, visibleFrame: screen.visibleFrame)

            let remainsAvailable = snapIsActive
                ? topEdgeBand.contains(point)
                : revealFrame.contains(point)
            if remainsAvailable {
                snapIsActive = true
                snapIsland = snapIsland ?? DeloresSnapIslandPanel()
                snapIsland?.showAtTopCenter(on: screen)
                snapIsland?.setHoveredSlot(snapIsland?.slot(at: point))
            } else if snapIsActive {
                snapIsActive = false
                snapIsland?.hide()
            }
        case .leftMouseUp:
            defer { releaseSnap() }
            guard !snapStartedOnIgnoredSurface else { return }
            guard snapIsActive, let candidate = snapCandidate, let snapIsland,
                  let screen = DeloresWindowGeometry.screenContaining(point),
                  let slot = snapIsland.slot(at: point) else { return }
            let target = slot.rect(in: screen.visibleFrame, gap: CGFloat(settings.windowGap))
            // Only a window that really went there is worth remembering: see `registerSnappedWindow`.
            if DeloresWindowGeometry.setWindowFrame(candidate.window, rect: target) {
                onWindowSnapped?(candidate.window, slot, target, screen)
            }
        default:
            break
        }
    }

    /// The window the drag would move, read once the press has become one. Delores' own surfaces
    /// are not targets. The frame it returns is a few points into the drag rather than the press
    /// itself, which only moves the gate claim a little further out — in the safe direction, away
    /// from the text selection this gesture might still turn out to be.
    private func snapCandidate(at point: CGPoint) -> SnapCandidate? {
        guard Permissions.isAccessibilityTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = DeloresWindowGeometry.focusedWindow(of: app),
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

}
