//
//  TransientCommandBarPanel.swift
//  HuaciGongju
//

import Cocoa
import SwiftUI

// MARK: - Custom Hosting View ensuring First Mouse Click is Accepted
public class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - UI Expansion State
public enum CommandBarDisplayMode {
    case collapsed // High capsule toolbar only (height adapts to the current screen's menu bar)
    case expanded  // Unified Liquid Glass surface with result area beneath (height: ~380pt)
}

public typealias ToolbarPanel = TransientCommandBarPanel

public class TransientCommandBarPanel: NSPanel {
    // MARK: - 懒实体化
    //
    // Swift 的 `static let` 是懒初始化，但只要**任何一个调用点**在启动早期顺手访问
    // `shared`，整棵 NSPanel + NSHostingView + SwiftUI View Graph + 玻璃图层就会在那一刻
    // 被建出来并常驻到进程结束。实测（footprint）面板是这个进程最大的一笔常驻开销。
    //
    // 历史上 `SelectionMonitor` 的全局 mouseUp 回调为了判断「这一下是不是点在自己身上」
    // 就访问了 `shared.isVisible` —— 结果用户开机后**第一次点鼠标**就付了这笔钱，
    // 而那时他可能一次都没划过词。
    //
    // 因此 `shared` 改成计算属性并留下 `isMaterialized`：
    // 调用方可以先问「它建过吗」，没建过就必然不可见，连访问都不必。
    private static let storage = TransientCommandBarPanel()
    private static var hasMaterialized = false

    /// 面板是否已被实体化。**不会触发创建** —— 用于在不付出构造代价的前提下短路判断。
    public static var isMaterialized: Bool { hasMaterialized }

    public static var shared: TransientCommandBarPanel {
        hasMaterialized = true
        return storage
    }

    /// 若面板已实体化则返回实例，否则返回 nil，绝不触发构造
    public static var safeShared: TransientCommandBarPanel? {
        isMaterialized ? storage : nil
    }

    private var currentSelectedText: String = ""
    private var currentActiveScreen: NSScreen?
    private var isExpanded: Bool = false
    private var topEdgeAnchorY: CGFloat = 0
    /// Companion 模式下条从宠物朝里一侧长出；Ghost 路径保持 nil。
    private var companionAnchor: (center: CGPoint, edge: CompanionEdge)?

    /// 退场令牌。每次 `dismiss()` / `show()` 递增，用来让**过期的收尾动作**作废。
    ///
    /// 竞态场景（既存 bug）：展开态点外部 → 起 0.26s 收起动画 → 这 0.26s 内用户又划词，
    /// `show()` 因为面板此刻仍可见而走「同屏连续选择」分支直接 return；
    /// 0.26s 后旧的 completionHandler 照常执行 `orderOut` + 拆监听，
    /// 把**刚划出来的浮条**连带隐藏。表现就是「划词偶尔没反应」。
    private var dismissalToken: Int = 0

    // MARK: - 临时事件监听（只在面板可见期间存在）
    //
    // 旧实现在 App 启动时就永久装好 outside-click 与 ESC 两个监听，而回调里直接访问
    // `TransientCommandBarPanel.shared` —— 用户启动程序后一次划词都没用过，只要第一次点鼠标，
    // 就会把整个 NSPanel + NSHostingView + SwiftUI View Graph + ViewModel 实体化，
    // 并且从此常驻到进程结束。
    //
    // 改成「谁需要谁负责生命周期」：面板出现时装、消失时拆。
    // 收益不只是省内存，还少掉一个常驻的 global event monitor。
    private var outsideClickMonitor: Any?
    private var localEscMonitor: Any?

