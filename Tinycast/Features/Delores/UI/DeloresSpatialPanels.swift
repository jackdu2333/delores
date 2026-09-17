import AppKit
import SwiftUI

enum DeloresCompanionExpression { case idle, glance, chat }

final class DeloresCompanionPanel: NSPanel {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onLongPress: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    private var down = CGPoint.zero
    private var dragged = false
    private var longPressTimer: Timer?
    private(set) var isCaptured = false
    private var hosting: NSHostingView<DeloresCompanionView>!
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 44, height: 44),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .floating; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true; isReleasedWhenClosed = false; canHide = false
        becomesKeyOnlyIfNeeded = true
        hosting = NSHostingView(rootView: DeloresCompanionView())
        contentView = hosting
    }

    /// Never takes the keyboard away from the app being used; the panel only needs the pointer.
    override var canBecomeKey: Bool { true }

    func present(at center: CGPoint) { move(to: center); orderFrontRegardless() }
    func move(to center: CGPoint) { setFrameOrigin(CGPoint(x: center.x - 22, y: center.y - 22)) }
    func hide() { setCaptured(false); orderOut(nil); longPressTimer?.invalidate() }
    func setCaptured(_ captured: Bool) {
        isCaptured = captured
        ignoresMouseEvents = !captured
    }
    func play(_ expression: DeloresCompanionExpression) { hosting.rootView = DeloresCompanionView(expression: expression) }
    func showBubble() { play(.chat) }

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
        guard !dragged else { return }
        event.clickCount >= 2 ? onDoubleClick?() : onSingleClick?()
    }
}

struct DeloresCompanionView: View {
    var expression = DeloresCompanionExpression.idle
    private var symbol: String {
        switch expression { case .idle: return "sparkles"; case .glance: return "eye"; case .chat: return "bubble.left" }
    }
    var body: some View {
        ZStack {
            DeloresVisualEffectView(material: .popover, blending: .behindWindow).clipShape(Circle())
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        }
        .frame(width: 28, height: 28)
        .frame(width: 44, height: 44)
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
    private let islandSize = SnapIslandGeometry.size
    private var activeScreen: NSScreen?
    private let hosting: NSHostingView<DeloresSnapIslandView>
    private let state = DeloresSnapIslandState()
    /// How far above its resting place the island starts, from the reference's own numbers.
    private static let enterSlide: CGFloat = 14
    private static let enterDuration: TimeInterval = 0.24

    init() {
        let hosting = NSHostingView(rootView: DeloresSnapIslandView(state: state))
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: islandSize)
        self.hosting = hosting
        super.init(
            contentRect: CGRect(origin: .zero, size: islandSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; level = .popUpMenu; ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hosting
    }
    override var canBecomeKey: Bool { false }
    /// The island drops into place from just above where it will rest, on the reference's own
    /// numbers — 14pt over 240ms — and its contents come up on a spring inside that. Arriving is
    /// most of what makes it read as something that appeared *for this drag* rather than as a strip
    /// that had been sitting there.
    ///
    /// Already up on the same display is not re-flown. Dragging near the top fires repeatedly, and
    /// restarting the animation on every frame would leave the island permanently mid-arrival.
    func show(on screen: NSScreen) {
        if isVisible, activeScreen?.frame == screen.frame { return }
        activeScreen = screen
        let width = islandSize.width
        let height = islandSize.height
        let resting = CGRect(
            x: round(screen.frame.midX - width / 2),
            y: max(screen.visibleFrame.maxY - height - 6, screen.frame.maxY - height - 8),
            width: width, height: height)
        setFrame(resting.offsetBy(dx: 0, dy: Self.enterSlide), display: false)
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
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        guard SnapIslandGeometry.bounds.contains(local) else { return nil }
        for card in SnapIslandGeometry.Card.allCases {
            let rect = SnapIslandGeometry.rect(for: card)
            guard rect.contains(local) else { continue }
            let ratio = (local.x - rect.minX) / rect.width
            switch card {
            case .halfSplit:
                return ratio <= 0.5 ? .left : .right
            case .mainSide:
                return ratio <= SnapIslandGeometry.mainSideSplitRatio ? .mainWorkspace : .sideWorkspace
            case .quarter:
                let isLeft = ratio <= 0.5
                let isTop = local.y >= SnapIslandGeometry.quarterCenterY
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

    static let size = CGSize(width: 620, height: 88)
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

    static func rect(for card: Card) -> CGRect {
        let index = CGFloat(Card.allCases.firstIndex(of: card) ?? 0)
        return CGRect(
            x: horizontalPadding + index * (cardWidth + gap), y: verticalPadding,
            width: cardWidth, height: cardHeight)
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
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(spacing: SnapIslandGeometry.gap) {
            card(.halfSplit)
            card(.mainSide)
            card(.quarter)
            card(.thirds)
        }
        .padding(.horizontal, SnapIslandGeometry.horizontalPadding)
        .padding(.vertical, SnapIslandGeometry.verticalPadding)
        .frame(width: SnapIslandGeometry.size.width, height: SnapIslandGeometry.size.height)
        .background(
            DeloresVisualEffectView(material: .popover, blending: .behindWindow)
                .clipShape(Capsule()))
        .scaleEffect(state.isAppearing ? 1 : 0.96)
        .opacity(state.isAppearing ? 1 : 0)
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

enum DeloresCompanionEdge { case top, bottom, left, right }

/// The edge of `frame` the point is closest to. Ties go to the right edge, which is where the
