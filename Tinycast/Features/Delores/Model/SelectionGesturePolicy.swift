import CoreGraphics
import Foundation

enum DeloresSelectionGesturePolicy {
    static let dragThreshold: CGFloat = 8
    static let doubleClickWindow: TimeInterval = 0.35
    static let doubleClickDistance: CGFloat = 4

    static func qualifies(
        dragDistance: CGFloat,
        previousReleaseDistance: CGFloat?,
        elapsedSincePreviousRelease: TimeInterval?
    ) -> Bool {
        if dragDistance >= dragThreshold { return true }
        guard let previousReleaseDistance, let elapsedSincePreviousRelease else { return false }
        return elapsedSincePreviousRelease < doubleClickWindow
            && previousReleaseDistance <= doubleClickDistance
    }
}
