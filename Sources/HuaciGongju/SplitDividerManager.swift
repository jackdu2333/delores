//
//  SplitDividerManager.swift
//  HuaciGongju
//

import Cocoa
import ApplicationServices

public struct SplitWindowPair: Equatable {
    public var leftElement: AXUIElement
    public var rightElement: AXUIElement
    public var leftRect: NSRect
    public var rightRect: NSRect
    public var screen: NSScreen
    public var leftPid: pid_t
    public var rightPid: pid_t

    public var dividerX: CGFloat {
        return (leftRect.maxX + rightRect.minX) / 2.0
    }

    public var dividerY: CGFloat {
        return max(leftRect.minY, rightRect.minY)
    }

    public var dividerHeight: CGFloat {
        let maxY = min(leftRect.maxY, rightRect.maxY)
        return max(0.0, maxY - dividerY)
    }

    public init(
        leftElement: AXUIElement,
        rightElement: AXUIElement,
        leftRect: NSRect,
        rightRect: NSRect,
        screen: NSScreen,
        leftPid: pid_t = 0,
        rightPid: pid_t = 0
    ) {
        self.leftElement = leftElement
        self.rightElement = rightElement
        self.leftRect = leftRect
        self.rightRect = rightRect
        self.screen = screen
        if leftPid != 0 {
            self.leftPid = leftPid
        } else {
            var p: pid_t = 0
            AXUIElementGetPid(leftElement, &p)
            self.leftPid = p
        }
        if rightPid != 0 {
            self.rightPid = rightPid
        } else {
            var p: pid_t = 0
            AXUIElementGetPid(rightElement, &p)
            self.rightPid = p
        }
    }

    public static func == (lhs: SplitWindowPair, rhs: SplitWindowPair) -> Bool {
        return CFEqual(lhs.leftElement, rhs.leftElement) &&
               CFEqual(lhs.rightElement, rhs.rightElement) &&
               lhs.leftRect == rhs.leftRect &&
               lhs.rightRect == rhs.rightRect &&
               lhs.screen.displayID == rhs.screen.displayID &&
               lhs.leftPid == rhs.leftPid &&
               lhs.rightPid == rhs.rightPid
    }
}

public class SplitDividerManager {
    public static let shared = SplitDividerManager()

    public private(set) var activePair: SplitWindowPair?
    public private(set) var isDraggingDivider: Bool = false

    private var mouseEventMonitor: Any?
    private var isMonitoring: Bool = false

    private var dragStartLeftRect: NSRect = .zero
    private var dragStartRightRect: NSRect = .zero
    private var dragStartDividerX: CGFloat = 0.0
    private var lastAXResizeTime: TimeInterval = 0.0
    private var lastScanTime: TimeInterval = 0.0
    private var lastValidateTime: TimeInterval = 0.0
    /// 测试计数：`windowGeometryDidChange` 被真实拖窗结束通知的次数。
    public private(set) var geometryChangeNotificationCount: Int = 0

    // MARK: - 后台开销预算（事件驱动 + 缓存）
    //
    // **旧模型的问题**：mouseMoved → 每 0.25s 校验 / 每 0.5s 发现扫描。
    // 用户只是正常动一下鼠标，就会持续触发 `CGWindowList` + O(n³) 窗口配对 + AX IPC，
    // 而且**空闲时也在跑**。这是本工具后台能耗的主要来源。
    //
    // **新模型**：
    // - `mouseMoved` 只做 O(1)：与**缓存**下来的中缝几何做距离判断；
    // - 昂贵的全量扫描只在**离散事件**上发生：App 切换 / 启动 / 退出 / 隐藏、
    //   Space 切换、本工具吸附完成、以及**鼠标拖拽结束**（窗口刚被移动或改变大小）；
    // - 鼠标**没真正移动时一个字节的活都不干** —— 这是「空闲 CPU ≈ 0」的关键；
    // - 缓存几何的低频校验只做 2 次 AX 取 frame，不再碰 CGWindowList；
    // - 保留一个很慢的兜底发现扫描，防止「手动摆好窗口却没触发任何事件」的极端情况。
    private enum Polling {
        /// 缓存几何的校验间隔（2 次 AX 取 frame，无 CGWindowList）
        static let validateInterval: TimeInterval = 2.0
        /// 无活跃窗口对时的全量发现扫描兜底间隔（正常情况由离散事件触发，这只是保险）
        static let discoveryInterval: TimeInterval = 10.0
        /// 「换一条更近的缝」（三等分等布局）的全量搜索间隔，比校验更慢
        static let seamSearchInterval: TimeInterval = 5.0
        /// 鼠标位移小于此值视为「没动」，跳过一切计时工作
        static let mouseMoveEpsilon: CGFloat = 8.0
        /// 换缝搜索的额外门槛：鼠标离当前中缝超过这么远才值得去找别的缝
        static let seamSearchMinDistance: CGFloat = 80.0
    }

