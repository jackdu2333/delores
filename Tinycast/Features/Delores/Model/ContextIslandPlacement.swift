import CoreGraphics

/// Where the Context Island sits: hung from the menu bar, with its top edge as the anchor every
/// later size grows away from. Pure, so a display's facts are injected rather than read.
enum DeloresContextIslandPlacement {
    /// The fallback width, used when the bar cannot measure itself. Not a target: a bar is meant to
    /// hug its own controls, so a short catalog does not leave two dead ends of glass.
    static let preferredWidth: CGFloat = 420

    /// Below this the bar is narrower than the controls it holds, so a measurement under it is a
    /// view that has not laid out yet rather than a genuinely narrow bar.
    static let minimumWidth: CGFloat = 200

    /// The bar's wish. A display with a notch reports the whole safe strip as its menu bar, so the
    /// wish survives there; a shallow menu bar caps the bar instead.
    static let preferredBarHeight: CGFloat = 38

    /// Keeps the bar off the menu bar's own edges rather than flush against them.
    static let menuBarClearance: CGFloat = 2

    /// The card's wish once the bar opens for an answer.
    static let preferredExpandedHeight: CGFloat = 390

    /// The floor under the card's width. The bar hugs its own controls, but a paragraph needs a
    /// column: a reader who switched most of the catalog off should not get an answer wrapped every
    /// three words because the bar they left it with is narrow.
    ///
    /// 420 is the toolbar this island came from: it calls the same number its reading baseline and
    /// takes `max(420, collapsed + 88)` for the opened width, so a default catalog opens to exactly
    /// this. Matching it means an answer is set in the same column it was set in before.
    static let minimumReadingWidth: CGFloat = 420

    /// How far above its resting place the bar starts, so it settles down onto the menu bar instead
    /// of simply appearing there. Taken from the toolbar this island came from, which condenses out
    /// of the top of the screen rather than fading in: 4pt over 180ms, eased out.
    static let enterSlide: CGFloat = 4

    /// The reading card's own corner. Softer than the vessel's, because it is a surface *inside* the
    /// glass: matching the vessel's corner would make the two read as one outline.
    static let cardCornerRadius: CGFloat = 14

    /// How far the card and the follow-up field sit from the vessel's sides. The vessel's own edge is
    /// 22pt-rounded, so a surface that ran to it would look like it had been pushed through.
    static let cardInset: CGFloat = 11

    /// The gap under the follow-up field, so the field stands clear of the vessel's bottom edge.
    static let pillBottomInset: CGFloat = 9

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

    /// The height the bar is actually given. Exposed so the bar can lay itself out against it
    /// instead of against its own wish — a bar laid out at 38pt inside a 28pt panel loses its
    /// bottom edge, which is what clipping the pills looked like.
    static func collapsedHeight(preferred: CGFloat, in screen: InvocationScreen) -> CGFloat {
        barHeight(in: screen, preferred: preferred)
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

    /// The bar's width, hugging the controls it actually holds.
    ///
    /// The guard is the point of this function rather than an edge case: a hosted view that has not
    /// laid out yet reports a zero ideal width, and a bar sized to that would clip everything in it.
    /// Anything at or under `minimumWidth` is therefore read as "no measurement" and falls back —
    /// too wide is recoverable, too narrow is not. Growth past `preferredWidth` is allowed up to the
    /// display, because a long catalog of actions should widen the bar rather than crush it.
    static func barWidth(hugging measured: CGFloat, in screen: InvocationScreen) -> CGFloat {
        let usable = max(minimumWidth, screen.frame.width - margin * 2)
        guard measured.isFinite, measured > minimumWidth else {
            return min(preferredWidth, usable)
        }
        return min(measured, usable)
    }

    /// The panel's width while a card is open: the bar's own width, unless the bar is narrower than
    /// a readable column. A card never exceeds the display, for the same reason the bar never does —
    /// and here the display wins over the column, because a card too narrow to read still beats one
    /// whose right edge is off the screen.
    static func resultWidth(barWidth: CGFloat, in screen: InvocationScreen) -> CGFloat {
        let usable = max(0, screen.frame.width - margin * 2)
        return min(max(barWidth, minimumReadingWidth), usable)
    }

    /// The width the panel needs for a bar whose row is pinned at `pinned`.
    ///
    /// The row is drawn at the width the bar had while it was the only thing in the panel, and the
    /// panel is centred on the display, so the catalog's first pill lands on the same screen point
    /// no matter what the panel became. The controls a later state adds — pin, collapse, close —
    /// therefore spill to the right of that row, and the panel has to be wide enough to hold the
    /// spill rather than squeezing it.
    ///
    /// The room the spill needs is **twice** the row's growth, not the growth itself: the panel is
    /// centred, so every point added to its width lands half on the left of the row, where nothing is
    /// drawn, and half on the right, where the spill is. `pinned` of zero means the bar was never
    /// measured, and then the row is simply as wide as it is.
    static func vesselWidth(row: CGFloat, pinned: CGFloat, in screen: InvocationScreen) -> CGFloat {
        let usable = max(0, screen.frame.width - margin * 2)
        let spill = pinned > 0 ? 2 * row - pinned : row
        return min(max(spill, row), usable)
    }

    /// Where the pinned row starts on screen.
    ///
    /// Stated rather than left to the view's own centring, because every state's placement rests on
    /// it: a panel centred on the display holds a row of the bar's own width at the bar's own left
    /// edge, so widening the panel moves the glass and not the text.
    static func pinnedRowFrame(in panelFrame: CGRect, pinned: CGFloat) -> CGRect {
        CGRect(
            x: panelFrame.midX - pinned / 2, y: panelFrame.minY,
            width: pinned, height: panelFrame.height)
    }

    /// A card's frame: hung from the same top edge the bar hangs from, and placed horizontally the
    /// same way. Keeping the bar's left edge instead would slide a wider card off centre, because the
    /// bar is centred on its display and a card is wider than it.
    static func expandedFrame(
        keepingTopEdgeOf anchor: CGRect, size: CGSize, in screen: InvocationScreen
    ) -> CGRect {
        CGRect(
            x: anchoredX(in: screen, width: size.width),
            y: anchor.maxY - size.height,
            width: size.width,
            height: size.height)
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
