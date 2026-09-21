import CoreGraphics
import Foundation

struct DeloresSurfaceWindowSnapshot: Equatable, Sendable {
    let frame: CGRect
    let isVisible: Bool
    let ignoresMouseEvents: Bool
    let blocksSelection: Bool
}

enum DeloresOwnSurfaceHitPolicy {
    static func containsInteractiveSurface(
        at point: CGPoint,
        in windows: [DeloresSurfaceWindowSnapshot],
        padding: CGFloat = 4
    ) -> Bool {
        windows.contains { window in
            window.blocksSelection
                && window.isVisible
                && !window.ignoresMouseEvents
                && window.frame.insetBy(dx: -padding, dy: -padding).contains(point)
        }
    }
}

/// Single owner for transient cross-surface mouse gestures.
///
/// A claimed gesture must not also be interpreted as text selection. The Context Surface decides
/// from the mouse-up that ended a drag, and it asks about that release a beat later — long after a
/// window drag has already released the gate — so letting go has to keep the gesture suppressed for
/// a moment rather than reopening it instantly.
@MainActor
final class DeloresSurfaceInteractionGate {
    enum Owner: Equatable {
        case companion
        case snapping
        case divider
    }

    /// How long a released gesture keeps suppressing selection capture. Longer than the Context
    /// Surface's own post-release delay, so the release that ended the drag is still covered.
    static let releaseSuppression: TimeInterval = 0.35

    private(set) var owner: Owner?
    private var suppressedUntil: TimeInterval = -.infinity

    func claim(_ owner: Owner) -> Bool {
        guard self.owner == nil || self.owner == owner else { return false }
        self.owner = owner
        return true
    }

    func release(_ owner: Owner) {
        guard self.owner == owner else { return }
        self.owner = nil
        suppressedUntil = ProcessInfo.processInfo.systemUptime + Self.releaseSuppression
    }

    func reset() {
        owner = nil
        suppressedUntil = -.infinity
    }

    /// True while a Spatial gesture is running or was just released, so the Context Surface must
    /// leave this mouse gesture alone.
    var blocksSelection: Bool {
        owner != nil || ProcessInfo.processInfo.systemUptime < suppressedUntil
    }
}
