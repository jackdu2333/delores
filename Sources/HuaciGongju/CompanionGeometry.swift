//
//  CompanionGeometry.swift
//  HuaciGongju
//
//  桌宠码头的几何真源。窗口仍各自独立，这里只负责「圆贴哪条边、壳往哪边长」。
//

import Cocoa

// MARK: - Edge

public enum CompanionEdge: String, CaseIterable, Equatable {
    case top
    case bottom
    case left
    case right
}

// MARK: - Interaction (pure, no AppKit)

public enum CompanionClickKind: Equatable {
    case single
    case double
    case longPress
}

public enum CompanionClickAction: Equatable {
    case expression
    case openBar
    case chatBubble
}

public enum CompanionSelectionResponse: Equatable {
    case glanceOnly
    case glanceAndBar
}

public enum CompanionInteraction {
    public static func action(for kind: CompanionClickKind, hasSelection: Bool) -> CompanionClickAction {
        switch kind {
        case .single:
            return .expression
        case .double:
            return hasSelection ? .openBar : .chatBubble
        case .longPress:
            return .chatBubble
        }
    }

    public static func selectionResponse(autoShowToolbar: Bool) -> CompanionSelectionResponse {
        autoShowToolbar ? .glanceAndBar : .glanceOnly
    }

    public static func allowsGhostSnap(companionEnabled: Bool, snapEnabled: Bool) -> Bool {
        !companionEnabled && snapEnabled
    }

    public static func allowsGhostDivider(companionEnabled: Bool, dividerEnabled: Bool) -> Bool {
        !companionEnabled && dividerEnabled
    }
}

// MARK: - Geometry

public struct CompanionGeometry {

    /// 看见的玻璃圆直径
    public static let visibleSize: CGFloat = 28
    /// 接手后的热区边长（圆仍画 28，窗口按 44 吃点击）
    public static let hitSize: CGFloat = 44
    /// 壳体与圆之间的缝
    public static let shellGap: CGFloat = 8
    /// 闲逛匀速。落在 24...36 约定区间中位。
    public static let patrolSpeed: CGFloat = 30
    /// 同屏出岛光环半径。落在 80...120 约定区间中位。
    public static let haloRadius: CGFloat = 100
    /// 热区停稳多久才接手
    public static let dwellDuration: TimeInterval = 0.25
    /// 离开热区多久再走
    public static let leaveDuration: TimeInterval = 0.9
    /// 划词看过来之后，自动出条再等这么久
    public static let autoBarDelay: TimeInterval = 0.15
    /// 长按判定
    public static let longPressDuration: TimeInterval = 0.5

    public static var visibleRadius: CGFloat { visibleSize / 2 }
    public static var hitRadius: CGFloat { hitSize / 2 }

    /// 左右边竖岛：图元不缩，条目改竖排。
    ///
    /// 宽 = 横岛一条目宽 + 左右内边距 = 140 + 12×2 = 164
    /// 高 = 四条目高 + 三条间距 + 上下内边距 = 72×4 + 12×3 + 8×2 = 340
    public static var verticalIslandSize: CGSize {
        let cardCount = CGFloat(SnapIslandGeometry.Card.allCases.count)
        let width = SnapIslandGeometry.horizontalPadding * 2 + SnapIslandGeometry.Card.itemWidth
        let height = SnapIslandGeometry.verticalPadding * 2
            + SnapIslandGeometry.cardHeight * cardCount
            + SnapIslandGeometry.interItemSpacing * max(0, cardCount - 1)
        return CGSize(width: width, height: height)
    }

    public static var landscapeIslandSize: CGSize { SnapIslandGeometry.panelSize }

    public static func islandSize(for edge: CompanionEdge) -> CGSize {
        switch edge {
        case .top, .bottom: return landscapeIslandSize
        case .left, .right: return verticalIslandSize
        }
    }

    public static func circleFrame(center: CGPoint) -> NSRect {
        NSRect(
            x: center.x - visibleRadius,
            y: center.y - visibleRadius,
            width: visibleSize,
            height: visibleSize
        )
    }

    public static func hitFrame(center: CGPoint) -> NSRect {
        NSRect(
            x: center.x - hitRadius,
            y: center.y - hitRadius,
            width: hitSize,
            height: hitSize
        )
    }

    public static func panelFrame(center: CGPoint) -> NSRect {
        hitFrame(center: center)
    }

    // MARK: Spawn / snap

