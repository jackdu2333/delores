import AppKit
@preconcurrency import ApplicationServices

@MainActor
enum DeloresWindowGeometry {
    static func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXWindowAccess.application(for: app.processIdentifier)
        guard let window = AXWindowAccess.targetWindow(in: appElement),
              AXWindowAccess.isEligible(window) else { return nil }
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        return window
    }
    @discardableResult
    static func setWindowFrame(_ window: AXUIElement, rect: CGRect) -> Bool {
        let geometry = AXGeometry(screens: NSScreen.screens)
        guard AXWindowAccess.isEligible(window), !AXWindowAccess.isFullScreen(window),
              let current = AXWindowAccess.frame(of: window),
              AXWindowAccess.isSettable(kAXPositionAttribute, on: window) else { return false }
        let canResize = AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
        let axRect = geometry.flip(rect)
        guard AXWindowAccess.write(axRect, anchor: WindowPlacementEngine.Anchor.topLeading, to: window, current: current, canResize: canResize, canvas: nil) != nil,
              let validated = AXWindowAccess.frame(of: window) else { return false }
        let tolerance = AXWindowAccess.clampTolerance
        return abs(validated.minX - axRect.minX) <= tolerance && abs(validated.minY - axRect.minY) <= tolerance && (!canResize || (abs(validated.width - axRect.width) <= tolerance && abs(validated.height - axRect.height) <= tolerance))
    }
    static func activeScreen() -> NSScreen? { NSScreen.main ?? NSScreen.screens.first }
    static func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? activeScreen()
    }
}
