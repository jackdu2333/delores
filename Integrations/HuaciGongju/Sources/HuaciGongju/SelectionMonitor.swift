//
//  SelectionMonitor.swift
//  HuaciGongju
//

import Cocoa
import ApplicationServices
import UniformTypeIdentifiers

public protocol SelectionMonitorDelegate: AnyObject {
    func selectionMonitorDidDetectSelection(_ text: String, at screenPoint: NSPoint)
}

/// 划词去重指纹：只保留 hash + 原文长度，绝不常驻整段选区。
public struct SelectionFingerprint: Equatable {
    public let hash: Int
    public let length: Int
}

public class SelectionMonitor {
    public static let shared = SelectionMonitor()

    /// 送进模型 / 面板的划词输入预算。超出部分裁掉，指纹仍按原文计算。
    public static let maxInputChars = 64_000

    public weak var delegate: SelectionMonitorDelegate?

    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?
    private var isMonitoring = false

    private var lastHandledFingerprint: SelectionFingerprint?
    private var lastHandledTime: TimeInterval = 0

    private var lastMouseDownPoint: NSPoint = .zero
    private var lastMouseDownTime: TimeInterval = 0
    private var lastMouseUpPoint: NSPoint = .zero
    private var lastMouseUpTime: TimeInterval = 0

    private init() {}