    public let viewModel = UnifiedCommandBarViewModel()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 38),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.becomesKeyOnlyIfNeeded = true
        self.alphaValue = 0.0
        self.hidesOnDeactivate = false
        // 进程级单例：关窗不得释放；NSApp.hide 也不得把条收走。
        self.isReleasedWhenClosed = false
        self.canHide = false

        let contentView = UnifiedCommandBarContainerView(
            viewModel: viewModel,
            onSelectAction: { [weak self] action in
                self?.handleActionTriggered(action)
            },
            onCopy: { [weak self] in
                self?.handleCopyTriggered()
            },
            onCollapse: { [weak self] in
                self?.collapseToToolbar()
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        let hostingView = FirstMouseHostingView(rootView: contentView)
        self.contentView = hostingView
    }

    // MARK: - Action Execution
    private func handleCopyTriggered() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentSelectedText, forType: .string)

        // 复制确认由「复制按钮自身」表达（图标换成绿色对勾），而**不是**往胶囊里插文字。
        // 收起态胶囊高度仅 28pt 且宽度紧贴内容，插入文字无论放哪儿都会撑开整行或压住相邻按钮。
        withAnimation(.easeInOut(duration: 0.15)) {
            viewModel.isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            withAnimation { self?.viewModel.isCopied = false }
        }
    }

    private func handleActionTriggered(_ action: ActionItem) {
        if action.type == .search {
            // 搜索的反馈是浏览器被打开本身；胶囊随后即自行消失，不再在胶囊内叠加文字提示
            performSearch(text: currentSelectedText, template: action.searchTemplate)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.dismiss()
            }
            return
        }

        // AI Action: Expand the container downward while keeping Top Edge strictly anchored
        viewModel.startAction(text: currentSelectedText, action: action)
        expandResultArea()
    }

    private func performSearch(text: String, template: String) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        let urlString = template.contains("%@") ? String(format: template, encoded) : "\(template)\(encoded)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            if ConfigManager.shared.enablePlaintextLogging {
                SelectionMonitor.shared.log("Opened search in browser: \(urlString)")
            } else {
                SelectionMonitor.shared.log("Opened search in browser (length: \(text.count))")
            }
        }
    }

    // MARK: - Exit Choreography

    /// 退场编排 —— **一次动作完成：玻璃收回菜单栏的同时溶解**。
    ///
    /// 曾经排成三拍：内容 0.12s 先退 → 容器 0.26s 收回 → **到位后**再 0.08s 淡出。
    /// 前两拍是刻意的层次（让「空玻璃」而不是「被裁切的文字」参与收缩），
    /// 但第三拍是错的：容器收完才起步淡出，于是观众读到的是
    /// 「先缩成一颗胶囊（= 一个状态栏），停一下，再消失」——两段式，不流畅。
    ///
    /// 现在：容器收缩与整体 alpha 放进**同一个** `NSAnimationContext`，
    /// 同一条时长、同一条曲线，从第一帧起就同时动、同时淡，一个连续动作落定。
    /// 内容仍略微提前退场（`contentDuration`），但它只是替收缩腾出画面，
    /// 不再构成可辨识的独立节拍。
    private enum ExitChoreography {
        /// 内容退场时长。短促且最先发生，保证窗口明显收缩之前结果区已经淡出，
        /// 因此收缩过程中露出的始终是「空玻璃」，不会看到内容被裁切。
        ///
        /// 用 ease-out（而非先前的 ease-in）：在 0.1s 这个尺度上 ease-in 几乎是
        /// 「先不动、再瞬间消失」，与紧随其后的收缩接不上；ease-out 则是干净退场。
        static let contentDuration: TimeInterval = 0.10
        /// **收缩 + 溶解的总时长**。注意它不再是「三拍里的第二拍」，
        /// 而是整个退场动作的全部时长。
        static let collapseDuration: TimeInterval = 0.26

        /// 收缩与溶解共用的曲线：温和的 S 形 —— 起步克制、中段推进、末端落定。
        ///
        /// 旧值是强 ease-out（controlPoints 0.25, 0.9, 0.35, 1.0，起点斜率约 3.6）：
        /// 位移在头 40% 时长内就走完约 90%，剩下 60% 只是蠕动。
        /// 单独驱动位移时这叫「干脆」；可一旦透明度和位移共用这条曲线，它就成了毛病 ——
        /// 玻璃会在头 0.1 秒里淡到近乎不可见，观众根本来不及读到「收回」这个动作。
        ///
        /// 当前控制点在 50% 时长处恰好走完 50% 行程（实测 Bezier 解 x=0.5 时 y≈0.53），
        /// 位移与溶解全程同步可见；起点斜率 0.17、末端斜率 0.25，两端都不生硬。
        static let collapseTiming = CAMediaTimingFunction(controlPoints: 0.30, 0.05, 0.60, 0.90)
    }

    /// 收起态的目标 frame（顶边恒定，底边向上收）。
    ///
    /// 宽度一律复用收起态记录的 `collapsedBarWidth`：展开态下 `resolveCollapsedWidth()`
    /// 会被 `< 420` 的守卫挡下并原样返回 420，反推不出真实胶囊宽度。
    private func collapsedTargetRect() -> NSRect {
        let screen = currentActiveScreen ?? NSScreen.main ?? NSScreen()
        let height = resolveCollapsedHeight(for: screen)
        let width = viewModel.collapsedBarWidth > 0
            ? viewModel.collapsedBarWidth
            : resolveCollapsedWidth()
        let frame = self.frame
        return NSRect(
            x: frame.midX - width / 2,
            y: topEdgeAnchorY - height,
            width: width,
            height: height
        )
    }

    // MARK: - Expansion & Collapse Geometry (Top Edge = Constant)

    private enum ExpandedLayout {
        /// 结果区的最小阅读宽度（设计基线）
        static let preferredWidth: CGFloat = 420
        /// 展开态右侧控件区比收起态多出来的宽度，**并非常规的「差额」**。
        ///
        /// 展开态顶栏被钉成收起态原宽（`collapsedBarWidth = W_c`），动作组在其中左对齐不动，
        /// 于是展开态多出来的 固定/收起/关闭 三键（约 72pt；收起态只有复制 23pt）
        /// 只能向**右溢出**到窗口留白里被吸收。
        ///
        /// 溢出量是恒定的 39pt，与动作多少无关：
        /// ```
        /// 收起态自然宽    W_c = 动作组A + 复制23 + 左右留白20   ⇒ A = W_c − 43
        /// 展开态内容宽    A + 72 = W_c + 29
        /// 行内框宽        W_c − 20            ⇒ 内容超出 49pt
        /// 吃掉右侧 10pt 内边距后，内容右缘比**行右缘**还多 39pt
        /// ```
        ///
        /// ⚠️ 关键：顶栏行在窗口里是**居中**的，所以窗口每加宽 Δ，
        /// 只有 **Δ/2** 落在溢出的右侧，另一半被浪费在左侧空白上 ——
        /// 内容右缘相对 midX 恒为 `W_c/2 + 39`（与窗口宽 T 无关），窗口右缘是 `T/2`，
        /// 于是不裁剪要求 `T/2 ≥ W_c/2 + 39`，即 **T ≥ W_c + 78**（= 2 × 39）。
        /// 直接取「差额 49 + 余量」是不够的，会少算一半。
        ///
        /// 取 88 = 78（零余量下限）+ 10（边距）。默认四个动作时 W_c ≈ 300，
        /// `max(420, 300+88)` 仍是 420 —— **默认配置宽度分毫不变**，
        /// 只有自定义 Action 多到 W_c > 332 时窗口才会跟着变宽。
        static let controlsDelta: CGFloat = 88
    }

    /// 展开态窗口宽度：既不小于结果区的阅读基线，也要能吸收展开态多出来的右侧控件，
    /// 最后夹到当前屏幕可视宽度，避免 Action 变多时窗口超出屏幕。
    ///
    /// ⚠️ 这里**可以**自由改宽度而不破坏「动作文字不横移」的不变量 ——
    /// 窗口与顶栏行共用同一个 midX，顶栏行宽恒为 `collapsedBarWidth`，
    /// 于是动作组的左侧屏幕坐标与 `targetWidth` 无关：
    /// ```
    /// 动作组左 = (midX − T/2) + (T − W)/2 + 10
    ///          = (x_c + W/2) − T/2 + T/2 − W/2 + 10 = x_c + 10   ← T 被抵消
    /// ```
    /// 即：无论窗口多宽，动作组永远钉在「收起态窗口左边缘 + 10pt」。
    private func expandedWidth(for screen: NSScreen) -> CGFloat {
        let needed = viewModel.collapsedBarWidth > 0
            ? viewModel.collapsedBarWidth + ExpandedLayout.controlsDelta
            : ExpandedLayout.preferredWidth
        let width = max(ExpandedLayout.preferredWidth, needed)
        return min(width, screen.visibleFrame.width)
    }

    private func expandResultArea() {
        guard !isExpanded else { return }
        isExpanded = true
        withAnimation(.easeOut(duration: 0.20)) {
            viewModel.displayMode = .expanded
        }

        let screen = currentActiveScreen ?? NSScreen.main ?? NSScreen()
        let maxAllowedHeight = screen.visibleFrame.height * 0.60
        let targetHeight: CGFloat = min(390, maxAllowedHeight)
        let targetWidth = expandedWidth(for: screen)

        let targetRect: NSRect
        if let anchor = companionAnchor {
            let collapsed = CGSize(
                width: viewModel.collapsedBarWidth > 0 ? viewModel.collapsedBarWidth : 28,
                height: viewModel.collapsedBarHeight > 0 ? viewModel.collapsedBarHeight : 28
            )
            let placement = CompanionGeometry.planExpandedBarOpening(
                petCenter: anchor.center,
                edge: anchor.edge,
                collapsedSize: collapsed,
                expandedSize: CGSize(width: targetWidth, height: targetHeight),
                visibleFrame: screen.visibleFrame
            )
            companionAnchor = (placement.petCenter, placement.edge)
            CompanionPetPanel.safeShared?.move(to: placement.petCenter)
            CompanionManager.shared.notePetRelocated(to: placement.petCenter, edge: placement.edge)
            targetRect = placement.frame
        } else {
            // Geometric Invariant: Top Edge = Constant, expand downwards
            let currentFrame = self.frame
            let newY = topEdgeAnchorY - targetHeight
            let newX = currentFrame.midX - targetWidth / 2
            targetRect = NSRect(x: newX, y: newY, width: targetWidth, height: targetHeight)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetRect, display: true)
        }
    }

    public func collapseToToolbar() {
        guard isExpanded else { return }
        isExpanded = false
        viewModel.stopGenerating()
        viewModel.isPinned = false

        let targetRect = companionCollapsedRect() ?? collapsedTargetRect()

        // ① 内容先退场：切换布局并让展开区淡出（0.10s）。
        //    它比窗口收缩（0.26s）快一倍以上，因此当窗口收缩变得肉眼可见时，
        //    内容早已不可见 —— 整个过程露出的始终是空玻璃，不会读到被裁切的文字。
        //    前提：展开区必须带 .transition(.opacity)，否则这一步是硬切，
        //    会退化成「内容瞬间消失、玻璃随后慢慢收」的观感。
        withAnimation(.easeOut(duration: ExitChoreography.contentDuration)) {
            viewModel.displayMode = .collapsed
        }

        // ② 容器随后收回：强 ease-out，让「被吸回菜单栏」这个位移本身被看见。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = ExitChoreography.collapseDuration
            context.timingFunction = ExitChoreography.collapseTiming
            self.animator().setFrame(targetRect, display: true)
        }
    }

    // MARK: - Positioning & Presentation
    private func resolveActiveScreen(for selectionPoint: NSPoint) -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(selectionPoint) }) {
            return screen
        }
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// 读取指定屏幕菜单栏的几何信息（高度与上下边界）。
    /// 菜单栏高度随设备与缩放档位而变：普通外接屏约 24–30pt、刘海屏约 28pt，
    /// 因此不能写死，必须每次动态读取。
    private func menuBarMetrics(for screen: NSScreen) -> (height: CGFloat, bottom: CGFloat, top: CGFloat) {
        let top = screen.frame.maxY
        let height = max(0, top - screen.visibleFrame.maxY)
        return (height, top - height, top)
    }

    /// 收起态浮条的目标高度：贴合当前屏幕的菜单栏高度（上下各留 1pt），
    /// 且不超过原始设计高度 38pt。菜单栏高度读不到有效值时回退 38pt。
    private func resolveCollapsedHeight(for screen: NSScreen) -> CGFloat {
        let menuBarHeight = menuBarMetrics(for: screen).height
        guard menuBarHeight > 0 else { return 38 }
        return min(38, menuBarHeight - 2)
    }

    /// 测量收起态浮条的理想宽度：让 SwiftUI 按内容自然尺寸布局后读取 fittingSize，
    /// 使胶囊宽度贴合内容，避免两端留下大片空白。
    /// 测量失败或结果不合理时回退到设计宽度 420pt。
    private func resolveCollapsedWidth() -> CGFloat {
        self.contentView?.layoutSubtreeIfNeeded()
        guard let ideal = self.contentView?.fittingSize.width,
              ideal > 120,
              ideal < 420 else {
            return 420
        }
        return ideal
    }

    private func resolveTopOverlayAnchor(screen: NSScreen, overlayWidth: CGFloat, overlayHeight: CGFloat) -> NSRect {
        let screenFrame = screen.frame
        let margin: CGFloat = 10.0
        let menuBar = menuBarMetrics(for: screen)

        var targetX: CGFloat = 0
        var minX: CGFloat = screenFrame.minX + margin

        if #available(macOS 12.0, *),
           screen.safeAreaInsets.top > 0,
           let rightArea = screen.auxiliaryTopRightArea,
           rightArea.width > 0 {
            // 刘海屏：横向起点贴在刘海右侧
            minX = rightArea.minX + margin
            targetX = minX
        } else {
            // 普通屏：横向绝对居中
            targetX = screenFrame.midX - (overlayWidth / 2)
        }

        // 纵向统一为「菜单栏色带内垂直居中」。
        // 浮条高度已按菜单栏高度收敛，因此不会再向下溢出遮挡下方窗口。
        var targetY = menuBar.bottom + (menuBar.height - overlayHeight) / 2

        let maxX = screenFrame.maxX - overlayWidth - margin
        if targetX < minX { targetX = minX }
        if targetX > maxX { targetX = maxX }

        // 纵向夹取，确保浮条完整落在菜单栏色带内
        let minY = menuBar.bottom
        let maxY = max(minY, menuBar.top - overlayHeight)
        if targetY < minY { targetY = minY }
        if targetY > maxY { targetY = maxY }

        return NSRect(x: targetX, y: targetY, width: overlayWidth, height: overlayHeight)
    }

    /// Companion：胶囊从宠物朝里一侧长出，不回菜单栏。
    public func showBesideCompanion(text: String, petCenter: CGPoint, edge: CompanionEdge) {
        if self.isVisible && self.isExpanded && self.viewModel.isPinned {
            SelectionMonitor.shared.log("Selection ignored: panel is pinned & expanded, state fully frozen.")
            return
        }

        let screen = resolveScreenContaining(petCenter)
        let wasVisible = self.isVisible

        self.currentSelectedText = text
        self.currentActiveScreen = screen

        dismissalToken += 1
        installTransientMonitors()

        viewModel.resetState()
        isExpanded = false

        let panelWidth = resolveCollapsedWidth()
        let collapsedHeight: CGFloat = 28
        viewModel.collapsedBarHeight = collapsedHeight
        viewModel.collapsedBarWidth = panelWidth

        let placement = CompanionGeometry.planBarOpening(
            petCenter: petCenter,
            edge: edge,
            barSize: CGSize(width: panelWidth, height: collapsedHeight),
            visibleFrame: screen.visibleFrame
        )
        companionAnchor = (placement.petCenter, placement.edge)
        CompanionPetPanel.safeShared?.move(to: placement.petCenter)
        CompanionManager.shared.notePetRelocated(to: placement.petCenter, edge: placement.edge)

        applyCompanionFrame(placement.frame, wasVisible: wasVisible)
        SelectionMonitor.shared.log("Companion bar presented at \(placement.frame)")
    }

    public func show(at screenPoint: NSPoint, text: String) {
        // Pin protection: 面板处于「已固定 + 已展开」时，新的划词一律忽略。
        // 注意：这里**不更新** currentSelectedText —— 否则会出现
        // currentSelectedText 是新文字、而 viewModel.sourceText 仍是旧文字的分裂状态。
        if self.isVisible && self.isExpanded && self.viewModel.isPinned {
            SelectionMonitor.shared.log("Selection ignored: panel is pinned & expanded, state fully frozen.")
            return
        }

        let screen = resolveActiveScreen(for: screenPoint)
        let isSameScreen = (currentActiveScreen?.frame == screen.frame)
        let wasVisible = self.isVisible
        let wasExpanded = self.isExpanded

        self.currentSelectedText = text
        self.currentActiveScreen = screen
        self.companionAnchor = nil

        // 作废进行中的退场：它的 completion 若仍挂着，会在动画结束时把这次刚划出的
        // 浮条一起 orderOut 并拆掉监听（见 `dismissalToken` 的注释）。
        dismissalToken += 1

        // 面板即将可见：安装 outside-click / ESC 监听（幂等）
        installTransientMonitors()

        // If not pinned, cancel LLMService, reset ViewModel dirty state and collapse
        viewModel.resetState()
        isExpanded = false

        // 宽度贴合内容（避免胶囊两端出现大片空白）；高度贴合当前屏幕的菜单栏。
        // 必须在收起之后再测量，否则会取到展开态的结果区宽度。
        let panelWidth = resolveCollapsedWidth()
        let collapsedHeight = resolveCollapsedHeight(for: screen)

        // 同步给 SwiftUI 层：高度决定胶囊形态，宽度决定胶囊在加宽窗口中的固定占位
        viewModel.collapsedBarHeight = collapsedHeight
        viewModel.collapsedBarWidth = panelWidth

        let targetRect = resolveTopOverlayAnchor(screen: screen, overlayWidth: panelWidth, overlayHeight: collapsedHeight)
        self.topEdgeAnchorY = targetRect.origin.y + collapsedHeight

        // Continuous selection on same screen: update frame directly or collapse smoothly
        if wasVisible && isSameScreen {
            if wasExpanded {
                // 与 collapseToToolbar() 复用同一套退场编排 ——
                // 同一个「从展开态收回」的动作不该因为触发来源（ESC / 新划词）而有两种手感。
                withAnimation(.easeOut(duration: ExitChoreography.contentDuration)) {
                    self.viewModel.displayMode = .collapsed
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = ExitChoreography.collapseDuration
                    context.timingFunction = ExitChoreography.collapseTiming
                    self.animator().setFrame(targetRect, display: true)
                }
            } else {
                self.setFrame(targetRect, display: true)
            }
            self.alphaValue = 1.0
            SelectionMonitor.shared.log("Continuous selection updated on same screen, reset to collapsed toolbar")
            return
        }

        // Fresh appearance in collapsed mode
        let slideOffset: CGFloat = 4.0
        let startRect = NSRect(x: targetRect.origin.x, y: targetRect.origin.y + slideOffset, width: panelWidth, height: collapsedHeight)

        self.setFrame(startRect, display: false)
        self.alphaValue = 0.0
        // 应用此前可能因「归还焦点」被 hide（见 AppDelegate.releaseFocus）；
        // 先 unhide 再 order front，保证浮条在任何情况下都能正常出现。
        NSApp.unhide(nil)
        self.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetRect, display: true)
            self.animator().alphaValue = 1.0
        }

        SelectionMonitor.shared.log("Unified Transient Command Bar presented at \(targetRect)")
    }

    /// 安装 outside-click / ESC 监听。幂等 —— 连续 `show()` 不会重复安装。
    private func installTransientMonitors() {
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                guard let self = self else { return }
                let mouseLoc = NSEvent.mouseLocation
                guard self.isVisible, !self.frame.contains(mouseLoc) else { return }
                // 已固定：外部点击不关闭
                if self.viewModel.displayMode == .expanded && self.viewModel.isPinned { return }
                self.dismiss()
            }
        }

        if localEscMonitor == nil {
            localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self = self else { return event }
                if event.keyCode == 53 { // ESC
                    // 展开态先收回成划词栏，再按一次才真正关闭
                    if self.viewModel.displayMode == .expanded {
                        self.collapseToToolbar()
                    } else {
                        self.dismiss()
                    }
                }
                return event
            }
        }
    }

    /// 拆除临时监听 —— 不让它们活到进程结束。
    ///
    /// 只在动画收尾（`orderOut`）时调用，避免在监听回调执行过程中摘除自己。
    private func removeTransientMonitors() {
        if let m = outsideClickMonitor {
            NSEvent.removeMonitor(m)
            outsideClickMonitor = nil
        }
        if let m = localEscMonitor {
            NSEvent.removeMonitor(m)
            localEscMonitor = nil
        }
    }

    /// Presence 硬切：立刻收掉条，不等退场动画。
    /// 切到桌宠 / 关桌宠都不能把窗口交给 AppKit 慢慢关，否则主循环排空自动释放池时会 SIGSEGV。
    public func dismissImmediately() {
        dismissalToken += 1
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        animator().alphaValue = 1.0
        NSAnimationContext.endGrouping()
        orderOut(nil)
        removeTransientMonitors()
        isExpanded = false
        viewModel.stopGenerating()
        viewModel.resetState()
        currentSelectedText = ""
        companionAnchor = nil
        alphaValue = 1.0
    }

    public func dismiss() {
        let wasExpanded = isExpanded
        isExpanded = false
        viewModel.stopGenerating()

        // 本次退场才是「最后一句」：作废上一次尚未收尾的退场，避免它迟到的 completion
        // 把期间重新 show 出来的面板一起 orderOut。
        dismissalToken += 1
        let token = dismissalToken

        // 收起态：本来就是一颗贴着菜单栏的小胶囊，没有什么高度可供「收回」，
        // 原地淡出就是它最自然的退场方式，硬做位移反而多余。
        guard wasExpanded else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.14
                self.animator().alphaValue = 0.0
            }, completionHandler: {
                guard self.dismissalToken == token else { return }
                self.orderOut(nil)
                self.removeTransientMonitors()
                self.viewModel.resetState()
                // 面板是常驻 singleton，这份选中文本会一直挂在它上面直到下次 show()。
                // 用户若刚选了一整篇长文，关闭后这段文本仍白白占着内存 —— 随手清掉。
                self.currentSelectedText = ""
                self.companionAnchor = nil
                self.alphaValue = 1.0
                CompanionManager.shared.notifyShellClosed()
            })
            return
        }

        // 展开态：关闭**不等于**「原地变透明」。此时窗口约 390pt 高，
        // 纯 alpha 淡出读到的是「一整块玻璃凭空蒸发」—— 既没有方向感，
        // 玻璃材质在淡化过程中还会先发糊再消失。这是「不够优雅」的主因。
        //
        // 但「收回 + 淡出」若排成两拍（收完 → 再淡出），读到的是另一件错事：
        // 「先缩成一颗胶囊，停一下，再消失」。所以两者必须**同时**发生 ——
        // 同一个动画组、同一条时长、同一条曲线，只有这样才是一段式。
        let targetRect = companionCollapsedRect() ?? collapsedTargetRect()

        withAnimation(.easeOut(duration: ExitChoreography.contentDuration)) {
            viewModel.displayMode = .collapsed
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ExitChoreography.collapseDuration
            context.timingFunction = ExitChoreography.collapseTiming
            // 位移与透明度同组同曲线：玻璃一边被吸回菜单栏色带，一边溶解。
            // 只留一个 completionHandler —— 最后一个动作结束时才收尾。
            self.animator().setFrame(targetRect, display: true)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            guard self.dismissalToken == token else { return }
            self.orderOut(nil)
            self.removeTransientMonitors()
            self.viewModel.resetState()
            self.currentSelectedText = ""   // 同上：面板常驻，别把长文本留到下次 show()
            self.companionAnchor = nil
            // 复位，供下次 show() 从 1.0 起淡入。
            self.alphaValue = 1.0
            CompanionManager.shared.notifyShellClosed()
        })
    }

    private func resolveScreenContaining(_ point: NSPoint) -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func companionCollapsedRect() -> NSRect? {
        guard let anchor = companionAnchor else { return nil }
        let screen = currentActiveScreen ?? resolveScreenContaining(anchor.center)
        let width = viewModel.collapsedBarWidth > 0 ? viewModel.collapsedBarWidth : resolveCollapsedWidth()
        let height = viewModel.collapsedBarHeight > 0 ? viewModel.collapsedBarHeight : 28
        let placement = CompanionGeometry.planBarOpening(
            petCenter: anchor.center,
            edge: anchor.edge,
            barSize: CGSize(width: width, height: height),
            visibleFrame: screen.visibleFrame
        )
        companionAnchor = (placement.petCenter, placement.edge)
        return placement.frame
    }

    private func applyCompanionFrame(_ targetRect: NSRect, wasVisible: Bool) {
        if wasVisible {
            self.setFrame(targetRect, display: true)
            self.alphaValue = 1.0
            return
        }
        let startRect = NSRect(
            x: targetRect.origin.x,
            y: targetRect.origin.y - 4,
            width: targetRect.width,
            height: targetRect.height
        )
        self.setFrame(startRect, display: false)
        self.alphaValue = 0.0
        NSApp.unhide(nil)
        self.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(targetRect, display: true)
            self.animator().alphaValue = 1.0
        }
    }

    public override func resignKey() {
        super.resignKey()
        if isExpanded && !viewModel.isPinned {
            dismiss()
        }
    }
}

