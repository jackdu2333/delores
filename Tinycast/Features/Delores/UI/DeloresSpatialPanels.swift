import AppKit
import QuartzCore
import SwiftUI

/// What a gesture can ask the body to do. Standing still is not one of them: that is `rest()`, and
/// the wander is what asks for it.
enum DeloresCompanionExpression { case glance, chat }

/// The body itself: one layer holding one decoded atlas, and a frame that is a rectangle into that one
/// image — which is why a pose costs a CGRect and neither a decode nor a rebuilt view tree.
final class DeloresCompanionBodyView: NSView {
    private static let breathKey = "breath"
    private static let reactionKey = "reaction"

    /// The one decoded sheet, loaded once for the life of the app. Every frame is a rectangle into it,
    /// so no pose ever decodes anything.
    private static let atlas: CGImage? = {
        guard let image = Bundle.main.image(forResource: "CompanionAtlas.generated") else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }()

    private let sprite = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Authored at 1x and scaled by the GPU, so nearest: linear turns every edge into a smear.
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        // A pose is a finished rectangle, and a step writes one twelve times a second. Core
        // Animation's implicit animation lasts a quarter of a second, so leaving it on would mean the
        // sheet is permanently caught between two cells — the art slides, which reads as a twitch.
        // The breathing loop is unaffected: an explicit animation does not go through `actions`.
        sprite.actions = [
            "contentsRect": NSNull(),
            "contents": NSNull(),
            "contentsScale": NSNull(),
            "position": NSNull(),
            "bounds": NSNull(),
        ]
        sprite.contents = Self.atlas
        sprite.contentsRect = DeloresCompanionAnimation.contentsRect(row: .idle, frame: 0)
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("DeloresCompanionBodyView is not made in a nib") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    /// Carried to another display, the art has to be told the new scale or it softens.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        sprite.contentsScale = window?.backingScaleFactor ?? 2
    }

    // MARK: - Poses

    /// Standing still and breathing. The loop is a Core Animation keyframe animation rather than a
    /// timer — the first ruling: a resting body does not wake the main thread.
    func rest() {
        guard sprite.animation(forKey: Self.breathKey) == nil else { return }
        sprite.removeAnimation(forKey: Self.reactionKey)
        sprite.contentsRect = DeloresCompanionAnimation.contentsRect(row: .idle, frame: 0)
        let breath = CAKeyframeAnimation(keyPath: "contentsRect")
        breath.values = [
            DeloresCompanionAnimation.contentsRect(row: .idle, frame: 0),
            DeloresCompanionAnimation.contentsRect(row: .idle, frame: 1),
        ]
        // Discrete, or Core Animation interpolates between two cells and draws the gap between them:
        // a rectangle that belongs to no frame.
        breath.calculationMode = .discrete
        breath.duration = DeloresCompanionAnimation.breathDuration
        breath.repeatCount = .infinity
        sprite.add(breath, forKey: Self.breathKey)
    }

    /// One step of a trip. The breath comes off first: while it is attached, writing `contentsRect`
    /// changes the model value and the screen keeps showing the animation's.
    func step(frame: Int, facing: DeloresCompanionFacing) {
        sprite.removeAnimation(forKey: Self.breathKey)
        sprite.removeAnimation(forKey: Self.reactionKey)
        sprite.contentsRect = DeloresCompanionAnimation.contentsRect(
            row: DeloresCompanionAnimation.row(isStrolling: true, isHeld: false, facing: facing),
            frame: frame)
    }

    /// A reaction, played and dropped back. The idle frame is written *first*, because it is the model
    /// value the layer returns to when a one-shot animation ends — which is how "played and dropped
    /// back" costs no timer to notice the end.
    func react(_ reaction: CompanionAtlas.Reaction) {
        sprite.removeAnimation(forKey: Self.breathKey)
        sprite.removeAnimation(forKey: Self.reactionKey)
        sprite.contentsRect = DeloresCompanionAnimation.contentsRect(row: .idle, frame: 0)
        let play = CAKeyframeAnimation(keyPath: "contentsRect")
        play.values = (0..<reaction.frameCount).map { frame in
            DeloresCompanionAnimation.contentsRect(row: .reaction, frame: reaction.rawValue + frame)
        }
        play.calculationMode = .discrete
        play.duration = DeloresCompanionAnimation.reactionDuration
        play.repeatCount = 2
        sprite.add(play, forKey: Self.reactionKey)
    }

    /// Nothing is watching any more, so nothing should still be running behind an ordered-out panel —
    /// a hidden window is not composited, but leaving the loop attached is a thing to explain later.
    func stop() {
        sprite.removeAllAnimations()
    }
}

