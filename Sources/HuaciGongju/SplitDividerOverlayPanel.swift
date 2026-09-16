//
//  SplitDividerOverlayPanel.swift
//  HuaciGongju
//

import Cocoa

public class SplitDividerOverlayPanel: NSPanel {
    private static let storage = SplitDividerOverlayPanel()
    private static var hasMaterialized = false

    /// 面板是否已被实体化。**不会触发创建** —— 用于在不付出构造代价的前提下短路判断。
    public static var isMaterialized: Bool { hasMaterialized }

    public static var shared: SplitDividerOverlayPanel {
        hasMaterialized = true
        return storage
    }

    /// 若面板已实体化则返回实例，否则返回 nil，绝不触发构造
    public static var safeShared: SplitDividerOverlayPanel? {
        isMaterialized ? storage : nil
    }

    // 宽幅悬浮面板 (100pt)，给拖拽徽标、高斯阴影与实时比例指示留出充足渲染空间，杜绝边缘切角
    public static let panelWidth: CGFloat = 100.0

    private var dividerView: SplitDividerView?

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: SplitDividerOverlayPanel.panelWidth, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.canHide = false

        let view = SplitDividerView(frame: NSRect(x: 0, y: 0, width: SplitDividerOverlayPanel.panelWidth, height: 500))
        view.autoresizingMask = [.width, .height]
        self.contentView = view
        self.dividerView = view
    }

    public func updatePosition(dividerX: CGFloat, y: CGFloat, height: CGFloat) {
        let width = SplitDividerOverlayPanel.panelWidth
        let newRect = NSRect(
            x: floor(dividerX - width / 2.0),
            y: y,
            width: width,
            height: max(30.0, height)
        )
        if self.frame != newRect {
            self.setFrame(newRect, display: true)
            if let cv = self.contentView {
                self.invalidateCursorRects(for: cv)
            }
        }
    }

    public func show(dividerX: CGFloat, y: CGFloat, height: CGFloat) {
        guard ConfigManager.shared.enableSplitDivider else { return }
        updatePosition(dividerX: dividerX, y: y, height: height)
        self.orderFront(nil)
        checkInitialHover()
    }

    public func hide() {
        dividerView?.resetState()
        self.orderOut(nil)
    }

    public func checkInitialHover() {
        let mouseLoc = NSEvent.mouseLocation
        if self.frame.contains(mouseLoc) {
            let localPoint = dividerView?.convert(self.convertPoint(fromScreen: mouseLoc), from: nil) ?? .zero
            if dividerView?.isPointInHoverZone(localPoint) == true {
                dividerView?.setHovered(true)
            }
        }
    }

    public func updateRatio(leftPercent: Int, rightPercent: Int) {
        dividerView?.showRatio(left: leftPercent, right: rightPercent)
    }

    public func hideRatio() {
        dividerView?.hideRatio()
    }
}

public class SplitDividerView: NSView {
    public static let defaultTrackWidth: CGFloat = 1.5
    public static let handleWidth: CGFloat = 24.0
    public static let handleHeight: CGFloat = 36.0
    public static let handleCornerRadius: CGFloat = 12.0

    // 居中垂直渐变导轨线 (两端自然消融，默认隐藏，鼠标移到间距时显现)
    private let guideTrackLayer = CAGradientLayer()
    // 呼吸间距上的悬浮 Liquid Glass 胶囊拖拽徽标 (24 x 36pt，圆角 12pt)
    private let gripHandleLayer = CALayer()
    // 徽标内 || 拖拽图标竖线 (精致双竖条)
    private let leftBarLayer = CALayer()
    private let rightBarLayer = CALayer()
    // 拖拽时动态浮现的 Liquid Glass 比例指示徽标 (72 x 24pt 半透明药丸)
    private let ratioBadgeLayer = CALayer()
    private let ratioTextLayer = CATextLayer()

    public private(set) var isHovered: Bool = false
    public private(set) var isDragging: Bool = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var trackingArea: NSTrackingArea?