// MARK: - Native macOS 26+ Liquid Glass Surface Bridge
public enum LiquidGlassStyle {
    case regular
}

public struct NativeLiquidGlassView: NSViewRepresentable {
    public var cornerRadius: CGFloat = 19.0
    public var style: LiquidGlassStyle = .regular
    public var tintColor: NSColor? = nil
    /// 交互式玻璃响应（macOS 27.0 新增 `effectIsInteractive`）。
    ///
    /// Apple 头文件的说明是：「当玻璃作为**交互控件的背景**、或作为交互控件的容器时应开启」——
    /// 划词栏与分屏岛都正是这个场景（玻璃承载一排按钮），却一直没开。
    /// 开启后玻璃会对交互给出自身的视觉响应，而不是一块静止的塑料板。
    ///
    /// ⚠️ 未经离线验证：能否生效取决于鼠标事件是否真正到达玻璃视图本身
    /// （当前架构里玻璃是 `.background()` 的兄弟层，事件先被上层 SwiftUI 内容吃掉）。
    public var effectIsInteractive: Bool = false

    public init(
        cornerRadius: CGFloat = 19.0,
        style: LiquidGlassStyle = .regular,
        tintColor: NSColor? = nil,
        effectIsInteractive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.style = style
        self.tintColor = tintColor
        self.effectIsInteractive = effectIsInteractive
    }