final class DeloresCompanionPanel: NSPanel {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    private var down = CGPoint.zero
    private var dragged = false
    private var longPressTimer: Timer?
    private(set) var isCaptured = false
    private var body: DeloresCompanionBodyView!
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    private var size: DeloresCompanionShell.Size

    init(size: DeloresCompanionShell.Size) {
        self.size = size
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: size.side, height: size.side),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // `.statusBar`, not `.floating`: the body walks the menu bar, and anything below level 24 is
        // covered by it outright rather than drawn over it.
        isOpaque = false; backgroundColor = .clear; level = .statusBar; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true; isReleasedWhenClosed = false; canHide = false
        becomesKeyOnlyIfNeeded = true
        body = DeloresCompanionBodyView(
            frame: CGRect(origin: .zero, size: CGSize(width: size.side, height: size.side)))
        contentView = body
    }

    /// Never takes the keyboard away from the app being used; the panel only needs the pointer.
    override var canBecomeKey: Bool { true }

    func present(at center: CGPoint) { move(to: center); orderFrontRegardless() }
    /// Where the window goes for a body centred on `center`.
    ///
    /// Whole points, because the body is pixel art: an origin that is not on a whole point puts a
    /// fractional number of screen pixels under each authored pixel, and the art then shimmers as it
    /// moves — the same picture, drawn a little differently every frame.
    private func origin(for center: CGPoint) -> CGPoint {
        CGPoint(x: (center.x - size.radius).rounded(), y: (center.y - size.radius).rounded())
    }

    func move(to center: CGPoint) { setFrameOrigin(origin(for: center)) }

    /// Drawn at the other step without going anywhere: the body grows about the point it stands on,
    /// which is the point the reader aimed at.
    func applySize(_ next: DeloresCompanionShell.Size) {
        guard next != size else { return }
        size = next
        setFrame(
            CGRect(origin: origin(for: center), size: CGSize(width: next.side, height: next.side)),
            display: true)
    }
    func hide() { setCaptured(false); body.stop(); orderOut(nil); longPressTimer?.invalidate() }
    func setCaptured(_ captured: Bool) {
        isCaptured = captured
        ignoresMouseEvents = !captured
    }
    func play(_ expression: DeloresCompanionExpression) {
        switch expression {
        case .glance: body.react(.glance)
        case .chat: body.react(.chat)
        }
    }
    func showBubble() { play(.chat) }

    /// Standing still. A pose the wander drives, not a gesture: see `DeloresCompanionBodyView.rest`.
    func rest() { body.rest() }

    /// One step of a trip, which is the only pose that carries a direction.
    func step(frame: Int, facing: DeloresCompanionFacing) { body.step(frame: frame, facing: facing) }

    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation; dragged = false
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onLongPress?() }
        }
        if let longPressTimer { RunLoop.main.add(longPressTimer, forMode: .common) }
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        guard hypot(point.x - down.x, point.y - down.y) >= 4 else { return }
        dragged = true; longPressTimer?.invalidate(); move(to: point); onDrag?(point)
    }
    override func mouseUp(with event: NSEvent) {
        longPressTimer?.invalidate(); longPressTimer = nil
        guard !dragged else { dragged = false; onDragEnded?(NSEvent.mouseLocation); return }
        event.clickCount >= 2 ? onDoubleClick?() : onSingleClick?()
    }
}

enum DeloresSnapSlot {
    case left, right, mainWorkspace, sideWorkspace
    case leftThird, centerThird, rightThird
    case topLeft, topRight, bottomLeft, bottomRight

    /// Which side of the seam it shares with its neighbour, for pairing. The quarters and the centre
    /// third answer `false` because neither has one neighbour to pair with: a quarter is stacked, so
    /// its seam is horizontal and not something this divider resizes, and the centre third has
    /// something either side of it.
    var isLeftOfSeam: Bool {
        switch self {
        case .left, .mainWorkspace, .leftThird: return true
        case .right, .sideWorkspace, .rightThird: return false
        case .centerThird, .topLeft, .topRight, .bottomLeft, .bottomRight: return false
        }
    }

