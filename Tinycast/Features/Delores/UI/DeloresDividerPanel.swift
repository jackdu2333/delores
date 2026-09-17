import AppKit

final class DeloresDividerPanel: NSPanel {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private let seam = DeloresDividerView()

    /// Derived into `dividerHoverTolerance`, so the two cannot drift apart: a tolerance wider than
    /// the band would leave the pointer outside the panel while still wanting it shown, which is
    /// exactly how an overlay learns to flicker at its own edge.
    static let width: CGFloat = 100

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .floating; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false; canHide = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        seam.owner = self
        seam.autoresizingMask = [.width, .height]
        contentView = seam
    }

    override var canBecomeKey: Bool { true }

    func show(x: CGFloat, y: CGFloat, height: CGFloat) {
        let width = Self.width
        setFrame(
            CGRect(x: floor(x - width / 2), y: y, width: width, height: max(30, height)),
            display: true)
        orderFrontRegardless()
        // Reported the moment the band appears. Without it the grip stays invisible until the
        // pointer happens to move again, which reads as the whole seam being dead.
        seam.checkInitialHover()
    }

    func hide() {
        seam.resetState()
        orderOut(nil)
    }

    func updateRatio(left: Int, right: Int) { seam.showRatio(left: left, right: right) }
    func hideRatio() { seam.hideRatio() }
}

/// What the seam is made of.
///
/// Everything here sits at zero opacity until the pointer arrives, because most of the time nobody
/// is resizing anything and there should be nothing on the screen to say otherwise. The three parts
/// answer three questions in the order a reader asks them: *is there a seam here* (the guide track,
/// dissolving at both ends so it reads as belonging to what is behind it), *can I take hold of it*
/// (the grip capsule), and *what am I about to get* (the ratio badge, live while dragging).
final class DeloresDividerView: NSView {
    weak var owner: DeloresDividerPanel?

    private static let trackWidth: CGFloat = 1.5
    private static let handleWidth: CGFloat = 24
    private static let handleHeight: CGFloat = 36
    private static let handleCornerRadius: CGFloat = 12
    private static let badgeWidth: CGFloat = 72
    private static let badgeHeight: CGFloat = 24

    private let guideTrackLayer = CAGradientLayer()
    private let gripHandleLayer = CALayer()
    private let leftBarLayer = CALayer()
    private let rightBarLayer = CALayer()
    private let ratioBadgeLayer = CALayer()
    private let ratioTextLayer = CATextLayer()

    private var isHovered = false
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        guideTrackLayer.cornerRadius = 0.75
        guideTrackLayer.startPoint = CGPoint(x: 0.5, y: 0)
        guideTrackLayer.endPoint = CGPoint(x: 0.5, y: 1)
        guideTrackLayer.locations = [0, 0.08, 0.5, 0.92, 1]
        guideTrackLayer.shadowColor = NSColor.black.cgColor
        guideTrackLayer.shadowOpacity = 0.15
        guideTrackLayer.shadowOffset = .zero
        guideTrackLayer.shadowRadius = 1.5
        guideTrackLayer.opacity = 0
        layer?.addSublayer(guideTrackLayer)

        gripHandleLayer.cornerRadius = Self.handleCornerRadius
        gripHandleLayer.borderWidth = 0.75
        gripHandleLayer.shadowColor = NSColor.black.cgColor
        gripHandleLayer.shadowOpacity = 0.20
        gripHandleLayer.shadowOffset = CGSize(width: 0, height: 2)
        gripHandleLayer.shadowRadius = 8
        gripHandleLayer.opacity = 0
        gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        layer?.addSublayer(gripHandleLayer)

        leftBarLayer.cornerRadius = 1
        gripHandleLayer.addSublayer(leftBarLayer)
        rightBarLayer.cornerRadius = 1
        gripHandleLayer.addSublayer(rightBarLayer)

