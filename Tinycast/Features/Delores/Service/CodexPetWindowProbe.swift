import AppKit
import CoreGraphics

/// Finds the Codex pet without depending on Codex's private renderer messages.
///
/// Codex exposes no public action or callback for its pet overlay. WindowServer metadata is the
/// narrowest bridge available: an on-screen, borderless Codex window that is small enough to be a
/// pet can be an anchor, while anything ambiguous returns nil and keeps Delores on its menu-bar
/// fallback.
@MainActor
final class DeloresCodexPetWindowProbe {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let minimumPetSide: CGFloat = 24
    private static let maximumPetSide: CGFloat = 480
    private static let maximumPetArea: CGFloat = 180_000
    private static let snapshotLifetime: TimeInterval = 0.05
    private var cachedFrames: [CGRect] = []
    private var cachedAt = -Double.infinity

    func anchor(on screen: NSScreen) -> DeloresCompanionAnchor? {
        guard let frame = petFrame(on: screen) else { return nil }
        let radius = max(frame.width, frame.height) / 2
        return (
            center: frame.midPoint,
            edge: DeloresCompanionWander.edge(for: frame.midPoint, in: screen.frame),
            radius: radius)
    }

    /// A drag that starts here belongs to Codex's pet, not to a window behind it.
    func containsPet(at point: CGPoint) -> Bool {
        guard let frame = candidateFrames().single else { return false }
        return frame.insetBy(dx: -12, dy: -12).contains(point)
    }

    private func petFrame(on screen: NSScreen) -> CGRect? {
        let candidates = candidateFrames().filter {
            $0.intersects(screen.frame) && screen.frame.contains($0.midPoint)
        }
        guard candidates.count == 1 else { return nil }
        return candidates[0]
    }

    private func candidateFrames() -> [CGRect] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - cachedAt < Self.snapshotLifetime { return cachedFrames }
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
            ?? []
        let geometry = AXGeometry(screens: NSScreen.screens)
        cachedFrames = windows.compactMap { window in
            guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber,
                NSRunningApplication(processIdentifier: pidNumber.int32Value)?.bundleIdentifier
                    == Self.codexBundleIdentifier,
                let layer = window[kCGWindowLayer as String] as? NSNumber,
                layer.intValue > 0,
                let alpha = window[kCGWindowAlpha as String] as? NSNumber,
                alpha.doubleValue > 0,
                let onScreen = window[kCGWindowIsOnscreen as String] as? NSNumber,
                onScreen.boolValue,
                (window[kCGWindowName as String] as? String ?? "").isEmpty,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let cgFrame = CGRect(dictionaryRepresentation: bounds),
                Self.isPetSized(cgFrame)
            else { return nil }
            return geometry.flip(cgFrame)
        }
        cachedAt = now
        return cachedFrames
    }

    private static func isPetSized(_ frame: CGRect) -> Bool {
        guard frame.width >= minimumPetSide, frame.height >= minimumPetSide,
            max(frame.width, frame.height) <= maximumPetSide,
            frame.width * frame.height <= maximumPetArea
        else { return false }
        return true
    }
}

private extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension Array where Element == CGRect {
    var single: CGRect? { count == 1 ? first : nil }
}