    func rect(in frame: CGRect) -> CGRect {
        let margin: CGFloat = 6
        let gap: CGFloat = 8
        let usableWidth = frame.width - margin * 2
        let usableHeight = frame.height - margin * 2
        let halfWidth = (usableWidth - gap) / 2
        let halfHeight = (usableHeight - gap) / 2
        switch self {
        case .left:
            return CGRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: halfWidth, height: usableHeight)
        case .right:
            return CGRect(x: frame.midX + gap / 2, y: frame.minY + margin,
                          width: halfWidth, height: usableHeight)
        case .mainWorkspace:
            let mainWidth = (usableWidth - gap) * 2 / 3
            return CGRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: mainWidth, height: usableHeight)
        case .sideWorkspace:
            let mainWidth = (usableWidth - gap) * 2 / 3
            let sideWidth = usableWidth - gap - mainWidth
            return CGRect(x: frame.maxX - margin - sideWidth, y: frame.minY + margin,
                          width: sideWidth, height: usableHeight)
        case .leftThird, .centerThird, .rightThird:
            let thirdWidth = (usableWidth - gap * 2) / 3
            let index: CGFloat = self == .leftThird ? 0 : (self == .centerThird ? 1 : 2)
            return CGRect(x: frame.minX + margin + index * (thirdWidth + gap),
                          y: frame.minY + margin, width: thirdWidth, height: usableHeight)
        case .topLeft:
            return CGRect(x: frame.minX + margin, y: frame.midY + gap / 2,
                          width: halfWidth, height: halfHeight)
        case .topRight:
            return CGRect(x: frame.midX + gap / 2, y: frame.midY + gap / 2,
                          width: halfWidth, height: halfHeight)
        case .bottomLeft:
            return CGRect(x: frame.minX + margin, y: frame.minY + margin,
                          width: halfWidth, height: halfHeight)
        case .bottomRight:
            return CGRect(x: frame.midX + gap / 2, y: frame.minY + margin,
                          width: halfWidth, height: halfHeight)
        }
    }
}

final class DeloresSnapIslandPanel: NSPanel {
    private(set) var layout: SnapIslandGeometry.Layout = .horizontal
    /// Where the island last settled, so a run already resting there is left alone.
    private var restingFrame: CGRect?
    private var activeScreen: NSScreen?
    private let hosting: NSHostingView<DeloresSnapIslandView>
    private let state = DeloresSnapIslandState()
    /// How far above its resting place the island starts, from the reference's own numbers.
    private static let enterSlide: CGFloat = 14
    private static let enterDuration: TimeInterval = 0.24

