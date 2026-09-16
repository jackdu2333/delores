import CoreGraphics

/// Where the Context Island sits: hung from the menu bar, with its top edge as the anchor every
/// later size grows away from. Pure, so a display's facts are injected rather than read.
enum DeloresContextIslandPlacement {
    static let preferredWidth: CGFloat = 420

    /// The bar's wish. A display with a notch reports the whole safe strip as its menu bar, so the
    /// wish survives there; a shallow menu bar caps the bar instead.
    static let preferredBarHeight: CGFloat = 38

    /// Keeps the bar off the menu bar's own edges rather than flush against them.
    static let menuBarClearance: CGFloat = 2

    /// The card's wish once the bar opens for an answer.
    static let preferredExpandedHeight: CGFloat = 390

    /// A card never takes more than this share of what the display actually shows, so the dock and
    /// whatever is behind the window stay reachable on a short screen.
    static let maximumVisibleFraction: CGFloat = 0.60

    /// The card's corner, carried over from the toolbar this island came from.
    ///
    /// Deliberately wider than half a closed bar's height, so a closed bar clamps to the same pill it
    /// has always been while an open card gets the wider corner. `RoundedRectangle` in the continuous
    /// style is pixel-for-pixel what `Capsule` draws — the circular style is not, and differs by a
    /// hair along the ends.
    static let openCornerRadius: CGFloat = 22

    static let margin: CGFloat = 10

    /// The card's height, which the display's visible area may cap below the wish.
    static func expandedHeight(preferred: CGFloat, in screen: InvocationScreen) -> CGFloat {
        min(preferred, max(0, screen.visibleFrame.height) * maximumVisibleFraction)
    }

    /// `size.height` is the wish; the menu bar may leave less room than that.
    static func collapsedFrame(in screen: InvocationScreen, size: CGSize) -> CGRect {
        let height = barHeight(in: screen, preferred: size.height)
        return CGRect(
            x: anchoredX(in: screen, width: size.width),
            y: barOriginY(in: screen, height: height),
            width: size.width,
            height: height)
    }

    /// Anchored by its top edge, so a resize grows downward and the bar never drifts upward.
    static func frame(keepingTopEdgeOf anchor: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: anchor.minX, y: anchor.maxY - height, width: anchor.width, height: height)
    }

    private static func barHeight(in screen: InvocationScreen, preferred: CGFloat) -> CGFloat {
        let menuBar = max(0, screen.menuBarFrame.height)
        guard menuBar > menuBarClearance else { return preferred }
        return min(preferred, menuBar - menuBarClearance)
    }

    /// Beside the notch's right safe area when the display has one, square on the screen otherwise.
    private static func anchoredX(in screen: InvocationScreen, width: CGFloat) -> CGFloat {
        let minX = screen.frame.minX + margin
        let maxX = max(minX, screen.frame.maxX - width - margin)
        let preferred =
            usesNotchAnchor(screen)
            ? screen.auxiliaryTopRightArea!.minX + margin
            : screen.frame.midX - width / 2
        return min(max(preferred, minX), maxX)
    }

    private static func barOriginY(in screen: InvocationScreen, height: CGFloat) -> CGFloat {
        let menuBar = max(0, screen.menuBarFrame.height)
        let origin =
            menuBar > 0
            ? screen.menuBarFrame.minY + (menuBar - height) / 2
            : screen.frame.maxY - height
        let maxY = max(screen.frame.minY, screen.frame.maxY - height)
        return min(max(origin, screen.frame.minY), maxY)
    }

    private static func usesNotchAnchor(_ screen: InvocationScreen) -> Bool {
        (screen.auxiliaryTopRightArea?.width ?? 0) > 0
    }
}
