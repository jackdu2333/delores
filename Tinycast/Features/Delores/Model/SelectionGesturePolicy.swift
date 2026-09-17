import CoreGraphics
import Foundation

enum DeloresSelectionGesturePolicy {
    enum Kind: Sendable, Equatable {
        case drag
        case doubleClick
    }

    static let dragThreshold: CGFloat = 8
    static let doubleClickWindow: TimeInterval = 0.35
    static let doubleClickDistance: CGFloat = 4

    static func qualifies(
        dragDistance: CGFloat,
        previousReleaseDistance: CGFloat?,
        elapsedSincePreviousRelease: TimeInterval?
    ) -> Kind? {
        if dragDistance >= dragThreshold { return .drag }
        guard let previousReleaseDistance, let elapsedSincePreviousRelease else { return nil }
        return elapsedSincePreviousRelease < doubleClickWindow
            && previousReleaseDistance <= doubleClickDistance ? .doubleClick : nil
    }
}