    /// 上一次处理过的鼠标位置 —— 用于判断「鼠标是否真的动了」
    private var lastMouseLocation: NSPoint = .zero
    private var lastSeamSearchTime: TimeInterval = 0.0

    private struct SnappedRecord {
        var element: AXUIElement
        var rect: NSRect
        var timestamp: TimeInterval
    }

    private var recentLeftSnapped: [CGDirectDisplayID: SnappedRecord] = [:]
    private var recentRightSnapped: [CGDirectDisplayID: SnappedRecord] = [:]

    private init() {}

    // MARK: - Lifecycle

    /// 启动监听：注册全局鼠标事件订阅与工作区通知。
    /// - Important: 本方法**只应在功能开启时调用**。因此启停由配置开关驱动（见 AppDelegate），
    ///   关闭功能时必须调用 `stop()`，而不是让回调自行 `guard` 配置。
    ///
    /// 订阅本身是廉价的：全局 `mouseMoved` 只在**鼠标真的移动了**且过了节流窗口时才干活，
    /// 昂贵的窗口全量扫描（CGWindowList + O(n³) 配对 + AX IPC）只在**离散事件**上发生
    /// （App 切换 / Space 切换 / 吸附完成 / 拖拽结束），空闲时开销为 0。
    /// 详见 `Polling`。
    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        SelectionMonitor.shared.log("SplitDividerManager started. Enabled: \(ConfigManager.shared.enableSplitDivider)")

        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.handleMouseMoved()
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            self,
            selector: #selector(handleAppActivation),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDeactivation),
            name: NSWorkspace.didHideApplicationNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleAppDeactivation),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        nc.addObserver(
            self,
            selector: #selector(handleSpaceChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    /// 停止监听：移除全局鼠标事件订阅与全部工作区通知观察者，并收起中缝浮层。
    /// 执行后本管理器不再接收任何系统事件，回到「零开销」待机状态。
    public func stop() {
        // 无论此前是否在运行都执行清理（幂等），但只在「由运行转为停止」时记录日志，
        // 避免应用以「关闭」状态冷启动时输出无意义的 stopped 噪音。
        let wasMonitoring = isMonitoring
        if let m = mouseEventMonitor {
            NSEvent.removeMonitor(m)
            mouseEventMonitor = nil
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isMonitoring = false
        clearActivePair()
        if wasMonitoring {
            SelectionMonitor.shared.log("SplitDividerManager stopped")
        }
    }

    @objc private func handleAppActivation(_ notification: Notification? = nil) {
        guard ConfigManager.shared.enableSplitDivider else { return }
        if let app = notification?.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            let pid = app.processIdentifier
            let selfPid = ProcessInfo.processInfo.processIdentifier
            if pid != selfPid, let pair = activePair {
                if pair.leftPid != pid && pair.rightPid != pid {
                    clearActivePair()
                    return
                }
            }
        }
        validateOrRefreshActivePair()

        // 切了 App 仍没有活跃对：这是最自然的「重新找一次」时机 ——
        // 离散事件上的一次扫描，而不是让 mouseMoved 一直轮询找。
        if activePair == nil {
            let loc = NSEvent.mouseLocation
            rescanAfterGeometryChange(on: WindowSnapManager.shared.resolveScreen(for: loc), near: loc)
        }
    }

    @objc private func handleAppDeactivation(_ notification: Notification? = nil) {
        guard ConfigManager.shared.enableSplitDivider else { return }
        validateOrRefreshActivePair()
    }

    @objc private func handleSpaceChange(_ notification: Notification? = nil) {
        guard ConfigManager.shared.enableSplitDivider else { return }
        clearActivePair()
        // 重置发现节流，让切换 Space 后的第一次鼠标移动就能在新 Space 上找一次
        lastScanTime = 0
        lastValidateTime = 0
    }

    private func handleMouseMoved() {
        guard ConfigManager.shared.enableSplitDivider else {
            if activePair != nil { clearActivePair() }
            return
        }

        // 窗口拖动中不干扰分屏岛
        if WindowSnapManager.shared.isDraggingWindow {
            if activePair != nil { clearActivePair() }
            return
        }

        // 正在拖拽中缝时不打断
        if isDraggingDivider { return }

        let mouseLoc = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let mouseScreen = WindowSnapManager.shared.resolveScreen(for: mouseLoc)

        // 窗口几何变化不再靠自己猜 leftMouseUp —— 那个事件根本没订阅。
        // 真实拖窗结束由 WindowSnapManager 显式调用 `windowGeometryDidChange`。

        // ② 鼠标没真正移动 → 一个字节的活都不干。
        //    这是「空闲时 CPU ≈ 0、无周期尖峰」的关键：
        //    用户离开鼠标后，不再有任何 CGWindowList / AX IPC。
        let moved = hypot(mouseLoc.x - lastMouseLocation.x, mouseLoc.y - lastMouseLocation.y)
        lastMouseLocation = mouseLoc
        guard moved > Polling.mouseMoveEpsilon else { return }

        if let pair = activePair {
            // O(1) 前台应用校验：只查 NSWorkspace，不涉及 IPC
            let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let selfPid = ProcessInfo.processInfo.processIdentifier
            if let front = frontPid, front != selfPid {
                if pair.leftPid != front && pair.rightPid != front {
                    clearActivePair()
                    return
                }
            } else if frontPid == nil {
                clearActivePair()
                return
            }

            if pair.screen.displayID == mouseScreen.displayID {
                // ③ 低频校验：刷新**缓存**几何（2 次 AX 取 frame，不碰 CGWindowList）
                guard now - lastValidateTime >= Polling.validateInterval else { return }
                lastValidateTime = now

                // 换缝搜索（三等分布局里鼠标横向移到另一条缝）：
                // 比校验更慢，且要求鼠标已明显离开当前中缝 —— 正常悬停时根本不触发。
                if now - lastSeamSearchTime >= Polling.seamSearchInterval,
                   abs(mouseLoc.x - pair.dividerX) > Polling.seamSearchMinDistance {
                    lastSeamSearchTime = now
                    if let closer = detectAdjacentPair(on: mouseScreen, near: mouseLoc),
                       abs(closer.dividerX - mouseLoc.x) < abs(pair.dividerX - mouseLoc.x) - 60.0 {
                        setActivePair(closer)
                        return
                    }
                }
                validateOrRefreshActivePair()
                return
            }

            // 换屏：清掉旧对，并让下面的发现分支立即在新屏上找
            lastScanTime = 0
            clearActivePair()
        }

        // ④ 无活跃窗口对：兜底发现扫描。
        //    正常路径是离散事件（App 切换 / 吸附完成 / 拖拽结束 / 换屏）立即发现，
        //    这里只是防止「手动摆好窗口后一直没触发任何事件」的极端情况。
        guard now - lastScanTime >= Polling.discoveryInterval else { return }
        lastScanTime = now
        if let pair = detectAdjacentPair(on: mouseScreen, near: mouseLoc) {
            setActivePair(pair)
        }
    }

    /// WindowSnap 在真实窗口拖动结束时调用。这是「几何可能变了」最可靠的离散信号。
    public func windowGeometryDidChange(at location: NSPoint) {
        guard ConfigManager.shared.enableSplitDivider else { return }
        geometryChangeNotificationCount += 1
        let screen = WindowSnapManager.shared.resolveScreen(for: location)
        let now = ProcessInfo.processInfo.systemUptime
        lastMouseLocation = location
        lastScanTime = now
        lastValidateTime = now
        rescanAfterGeometryChange(on: screen, near: location)
    }

    /// 几何可能已变化后的重算 —— **只在离散事件**（拖拽结束 / App 切换 / 吸附完成）调用，
    /// 绝不放在 mouseMoved 的周期路径上。
    private func rescanAfterGeometryChange(on screen: NSScreen, near point: NSPoint) {
        if activePair != nil {
            validateOrRefreshActivePair()
        }
        if activePair == nil, let pair = detectAdjacentPair(on: screen, near: point) {
            setActivePair(pair)
        }
    }

    // MARK: - Adjacency Detection & Math

    /// 判定两窗口是否并排横向贴合且满足尺寸约束
    /// - 横向相邻：abs(right.minX - left.maxX) <= 12pt
    /// - 纵向重叠：垂直方向高度重合度 >= 70%
    /// - 尺寸底线：高度 >= 300pt，单侧宽度 >= 250pt
    public static func areAdjacent(
        left: NSRect,
        right: NSRect,
        maxGap: CGFloat = 12.0,
        minOverlapRatio: CGFloat = 0.70,
        minHeight: CGFloat = 300.0,
        minWidth: CGFloat = 250.0
    ) -> Bool {
        // 左窗必须位于右窗左侧
        guard left.minX < right.minX else { return false }

        // 横向缝隙在允许阈值内
        let gap = right.minX - left.maxX
        guard abs(gap) <= maxGap else { return false }

        // 基础尺寸保护
        guard left.height >= minHeight && right.height >= minHeight else { return false }
        guard left.width >= minWidth && right.width >= minWidth else { return false }

        // 纵向重叠度计算
        let overlapMinY = max(left.minY, right.minY)
        let overlapMaxY = min(left.maxY, right.maxY)
        let overlapHeight = max(0.0, overlapMaxY - overlapMinY)
        let shortestHeight = min(left.height, right.height)
        guard shortestHeight > 0.0 else { return false }

        let overlapRatio = overlapHeight / shortestHeight
        return overlapRatio >= minOverlapRatio
    }

    /// 针对任意两个窗口矩形，自动识别左右顺序并判定是否贴合
    public static func findAdjacentPair(
        windowA: NSRect,
        windowB: NSRect,
        maxGap: CGFloat = 12.0,
        minOverlapRatio: CGFloat = 0.70,
        minHeight: CGFloat = 300.0,
        minWidth: CGFloat = 250.0
    ) -> (left: NSRect, right: NSRect)? {
        if windowA.minX < windowB.minX {
            if areAdjacent(left: windowA, right: windowB, maxGap: maxGap, minOverlapRatio: minOverlapRatio, minHeight: minHeight, minWidth: minWidth) {
                return (windowA, windowB)
            }
        } else {
            if areAdjacent(left: windowB, right: windowA, maxGap: maxGap, minOverlapRatio: minOverlapRatio, minHeight: minHeight, minWidth: minWidth) {
                return (windowB, windowA)
            }
        }
        return nil
    }

    // MARK: - Joint Resizing Calculation

    /// 计算联动拖拽后的两窗口尺寸（保证总宽守恒且各自 >= minWidth，支持 50:50 居中阻尼磁吸）
    public static func calculateJointResize(
        left: NSRect,
        right: NSRect,
        deltaX: CGFloat,
        minWidth: CGFloat = 250.0,
        magneticTolerance: CGFloat = 0.0
    ) -> (left: NSRect, right: NSRect) {
        guard deltaX.isFinite else { return (left, right) }

        let effectiveMinWidth = max(0.0, min(minWidth, (left.width + right.width) / 2.0))
        let maxDelta = max(0.0, right.width - effectiveMinWidth)
        let minDelta = min(0.0, effectiveMinWidth - left.width)
        var clampedDelta = min(max(deltaX, minDelta), maxDelta)

        // 50%:50% 居中阻尼磁吸算法
        if magneticTolerance > 0.0 {
            let totalSpan = right.maxX - left.minX
            let rawGap = right.minX - left.maxX
            let gap = max(0.0, rawGap)
            let usableWidth = max(0.0, totalSpan - gap)
            let fiftyFiftyLeftWidth = floor(usableWidth / 2.0)
            let targetFiftyFiftyDelta = fiftyFiftyLeftWidth - left.width

            if abs(clampedDelta - targetFiftyFiftyDelta) <= magneticTolerance {
                clampedDelta = targetFiftyFiftyDelta
            }
        }

        let newLeft = NSRect(
            x: left.minX,
            y: left.minY,
            width: left.width + clampedDelta,
            height: left.height
        )
        let newRight = NSRect(
            x: right.minX + clampedDelta,
            y: right.minY,
            width: right.width - clampedDelta,
            height: right.height
        )
        return (newLeft, newRight)
    }

    /// 计算 50%:50% 平分重置尺寸（保持外侧边界与缝隙不变）
    public static func calculateFiftyFiftyReset(
        left: NSRect,
        right: NSRect
    ) -> (left: NSRect, right: NSRect) {
        let totalSpan = right.maxX - left.minX
        let rawGap = right.minX - left.maxX
        let gap = max(0.0, rawGap)
        let usableWidth = max(0.0, totalSpan - gap)
        let halfWidth = floor(usableWidth / 2.0)
        let remainingWidth = usableWidth - halfWidth

        let newLeft = NSRect(
            x: left.minX,
            y: left.minY,
            width: halfWidth,
            height: left.height
        )
        let newRight = NSRect(
            x: left.minX + halfWidth + gap,
            y: right.minY,
            width: remainingWidth,
            height: right.height
        )
        return (newLeft, newRight)
    }

    // MARK: - Interactive Dragging

    public func beginDrag(at mouseLocation: NSPoint) {
        guard let pair = activePair else { return }
        isDraggingDivider = true
        dragStartLeftRect = pair.leftRect
        dragStartRightRect = pair.rightRect
        dragStartDividerX = pair.dividerX
        lastAXResizeTime = 0.0
        SelectionMonitor.shared.log("Begin split divider drag at \(mouseLocation)")
    }

    public func jointResize(deltaX: CGFloat) {
        guard isDraggingDivider, var pair = activePair else { return }

        let (newLeft, newRight) = SplitDividerManager.calculateJointResize(
            left: dragStartLeftRect,
            right: dragStartRightRect,
            deltaX: deltaX,
            minWidth: 250.0,
            magneticTolerance: 12.0
        )

        // 优先即时跟随光标移动悬浮中缝
        let newDividerX = (newLeft.maxX + newRight.minX) / 2.0
        SplitDividerOverlayPanel.shared.updatePosition(
            dividerX: newDividerX,
            y: pair.dividerY,
            height: pair.dividerHeight
        )

        // 实时更新比例徽标
        let totalW = max(1.0, newLeft.width + newRight.width)
        let leftPct = Int(round((newLeft.width / totalW) * 100))
        let rightPct = max(0, 100 - leftPct)
        SplitDividerOverlayPanel.shared.updateRatio(leftPercent: leftPct, rightPercent: rightPct)

        pair.leftRect = newLeft
        pair.rightRect = newRight
        self.activePair = pair

        // 16ms 频率节流 AX 系统调用，避免 IPC 拥塞
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastAXResizeTime >= 0.016 {
            lastAXResizeTime = now
            applyWindowFrames(pair: pair)
        }
    }

    public func endDrag(finalDeltaX: CGFloat) {
        guard isDraggingDivider, var pair = activePair else { return }

        let (finalLeft, finalRight) = SplitDividerManager.calculateJointResize(
            left: dragStartLeftRect,
            right: dragStartRightRect,
            deltaX: finalDeltaX,
            minWidth: 250.0,
            magneticTolerance: 12.0
        )

        pair.leftRect = finalLeft
        pair.rightRect = finalRight
        self.activePair = pair

        // 结束时无节流写入最终坐标，确保像素级精确
        applyWindowFrames(pair: pair)

        let newDividerX = (finalLeft.maxX + finalRight.minX) / 2.0
        SplitDividerOverlayPanel.shared.updatePosition(
            dividerX: newDividerX,
            y: pair.dividerY,
            height: pair.dividerHeight
        )

        isDraggingDivider = false
        SplitDividerOverlayPanel.shared.hideRatio()
        SelectionMonitor.shared.log("End split divider drag: left width=\(finalLeft.width), right width=\(finalRight.width)")
    }

    private func applyWindowFrames(pair: SplitWindowPair) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        // 防碰撞顺序：先收缩后扩张
        if pair.leftRect.width < dragStartLeftRect.width {
            WindowSnapManager.setWindowFrame(element: pair.leftElement, rect: pair.leftRect, primaryScreenHeight: primaryHeight)
            WindowSnapManager.setWindowFrame(element: pair.rightElement, rect: pair.rightRect, primaryScreenHeight: primaryHeight)
        } else {
            WindowSnapManager.setWindowFrame(element: pair.rightElement, rect: pair.rightRect, primaryScreenHeight: primaryHeight)
            WindowSnapManager.setWindowFrame(element: pair.leftElement, rect: pair.leftRect, primaryScreenHeight: primaryHeight)
        }
    }

    // MARK: - Double-Click Reset (50%:50%)

    public func resetToFiftyFifty() {
        guard let pair = activePair else { return }
        let (targetLeft, targetRight) = SplitDividerManager.calculateFiftyFiftyReset(
            left: pair.leftRect,
            right: pair.rightRect
        )

        var updatedPair = pair
        updatedPair.leftRect = targetLeft
        updatedPair.rightRect = targetRight
        self.activePair = updatedPair

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0

        // 防碰撞顺序：先收缩缩小的一侧，再扩张放大的一侧
        if targetLeft.width < pair.leftRect.width {
            WindowSnapManager.setWindowFrame(element: updatedPair.leftElement, rect: targetLeft, primaryScreenHeight: primaryHeight)
            WindowSnapManager.setWindowFrame(element: updatedPair.rightElement, rect: targetRight, primaryScreenHeight: primaryHeight)
        } else {
            WindowSnapManager.setWindowFrame(element: updatedPair.rightElement, rect: targetRight, primaryScreenHeight: primaryHeight)
            WindowSnapManager.setWindowFrame(element: updatedPair.leftElement, rect: targetLeft, primaryScreenHeight: primaryHeight)
        }

        let newDividerX = (targetLeft.maxX + targetRight.minX) / 2.0
        SplitDividerOverlayPanel.shared.updatePosition(
            dividerX: newDividerX,
            y: updatedPair.dividerY,
            height: updatedPair.dividerHeight
        )

        // 同步更新吸附缓存记录，防止后续吸附读取到旧尺寸
        let screenId = pair.screen.displayID
        if var lRec = recentLeftSnapped[screenId], CFEqual(lRec.element, pair.leftElement) {
            lRec.rect = targetLeft
            recentLeftSnapped[screenId] = lRec
        }
        if var rRec = recentRightSnapped[screenId], CFEqual(rRec.element, pair.rightElement) {
            rRec.rect = targetRight
            recentRightSnapped[screenId] = rRec
        }

        SelectionMonitor.shared.log("Reset split windows to 50%:50% (left=\(targetLeft.width), right=\(targetRight.width))")
    }

    // MARK: - Snapping Coordination

    public func registerSnappedWindow(
        element: AXUIElement,
        slot: SnapSlot,
        rect: NSRect,
        screen: NSScreen
    ) {
        guard ConfigManager.shared.enableSplitDivider else { return }

        let screenId = screen.displayID
        let now = Date().timeIntervalSince1970
        let record = SnappedRecord(element: element, rect: rect, timestamp: now)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0

        switch slot {
        case .leftHalf, .mainWorkspace, .leftThird:
            // 若该窗口之前记录在右侧，彻底移除，杜绝自身配对
            if let r = recentRightSnapped[screenId], CFEqual(r.element, element) {
                recentRightSnapped.removeValue(forKey: screenId)
            }
            recentLeftSnapped[screenId] = record

            if let right = recentRightSnapped[screenId], !CFEqual(right.element, element), (now - right.timestamp) <= 300.0 {
                if let currentRightRect = WindowSnapManager.getWindowFrame(element: right.element, primaryScreenHeight: primaryHeight),
                   SplitDividerManager.areAdjacent(left: rect, right: currentRightRect) {
                    var lPid: pid_t = 0
                    var rPid: pid_t = 0
                    AXUIElementGetPid(element, &lPid)
                    AXUIElementGetPid(right.element, &rPid)
                    let pair = SplitWindowPair(
                        leftElement: element,
                        rightElement: right.element,
                        leftRect: rect,
                        rightRect: currentRightRect,
                        screen: screen,
                        leftPid: lPid,
                        rightPid: rPid
                    )
                    setActivePair(pair)
                } else {
                    recentRightSnapped.removeValue(forKey: screenId)
                }
            }

        case .rightHalf, .sideWorkspace, .rightThird:
            // 若该窗口之前记录在左侧，彻底移除，杜绝自身配对
            if let l = recentLeftSnapped[screenId], CFEqual(l.element, element) {
                recentLeftSnapped.removeValue(forKey: screenId)
            }
            recentRightSnapped[screenId] = record

            if let left = recentLeftSnapped[screenId], !CFEqual(left.element, element), (now - left.timestamp) <= 300.0 {
                if let currentLeftRect = WindowSnapManager.getWindowFrame(element: left.element, primaryScreenHeight: primaryHeight),
                   SplitDividerManager.areAdjacent(left: currentLeftRect, right: rect) {
                    var lPid: pid_t = 0
                    var rPid: pid_t = 0
                    AXUIElementGetPid(left.element, &lPid)
                    AXUIElementGetPid(element, &rPid)
                    let pair = SplitWindowPair(
                        leftElement: left.element,
                        rightElement: element,
                        leftRect: currentLeftRect,
                        rightRect: rect,
                        screen: screen,
                        leftPid: lPid,
                        rightPid: rPid
                    )
                    setActivePair(pair)
                } else {
                    recentLeftSnapped.removeValue(forKey: screenId)
                }
            }

        case .maximize, .centerThird, .topLeftQuarter, .topRightQuarter, .bottomLeftQuarter, .bottomRightQuarter:
            recentLeftSnapped.removeValue(forKey: screenId)
            recentRightSnapped.removeValue(forKey: screenId)
            if activePair?.screen.displayID == screenId {
                clearActivePair()
            }
            if slot == .centerThird {
                validateOrRefreshActivePair()
            }
        }
    }

    // MARK: - Pair Management

    public func setActivePair(_ pair: SplitWindowPair) {
        self.activePair = pair
        SplitDividerOverlayPanel.shared.show(
            dividerX: pair.dividerX,
            y: pair.dividerY,
            height: pair.dividerHeight
        )
        SelectionMonitor.shared.log("Active SplitWindowPair registered at dividerX=\(pair.dividerX)")
    }

    public func clearActivePair() {
        self.activePair = nil
        SplitDividerOverlayPanel.safeShared?.hide()
    }

    public func validateOrRefreshActivePair() {
        guard ConfigManager.shared.enableSplitDivider else {
            clearActivePair()
            return
        }

        if isDraggingDivider { return }

        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let selfPid = ProcessInfo.processInfo.processIdentifier

        if let pair = activePair {
            // 前台应用强守卫：如果当前前台应用既不是左窗也不是右窗（且不是本应用自身），立即清理活跃分屏对并隐藏
            if let front = frontPid, front != selfPid {
                if pair.leftPid != front && pair.rightPid != front {
                    clearActivePair()
                    return
                }

                // 深度校验：即使前台应用 PID 匹配，检查该应用当前的聚焦窗口是否确实是分屏对成员
                let appElem = AXUIElementCreateApplication(front)
                var focusedRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
                   let focusedElem = AXCast.element(focusedRef) {
                    if !CFEqual(focusedElem, pair.leftElement) && !CFEqual(focusedElem, pair.rightElement) {
                        // 用户聚焦的是该 App 的另一个独立窗口，而非分屏窗口
                        clearActivePair()
                        return
                    }
                }
            } else if frontPid == nil {
                clearActivePair()
                return
            }

            let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
            if let curLeft = WindowSnapManager.getWindowFrame(element: pair.leftElement, primaryScreenHeight: primaryHeight),
               let curRight = WindowSnapManager.getWindowFrame(element: pair.rightElement, primaryScreenHeight: primaryHeight),
               SplitDividerManager.areAdjacent(left: curLeft, right: curRight) {
                if curLeft != pair.leftRect || curRight != pair.rightRect {
                    var updated = pair
                    updated.leftRect = curLeft
                    updated.rightRect = curRight
                    self.activePair = updated
                    SplitDividerOverlayPanel.safeShared?.updatePosition(
                        dividerX: updated.dividerX,
                        y: updated.dividerY,
                        height: updated.dividerHeight
                    )
                }
                return
            } else {
                clearActivePair()
            }
        }

        let mouseLoc = NSEvent.mouseLocation
        let mouseScreen = WindowSnapManager.shared.resolveScreen(for: mouseLoc)
        if let pair = detectAdjacentPair(on: mouseScreen, near: mouseLoc) {
            setActivePair(pair)
        }
    }

    // MARK: - System Window Detection

    /// 检验分屏窗口对中是否至少有一侧属于指定的前台应用 PID
    public static func isPairMatchingFrontmost(
        leftPid: pid_t,
        rightPid: pid_t,
        frontmostPid: pid_t?
    ) -> Bool {
        guard let front = frontmostPid, front != 0 else { return false }
        return leftPid == front || rightPid == front
    }

    public func detectAdjacentPair(
        on screen: NSScreen,
        near mouseLoc: NSPoint? = nil,
        frontmostPid: pid_t? = nil
    ) -> SplitWindowPair? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let selfPid = ProcessInfo.processInfo.processIdentifier
        let activeFrontPid = frontmostPid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier

        var candidates: [(pid: pid_t, rect: NSRect)] = []

        for info in windowInfoList {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != selfPid,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else {
                continue
            }

            guard w >= 250.0 && h >= 300.0 else { continue }

            let cocoaY = primaryHeight - (y + h)
            let cocoaRect = NSRect(x: x, y: cocoaY, width: w, height: h)

            if screen.visibleFrame.intersects(cocoaRect) {
                candidates.append((pid: pid, rect: cocoaRect))
            }
        }

        var validPairs: [SplitWindowPair] = []

        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                let a = candidates[i]
                let b = candidates[j]

                let (left, right, leftPid, rightPid): (NSRect, NSRect, pid_t, pid_t)
                if a.rect.minX < b.rect.minX {
                    (left, right, leftPid, rightPid) = (a.rect, b.rect, a.pid, b.pid)
                } else {
                    (left, right, leftPid, rightPid) = (b.rect, a.rect, b.pid, a.pid)
                }

                // 前台应用过滤：必须至少有一侧窗口属于当前活跃的前台应用（防止在单窗口或无关应用前台时激活后台分屏中缝）
                if let front = activeFrontPid, front != selfPid {
                    guard SplitDividerManager.isPairMatchingFrontmost(leftPid: leftPid, rightPid: rightPid, frontmostPid: front) else {
                        continue
                    }
                }

                guard SplitDividerManager.areAdjacent(left: left, right: right) else { continue }

                // 遮挡检测：判断在 Z 轴前方是否有更顶层窗口遮住了中缝核心区域
                let seamX = (left.maxX + right.minX) / 2.0
                let seamMinY = max(left.minY, right.minY)
                let seamMaxY = min(left.maxY, right.maxY)
                let seamRect = NSRect(x: seamX - 8.0, y: seamMinY, width: 16.0, height: max(1.0, seamMaxY - seamMinY))

                var isOccluded = false
                for k in 0..<max(i, j) {
                    if k == i || k == j { continue }
                    let higherWindow = candidates[k]
                    // 1. 顶层窗口横跨中缝核心区域（无论所属应用为何，包括同应用其它独立大窗口）
                    if higherWindow.rect.intersects(seamRect) {
                        isOccluded = true
                        break
                    }
                    // 2. 顶层窗口大面积遮挡左窗主体 (> 20% 面积)
                    let leftOverlap = higherWindow.rect.intersection(left)
                    if !leftOverlap.isNull && (leftOverlap.width * leftOverlap.height) > (left.width * left.height * 0.20) {
                        isOccluded = true
                        break
                    }
                    // 3. 顶层窗口大面积遮挡右窗主体 (> 20% 面积)
                    if k < j {
                        let rightOverlap = higherWindow.rect.intersection(right)
                        if !rightOverlap.isNull && (rightOverlap.width * rightOverlap.height) > (right.width * right.height * 0.20) {
                            isOccluded = true
                            break
                        }
                    }
                }
                guard !isOccluded else { continue }

                if let leftElem = resolveWindowElement(pid: leftPid, matching: left, primaryHeight: primaryHeight),
                   let rightElem = resolveWindowElement(pid: rightPid, matching: right, primaryHeight: primaryHeight),
                   !CFEqual(leftElem, rightElem) {
                    // 如果前台应用属于这一对，校验前台应用的聚焦窗口是否确实是两者之一
                    if let front = activeFrontPid, front != selfPid {
                        let appElem = AXUIElementCreateApplication(front)
                        var focusedRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
                           let focusedElem = AXCast.element(focusedRef) {
                            if !CFEqual(focusedElem, leftElem) && !CFEqual(focusedElem, rightElem) {
                                // 用户当前聚焦的是该前台 App 的另一个独立窗口，而非这对分屏窗口
                                continue
                            }
                        }
                    }
                    let pair = SplitWindowPair(
                        leftElement: leftElem,
                        rightElement: rightElem,
                        leftRect: left,
                        rightRect: right,
                        screen: screen,
                        leftPid: leftPid,
                        rightPid: rightPid
                    )
                    validPairs.append(pair)
                }
            }
        }

        if let loc = mouseLoc {
            // 优先匹配中缝横坐标距当前鼠标位置最近的接缝窗口对（适配三等分屏等多缝隙布局）
            return validPairs.min(by: { abs($0.dividerX - loc.x) < abs($1.dividerX - loc.x) })
        }
        return validPairs.first
    }

    private func resolveWindowElement(pid: pid_t, matching targetRect: NSRect, primaryHeight: CGFloat) -> AXUIElement? {
        let appElem = AXUIElementCreateApplication(pid)
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let windows = windowsRef as? [AXUIElement] {
            for win in windows {
                if let frame = WindowSnapManager.getWindowFrame(element: win, primaryScreenHeight: primaryHeight) {
                    if abs(frame.minX - targetRect.minX) <= 15.0 &&
                       abs(frame.minY - targetRect.minY) <= 15.0 &&
                       abs(frame.width - targetRect.width) <= 15.0 &&
                       abs(frame.height - targetRect.height) <= 15.0 {
                        return win
                    }
                }
            }
        }

        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let elem = AXCast.element(focusedRef) {
            if let frame = WindowSnapManager.getWindowFrame(element: elem, primaryScreenHeight: primaryHeight) {
                if abs(frame.minX - targetRect.minX) <= 15.0 &&
                   abs(frame.minY - targetRect.minY) <= 15.0 &&
                   abs(frame.width - targetRect.width) <= 15.0 &&
                   abs(frame.height - targetRect.height) <= 15.0 {
                    return elem
                }
            }
        }
        return nil
    }
}

extension NSScreen {
    public var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
