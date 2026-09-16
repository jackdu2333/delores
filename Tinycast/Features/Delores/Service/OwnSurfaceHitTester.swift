import AppKit

@MainActor
enum DeloresOwnSurfaceHitTester {
    static func containsInteractiveSurface(at point: CGPoint) -> Bool {
        guard let application = NSApp else { return false }
        let windows = application.windows.map {
            DeloresSurfaceWindowSnapshot(
                frame: $0.frame,
                isVisible: $0.isVisible,
                ignoresMouseEvents: $0.ignoresMouseEvents)
        }
        return DeloresOwnSurfaceHitPolicy.containsInteractiveSurface(at: point, in: windows)
    }
}
