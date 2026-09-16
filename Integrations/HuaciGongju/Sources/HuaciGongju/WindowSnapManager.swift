//
//  WindowSnapManager.swift
//  HuaciGongju
//

import Cocoa
import ApplicationServices

public class WindowSnapManager {
    public static let shared = WindowSnapManager()

    /// AX 取焦窗口的时机。普通点击走 mouseDown，真正拖窗才走 mouseDragged。
    public enum MouseCapturePhase {
        case mouseDown
        case mouseDragged
    }

    private var mouseEventMonitor: Any?
    private var isMonitoring: Bool = false

    public private(set) var isDraggingWindow: Bool = false
    public private(set) var isIslandActive: Bool = false
    public private(set) var lastWindowDragEndTime: TimeInterval = 0

    /// 顶部边缘触发判定阈值（单位：pt）
    public static let topTriggerThreshold: CGFloat = 45.0
    /// 顶部边缘脱离/取消阈值（单位：pt，带有充分的滞后回差，避免反复闪烁）
    public static let topDismissThreshold: CGFloat = 85.0
    /// 顶部居中触发区宽度（单位：pt，对应 600pt 分屏岛面板外加左右各 30pt 缓冲容错区，避免全屏顶部栏误触菜单与状态栏托盘）
    public static let topCenterTriggerWidth: CGFloat = 660.0
    public static let centerTriggerWidth: CGFloat = topCenterTriggerWidth

    /// 判断最近是否刚发生过窗口拖动吸附（0.35s 窗口期内忽略选中文本检测，防止出现幽灵划词栏）
    public var didDragWindowRecently: Bool {
        return (Date().timeIntervalSince1970 - lastWindowDragEndTime) < 0.35
    }

    private var mouseDownLocation: NSPoint = .zero
    private var lastDragLocation: NSPoint = .zero
    private var targetWindowElement: AXUIElement?
    private var initialWindowPosition: CGPoint?
    private var targetApp: NSRunningApplication?
    private var currentHoveredSlot: SnapSlot?
    private var activeScreen: NSScreen?
    /// 按下时点在自己的浮层上：整段手势都不再走 AX / 吸附。
    private var ignoreCurrentGesture = false