    /// 出生在可视区域右缘中部，圆的右缘贴齐可视右缘。
    public static func spawnCenter(in visibleFrame: NSRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.maxX - visibleRadius,
            y: visibleFrame.midY
        )
    }

    public static func nearestEdge(to point: CGPoint, in visibleFrame: NSRect) -> CompanionEdge {
        let distances: [(CompanionEdge, CGFloat)] = [
            (.right, abs(visibleFrame.maxX - point.x)),
            (.left, abs(point.x - visibleFrame.minX)),
            (.top, abs(visibleFrame.maxY - point.y)),
            (.bottom, abs(point.y - visibleFrame.minY))
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .right
    }

    /// 把点吸到指定边，圆心夹在四角内侧，保证 28pt 圆不探出可视区域。
    public static func snapCenter(_ point: CGPoint, to edge: CompanionEdge, in visibleFrame: NSRect) -> CGPoint {
        let minX = visibleFrame.minX + visibleRadius
        let maxX = visibleFrame.maxX - visibleRadius
        let minY = visibleFrame.minY + visibleRadius
        let maxY = visibleFrame.maxY - visibleRadius
        let x = min(max(point.x, minX), maxX)
        let y = min(max(point.y, minY), maxY)
        switch edge {
        case .right:  return CGPoint(x: maxX, y: y)
        case .left:   return CGPoint(x: minX, y: y)
        case .top:    return CGPoint(x: x, y: maxY)
        case .bottom: return CGPoint(x: x, y: minY)
        }
    }

    public static func snapToNearestEdge(_ point: CGPoint, in visibleFrame: NSRect) -> (center: CGPoint, edge: CompanionEdge) {
        let edge = nearestEdge(to: point, in: visibleFrame)
        return (snapCenter(point, to: edge, in: visibleFrame), edge)
    }

    // MARK: Halo / jump

    public static func isInHalo(cursor: CGPoint, petCenter: CGPoint, radius: CGFloat = haloRadius) -> Bool {
        hypot(cursor.x - petCenter.x, cursor.y - petCenter.y) <= radius
    }

    /// 窗口中心必须先越屏，宠物才搬家。同屏对面边够不着就不出岛。
    public static func shouldJumpScreen(windowCenter: CGPoint, currentScreenFrame: NSRect) -> Bool {
        !currentScreenFrame.contains(windowCenter)
    }

    /// 拔屏：在剩余屏的所有边上，落到离原坐标最近的那条边。
    public static func relocateAfterUnplug(
        previousCenter: CGPoint,
        remainingVisibleFrames: [NSRect]
    ) -> (center: CGPoint, edge: CompanionEdge)? {
        guard !remainingVisibleFrames.isEmpty else { return nil }
        var best: (center: CGPoint, edge: CompanionEdge, distance: CGFloat)?
        for vf in remainingVisibleFrames {
            for edge in CompanionEdge.allCases {
                let center = snapCenter(previousCenter, to: edge, in: vf)
                let distance = hypot(center.x - previousCenter.x, center.y - previousCenter.y)
                if best == nil || distance < best!.distance {
                    best = (center, edge, distance)
                }
            }
        }
        guard let best else { return nil }
        return (best.center, best.edge)
    }

    // MARK: Patrol

    public struct PatrolState: Equatable {
        public var center: CGPoint
        public var edge: CompanionEdge

        public init(center: CGPoint, edge: CompanionEdge) {
            self.center = center
            self.edge = edge
        }
    }

    /// 沿可视四边顺时针匀速走，拐角不加速。
    public static func patrolStep(
        state: PatrolState,
        visibleFrame: NSRect,
        dt: TimeInterval,
        speed: CGFloat = patrolSpeed
    ) -> PatrolState {
        var remaining = max(0, speed * CGFloat(dt))
        var edge = state.edge
        var center = snapCenter(state.center, to: edge, in: visibleFrame)
        var guardCount = 0
        while remaining > 0.0001 && guardCount < 8 {
            guardCount += 1
            let target = clockwiseEnd(of: edge, in: visibleFrame)
            let dx = target.x - center.x
            let dy = target.y - center.y
            let dist = hypot(dx, dy)
            if dist <= remaining {
                remaining -= dist
                center = target
                edge = clockwiseNext(edge)
                center = snapCenter(center, to: edge, in: visibleFrame)
            } else {
                let t = remaining / dist
                center = CGPoint(x: center.x + dx * t, y: center.y + dy * t)
                remaining = 0
            }
        }
        return PatrolState(center: center, edge: edge)
    }

    public static func clockwiseNext(_ edge: CompanionEdge) -> CompanionEdge {
        switch edge {
        case .right: return .bottom
        case .bottom: return .left
        case .left: return .top
        case .top: return .right
        }
    }

    private static func clockwiseEnd(of edge: CompanionEdge, in visibleFrame: NSRect) -> CGPoint {
        let minX = visibleFrame.minX + visibleRadius
        let maxX = visibleFrame.maxX - visibleRadius
        let minY = visibleFrame.minY + visibleRadius
        let maxY = visibleFrame.maxY - visibleRadius
        switch edge {
        case .right:  return CGPoint(x: maxX, y: minY)
        case .bottom: return CGPoint(x: minX, y: minY)
        case .left:   return CGPoint(x: minX, y: maxY)
        case .top:    return CGPoint(x: maxX, y: maxY)
        }
    }

    // MARK: Inward shells

    public struct ShellPlacement: Equatable {
        public var petCenter: CGPoint
        public var edge: CompanionEdge
        public var frame: NSRect
    }

    /// 贴底边要出条：先滑到更近的那条竖边。
    public static func edgeForOpeningBar(
        current: CompanionEdge,
        petCenter: CGPoint,
        visibleFrame: NSRect
    ) -> CompanionEdge {
        guard current == .bottom else { return current }
        let distLeft = petCenter.x - visibleFrame.minX
        let distRight = visibleFrame.maxX - petCenter.x
        return distLeft <= distRight ? .left : .right
    }

    public static func planIslandOpening(
        petCenter: CGPoint,
        edge: CompanionEdge,
        visibleFrame: NSRect
    ) -> ShellPlacement {
        placeShell(
            petCenter: petCenter,
            edge: edge,
            shellSize: islandSize(for: edge),
            visibleFrame: visibleFrame,
            alignCenter: true
        )
    }

    public static func planBarOpening(
        petCenter: CGPoint,
        edge: CompanionEdge,
        barSize: CGSize,
        visibleFrame: NSRect
    ) -> ShellPlacement {
        let resolvedEdge = edgeForOpeningBar(current: edge, petCenter: petCenter, visibleFrame: visibleFrame)
        var center = petCenter
        if resolvedEdge != edge {
            center = snapCenter(petCenter, to: resolvedEdge, in: visibleFrame)
        }
        return placeShell(
            petCenter: center,
            edge: resolvedEdge,
            shellSize: barSize,
            visibleFrame: visibleFrame,
            alignCenter: true
        )
    }

    /// 展开态：胶囊仍与圆心同高，结果往下挂。空间不够时圆一起上滑。
    public static func planExpandedBarOpening(
        petCenter: CGPoint,
        edge: CompanionEdge,
        collapsedSize: CGSize,
        expandedSize: CGSize,
        visibleFrame: NSRect
    ) -> ShellPlacement {
        let resolvedEdge = edgeForOpeningBar(current: edge, petCenter: petCenter, visibleFrame: visibleFrame)
        var center = petCenter
        if resolvedEdge != edge {
            center = snapCenter(petCenter, to: resolvedEdge, in: visibleFrame)
        }
        var frame = hangDownFrame(
            petCenter: center,
            edge: resolvedEdge,
            collapsedSize: collapsedSize,
            expandedSize: expandedSize
        )
        if resolvedEdge == .left || resolvedEdge == .right {
            let overflowBottom = visibleFrame.minY - frame.minY
            if overflowBottom > 0 {
                center = snapCenter(
                    CGPoint(x: center.x, y: center.y + overflowBottom),
                    to: resolvedEdge,
                    in: visibleFrame
                )
                frame = hangDownFrame(
                    petCenter: center,
                    edge: resolvedEdge,
                    collapsedSize: collapsedSize,
                    expandedSize: expandedSize
                )
            }
        }
        frame = clamp(frame, to: visibleFrame)
        return ShellPlacement(petCenter: center, edge: resolvedEdge, frame: frame)
    }

    private static func hangDownFrame(
        petCenter: CGPoint,
        edge: CompanionEdge,
        collapsedSize: CGSize,
        expandedSize: CGSize
    ) -> NSRect {
        let pet = circleFrame(center: petCenter)
        let top = pet.midY + collapsedSize.height / 2
        let y = top - expandedSize.height
        switch edge {
        case .right:
            return NSRect(
                x: pet.minX - shellGap - expandedSize.width,
                y: y,
                width: expandedSize.width,
                height: expandedSize.height
            )
        case .left:
            return NSRect(
                x: pet.maxX + shellGap,
                y: y,
                width: expandedSize.width,
                height: expandedSize.height
            )
        case .top, .bottom:
            return inwardFrame(
                petVisible: pet,
                edge: edge,
                shellSize: expandedSize,
                alignCenter: true
            )
        }
    }

    /// 壳在圆朝里一侧，8pt 缝，圆留在壳外。空间不够时先沿当前边把圆滑开。
    public static func placeShell(
        petCenter: CGPoint,
        edge: CompanionEdge,
        shellSize: CGSize,
        visibleFrame: NSRect,
        alignCenter: Bool
    ) -> ShellPlacement {
        var center = snapCenter(petCenter, to: edge, in: visibleFrame)
        let pet = circleFrame(center: center)
        var frame = inwardFrame(petVisible: pet, edge: edge, shellSize: shellSize, alignCenter: alignCenter)

        switch edge {
        case .top, .bottom:
            let overflowLeft = visibleFrame.minX - frame.minX
            let overflowRight = frame.maxX - visibleFrame.maxX
            var shift: CGFloat = 0
            if overflowLeft > 0 { shift += overflowLeft }
            if overflowRight > 0 { shift -= overflowRight }
            if shift != 0 {
                center = snapCenter(CGPoint(x: center.x + shift, y: center.y), to: edge, in: visibleFrame)
                frame = inwardFrame(
                    petVisible: circleFrame(center: center),
                    edge: edge,
                    shellSize: shellSize,
                    alignCenter: alignCenter
                )
            }
        case .left, .right:
            let overflowBottom = visibleFrame.minY - frame.minY
            let overflowTop = frame.maxY - visibleFrame.maxY
            var shift: CGFloat = 0
            if overflowBottom > 0 { shift += overflowBottom }
            if overflowTop > 0 { shift -= overflowTop }
            if shift != 0 {
                center = snapCenter(CGPoint(x: center.x, y: center.y + shift), to: edge, in: visibleFrame)
                frame = inwardFrame(
                    petVisible: circleFrame(center: center),
                    edge: edge,
                    shellSize: shellSize,
                    alignCenter: alignCenter
                )
            }
        }

        frame = clamp(frame, to: visibleFrame)
        return ShellPlacement(petCenter: center, edge: edge, frame: frame)
    }

    /// 左右边：胶囊与圆心同高，整栋放到内侧。顶/底：壳与圆心水平居中。
    private static func inwardFrame(
        petVisible: NSRect,
        edge: CompanionEdge,
        shellSize: CGSize,
        alignCenter: Bool
    ) -> NSRect {
        switch edge {
        case .right:
            let x = petVisible.minX - shellGap - shellSize.width
            let y = alignCenter ? petVisible.midY - shellSize.height / 2 : petVisible.midY - shellSize.height / 2
            return NSRect(x: x, y: y, width: shellSize.width, height: shellSize.height)
        case .left:
            let x = petVisible.maxX + shellGap
            let y = petVisible.midY - shellSize.height / 2
            return NSRect(x: x, y: y, width: shellSize.width, height: shellSize.height)
        case .top:
            let x = petVisible.midX - shellSize.width / 2
            let y = petVisible.minY - shellGap - shellSize.height
            return NSRect(x: x, y: y, width: shellSize.width, height: shellSize.height)
        case .bottom:
            let x = petVisible.midX - shellSize.width / 2
            let y = petVisible.maxY + shellGap
            return NSRect(x: x, y: y, width: shellSize.width, height: shellSize.height)
        }
    }

    private static func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        var r = rect
        if r.width > bounds.width { r.size.width = bounds.width }
        if r.height > bounds.height { r.size.height = bounds.height }
        if r.minX < bounds.minX { r.origin.x = bounds.minX }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }
        if r.minY < bounds.minY { r.origin.y = bounds.minY }
        if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r
    }

    public static let chatBubbleSize = CGSize(width: 132, height: 32)

    public static func chatBubbleFrame(petCenter: CGPoint, edge: CompanionEdge) -> NSRect {
        let pet = circleFrame(center: petCenter)
        return inwardFrame(
            petVisible: pet,
            edge: edge,
            shellSize: chatBubbleSize,
            alignCenter: false
        )
    }
}