    init() {
        let hosting = NSHostingView(rootView: DeloresSnapIslandView(state: state))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: SnapIslandGeometry.size)
        self.hosting = hosting
        super.init(
            contentRect: CGRect(origin: .zero, size: SnapIslandGeometry.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .popUpMenu; ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hosting
    }
    override var canBecomeKey: Bool { false }
    /// The fallback with no Companion in sight: the island drops into place at the top centre of
    /// the display, on the reference's own numbers — 14pt over 240ms — and its contents come up on
    /// a spring inside that. Arriving is most of what makes it read as something that appeared
    /// *for this drag* rather than as a strip that had been sitting there.
    func showAtTopCenter(on screen: NSScreen) {
        let layout = SnapIslandGeometry.Layout.horizontal
        let width = layout.size.width
        let height = layout.size.height
        let resting = CGRect(
            x: round(screen.frame.midX - width / 2),
            y: max(screen.visibleFrame.maxY - height - 6, screen.frame.maxY - height - 8),
            width: width, height: height)
        flyIn(
            to: resting, layout: layout, screen: screen,
            from: CGVector(dx: 0, dy: Self.enterSlide))
    }

    /// Beside the body a window was brought to, with the island's long axis along the edge the body
    /// rides. The island comes in from the body's side rather than from above, which is what makes
    /// it read as having grown out of the body rather than dropped onto the edge.
    func showBesideBody(_ placement: DeloresCompanionShell.Placement, on screen: NSScreen) {
        let layout = SnapIslandGeometry.layout(forEdge: placement.edge)
        let slide = Self.enterSlide
        let from: CGVector
        switch placement.edge {
        case .top: from = CGVector(dx: 0, dy: slide)
        case .bottom: from = CGVector(dx: 0, dy: -slide)
        case .left: from = CGVector(dx: -slide, dy: 0)
        case .right: from = CGVector(dx: slide, dy: 0)
        }
        flyIn(to: placement.frame, layout: layout, screen: screen, from: from)
    }

    /// The one place an arrival is performed: laid out for the layout it lands in, put just off its
    /// resting place on the side it comes from, then settled onto it.
    ///
    /// A run already resting exactly there is not re-flown. Dragging near the top fires repeatedly,
    /// and restarting the animation on every frame would leave the island permanently mid-arrival.
    private func flyIn(
        to resting: CGRect,
        layout: SnapIslandGeometry.Layout,
        screen: NSScreen,
        from offset: CGVector
    ) {
        if isVisible, activeScreen?.frame == screen.frame, self.layout == layout,
            restingFrame == resting
        { return }
        activeScreen = screen
        self.layout = layout
        // A column is four outlines and nothing else, so the window must not add a ground of its
        // own: the panel's shadow is drawn around the window's rectangle, which fills the gaps
        // between the panes and reads as the very slab the outlines were meant to replace.
        hasShadow = layout == .horizontal
        restingFrame = resting
        hosting.rootView = DeloresSnapIslandView(state: state, layout: layout)
        hosting.frame = CGRect(origin: .zero, size: layout.size)
        let entered = resting.offsetBy(dx: offset.dx, dy: offset.dy)
        setFrame(entered, display: false)
        alphaValue = 0
        orderFrontRegardless()

        state.isAppearing = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            state.isAppearing = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.enterDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            animator().setFrame(resting, display: true)
            animator().alphaValue = 1
        }
    }
    func setHoveredSlot(_ slot: DeloresSnapSlot?) {
        guard state.hoveredSlot != slot else { return }
        state.hoveredSlot = slot
    }
    func hide() {
        ignoresMouseEvents = true
        state.hoveredSlot = nil
        orderOut(nil)
    }
    func slot(at point: CGPoint) -> DeloresSnapSlot? {
        guard activeScreen != nil, frame.contains(point) else { return nil }
        // The card rects are laid out from the island's top-left, which is where SwiftUI puts its
        // origin; the point arrives in screen coordinates, measured from the bottom. Flipping here
        // rather than in the geometry keeps `rect(for:)` a statement about the layout and leaves
        // the one place that knows about screen space to say so.
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        guard layout.bounds.contains(local) else { return nil }
        for card in SnapIslandGeometry.Card.allCases {
            let rect = layout.rect(for: card)
            guard rect.contains(local) else { continue }
            let ratio = (local.x - rect.minX) / rect.width
            switch card {
            case .halfSplit:
                return ratio <= 0.5 ? .left : .right
            case .mainSide:
                return ratio <= SnapIslandGeometry.mainSideSplitRatio ? .mainWorkspace : .sideWorkspace
            case .quarter:
                let isLeft = ratio <= 0.5
                let isTop = local.y >= rect.midY
                if isTop { return isLeft ? .topLeft : .topRight }
                return isLeft ? .bottomLeft : .bottomRight
            case .thirds:
                if ratio <= 1.0 / 3.0 { return .leftThird }
                if ratio <= 2.0 / 3.0 { return .centerThird }
                return .rightThird
            }
        }
        return nil
    }
}

struct SnapIslandGeometry {
    enum Card: CaseIterable {
        case halfSplit, mainSide, quarter, thirds

        var glyphSize: CGSize {
            switch self {
            case .halfSplit: return CGSize(width: 108, height: 64)
            case .mainSide:  return CGSize(width: 110, height: 64)
            case .quarter:   return CGSize(width: 106, height: 64)
            case .thirds:    return CGSize(width: 112, height: 64)
            }
        }
    }

    /// Which way the island lays its cards out: a horizontal island on a horizontal edge, a
    /// vertical one on a vertical edge. The cards themselves never rotate — a card's glyphs are
    /// drawn for the width the card has either way — only the row they stand in does.
    enum Layout {
        case horizontal, vertical

        var size: CGSize {
            switch self {
            case .horizontal: return SnapIslandGeometry.size
            case .vertical: return SnapIslandGeometry.verticalSize
            }
        }

        var bounds: CGRect { CGRect(origin: .zero, size: size) }

        func rect(for card: Card) -> CGRect {
            let index = CGFloat(Card.allCases.firstIndex(of: card) ?? 0)
            switch self {
            case .horizontal:
                return CGRect(
                    x: horizontalPadding + index * (cardWidth + gap), y: verticalPadding,
                    width: cardWidth, height: cardHeight)
            case .vertical:
                // No padding: a column is the panes themselves, so a pane's rect *is* its slice of
                // the island and the first one starts at the island's own edge.
                return CGRect(
                    x: 0, y: index * (cardHeight + gap),
                    width: cardWidth, height: cardHeight)
            }
        }
    }