        ratioBadgeLayer.cornerRadius = 12
        ratioBadgeLayer.backgroundColor = NSColor(white: 0.12, alpha: 0.75).cgColor
        ratioBadgeLayer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        ratioBadgeLayer.borderWidth = 0.75
        ratioBadgeLayer.shadowColor = NSColor.black.cgColor
        ratioBadgeLayer.shadowOpacity = 0.22
        ratioBadgeLayer.shadowOffset = CGSize(width: 0, height: 2)
        ratioBadgeLayer.shadowRadius = 6
        ratioBadgeLayer.opacity = 0

        ratioTextLayer.fontSize = 11.5
        ratioTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        ratioTextLayer.foregroundColor = NSColor.white.cgColor
        ratioTextLayer.alignmentMode = .center
        ratioTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        ratioBadgeLayer.addSublayer(ratioTextLayer)

        layer?.addSublayer(ratioBadgeLayer)

        updateVisualStyles()
    }

    private func updateVisualStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guideTrackLayer.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor(white: 1, alpha: isDark ? 0.25 : 0.22).cgColor,
            NSColor(white: 1, alpha: isDark ? 0.38 : 0.35).cgColor,
            NSColor(white: 1, alpha: isDark ? 0.25 : 0.22).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        gripHandleLayer.backgroundColor = NSColor(
            white: isDark ? 0.22 : 1, alpha: isDark ? 0.72 : 0.76).cgColor
        gripHandleLayer.borderColor = NSColor.white.withAlphaComponent(0.65).cgColor
        // Read against the grip, so they invert with it: light bars on the dark grip, dark on light.
        let bar = NSColor(white: isDark ? 0.88 : 0.28, alpha: isDark ? 0.85 : 0.75).cgColor
        leftBarLayer.backgroundColor = bar
        rightBarLayer.backgroundColor = bar
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualStyles()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutSublayers()
        CATransaction.commit()
    }

    private func layoutSublayers() {
        let trackX = round((bounds.width - Self.trackWidth) / 2)
        let insetY: CGFloat = 4
        guideTrackLayer.frame = CGRect(
            x: trackX, y: insetY,
            width: Self.trackWidth, height: max(0, bounds.height - insetY * 2))

        let handleX = round((bounds.width - Self.handleWidth) / 2)
        let handleY = round((bounds.height - Self.handleHeight) / 2)
        gripHandleLayer.frame = CGRect(
            x: handleX, y: handleY, width: Self.handleWidth, height: Self.handleHeight)

        // The two bars that say "this one moves sideways": 2pt wide, 12pt tall, 3pt apart.
        let barWidth: CGFloat = 2
        let barHeight: CGFloat = 12
        let barSpacing: CGFloat = 3
        let startBarX = round((Self.handleWidth - (barWidth * 2 + barSpacing)) / 2)
        let barY = round((Self.handleHeight - barHeight) / 2)
        leftBarLayer.frame = CGRect(x: startBarX, y: barY, width: barWidth, height: barHeight)
        rightBarLayer.frame = CGRect(
            x: startBarX + barWidth + barSpacing, y: barY, width: barWidth, height: barHeight)

        // Above the grip by preference, below it when there is no room above — it must never be
        // clipped, and the panel is exactly as tall as the seam it sits on.
        let badgeX = round((bounds.width - Self.badgeWidth) / 2)
        let above = handleY + Self.handleHeight + 8
        let badgeY =
            above + Self.badgeHeight <= bounds.height - 4
            ? above
            : max(4, handleY - Self.badgeHeight - 8)
        ratioBadgeLayer.frame = CGRect(
            x: badgeX, y: badgeY, width: Self.badgeWidth, height: Self.badgeHeight)
        ratioTextLayer.frame = CGRect(
            x: 0, y: 4, width: Self.badgeWidth, height: Self.badgeHeight - 8)
    }

    /// The grip's rectangle, grown a little — a target the size of the drawing itself is small enough
    /// that taking hold of it feels like aiming.
    private var handleRect: CGRect {
        let x = round((bounds.width - Self.handleWidth) / 2)
        let y = round((bounds.height - Self.handleHeight) / 2)
        return CGRect(x: x, y: y, width: Self.handleWidth, height: Self.handleHeight)
            .insetBy(dx: -4, dy: -4)
    }

    // MARK: Taking or passing the pointer

    /// Whether this point belongs to the seam. The narrow strip either side catches a pointer that
    /// has not reached the grip yet, so approaching it from the side works as well as landing on it.
    private func isPointInHoverZone(_ point: NSPoint) -> Bool {
        abs(point.x - bounds.width / 2) <= 6 || handleRect.contains(point)
    }

    /// A slightly-wider grip is a fairer target than the drawing.
    ///
    /// Returning `nil` is what makes the hundred-point band free: the pointer goes to whichever
    /// window is underneath, so the seam can be wide without being in the way. During a drag it takes
    /// everything instead, because letting one go mid-gesture would drop the drag.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isDragging { return self }
        return isPointInHoverZone(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways,
                          .inVisibleRect],
                owner: self, userInfo: nil))
    }

    /// Only once the grip is actually visible. A resize cursor over nothing would announce a seam
    /// that, from the reader's side, has not appeared.
    override func resetCursorRects() {
        super.resetCursorRects()
        if isHovered { addCursorRect(handleRect, cursor: .resizeLeftRight) }
    }

    override func cursorUpdate(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if isPointInHoverZone(localPoint) { NSCursor.resizeLeftRight.set() }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if isPointInHoverZone(convert(event.locationInWindow, from: nil)) { setHovered(true) }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let inZone = isPointInHoverZone(convert(event.locationInWindow, from: nil))
        if inZone && !isHovered {
            setHovered(true)
        } else if !inZone && isHovered && !isDragging {
            setHovered(false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if !isDragging && isHovered { setHovered(false) }
    }

    /// Whether the pointer is already on the seam when the band appears, which it is whenever the
    /// reader has driven the pointer *to* the seam rather than past it.
    func checkInitialHover() {
        guard let window, window.frame.contains(NSEvent.mouseLocation) else { return }
        // Twice translated: screen to the window, then the window to this view, whose bounds are
        // what `handleRect` is written against. Spelled out rather than nested, because Swift reads
        // `convert(_:from:)` against both points and rectangles and picks the rectangle.
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPoint = convert(windowPoint, from: nil)
        if isPointInHoverZone(localPoint) { setHovered(true) }
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        window?.invalidateCursorRects(for: self)
        animateHoverState(hovered: hovered)
    }

    private func animateHoverState(hovered: Bool) {
        CATransaction.begin()
        if hovered {
            CATransaction.setAnimationDuration(0.20)
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1))
            guideTrackLayer.opacity = 1
            gripHandleLayer.opacity = 1
            gripHandleLayer.transform = CATransform3DIdentity
        } else {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            guideTrackLayer.opacity = 0
            gripHandleLayer.opacity = 0
            gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        }
        CATransaction.commit()
    }

    // MARK: The ratio badge

    func showRatio(left: Int, right: Int) {
        ratioTextLayer.string = "\(left)% : \(right)%"
        guard ratioBadgeLayer.opacity < 0.1 else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        ratioBadgeLayer.opacity = 1
        CATransaction.commit()
    }

    func hideRatio() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        ratioBadgeLayer.opacity = 0
        CATransaction.commit()
    }

    // MARK: Gestures

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            springPulse()
            owner?.onDoubleClick?()
            return
        }
        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        owner?.onMouseDown?(dragStartMouseLocation)
        // Taken hold of: a small swell, answered by an equally small settle on release.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        gripHandleLayer.transform = CATransform3DMakeScale(1.06, 1.06, 1)
        CATransaction.commit()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        owner?.onMouseDragged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        owner?.onMouseUp?()
        hideRatio()
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.14)
        gripHandleLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    private func springPulse() {
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1, 0.88, 1.12, 1]
        pulse.keyTimes = [0, 0.35, 0.70, 1]
        pulse.duration = 0.20
        gripHandleLayer.add(pulse, forKey: "doubleClickPulse")
    }

    func resetState() {
        isHovered = false
        isDragging = false
        window?.invalidateCursorRects(for: self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideTrackLayer.opacity = 0
        gripHandleLayer.opacity = 0
        gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1)
        ratioBadgeLayer.opacity = 0
        CATransaction.commit()
    }
}

