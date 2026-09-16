//
//  AppDelegate.swift
//  HuaciGongju
//

import Cocoa
import SwiftUI
import Combine

public class AppDelegate: NSObject, NSApplicationDelegate, SelectionMonitorDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    /// 只做 weak 持有：设置窗口 `isReleasedWhenClosed = true`，关闭后由 AppKit 回收，
    /// 这里若用强引用就会变成悬垂指针。见 `openSettings()` 内的说明。
    private weak var settingsWindow: NSWindow?
    // outside-click / ESC 监听已迁到 TransientCommandBarPanel 内部，
    // 改为「面板出现时装、消失时拆」，不再在 App 启动时常驻。
    private var featureCancellables: Set<AnyCancellable> = []

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory app (no Dock icon, light footprint)
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupSelectionMonitor()
        setupLazyFeatureManagers()

        SelectionMonitor.shared.log("HuaciGongju applicationDidFinishLaunching complete")

        if !SelectionMonitor.isAccessibilityTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.promptAccessibilityGuide()
            }
        }
    }

    /// 按需启停可选功能（Lazy Feature）：开关直接驱动 `start()` / `stop()`。
    ///
    /// 设计取舍：这两个功能默认均为**开启**，但它们都依赖全局事件监听，常驻成本不可忽略 ——
    /// 尤其是 `SplitDividerManager`，只要启动就会订阅全系统 `mouseMoved`（最高频事件之一），
    /// 并在无活跃窗口对时按 0.5s 节流执行 `CGWindowListCopyWindowInfo` + O(n³) 窗口配对
    /// + `AXUIElement` 跨进程 IPC。对一款定位「静默待机」的划词工具而言，这笔开销应当只在
    /// 功能真正开启时支付。
    ///
    /// 因此这里采用「开关 → start/stop」，而**不是**让 Manager 永远运行、在每次事件回调里
    /// 再 `guard` 配置：关闭功能 = 连全局事件监听都不存在，彻底回到零开销待机。
    ///
    /// - Important: `@Published` 在 **willSet** 阶段派发新值（此刻读属性仍是旧值），
    ///   所以必须使用 sink 闭包参数 `enabled`，不可改写成 `ConfigManager.shared.enableXxx`。
    /// - Note: Combine 的 `CurrentValueSubject` 语义保证订阅瞬间即收到当前值，
    ///   因此启动时的初始状态会自动与配置对齐，无需额外显式调用一次 `start()`。
    private func setupLazyFeatureManagers() {
        ConfigManager.shared.$enableCompanionMode
            .receive(on: RunLoop.main)
            .sink { [weak self] companionEnabled in
                self?.applyPresenceMode(companionEnabled: companionEnabled)
            }
            .store(in: &featureCancellables)

        ConfigManager.shared.$enableWindowSnapping
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.applyGhostSnap(enabled: enabled)
            }
            .store(in: &featureCancellables)

        ConfigManager.shared.$enableSplitDivider
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.applyGhostDivider(enabled: enabled)
            }
            .store(in: &featureCancellables)
    }

    private func applyPresenceMode(companionEnabled: Bool) {
        if companionEnabled {
            WindowSnapManager.shared.stop()
            SplitDividerManager.shared.stop()
            CompanionManager.shared.start()
        } else {
            CompanionManager.shared.stop()
            applyGhostSnap(enabled: ConfigManager.shared.enableWindowSnapping)
            applyGhostDivider(enabled: ConfigManager.shared.enableSplitDivider)
        }
        updateMenu()
    }

    private func applyGhostSnap(enabled: Bool) {
        let allow = CompanionInteraction.allowsGhostSnap(
            companionEnabled: ConfigManager.shared.enableCompanionMode,
            snapEnabled: enabled
        )
        if allow {
            WindowSnapManager.shared.start()
        } else {
            WindowSnapManager.shared.stop()
        }
    }

    private func applyGhostDivider(enabled: Bool) {
        let allow = CompanionInteraction.allowsGhostDivider(
            companionEnabled: ConfigManager.shared.enableCompanionMode,
            dividerEnabled: enabled
        )
        if allow {
            SplitDividerManager.shared.start()
        } else {
            SplitDividerManager.shared.stop()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "划词小工具")
        }

        updateMenu()
    }

    public func updateMenu() {
        let menu = NSMenu()
        let isTrusted = SelectionMonitor.isAccessibilityTrusted()

        let statusText = isTrusted ? "顶部瞬时控制器 (已就绪)" : "顶部瞬时控制器 (⚠️ 待授权辅助功能)"
        let titleItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let autoItem = NSMenuItem(title: "自动划选呼出", action: #selector(toggleAutoShow), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = ConfigManager.shared.autoShowToolbar ? .on : .off
        menu.addItem(autoItem)

        let companionOn = ConfigManager.shared.enableCompanionMode

        let snapItem = NSMenuItem(title: "拖拽窗口分屏岛", action: #selector(toggleWindowSnapping), keyEquivalent: "")
        snapItem.target = self
        snapItem.state = ConfigManager.shared.enableWindowSnapping ? .on : .off
        snapItem.isEnabled = !companionOn
        if companionOn {
            snapItem.title = "拖拽窗口分屏岛（由宠物接管）"
        }
        menu.addItem(snapItem)

        let splitItem = NSMenuItem(title: "分屏中缝联动调节", action: #selector(toggleSplitDivider), keyEquivalent: "")
        splitItem.target = self
        splitItem.state = ConfigManager.shared.enableSplitDivider ? .on : .off
        splitItem.isEnabled = !companionOn
        if companionOn {
            splitItem.title = "分屏中缝联动调节（由宠物接管）"
        }
        menu.addItem(splitItem)

        let triggerItem = NSMenuItem(title: "手动触发当前划词", action: #selector(manualTrigger), keyEquivalent: "h")
        triggerItem.keyEquivalentModifierMask = [.option]
        triggerItem.target = self
        menu.addItem(triggerItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let authTitle = isTrusted ? "辅助功能权限: 已开启 ✅" : "授权辅助功能权限 (点击开启)..."
        let authItem = NSMenuItem(title: authTitle, action: #selector(checkAccessibility), keyEquivalent: "")
        authItem.target = self
        menu.addItem(authItem)

        let logItem = NSMenuItem(title: "查看实时运行日志...", action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 划词小工具", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleAutoShow() {
        ConfigManager.shared.autoShowToolbar.toggle()
        updateMenu()
    }

    @objc private func toggleWindowSnapping() {
        ConfigManager.shared.enableWindowSnapping.toggle()
        updateMenu()
    }

    @objc private func toggleSplitDivider() {
        ConfigManager.shared.enableSplitDivider.toggle()
        updateMenu()
    }

    @objc private func manualTrigger() {
        SelectionMonitor.shared.triggerManually()
    }

    @objc public func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "划词小工具 - 偏好设置"
            window.center()
            // 关闭即回收：默认的 `true` 才是「设置窗口关闭后释放整棵 SwiftUI 视图树」的行为。
            // 之前设成 false 是为了配合强引用持有，结果 AppKit 会一直把它留在 `NSApp.windows`
            // 里（本机探针实测：false 时关闭后计数 1→1，true 时 1→0），窗口与 NSHostingView
            // 都退不出去。改回 true 后这里必须 weak 持有，否则是悬垂指针。
            window.isReleasedWhenClosed = true
            window.delegate = self  // 关闭时归还焦点，见 windowWillClose
            window.contentView = NSHostingView(rootView: SettingsView())
            self.settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 归还焦点：本应用是 accessory（无 Dock 图标）应用，`openSettings()` 与模态弹窗都会
    /// 主动激活自身。若结束时不让出「活跃应用」身份，本应用会一直占着前台且没有可交互窗口，
    /// 用户在其他应用里按 Cmd+C / Cmd+V 等按键都不会送达真正的前台应用
    /// —— 表面上就是「划词工具运行期间系统快捷键失效」。
    private func releaseFocus() {
        NSApp.hide(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        releaseFocus()
    }

    @objc private func promptAccessibilityGuide() {
        SelectionMonitor.requestAccessibilityPermission()

        let alert = NSAlert()
        alert.messageText = "需要开启「辅助功能」权限"
        alert.informativeText = "划词小工具需要辅助功能权限以捕获跨应用的选中文本与光标位置。\n\n请在弹出的系统设置中，允许「划词小工具」；若列表中未出现，可点击「+」添加本工具。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后设置")

        let response = alert.runModal()
        releaseFocus()  // 模态弹窗同样会激活本应用，结束后需要让出前台身份
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func checkAccessibility() {
        if SelectionMonitor.isAccessibilityTrusted() {
            let alert = NSAlert()
            alert.messageText = "辅助功能权限正常"
            alert.informativeText = "划词小工具已获得 macOS 辅助功能权限，可以正常划词并获取光标位置。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好的")
            alert.runModal()
            releaseFocus()  // 同上：弹窗结束后归还焦点
        } else {
            promptAccessibilityGuide()
        }
    }

    @objc private func openLog() {
        let logDir = ChatLog.logDirectoryURL
        let logUrl = logDir.appendingPathComponent("huacigongju.log")
        if FileManager.default.fileExists(atPath: logUrl.path) {
            NSWorkspace.shared.open(logUrl)
        } else {
            NSWorkspace.shared.open(logDir)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupSelectionMonitor() {
        SelectionMonitor.shared.delegate = self
        SelectionMonitor.shared.start()
    }

    // MARK: - SelectionMonitorDelegate
    public func selectionMonitorDidDetectSelection(_ text: String, at screenPoint: NSPoint) {
        if ConfigManager.shared.enableCompanionMode {
            CompanionManager.shared.handleSelection(text, at: screenPoint)
            return
        }
        TransientCommandBarPanel.shared.show(at: screenPoint, text: text)
    }
}