    static let size = CGSize(width: 620, height: 88)
    /// The vertical island is the four panes and nothing else: no vessel around them, no padding, a
    /// pane's rect being its own slice of the column.
    ///
    /// There is no capsule around it on purpose. A capsule 340 tall has 82pt semicircular ends, and
    /// a pane is 140 wide — so the top and bottom panes were being cut down to a sliver of glass by
    /// the very shape that was supposed to be holding them. Where a column cannot be wrapped, the
    /// panes are the surface: each carries its own glass, and the island is however tall they are.
    static var verticalSize: CGSize {
        let count = CGFloat(Card.allCases.count)
        return CGSize(
            width: cardWidth,
            height: count * cardHeight + (count - 1) * gap)
    }
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let gap: CGFloat = 12
    static let cardWidth: CGFloat = 140
    static let cardHeight: CGFloat = 72
    static let bounds = CGRect(origin: .zero, size: size)
    static let quarterCenterY = verticalPadding + cardHeight / 2
    /// Matches the reference, where both were settled against rendered output: thick enough to see
    /// against its own pane, thin enough to read as an edge of it rather than a line on it.
    static let glyphDividerWidth: CGFloat = 1.4
    static let glyphCornerRadius: CGFloat = 4.5
    /// The corner of a pane carrying its own ground, which every pane does in a column.
    static let paneCornerRadius: CGFloat = 10

    static func rect(for card: Card) -> CGRect {
        Layout.horizontal.rect(for: card)
    }

    /// The layout an island takes beside a body standing on `edge` — the island's long axis
    /// follows the edge.
    static func layout(forEdge edge: DeloresCompanionEdge) -> Layout {
        edge == .left || edge == .right ? .vertical : .horizontal
    }

    static var mainSideSplitRatio: CGFloat {
        let glyphW = Card.mainSide.glyphSize.width
        let inset = (cardWidth - glyphW) / 2
        let available = glyphW - glyphDividerWidth
        let mainWidth = available * (2.0 / 3.0)
        return (inset + mainWidth + glyphDividerWidth / 2) / cardWidth
    }
}

/// The panels arrive rather than appear, which needs something observable to animate against —
/// the frame and the alpha are driven from AppKit, but the contents come up on their own curve.
final class DeloresSnapIslandState: ObservableObject {
    @Published var isAppearing = false
    @Published var hoveredSlot: DeloresSnapSlot? = nil
}