    public func makeNSView(context: Context) -> NSView {
        let appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.appearance = appearance
            view.cornerRadius = cornerRadius
            view.style = .regular
            if #available(macOS 27.0, *) {
                view.effectIsInteractive = effectIsInteractive
            }
            if let tint = tintColor {
                view.tintColor = tint
            }
            view.wantsLayer = true
            // 与下方 NSVisualEffectView 分支保持对称（该分支一直设了 masksToBounds，此处原先漏设）。
            // NSGlassEffectView 自身有 cornerRadius，但 SwiftUI 的 .clipShape 对
            // NSViewRepresentable 内的 AppKit layer 未必生效；一旦漏裁，玻璃会以方形角
            // 溢出到圆角轮廓之外，同样表现为「矩形框与胶囊打架」。
            view.layer?.masksToBounds = true
            return view
        } else {
            let view = NSVisualEffectView()
            view.appearance = appearance
            // .popover 会随 appearance 自动切换亮/暗表现；
            // 原 .hudWindow 属深色专用材质，在亮色主题下会明显突兀。
            view.material = .popover
            view.blendingMode = .behindWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.masksToBounds = true
            return view
        }
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        nsView.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if #available(macOS 26.0, *), let glassView = nsView as? NSGlassEffectView {
            glassView.cornerRadius = cornerRadius
            glassView.style = .regular
            if #available(macOS 27.0, *) {
                glassView.effectIsInteractive = effectIsInteractive
            }
            if let tint = tintColor {
                glassView.tintColor = tint
            }
        } else if let visualEffectView = nsView as? NSVisualEffectView {
            visualEffectView.layer?.cornerRadius = cornerRadius
        }
    }
}

public typealias NativeVisualEffectView = NativeLiquidGlassView

// MARK: - Optical Liquid Glass Edge & Highlight
public struct LiquidGlassEdgeOverlay: View {
    public let cornerRadius: CGFloat

    /// 边缘高光强度系数（1.0 = 原始档位，0.0 = 完全不出轮廓）。
    ///
    /// 深色主题下顶部高光为白色 46%，在深色底上会形成一圈相当抢眼的浅色描边；
    /// 大尺寸面板（如分屏岛）尤其明显，可按场景下调直到只留一层极淡的厚度暗示。
    ///
    /// 注意：0.0 必须让**整条 rim** 归零（含底部黑色描边）。若底部暗边不受控，
    /// 「零轮廓」只是把上方的白边翻成了下方的黑边，视觉上仍是一道轮廓。
    public let rimIntensity: CGFloat

    /// 是否绘制第二道 inset 内描边。
    ///
    /// 这道内描边叠在外 rim 内侧，会在同一块表面上形成「框里还有一圈框」的套层观感；
    /// 收起态划词栏尺寸小、边缘占比高，套层最明显，故该场景关闭，只留一道顶光 rim。
    /// 大尺寸面板可保留：其 rimIntensity 为 0 时本层自然不可见。
    public let showsInsetSheen: Bool

    @Environment(\.colorScheme) var colorScheme

