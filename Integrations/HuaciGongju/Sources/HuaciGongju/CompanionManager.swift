//
//  CompanionManager.swift
//  HuaciGongju
//
//  桌宠码头：巡逻、停稳接手、跳屏、出条。出厂不启动。
//

import Cocoa
import ApplicationServices

public class CompanionManager {
    public static let shared = CompanionManager()

    public private(set) var isMonitoring: Bool = false
    public private(set) var currentEdge: CompanionEdge = .right
    public private(set) var isCaptured: Bool = false
    public private(set) var lastSelectedText: String = ""

    private var patrolTimer: Timer?
    private var dwellTimer: Timer?
    private var leaveTimer: Timer?
    private var autoBarTimer: Timer?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?

    private var homes: [CGDirectDisplayID: CompanionGeometry.PatrolState] = [:]
    private var lastPatrolTime: TimeInterval = 0
    private var shellsPinned = false
    private var isHiddenForFullscreen = false

    private init() {}

    public var isPatrolling: Bool { patrolTimer != nil && !isCaptured && !shellsPinned }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isHiddenForFullscreen = false
        // Ghost 条不能留在菜单栏：Presence 互斥，切到桌宠立刻硬切。
        TransientCommandBarPanel.safeShared?.dismissImmediately()
        SelectionMonitor.shared.log("CompanionManager started")

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let center = CompanionGeometry.spawnCenter(in: screen.visibleFrame)
        currentEdge = .right
        homes[screen.displayID] = CompanionGeometry.PatrolState(center: center, edge: .right)

        let panel = CompanionPetPanel.shared
        bindPanelActions(panel)
        panel.present(at: center)
        panel.setClickThrough(true)
        isCaptured = false