struct DeloresSnapIslandView: View {
    @ObservedObject var state: DeloresSnapIslandState
    var layout: SnapIslandGeometry.Layout = .horizontal
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                cards
                    .padding(.horizontal, SnapIslandGeometry.horizontalPadding)
                    .padding(.vertical, SnapIslandGeometry.verticalPadding)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .background(
                        DeloresVisualEffectView(material: .popover, blending: .behindWindow)
                            .clipShape(Capsule()))
            case .vertical:
                // The panes are the island: no vessel, no padding. See `verticalSize`.
                cards
                    .frame(width: layout.size.width, height: layout.size.height)
            }
        }
        .scaleEffect(state.isAppearing ? 1 : 0.96)
        .opacity(state.isAppearing ? 1 : 0)
    }

    /// The same four cards either way — a card's glyphs are drawn for its width, never rotated —
    /// only the row they stand in turns with the edge.
    @ViewBuilder
    private var cards: some View {
        switch layout {
        case .horizontal:
            HStack(spacing: SnapIslandGeometry.gap) { islandCards }
        case .vertical:
            VStack(spacing: SnapIslandGeometry.gap) { islandCards }
        }
    }

    @ViewBuilder
    private var islandCards: some View {
        card(.halfSplit)
        card(.mainSide)
        card(.quarter)
        card(.thirds)
    }

    /// A line that takes the light along its top edge and falls into shadow along its bottom.
    ///
    /// Ported from the reference's pane rim, whose comment is worth carrying: a stroke of one
    /// uniform colour around a card is exactly what makes that card read as *stroked* rather than as
    /// a pane of something. Every edge in these cards is this instead.
    private var paneRim: some ShapeStyle {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isDark ? 0.24 : 0.85), location: 0),
                .init(color: Color.black.opacity(isDark ? 0.05 : 0.06), location: 0.55),
                .init(color: Color.black.opacity(isDark ? 0.16 : 0.10), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// The middle stop on its own, for edges too short for the gradient to read along.
    private var paneMidTone: Color {
        Color.black.opacity(isDark ? 0.05 : 0.06)
    }

    @ViewBuilder
    private func highlightCell(_ slot: DeloresSnapSlot) -> some View {
        if state.hoveredSlot == slot {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.accentColor.opacity(isDark ? 0.35 : 0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(isDark ? 0.8 : 0.6), lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func card(_ card: SnapIslandGeometry.Card) -> some View {
        let geometry = SnapIslandGeometry.self
        let size = card.glyphSize
        ZStack {
            // Interactive slot highlights
            switch card {
            case .halfSplit:
                HStack(spacing: geometry.glyphDividerWidth) {
                    highlightCell(.left)
                    highlightCell(.right)
                }
                .padding(geometry.glyphDividerWidth)
            case .mainSide:
                let mainW = (size.width - geometry.glyphDividerWidth) * (2.0 / 3.0)
                HStack(spacing: geometry.glyphDividerWidth) {
                    highlightCell(.mainWorkspace).frame(width: mainW)
                    highlightCell(.sideWorkspace).frame(maxWidth: .infinity)
                }
                .padding(geometry.glyphDividerWidth)
            case .quarter:
                VStack(spacing: geometry.glyphDividerWidth) {
                    HStack(spacing: geometry.glyphDividerWidth) {
                        highlightCell(.topLeft)
                        highlightCell(.topRight)
                    }
                    HStack(spacing: geometry.glyphDividerWidth) {
                        highlightCell(.bottomLeft)
                        highlightCell(.bottomRight)
                    }
                }
                .padding(geometry.glyphDividerWidth)
            case .thirds:
                HStack(spacing: geometry.glyphDividerWidth) {
                    highlightCell(.leftThird)
                    highlightCell(.centerThird)
                    highlightCell(.rightThird)
                }
                .padding(geometry.glyphDividerWidth)
            }

            // Outer rim and inner dividers
            RoundedRectangle(cornerRadius: geometry.glyphCornerRadius, style: .continuous)
                .strokeBorder(paneRim, lineWidth: geometry.glyphDividerWidth)
            switch card {
            case .halfSplit:
                divider(.vertical)
            case .mainSide:
                HStack(spacing: 0) {
                    Color.clear.frame(width: (size.width - geometry.glyphDividerWidth) * (2.0 / 3.0))
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            case .quarter:
                VStack(spacing: 0) {
                    Color.clear.frame(maxHeight: .infinity)
                    divider(.horizontal)
                    Color.clear.frame(maxHeight: .infinity)
                }
                HStack(spacing: 0) {
                    Color.clear.frame(maxWidth: .infinity)
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            case .thirds:
                let colW = (size.width - geometry.glyphDividerWidth * 2) / 3.0
                HStack(spacing: 0) {
                    Color.clear.frame(width: colW)
                    divider(.vertical)
                    Color.clear.frame(width: colW)
                    divider(.vertical)
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(width: geometry.cardWidth, height: geometry.cardHeight)
        // A column has no vessel, so each pane carries its own ground. Glass on its own is not
        // enough there: over a bright window every edge in these cards is a pale line on pale, and
        // the panes are the only thing telling the reader where the window is about to land.
        .background(
            Group {
                if layout == .vertical {
                    DeloresVisualEffectView(material: .popover, blending: .behindWindow)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: geometry.paneCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(
                                cornerRadius: geometry.paneCornerRadius, style: .continuous)
                                .fill(
                                    Color(nsColor: .windowBackgroundColor)
                                        .opacity(isDark ? 0.34 : 0.44)))
                }
            })
    }

    @ViewBuilder
    private func divider(_ axis: Axis) -> some View {
        let thickness = SnapIslandGeometry.glyphDividerWidth
        switch axis {
        case .vertical:
            // Vertical, so light has somewhere to fall along it.
            Rectangle()
                .fill(paneRim)
                .frame(width: thickness)
        case .horizontal:
            // Seen edge-on: a single row of pixels has no room for a gradient to read, so the
            // middle stop is used flat. Grading it anyway would darken the whole line unevenly.
            Rectangle()
                .fill(paneMidTone)
                .frame(height: thickness)
        }
    }

    private enum Axis { case horizontal, vertical }
}

struct DeloresVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