    private init() {}

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        SelectionMonitor.shared.log("WindowSnapManager started. Snapping enabled: \(ConfigManager.shared.enableWindowSnapping)")

        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
        }
    }

    /// 停止监听：移除全局鼠标事件订阅，让功能彻底回到「零开销」待机状态。
    /// 与 `start()` 幂等配对，由配置开关驱动，可反复调用。
    public func stop() {
        // 无论此前是否在运行都执行清理（幂等），但只在「由运行转为停止」时记录日志，
        // 避免应用以「关闭」状态冷启动时输出无意义的 stopped 噪音。
        let wasMonitoring = isMonitoring
        if let m = mouseEventMonitor {
            NSEvent.removeMonitor(m)
            mouseEventMonitor = nil
        }
        isMonitoring = false
        // 关键：必须清空瞬态状态。`isDraggingWindow` 会被 SelectionMonitor 读取以抑制划词，
        // 若关闭功能时残留 true，划词功能将永久哑火。
        resetTransientState()
        if wasMonitoring {
            SelectionMonitor.shared.log("WindowSnapManager stopped")
        }
    }

    /// 彻底清空所有拖拽 / 吸附瞬态状态与浮层。
    /// 由 `handleMouseUp`（每次松手后）与 `stop()`（功能被关闭时）共同复用，
    /// 保证「松手」与「功能关闭」两条路径的状态清理清单永不脱节。
    func resetTransientState() {
        isDraggingWindow = false
        isIslandActive = false
        lastDragLocation = .zero
        targetWindowElement = nil
        initialWindowPosition = nil
        targetApp = nil
        currentHoveredSlot = nil
        activeScreen = nil
        ignoreCurrentGesture = false
        WindowSnapIslandPanel.safeShared?.hide()
        GhostPreviewPanel.safeShared?.hide()
    }

    private func handleMouseEvent(_ event: NSEvent) {
        let mouseLoc = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            handleMouseDown(at: mouseLoc)

        case .leftMouseDragged:
            handleMouseDragged(at: mouseLoc)

        case .leftMouseUp:
            handleMouseUp(at: mouseLoc)

        default:
            break
        }
    }

    private func handleMouseDown(at location: NSPoint) {
        mouseDownLocation = location
        lastDragLocation = location
        isDraggingWindow = false
        isIslandActive = false
        targetWindowElement = nil
        initialWindowPosition = nil
        targetApp = nil
        currentHoveredSlot = nil
        activeScreen = nil
        ignoreCurrentGesture = false

        guard ConfigManager.shared.enableWindowSnapping else { return }

        // 排除对本应用自身各面板与设置窗口的点击。整段手势都不再走 AX。
        if isClickOnSelf(at: location) {
            ignoreCurrentGesture = true
            return
        }

        // 普通点击绝不走 AX。跨进程取焦窗口只在真正拖出 20pt 之后发生。
    }

    private func captureFocusedWindow(for app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowVal: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowVal)

        // 若 FocusedWindow 未命中，备选查询 MainWindow
        if status != .success || windowVal == nil {
            status = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &windowVal)
        }

        // ⚠️ 跨进程 AX 返回值一律走 `as?`：类型不符合就当作这次没取到，绝不强转崩溃
        if status == .success, let windowElement = AXCast.element(windowVal) {
            var posVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posVal) == .success,
               let axPos = AXCast.axValue(posVal) {
                var pt = CGPoint.zero
                if AXValueGetValue(axPos, .cgPoint, &pt) {
                    self.targetWindowElement = windowElement
                    self.initialWindowPosition = pt
                    self.targetApp = app
                }
            }
        }
    }

    private func handleMouseDragged(at location: NSPoint) {
        guard ConfigManager.shared.enableWindowSnapping else { return }
        guard !ignoreCurrentGesture else { return }

        // 1. 过滤微小抖动
        let mouseDist = hypot(location.x - mouseDownLocation.x, location.y - mouseDownLocation.y)
        guard mouseDist >= 20.0 else { return }

        // 动态前台适配：拖出 20pt 后才第一次 AX；前台 PID 变了才重新取。
        if let frontApp = NSWorkspace.shared.frontmostApplication, !isSelfApplication(frontApp) {
            if Self.shouldAttemptAXCapture(
                phase: .mouseDragged,
                dragDistance: mouseDist,
                capturedPID: targetApp?.processIdentifier,
                frontPID: frontApp.processIdentifier
            ) {
                captureFocusedWindow(for: frontApp)
            }
        }

        guard let windowElement = targetWindowElement, let initPos = initialWindowPosition else { return }

        // 2. 查询目标窗口当前真实位移与上沿坐标
        var currentPt = CGPoint.zero
        var windowTopY: CGFloat? = nil

        var currentPosVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &currentPosVal) == .success,
           let axCurrentPos = AXCast.axValue(currentPosVal) {
            if AXValueGetValue(axCurrentPos, .cgPoint, &currentPt) {
                let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080.0
                windowTopY = primaryScreenHeight - currentPt.y
            }
        }

        if !isDraggingWindow {
            let winDist = hypot(currentPt.x - initPos.x, currentPt.y - initPos.y)
            // 窗口必须产生了真实的物理位移 (>= 20pt)，严格将窗口拖拽与普通划选彻底解耦
            guard winDist >= 20.0 else { return }
            isDraggingWindow = true
            SelectionMonitor.shared.log("Window drag detected: [\(targetApp?.localizedName ?? "")] dist=\(winDist)")
        }

        let screen = resolveScreen(for: location)

        // 3. 控制分屏岛显示与隐藏生命周期：仅贴顶激活，向下拉回时平滑隐退
        let curDeltaY = (lastDragLocation == .zero) ? (location.y - mouseDownLocation.y) : (location.y - lastDragLocation.y)
        lastDragLocation = location

        if !isIslandActive {
            // 未激活状态下：必须贴近屏幕顶部才唤出分屏岛（普通桌面挪动绝不触发）
            if Self.isNearScreenTop(
                cursorLocation: location,
                screen: screen,
                windowTopY: windowTopY,
                triggerThreshold: Self.topTriggerThreshold,
                mouseDownLocation: mouseDownLocation,
                currentDeltaY: curDeltaY
            ) {
                isIslandActive = true
                activeScreen = screen
                WindowSnapIslandPanel.shared.show(on: screen)
                SelectionMonitor.shared.log("Window dragged to top edge, showing island: [\(targetApp?.localizedName ?? "")]")
            }
        } else {
            // 已激活状态下：检测用户是否向下拉回窗口（放弃分屏意图）
            let islandFrame = WindowSnapIslandPanel.safeShared?.frame ?? .zero
            if Self.shouldDismissTopIsland(
                cursorLocation: location,
                screen: screen,
                islandFrame: islandFrame,
                windowTopY: windowTopY
            ) {
                isIslandActive = false
                currentHoveredSlot = nil
                WindowSnapIslandPanel.safeShared?.hide()
                GhostPreviewPanel.safeShared?.hide()
                SelectionMonitor.shared.log("Window dragged away from top edge, hiding island")
            }
        }

        // 4. 当分屏岛处于激活状态时，处理多显示器漫游及卡片悬停反馈
        if isIslandActive {
            // 支持多显示器动态漫游：随光标移动实时迁移控制岛与预览线框至所在屏幕
            let currentScreen = resolveScreen(for: location)
            if activeScreen?.frame != currentScreen.frame {
                activeScreen = currentScreen
                WindowSnapIslandPanel.shared.show(on: currentScreen)
            }

            let s = currentScreen
            let slot = WindowSnapIslandPanel.safeShared?.slot(at: location)

            if slot != currentHoveredSlot {
                currentHoveredSlot = slot
                WindowSnapIslandPanel.safeShared?.setHoveredSlot(slot)

                if let currentSlot = slot {
                    let targetRect = SnapSlot.targetRect(for: currentSlot, in: s.visibleFrame)
                    GhostPreviewPanel.shared.show(targetRect: targetRect, slot: currentSlot, on: s)
                } else {
                    GhostPreviewPanel.safeShared?.hide()
                }
            }
        }
    }

    private func handleMouseUp(at location: NSPoint) {
        defer {
            // 无论此前是否处于拖动状态，鼠标松开时必定彻底清空所有内部暂存引用，杜绝状态残留
            resetTransientState()
        }

        if isDraggingWindow {
            lastWindowDragEndTime = Date().timeIntervalSince1970

            if isIslandActive {
                // 严格卡片内外部感应边界：松开鼠标时，只有光标严格落在卡片内部时才执行分屏；在卡片外部绝不分屏
                let hoveredSlot = WindowSnapIslandPanel.safeShared?.slot(at: location)
                let isInsideIsland = hoveredSlot != nil
                let slotToSnap = isInsideIsland ? (hoveredSlot ?? currentHoveredSlot) : nil

                if let slot = slotToSnap, let windowElement = targetWindowElement {
                    let screen = activeScreen ?? resolveScreen(for: location)
                    let targetRect = SnapSlot.targetRect(for: slot, in: screen.visibleFrame)
                    snapWindow(windowElement, to: targetRect)
                    SplitDividerManager.shared.registerSnappedWindow(
                        element: windowElement,
                        slot: slot,
                        rect: targetRect,
                        screen: screen
                    )
                } else if targetWindowElement != nil {
                    SplitDividerManager.shared.validateOrRefreshActivePair()
                }
            } else {
                // 普通拖窗结束：这是「几何可能变了」最可靠的离散信号。
                // SplitDivider 自己猜 leftMouseUp 永远收不到（它没订这个事件）。
                SplitDividerManager.shared.windowGeometryDidChange(at: location)
            }
        }
    }

    /// 决策表：什么时候才值得付一次跨进程 AX。
    /// mouseDown / 位移不足 20pt → 否；已捕获且 PID 没变 → 否；真正拖动或前台变了 → 是。
    public static func shouldAttemptAXCapture(
        phase: MouseCapturePhase,
        dragDistance: CGFloat,
        capturedPID: pid_t? = nil,
        frontPID: pid_t? = nil
    ) -> Bool {
        guard phase == .mouseDragged else { return false }
        guard dragDistance >= 20.0 else { return false }
        if let captured = capturedPID, let front = frontPID, captured == front {
            return false
        }
        return true
    }

    /// 测试缝：直接驱动松手路径，不必伪造全局 NSEvent。
    func handleMouseUpForTesting(at location: NSPoint, wasDraggingWindow: Bool) {
        isDraggingWindow = wasDraggingWindow
        handleMouseUp(at: location)
    }

    /// 判断光标或窗口上沿是否贴近屏幕顶端触发区（仅在当前屏幕顶栏中间区域激活，避免全屏顶栏误触左侧应用菜单和右侧状态栏托盘）
    public static func isNearScreenTop(
        cursorLocation: NSPoint,
        screen: NSScreen,
        windowTopY: CGFloat?,
        triggerThreshold: CGFloat = topTriggerThreshold,
        centerTriggerWidth: CGFloat = topCenterTriggerWidth,
        mouseDownLocation: NSPoint? = nil,
        currentDeltaY: CGFloat? = nil
    ) -> Bool {
        return isNearScreenTop(
            cursorLocation: cursorLocation,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            windowTopY: windowTopY,
            triggerThreshold: triggerThreshold,
            centerTriggerWidth: centerTriggerWidth,
            mouseDownLocation: mouseDownLocation,
            currentDeltaY: currentDeltaY
        )
    }

    /// 支持传入屏幕与可见区矩形的重载，便于单元测试及多屏虚拟布局计算
    public static func isNearScreenTop(
        cursorLocation: NSPoint,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        windowTopY: CGFloat?,
        triggerThreshold: CGFloat = topTriggerThreshold,
        centerTriggerWidth: CGFloat = topCenterTriggerWidth,
        mouseDownLocation: NSPoint? = nil,
        currentDeltaY: CGFloat? = nil
    ) -> Bool {
        let netDeltaX = mouseDownLocation.map { cursorLocation.x - $0.x }
        let netDeltaY = mouseDownLocation.map { cursorLocation.y - $0.y }
        return isNearScreenTop(
            cursorX: cursorLocation.x,
            cursorY: cursorLocation.y,
            screenMidX: screenFrame.midX,
            visibleTopY: visibleFrame.maxY,
            physicalTopY: screenFrame.maxY,
            windowTopY: windowTopY,
            triggerThreshold: triggerThreshold,
            centerTriggerWidth: centerTriggerWidth,
            netDeltaX: netDeltaX,
            netDeltaY: netDeltaY,
            currentDeltaY: currentDeltaY
        )
    }

    /// 纯 Y 轴及位移检测重载（向下兼容仅测试垂直阈值的老调用方）
    public static func isNearScreenTop(
        cursorY: CGFloat,
        visibleTopY: CGFloat,
        physicalTopY: CGFloat,
        windowTopY: CGFloat?,
        triggerThreshold: CGFloat = topTriggerThreshold,
        netDeltaX: CGFloat? = nil,
        netDeltaY: CGFloat? = nil,
        currentDeltaY: CGFloat? = nil
    ) -> Bool {
        return isNearScreenTop(
            cursorX: nil,
            cursorY: cursorY,
            screenMidX: nil,
            visibleTopY: visibleTopY,
            physicalTopY: physicalTopY,
            windowTopY: windowTopY,
            triggerThreshold: triggerThreshold,
            centerTriggerWidth: topCenterTriggerWidth,
            netDeltaX: netDeltaX,
            netDeltaY: netDeltaY,
            currentDeltaY: currentDeltaY
        )
    }

    /// 全维度（X 居中 + Y 贴顶 + 拖拽方向）检测核心实现
    public static func isNearScreenTop(
        cursorX: CGFloat?,
        cursorY: CGFloat,
        screenMidX: CGFloat?,
        visibleTopY: CGFloat,
        physicalTopY: CGFloat,
        windowTopY: CGFloat?,
        triggerThreshold: CGFloat = topTriggerThreshold,
        centerTriggerWidth: CGFloat = topCenterTriggerWidth,
        netDeltaX: CGFloat? = nil,
        netDeltaY: CGFloat? = nil,
        currentDeltaY: CGFloat? = nil
    ) -> Bool {
        // 1. 水平居中触发判定：若提供了 X 坐标与屏幕中点，仅在顶部中间区域（默认 660pt 宽）触发
        // 当拖拽靠近左上角（苹果菜单/应用菜单）或右上角（状态栏控制中心/托盘图标）时，绝不触发分屏岛！
        if let cX = cursorX, let mX = screenMidX {
            let halfWidth = centerTriggerWidth / 2.0
            let minTriggerX = mX - halfWidth
            let maxTriggerX = mX + halfWidth
            if cX < minTriggerX || cX > maxTriggerX {
                return false
            }
        }

        // 2. 若提供了拖动位移上下文，排查非贴顶意图：
        if let netY = netDeltaY {
            // A. 向下拖拽：用户正将窗口拉离屏幕顶部，绝对不触发分屏岛
            if netY < -8.0 {
                return false
            }

            // B. 桌面水平平移：水平位移显著但垂直偏移极小，且光标未直接推入顶部边缘（菜单栏/最上沿）
            if let netX = netDeltaX {
                let isHorizontalMove = abs(netY) <= 15.0 && abs(netX) >= 20.0
                let isPushedIntoTopEdge = cursorY >= (visibleTopY - 4.0) || cursorY >= (physicalTopY - 4.0)
                if isHorizontalMove && !isPushedIntoTopEdge {
                    return false
                }
            }
        }

        // C. 瞬时向下拖动判定：若当前正往下拉，不激活
        if let curDY = currentDeltaY, curDY < -4.0 {
            return false
        }

        // 3. 空间垂直位置阈值判定：
        // 光标是否贴近顶部触发区（可见区上沿或物理屏幕上沿）
        let isCursorNearTop = cursorY >= (visibleTopY - triggerThreshold) || cursorY >= (physicalTopY - triggerThreshold)

        // 窗口上沿是否贴紧屏幕顶端
        let isWindowNearTop: Bool
        if let topY = windowTopY {
            let windowTouchesTop = topY >= (visibleTopY - 6.0) || topY >= (physicalTopY - 6.0)
            // 窗口贴顶时，光标也必须处于屏幕上方合理标题栏区域（距顶端不超过 75pt），防止下半区普通拖窗误触
            let cursorInTopHalf = cursorY >= (visibleTopY - 75.0) || cursorY >= (physicalTopY - 75.0)
            isWindowNearTop = windowTouchesTop && cursorInTopHalf
        } else {
            isWindowNearTop = false
        }

        return isCursorNearTop || isWindowNearTop
    }

    /// 判断是否应当收回分屏岛（当用户将窗口从顶部向下拉离触发区，放弃分屏意图时）
    public static func shouldDismissTopIsland(
        cursorLocation: NSPoint,
        screen: NSScreen,
        islandFrame: NSRect,
        windowTopY: CGFloat?,
        dismissThreshold: CGFloat = topDismissThreshold
    ) -> Bool {
        return shouldDismissTopIsland(
            cursorLocation: cursorLocation,
            visibleTopY: screen.visibleFrame.maxY,
            physicalTopY: screen.frame.maxY,
            islandFrame: islandFrame,
            windowTopY: windowTopY,
            dismissThreshold: dismissThreshold
        )
    }

    public static func shouldDismissTopIsland(
        cursorLocation: NSPoint,
        visibleTopY: CGFloat,
        physicalTopY: CGFloat,
        islandFrame: NSRect,
        windowTopY: CGFloat?,
        dismissThreshold: CGFloat = topDismissThreshold
    ) -> Bool {
        // 1. 若光标落在分屏岛面板内部（用户正在卡片上悬停选择），绝不收回
        if islandFrame.contains(cursorLocation) {
            return false
        }

        // 2. 若光标依然位于顶部触发区或菜单栏区域内，暂不收回
        if cursorLocation.y >= (visibleTopY - 55.0) || cursorLocation.y >= (physicalTopY - 55.0) {
            // 但是，如果光标横向移动超出了居中触发区（如拉到左侧苹果菜单或右侧控制中心），则同样收回
            let horizontalDist = abs(cursorLocation.x - islandFrame.midX)
            if islandFrame.width > 0 && horizontalDist > (WindowSnapManager.topCenterTriggerWidth / 2.0) {
                return true
            }
            return false
        }

        // 3. 用户已将光标拉到分屏岛下方，且超出回差阈值，判定为放弃分屏，平滑收回
        let isBelowIsland = islandFrame.height > 0 ? (cursorLocation.y < (islandFrame.minY - 12.0)) : false
        let isBelowTopZone = cursorLocation.y < (visibleTopY - dismissThreshold)

        if isBelowIsland || isBelowTopZone {
            // 若窗口上沿依然紧密贴在屏幕顶端，且光标并未明显远离（在容忍范围内），暂不收回以防抖动；
            // 但若光标已经显著拉离顶端（例如低于 visibleTopY - dismissThreshold - 25），即使窗口位置因 AX 延迟未及时刷新也必须收回
            if let topY = windowTopY, (topY >= visibleTopY - 20.0 || topY >= physicalTopY - 20.0) {
                if cursorLocation.y < (visibleTopY - dismissThreshold - 25.0) {
                    return true
                }
                return false
            }
            return true
        }

        return false
    }

    /// 应用分屏矩形：通过 AXUIElementSetAttributeValue 设定目标窗口的坐标与尺寸
    public func snapWindow(_ windowElement: AXUIElement, to targetRect: NSRect) {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        WindowSnapManager.setWindowFrame(element: windowElement, rect: targetRect, primaryScreenHeight: primaryScreenHeight)
        SelectionMonitor.shared.log("Snapped window to \(targetRect)")
    }

    /// 设置窗口在 Accessibility/Quartz 坐标系中的坐标与尺寸
    public static func setWindowFrame(element: AXUIElement, rect: NSRect, primaryScreenHeight: CGFloat) {
        let (axPos, axSize) = WindowSnapManager.convertCocoaRectToAX(cocoaRect: rect, primaryScreenHeight: primaryScreenHeight)

        var point = axPos
        var size = axSize

        guard let posVal = AXValueCreate(.cgPoint, &point),
              let sizeVal = AXValueCreate(.cgSize, &size) else { return }

        // 经典三连调用：Size -> Pos -> Size（保障对窗口最小/最大尺寸约束的完全贴合）
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
    }

    /// 获取窗口在 Cocoa 坐标系中的矩形坐标
    public static func getWindowFrame(element: AXUIElement, primaryScreenHeight: CGFloat) -> NSRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let axPos = AXCast.axValue(posVal), let axSize = AXCast.axValue(sizeVal) else {
            return nil
        }
        var pt = CGPoint.zero
        var sz = CGSize.zero
        guard AXValueGetValue(axPos, .cgPoint, &pt),
              AXValueGetValue(axSize, .cgSize, &sz) else {
            return nil
        }
        let cocoaY = primaryScreenHeight - (pt.y + sz.height)
        return NSRect(x: pt.x, y: cocoaY, width: sz.width, height: sz.height)
    }

    /// 将 Cocoa 坐标系（左下角原点，Y轴向上）转换为 Accessibility/Quartz 坐标系（左上角原点，Y轴向下）
    public static func convertCocoaRectToAX(cocoaRect: NSRect, primaryScreenHeight: CGFloat) -> (position: CGPoint, size: CGSize) {
        let axX = cocoaRect.minX
        let axY = primaryScreenHeight - cocoaRect.maxY
        let axWidth = cocoaRect.width
        let axHeight = cocoaRect.height
        return (CGPoint(x: axX, y: axY), CGSize(width: axWidth, height: axHeight))
    }

    public func resolveScreen(for point: NSPoint) -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func isSelfApplication(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return true
        }
        if let bundleId = app.bundleIdentifier {
            if bundleId == "com.jackdu.huacigongju" || bundleId == Bundle.main.bundleIdentifier {
                return true
            }
        }
        return false
    }

    func isClickOnSelf(at point: NSPoint) -> Bool {
        // ⚠️ 同理于 SelectionMonitor：`isMaterialized` / `safeShared` 短路在前，
        // 别让「拖窗口 / 鼠标点击」顺手把任何面板实体化（面板是这个进程最大的一笔常驻开销）。
        if let bar = TransientCommandBarPanel.safeShared, bar.isVisible, bar.frame.contains(point) {
            return true
        }
        if let island = WindowSnapIslandPanel.safeShared, island.isVisible, island.frame.contains(point) {
            return true
        }
        if let ghost = GhostPreviewPanel.safeShared, ghost.isVisible, ghost.frame.contains(point) {
            return true
        }
        if let divider = SplitDividerOverlayPanel.safeShared, divider.isVisible, divider.frame.contains(point) {
            return true
        }
        if let pet = CompanionPetPanel.safeShared, pet.isVisible, pet.frame.contains(point) {
            return true
        }
        if let bubble = CompanionChatBubblePanel.safeShared, bubble.isVisible, bubble.frame.contains(point) {
            return true
        }
        if let app = NSApp {
            for window in app.windows where window.isVisible {
                if window.frame.contains(point) {
                    return true
                }
            }
        }
        return false
    }
}
