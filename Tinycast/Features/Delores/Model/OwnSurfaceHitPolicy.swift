import CoreGraphics

struct DeloresSurfaceWindowSnapshot: Equatable, Sendable {
    let frame: CGRect
    let isVisible: Bool
    let ignoresMouseEvents: Bool
}

enum DeloresOwnSurfaceHitPolicy {
    static func containsInteractiveSurface(
        at point: CGPoint,
        in windows: [DeloresSurfaceWindowSnapshot],
        padding: CGFloat = 4
    ) -> Bool {
        windows.contains { window in
            window.isVisible
                && !window.ignoresMouseEvents
                && window.frame.insetBy(dx: -padding, dy: -padding).contains(point)
        }
    }
}