    public init(cornerRadius: CGFloat, rimIntensity: CGFloat = 1.0, showsInsetSheen: Bool = true) {
        self.cornerRadius = cornerRadius
        self.rimIntensity = rimIntensity
        self.showsInsetSheen = showsInsetSheen
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            // Primary Optical Rim: Overhead skylight specular highlight tapering to faint lateral refraction and soft bottom shadow rim
            .strokeBorder(
                LinearGradient(
                    stops: [
                        // 暗色主题下背景更暗，需要更强的白色高光才能在视觉上形成玻璃边缘的层次，
                        // 因此暗色档位高于亮色（而非等比例调低）。
                        // 注意：此档位仅在 rimIntensity == 1.0 时生效原值。
                        .init(color: Color.white.opacity((colorScheme == .dark ? 0.46 : 0.50) * rimIntensity), location: 0.0),
                        .init(color: Color.white.opacity((colorScheme == .dark ? 0.22 : 0.25) * rimIntensity), location: 0.15),
                        .init(color: Color.white.opacity((colorScheme == .dark ? 0.09 : 0.12) * rimIntensity), location: 0.70),
                        // 底部软阴影沿同样乘以 rimIntensity —— 它是一条真实的轮廓，不能豁免
                        .init(color: Color.black.opacity((colorScheme == .dark ? 0.18 : 0.06) * rimIntensity), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.65
            )
            // Secondary Inset Specular Sheen: Physical glass thickness simulation along upper rim
            .overlay(
                Group {
                    if showsInsetSheen {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .inset(by: 0.65)
                            .stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity((colorScheme == .dark ? 0.20 : 0.22) * rimIntensity), location: 0.0),
                                        .init(color: Color.clear, location: 0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.65
                            )
                    }
                }
            )
    }
}


// MARK: - Button Physics Styles (1.0 -> 0.97 -> 1.0)
public struct CommandBarActionButtonStyle: ButtonStyle {
    let isHovered: Bool

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.03 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

public struct PhysicsPressButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Unified View Model
public class UnifiedCommandBarViewModel: ObservableObject {
    /// 常驻内存的文本上限。
    ///
    /// 面板是常驻单例，一次会话里可以连续追问很多轮。旧实现里 outputText /
    /// reasoningText / history 都是无上限累积：一个跑飞的模型或几十轮追问就能
    /// 让这几个字符串涨到几十 MB 且永不释放。这里给每一处都设了天花板，
    /// 触顶后停止累积并留一句提示，而不是静默丢字。
    internal enum Capacity {
        /// 正文上限（约 1.5 万汉字）
        static let maxOutputChars = 64_000
        /// 思考过程上限（思考通常比正文长得多，但显示区更小）
        static let maxReasoningChars = 32_000
        /// 上下文保留的消息条数（user + assistant 成对，即 10 轮）
        static let maxHistoryMessages = 20
        /// 单条上下文消息上限，避免把整篇长文塞进下一轮请求
        static let maxHistoryMessageChars = 8_000
    }

    /// 触顶提示。用后缀兼作「已截断」标记，省掉一个需要到处重置的状态位。
    private static let truncationNotice = "\n…（内容过长，已停止累积以限制内存占用）"

    @Published public var displayMode: CommandBarDisplayMode = .collapsed
    /// 收起态浮条高度。由面板按当前屏幕的菜单栏高度动态下发，默认 38pt，
    /// 使 SwiftUI 内容布局与 NSPanel 实际高度保持一致。
    @Published public var collapsedBarHeight: CGFloat = 38
    /// 收起态胶囊宽度（含左右内边距）。窗口在展开时会整体加宽，但胶囊固定为此宽度
    /// 并在窗口内居中，因此顶部 Command Bar 的屏幕坐标在任何形态下都不发生横向位移。
    /// 0 表示尚未测量，此时由内容自然宽度决定。
    @Published public var collapsedBarWidth: CGFloat = 0
    @Published public var activeAction: ActionItem? = nil
    @Published public var sourceText: String = ""
    @Published public var currentPrompt: String = ""
    @Published public var outputText: String = ""
    @Published public var reasoningText: String = ""
    @Published public var isReasoningExpanded: Bool = true
    @Published public var hasAnswerStarted: Bool = false
    @Published public var hasNoAnswerNotice: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var isPinned: Bool = false
    @Published public var isCopied: Bool = false
    @Published public var followUpInput: String = ""
    @Published public var history: [ChatMessage] = []
    @Published public var selectedProfileId: String = ""
    @Published public var hoveredActionId: String? = nil

    /// 收起态复制按钮的 hover 状态。其圆底只在 hover / 已复制时出现，
    /// 静止态不留任何常驻容器 —— 玻璃上应当只有图标本身。
    ///
    /// 与 hoveredActionId 同源，放在 ViewModel 而非视图内 `@State`：
    /// 本项目由 CommandLineTools 的 swift-frontend 构建，只加载了
    /// ObservationMacros / SwiftMacros，**未加载 SwiftUIMacros**，
    /// 因此 `@State`（宏实现）无法展开，编译直接报 StateMacro not found。
    @Published public var isCopyHovered: Bool = false

    private var currentRequestId: UUID? = nil
    public private(set) var lastRequestedProfileId: String = ""

    /// 可注入的流式调用处理器（用于单元测试与确定性验证，为空时默认调用 LLMService.shared）
    internal var onStreamChat: ((
        _ systemPrompt: String,
        _ userContent: String,
        _ profile: LLMProfile?,
        _ history: [ChatMessage],
        _ onReasoning: ((String) -> Void)?,
        _ onToken: @escaping (String) -> Void,
        _ onComplete: @escaping (String) -> Void,
        _ onError: @escaping (Error) -> Void
    ) -> Void)? = nil

    public init() {
        let active = ConfigManager.shared.activeProfileId
        self.selectedProfileId = active
        self.lastRequestedProfileId = active
    }

    /// 解析某个动效应使用的模型：优先该动作绑定的专属模型；
    /// 未绑定、或绑定的模型已被删除时，回退到全局默认模型。
    private func resolveProfileId(for action: ActionItem?) -> String {
        if let preferred = action?.preferredProfileId,
           ConfigManager.shared.profiles.contains(where: { $0.id == preferred }) {
            return preferred
        }
        return ConfigManager.shared.activeProfileId
    }

    /// 停止当前流式生成并重置 requestId 守卫
    public func stopGenerating() {
        LLMService.shared.cancel()
        self.currentRequestId = nil
        self.isLoading = false
        if self.outputText.isEmpty && (self.activeAction != nil || !self.reasoningText.isEmpty) {
            self.hasNoAnswerNotice = true
        }
    }

    /// 重置状态机，取消当前请求并清空所有临时与输出数据
    public func resetState() {
        stopGenerating()
        self.outputText = ""
        self.reasoningText = ""
        self.history = []
        self.activeAction = nil
        self.sourceText = ""
        self.currentPrompt = ""
        self.followUpInput = ""
        self.errorMessage = nil
        self.isLoading = false
        self.hasAnswerStarted = false
        self.isReasoningExpanded = true
        self.hasNoAnswerNotice = false
        self.isPinned = false
        self.displayMode = .collapsed
    }

    /// 每轮新请求开始时重置思考区：回到展开态，等待新的思考流
    private func resetReasoning() {
        self.reasoningText = ""
        self.hasAnswerStarted = false
        self.isReasoningExpanded = true
    }

    /// 思考流：追加到思考区。答案尚未开始时保持展开，让用户看到实时推理过程
    private func appendReasoning(_ token: String) {
        guard !reasoningText.hasSuffix(Self.truncationNotice) else { return }
        self.reasoningText += token
        if reasoningText.count > Capacity.maxReasoningChars {
            reasoningText += Self.truncationNotice
        }
        if !self.hasAnswerStarted {
            self.isReasoningExpanded = true
        }
    }

    /// 答案流：首个答案 token 到达时自动折叠思考区，之后只累积正文
    private func appendAnswer(_ token: String) {
        if !self.hasAnswerStarted {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.hasAnswerStarted = true
                self.isReasoningExpanded = false
            }
        }
        guard !outputText.hasSuffix(Self.truncationNotice) else { return }
        self.outputText += token
        if outputText.count > Capacity.maxOutputChars {
            outputText += Self.truncationNotice
        }
    }

    /// 按上限裁剪文本，尾部保留省略提示
    private static func clipped(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…（已省略 \(text.count - limit) 字）"
    }

    /// 把本轮问答并入上下文，并裁剪到容量上限：
    /// 先按条数丢最老的对，再限制单条长度。
    private func commitHistory(prompt: String, answer: String) {
        history.append(ChatMessage(role: "user", content: Self.clipped(prompt, limit: Capacity.maxHistoryMessageChars)))
        history.append(ChatMessage(role: "assistant", content: Self.clipped(answer, limit: Capacity.maxHistoryMessageChars)))

        let excess = history.count - Capacity.maxHistoryMessages
        guard excess > 0 else { return }
        // 消息是 user/assistant 成对入列的，只丢偶数条才能保持配对不错位
        let drop = excess % 2 == 0 ? excess : excess + 1
        history.removeFirst(min(drop, history.count))
    }

    public func startAction(text: String, action: ActionItem) {
        self.sourceText = text
        self.currentPrompt = text
        self.activeAction = action
        self.outputText = ""
        self.isLoading = true
        self.errorMessage = nil
        self.hasNoAnswerNotice = false
        self.isCopied = false
        self.followUpInput = ""
        self.history = []
        self.selectedProfileId = self.resolveProfileId(for: action)
        self.lastRequestedProfileId = self.selectedProfileId
        self.resetReasoning()

        requestLLM()
    }

    public func switchAction(_ action: ActionItem) {
        self.activeAction = action
        self.currentPrompt = self.sourceText
        self.outputText = ""
        self.isLoading = true
        self.errorMessage = nil
        self.hasNoAnswerNotice = false
        self.history = []
        self.selectedProfileId = self.resolveProfileId(for: action)
        self.lastRequestedProfileId = self.selectedProfileId
        self.resetReasoning()

        requestLLM()
    }

    public func retryCurrent() {
        self.outputText = ""
        self.isLoading = true
        self.errorMessage = nil
        self.hasNoAnswerNotice = false
        self.resetReasoning()
        self.lastRequestedProfileId = self.selectedProfileId
        requestLLM()
    }

    public func sendFollowUp() {
        let question = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, activeAction != nil else { return }

        if !outputText.isEmpty {
            commitHistory(prompt: currentPrompt, answer: outputText)
        }

        self.currentPrompt = question
        followUpInput = ""
        isLoading = true
        errorMessage = nil
        outputText = ""
        hasNoAnswerNotice = false
        resetReasoning()
        self.lastRequestedProfileId = self.selectedProfileId

        requestLLM()
    }

    private func requestLLM() {
        guard let action = activeAction else { return }
        let profile = ConfigManager.shared.profiles.first(where: { $0.id == selectedProfileId }) ?? ConfigManager.shared.activeProfile

        let requestId = UUID()
        self.currentRequestId = requestId

        if let customStream = onStreamChat {
            customStream(
                action.prompt,
                currentPrompt,
                profile,
                history,
                { [weak self] token in
                    guard let self = self, self.currentRequestId == requestId else { return }
                    self.appendReasoning(token)
                },
                { [weak self] token in
                    guard let self = self, self.currentRequestId == requestId else { return }
                    self.appendAnswer(token)
                },
                { [weak self] fullText in
                    guard let self = self, self.currentRequestId == requestId else { return }
                    self.isLoading = false
                    if self.outputText.isEmpty {
                        self.hasNoAnswerNotice = true
                    }
                },
                { [weak self] error in
                    guard let self = self, self.currentRequestId == requestId else { return }
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            )
            return
        }

        LLMService.shared.streamChat(
            systemPrompt: action.prompt,
            userContent: currentPrompt,
            profile: profile,
            history: history,
            onReasoning: { [weak self] token in
                guard let self = self, self.currentRequestId == requestId else { return }
                self.appendReasoning(token)
            },
            onToken: { [weak self] token in
                guard let self = self, self.currentRequestId == requestId else { return }
                self.appendAnswer(token)
            },
            onComplete: { [weak self] fullText in
                guard let self = self, self.currentRequestId == requestId else { return }
                self.isLoading = false
                if self.outputText.isEmpty {
                    self.hasNoAnswerNotice = true
                }
            },
            onError: { [weak self] error in
                guard let self = self, self.currentRequestId == requestId else { return }
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        )
    }

    public func copyOutput() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(outputText, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isCopied = false
        }
    }
}

// MARK: - Unified Liquid Glass Container View
public struct UnifiedCommandBarContainerView: View {
    @ObservedObject public var config = ConfigManager.shared
    @ObservedObject public var viewModel: UnifiedCommandBarViewModel
    @Environment(\.colorScheme) var colorScheme

    public let onSelectAction: (ActionItem) -> Void
    public let onCopy: () -> Void
    public let onCollapse: () -> Void
    public let onClose: () -> Void

    public init(
        viewModel: UnifiedCommandBarViewModel,
        onSelectAction: @escaping (ActionItem) -> Void,
        onCopy: @escaping () -> Void,
        onCollapse: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onSelectAction = onSelectAction
        self.onCopy = onCopy
        self.onCollapse = onCollapse
        self.onClose = onClose
    }

    private var currentCornerRadius: CGFloat {
        viewModel.displayMode == .collapsed ? (viewModel.collapsedBarHeight / 2) : 22.0
    }

    /// 玻璃表面主题基底的不透明度。
    ///
    /// **这层纱是「看起来像磨砂塑料」的头号原因**：它把系统玻璃的输出直接按比例替换成
    /// 一块平面的主题色。0.50 意味着**一半的折射被抹掉**——玻璃再通透，露出来的也只有一半。
    ///
    /// 它为什么存在：系统玻璃（NSGlassEffectView / NSVisualEffectView + .behindWindow）
    /// 会采样窗口背后的真实颜色。全屏时顶部菜单栏渲染为纯黑，玻璃随之变黑，而文字颜色
    /// 取自系统主题（浅色主题 = 黑字），形成黑吃黑，实测对比度仅 1.2:1。
    /// 这层基底把表面亮度锚定回主题，使文字对比度不再随背景漂移。
    /// **这是一个真实缺陷的修复，不能为了好看而直接删掉。**
    ///
    /// 档位沿革：
    /// - 0.70 / 0.76 —— 早期版本，按「纯黑背景下黑字仍约 6.8:1」标定，玻璃几乎被盖成平板
    /// - 0.50 / 0.54 —— 上一轮下调，透过率 30% → 50%
    /// - **0.30 / 0.36 —— 本轮**，透过率提升到约 65~70%，让折射真正成为主导
    ///
    /// 取舍：纱越薄越「液态」，但全屏纯黑底图上的文字对比度余量也越小。
    /// 这一档是按「保留全屏下限、同时让折射可感知」取的平衡点，**不是**能一路下探到 0 ——
    /// 分屏岛的 0.10 / 0.20 不能平移过来，岛浮在屏幕中央对着壁纸，栏是贴在菜单栏色带里的。
    ///
    /// 注意：玻璃的实际透出效果**无法在本机自证** —— `cacheDisplay` 采不到
    /// `.behindWindow` 的混合结果，`screencapture` 又受屏幕录制权限限制。
    /// 因此本档位必须靠肉眼验收：重点在**全屏 App 下文字是否仍清晰**。
    private var surfaceScrimOpacity: Double {
        colorScheme == .dark ? 0.36 : 0.30
    }

    public var body: some View {
        // ⚠️ 这里**不能**用 VStack 纵向串起「顶栏 + 结果区」，必须是 ZStack(alignment: .top)。
        //
        // 原因：SwiftUI 的 VStack 在「子视图总高 > 可用高度」时，会把溢出量**上下均分**
        // （与 frame 对超尺寸子视图的处理同源）。展开动画的头一段（窗口高 38 → 约 107pt，
        // 展开态内容的最小总高）正好落在这个区间，顶栏会被整体推到窗口上方裁掉，
        // 屏幕上只剩结果卡片的模型选择器 —— 实测 /tmp/anim2_D_expanded_h38.png。
        // 用 ZStack 贴合顶部后：顶栏永远贴顶；结果区从栏下方开始，
        // 高度不足时向**下**溢出被裁 —— 与「面板向下展开」的心智一致。
        //
        // 收起态 ZStack 里只有顶栏（38pt），由外层 frame 的 .top 对齐钉在顶部，
        // 因此收起动画全程文字零位移（实测 F 系列：宿主高 38~390 全部 yFromTop=19.0）。
        ZStack(alignment: .top) {
            // MARK: Level 1 - Top Command Bar Area (Visual Nucleus & Notch Anchor)
            HStack(spacing: 6) {
                Spacer(minLength: 0)

                // Action Buttons: Subtle Glass Highlight + Accent Tint (no solid blue capsule)
                ForEach(config.actions.filter { $0.isEnabled }) { action in
                    let isCurrentActive = (viewModel.displayMode == .expanded && viewModel.activeAction?.id == action.id)
                    let isHovered = (viewModel.hoveredActionId == action.id)

                    Button(action: {
                        if viewModel.displayMode == .expanded && action.type != .search {
                            viewModel.switchAction(action)
                        } else {
                            onSelectAction(action)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: action.icon)
                                .font(.system(size: 12, weight: isCurrentActive ? .semibold : .medium))
                                .foregroundColor(isCurrentActive ? .accentColor : .primary.opacity(isHovered ? 0.95 : 0.72))

                            Text(action.title)
                                .font(.system(size: 12, weight: isCurrentActive ? .semibold : .medium))
                                .foregroundColor(isCurrentActive ? .accentColor : .primary.opacity(isHovered ? 0.95 : 0.72))
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Group {
                                if isCurrentActive {
                                    // 玻璃局部染色：只留柔和的 accent 亮斑，不描边。
                                    // 一道圆形描边会在玻璃内部重新画出一个小容器，正是套层感的来源。
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                                    Color.accentColor.opacity(colorScheme == .dark ? 0.05 : 0.03)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                } else if isHovered {
                                    // Localized glass illumination sheen（同样只留亮斑，不描边）
                                    Capsule()
                                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18))
                                } else {
                                    Color.clear
                                }
                            }
                        )
                    }
                    .buttonStyle(CommandBarActionButtonStyle(isHovered: isHovered))
                    .onHover { hovered in
                        viewModel.hoveredActionId = hovered ? action.id : nil
                    }
                }

                // 原 Optical Glass Slit Separator 已移除：
                // 这道竖线把「一块玻璃 + 图标」拉回「工具栏 / 分段控件」的心智，且 0.75pt
                // 宽度上渲染三段渐变实际只会读成一根灰线。动作组与复制按钮的区分
                // 改由 HStack 自身间距承担。
                if viewModel.displayMode == .collapsed {
                    // Quick Copy Icon in Collapsed Mode
                    // 复制确认直接由「图标自身」表达（变成绿色对勾），**不往胶囊里插文字**：
                    // 收起态胶囊仅 28pt 高、宽度紧贴内容，插入文字必然要么撑开整行、要么压住相邻按钮。
                    // 固定 13pt 见方 —— 保证「文档图标 ↔ 对勾」换形时行宽不变，按钮不发生横移。
                    Button(action: onCopy) {
                        Image(systemName: viewModel.isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(viewModel.isCopied ? .green : .primary.opacity(0.72))
                            .frame(width: 13, height: 12)
                            .padding(5)
                            .background(
                                Circle()
                                    .fill(
                                        viewModel.isCopied
                                            ? Color.green.opacity(0.14)
                                            : (viewModel.isCopyHovered
                                                ? Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
                                                : Color.clear)
                                    )
                            )
                    }
                    .buttonStyle(PhysicsPressButtonStyle())
                    .onHover { viewModel.isCopyHovered = $0 }
                    .help("复制选中文本")
                } else {
                    // Controls in Expanded Mode
                    // Pin
                    Button(action: { viewModel.isPinned.toggle() }) {
                        Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(viewModel.isPinned ? .accentColor : .primary.opacity(0.65))
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(viewModel.isPinned ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
                            )
                    }
                    .buttonStyle(PhysicsPressButtonStyle())
                    .help(viewModel.isPinned ? "取消固定" : "固定窗口")

                    // Collapse
                    Button(action: onCollapse) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.65))
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                    .buttonStyle(PhysicsPressButtonStyle())
                    .help("收起结果")

                    // Close
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary.opacity(0.65))
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.04))
                            )
                    }
                    .buttonStyle(PhysicsPressButtonStyle())
                    .help("关闭 (ESC)")
                }

                Spacer(minLength: 0)
            }
            // 宽度仅在「展开态」固定为收起态胶囊宽度：
            // 展开时窗口整体加宽，胶囊需在窗口内保持原宽，动作按钮的屏幕坐标才不会横向位移。
            // 收起态必须放开宽度约束 —— show() 是在收起态读取 fittingSize 来重新适配宽度的，
            // 若此时仍被上一次记录的宽度钉住，测量只会得到同一个值（自我锁定），
            // 导致动作列表变化（启用/停用/新增/删除）后胶囊宽度永远不再跟随内容。
            //
            // `alignment: .leading` 是「文字不横移」的关键，必须有：
            // 右侧控件区在两态下宽度不同 —— 收起态只有 1 个复制按钮（23pt），
            // 展开态是 固定/收起/关闭 3 个（72pt）。若让这一行**整体居中**，
            // 组宽一变大（+49pt）左侧动作组就被对称推左 24.5pt，
            // 实测 12 段动作文字全部 Δx = −24.00pt（见 /tmp/snapprobe 的 AnimProbe）。
            // 改成左对齐后：动作组钉在本行左边缘 = 胶囊内容左边缘（两态同一点），
            // 展开态多出来的 49pt 全部向右溢出到窗口留白里。
            // 收起态宽度为 nil（无富余空间），左对齐与居中完全等价，外观零变化。
            .frame(
                width: (viewModel.displayMode == .expanded && viewModel.collapsedBarWidth > 0)
                    ? max(0, viewModel.collapsedBarWidth - 20)
                    : nil,
                height: viewModel.collapsedBarHeight,
                alignment: .leading
            )
            .padding(.horizontal, 10)

            // MARK: Expandable Content Area (Floating Sub-Surfaces inside Glass Vessel)
            //
            // ⚠️ 结果区**不能**再作为 ZStack 的直接子视图。
            //
            // 原因：ZStack 的尺寸是所有子视图的**并集**。结果区最小总高约
            // 38(顶栏) + 39(卡片最小) + 8 + 33(追问胶囊) ≈ 118pt，一旦它成为直接子视图，
            // ZStack 就有 118pt 高；而展开动画开头窗口还只有 38~118pt。
            // SwiftUI 在「父容器比子视图矮」时会把溢出量**上下均分**（居中对齐），
            // 顶栏会被整体推到窗口上方裁掉 —— 实测 /tmp/anim2_D_expanded_h38.png
            // 里屏幕上只剩结果卡片的模型选择器，顶栏完全消失；h=100 时顶栏文字
            // 也已上飘到「顶边下方 9.8pt」（正确值 19.0）。
            //
            // 解法：插一个**零最小高度的「高度接收器」**（`Color.clear` 接受任何提议尺寸，
            // 最小可到 0），它保证 ZStack 的高度恒等于窗口高度、永不溢出；
            // 结果区则挂到它的 `background` 上 —— background 不参与父视图尺寸计算，
            // 所以结果区再高也顶不走顶栏，只会向**下**溢出被窗口裁掉。
            //
            // 用 LayoutLab（/tmp/snapprobe）对 5 种结构 × 7 个高度做过对照：
            //   直接 VStack / ZStack(.top) / VStack+尾部Spacer —— 窗口高 < 内容最小高时
            //   顶栏都会被推离原位；只有「零最小高度接收器」与「GeometryReader 显式高」
            //   能在窗口高 20~120pt 全程把顶栏钉在顶边。此处选前者（不改动高度计算）。
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(alignment: .top) {
                    if viewModel.displayMode == .expanded {
                    VStack(spacing: 8) {
                        // MARK: Level 2 & 3 - Floating AI Result Workspace Surface
                        // High-contrast, stable canvas for text readability with embedded auxiliary metadata control
                        VStack(spacing: 0) {
                            // Integrated Auxiliary Metadata Header (Embedded metadata strip, zero 1px hard lines)
                            HStack(spacing: 6) {
                                if let act = viewModel.activeAction {
                                    HStack(spacing: 4) {
                                        Image(systemName: act.icon)
                                            .font(.system(size: 10, weight: .medium))
                                        Text(act.title)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                                    )
                                }

                                // Model Selector (Auxiliary Glass Menu)
                                Menu {
                                    ForEach(config.profiles) { p in
                                        Button(action: {
                                            if viewModel.selectedProfileId != p.id {
                                                viewModel.selectedProfileId = p.id
                                                viewModel.retryCurrent()
                                            }
                                        }) {
                                            HStack {
                                                Text(p.name)
                                                if viewModel.selectedProfileId == p.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        let currentName = config.profiles.first(where: { $0.id == viewModel.selectedProfileId })?.name ?? "默认模型"
                                        Text(currentName)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                                    )
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()

                                Spacer()

                                // Quick Copy Button
                                Button(action: { viewModel.copyOutput() }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: viewModel.isCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                        if viewModel.isCopied {
                                            Text("已复制").font(.system(size: 10, weight: .medium))
                                        }
                                    }
                                    .foregroundColor(viewModel.isCopied ? .green : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(
                                        Capsule()
                                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04))
                                    )
                                }
                                .buttonStyle(PhysicsPressButtonStyle())
                                .disabled(viewModel.outputText.isEmpty)
                                .help("复制结果")
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 7)
                            .padding(.bottom, 5)

                            // Reading Canvas (High-contrast, stable surface for text readability)
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Reasoning process block
                                    if !viewModel.reasoningText.isEmpty {
                                        ReasoningBlockView(
                                            text: viewModel.reasoningText,
                                            isExpanded: $viewModel.isReasoningExpanded,
                                            isStreaming: viewModel.isLoading && !viewModel.hasAnswerStarted
                                        )
                                    }

                                    if let error = viewModel.errorMessage {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.orange)
                                                Text("请求失败")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            Text(error)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                            Button("点击重试") {
                                                viewModel.retryCurrent()
                                            }
                                            .buttonStyle(PhysicsPressButtonStyle())
                                            .controlSize(.small)
                                        }
                                        .padding(12)
                                    } else if !viewModel.outputText.isEmpty {
                                        Text(viewModel.outputText)
                                            .font(.system(size: 13, weight: .regular))
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, viewModel.reasoningText.isEmpty ? 8 : 4)
                                    } else if viewModel.hasNoAnswerNotice {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "info.circle")
                                                    .foregroundColor(.orange)
                                                Text("模型未返回最终答复")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.secondary)
                                            }
                                            Button("重新生成") {
                                                viewModel.retryCurrent()
                                            }
                                            .buttonStyle(PhysicsPressButtonStyle())
                                            .controlSize(.small)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, viewModel.reasoningText.isEmpty ? 8 : 4)
                                    } else if viewModel.isLoading {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text(viewModel.reasoningText.isEmpty ? "正在生成结果..." : "正在组织答案...")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, viewModel.reasoningText.isEmpty ? 12 : 6)
                                    }
                                }
                                .padding(.bottom, 6)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor).opacity(colorScheme == .dark ? 0.18 : 0.32))
                        )
                        .overlay(
                            // Directional rim（上亮下暗）：
                            // 上缘亮高光把卡片从「比它暗」的背景里托出来，
                            // 下缘暗缘把卡片从「比它亮」的背景里切出来。
                            // 两端同时覆盖 ⇒ 分离不再依赖卡片与容器的明暗差 Δ，
                            // 背景怎么漂移都不影响层级可辨。（Δ 本身仍会漂移，这是故意的取舍。）
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.36 : 0.42), location: 0.0),
                                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.18 : 0.20), location: 0.16),
                                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08), location: 0.72),
                                            .init(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.10), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .padding(.horizontal, 11)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // MARK: Level 4 - Floating Glass Input Surface (Floating Pill)
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.6))

                            TextField("对此内容继续追问...", text: $viewModel.followUpInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .onSubmit {
                                    viewModel.sendFollowUp()
                                }

                            if viewModel.isLoading {
                                Button(action: {
                                    viewModel.stopGenerating()
                                }) {
                                    Image(systemName: "stop.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.red.opacity(0.9))
                                }
                                .buttonStyle(PhysicsPressButtonStyle())
                                .help("停止生成")
                            } else {
                                Button(action: {
                                    viewModel.sendFollowUp()
                                }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(viewModel.followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.35) : .accentColor)
                                }
                                .buttonStyle(PhysicsPressButtonStyle())
                                .disabled(viewModel.followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .help("发送追问 (Enter)")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(NSColor.controlBackgroundColor).opacity(colorScheme == .dark ? 0.30 : 0.45))
                        )
                        .overlay(
                            // 与内容卡片共用同一套 rim 参数：同为「容器内的表面」，边缘语言必须一致。
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.36 : 0.42), location: 0.0),
                                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.18 : 0.20), location: 0.16),
                                            .init(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08), location: 0.72),
                                            .init(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.10), location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.6
                                )
                        )
                        .padding(.horizontal, 11)
                        .padding(.bottom, 9)
                    }
                    // 结果区从顶栏下方开始。ZStack 里两个子视图是叠放的，
                    // 必须显式让出一个栏高，否则结果卡片会盖住顶栏。
                    .padding(.top, viewModel.collapsedBarHeight)
                    // 退场时让内容**先淡出**，而不是随窗口收缩被裁切。
                    // 缺少这一步时 displayMode 的切换是一次硬切，读者会看到结果区
                    // 凭空消失、只剩一块空玻璃慢慢收起 —— 两个动作接不上。
                    // 有了它，内容在 0.12s 内干净退场，其后的收缩露出的始终是空玻璃。
                    .transition(.opacity)
                    }
                }
        }
        // `alignment: .top` 是「文字不竖移」的关键，必须有：
        // 收起态 ZStack 里只有顶栏一个子视图，内容总高 = 38pt，而窗口高度在收起动画的
        // 整段时间里仍是「展开态的高」（从 390 一路缩到 38）。默认居中对齐会把这 38pt 的
        // 顶栏放进 390pt 窗口的**正中间**，于是文字要从面板中部向上滑约 176pt ——
        // 实测：收起态宿主高 390 时，栏内文字位于「顶边下方 195pt」（AnimProbe F 系列）。
        // 展开态 ZStack 会被结果区撑满整个窗口高度，此时该对齐参数不产生任何影响，
        // 因此展开态布局逐像素不变（实测 h=120~390 全部落在 yFromTop=19.0）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Unified Liquid Glass Vessel Surface
        .background(
            ZStack {
                // 底层：系统玻璃，负责采样背景的模糊与折射质感
                // effectIsInteractive：玻璃承载着一排按钮，正是 Apple 头文件里
                // 「glass used as the background for interactive controls」的场景。
                NativeLiquidGlassView(
                    cornerRadius: currentCornerRadius,
                    style: .regular,
                    effectIsInteractive: true
                )
                // 上层：主题基底色，把表面亮度锚定到当前主题，
                // 避免全屏时背后菜单栏变黑导致表面变黑、文字却仍是主题深色
                Color(nsColor: .windowBackgroundColor)
                    .opacity(surfaceScrimOpacity)
            }
            .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        )
        // Optical Specular Rim —— 本轮**整体关闭**（rimIntensity 0）。
        //
        // 原先这里画着一道 4 段渐变的手绘顶光 rim（强度 1.0，用的是构造器默认值，
        // 并非当初显式选择）。它和 inset 内描边叠在一起时是套层感的直接来源；
        // 而更根本的问题在于：**真实的 Liquid Glass 自带边缘高光与镜面折射**，
        // 在它上面再描一圈，等于用手绘的假光替代系统给的材质光。
        //
        // 分屏岛已经先做过这一步（rimIntensity 0.0），肉眼验收通过；
        // 本次把栏对齐到同一档，两个面板共用「只留系统材质边缘」这一套语言。
        //
        // 保留该 overlay 调用（强度 0）是为了让「以后想加回一道很淡的 rim」只需改一个数，
        // 而不是重新翻出这整段实现。
        .overlay(
            LiquidGlassEdgeOverlay(
                cornerRadius: currentCornerRadius,
                rimIntensity: 0.0,
                showsInsetSheen: false
            )
        )
        // Atmospheric Elevation Shadow —— 已整个移除，不是调小。
        //
        // 原实现在此叠了两层 .shadow（radius 14 + radius 2）。问题出在它们的挂载点：
        // 该修饰符作用在上方 .frame(maxWidth: .infinity, maxHeight: .infinity) 的**矩形**栈上，
        // 而栈内含 NSGlassEffectView 这个 NSViewRepresentable —— SwiftUI 取不到 AppKit 视图
        // 的真实 alpha 轮廓来求投影，投影于是退化成视图 bounds（矩形）。
        // 结果：一圈方角暗影套在胶囊外面，与圆角玻璃边缘互相打架。
        // 收起态高度仅一个菜单栏，方角与胶囊的错位尤其刺眼，故肉眼可见为「最外层矩形框」。
        //
        // 注意：只要 shadow 留在含 representable 的矩形栈上，调小半径只会减弱而不会消除方角，
        // 因此这里必须整体移除。浮起感改由玻璃自身的折射与那一道顶光 rim 承担。
    }
}

// MARK: - Reasoning Block (思考过程折叠区)
/// 展示模型的思考过程：思考期间实时展开，答案开始后自动折叠为一条摘要，用户可点击随时回看。
private struct ReasoningBlockView: View {
    let text: String
    @Binding var isExpanded: Bool
    let isStreaming: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))

                    if isStreaming {
                        Text("正在思考…")
                    } else {
                        Text("已思考 \(text.count) 字")
                    }

                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(PhysicsPressButtonStyle())
            .help(isExpanded ? "收起思考过程" : "展开思考过程")

            if isExpanded {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.035))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