    public var guideTrackWidth: CGFloat {
        return guideTrackLayer.frame.width
    }
    public var gripHandleFrame: CGRect {
        return gripHandleLayer.frame
    }
    public var ratioBadgeFrame: CGRect {
        return ratioBadgeLayer.frame
    }
    public var guideTrackGradientColors: [Any]? {
        return guideTrackLayer.colors
    }
    public var gripHandleCornerRadius: CGFloat {
        return gripHandleLayer.cornerRadius
    }
    public var gripHandleBorderWidth: CGFloat {
        return gripHandleLayer.borderWidth
    }

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

        // 1. 导轨层：CAGradientLayer 垂直渐变，两端自然消融，默认完全隐藏 (0.0)
        guideTrackLayer.cornerRadius = 0.75
        guideTrackLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        guideTrackLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        guideTrackLayer.locations = [0.0, 0.08, 0.5, 0.92, 1.0]
        guideTrackLayer.shadowColor = NSColor.black.cgColor
        guideTrackLayer.shadowOpacity = 0.15
        guideTrackLayer.shadowOffset = .zero
        guideTrackLayer.shadowRadius = 1.5
        guideTrackLayer.opacity = 0.0
        layer?.addSublayer(guideTrackLayer)

        // 2. 中央 Liquid Glass 悬浮胶囊抓手 (24 x 36pt，圆角 12pt，内置 || 图标，默认微缩 0.92 隐藏)
        gripHandleLayer.cornerRadius = SplitDividerView.handleCornerRadius
        gripHandleLayer.borderWidth = 0.75
        gripHandleLayer.shadowColor = NSColor.black.cgColor
        gripHandleLayer.shadowOpacity = 0.20
        gripHandleLayer.shadowOffset = CGSize(width: 0, height: 2)
        gripHandleLayer.shadowRadius = 8.0
        gripHandleLayer.opacity = 0.0
        gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1.0)
        layer?.addSublayer(gripHandleLayer)

        // 2.1 抓手内两道精致竖向拖拽条 (|| 拖拽图标，对称居中)
        leftBarLayer.cornerRadius = 1.0
        gripHandleLayer.addSublayer(leftBarLayer)

        rightBarLayer.cornerRadius = 1.0
        gripHandleLayer.addSublayer(rightBarLayer)

        // 3. 实时比例徽标浮层 (72 x 24pt Liquid Glass 半透明药丸，悬浮于抓手上方)
        ratioBadgeLayer.cornerRadius = 12.0
        ratioBadgeLayer.backgroundColor = NSColor(white: 0.12, alpha: 0.75).cgColor
        ratioBadgeLayer.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        ratioBadgeLayer.borderWidth = 0.75
        ratioBadgeLayer.shadowColor = NSColor.black.cgColor
        ratioBadgeLayer.shadowOpacity = 0.22
        ratioBadgeLayer.shadowOffset = CGSize(width: 0, height: 2)
        ratioBadgeLayer.shadowRadius = 6.0
        ratioBadgeLayer.opacity = 0.0

        ratioTextLayer.fontSize = 11.5
        ratioTextLayer.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        ratioTextLayer.foregroundColor = NSColor.white.cgColor
        ratioTextLayer.alignmentMode = .center
        ratioTextLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        ratioBadgeLayer.addSublayer(ratioTextLayer)

        layer?.addSublayer(ratioBadgeLayer)

        updateVisualStyles()
    }

    public func updateVisualStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDark {
            guideTrackLayer.colors = [
                NSColor.white.withAlphaComponent(0.0).cgColor,
                NSColor(white: 1.0, alpha: 0.25).cgColor,
                NSColor(white: 1.0, alpha: 0.38).cgColor,
                NSColor(white: 1.0, alpha: 0.25).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ]
            gripHandleLayer.backgroundColor = NSColor(white: 0.22, alpha: 0.72).cgColor
            gripHandleLayer.borderColor = NSColor.white.withAlphaComponent(0.65).cgColor
            leftBarLayer.backgroundColor = NSColor(white: 0.88, alpha: 0.85).cgColor
            rightBarLayer.backgroundColor = NSColor(white: 0.88, alpha: 0.85).cgColor
        } else {
            guideTrackLayer.colors = [
                NSColor.white.withAlphaComponent(0.0).cgColor,
                NSColor(white: 1.0, alpha: 0.22).cgColor,
                NSColor(white: 1.0, alpha: 0.35).cgColor,
                NSColor(white: 1.0, alpha: 0.22).cgColor,
                NSColor.white.withAlphaComponent(0.0).cgColor
            ]
            gripHandleLayer.backgroundColor = NSColor(white: 1.0, alpha: 0.76).cgColor
            gripHandleLayer.borderColor = NSColor.white.withAlphaComponent(0.65).cgColor
            leftBarLayer.backgroundColor = NSColor(white: 0.28, alpha: 0.75).cgColor
            rightBarLayer.backgroundColor = NSColor(white: 0.28, alpha: 0.75).cgColor
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualStyles()
    }

    override public func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // 导轨尺寸：居中 1.5pt 宽，贯穿窗口上下
        let trackWidth: CGFloat = SplitDividerView.defaultTrackWidth
        let trackX = round((bounds.width - trackWidth) / 2.0)
        let insetY: CGFloat = 4.0
        let trackHeight = max(0, bounds.height - insetY * 2)
        guideTrackLayer.frame = CGRect(x: trackX, y: insetY, width: trackWidth, height: trackHeight)

        // 胶囊抓手尺寸：居中 24 x 36pt 胶囊
        let handleWidth: CGFloat = SplitDividerView.handleWidth
        let handleHeight: CGFloat = SplitDividerView.handleHeight
        let handleX = round((bounds.width - handleWidth) / 2.0)
        let handleY = round((bounds.height - handleHeight) / 2.0)
        gripHandleLayer.frame = CGRect(x: handleX, y: handleY, width: handleWidth, height: handleHeight)

        // 内置两道竖条 (|| 图标) 居中：2pt宽，12pt高，间隙3pt
        let barWidth: CGFloat = 2.0
        let barHeight: CGFloat = 12.0
        let barSpacing: CGFloat = 3.0
        let totalBarsWidth = barWidth * 2.0 + barSpacing
        let startBarX = round((handleWidth - totalBarsWidth) / 2.0)
        let barY = round((handleHeight - barHeight) / 2.0)
        leftBarLayer.frame = CGRect(x: startBarX, y: barY, width: barWidth, height: barHeight)
        rightBarLayer.frame = CGRect(x: startBarX + barWidth + barSpacing, y: barY, width: barWidth, height: barHeight)

        // 比例 Badge 尺寸：宽 72pt，高 24pt，垂直悬浮于抓手正上方
        let badgeWidth: CGFloat = 72.0
        let badgeHeight: CGFloat = 24.0
        let badgeX = round((bounds.width - badgeWidth) / 2.0)
        let candidateBadgeY = handleY + handleHeight + 8.0
        let badgeY = (candidateBadgeY + badgeHeight <= bounds.height - 4.0) ? candidateBadgeY : max(4.0, handleY - badgeHeight - 8.0)
        ratioBadgeLayer.frame = CGRect(x: badgeX, y: badgeY, width: badgeWidth, height: badgeHeight)
        ratioTextLayer.frame = CGRect(x: 0, y: 4.0, width: badgeWidth, height: badgeHeight - 8.0)

        CATransaction.commit()
    }

    // MARK: - Precise Hit-Testing & Hover Zone

    /// 判断坐标是否落入呼吸间隙或拖拽图标热区（非热区范围点击穿透至底层应用，绝不阻碍用户正常操作）
    public func isPointInHoverZone(_ point: NSPoint) -> Bool {
        let centerX = bounds.width / 2.0
        let isOverGap = abs(point.x - centerX) <= 6.0
        let handleWidth: CGFloat = SplitDividerView.handleWidth
        let handleHeight: CGFloat = SplitDividerView.handleHeight
        let handleX = round((bounds.width - handleWidth) / 2.0)
        let handleY = round((bounds.height - handleHeight) / 2.0)
        let handleRect = CGRect(x: handleX, y: handleY, width: handleWidth, height: handleHeight)
        let isOverHandle = handleRect.insetBy(dx: -4.0, dy: -4.0).contains(point)
        return isOverGap || isOverHandle
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        // 拖拽过程中无条件锁定自身，确保手势平滑
        if isDragging { return self }
        // 仅在光标处于呼吸间距或手柄徽标内部时接管点击；其余区域完全穿透给两侧窗口
        if isPointInHoverZone(point) {
            return self
        }
        return nil
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .cursorUpdate,
            .activeAlways,
            .inVisibleRect
        ]
        let ta = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        // 仅在激活悬停显现时添加左右调整光标，隐藏时不污染系统光标
        if isHovered {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }

    override public func cursorUpdate(with event: NSEvent) {
        if isHovered {
            NSCursor.resizeLeftRight.set()
        }
    }

    public func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        self.window?.invalidateCursorRects(for: self)
        animateHoverState(hovered: hovered)
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        let localPoint = convert(event.locationInWindow, from: nil)
        if isPointInHoverZone(localPoint) && !isHovered {
            setHovered(true)
        }
    }

    override public func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let localPoint = convert(event.locationInWindow, from: nil)
        let inZone = isPointInHoverZone(localPoint)
        if inZone && !isHovered {
            setHovered(true)
        } else if !inZone && isHovered && !isDragging {
            setHovered(false)
        }
    }

    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if !isDragging && isHovered {
            setHovered(false)
        }
    }

    private func animateHoverState(hovered: Bool) {
        CATransaction.begin()
        if hovered {
            CATransaction.setAnimationDuration(0.20)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0))
            guideTrackLayer.opacity = 1.0
            gripHandleLayer.opacity = 1.0
            gripHandleLayer.transform = CATransform3DIdentity
        } else {
            CATransaction.setAnimationDuration(0.18)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            guideTrackLayer.opacity = 0.0
            gripHandleLayer.opacity = 0.0
            gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1.0)
        }
        CATransaction.commit()
    }

    // MARK: - Ratio Badge Updates

    public func showRatio(left: Int, right: Int) {
        ratioTextLayer.string = "\(left)% : \(right)%"
        if ratioBadgeLayer.opacity < 0.1 {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.12)
            ratioBadgeLayer.opacity = 1.0
            CATransaction.commit()
        }
    }

    public func hideRatio() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        ratioBadgeLayer.opacity = 0.0
        CATransaction.commit()
    }

    // MARK: - Mouse Gestures

    override public func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // 双击弹簧回弹微动效 (Spring Pulse)
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [1.0, 0.88, 1.12, 1.0]
            pulse.keyTimes = [0.0, 0.35, 0.70, 1.0]
            pulse.duration = 0.20
            gripHandleLayer.add(pulse, forKey: "doubleClickPulse")

            SplitDividerManager.shared.resetToFiftyFifty()
            return
        }

        // 功能 1：按住中缝左右联动拖拽
        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        SplitDividerManager.shared.beginDrag(at: dragStartMouseLocation)

        // 拖拽手感反馈放大 (微量膨胀 1.06)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        gripHandleLayer.transform = CATransform3DMakeScale(1.06, 1.06, 1.0)
        CATransaction.commit()
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentMouseLoc = NSEvent.mouseLocation
        let deltaX = currentMouseLoc.x - dragStartMouseLocation.x
        SplitDividerManager.shared.jointResize(deltaX: deltaX)
    }

    override public func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            let currentMouseLoc = NSEvent.mouseLocation
            let deltaX = currentMouseLoc.x - dragStartMouseLocation.x
            SplitDividerManager.shared.endDrag(finalDeltaX: deltaX)
            hideRatio()

            let localPoint = convert(event.locationInWindow, from: nil)
            let inZone = isPointInHoverZone(localPoint)
            if !inZone && isHovered {
                setHovered(false)
            } else if isHovered {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.14)
                gripHandleLayer.transform = CATransform3DIdentity
                CATransaction.commit()
            }
        }
    }

    public func resetState() {
        isHovered = false
        isDragging = false
        self.window?.invalidateCursorRects(for: self)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideTrackLayer.opacity = 0.0
        gripHandleLayer.opacity = 0.0
        gripHandleLayer.transform = CATransform3DMakeScale(0.92, 0.92, 1.0)
        ratioBadgeLayer.opacity = 0.0
        CATransaction.commit()
    }
}