        installMonitors()
        startPatrol()
        evaluateFullscreenPresence()
    }

    public func stop() {
        let wasMonitoring = isMonitoring
        isMonitoring = false
        tearDownMonitors()
        stopPatrol()
        cancelDwell()
        cancelLeave()
        cancelAutoBar()
        shellsPinned = false
        isCaptured = false
        isHiddenForFullscreen = false
        lastSelectedText = ""
        hardCutOpenShells()
        CompanionPetPanel.safeShared?.hide()
        if wasMonitoring {
            SelectionMonitor.shared.log("CompanionManager stopped")
        }
    }

    /// 关桌宠立刻收掉开着的条 / 泡泡 / 岛，不把条传送回菜单栏。
    public func hardCutOpenShells() {
        CompanionChatBubblePanel.safeShared?.hide()
        TransientCommandBarPanel.safeShared?.dismissImmediately()
        WindowSnapIslandPanel.safeShared?.hide()
        GhostPreviewPanel.safeShared?.hide()
        shellsPinned = false
    }

    public func handleSelection(_ text: String, at screenPoint: NSPoint) {
        lastSelectedText = text
        let screen = resolveScreen(for: screenPoint)
        jump(to: screen, near: screenPoint, writeHome: true)
        CompanionPetPanel.safeShared?.playExpression(.glance)

        cancelAutoBar()
        guard ConfigManager.shared.autoShowToolbar else { return }
        autoBarTimer = Timer.scheduledTimer(
            withTimeInterval: CompanionGeometry.autoBarDelay,
            repeats: false
        ) { [weak self] _ in
            self?.openBar()
        }
        if let timer = autoBarTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func handleWindowCenterMoved(_ windowCenter: CGPoint, cursor: CGPoint) {
        guard isMonitoring, !isHiddenForFullscreen else { return }
        let currentScreen = resolveScreen(for: CompanionPetPanel.safeShared?.petCenter ?? windowCenter)
        guard CompanionGeometry.shouldJumpScreen(
            windowCenter: windowCenter,
            currentScreenFrame: currentScreen.frame
        ) else { return }
        let nextScreen = resolveScreen(for: windowCenter)
        jump(to: nextScreen, near: cursor, writeHome: true)
    }

    // MARK: - Presence

    private func installMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.handleCursorMoved(NSEvent.mouseLocation)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleCursorMoved(NSEvent.mouseLocation)
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreensChanged()
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateFullscreenPresence()
        }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluateFullscreenPresence()
        }
    }

    private func tearDownMonitors() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o); screenObserver = nil }
        if let o = spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); spaceObserver = nil }
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); appObserver = nil }
    }

    private func bindPanelActions(_ panel: CompanionPetPanel) {
        panel.onSingleClick = { [weak self] in
            self?.handlePetClick(.single)
        }
        panel.onDoubleClick = { [weak self] in
            self?.handlePetClick(.double)
        }
        panel.onLongPress = { [weak self] in
            self?.handlePetClick(.longPress)
        }
        panel.onDragMoved = { [weak self] loc in
            self?.stopPatrol()
            self?.cancelDwell()
            self?.cancelLeave()
            CompanionChatBubblePanel.safeShared?.hide()
            TransientCommandBarPanel.safeShared?.dismiss()
            self?.shellsPinned = false
            self?.currentEdge = CompanionGeometry.nearestEdge(
                to: loc,
                in: self?.resolveScreen(for: loc).visibleFrame ?? .zero
            )
        }
        panel.onDragEnded = { [weak self] loc in
            self?.snapDragEnded(at: loc)
        }
    }

    private func handlePetClick(_ kind: CompanionClickKind) {
        let action = CompanionInteraction.action(for: kind, hasSelection: !lastSelectedText.isEmpty)
        switch action {
        case .expression:
            CompanionPetPanel.shared.playExpression(.glance)
        case .openBar:
            openBar()
        case .chatBubble:
            toggleChatBubble()
        }
    }

    // MARK: - Patrol / dwell

    private func startPatrol() {
        guard isMonitoring, !isCaptured, !shellsPinned, !isHiddenForFullscreen else { return }
        CompanionPetPanel.safeShared?.setClickThrough(true)
        lastPatrolTime = Date().timeIntervalSince1970
        patrolTimer?.invalidate()
        patrolTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tickPatrol()
        }
        if let timer = patrolTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopPatrol() {
        patrolTimer?.invalidate()
        patrolTimer = nil
    }

    private func tickPatrol() {
        guard let panel = CompanionPetPanel.safeShared, panel.isVisible else { return }
        let now = Date().timeIntervalSince1970
        let dt = now - lastPatrolTime
        lastPatrolTime = now
        let screen = resolveScreen(for: panel.petCenter)
        let next = CompanionGeometry.patrolStep(
            state: CompanionGeometry.PatrolState(center: panel.petCenter, edge: currentEdge),
            visibleFrame: screen.visibleFrame,
            dt: dt
        )
        currentEdge = next.edge
        panel.move(to: next.center)
        homes[screen.displayID] = next
    }

    private func handleCursorMoved(_ location: NSPoint) {
        guard isMonitoring, let panel = CompanionPetPanel.safeShared, panel.isVisible else { return }
        let hit = CompanionGeometry.hitFrame(center: panel.petCenter)
        if hit.contains(location) {
            cancelLeave()
            if !isCaptured && dwellTimer == nil {
                dwellTimer = Timer.scheduledTimer(
                    withTimeInterval: CompanionGeometry.dwellDuration,
                    repeats: false
                ) { [weak self] _ in
                    self?.capture()
                }
                if let timer = dwellTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        } else {
            cancelDwell()
            if isCaptured && !shellsPinned && leaveTimer == nil {
                leaveTimer = Timer.scheduledTimer(
                    withTimeInterval: CompanionGeometry.leaveDuration,
                    repeats: false
                ) { [weak self] _ in
                    self?.releaseCapture()
                }
                if let timer = leaveTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
        }
    }

    private func capture() {
        dwellTimer = nil
        isCaptured = true
        stopPatrol()
        CompanionPetPanel.safeShared?.setClickThrough(false)
    }

    private func releaseCapture() {
        leaveTimer = nil
        isCaptured = false
        startPatrol()
    }

    private func cancelDwell() {
        dwellTimer?.invalidate()
        dwellTimer = nil
    }

    private func cancelLeave() {
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    private func cancelAutoBar() {
        autoBarTimer?.invalidate()
        autoBarTimer = nil
    }

    // MARK: - Jump / snap / unplug

    private func jump(to screen: NSScreen, near point: CGPoint, writeHome: Bool) {
        let snapped = CompanionGeometry.snapToNearestEdge(point, in: screen.visibleFrame)
        currentEdge = snapped.edge
        if writeHome {
            homes[screen.displayID] = CompanionGeometry.PatrolState(center: snapped.center, edge: snapped.edge)
        }
        CompanionPetPanel.shared.present(at: snapped.center)
        if shellsPinned {
            CompanionPetPanel.shared.setClickThrough(false)
        }
    }

    private func snapDragEnded(at location: NSPoint) {
        let screen = resolveScreen(for: location)
        let snapped = CompanionGeometry.snapToNearestEdge(location, in: screen.visibleFrame)
        currentEdge = snapped.edge
        homes[screen.displayID] = CompanionGeometry.PatrolState(center: snapped.center, edge: snapped.edge)
        CompanionPetPanel.shared.move(to: snapped.center)
        isCaptured = true
        CompanionPetPanel.shared.setClickThrough(false)
        startLeaveCountdown()
    }

    private func startLeaveCountdown() {
        cancelLeave()
        leaveTimer = Timer.scheduledTimer(
            withTimeInterval: CompanionGeometry.leaveDuration,
            repeats: false
        ) { [weak self] _ in
            self?.releaseCapture()
        }
        if let timer = leaveTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func handleScreensChanged() {
        evaluateFullscreenPresence()
        guard let panel = CompanionPetPanel.safeShared, panel.isVisible else { return }
        let remaining = NSScreen.screens.map(\.visibleFrame)
        if remaining.contains(where: { $0.contains(panel.petCenter) }) {
            return
        }
        guard let relocated = CompanionGeometry.relocateAfterUnplug(
            previousCenter: panel.petCenter,
            remainingVisibleFrames: remaining
        ) else { return }
        currentEdge = relocated.edge
        panel.move(to: relocated.center)
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(relocated.center) }) {
            homes[screen.displayID] = CompanionGeometry.PatrolState(center: relocated.center, edge: relocated.edge)
        }
    }

    private func evaluateFullscreenPresence() {
        guard isMonitoring else { return }
        let fullscreen = isFrontmostAppFullscreen()
        if fullscreen && !isHiddenForFullscreen {
            isHiddenForFullscreen = true
            stopPatrol()
            hardCutOpenShells()
            CompanionPetPanel.safeShared?.hide()
        } else if !fullscreen && isHiddenForFullscreen {
            isHiddenForFullscreen = false
            restorePet()
        }
    }

    private func restorePet() {
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let state = homes[screen.displayID] ?? CompanionGeometry.PatrolState(
            center: CompanionGeometry.spawnCenter(in: screen.visibleFrame),
            edge: .right
        )
        currentEdge = state.edge
        CompanionPetPanel.shared.present(at: state.center)
        isCaptured = false
        startPatrol()
    }

    private func isFrontmostAppFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if app.bundleIdentifier == "com.jackdu.huacigongju" { return false }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowVal) == .success,
              let window = AXCast.element(windowVal) else {
            return false
        }
        var fullVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullVal) == .success,
              let number = fullVal as? NSNumber else {
            return false
        }
        return number.boolValue
    }

    // MARK: - Shells

    private func openBar() {
        guard isMonitoring, !isHiddenForFullscreen else { return }
        CompanionChatBubblePanel.safeShared?.hide()
        let text = lastSelectedText
        guard !text.isEmpty else {
            toggleChatBubble()
            return
        }
        pinPet()
        TransientCommandBarPanel.shared.showBesideCompanion(
            text: text,
            petCenter: CompanionPetPanel.shared.petCenter,
            edge: currentEdge
        )
    }

    private func toggleChatBubble() {
        if let bubble = CompanionChatBubblePanel.safeShared, bubble.isVisible {
            bubble.hide()
            shellsPinned = TransientCommandBarPanel.safeShared?.isVisible == true
            if !shellsPinned { startLeaveCountdown() }
            return
        }
        pinPet()
        CompanionPetPanel.shared.playExpression(.chat, duration: 1.2)
        let frame = CompanionGeometry.chatBubbleFrame(
            petCenter: CompanionPetPanel.shared.petCenter,
            edge: currentEdge
        )
        CompanionChatBubblePanel.shared.show(at: frame)
    }

    private func pinPet() {
        shellsPinned = true
        isCaptured = true
        stopPatrol()
        cancelLeave()
        CompanionPetPanel.shared.setClickThrough(false)
    }

    public func notifyShellClosed() {
        guard isMonitoring else { return }
        let bubbleOpen = CompanionChatBubblePanel.safeShared?.isVisible == true
        let barOpen = TransientCommandBarPanel.safeShared?.isVisible == true
        shellsPinned = bubbleOpen || barOpen
        if !shellsPinned {
            startLeaveCountdown()
        }
    }

    public func resolveScreen(for point: NSPoint) -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// 壳体把圆滑开后回写当前位置，避免巡逻从旧坐标接着走。
    public func notePetRelocated(to center: CGPoint, edge: CompanionEdge) {
        currentEdge = edge
        let screen = resolveScreen(for: center)
        homes[screen.displayID] = CompanionGeometry.PatrolState(center: center, edge: edge)
    }
}