    public static func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func log(_ msg: String) {
        let text = "[\(Date())] \(msg)\n"
        print(text, terminator: "")
        guard let data = text.data(using: .utf8) else { return }

        let logUrl = ChatLog.logDirectoryURL.appendingPathComponent("huacigongju.log")
        let filePath = logUrl.path
        let fm = FileManager.default

        if !fm.fileExists(atPath: filePath) {
            fm.createFile(atPath: filePath, contents: data, attributes: [.posixPermissions: 0o600])
            return
        }

        // 超过 2MB 时轮转重开，避免日志无限增长
        if let attrs = try? fm.attributesOfItem(atPath: filePath),
           let size = attrs[.size] as? Int,
           size > 2 * 1024 * 1024 {
            try? fm.removeItem(atPath: filePath)
            let header = "[日志超过 2MB，已轮转重开]\n"
            fm.createFile(atPath: filePath, contents: header.data(using: .utf8), attributes: [.posixPermissions: 0o600])
        }

        if let handle = try? FileHandle(forWritingTo: logUrl) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        log("SelectionMonitor started. Trusted: \(AXIsProcessTrusted())")

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            let loc = NSEvent.mouseLocation
            self?.lastMouseDownPoint = loc
            self?.lastMouseDownTime = Date().timeIntervalSince1970
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard let self = self else { return }
            // Ghost：关自动呼出 = 整段检测都不跑。
            // Companion：关自动呼出仍要取词，圆会看一眼，出不出条由 CompanionManager 决定。
            guard ConfigManager.shared.autoShowToolbar || ConfigManager.shared.enableCompanionMode else { return }

            let upPoint = NSEvent.mouseLocation

            // Rule A0: If window dragging/snapping was just in progress, ignore text selection!
            if WindowSnapManager.shared.didDragWindowRecently || WindowSnapManager.shared.isDraggingWindow {
                return
            }

            // Rule A: If click/drag landed inside our own floating bars, IGNORE completely!
            // Never trigger selection check when user is clicking the toolbar buttons!
            //
            // ⚠️ `isMaterialized` 必须短路在前：面板没建过就必然不可见，
            // 直接访问 `shared` 会让用户开机后第一次点鼠标就把整个面板实体化。
            if let bar = TransientCommandBarPanel.safeShared,
               bar.isVisible,
               bar.frame.contains(upPoint) {
                return
            }
            if let island = WindowSnapIslandPanel.safeShared,
               island.isVisible,
               island.frame.contains(upPoint) {
                return
            }
            if let divider = SplitDividerOverlayPanel.safeShared,
               divider.isVisible,
               divider.frame.contains(upPoint) {
                return
            }
            if let pet = CompanionPetPanel.safeShared,
               pet.isVisible,
               pet.frame.contains(upPoint) {
                return
            }
            if let bubble = CompanionChatBubblePanel.safeShared,
               bubble.isVisible,
               bubble.frame.contains(upPoint) {
                return
            }

            let downPoint = self.lastMouseDownPoint
            let dist = hypot(upPoint.x - downPoint.x, upPoint.y - downPoint.y)
            let now = Date().timeIntervalSince1970

            // Check gesture thresholds (Cherry Studio / macOS Accessibility standard)
            // 1. Drag selection: distance traveled >= 8.0 pt
            let isDragSelection = (dist >= 8.0)

            // 2. Double-click selection: two consecutive releases within 350ms and distance <= 4.0 pt
            let isDoubleClick = (now - self.lastMouseUpTime < 0.35) && (hypot(upPoint.x - self.lastMouseUpPoint.x, upPoint.y - self.lastMouseUpPoint.y) <= 4.0)

            self.lastMouseUpPoint = upPoint
            self.lastMouseUpTime = now

            // Single clicks (like clicking tabs in Chrome, clicking links, clicking buttons) MUST BE IGNORED!
            guard isDragSelection || isDoubleClick else {
                return
            }

            // Small delay to allow target app to finalize text highlight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                self.checkSelectionAndNotify(triggerPoint: upPoint)
            }
        }
    }

    public func stop() {
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        isMonitoring = false
        log("SelectionMonitor stopped")
    }

    public func triggerManually() {
        log("Manual trigger requested")
        checkSelectionAndNotify(triggerPoint: NSEvent.mouseLocation, isManual: true)
    }

    /// 裁到输入预算，并给出去重指纹。指纹按**原文**计算，避免「裁后碰巧相同」误伤去重。
    public static func prepareSelectedText(_ text: String) -> (text: String, fingerprint: SelectionFingerprint) {
        let fingerprint = SelectionFingerprint(hash: text.hashValue, length: text.count)
        guard text.count > maxInputChars else {
            return (text, fingerprint)
        }
        return (String(text.prefix(maxInputChars)), fingerprint)
    }

    private func checkSelectionAndNotify(triggerPoint: NSPoint, isManual: Bool = false) {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.bundleIdentifier == "com.jackdu.huacigongju" {
            return
        }

        guard let raw = getSelectedText(from: frontApp)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return
        }

        let prepared = Self.prepareSelectedText(raw)
        let now = Date().timeIntervalSince1970
        // Prevent accidental re-trigger for exact same text within 0.5s unless manual
        if !isManual,
           let last = lastHandledFingerprint,
           last == prepared.fingerprint,
           (now - lastHandledTime) < 0.5 {
            return
        }

        lastHandledFingerprint = prepared.fingerprint
        lastHandledTime = now

        log("Selection detected from [\(frontApp.localizedName ?? "")] length: \(raw.count) at: \(triggerPoint)")
        delegate?.selectionMonitorDidDetectSelection(prepared.text, at: triggerPoint)
    }

    public func getSelectedText(from frontApp: NSRunningApplication) -> String? {
        let allowPlaintext = ConfigManager.shared.enablePlaintextLogging

        // Method 1: AXUIElement API (Clean, zero clipboard pollution)
        if let axText = getSelectedTextViaAccessibility(frontApp: frontApp),
           !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if allowPlaintext {
                log("Got text via AXAPI: \(axText.prefix(30))...")
            } else {
                log("Got text via AXAPI (length: \(axText.count))")
            }
            return axText
        }

        // Method 2: Targeted Cmd+C clipboard fallback (Only when gesture was verified)
        if let clipText = getSelectedTextViaTargetedCopy(frontApp: frontApp),
           !clipText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if allowPlaintext {
                log("Got text via Clipboard fallback: \(clipText.prefix(30))...")
            } else {
                log("Got text via Clipboard fallback (length: \(clipText.count))")
            }
            return clipText
        }

        return nil
    }

    private func getSelectedTextViaAccessibility(frontApp: NSRunningApplication) -> String? {
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // 唤醒应用的无障碍树：
        //   - AXManualAccessibility 是 Electron 的专用唤醒信号，保留（副作用仅为性能开销）。
        //   - 读取 role 属性即可触发 Chromium / Firefox 系的现代激活路径
        //     （Chromium 2021 补丁、Firefox bug 1845364），无需任何副作用标志。
        //   - ⚠️ 刻意**不再设置 AXEnhancedUserInterface**：该属性等于向应用宣告
        //     「VoiceOver 正在运行」，AppKit 会据此「抬起主窗口」，并已知会改变应用行为、
        //     破坏窗口管理器，且设置后长期残留。它正是「划词后复制/粘贴等快捷键行为异常」的元凶之一。
        var roleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &roleValue)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var focusedElementVal: CFTypeRef?
        let fStatus = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElementVal)

        // ⚠️ 一律经 AXCast 转换而不是 `as!`：跨进程 AX 返回的对象不保证规整，
        // Electron / Java / 游戏 / 自绘 GUI 在权限半授权状态下会返回 NSNull、NSNumber
        // 甚至完全不同的 CF 对象。强转的代价是整条划词链路崩溃，转换失败只是「这次取不到」。
        var candidateElement: AXUIElement? = nil
        if fStatus == .success {
            candidateElement = AXCast.element(focusedElementVal)
        }
        if candidateElement == nil {
            var windowVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowVal) == .success {
                candidateElement = AXCast.element(windowVal)
            }
        }

        guard let targetElement = candidateElement else { return nil }

        if let text = readSelectedText(from: targetElement) {
            return text
        }

        var current = targetElement
        for _ in 0..<4 {
            var parentVal: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentVal) == .success,
               let parent = AXCast.element(parentVal) {
                current = parent
                if let text = readSelectedText(from: current) {
                    return text
                }
            } else {
                break
            }
        }

        return nil
    }

    private func readSelectedText(from element: AXUIElement) -> String? {
        var selectedTextVal: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextVal)
        if status == .success, let str = selectedTextVal as? String, !str.isEmpty {
            return str
        }
        return nil
    }

    // MARK: - 剪贴板兜底的资源预算
    //
    // 剪贴板兜底只是「AX 取不到选中文字」时的**备用**手段。若为了取几十个字，
    // 把用户刚复制的 30MB 截图 / PSD / 带附件的富文本整个实体化进自己内存，
    // 一次划词就能让常驻小工具的内存从 40MB 飙到 150MB+ ——
    // 这正是「平时很轻，突然某一次飙上去」的来源。
    // 对常驻工具而言，「偶尔某个 App 取不到字」远比「瞬间吃掉几十 MB」可接受。
    private enum ClipboardFallback {
        /// 备份总量上限（字节）。超过即整体放弃兜底。
        static let maxTotalBytes = 2 * 1024 * 1024
        /// 单个类型的上限，避免「总量没超、但某一项本身就巨大」时先被完整读进来。
        static let maxSingleTypeBytes = 1 * 1024 * 1024
    }

    /// 仅凭类型就能判定「大概率是大块数据」—— **在读 data 之前**先拦掉。
    ///
    /// 必须先看类型再看大小：为了「量一下尺寸」而先把 30MB 截图读进内存，
    /// 就等于没有防护，预算形同虚设。
    private func isHeavyPasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
        let raw = type.rawValue
        // 承诺式（promised）数据：实际内容可能任意大，读取还会触发提供方进程
        if raw.localizedCaseInsensitiveContains("promised") { return true }
        guard let ut = UTType(raw) else { return false }
        return ut.conforms(to: .image)
            || ut.conforms(to: .movie)
            || ut.conforms(to: .audio)
            || ut.conforms(to: .archive)
            || ut.conforms(to: .executable)
            || ut.conforms(to: .diskImage)
    }

    /// 剪贴板快照：把当前所有条目连同各类型数据**立即复制一份**，
    /// 避免原条目被清除后其惰性数据源失效。
    ///
    /// - Returns: 成功时返回备份；**`nil` 表示剪贴板过大或含大块类型，必须整体放弃兜底**。
    ///
    /// ⚠️ 为什么只能「整体放弃」、不能「备份一部分」：
    /// 兜底流程会执行 `clearContents()`。一旦清了却只还原部分类型，
    /// 剩下那部分就是**永久丢失用户数据** —— 这比取不到字严重得多。
    /// 所以判定必须发生在**清理之前**，且只有「全部备份」或「完全不碰」两种结果。
    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems else { return [] }

        var total = 0
        var backup: [NSPasteboardItem] = []
        backup.reserveCapacity(items.count)

        for item in items {
            // 先过类型关：明显的大块类型在读取之前就拦掉
            for type in item.types where isHeavyPasteboardType(type) {
                return nil
            }
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                if data.count > ClipboardFallback.maxSingleTypeBytes { return nil }
                total += data.count
                if total > ClipboardFallback.maxTotalBytes { return nil }
                copy.setData(data, forType: type)
            }
            backup.append(copy)
        }
        return backup
    }

    private func getSelectedTextViaTargetedCopy(frontApp: NSRunningApplication) -> String? {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        // 备份用户原有剪贴板。这条通道只是取词的内部手段，若直接覆盖剪贴板，
        // 用户随后按 Cmd+V 会粘贴到划词内容、而不是他自己刚才复制的东西
        //（表现为「复制/粘贴快捷键失效」）。取词对剪贴板必须零副作用。
        //
        // 有硬预算：过大或含大块类型时 snapshotPasteboard 返回 nil，
        // 此时**整体放弃兜底**直接返回，剪贴板一点都不碰 ——
        // 半套备份是不可接受的（清了却只还原一部分 = 永久丢失用户数据）。
        guard let backup = snapshotPasteboard(pasteboard) else {
            log("剪贴板兜底跳过：剪贴板超过预算或含图片/压缩包等大块类型（AX 未取到选中文本）")
            return nil
        }

        let pid = frontApp.processIdentifier
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false) else {
            return nil
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.postToPid(pid)
        usleep(5000) // 5ms
        keyUp.postToPid(pid)

        let start = Date()
        while Date().timeIntervalSince(start) < 0.08 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            if pasteboard.changeCount != initialChangeCount {
                break
            }
        }

        // 剪贴板未被改动：说明目标应用没有响应合成按键，本次没有取到内容，无需还原
        guard pasteboard.changeCount != initialChangeCount else { return nil }

        let copiedString = pasteboard.string(forType: .string)

        // 取完立刻还原用户剪贴板，只把文字作为返回值带出，不留任何副作用
        pasteboard.clearContents()
        if !backup.isEmpty {
            pasteboard.writeObjects(backup)
        }

        return copiedString
    }
}

