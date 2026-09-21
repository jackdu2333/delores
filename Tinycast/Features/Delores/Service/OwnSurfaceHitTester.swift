import AppKit

/// Only interactive transient surfaces can suppress a foreign selection gesture.
protocol DeloresSelectionBlockingSurface: AnyObject {}

@MainActor
enum DeloresOwnSurfaceHitTester {
    static func containsInteractiveSurface(at point: CGPoint) -> Bool {
        guard let application = NSApp else { return false }
        let windows = application.windows.compactMap { window -> DeloresSurfaceWindowSnapshot? in
            guard window is DeloresSelectionBlockingSurface else { return nil }
            return DeloresSurfaceWindowSnapshot(
                frame: window.frame,
                isVisible: window.isVisible,
                ignoresMouseEvents: window.ignoresMouseEvents,
                blocksSelection: true)
        }
        return DeloresOwnSurfaceHitPolicy.containsInteractiveSurface(at: point, in: windows)
    }
}
