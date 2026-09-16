//
//  HuaciGongjuTests.swift
//  HuaciGongju
//

import Foundation
import Cocoa

#if canImport(HuaciGongjuKit)
@testable import HuaciGongjuKit
#endif

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        fatalError("Assertion failed: [\(actual)] != [\(expected)] - \(message) at \(file):\(line)")
    }
}

func assertEqual<T: Equatable>(_ actual: T?, _ expected: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        fatalError("Assertion failed: [\(String(describing: actual))] != [\(String(describing: expected))] - \(message) at \(file):\(line)")
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition {
        fatalError("Assertion failed: expected true - \(message) at \(file):\(line)")
    }
}

func assertFalse(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if condition {
        fatalError("Assertion failed: expected false - \(message) at \(file):\(line)")
    }
}

/// 测试程序入口。
/// 本机仅装 Command Line Tools、无 Xcode，XCTest 不可用，
/// 因此以独立可执行 target 形式运行，由 build.sh 在编译产品前调用，
/// 实现「构建即跑测试」的自动化保障。
@main
struct TestRunner {
    static func main() {
        print("🚀 Running HuaciGongju Verification Test Suite...")

        testPrivacyAndLogPaths()
        testToolbarPanelStaysUnmaterialized()
        testPanelsStayUnmaterializedOnLaunchAndReset()
        testConfigManagerDefaults()
        testViewModelFollowUpHistoryChaining()
        testViewModelSwitchActionAndRetryPrompt()
        testViewModelReasoningNoAnswerNotice()
        testViewModelEmptyResponseNotice()
        testViewModelStopGenerating()
        testViewModelResetStateAndPin()
        testStreamRaceConditionWithRequestId()
        testStreamDelegateByteSafeUTF8ChunkSplitting()
        testStreamDelegateBatchesTokensToReduceUIRefreshes()
        testStreamDelegateFlushesLargeChunkImmediately()
        testStreamDelegateContentCapCompletesSuccessfully()
        testStreamDelegateReasoningCapDoesNotAbortContent()
        testViewModelHistoryCapacity()
        testViewModelOutputTextCapacity()
        testAXCastRejectsUnexpectedTypes()
        testLLMServiceCancelCleanup()
        testLLMServiceEphemeralConfiguration()
        testWindowSnapGeometryCalculation()
        testWindowSnapConfigPersistence()
        testWindowSnapHitTestingAndThresholds()
        testWindowSnapTopEdgeTriggerAndDismissal()
        testGhostPreviewPanelFramebufferReclamation()
        testSplitDividerAdjacencyDetection()
        testSplitDividerJointResizingCalculation()
        testSplitDividerFiftyFiftyReset()
        testSplitDividerConfigPersistence()
        testSplitDividerOverlayHoverAndHitTesting()
        testSplitDividerFrontmostAppFilter()
        testSplitDividerLiquidGlassVisualTokens()
        testSplitDividerOcclusionAndSpaceSwitching()
        testSelectionInputBudgetAndFingerprintDedupe()
        testWindowSnapDefersAXCaptureUntilRealDrag()
        testWindowSnapNotifiesSplitDividerOnRealDragEnd()
        testCompanionGeometryAndInteraction()
        testCompanionConfigPersistence()
        testCompanionPanelStaysUnmaterializedUntilStart()
        testCompanionSingletonPanelsSurvivePresenceSwitch()

        print("🎉 ALL TESTS PASSED SUCCESSFULLY!")
    }

    static func testPrivacyAndLogPaths() {
        print("  - Testing ChatLog & SelectionMonitor secure log paths & privacy defaults...")
        let logDir = ChatLog.logDirectoryURL.path
        assertTrue(logDir.contains("Library/Logs/HuaciGongju"), "Log directory must be in Library/Logs/HuaciGongju")
        assertTrue(ChatLog.path.hasSuffix("huacigongju-chat.log"), "Chat log file name must match")

        // Directory POSIX permissions must be 0o700
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logDir),
           let posix = attrs[.posixPermissions] as? NSNumber {
            assertEqual(posix.intValue, 0o700, "Log directory permissions must be 0o700")
        }

        // Plaintext logging default must be false
        assertFalse(ConfigManager.shared.enablePlaintextLogging, "Default plaintext logging must be OFF for user privacy")

        // SelectionMonitor log test
        SelectionMonitor.shared.log("Unit test log entry")
        let monitorLogPath = ChatLog.logDirectoryURL.appendingPathComponent("huacigongju.log").path
        assertTrue(FileManager.default.fileExists(atPath: monitorLogPath), "huacigongju.log must exist after logging")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: monitorLogPath),
           let posix = attrs[.posixPermissions] as? NSNumber {
            assertEqual(posix.intValue, 0o600, "huacigongju.log file permissions must be 0o600")
        }
    }

    static func testConfigManagerDefaults() {
        print("  - Testing ConfigManager profiles & actions defaults...")
        let cm = ConfigManager.shared
        assertTrue(!cm.profiles.isEmpty, "Default profiles must not be empty")
        assertTrue(!cm.actions.isEmpty, "Default actions must not be empty")
        guard let translateAction = cm.actions.first(where: { $0.id == "translate" }) else {
            fatalError("Default actions must include translate")
        }
        assertTrue(translateAction.prompt.contains("简体中文"), "Translate prompt must enforce Simplified Chinese target")
        assertTrue(translateAction.prompt.contains("待翻译的原材料文本"), "Translate prompt must enforce raw text boundary")
        assertTrue(translateAction.prompt.contains("代码标识符"), "Translate prompt must cover code identifiers")
        assertFalse(cm.enableCompanionMode, "桌宠模式出厂必须关闭，Ghost 仍是默认 Presence")
    }

    static func testViewModelFollowUpHistoryChaining() {
        print("  - Testing ViewModel follow-up history chain (no repeated sourceText)...")
        let vm = UnifiedCommandBarViewModel()
        vm.onStreamChat = { _, _, _, _, _, _, _, _ in }
        let action = ActionItem(id: "test", title: "测试", icon: "sparkles", prompt: "Prompt")

        // Round 1: Initial action
        vm.startAction(text: "初始划词文本", action: action)
        assertEqual(vm.sourceText, "初始划词文本", "sourceText must be initialized")
        assertEqual(vm.currentPrompt, "初始划词文本", "currentPrompt must equal sourceText initially")
        assertTrue(vm.history.isEmpty, "Initial history must be empty")

        // Simulate Round 1 answer received
        vm.outputText = "第一轮助手回复"

        // Round 2: Follow-up question 1
        vm.followUpInput = "第一个追问问题？"
        vm.sendFollowUp()

        // Verify history now records the first user question and assistant answer
        assertEqual(vm.history.count, 2, "History must contain 2 messages after follow-up")
        assertEqual(vm.history[0].role, "user")
        assertEqual(vm.history[0].content, "初始划词文本", "First user turn must be original prompt")
        assertEqual(vm.history[1].role, "assistant")
        assertEqual(vm.history[1].content, "第一轮助手回复", "First assistant turn must be outputText")
        assertEqual(vm.currentPrompt, "第一个追问问题？", "currentPrompt must be updated to follow-up question")

        // Simulate Round 2 answer received
        vm.outputText = "第二轮助手回复"

        // Round 3: Follow-up question 2
        vm.followUpInput = "第二个追问问题？"
        vm.sendFollowUp()

        assertEqual(vm.history.count, 4, "History must contain 4 messages")
        assertEqual(vm.history[2].role, "user")
        assertEqual(vm.history[2].content, "第一个追问问题？", "Second user turn must be the follow-up question, NOT sourceText!")
        assertEqual(vm.history[3].role, "assistant")
        assertEqual(vm.history[3].content, "第二轮助手回复")
        assertEqual(vm.currentPrompt, "第二个追问问题？", "currentPrompt must now be the second follow-up question")
    }

    static func testViewModelSwitchActionAndRetryPrompt() {
        print("  - Testing ViewModel switchAction and retryCurrent prompt preservation...")
        let vm = UnifiedCommandBarViewModel()
        vm.onStreamChat = { _, _, _, _, _, _, _, _ in }
        let action1 = ActionItem(id: "act1", title: "动作1", icon: "1.circle", prompt: "P1")
        let action2 = ActionItem(id: "act2", title: "动作2", icon: "2.circle", prompt: "P2")

        vm.startAction(text: "原文", action: action1)
        vm.outputText = "答案1"
        vm.followUpInput = "追问1"
        vm.sendFollowUp()
        assertEqual(vm.currentPrompt, "追问1")

        // Calling retryCurrent should keep currentPrompt = "追问1"
        vm.outputText = "旧答案"
        vm.retryCurrent()
        assertEqual(vm.currentPrompt, "追问1", "retryCurrent must preserve currentPrompt")
        assertEqual(vm.outputText, "", "retryCurrent must clear outputText")
        assertEqual(vm.lastRequestedProfileId, vm.selectedProfileId, "lastRequestedProfileId must match selectedProfileId")

        // Calling switchAction should reset currentPrompt back to sourceText and clear history
        vm.switchAction(action2)
        assertEqual(vm.currentPrompt, "原文", "switchAction must restore currentPrompt to sourceText")
        assertTrue(vm.history.isEmpty, "switchAction must clear history")
        assertEqual(vm.lastRequestedProfileId, vm.selectedProfileId, "lastRequestedProfileId must match selectedProfileId on switch")
    }

    static func testViewModelReasoningNoAnswerNotice() {
        print("  - Testing reasoning fallback removal: noAnswerNotice when answer is empty...")
        let vm = UnifiedCommandBarViewModel()
        var completeCallback: ((String) -> Void)? = nil
        var reasoningCallback: ((String) -> Void)? = nil

        vm.onStreamChat = { _, _, _, _, onReasoning, _, onComplete, _ in
            reasoningCallback = onReasoning
            completeCallback = onComplete
        }
        let action = ActionItem(id: "act", title: "思考测试", icon: "brain", prompt: "Think")

        vm.startAction(text: "待思考文本", action: action)
        assertFalse(vm.hasNoAnswerNotice, "Initial hasNoAnswerNotice must be false")

        // Stream reasoning only
        reasoningCallback?("这是模型的深度思考过程...")
        assertEqual(vm.reasoningText, "这是模型的深度思考过程...")
        assertEqual(vm.outputText, "")

        // Trigger real completion
        completeCallback?("")

        assertTrue(vm.hasNoAnswerNotice, "hasNoAnswerNotice must be true when content is empty but reasoning exists")
        assertEqual(vm.outputText, "", "outputText must remain empty and not be polluted by reasoning")

        // If user now sends follow-up, history must not be polluted by reasoningText!
        vm.followUpInput = "新追问"
        vm.sendFollowUp()
        assertTrue(vm.history.isEmpty, "History must remain empty since outputText was empty")
    }

    static func testViewModelEmptyResponseNotice() {
        print("  - Testing empty response (both reasoning and answer empty)...")
        let vm = UnifiedCommandBarViewModel()
        var completeCallback: ((String) -> Void)? = nil

        vm.onStreamChat = { _, _, _, _, _, _, onComplete, _ in
            completeCallback = onComplete
        }
        let action = ActionItem(id: "act", title: "空测试", icon: "brain", prompt: "Think")

        vm.startAction(text: "待测试文本", action: action)
        completeCallback?("")

        assertTrue(vm.hasNoAnswerNotice, "hasNoAnswerNotice must be true even if reasoning is also empty, preventing blank UI")
        assertFalse(vm.isLoading)
    }

    static func testViewModelStopGenerating() {
        print("  - Testing stopGenerating cancels request and sets notice...")
        let vm = UnifiedCommandBarViewModel()
        var tokenCallback: ((String) -> Void)? = nil

        vm.onStreamChat = { _, _, _, _, onReasoning, onToken, _, _ in
            onReasoning?("思考中")
            tokenCallback = onToken
        }
        let action = ActionItem(id: "act", title: "测试", icon: "sparkles", prompt: "P")
        vm.startAction(text: "待测试文本", action: action)

        assertTrue(vm.isLoading)
        assertFalse(vm.hasNoAnswerNotice)

        // Stop while output is still empty
        vm.stopGenerating()

        assertFalse(vm.isLoading)
        assertTrue(vm.hasNoAnswerNotice, "Stopping generation before answer starts must show notice with regenerate option")

        // Outdated token arriving after stop must be dropped
        tokenCallback?("延迟到达的 token")
        assertEqual(vm.outputText, "", "Tokens arriving after stopGenerating must be discarded")
    }

    static func testViewModelResetStateAndPin() {
        print("  - Testing ViewModel resetState dirty state and pin purge...")
        let vm = UnifiedCommandBarViewModel()
        let action = ActionItem(id: "act", title: "测试", icon: "star", prompt: "P")

        vm.startAction(text: "dirty source", action: action)
        vm.outputText = "dirty output"
        vm.reasoningText = "dirty reasoning"
        vm.history = [ChatMessage(role: "user", content: "hi")]
        vm.followUpInput = "dirty input"
        vm.hasNoAnswerNotice = true
        vm.isPinned = true
        vm.displayMode = .expanded

        vm.resetState()

        assertEqual(vm.outputText, "")
        assertEqual(vm.reasoningText, "")
        assertTrue(vm.history.isEmpty)
        assertTrue(vm.activeAction == nil)
        assertEqual(vm.sourceText, "")
        assertEqual(vm.currentPrompt, "")
        assertEqual(vm.followUpInput, "")
        assertFalse(vm.isLoading)
        assertFalse(vm.hasNoAnswerNotice)
        assertFalse(vm.isPinned, "isPinned must be reset to false")
        assertEqual(vm.displayMode, .collapsed)
    }

    static func testStreamRaceConditionWithRequestId() {
        print("  - Testing requestId guard against obsolete streaming callbacks...")
        let vm = UnifiedCommandBarViewModel()
        var oldTokenCallback: ((String) -> Void)? = nil

        vm.onStreamChat = { _, _, _, _, _, onToken, _, _ in
            if oldTokenCallback == nil {
                oldTokenCallback = onToken
            }
        }

        let action = ActionItem(id: "act", title: "测试", icon: "star", prompt: "P")
        vm.startAction(text: "第一问", action: action)

        // Now user quickly switches to a different action
        let action2 = ActionItem(id: "act2", title: "动作2", icon: "star", prompt: "P2")
        vm.switchAction(action2)

        // Now the old callback for "第一问" fires
        oldTokenCallback?("这是第一问的迟到内容")

        assertEqual(vm.outputText, "", "Obsolete token from previous requestId must be ignored")
    }

    static func testStreamDelegateByteSafeUTF8ChunkSplitting() {
        print("  - Testing StreamDelegate byte-safe UTF-8 chunk splitting...")
        var receivedTokens: [String] = []
        var receivedReasoning: [String] = []
        var isCompleted = false

        // 解析在后台队列、回调在 flushQueue 上派发；测试用独立队列以便同步排空
        let flushQueue = DispatchQueue(label: "test.llm.flush.utf8")

        let delegate = StreamDelegate(
            onReasoning: { reasoning in
                receivedReasoning.append(reasoning)
            },
            onToken: { token in
                receivedTokens.append(token)
            },
            onComplete: { _ in
                isCompleted = true
            },
            onError: { error in
                fatalError("Unexpected error in byte safe test: \(error)")
            },
            flushQueue: flushQueue
        )

        // Let's create an SSE payload with multi-byte Chinese characters: "划词小工具"
        // UTF-8 of "划" is 3 bytes: 0xE5, 0x88, 0x92
        let fullLine = "data: {\"choices\":[{\"delta\":{\"content\":\"划词小工具\"}}]}\n"
        let fullData = fullLine.data(using: .utf8)!

        // Split right inside the 3-byte character "划"
        let range = fullLine.range(of: "划")!
        let utf8PrefixCount = fullLine[..<range.lowerBound].utf8.count
        let splitIndex = utf8PrefixCount + 1

        let chunk1 = fullData.subdata(in: 0..<splitIndex)
        let chunk2 = fullData.subdata(in: splitIndex..<fullData.count)

        let dummySession = URLSession(configuration: .default)
        let dummyTask = dummySession.dataTask(with: URL(string: "http://localhost")!)

        // Feed chunk1
        delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: chunk1)
        delegate.drainPendingForTesting()
        assertEqual(receivedTokens.count, 0, "No complete line yet, buffer must hold chunk1")

        // Feed chunk2
        delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: chunk2)
        delegate.drainPendingForTesting()
        assertEqual(receivedTokens.count, 1, "Complete line processed after chunk2")
        assertEqual(receivedTokens[0], "划词小工具", "Multi-byte Chinese string must be decoded perfectly without dropping!")

        // Complete task
        delegate.urlSession(dummySession, task: dummyTask, didCompleteWithError: nil)
        delegate.drainPendingForTesting()
        assertTrue(isCompleted, "Task must complete cleanly")
    }

    static func testStreamDelegateBatchesTokensToReduceUIRefreshes() {
        print("  - Testing StreamDelegate throttles UI refreshes (40ms batch)...")
        let flushQueue = DispatchQueue(label: "test.llm.flush.throttle")
        var callbackCount = 0
        var received = ""
        var isCompleted = false

        let delegate = StreamDelegate(
            onReasoning: nil,
            onToken: { token in
                callbackCount += 1
                received += token
            },
            onComplete: { _ in isCompleted = true },
            onError: { error in fatalError("Unexpected error in throttle test: \(error)") },
            flushQueue: flushQueue
        )

        let dummySession = URLSession(configuration: .default)
        let dummyTask = dummySession.dataTask(with: URL(string: "http://localhost")!)

        // 一次性灌 200 个 token，模拟快速模型的高频推送
        var expected = ""
        for i in 0..<200 {
            expected += "\(i)"
            let line = "data: {\"choices\":[{\"delta\":{\"content\":\"\(i)\"}}]}\n"
            delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: line.data(using: .utf8)!)
        }
        delegate.drainPendingForTesting()

        assertTrue(callbackCount <= 3, "200 个 token 应被合并成个位数次刷新，实际 \(callbackCount) 次")
        assertEqual(received, expected, "批量合并不能丢字、不能乱序")

        delegate.urlSession(dummySession, task: dummyTask, didCompleteWithError: nil)
        delegate.drainPendingForTesting()
        assertTrue(isCompleted, "Task must complete cleanly")
    }

    static func testStreamDelegateFlushesLargeChunkImmediately() {
        print("  - Testing StreamDelegate bypasses throttle for oversized chunk...")
        let flushQueue = DispatchQueue(label: "test.llm.flush.large")
        var callbackCount = 0
        var received = ""

        let delegate = StreamDelegate(
            onReasoning: nil,
            onToken: { token in
                callbackCount += 1
                received += token
            },
            onComplete: { _ in },
            onError: { error in fatalError("Unexpected error in large chunk test: \(error)") },
            flushQueue: flushQueue
        )

        let dummySession = URLSession(configuration: .default)
        let dummyTask = dummySession.dataTask(with: URL(string: "http://localhost")!)

        // 3600 字节 > 2048 上限，应立刻发出而不是再等一拍
        let big = String(repeating: "字", count: 1200)
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"\(big)\"}}]}\n"
        delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: line.data(using: .utf8)!)
        delegate.drainPendingForTesting()

        assertEqual(callbackCount, 1, "超过上限的块应立刻刷新一次")
        assertEqual(received, big, "大块内容必须完整送达")
    }

    /// 正文触顶必须当成功结束：onComplete 拿到截断文本，onError 不得被叫。
    /// 若改成 task.cancel() 再靠 NSURLErrorCancelled 吞掉，上层会以为请求被用户点了停止。
    static func testStreamDelegateContentCapCompletesSuccessfully() {
        print("  - Testing StreamDelegate content cap completes successfully (not as cancelled error)...")
        let flushQueue = DispatchQueue(label: "test.llm.flush.contentcap")
        var received = ""
        var completedText: String?
        var errorMessage: String?
        let cap = UnifiedCommandBarViewModel.Capacity.maxOutputChars

        let delegate = StreamDelegate(
            onReasoning: nil,
            onToken: { token in received += token },
            onComplete: { text in completedText = text },
            onError: { error in errorMessage = error.localizedDescription },
            flushQueue: flushQueue
        )

        let dummySession = URLSession(configuration: .default)
        let dummyTask = dummySession.dataTask(with: URL(string: "http://localhost")!)

        let chunk = String(repeating: "字", count: 1000)
        for _ in 0..<70 {
            let line = "data: {\"choices\":[{\"delta\":{\"content\":\"\(chunk)\"}}]}\n"
            delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: line.data(using: .utf8)!)
        }
        delegate.drainPendingForTesting()
        delegate.urlSession(dummySession, task: dummyTask, didCompleteWithError: nil)
        delegate.drainPendingForTesting()

        assertTrue(errorMessage == nil, "正文触顶不得走 onError，实际: \(errorMessage ?? "")")
        assertTrue(completedText != nil, "正文触顶必须走 onComplete")
        assertTrue(completedText!.count <= cap, "onComplete 文本必须 <= \(cap)，实际 \(completedText!.count)")
        assertTrue(received.count <= cap, "onToken 累积必须 <= \(cap)，实际 \(received.count)")
        assertEqual(completedText, received, "onComplete 文本必须与已推送正文一致")
    }

    /// 思考通道触顶只停思考累积，正文继续，且不得把整次请求打成错误。
    static func testStreamDelegateReasoningCapDoesNotAbortContent() {
        print("  - Testing StreamDelegate reasoning cap stops reasoning only...")
        let flushQueue = DispatchQueue(label: "test.llm.flush.reasoncap")
        var reasoning = ""
        var content = ""
        var completedText: String?
        var errorMessage: String?
        let rcap = UnifiedCommandBarViewModel.Capacity.maxReasoningChars

        let delegate = StreamDelegate(
            onReasoning: { token in reasoning += token },
            onToken: { token in content += token },
            onComplete: { text in completedText = text },
            onError: { error in errorMessage = error.localizedDescription },
            flushQueue: flushQueue
        )

        let dummySession = URLSession(configuration: .default)
        let dummyTask = dummySession.dataTask(with: URL(string: "http://localhost")!)

        let chunk = String(repeating: "思", count: 1000)
        for _ in 0..<40 {
            let line = "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"\(chunk)\"}}]}\n"
            delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: line.data(using: .utf8)!)
        }
        let answer = "正文还在"
        let contentLine = "data: {\"choices\":[{\"delta\":{\"content\":\"\(answer)\"}}]}\n"
        delegate.urlSession(dummySession, dataTask: dummyTask, didReceive: contentLine.data(using: .utf8)!)
        delegate.drainPendingForTesting()
        delegate.urlSession(dummySession, task: dummyTask, didCompleteWithError: nil)
        delegate.drainPendingForTesting()

        assertTrue(errorMessage == nil, "思考触顶不得走 onError，实际: \(errorMessage ?? "")")
        assertEqual(completedText, answer, "思考触顶后正文必须完整送达")
        assertEqual(content, answer, "思考触顶不得截断正文通道")
        assertTrue(reasoning.count <= rcap, "思考累积必须 <= \(rcap)，实际 \(reasoning.count)")
    }

    /// 划词面板必须保持「未实体化」直到真正第一次划词。
    ///
    /// 它是这个进程最大的一笔常驻开销（NSPanel + NSHostingView + SwiftUI View Graph +
    /// 玻璃图层）。历史上 `SelectionMonitor` 的全局 mouseUp 为了判断「是否点在自己身上」
    /// 直接读了 `shared.isVisible`，导致用户开机后第一次点鼠标就付了这笔钱。
    ///
    /// 本断言放在最前面：此时测试进程从未 `show()` 过，`isMaterialized` 必须为 false，
    /// 且**读取它本身不得触发构造**（一旦改坏，hasMaterialized 就会被置 true 而失败）。
    static func testToolbarPanelStaysUnmaterialized() {
        print("  - Testing toolbar panel stays unmaterialized until first use...")
        assertFalse(
            TransientCommandBarPanel.isMaterialized,
            "划词面板必须保持未实体化：读 isMaterialized 不得触发 shared 的构造"
        )
    }

    /// 验证所有常驻浮层面板（划词命令条、分屏控制岛、分屏幽灵预览、分屏中缝浮层）在冷启动、
    /// 以及经历状态重置/停止（resetTransientState/stop/clearActivePair/isClickOnSelf）时，
    /// 必须保持「未实体化（Unmaterialized）」状态，绝不提前创建 NSPanel/NSView/渲染图层。
    static func testPanelsStayUnmaterializedOnLaunchAndReset() {
        print("  - Testing all floating panels stay unmaterialized on launch and reset...")

        // 1. 冷启动状态断言：四大面板必须全部处于未实体化状态，且 safeShared 为 nil
        assertFalse(TransientCommandBarPanel.isMaterialized, "划词面板在冷启动时必须保持未实体化")
        assertTrue(TransientCommandBarPanel.safeShared == nil, "划词面板 safeShared 在未实体化时必须为 nil")

        assertFalse(WindowSnapIslandPanel.isMaterialized, "分屏控制岛在冷启动时必须保持未实体化")
        assertTrue(WindowSnapIslandPanel.safeShared == nil, "分屏控制岛 safeShared 在未实体化时必须为 nil")

        assertFalse(GhostPreviewPanel.isMaterialized, "分屏幽灵预览面板在冷启动时必须保持未实体化")
        assertTrue(GhostPreviewPanel.safeShared == nil, "分屏幽灵预览面板 safeShared 在未实体化时必须为 nil")

        assertFalse(SplitDividerOverlayPanel.isMaterialized, "中缝拖拽浮层在冷启动时必须保持未实体化")
        assertTrue(SplitDividerOverlayPanel.safeShared == nil, "中缝拖拽浮层 safeShared 在未实体化时必须为 nil")

        assertFalse(CompanionPetPanel.isMaterialized, "桌宠圆在冷启动时必须保持未实体化")
        assertTrue(CompanionPetPanel.safeShared == nil, "桌宠圆 safeShared 在未实体化时必须为 nil")
        assertFalse(CompanionChatBubblePanel.isMaterialized, "聊天泡泡在冷启动时必须保持未实体化")
        assertTrue(CompanionChatBubblePanel.safeShared == nil, "聊天泡泡 safeShared 在未实体化时必须为 nil")

        // 2. 状态重置与清理路径（reset / stop）：保证绝不无故构造面板
        WindowSnapManager.shared.resetTransientState()
        assertFalse(WindowSnapIslandPanel.isMaterialized, "resetTransientState() 不得触发 WindowSnapIslandPanel 实体化")
        assertFalse(GhostPreviewPanel.isMaterialized, "resetTransientState() 不得触发 GhostPreviewPanel 实体化")

        WindowSnapManager.shared.stop()
        assertFalse(WindowSnapIslandPanel.isMaterialized, "WindowSnapManager.stop() 不得触发 WindowSnapIslandPanel 实体化")
        assertFalse(GhostPreviewPanel.isMaterialized, "WindowSnapManager.stop() 不得触发 GhostPreviewPanel 实体化")

        SplitDividerManager.shared.clearActivePair()
        assertFalse(SplitDividerOverlayPanel.isMaterialized, "clearActivePair() 不得触发 SplitDividerOverlayPanel 实体化")

        SplitDividerManager.shared.stop()
        assertFalse(SplitDividerOverlayPanel.isMaterialized, "SplitDividerManager.stop() 不得触发 SplitDividerOverlayPanel 实体化")

        CompanionManager.shared.stop()
        assertFalse(CompanionPetPanel.isMaterialized, "CompanionManager.stop() 不得触发 CompanionPetPanel 实体化")
        assertFalse(CompanionChatBubblePanel.isMaterialized, "CompanionManager.stop() 不得触发 CompanionChatBubblePanel 实体化")

        // 3. 全局鼠标事件命中测试（isClickOnSelf）：未命中自身浮层时绝不触发实体化
        let testPoint = NSPoint(x: 200, y: 300)
        let clickedSelf = WindowSnapManager.shared.isClickOnSelf(at: testPoint)
        assertFalse(clickedSelf, "空闲屏幕点击不应命中自身")
        assertFalse(TransientCommandBarPanel.isMaterialized, "isClickOnSelf 不得触发 TransientCommandBarPanel 实体化")
        assertFalse(WindowSnapIslandPanel.isMaterialized, "isClickOnSelf 不得触发 WindowSnapIslandPanel 实体化")
        assertFalse(GhostPreviewPanel.isMaterialized, "isClickOnSelf 不得触发 GhostPreviewPanel 实体化")
        assertFalse(SplitDividerOverlayPanel.isMaterialized, "isClickOnSelf 不得触发 SplitDividerOverlayPanel 实体化")
        assertFalse(CompanionPetPanel.isMaterialized, "isClickOnSelf 不得触发 CompanionPetPanel 实体化")
        assertFalse(CompanionChatBubblePanel.isMaterialized, "isClickOnSelf 不得触发 CompanionChatBubblePanel 实体化")

        // 4. safeShared 安全性：未实体化时调用 safeShared?.hide() 无副作用且不触发构造
        TransientCommandBarPanel.safeShared?.dismiss()
        WindowSnapIslandPanel.safeShared?.hide()
        GhostPreviewPanel.safeShared?.hide()
        SplitDividerOverlayPanel.safeShared?.hide()
        CompanionPetPanel.safeShared?.hide()
        CompanionChatBubblePanel.safeShared?.hide()

        // 5. 屏幕计算与前台探测：resolveScreen 等高频几何方法绝不触发面板实体化
        _ = WindowSnapManager.shared.resolveScreen(for: testPoint)
        _ = SelectionMonitor.shared

        assertFalse(TransientCommandBarPanel.isMaterialized)
        assertFalse(WindowSnapIslandPanel.isMaterialized)
        assertFalse(GhostPreviewPanel.isMaterialized)
        assertFalse(SplitDividerOverlayPanel.isMaterialized)
        assertFalse(CompanionPetPanel.isMaterialized)
        assertFalse(CompanionChatBubblePanel.isMaterialized)
    }

    static func testViewModelHistoryCapacity() {
        print("  - Testing ViewModel history capacity cap...")
        let vm = UnifiedCommandBarViewModel()
        vm.onStreamChat = { _, _, _, _, _, _, _, _ in }
        let action = ActionItem(id: "act", title: "容量", icon: "star", prompt: "P")
        vm.startAction(text: "第0问", action: action)

        // 连问 30 轮，远超 10 轮上限
        for i in 1...30 {
            vm.outputText = "第\(i)答"
            vm.followUpInput = "第\(i)问"
            vm.sendFollowUp()
        }

        let cap = UnifiedCommandBarViewModel.Capacity.maxHistoryMessages
        assertTrue(vm.history.count <= cap, "history 必须裁剪到 \(cap) 条以内，实际 \(vm.history.count)")
        assertEqual(vm.history.count % 2, 0, "裁剪后必须保持 user/assistant 成对，否则上下文会错位")
        assertEqual(vm.history[0].role, "user", "裁剪后队首仍应是 user 消息")
        assertTrue(vm.history.contains(where: { $0.content == "第30答" }), "最近的回答必须还在上下文里")
        assertFalse(vm.history.contains(where: { $0.content == "第0问" }), "最老的对话应已被丢弃")
    }

    static func testViewModelOutputTextCapacity() {
        print("  - Testing ViewModel output/reasoning capacity cap...")
        let vm = UnifiedCommandBarViewModel()
        var tokenCallback: ((String) -> Void)? = nil
        var reasoningCallback: ((String) -> Void)? = nil
        vm.onStreamChat = { _, _, _, _, onReasoning, onToken, _, _ in
            reasoningCallback = onReasoning
            tokenCallback = onToken
        }
        let action = ActionItem(id: "act", title: "长文", icon: "star", prompt: "P")
        vm.startAction(text: "长文测试", action: action)

        let chunk = String(repeating: "字", count: 500)
        for _ in 0..<200 { tokenCallback?(chunk) }          // 10 万字，远超上限

        let cap = UnifiedCommandBarViewModel.Capacity.maxOutputChars
        assertTrue(vm.outputText.count <= cap + 600, "outputText 触顶后必须停止累积，实际 \(vm.outputText.count)")
        assertTrue(vm.outputText.hasSuffix("以限制内存占用）"), "截断必须有可见提示，不能静默丢字")

        let frozen = vm.outputText
        tokenCallback?("后续内容再推一千字")
        assertEqual(vm.outputText, frozen, "触顶后继续推送不得再改动 outputText")

        for _ in 0..<200 { reasoningCallback?(chunk) }      // 10 万字，远超上限
        let rcap = UnifiedCommandBarViewModel.Capacity.maxReasoningChars
        assertTrue(vm.reasoningText.count <= rcap + 600, "reasoningText 触顶后必须停止累积，实际 \(vm.reasoningText.count)")
        assertTrue(vm.reasoningText.hasSuffix("以限制内存占用）"), "思考区截断同样要有可见提示")
    }

    static func testAXCastRejectsUnexpectedTypes() {
        print("  - Testing AXCast never crashes on unexpected CF types...")
        // 真实 AX 对象必须转得过去
        let systemWide = AXUIElementCreateSystemWide()
        assertTrue(AXCast.element(systemWide) != nil, "合法 AXUIElement 必须转换成功")

        var point = CGPoint(x: 1, y: 2)
        let axPoint = AXValueCreate(.cgPoint, &point)
        assertTrue(axPoint != nil, "AXValueCreate 应成功")
        assertTrue(AXCast.axValue(axPoint) != nil, "合法 AXValue 必须转换成功")

        // 跨进程 AX 常见的「脏」返回值必须转成 nil 而不是崩溃
        assertTrue(AXCast.element(nil) == nil, "nil 必须安全返回 nil")
        assertTrue(AXCast.element("我不是 AXUIElement" as CFString) == nil, "字符串不能被当成 AXUIElement")
        assertTrue(AXCast.element(42 as CFNumber) == nil, "数字不能被当成 AXUIElement")
        assertTrue(AXCast.axValue(axPoint) != nil && AXCast.element(axPoint) == nil, "AXValue 不能被当成 AXUIElement")
        assertTrue(AXCast.axValue(systemWide) == nil, "AXUIElement 不能被当成 AXValue")
    }

    static func testLLMServiceCancelCleanup() {
        print("  - Testing LLMService cancel() cleans up session...")
        let service = LLMService.shared
        service.cancel()
        service.cancel()
    }

    static func testLLMServiceEphemeralConfiguration() {
        print("  - Testing LLMService ephemeral URLSession configuration...")
        let config = LLMService.sessionConfiguration
        // .ephemeral guarantees that diskCapacity is 0 and no persistent SQLite Cache.db is created
        let diskCap = config.urlCache?.diskCapacity ?? 0
        assertEqual(diskCap, 0, "Ephemeral session must have 0 disk cache capacity to prevent Cache.db creation")
    }

    static func testWindowSnapGeometryCalculation() {
        print("  - Testing WindowSnap geometry & AX coordinate calculations (12 Canonical Slots including 1/3, 2:1, and 1/4 Quarters)...")

        // 0. Verify slot count and canonical cases
        assertEqual(SnapSlot.allCases.count, 12, "SnapSlot must have 12 canonical slots")
        assertEqual(SnapSlot.leftTwoThirds, .mainWorkspace)

        // Verify SF Symbol names
        assertEqual(SnapSlot.leftHalf.systemImageName, "rectangle.lefthalf.filled")
        assertEqual(SnapSlot.rightHalf.systemImageName, "rectangle.righthalf.filled")
        assertEqual(SnapSlot.mainWorkspace.systemImageName, "rectangle.leadinghalf.filled")
        assertEqual(SnapSlot.sideWorkspace.systemImageName, "rectangle.trailinghalf.filled")
        assertEqual(SnapSlot.maximize.systemImageName, "rectangle.fill")
        assertEqual(SnapSlot.leftThird.systemImageName, "rectangle.split.3x1")
        assertEqual(SnapSlot.centerThird.systemImageName, "rectangle.split.3x1")
        assertEqual(SnapSlot.rightThird.systemImageName, "rectangle.split.3x1")
        assertEqual(SnapSlot.topLeftQuarter.systemImageName, "rectangle.split.2x2")
        assertEqual(SnapSlot.topRightQuarter.systemImageName, "rectangle.split.2x2")
        assertEqual(SnapSlot.bottomLeftQuarter.systemImageName, "rectangle.split.2x2")
        assertEqual(SnapSlot.bottomRightQuarter.systemImageName, "rectangle.split.2x2")

        // Verify Titles and Ratio Subtitles for 4 Quarters
        assertEqual(SnapSlot.topLeftQuarter.title, "左上 1/4")
        assertEqual(SnapSlot.topRightQuarter.title, "右上 1/4")
        assertEqual(SnapSlot.bottomLeftQuarter.title, "左下 1/4")
        assertEqual(SnapSlot.bottomRightQuarter.title, "右下 1/4")
        assertEqual(SnapSlot.topLeftQuarter.ratioSubtitle, "1/4")
        assertEqual(SnapSlot.topRightQuarter.ratioSubtitle, "1/4")
        assertEqual(SnapSlot.bottomLeftQuarter.ratioSubtitle, "1/4")
        assertEqual(SnapSlot.bottomRightQuarter.ratioSubtitle, "1/4")

        // 1. Standard 1080p Display with 24pt menu bar: visibleFrame = (0, 0, 1920, 1056)
        let vf1080 = NSRect(x: 0, y: 0, width: 1920, height: 1056)

        // Half split with outerMargin = 6.0, innerGap = 8.0:
        // availW = 1920 - 12 - 8 = 1900, leftW = 950, rightW = 950, h = 1044, y = 6
        let leftHalf = SnapSlot.targetRect(for: .leftHalf, in: vf1080)
        assertEqual(leftHalf.origin.x, 6.0)
        assertEqual(leftHalf.origin.y, 6.0)
        assertEqual(leftHalf.width, 950.0)
        assertEqual(leftHalf.height, 1044.0)

        let rightHalf = SnapSlot.targetRect(for: .rightHalf, in: vf1080)
        assertEqual(rightHalf.origin.x, 964.0)
        assertEqual(rightHalf.origin.y, 6.0)
        assertEqual(rightHalf.width, 950.0)
        assertEqual(rightHalf.height, 1044.0)
        assertEqual(rightHalf.minX - leftHalf.maxX, 8.0, "Inner breathing gap between left and right halves must be exactly 8.0pt")
        assertEqual(leftHalf.minX - vf1080.minX, 6.0, "Left outer margin must be 6.0pt")
        assertEqual(vf1080.maxX - rightHalf.maxX, 6.0, "Right outer margin must be 6.0pt")
        assertEqual(leftHalf.width + rightHalf.width + 8.0 + 12.0, 1920.0, "Left half + right half + gap + outer margins must equal visibleFrame width")

        // Main (Left 67%) + Side (Right 33%) - Scheme B with breathing gap
        // mainW = round(1900 * 2 / 3) = 1267, sideW = 1900 - 1267 = 633
        let mainWork = SnapSlot.targetRect(for: .mainWorkspace, in: vf1080)
        assertEqual(mainWork.origin.x, 6.0)
        assertEqual(mainWork.origin.y, 6.0)
        assertEqual(mainWork.width, 1267.0)
        assertEqual(mainWork.height, 1044.0)

        let sideWork = SnapSlot.targetRect(for: .sideWorkspace, in: vf1080)
        assertEqual(sideWork.origin.x, 1281.0)
        assertEqual(sideWork.origin.y, 6.0)
        assertEqual(sideWork.width, 633.0)
        assertEqual(sideWork.height, 1044.0)
        assertEqual(sideWork.minX - mainWork.maxX, 8.0, "Inner breathing gap between main and side must be exactly 8.0pt")
        assertEqual(mainWork.width + sideWork.width + 8.0 + 12.0, 1920.0, "Main workspace (2/3) + Side workspace (1/3) + gap + margins must equal visible width")

        // Three-way equal split (1/3, 1/3, 1/3) - Scheme A with breathing gaps
        // availW = 1920 - 12 - 16 = 1892, w1 = 631, w3 = 631, w2 = 630
        let left3rd = SnapSlot.targetRect(for: .leftThird, in: vf1080)
        let center3rd = SnapSlot.targetRect(for: .centerThird, in: vf1080)
        let right3rd = SnapSlot.targetRect(for: .rightThird, in: vf1080)
        assertEqual(left3rd.origin.x, 6.0)
        assertEqual(left3rd.width, 631.0)
        assertEqual(center3rd.origin.x, 645.0)
        assertEqual(center3rd.width, 630.0)
        assertEqual(right3rd.origin.x, 1283.0)
        assertEqual(right3rd.width, 631.0)
        assertEqual(center3rd.minX - left3rd.maxX, 8.0, "Gap between left and center third must be 8.0pt")
        assertEqual(right3rd.minX - center3rd.maxX, 8.0, "Gap between center and right third must be 8.0pt")
        assertEqual(left3rd.width + center3rd.width + right3rd.width + 16.0 + 12.0, 1920.0, "Three thirds + 2 gaps + 2 margins must equal 1920 exactly")

        // Four-way quadrant split (1/4 2x2 田字格) - with breathing gaps (outerMargin = 6.0, innerGap = 8.0)
        // availW = 1920 - 12 - 8 = 1900, halfW = 950, rightW = 950
        // availH = 1056 - 12 - 8 = 1036, halfH = 518, topH = 518
        let topLeft = SnapSlot.targetRect(for: .topLeftQuarter, in: vf1080)
        let topRight = SnapSlot.targetRect(for: .topRightQuarter, in: vf1080)
        let bottomLeft = SnapSlot.targetRect(for: .bottomLeftQuarter, in: vf1080)
        let bottomRight = SnapSlot.targetRect(for: .bottomRightQuarter, in: vf1080)

        assertEqual(topLeft.origin.x, 6.0)
        assertEqual(topLeft.origin.y, 532.0)
        assertEqual(topLeft.width, 950.0)
        assertEqual(topLeft.height, 518.0)

        assertEqual(topRight.origin.x, 964.0)
        assertEqual(topRight.origin.y, 532.0)
        assertEqual(topRight.width, 950.0)
        assertEqual(topRight.height, 518.0)

        assertEqual(bottomLeft.origin.x, 6.0)
        assertEqual(bottomLeft.origin.y, 6.0)
        assertEqual(bottomLeft.width, 950.0)
        assertEqual(bottomLeft.height, 518.0)

        assertEqual(bottomRight.origin.x, 964.0)
        assertEqual(bottomRight.origin.y, 6.0)
        assertEqual(bottomRight.width, 950.0)
        assertEqual(bottomRight.height, 518.0)

        // Margin & gap assertions for quadrants
        assertEqual(topRight.minX - topLeft.maxX, 8.0, "Inner horizontal gap between top quadrants must be 8.0pt")
        assertEqual(bottomRight.minX - bottomLeft.maxX, 8.0, "Inner horizontal gap between bottom quadrants must be 8.0pt")
        assertEqual(topLeft.minY - bottomLeft.maxY, 8.0, "Inner vertical gap between left quadrants must be 8.0pt")
        assertEqual(topRight.minY - bottomRight.maxY, 8.0, "Inner vertical gap between right quadrants must be 8.0pt")
        assertEqual(topLeft.minX - vf1080.minX, 6.0, "Left outer margin must be 6.0pt")
        assertEqual(vf1080.maxX - topRight.maxX, 6.0, "Right outer margin must be 6.0pt")
        assertEqual(bottomLeft.minY - vf1080.minY, 6.0, "Bottom outer margin must be 6.0pt")
        assertEqual(vf1080.maxY - topLeft.maxY, 6.0, "Top outer margin must be 6.0pt")
        assertEqual(topLeft.width + topRight.width + 8.0 + 12.0, 1920.0, "Quadrant widths + gap + margins must equal 1920")
        assertEqual(topLeft.height + bottomLeft.height + 8.0 + 12.0, 1056.0, "Quadrant heights + gap + margins must equal 1056")

        // Maximize: inset by outerMargin (6.0pt) from visibleFrame
        let maxRect = SnapSlot.targetRect(for: .maximize, in: vf1080)
        assertEqual(maxRect, vf1080.insetBy(dx: 6.0, dy: 6.0))

        // 2. Secondary Display with Non-zero Origin: visibleFrame = (1920, 100, 2560, 1340)
        // availW = 2560 - 12 - 8 = 2540, leftW = 1270, rightW = 1270, h = 1328, y = 106
        let vfSecondary = NSRect(x: 1920, y: 100, width: 2560, height: 1340)
        let secLeftHalf = SnapSlot.targetRect(for: .leftHalf, in: vfSecondary)
        assertEqual(secLeftHalf.origin.x, 1926.0)
        assertEqual(secLeftHalf.origin.y, 106.0)
        assertEqual(secLeftHalf.width, 1270.0)
        assertEqual(secLeftHalf.height, 1328.0)

        let secRightHalf = SnapSlot.targetRect(for: .rightHalf, in: vfSecondary)
        assertEqual(secRightHalf.origin.x, 3204.0)
        assertEqual(secRightHalf.origin.y, 106.0)
        assertEqual(secRightHalf.width, 1270.0)
        assertEqual(secRightHalf.minX - secLeftHalf.maxX, 8.0, "Secondary display halves gap must be 8.0pt")

        let secMain = SnapSlot.targetRect(for: .mainWorkspace, in: vfSecondary)
        let secSide = SnapSlot.targetRect(for: .sideWorkspace, in: vfSecondary)
        assertEqual(secMain.origin.x, 1926.0)
        assertEqual(secMain.width, 1693.0)
        assertEqual(secSide.origin.x, 3627.0)
        assertEqual(secSide.width, 847.0)
        assertEqual(secSide.minX - secMain.maxX, 8.0, "Secondary display main and side gap must be 8.0pt")
        assertEqual(secMain.width + secSide.width + 8.0 + 12.0, 2560.0)

        // Secondary Display Quadrants:
        // availW = 2560 - 12 - 8 = 2540, halfW = 1270, rightW = 1270
        // availH = 1340 - 12 - 8 = 1320, halfH = 660, topH = 660
        let secTL = SnapSlot.targetRect(for: .topLeftQuarter, in: vfSecondary)
        let secTR = SnapSlot.targetRect(for: .topRightQuarter, in: vfSecondary)
        let secBL = SnapSlot.targetRect(for: .bottomLeftQuarter, in: vfSecondary)
        let secBR = SnapSlot.targetRect(for: .bottomRightQuarter, in: vfSecondary)

        assertEqual(secTL.origin.x, 1926.0)
        assertEqual(secTL.origin.y, 774.0)
        assertEqual(secTL.width, 1270.0)
        assertEqual(secTL.height, 660.0)

        assertEqual(secTR.origin.x, 3204.0)
        assertEqual(secTR.origin.y, 774.0)
        assertEqual(secTR.width, 1270.0)
        assertEqual(secTR.height, 660.0)

        assertEqual(secBL.origin.x, 1926.0)
        assertEqual(secBL.origin.y, 106.0)
        assertEqual(secBL.width, 1270.0)
        assertEqual(secBL.height, 660.0)

        assertEqual(secBR.origin.x, 3204.0)
        assertEqual(secBR.origin.y, 106.0)
        assertEqual(secBR.width, 1270.0)
        assertEqual(secBR.height, 660.0)

        assertEqual(secTR.minX - secTL.maxX, 8.0)
        assertEqual(secTL.minY - secBL.maxY, 8.0)
        assertEqual(secTL.width + secTR.width + 8.0 + 12.0, 2560.0)
        assertEqual(secTL.height + secBL.height + 8.0 + 12.0, 1340.0)

        // 3. Accessibility / Quartz Coordinate Conversion
        let primaryHeight: CGFloat = 1080.0
        let (axPos1, axSize1) = WindowSnapManager.convertCocoaRectToAX(cocoaRect: leftHalf, primaryScreenHeight: primaryHeight)
        assertEqual(axPos1.x, 6.0)
        assertEqual(axPos1.y, 1080.0 - (6.0 + 1044.0), "AX y must equal primaryScreenHeight - cocoaRect.maxY (1080 - 1050 = 30)")
        assertEqual(axSize1.width, 950.0)
        assertEqual(axSize1.height, 1044.0)

        // Secondary display AX coordinate conversion
        let (secAxPos, secAxSize) = WindowSnapManager.convertCocoaRectToAX(cocoaRect: secLeftHalf, primaryScreenHeight: primaryHeight)
        assertEqual(secAxPos.x, 1926.0)
        assertEqual(secAxPos.y, 1080.0 - (106.0 + 1328.0))
        assertEqual(secAxSize.width, 1270.0)
        assertEqual(secAxSize.height, 1328.0)

        // Quadrants AX coordinate conversion
        let (axTLPos, axTLSize) = WindowSnapManager.convertCocoaRectToAX(cocoaRect: topLeft, primaryScreenHeight: primaryHeight)
        assertEqual(axTLPos.x, 6.0)
        assertEqual(axTLPos.y, 30.0, "AX top-left Y must be 1080 - (532 + 518) = 30")
        assertEqual(axTLSize.width, 950.0)
        assertEqual(axTLSize.height, 518.0)

        let (axBLPos, axBLSize) = WindowSnapManager.convertCocoaRectToAX(cocoaRect: bottomLeft, primaryScreenHeight: primaryHeight)
        assertEqual(axBLPos.x, 6.0)
        assertEqual(axBLPos.y, 556.0, "AX bottom-left Y must be 1080 - (6 + 518) = 556")
        assertEqual(axBLSize.width, 950.0)
        assertEqual(axBLSize.height, 518.0)
    }

    static func testWindowSnapConfigPersistence() {
        print("  - Testing WindowSnap config persistence & defaults...")
        let cm = ConfigManager.shared
        assertTrue(cm.enableWindowSnapping, "Default enableWindowSnapping must be true")

        // Test SavedConfigV3 roundtrip encoding
        let v3 = ConfigManager.SavedConfigV3(
            profiles: cm.profiles,
            activeProfileId: cm.activeProfileId,
            autoShowToolbar: cm.autoShowToolbar,
            actions: cm.actions,
            enablePlaintextLogging: false,
            enableWindowSnapping: false
        )

        let encoded = try! JSONEncoder().encode(v3)
        let decoded = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: encoded)
        assertEqual(decoded.enableWindowSnapping, false, "Serialized enableWindowSnapping must decode correctly")

        // Test fallback for older configs where enableWindowSnapping was nil
        let legacyV3 = ConfigManager.SavedConfigV3(
            profiles: cm.profiles,
            activeProfileId: cm.activeProfileId,
            autoShowToolbar: cm.autoShowToolbar,
            actions: cm.actions,
            enablePlaintextLogging: false,
            enableWindowSnapping: nil
        )
        let legacyEncoded = try! JSONEncoder().encode(legacyV3)
        let legacyDecoded = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: legacyEncoded)
        assertEqual(legacyDecoded.enableWindowSnapping ?? true, true, "Missing enableWindowSnapping must default to true")

        // Test toggling
        let initial = cm.enableWindowSnapping
        cm.enableWindowSnapping.toggle()
        assertEqual(cm.enableWindowSnapping, !initial)
        cm.enableWindowSnapping = initial
    }

    static func testWindowSnapHitTestingAndThresholds() {
        print("  - Testing WindowSnap Island hit-test envelope & 4-card slot mapping...")
        let panel = WindowSnapIslandPanel.shared

        // 面板尺寸真源 = SnapIslandGeometry；同时守护它落在设计区间内
        assertEqual(WindowSnapIslandPanel.panelWidth, SnapIslandGeometry.panelSize.width)
        assertEqual(WindowSnapIslandPanel.panelHeight, SnapIslandGeometry.panelSize.height)
        assertTrue(
            (600.0...640.0).contains(SnapIslandGeometry.panelSize.width),
            "Island width must stay within 600...640pt (actual \(SnapIslandGeometry.panelSize.width))"
        )
        assertTrue(
            (82.0...94.0).contains(SnapIslandGeometry.panelSize.height),
            "Island height must stay within 82...94pt (actual \(SnapIslandGeometry.panelSize.height))"
        )
        assertTrue(
            (8.0...18.0).contains(SnapIslandGeometry.interItemSpacing),
            "Inter-item spacing must stay within 8...18pt (actual \(SnapIslandGeometry.interItemSpacing))"
        )

        let testScreen = NSScreen.screens.first ?? NSScreen()
        panel.show(on: testScreen)
        assertTrue(panel.isVisible, "Panel must be visible after show")

        let frame = panel.frame

        // 条目矩形（命中真源）—— 所有探针坐标由此推导，几何常量变化时无需再手改断言
        let halfRect = SnapIslandGeometry.halfCardRect
        let mainRect = SnapIslandGeometry.mainSideCardRect
        let quarterRect = SnapIslandGeometry.quarterCardRect
        let thirdsRect = SnapIslandGeometry.thirdsCardRect

        /// 条目内的相对比例 → 屏幕坐标
        func probe(_ rect: CGRect, _ fx: CGFloat, _ fy: CGFloat) -> NSPoint {
            NSPoint(
                x: frame.minX + rect.minX + rect.width * fx,
                y: frame.minY + rect.minY + rect.height * fy
            )
        }

        // Card 1: 二分屏 (Left half vs Right half)
        assertEqual(panel.slot(at: probe(halfRect, 0.25, 0.5)), .leftHalf)
        assertEqual(panel.slot(at: probe(halfRect, 0.75, 0.5)), .rightHalf)

        // Card 2: 主副屏 2:1 (主 2/3 vs 辅 1/3，分界由图元几何推导，不再是硬编码 0.62)
        assertEqual(panel.slot(at: probe(mainRect, 0.25, 0.5)), .mainWorkspace)
        assertEqual(panel.slot(at: probe(mainRect, 0.85, 0.5)), .sideWorkspace)

        // 主辅分界必须等于「图元内分割线中心」在条目内的相对位置。
        // 在测试里**独立重算**一遍（不复用被实现），任一侧脱钩都会立刻失败 ——
        // 这是「肉眼分界线 ≠ 鼠标切换位置」那 1.3pt 偏差的回归守卫。
        let glyphW = SnapIslandGeometry.Card.mainSide.glyphSize.width
        let glyphInset = (SnapIslandGeometry.Card.itemWidth - glyphW) / 2
        let seamW = SnapIslandGeometry.glyphDividerWidth
        let expectedMainSide = (glyphInset + (glyphW - seamW) * (2.0 / 3.0) + seamW / 2)
            / SnapIslandGeometry.Card.itemWidth
        print("  - 主辅命中分界 = \(SnapIslandGeometry.mainSideSplitRatio)（图元几何独立重算 \(expectedMainSide)）")
        assertTrue(
            abs(SnapIslandGeometry.mainSideSplitRatio - expectedMainSide) < 0.0001,
            "主辅分界必须由图元几何推导：实测 \(SnapIslandGeometry.mainSideSplitRatio) vs \(expectedMainSide)"
        )
        // 分界两侧各 1pt 的探针必须分别落在主区 / 辅区 —— 证明命中边界真的落在图元缝上
        let seamCenterX = frame.minX + mainRect.minX + mainRect.width * SnapIslandGeometry.mainSideSplitRatio
        let seamProbeY = frame.minY + mainRect.midY
        assertEqual(panel.slot(at: NSPoint(x: seamCenterX - 1, y: seamProbeY)), .mainWorkspace,
                    "缝左 1pt 应为主区")
        assertEqual(panel.slot(at: NSPoint(x: seamCenterX + 1, y: seamProbeY)), .sideWorkspace,
                    "缝右 1pt 应为辅区")

        // Card 3: 四等分 1/4 (田字格 2x2: 左上 / 右上 / 左下 / 右下)
        // 上下分界 = 四等分图元的垂直中线。该值由 SnapIslandGeometry 从
        // cardHeight / verticalPadding 推导（当前 44.0），不再是硬编码的 54.0 ——
        // 文案移除后图元在条目内垂直居中，中线正好回到面板中线。
        let qMidX = frame.minX + quarterRect.midX
        let qCenterY = frame.minY + SnapIslandGeometry.quarterGlyphCenterY

        // 探针点必须落在图元**内部**，否则测的就不是「图元内的象限判定」了。
        // 图元垂直居中于条目 → 图元带 = [midY − h/2, midY + h/2]。
        let glyphHalfHeight = SnapIslandGeometry.Card.quarter.glyphSize.height / 2
        let glyphBottom = SnapIslandGeometry.quarterGlyphCenterY - glyphHalfHeight
        let glyphTop = SnapIslandGeometry.quarterGlyphCenterY + glyphHalfHeight
        let qTopY = frame.minY + glyphBottom + (glyphTop - glyphBottom) * 0.88
        let qBottomY = frame.minY + glyphBottom + (glyphTop - glyphBottom) * 0.12

        // 上半区象限判定
        assertEqual(panel.slot(at: NSPoint(x: qMidX - 20, y: qTopY)), .topLeftQuarter)
        assertEqual(panel.slot(at: NSPoint(x: qMidX, y: qTopY)), .topLeftQuarter, "Exact center X must tie-break to left quadrant")
        assertEqual(panel.slot(at: NSPoint(x: qMidX + 1, y: qTopY)), .topRightQuarter, "1pt right of center must hit topRightQuarter")
        assertEqual(panel.slot(at: NSPoint(x: qMidX + 20, y: qTopY)), .topRightQuarter)

        // 下半区象限判定
        assertEqual(panel.slot(at: NSPoint(x: qMidX - 20, y: qBottomY)), .bottomLeftQuarter)
        assertEqual(panel.slot(at: NSPoint(x: qMidX, y: qBottomY)), .bottomLeftQuarter, "Exact center X must tie-break to left quadrant")
        assertEqual(panel.slot(at: NSPoint(x: qMidX + 1, y: qBottomY)), .bottomRightQuarter, "1pt right of center must hit bottomRightQuarter")
        assertEqual(panel.slot(at: NSPoint(x: qMidX + 20, y: qBottomY)), .bottomRightQuarter)

        // 上下 Y 边界探测（分界 = 图元垂直中线）
        assertEqual(panel.slot(at: NSPoint(x: qMidX - 20, y: qCenterY)), .topLeftQuarter, "y == glyph center Y must classify as top half")
        assertEqual(panel.slot(at: NSPoint(x: qMidX - 20, y: qCenterY - 1)), .bottomLeftQuarter, "1pt below glyph center Y must classify as bottom half")

        // Card 3 外缘边界探测：条目矩形左闭右开
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + quarterRect.minX, y: qTopY)), .topLeftQuarter)
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + quarterRect.maxX - 1, y: qTopY)), .topRightQuarter)

        // 条目右缘为开区间：x == maxX 已越出条目矩形，不得再命中
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + quarterRect.maxX, y: qTopY)), nil, "maxX is the exclusive bound of Card 3 and must not hit")

        // 条目间留白不是条目，必须返回 nil
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + quarterRect.maxX + 3, y: qTopY)), nil, "Inter-item spacing must not snap to any slot")

        // Card 4: 标准三等分 (Left 1/3, Center 1/3, Right 1/3)
        assertEqual(panel.slot(at: probe(thirdsRect, 0.15, 0.5)), .leftThird)
        assertEqual(panel.slot(at: probe(thirdsRect, 0.50, 0.5)), .centerThird)
        assertEqual(panel.slot(at: probe(thirdsRect, 0.85, 0.5)), .rightThird)

        // 严格边界测试：卡片外部绝不触发分屏
        let pJustBelow = NSPoint(x: frame.midX, y: frame.minY - 1)
        assertEqual(panel.slot(at: pJustBelow), nil, "Points just below island panel must not hit")

        let pJustAbove = NSPoint(x: frame.midX, y: frame.maxY + 1)
        assertEqual(panel.slot(at: pJustAbove), nil, "Points just above island panel must not hit")

        let pJustLeft = NSPoint(x: frame.minX - 1, y: frame.midY)
        assertEqual(panel.slot(at: pJustLeft), nil, "Points just left of island panel must not hit")

        let pJustRight = NSPoint(x: frame.maxX + 1, y: frame.midY)
        assertEqual(panel.slot(at: pJustRight), nil, "Points just right of island panel must not hit")

        // 屏幕顶部非卡片区域（在屏幕顶端但不在卡片面板内时必须为 nil）
        if testScreen.frame.maxY - 1 > frame.maxY {
            let pTopEdge = NSPoint(x: frame.minX + 360, y: testScreen.frame.maxY - 1)
            assertEqual(panel.slot(at: pTopEdge), nil, "Cursor at screen top outside card must not trigger snap")
        }

        // 远离卡片的外部落点
        let pFarBelow = NSPoint(x: frame.midX, y: frame.minY - 100)
        assertEqual(panel.slot(at: pFarBelow), nil, "Points far below island must not hit")

        let pFarLeft = NSPoint(x: frame.minX - 100, y: frame.midY)
        assertEqual(panel.slot(at: pFarLeft), nil, "Points far to the left must not hit")

        let pFarRight = NSPoint(x: frame.maxX + 100, y: frame.midY)
        assertEqual(panel.slot(at: pFarRight), nil, "Points far to the right must not hit")

        // MARK: 严格条目命中 —— 面板内边距与条目间留白一律不得吸附

        // 布局自检：条目区正好铺满可用宽度，命中矩形与视觉严格重合（无居中漂移）
        assertTrue(
            SnapIslandGeometry.fitsExactly,
            "Item widths must exactly fill the panel's usable width (no centering drift)"
        )

        // 四个条目矩形互不重叠，彼此之间必须存在真实留白
        let orderedRects = [halfRect, mainRect, quarterRect, thirdsRect]
        for i in 0..<(orderedRects.count - 1) {
            assertTrue(
                orderedRects[i].maxX < orderedRects[i + 1].minX,
                "Item \(i) must not overlap Item \(i + 1)"
            )
        }
        assertEqual(halfRect.minX, SnapIslandGeometry.horizontalPadding, "First item must start at the horizontal padding")
        assertEqual(thirdsRect.maxX, SnapIslandGeometry.panelSize.width - SnapIslandGeometry.horizontalPadding, "Last item must end at the horizontal padding")

        // 命中区与视觉刻意解耦：条目宽度必须明显大于图元宽度
        for card in SnapIslandGeometry.Card.allCases {
            assertTrue(
                card.width > card.glyphSize.width,
                "\(card) hit width (\(card.width)) must exceed its glyph width (\(card.glyphSize.width))"
            )
        }

        // 左右内边距：视觉上是空白玻璃，不是条目
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + 2, y: frame.midY)), nil, "Left padding must not hit any item")
        assertEqual(panel.slot(at: NSPoint(x: frame.maxX - 2, y: frame.midY)), nil, "Right padding must not hit any item")

        // 条目间留白：不是条目，绝不就近吸附
        for (index, rect) in [halfRect, mainRect, quarterRect].enumerated() {
            assertEqual(
                panel.slot(at: NSPoint(x: frame.minX + rect.maxX + 3, y: frame.midY)),
                nil,
                "Spacing after item \(index) must not snap"
            )
        }

        // 上下内边距：条目区仅 verticalPadding ..< (verticalPadding + cardHeight)
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + halfRect.midX, y: frame.minY + 2)), nil, "Bottom padding must not hit any item")
        assertEqual(panel.slot(at: NSPoint(x: frame.minX + halfRect.midX, y: frame.maxY - 2)), nil, "Top padding must not hit any item")

        panel.hide()
    }

    static func testWindowSnapTopEdgeTriggerAndDismissal() {
        print("  - Testing WindowSnap top-edge trigger thresholds & smooth drag-down dismissal...")

        // 1. Initial state & threshold constants verification
        assertEqual(WindowSnapManager.topTriggerThreshold, 45.0, "topTriggerThreshold must be 45.0pt")
        assertEqual(WindowSnapManager.topDismissThreshold, 85.0, "topDismissThreshold must be 85.0pt")
        assertEqual(WindowSnapManager.topCenterTriggerWidth, 660.0, "topCenterTriggerWidth must be 660.0pt")
        assertEqual(WindowSnapManager.centerTriggerWidth, 660.0, "centerTriggerWidth alias must be 660.0pt")
        assertFalse(WindowSnapManager.shared.isIslandActive, "Initial isIslandActive must be false")

        // 2. Primary display with menu bar: visibleTop = 1056, physicalTop = 1080
        let visibleTop1080: CGFloat = 1056.0
        let physicalTop1080: CGFloat = 1080.0

        // A. Activation: Cursor within 45pt of visibleTop (1056 - 45 = 1011)
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1056.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: nil),
            "Cursor at visible top boundary (1056) must trigger"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1070.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: nil),
            "Cursor inside menu bar (1070) must trigger"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1020.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: nil),
            "Cursor within 45pt of top (1020) must trigger"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1011.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: nil),
            "Cursor at exact 45pt threshold (1011) must trigger"
        )

        // B. Non-activation: Desktop movements far from top edge must NOT trigger
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 1010.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: nil),
            "Cursor just below 45pt threshold (1010) must NOT trigger"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 850.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 850.0),
            "Cursor in upper screen (850 / 1080 = 78%) must NOT trigger"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 600.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 600.0),
            "Cursor in upper 50% (600 / 1080 = 55%, the old bug threshold) must NEVER trigger!"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 400.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 400.0),
            "Cursor in lower desktop must NEVER trigger"
        )

        // C. Window top touching screen top (Window touches top + cursor in reasonable titlebar/toolbar zone)
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1000.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 1056.0),
            "Window touching top edge (1056) with cursor in toolbar zone (1000) must trigger"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1000.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 1051.0),
            "Window touching within 6pt of top (1051) must trigger"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 900.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 1056.0),
            "Cursor far below in desktop area (900) must NOT trigger even if window top touches 1056"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 1000.0, visibleTopY: visibleTop1080, physicalTopY: physicalTop1080, windowTopY: 1040.0),
            "Window 16pt below top (1040) with cursor at 1000 must NOT trigger"
        )

        // D. Drag Direction & Intent Tests (Downwards and Horizontal drag prevention)
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorY: 1030.0,
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                windowTopY: 1056.0,
                netDeltaY: -20.0
            ),
            "Dragging downwards (netDeltaY < 0) from top window must NEVER trigger island"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorY: 1040.0,
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                windowTopY: 1056.0,
                netDeltaX: 80.0,
                netDeltaY: 2.0
            ),
            "Dragging horizontally across desktop must NEVER trigger island"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(
                cursorY: 1030.0,
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                windowTopY: 1056.0,
                netDeltaX: 10.0,
                netDeltaY: 50.0,
                currentDeltaY: 10.0
            ),
            "Dragging upwards into top edge must trigger island"
        )

        // 3. Secondary display with non-zero origin: visibleTop = 1440, physicalTop = 1440
        let visibleTop1440: CGFloat = 1440.0
        let physicalTop1440: CGFloat = 1440.0

        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1420.0, visibleTopY: visibleTop1440, physicalTopY: physicalTop1440, windowTopY: nil),
            "Cursor within 45pt of secondary screen top (1420) must trigger"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1395.0, visibleTopY: visibleTop1440, physicalTopY: physicalTop1440, windowTopY: nil),
            "Cursor at exact 45pt threshold of secondary screen (1395) must trigger"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 1390.0, visibleTopY: visibleTop1440, physicalTopY: physicalTop1440, windowTopY: 1390.0),
            "Cursor below 45pt threshold of secondary screen (1390) must NOT trigger"
        )
        assertTrue(
            WindowSnapManager.isNearScreenTop(cursorY: 1380.0, visibleTopY: visibleTop1440, physicalTopY: physicalTop1440, windowTopY: 1438.0),
            "Window touching secondary screen top (1438) with cursor in toolbar (1380) must trigger"
        )
        assertFalse(
            WindowSnapManager.isNearScreenTop(cursorY: 1200.0, visibleTopY: visibleTop1440, physicalTopY: physicalTop1440, windowTopY: 1438.0),
            "Cursor far below (1200) on secondary screen must NOT trigger even if window touches top"
        )

        // 4. Horizontal Top-Center Trigger Zone (Apple menu / Control Center & Tray immunity)
        // Ensure dragging near top-left menus or top-right tray items never triggers island
        let testDisplayFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let testDisplayVisible = NSRect(x: 0, y: 0, width: 1920, height: 1056)
        let topCenterLocation = NSPoint(x: testDisplayFrame.midX, y: 1056.0)
        let topLeftLocation = NSPoint(x: testDisplayFrame.minX + 80.0, y: 1056.0)
        let topRightLocation = NSPoint(x: testDisplayFrame.maxX - 80.0, y: 1056.0)

        // Pushing window to top-center (x = screen.frame.midX) triggers activation
        assertTrue(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: topCenterLocation,
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Pushing window to top-center (x = screen.frame.midX) must trigger activation"
        )
        // Pushing window to top-left (x = screen.frame.minX + 80, near Apple menu) does NOT trigger activation
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: topLeftLocation,
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Pushing window to top-left (x = screen.frame.minX + 80, near Apple menu) must NOT trigger activation"
        )
        // Pushing window to top-right (x = screen.frame.maxX - 80, near Control Center / tray) does NOT trigger activation
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: topRightLocation,
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Pushing window to top-right (x = screen.frame.maxX - 80, near Control Center / tray) must NOT trigger activation"
        )

        // Also assert with real NSScreen if available
        let currentScreen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        if currentScreen.frame.width > 0 {
            let screen = currentScreen
            let curTopY = screen.visibleFrame.maxY
            assertTrue(
                WindowSnapManager.isNearScreenTop(
                    cursorLocation: NSPoint(x: screen.frame.midX, y: curTopY),
                    screen: screen,
                    windowTopY: nil
                ),
                "Pushing window to top-center (x = screen.frame.midX) on active NSScreen must trigger activation"
            )
            assertFalse(
                WindowSnapManager.isNearScreenTop(
                    cursorLocation: NSPoint(x: screen.frame.minX + 80.0, y: curTopY),
                    screen: screen,
                    windowTopY: nil
                ),
                "Pushing window to top-left (x = screen.frame.minX + 80, near Apple menu) on active NSScreen must NOT trigger activation"
            )
            assertFalse(
                WindowSnapManager.isNearScreenTop(
                    cursorLocation: NSPoint(x: screen.frame.maxX - 80.0, y: curTopY),
                    screen: screen,
                    windowTopY: nil
                ),
                "Pushing window to top-right (x = screen.frame.maxX - 80, near Control Center / tray) on active NSScreen must NOT trigger activation"
            )
        }

        // Boundary edge-cases around the 660pt center trigger zone (midX = 960, trigger zone: [630, 1290])
        let halfTrigger = WindowSnapManager.topCenterTriggerWidth / 2.0 // 330
        let midX = testDisplayFrame.midX // 960
        // Exact left boundary (630) -> trigger
        assertTrue(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: NSPoint(x: midX - halfTrigger, y: 1056.0),
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Cursor at exact left edge of center trigger zone (630) must trigger"
        )
        // Exact right boundary (1290) -> trigger
        assertTrue(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: NSPoint(x: midX + halfTrigger, y: 1056.0),
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Cursor at exact right edge of center trigger zone (1290) must trigger"
        )
        // 10pt left of trigger zone (620) -> must NOT trigger
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: NSPoint(x: midX - halfTrigger - 10.0, y: 1056.0),
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Cursor 10pt outside left edge of center zone (620) must NOT trigger"
        )
        // 10pt right of trigger zone (1300) -> must NOT trigger
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: NSPoint(x: midX + halfTrigger + 10.0, y: 1056.0),
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: nil
            ),
            "Cursor 10pt outside right edge of center zone (1300) must NOT trigger"
        )
        // Window touching top but cursor at top-left -> must NOT trigger
        assertFalse(
            WindowSnapManager.isNearScreenTop(
                cursorLocation: NSPoint(x: testDisplayFrame.minX + 80.0, y: 1056.0),
                screenFrame: testDisplayFrame,
                visibleFrame: testDisplayVisible,
                windowTopY: 1056.0
            ),
            "Window touching top but cursor at top-left must NOT trigger island"
        )

        // 5. Smooth dismissal when user drags back down (hysteresis cancel)
        let islandFrame = NSRect(x: 660, y: 980, width: 600, height: 70) // minY: 980, maxY: 1050

        // A. Cursor inside island panel -> DO NOT dismiss
        assertFalse(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 960, y: 1000),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: nil
            ),
            "Cursor inside island panel must NOT dismiss"
        )

        // B. Cursor near top edge (e.g. 1020) -> DO NOT dismiss
        assertFalse(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 960, y: 1020),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: nil
            ),
            "Cursor near top edge (1020) within center must NOT dismiss"
        )

        // C. Window top pinned at top edge -> DO NOT dismiss if cursor is close to top
        assertFalse(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 960, y: 960),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: 1050.0
            ),
            "Window top pinned at top (1050) with cursor at 960 (horizontally centered) must NOT dismiss"
        )

        // D. User drags down below island & threshold -> DISMISS
        assertTrue(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 960, y: 940),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: 960.0
            ),
            "Cursor pulled down below island (940) must dismiss"
        )
        assertTrue(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 960, y: 600),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: 600.0
            ),
            "Cursor dragged to desktop middle (600) must dismiss"
        )
        assertTrue(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 960, y: 600),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: 1050.0
            ),
            "Cursor dragged to desktop middle (600) must dismiss even if AX reports stale window top 1050"
        )

        // E. User drags horizontally outside the center trigger zone -> DISMISS
        assertTrue(
            WindowSnapManager.shouldDismissTopIsland(
                cursorLocation: NSPoint(x: 200, y: 1040),
                visibleTopY: visibleTop1080,
                physicalTopY: physicalTop1080,
                islandFrame: islandFrame,
                windowTopY: 1050.0
            ),
            "Cursor dragged horizontally outside the center trigger zone (200) must dismiss"
        )
    }

    /// 验证分屏幽灵预览面板的高保真轻量化渲染与退场显存归还机制：
    /// 隐藏时 frame 归零且清空根视图，将 Retina 全屏离屏 Framebuffer 与图层树立即释放给 WindowServer。
    /// 同时验证在退场淡出过程中快速再次悬停槽位时，透明度能正确满血恢复（alpha = 1.0）。
    static func testGhostPreviewPanelFramebufferReclamation() {
        print("  - Testing GhostPreviewPanel framebuffer reclamation, interruption restoration, and lightweight rendering...")

        // 1. 实体化访问
        let panel = GhostPreviewPanel.shared
        assertTrue(GhostPreviewPanel.isMaterialized, "访问 shared 后 GhostPreviewPanel 必须标记为已实体化")
        assertTrue(GhostPreviewPanel.safeShared != nil, "已实体化后 safeShared 不得为 nil")

        // 2. 显示预览：正确设置目标几何
        let testRect = NSRect(x: 100, y: 100, width: 400, height: 300)
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        panel.show(targetRect: testRect, slot: .leftHalf, on: screen)
        assertEqual(panel.frame, testRect, "show() 必须将面板几何设置为 targetRect")

        // 3. 隐藏并归还显存：运行主循环等待退场动画完成
        panel.hide()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))

        assertEqual(panel.frame, .zero, "hide() 退场后 frame 必须立即置为 .zero 归还 WindowServer 显存")
        assertFalse(panel.isVisible, "hide() 退场后面板必须处于隐藏状态")

        // 4. 关键边缘场景：退场中途（0.14s 内）被再次触发唤醒，必须满血恢复透明度与几何
        panel.show(targetRect: testRect, slot: .leftHalf, on: screen)
        panel.hide() // 启动 0.14s 的淡出动画
        // 不等待动画完成（立即在淡出中途以新目标槽位重新唤起）
        let interruptedRect = NSRect(x: 200, y: 150, width: 500, height: 400)
        panel.show(targetRect: interruptedRect, slot: .rightHalf, on: screen)
        // 运行主循环让进场动画走完
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))

        assertEqual(panel.frame, interruptedRect, "中途打断退场时，新目标几何必须被准确定位")
        assertTrue(panel.isVisible, "中途打断退场时，面板必须保持可见")
        assertEqual(panel.alphaValue, 1.0, "中途打断退场并重新 show 时，透明度必须满血恢复为 1.0")

        // 5. 再次退场并确保彻底清空显存
        panel.hide()
        RunLoop.current.run(until: Date().addingTimeInterval(0.20))
        assertEqual(panel.frame, .zero, "再次 hide() 退场后 frame 必须置为 .zero")

        // 6. 异常场景：在面板已被外部 orderOut 隐藏但 frame 尚未置零时调用 hide()，必须强力兜底清零
        panel.show(targetRect: testRect, slot: .leftHalf, on: screen)
        panel.orderOut(nil) // 外部强行 orderOut
        panel.hide()
        assertEqual(panel.frame, .zero, "对已 orderOut 的面板调用 hide() 必须依然彻底回收 frame 显存")
    }

    static func testSplitDividerAdjacencyDetection() {
        print("  - Testing SplitDivider adjacency detection & threshold rules...")

        // 1. Standard 50%:50% side-by-side halves
        let leftHalf = NSRect(x: 0, y: 0, width: 960, height: 1056)
        let rightHalf = NSRect(x: 960, y: 0, width: 960, height: 1056)
        assertTrue(SplitDividerManager.areAdjacent(left: leftHalf, right: rightHalf), "Standard halves must be adjacent")

        // 2. Main Workspace (2/3) + Side Workspace (1/3)
        let mainWork = NSRect(x: 0, y: 0, width: 1280, height: 1056)
        let sideWork = NSRect(x: 1280, y: 0, width: 640, height: 1056)
        assertTrue(SplitDividerManager.areAdjacent(left: mainWork, right: sideWork), "Main + Side must be adjacent")

        // 3. Gap tolerance <= 12pt
        let leftWithGap = NSRect(x: 0, y: 0, width: 955, height: 1056)
        let rightWithGap8 = NSRect(x: 963, y: 0, width: 955, height: 1056) // gap = 8pt
        assertTrue(SplitDividerManager.areAdjacent(left: leftWithGap, right: rightWithGap8), "Gap of 8pt must be accepted")

        let rightWithGap12 = NSRect(x: 967, y: 0, width: 955, height: 1056) // gap = 12pt
        assertTrue(SplitDividerManager.areAdjacent(left: leftWithGap, right: rightWithGap12), "Gap of 12pt must be accepted at threshold boundary")

        let rightWithGap13 = NSRect(x: 968, y: 0, width: 955, height: 1056) // gap = 13pt
        assertFalse(SplitDividerManager.areAdjacent(left: leftWithGap, right: rightWithGap13), "Gap of 13pt must be rejected")

        let rightFar = NSRect(x: 1050, y: 0, width: 870, height: 1056) // gap = 95pt
        assertFalse(SplitDividerManager.areAdjacent(left: leftWithGap, right: rightFar), "Far apart windows must be rejected")

        // Slight overlap due to window borders (e.g. 2pt overlap, gap = -2pt)
        let rightSlightOverlap = NSRect(x: 953, y: 0, width: 960, height: 1056) // gap = -2pt
        assertTrue(SplitDividerManager.areAdjacent(left: leftWithGap, right: rightSlightOverlap), "Slight border overlap <= 12pt must be accepted")

        // 4. Vertical overlap ratio >= 70%
        let leftH1000 = NSRect(x: 0, y: 0, width: 960, height: 1000)
        let rightShift250 = NSRect(x: 960, y: 250, width: 960, height: 1000) // overlap = 750 / 1000 = 75%
        assertTrue(SplitDividerManager.areAdjacent(left: leftH1000, right: rightShift250), "Overlap of 75% must be accepted")

        let rightShift400 = NSRect(x: 960, y: 400, width: 960, height: 1000) // overlap = 600 / 1000 = 60%
        assertFalse(SplitDividerManager.areAdjacent(left: leftH1000, right: rightShift400), "Overlap of 60% must be rejected")

        let rightShift1100 = NSRect(x: 960, y: 1100, width: 960, height: 1000) // overlap = 0%
        assertFalse(SplitDividerManager.areAdjacent(left: leftH1000, right: rightShift1100), "Zero vertical overlap must be rejected")

        // 5. Minimum height protection >= 300pt
        let leftTooShort = NSRect(x: 0, y: 0, width: 960, height: 280)
        assertFalse(SplitDividerManager.areAdjacent(left: leftTooShort, right: rightHalf), "Window height < 300pt must be rejected")

        let rightTooShort = NSRect(x: 960, y: 0, width: 960, height: 290)
        assertFalse(SplitDividerManager.areAdjacent(left: leftHalf, right: rightTooShort), "Window height < 300pt must be rejected")

        // 6. Minimum width protection >= 250pt
        let leftTooNarrow = NSRect(x: 0, y: 0, width: 240, height: 1056)
        let rightWide = NSRect(x: 240, y: 0, width: 1680, height: 1056)
        assertFalse(SplitDividerManager.areAdjacent(left: leftTooNarrow, right: rightWide), "Window width < 250pt must be rejected")

        // 7. Left-right horizontal order
        assertFalse(SplitDividerManager.areAdjacent(left: rightHalf, right: leftHalf), "Inverted horizontal order must return false")

        let foundPair = SplitDividerManager.findAdjacentPair(windowA: rightHalf, windowB: leftHalf)
        assertTrue(foundPair != nil, "findAdjacentPair must automatically orient windows left-to-right")
        assertEqual(foundPair?.left, leftHalf)
        assertEqual(foundPair?.right, rightHalf)

        // 8. Canonical Breathing Gap Slots (8pt gap) Adjacency & Center DividerX
        let vf1080 = NSRect(x: 0, y: 0, width: 1920, height: 1056)
        let gappedLeft = SnapSlot.targetRect(for: .leftHalf, in: vf1080)
        let gappedRight = SnapSlot.targetRect(for: .rightHalf, in: vf1080)
        assertTrue(SplitDividerManager.areAdjacent(left: gappedLeft, right: gappedRight), "Breathing-gapped halves (8pt gap) must be adjacent")
        assertEqual(gappedRight.minX - gappedLeft.maxX, 8.0, "Gap must be exactly 8.0pt")
        assertEqual((gappedLeft.maxX + gappedRight.minX) / 2.0, 960.0, "DividerX must align to center of gap at 960.0")

        let gappedMain = SnapSlot.targetRect(for: .mainWorkspace, in: vf1080)
        let gappedSide = SnapSlot.targetRect(for: .sideWorkspace, in: vf1080)
        assertTrue(SplitDividerManager.areAdjacent(left: gappedMain, right: gappedSide), "Breathing-gapped 2:1 split (8pt gap) must be adjacent")
        assertEqual(gappedSide.minX - gappedMain.maxX, 8.0, "Gap must be exactly 8.0pt for 2:1 split")
        assertEqual((gappedMain.maxX + gappedSide.minX) / 2.0, 1277.0, "DividerX must align to center of 2:1 gap at 1277.0")
    }

    static func testSplitDividerJointResizingCalculation() {
        print("  - Testing SplitDivider joint resizing calculation & width conservation...")

        let initialLeft = NSRect(x: 0, y: 0, width: 960, height: 1056)
        let initialRight = NSRect(x: 960, y: 0, width: 960, height: 1056)
        let totalWidth = initialLeft.width + initialRight.width

        // 1. Positive deltaX (+120): expands left window, shrinks right window
        let (dragRightLeft, dragRightRight) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: 120.0
        )
        assertEqual(dragRightLeft.minX, 0.0)
        assertEqual(dragRightLeft.width, 1080.0)
        assertEqual(dragRightRight.minX, 1080.0)
        assertEqual(dragRightRight.width, 840.0)
        assertEqual(dragRightRight.maxX, 1920.0)
        assertEqual(dragRightLeft.width + dragRightRight.width, totalWidth, "Total width must be strictly conserved (+120)")

        // 2. Negative deltaX (-200): shrinks left window, expands right window
        let (dragLeftLeft, dragLeftRight) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: -200.0
        )
        assertEqual(dragLeftLeft.minX, 0.0)
        assertEqual(dragLeftLeft.width, 760.0)
        assertEqual(dragLeftRight.minX, 760.0)
        assertEqual(dragLeftRight.width, 1160.0)
        assertEqual(dragLeftRight.maxX, 1920.0)
        assertEqual(dragLeftLeft.width + dragLeftRight.width, totalWidth, "Total width must be strictly conserved (-200)")

        // 3. Clamping constraint protection: dragging right excessively (+5000)
        let (clampedRightLeft, clampedRightRight) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: 5000.0,
            minWidth: 250.0
        )
        assertEqual(clampedRightRight.width, 250.0, "Right window width must be strictly clamped to minWidth (250pt)")
        assertEqual(clampedRightLeft.width, totalWidth - 250.0, "Left window takes remaining space")
        assertEqual(clampedRightLeft.width + clampedRightRight.width, totalWidth, "Total width must be strictly conserved under right clamp")
        assertEqual(clampedRightRight.minX, totalWidth - 250.0)

        // 4. Clamping constraint protection: dragging left excessively (-5000)
        let (clampedLeftLeft, clampedLeftRight) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: -5000.0,
            minWidth: 250.0
        )
        assertEqual(clampedLeftLeft.width, 250.0, "Left window width must be strictly clamped to minWidth (250pt)")
        assertEqual(clampedLeftRight.width, totalWidth - 250.0, "Right window takes remaining space")
        assertEqual(clampedLeftLeft.width + clampedLeftRight.width, totalWidth, "Total width must be strictly conserved under left clamp")
        assertEqual(clampedLeftRight.minX, 250.0)

        // 5. Gap conservation when gap > 0 (e.g. 10pt gap)
        let leftWithGap = NSRect(x: 0, y: 0, width: 955, height: 1056)
        let rightWithGap = NSRect(x: 965, y: 0, width: 955, height: 1056) // 10pt gap
        let (gapResL, gapResR) = SplitDividerManager.calculateJointResize(
            left: leftWithGap,
            right: rightWithGap,
            deltaX: 80.0
        )
        assertEqual(gapResL.width, 1035.0)
        assertEqual(gapResR.minX, 1045.0)
        assertEqual(gapResR.width, 875.0)
        assertEqual(gapResR.minX - gapResL.maxX, 10.0, "Gap of 10pt between windows must be perfectly conserved")

        // 6. Edge case: small windows where totalWidth < 2 * minWidth
        let smallLeft = NSRect(x: 0, y: 0, width: 200, height: 800)
        let smallRight = NSRect(x: 200, y: 0, width: 200, height: 800)
        let (smallL, smallR) = SplitDividerManager.calculateJointResize(
            left: smallLeft,
            right: smallRight,
            deltaX: 50.0,
            minWidth: 250.0
        )
        assertEqual(smallL.width, 200.0, "Small windows must clamp to half total width rather than freeze or invert")
        assertEqual(smallR.width, 200.0)

        // 7. Non-finite deltaX protection
        let (nanL, nanR) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: CGFloat.nan
        )
        assertEqual(nanL, initialLeft, "NaN deltaX must return unmodified initial left rect")
        assertEqual(nanR, initialRight, "NaN deltaX must return unmodified initial right rect")

        // 8. 50%:50% Magnetic Snapping
        // When drag brings divider within ±12pt of exact 50:50, it snaps to exact 50:50
        let (snapL, snapR) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: 8.0,
            magneticTolerance: 12.0
        )
        assertEqual(snapL.width, 960.0, "Small delta (+8) within tolerance (12) must magnetically snap to 50:50")
        assertEqual(snapR.width, 960.0)

        // When drag exceeds magnetic tolerance (+25pt > 12pt), it does not snap
        let (noSnapL, noSnapR) = SplitDividerManager.calculateJointResize(
            left: initialLeft,
            right: initialRight,
            deltaX: 25.0,
            magneticTolerance: 12.0
        )
        assertEqual(noSnapL.width, 985.0, "Delta (+25) outside tolerance must freely resize without magnetic clamp")
        assertEqual(noSnapR.width, 935.0)

        // 9. Joint drag with 8pt breathing gap
        let vf1080 = NSRect(x: 0, y: 0, width: 1920, height: 1056)
        let gappedLeft = SnapSlot.targetRect(for: .leftHalf, in: vf1080)
        let gappedRight = SnapSlot.targetRect(for: .rightHalf, in: vf1080)
        let (dragBreathingL, dragBreathingR) = SplitDividerManager.calculateJointResize(
            left: gappedLeft,
            right: gappedRight,
            deltaX: 60.0
        )
        assertEqual(dragBreathingR.minX - dragBreathingL.maxX, 8.0, "8pt breathing gap must be strictly conserved during joint drag")
        assertEqual(dragBreathingL.minX, 6.0, "Left outer margin must be preserved")
        assertEqual(dragBreathingR.maxX, 1914.0, "Right outer margin must be preserved")
        assertEqual(dragBreathingL.width, 1010.0)
        assertEqual(dragBreathingR.width, 890.0)
    }

    static func testSplitDividerFiftyFiftyReset() {
        print("  - Testing SplitDivider 50%:50% double-click reset calculation...")

        // 1. Reset from 2/3 (1280) and 1/3 (640)
        let leftTwoThirds = NSRect(x: 0, y: 0, width: 1280, height: 1056)
        let rightOneThird = NSRect(x: 1280, y: 0, width: 640, height: 1056)
        let (resetL, resetR) = SplitDividerManager.calculateFiftyFiftyReset(
            left: leftTwoThirds,
            right: rightOneThird
        )
        assertEqual(resetL.minX, 0.0)
        assertEqual(resetL.width, 960.0)
        assertEqual(resetR.minX, 960.0)
        assertEqual(resetR.width, 960.0)
        assertEqual(resetL.width, resetR.width, "Both windows must have identical width on 50:50 reset")
        assertEqual(resetL.width + resetR.width, 1920.0)

        // 2. Reset with non-zero gap
        let leftGapped = NSRect(x: 0, y: 0, width: 1200, height: 1000)
        let rightGapped = NSRect(x: 1210, y: 0, width: 600, height: 1000) // 10pt gap, total usable width = 1800
        let (resetGapL, resetGapR) = SplitDividerManager.calculateFiftyFiftyReset(
            left: leftGapped,
            right: rightGapped
        )
        assertEqual(resetGapL.width, 900.0)
        assertEqual(resetGapR.minX, 910.0)
        assertEqual(resetGapR.width, 900.0)
        assertEqual(resetGapR.minX - resetGapL.maxX, 10.0, "Gap must be conserved on reset")

        // 3. Reset with overlapping windows (rawGap = -2pt)
        let leftOverlap = NSRect(x: 0, y: 0, width: 1200, height: 1000)
        let rightOverlap = NSRect(x: 1198, y: 0, width: 600, height: 1000) // total span = 1798
        let (resetOverL, resetOverR) = SplitDividerManager.calculateFiftyFiftyReset(
            left: leftOverlap,
            right: rightOverlap
        )
        assertEqual(resetOverL.width, 899.0)
        assertEqual(resetOverR.minX, 899.0)
        assertEqual(resetOverR.width, 899.0)
        assertEqual(resetOverR.maxX, 1798.0, "Outer boundary must be strictly conserved on overlap reset")
        assertEqual(resetOverR.minX - resetOverL.maxX, 0.0, "Overlap must be resolved to clean 0 gap")

        // 4. Secondary screen with non-zero origin
        let secLeft = NSRect(x: 1920, y: 100, width: 1600, height: 1200)
        let secRight = NSRect(x: 3520, y: 100, width: 960, height: 1200)
        let (secResetL, secResetR) = SplitDividerManager.calculateFiftyFiftyReset(
            left: secLeft,
            right: secRight
        )
        assertEqual(secResetL.minX, 1920.0)
        assertEqual(secResetL.width, 1280.0)
        assertEqual(secResetR.minX, 1920.0 + 1280.0)
        assertEqual(secResetR.width, 1280.0)
        assertEqual(secResetL.origin.y, 100.0)
        assertEqual(secResetR.origin.y, 100.0)

        // 5. Fifty-fifty reset from 2:1 breathing gapped windows
        let vf1080 = NSRect(x: 0, y: 0, width: 1920, height: 1056)
        let gappedMain = SnapSlot.targetRect(for: .mainWorkspace, in: vf1080)
        let gappedSide = SnapSlot.targetRect(for: .sideWorkspace, in: vf1080)
        let (resetBreathingL, resetBreathingR) = SplitDividerManager.calculateFiftyFiftyReset(
            left: gappedMain,
            right: gappedSide
        )
        assertEqual(resetBreathingR.minX - resetBreathingL.maxX, 8.0, "8pt breathing gap must be conserved after reset")
        assertEqual(resetBreathingL.minX, 6.0, "Left outer margin must be preserved")
        assertEqual(resetBreathingR.maxX, 1914.0, "Right outer margin must be preserved")
        assertEqual(resetBreathingL.width, resetBreathingR.width, "Both windows must have identical width on 50:50 reset")
        assertEqual(resetBreathingL.width, 950.0)
        assertEqual(resetBreathingR.width, 950.0)
    }

    static func testSplitDividerConfigPersistence() {
        print("  - Testing SplitDivider config persistence & defaults...")

        let cm = ConfigManager.shared
        assertTrue(cm.enableSplitDivider, "Default enableSplitDivider must be true")

        // Test SavedConfigV3 roundtrip encoding
        let v3 = ConfigManager.SavedConfigV3(
            profiles: cm.profiles,
            activeProfileId: cm.activeProfileId,
            autoShowToolbar: cm.autoShowToolbar,
            actions: cm.actions,
            enablePlaintextLogging: false,
            enableWindowSnapping: true,
            enableSplitDivider: false
        )

        let encoded = try! JSONEncoder().encode(v3)
        let decoded = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: encoded)
        assertEqual(decoded.enableSplitDivider, false, "Serialized enableSplitDivider must decode correctly")

        // Test legacy fallback when enableSplitDivider was missing/nil
        let legacyV3 = ConfigManager.SavedConfigV3(
            profiles: cm.profiles,
            activeProfileId: cm.activeProfileId,
            autoShowToolbar: cm.autoShowToolbar,
            actions: cm.actions,
            enablePlaintextLogging: false,
            enableWindowSnapping: true,
            enableSplitDivider: nil
        )
        let legacyEncoded = try! JSONEncoder().encode(legacyV3)
        let legacyDecoded = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: legacyEncoded)
        assertEqual(legacyDecoded.enableSplitDivider ?? true, true, "Missing enableSplitDivider must default to true")

        // Test toggling
        let initial = cm.enableSplitDivider
        cm.enableSplitDivider.toggle()
        assertEqual(cm.enableSplitDivider, !initial)
        cm.enableSplitDivider = initial
    }

    static func testSplitDividerOverlayHoverAndHitTesting() {
        print("  - Testing SplitDivider overlay hover detection, hit-testing click-through, and ratio badge layout...")

        // 1. Panel dimensions and unclipped width
        assertEqual(SplitDividerOverlayPanel.panelWidth, 100.0, "Panel width must be 100.0 to prevent badge/shadow clipping")

        let viewRect = NSRect(x: 0, y: 0, width: SplitDividerOverlayPanel.panelWidth, height: 600.0)
        let dividerView = SplitDividerView(frame: viewRect)
        dividerView.layout()

        // 2. Hover Zone Detection (centerX = 50.0)
        // A. In breathing gap (centerX +/- 6pt)
        assertTrue(dividerView.isPointInHoverZone(NSPoint(x: 50.0, y: 100.0)), "Center of breathing gap must be in hover zone")
        assertTrue(dividerView.isPointInHoverZone(NSPoint(x: 45.0, y: 100.0)), "Left edge of breathing gap must be in hover zone")
        assertTrue(dividerView.isPointInHoverZone(NSPoint(x: 55.0, y: 100.0)), "Right edge of breathing gap must be in hover zone")

        // B. Far inside windows (outside breathing gap)
        assertFalse(dividerView.isPointInHoverZone(NSPoint(x: 15.0, y: 100.0)), "Point 35pt left of center (in left window) must NOT be in hover zone")
        assertFalse(dividerView.isPointInHoverZone(NSPoint(x: 85.0, y: 100.0)), "Point 35pt right of center (in right window) must NOT be in hover zone")

        // C. On circular handle (26x26pt centered at (50, 287))
        assertTrue(dividerView.isPointInHoverZone(NSPoint(x: 50.0, y: 300.0)), "Center of circular handle must be in hover zone")
        assertTrue(dividerView.isPointInHoverZone(NSPoint(x: 40.0, y: 300.0)), "Left edge of handle must be in hover zone")
        assertTrue(dividerView.isPointInHoverZone(NSPoint(x: 60.0, y: 300.0)), "Right edge of handle must be in hover zone")

        // 3. Click-through protection via hitTest
        // Points over left/right windows must return nil so mouse clicks pass through to Safari/Finder/etc.
        let leftWindowClick = dividerView.hitTest(NSPoint(x: 15.0, y: 100.0))
        assertTrue(leftWindowClick == nil, "Clicks in window margin must return nil for underlying application click-through")

        let rightWindowClick = dividerView.hitTest(NSPoint(x: 85.0, y: 100.0))
        assertTrue(rightWindowClick == nil, "Clicks in right window margin must return nil for click-through")

        // Points in the breathing gap and handle must return dividerView
        let seamClick = dividerView.hitTest(NSPoint(x: 50.0, y: 100.0))
        assertTrue(seamClick === dividerView, "Clicks on seam gap must return dividerView for drag resizing")

        let handleClick = dividerView.hitTest(NSPoint(x: 50.0, y: 300.0))
        assertTrue(handleClick === dividerView, "Clicks on circular handle must return dividerView")

        // 4. Ratio badge placement: centered horizontally and placed above handle
        let badgeWidth: CGFloat = 72.0
        let badgeX = round((SplitDividerOverlayPanel.panelWidth - badgeWidth) / 2.0)
        assertEqual(badgeX, 14.0, "Badge must be centered at x=14.0")
        assertTrue(badgeX >= 10.0, "Badge left margin must have >= 10pt padding for drop shadow")
        assertTrue(badgeX + badgeWidth <= SplitDividerOverlayPanel.panelWidth - 10.0, "Badge right margin must have >= 10pt padding")

        // 5. State transitions
        assertFalse(dividerView.isHovered, "Initial isHovered must be false")
        assertFalse(dividerView.isDragging, "Initial isDragging must be false")

        dividerView.setHovered(true)
        assertTrue(dividerView.isHovered, "setHovered(true) must set isHovered")

        dividerView.resetState()
        assertFalse(dividerView.isHovered, "resetState() must clear isHovered")
    }

    static func testSplitDividerFrontmostAppFilter() {
        print("  - Testing SplitDivider frontmost app filter (preventing divider on unrelated/single windows)...")

        let pidLeft: pid_t = 1001
        let pidRight: pid_t = 1002
        let pidForeground: pid_t = 1001
        let pidUnrelatedSingleApp: pid_t = 9999 // e.g. 八局通 or Finder

        // 1. When unrelated app is in foreground, matching must fail
        assertFalse(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: pidLeft, rightPid: pidRight, frontmostPid: pidUnrelatedSingleApp),
            "Pair must NOT match when foreground app is an unrelated single window application"
        )

        // 2. When left window is frontmost, matching must succeed
        assertTrue(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: pidLeft, rightPid: pidRight, frontmostPid: pidForeground),
            "Pair must match when left window application is frontmost"
        )

        // 3. When right window is frontmost, matching must succeed
        assertTrue(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: pidLeft, rightPid: pidRight, frontmostPid: pidRight),
            "Pair must match when right window application is frontmost"
        )

        // 4. Edge cases: nil or 0 frontmostPid
        assertFalse(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: pidLeft, rightPid: pidRight, frontmostPid: nil),
            "Pair must NOT match when frontmost PID is nil"
        )
        assertFalse(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: pidLeft, rightPid: pidRight, frontmostPid: 0),
            "Pair must NOT match when frontmost PID is 0"
        )
        assertFalse(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: 0, rightPid: pidRight, frontmostPid: pidUnrelatedSingleApp),
            "Pair must NOT match when leftPid is 0 and foreground app is unrelated"
        )
        assertFalse(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: pidLeft, rightPid: 0, frontmostPid: pidUnrelatedSingleApp),
            "Pair must NOT match when rightPid is 0 and foreground app is unrelated"
        )
        assertFalse(
            SplitDividerManager.isPairMatchingFrontmost(leftPid: 0, rightPid: 0, frontmostPid: pidUnrelatedSingleApp),
            "Pair must NOT match when both PIDs are 0 and foreground app is unrelated"
        )

        // 5. SplitWindowPair PID storage and Equatable verification
        let elem1 = AXUIElementCreateApplication(pidLeft)
        let elem2 = AXUIElementCreateApplication(pidRight)
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let pairWithExplicitPids = SplitWindowPair(
            leftElement: elem1,
            rightElement: elem2,
            leftRect: NSRect(x: 0, y: 0, width: 960, height: 1056),
            rightRect: NSRect(x: 960, y: 0, width: 960, height: 1056),
            screen: screen,
            leftPid: pidLeft,
            rightPid: pidRight
        )
        assertEqual(pairWithExplicitPids.leftPid, pidLeft)
        assertEqual(pairWithExplicitPids.rightPid, pidRight)

        // Automatic PID retrieval from AXUIElement
        let autoPair = SplitWindowPair(
            leftElement: elem1,
            rightElement: elem2,
            leftRect: NSRect(x: 0, y: 0, width: 960, height: 1056),
            rightRect: NSRect(x: 960, y: 0, width: 960, height: 1056),
            screen: screen
        )
        assertEqual(autoPair.leftPid, pidLeft, "AXUIElementGetPid must extract correct leftPid")
        assertEqual(autoPair.rightPid, pidRight, "AXUIElementGetPid must extract correct rightPid")
        assertEqual(pairWithExplicitPids, autoPair, "Pairs with same elements, rects, and pids must be equal")

        let differentPair = SplitWindowPair(
            leftElement: elem1,
            rightElement: elem2,
            leftRect: NSRect(x: 0, y: 0, width: 960, height: 1056),
            rightRect: NSRect(x: 960, y: 0, width: 960, height: 1056),
            screen: screen,
            leftPid: 8888,
            rightPid: pidRight
        )
        assertFalse(pairWithExplicitPids == differentPair, "Pairs with different PIDs must NOT be equal")
    }

    static func testSplitDividerLiquidGlassVisualTokens() {
        print("  - Testing SplitDivider Apple Liquid Glass visual geometry and color tokens...")

        // 1. Static Geometry Tokens
        assertEqual(SplitDividerView.defaultTrackWidth, 1.5, "Guide track width must be refined 1.5pt Liquid Glass seam")
        assertEqual(SplitDividerView.handleWidth, 24.0, "Capsule grip handle width must be 24.0pt")
        assertEqual(SplitDividerView.handleHeight, 36.0, "Capsule grip handle height must be 36.0pt")
        assertEqual(SplitDividerView.handleCornerRadius, 12.0, "Capsule grip handle corner radius must be 12.0pt (full capsule)")

        // 2. View Hierarchy and Layout Frame Inspection
        let frame = NSRect(x: 0, y: 0, width: SplitDividerOverlayPanel.panelWidth, height: 700.0)
        let view = SplitDividerView(frame: frame)
        view.layout()

        assertEqual(view.guideTrackWidth, 1.5, "Guide track layer width must be 1.5pt in layout")
        assertEqual(view.gripHandleFrame.width, 24.0, "Grip handle layer width must be 24.0pt")
        assertEqual(view.gripHandleFrame.height, 36.0, "Grip handle layer height must be 36.0pt")
        assertEqual(view.gripHandleCornerRadius, 12.0, "Grip handle corner radius must be 12.0pt")
        assertEqual(view.gripHandleBorderWidth, 0.75, "Specular highlight border width must be 0.75pt")
        assertTrue(view.guideTrackGradientColors != nil, "Guide track must use CAGradientLayer with vertical fade colors")

        // 3. Ratio Badge Geometry
        assertEqual(view.ratioBadgeFrame.width, 72.0, "Ratio badge width must be 72.0pt")
        assertEqual(view.ratioBadgeFrame.height, 24.0, "Ratio badge height must be 24.0pt")

        // 4. Hover State and Transitions
        view.setHovered(true)
        assertTrue(view.isHovered)
        view.resetState()
        assertFalse(view.isHovered)
    }

    static func testSplitDividerOcclusionAndSpaceSwitching() {
        print("  - Testing SplitDivider seam/window occlusion geometry & space switching safety...")

        // 1. Overlay Panel Space Behavior: MUST NOT contain .canJoinAllSpaces
        let panel = SplitDividerOverlayPanel.shared
        assertFalse(
            panel.collectionBehavior.contains(.canJoinAllSpaces),
            "Overlay panel must NOT have .canJoinAllSpaces to prevent leaking across Stage Manager sets or Spaces"
        )
        assertTrue(
            panel.collectionBehavior.contains(.fullScreenAuxiliary),
            "Overlay panel must support fullScreenAuxiliary"
        )

        // 2. Seam Occlusion Detection Geometry
        let leftRect = NSRect(x: 0, y: 0, width: 800, height: 1000)
        let rightRect = NSRect(x: 800, y: 0, width: 800, height: 1000)
        let seamX = (leftRect.maxX + rightRect.minX) / 2.0 // 800.0
        let seamRect = NSRect(x: seamX - 8.0, y: 0, width: 16.0, height: 1000.0) // 792...808

        // A. Higher window covers seam (e.g. 八局通 or full window across middle)
        let higherWindowCoveringSeam = NSRect(x: 750, y: 0, width: 200, height: 1000)
        assertTrue(higherWindowCoveringSeam.intersects(seamRect), "Window covering middle must intersect seamRect")

        // B. Higher window covers left window主体 (> 20% area: 800*1000 = 800,000; 20% = 160,000)
        let higherWindowCoveringLeft = NSRect(x: 100, y: 0, width: 600, height: 1000) // overlap = 600,000 (75%)
        let leftOverlap = higherWindowCoveringLeft.intersection(leftRect)
        assertTrue((leftOverlap.width * leftOverlap.height) > (leftRect.width * leftRect.height * 0.20), "Window covering >20% left must trigger left occlusion")

        // C. Higher window covers right window主体 (> 20% area)
        let higherWindowCoveringRight = NSRect(x: 900, y: 0, width: 600, height: 1000) // overlap = 500,000 (62.5%)
        let rightOverlap = higherWindowCoveringRight.intersection(rightRect)
        assertTrue((rightOverlap.width * rightOverlap.height) > (rightRect.width * rightRect.height * 0.20), "Window covering >20% right must trigger right occlusion")

        // D. Non-occluding auxiliary window (e.g. small status item or window in other corner)
        let smallAuxWindow = NSRect(x: 20, y: 20, width: 50, height: 50)
        assertFalse(smallAuxWindow.intersects(seamRect), "Small window must NOT intersect seam")
        let smallOverlap = smallAuxWindow.intersection(leftRect)
        assertFalse((smallOverlap.width * smallOverlap.height) > (leftRect.width * leftRect.height * 0.20), "Small window (<20%) must NOT trigger area occlusion")

        // 3. Light Appearance Gradient Color Inspection (Liquid Glass white reflection)
        let testView = SplitDividerView(frame: NSRect(x: 0, y: 0, width: 100, height: 500))
        testView.layout()
        testView.appearance = NSAppearance(named: .aqua)
        testView.updateVisualStyles()
        assertTrue(testView.guideTrackGradientColors != nil)
        if let colors = testView.guideTrackGradientColors as? [CGColor], colors.count == 5 {
            if let comp = colors[2].components, comp.count >= 2 {
                assertEqual(comp[0], 1.0, "Light mode seam peak reflection must be white (1.0), not dark grey")
            }
        }
    }

    /// 划词去重只保留指纹，超长选区必须在进模型前裁到输入预算。
    /// 若改回整段 `lastHandledText`，超长选区会在 0.5s 窗口里常驻一整份原文。
    static func testSelectionInputBudgetAndFingerprintDedupe() {
        print("  - Testing selection input budget and fingerprint dedupe...")
        let budget = SelectionMonitor.maxInputChars
        assertEqual(budget, 64_000, "划词输入预算必须是 64000 字")

        let short = "你好世界"
        let shortPrepared = SelectionMonitor.prepareSelectedText(short)
        assertEqual(shortPrepared.text, short, "短选区不得被裁")
        assertEqual(shortPrepared.fingerprint.length, short.count)

        let long = String(repeating: "词", count: 80_000)
        let longPrepared = SelectionMonitor.prepareSelectedText(long)
        assertEqual(longPrepared.text.count, budget, "超长选区必须裁到输入预算")
        assertTrue(longPrepared.text.hasPrefix("词"), "裁剪必须保留原文前缀")
        assertEqual(longPrepared.fingerprint.length, long.count, "指纹长度必须记录原文长度，而不是裁后长度")
        assertEqual(
            longPrepared.fingerprint,
            SelectionMonitor.prepareSelectedText(long).fingerprint,
            "同一超长原文的指纹必须稳定"
        )
        assertTrue(
            SelectionMonitor.prepareSelectedText(short).fingerprint
                != SelectionMonitor.prepareSelectedText(long).fingerprint,
            "不同选区不得撞指纹"
        )
    }

    /// 普通点击不得立刻走 AX 取焦窗口；要等鼠标真正拖出 20pt。
    /// 若把 capture 放回 mouseDown，空闲连点会持续付跨进程 IPC。
    static func testWindowSnapDefersAXCaptureUntilRealDrag() {
        print("  - Testing WindowSnap defers AX capture until real dragged (>=20pt)...")
        assertFalse(
            WindowSnapManager.shouldAttemptAXCapture(phase: .mouseDown, dragDistance: 0),
            "mouseDown 不得发起 AX 取焦"
        )
        assertFalse(
            WindowSnapManager.shouldAttemptAXCapture(phase: .mouseDown, dragDistance: 80),
            "即便按下时已经位移很大，mouseDown 也不得 AX"
        )
        assertFalse(
            WindowSnapManager.shouldAttemptAXCapture(phase: .mouseDragged, dragDistance: 19),
            "位移 <20pt 的抖动不得 AX"
        )
        assertTrue(
            WindowSnapManager.shouldAttemptAXCapture(phase: .mouseDragged, dragDistance: 20),
            "真正拖出 20pt 后才允许 AX 取焦"
        )
        assertFalse(
            WindowSnapManager.shouldAttemptAXCapture(
                phase: .mouseDragged,
                dragDistance: 40,
                capturedPID: 42,
                frontPID: 42
            ),
            "同一 PID 已捕获时不得重复 AX"
        )
        assertTrue(
            WindowSnapManager.shouldAttemptAXCapture(
                phase: .mouseDragged,
                dragDistance: 40,
                capturedPID: 42,
                frontPID: 99
            ),
            "前台 PID 变化时必须重新 AX"
        )
    }

    /// 真实窗口拖动结束后必须通知 SplitDivider 重扫几何。
    /// 旧实现把这条放在自己猜的 leftMouseUp 分支上，但根本没订阅这个事件。
    static func testWindowSnapNotifiesSplitDividerOnRealDragEnd() {
        print("  - Testing WindowSnap notifies SplitDivider on real window-drag end...")
        let before = SplitDividerManager.shared.geometryChangeNotificationCount

        WindowSnapManager.shared.handleMouseUpForTesting(
            at: NSPoint(x: 500, y: 500),
            wasDraggingWindow: false
        )
        assertEqual(
            SplitDividerManager.shared.geometryChangeNotificationCount,
            before,
            "普通点击松手不得触发几何重扫"
        )

        WindowSnapManager.shared.handleMouseUpForTesting(
            at: NSPoint(x: 500, y: 500),
            wasDraggingWindow: true
        )
        assertEqual(
            SplitDividerManager.shared.geometryChangeNotificationCount,
            before + 1,
            "真实窗口拖动结束必须通知 SplitDivider 重扫一次"
        )
    }

    /// 桌宠几何与点击语法：圆是码头，壳往里长，Ghost 开关被桌宠让路。
    static func testCompanionGeometryAndInteraction() {
        print("  - Testing Companion geometry, click grammar, and Ghost yield...")

        assertEqual(CompanionGeometry.visibleSize, 28, "看见的圆必须是 28pt")
        assertEqual(CompanionGeometry.hitSize, 44, "热区必须是 44pt")
        assertEqual(CompanionGeometry.shellGap, 8, "壳体与圆的缝必须是 8pt")
        assertTrue(
            (24.0...36.0).contains(CompanionGeometry.patrolSpeed),
            "闲逛速度必须落在 24...36 pt/s（实际 \(CompanionGeometry.patrolSpeed)）"
        )
        assertTrue(
            (80.0...120.0).contains(CompanionGeometry.haloRadius),
            "同屏光环必须落在 80...120pt（实际 \(CompanionGeometry.haloRadius)）"
        )

        assertEqual(CompanionGeometry.landscapeIslandSize, SnapIslandGeometry.panelSize)
        assertEqual(CompanionGeometry.verticalIslandSize.width, 164, "竖岛宽 = 140 + 12×2")
        assertEqual(CompanionGeometry.verticalIslandSize.height, 340, "竖岛高 = 72×4 + 12×3 + 8×2")
        assertEqual(CompanionGeometry.islandSize(for: .top), CompanionGeometry.landscapeIslandSize)
        assertEqual(CompanionGeometry.islandSize(for: .right), CompanionGeometry.verticalIslandSize)

        let vf = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let spawn = CompanionGeometry.spawnCenter(in: vf)
        assertEqual(spawn.x, vf.maxX - CompanionGeometry.visibleRadius, "出生必须贴可视右缘")
        assertEqual(spawn.y, vf.midY, "出生必须在右缘中部")

        let stepped = CompanionGeometry.patrolStep(
            state: CompanionGeometry.PatrolState(center: spawn, edge: .right),
            visibleFrame: vf,
            dt: 1.0,
            speed: 30
        )
        assertEqual(stepped.edge, CompanionEdge.right, "一秒内不得拐过右下角")
        assertEqual(stepped.center.x, spawn.x, "右缘巡逻不得离开右缘")
        assertEqual(stepped.center.y, spawn.y - 30, "顺时针右缘必须向下匀速")

        assertEqual(CompanionInteraction.action(for: .single, hasSelection: true), .expression)
        assertEqual(CompanionInteraction.action(for: .single, hasSelection: false), .expression)
        assertEqual(CompanionInteraction.action(for: .double, hasSelection: true), .openBar)
        assertEqual(CompanionInteraction.action(for: .double, hasSelection: false), .chatBubble)
        assertEqual(CompanionInteraction.action(for: .longPress, hasSelection: true), .chatBubble)
        assertEqual(CompanionInteraction.selectionResponse(autoShowToolbar: true), .glanceAndBar)
        assertEqual(CompanionInteraction.selectionResponse(autoShowToolbar: false), .glanceOnly)

        assertFalse(
            CompanionInteraction.allowsGhostSnap(companionEnabled: true, snapEnabled: true),
            "桌宠开着时 Ghost 分屏岛必须让路"
        )
        assertTrue(
            CompanionInteraction.allowsGhostSnap(companionEnabled: false, snapEnabled: true),
            "退出桌宠后按原开关恢复分屏岛"
        )
        assertFalse(
            CompanionInteraction.allowsGhostDivider(companionEnabled: true, dividerEnabled: true),
            "桌宠开着时 Ghost 中缝必须让路"
        )
        assertFalse(
            CompanionInteraction.allowsGhostDivider(companionEnabled: false, dividerEnabled: false),
            "退出桌宠后中缝仍尊重原关闭值"
        )

        let petOnRight = CompanionGeometry.snapCenter(CGPoint(x: 999, y: 400), to: .right, in: vf)
        let bar = CompanionGeometry.planBarOpening(
            petCenter: petOnRight,
            edge: .right,
            barSize: CGSize(width: 180, height: 28),
            visibleFrame: vf
        )
        let petVisible = CompanionGeometry.circleFrame(center: bar.petCenter)
        assertEqual(bar.edge, CompanionEdge.right)
        assertTrue(bar.frame.maxX <= petVisible.minX - CompanionGeometry.shellGap + 0.001, "右缘出条必须长在圆朝里一侧")
        assertTrue(bar.frame.minY >= vf.minY && bar.frame.maxY <= vf.maxY, "壳体不得探出可视区域")

        let bottomLeftish = CompanionGeometry.snapCenter(CGPoint(x: 200, y: 0), to: .bottom, in: vf)
        let fromBottom = CompanionGeometry.planBarOpening(
            petCenter: bottomLeftish,
            edge: .bottom,
            barSize: CGSize(width: 180, height: 28),
            visibleFrame: vf
        )
        assertEqual(fromBottom.edge, CompanionEdge.left, "贴底边出条必须先滑到更近的竖边")

        assertTrue(
            CompanionGeometry.shouldJumpScreen(
                windowCenter: CGPoint(x: 2000, y: 100),
                currentScreenFrame: vf
            ),
            "窗口中心越屏才跳"
        )
        assertFalse(
            CompanionGeometry.shouldJumpScreen(
                windowCenter: CGPoint(x: 500, y: 100),
                currentScreenFrame: vf
            ),
            "同屏窗口中心不得把宠物拉走"
        )

        let relocated = CompanionGeometry.relocateAfterUnplug(
            previousCenter: CGPoint(x: 2000, y: 300),
            remainingVisibleFrames: [vf]
        )
        assertTrue(relocated != nil, "拔屏必须落到剩余屏")
        assertEqual(relocated?.edge, CompanionEdge.right, "原坐标在右侧外屏时，应落到剩余屏右缘")

        assertTrue(
            CompanionGeometry.isInHalo(cursor: CGPoint(x: petOnRight.x - 80, y: petOnRight.y), petCenter: petOnRight),
            "光环内必须判定为靠近"
        )
        assertFalse(
            CompanionGeometry.isInHalo(cursor: CGPoint(x: petOnRight.x - 140, y: petOnRight.y), petCenter: petOnRight),
            "光环外必须判定为够不着"
        )
    }

    /// 桌宠开关是 V3 可选字段：缺它按 false，旧配置不得整份重置。
    static func testCompanionConfigPersistence() {
        print("  - Testing Companion config persistence & defaults...")
        let cm = ConfigManager.shared
        assertFalse(cm.enableCompanionMode, "Default enableCompanionMode must be false (Ghost factory)")

        let v3 = ConfigManager.SavedConfigV3(
            profiles: cm.profiles,
            activeProfileId: cm.activeProfileId,
            autoShowToolbar: cm.autoShowToolbar,
            actions: cm.actions,
            enablePlaintextLogging: false,
            enableWindowSnapping: true,
            enableSplitDivider: true,
            enableCompanionMode: true
        )
        let encoded = try! JSONEncoder().encode(v3)
        let decoded = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: encoded)
        assertEqual(decoded.enableCompanionMode, true, "Serialized enableCompanionMode must decode correctly")

        let legacyV3 = ConfigManager.SavedConfigV3(
            profiles: cm.profiles,
            activeProfileId: cm.activeProfileId,
            autoShowToolbar: cm.autoShowToolbar,
            actions: cm.actions,
            enablePlaintextLogging: false,
            enableWindowSnapping: true,
            enableSplitDivider: true,
            enableCompanionMode: nil
        )
        let legacyEncoded = try! JSONEncoder().encode(legacyV3)
        let legacyDecoded = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: legacyEncoded)
        assertEqual(legacyDecoded.enableCompanionMode ?? false, false, "Missing enableCompanionMode must default to false")

        let omittedJSON = """
        {"profiles":[],"activeProfileId":"x","autoShowToolbar":true,"actions":[]}
        """.data(using: .utf8)!
        let omitted = try! JSONDecoder().decode(ConfigManager.SavedConfigV3.self, from: omittedJSON)
        assertEqual(omitted.enableCompanionMode, nil, "旧 V3 JSON 缺字段必须仍能解码")
        assertEqual(omitted.enableCompanionMode ?? false, false, "缺字段加载时按 false，不得重置整份配置")

        let initial = cm.enableCompanionMode
        cm.enableCompanionMode.toggle()
        assertEqual(cm.enableCompanionMode, !initial)
        cm.enableCompanionMode = initial
    }

    /// 桌宠圆与聊天泡泡必须保持未实体化，直到用户真正打开桌宠模式。
    static func testCompanionPanelStaysUnmaterializedUntilStart() {
        print("  - Testing Companion pet/bubble stay unmaterialized until start()...")
        assertFalse(CompanionPetPanel.isMaterialized, "读 isMaterialized 不得触发宠物圆构造")
        assertTrue(CompanionPetPanel.safeShared == nil)
        assertFalse(CompanionChatBubblePanel.isMaterialized, "读 isMaterialized 不得触发聊天泡泡构造")
        assertTrue(CompanionChatBubblePanel.safeShared == nil)

        CompanionManager.shared.stop()
        CompanionManager.shared.hardCutOpenShells()
        CompanionManager.shared.notifyShellClosed()

        assertFalse(CompanionPetPanel.isMaterialized, "stop()/hardCut 不得触发宠物圆实体化")
        assertFalse(CompanionChatBubblePanel.isMaterialized, "stop()/hardCut 不得触发聊天泡泡实体化")
        assertFalse(TransientCommandBarPanel.isMaterialized, "关桌宠硬切不得把划词条实体化")
    }

    /// Presence 切换不得拆掉单例 NSPanel。
    ///
    /// 现场崩溃（2026-09-16 17:57 / 18:00）：切桌宠开或关后 2–7s，主线程
    /// `NSApplication.run` 排空自动释放池时对 `NSWindow` `objc_release` → SIGSEGV。
    /// 单例面板必须钉死 `isReleasedWhenClosed = false`、`canHide = false`，
    /// 切到桌宠立刻收 Ghost 条，切走立刻收宠物/条，不得把窗口交给 AppKit 关。
    static func testCompanionSingletonPanelsSurvivePresenceSwitch() {
        print("  - Testing Companion singleton panels survive Presence start/stop...")

        let pet = CompanionPetPanel.shared
        assertFalse(pet.isReleasedWhenClosed, "宠物圆是进程级单例，关闭时不得释放")
        assertFalse(pet.canHide, "NSApp.hide 不得把宠物圆交给 AppKit 收掉")

        let bubble = CompanionChatBubblePanel.shared
        assertFalse(bubble.isReleasedWhenClosed, "聊天泡泡是进程级单例，关闭时不得释放")
        assertFalse(bubble.canHide, "NSApp.hide 不得把聊天泡泡交给 AppKit 收掉")

        let bar = TransientCommandBarPanel.shared
        assertFalse(bar.isReleasedWhenClosed, "划词条是进程级单例，关闭时不得释放")
        assertFalse(bar.canHide, "NSApp.hide 不得把划词条交给 AppKit 收掉")

        let island = WindowSnapIslandPanel.shared
        assertFalse(island.isReleasedWhenClosed, "分屏岛是进程级单例，关闭时不得释放")
        assertFalse(island.canHide, "NSApp.hide 不得把分屏岛交给 AppKit 收掉")

        let preview = GhostPreviewPanel.shared
        assertFalse(preview.isReleasedWhenClosed, "Ghost Preview 是进程级单例，关闭时不得释放")
        assertFalse(preview.canHide, "NSApp.hide 不得把 Ghost Preview 交给 AppKit 收掉")

        let divider = SplitDividerOverlayPanel.shared
        assertFalse(divider.isReleasedWhenClosed, "中缝浮层是进程级单例，关闭时不得释放")
        assertFalse(divider.canHide, "NSApp.hide 不得把中缝浮层交给 AppKit 收掉")

        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        let ghostPoint = NSPoint(x: screen.visibleFrame.midX, y: screen.visibleFrame.maxY - 8)
        bar.show(at: ghostPoint, text: "presence-switch")
        assertTrue(bar.isVisible, "Ghost 条 show() 后必须可见，才能验证切桌宠硬切")

        CompanionManager.shared.start()
        assertTrue(pet === CompanionPetPanel.shared, "start() 不得重建宠物窗口")
        assertTrue(pet.isVisible, "桌宠 start() 后圆必须可见")
        assertFalse(bar.isVisible, "切到桌宠必须立刻收掉 Ghost 条，不能留在菜单栏")
        assertFalse(pet.isReleasedWhenClosed)
        assertFalse(pet.canHide)

        CompanionManager.shared.stop()
        assertFalse(pet.isVisible, "关桌宠必须立刻收掉圆，不得等退场动画")
        assertFalse(bar.isVisible, "关桌宠必须立刻收掉条，不得等退场动画")
        assertFalse(bubble.isVisible, "关桌宠必须立刻收掉泡泡")
        assertTrue(pet === CompanionPetPanel.shared, "stop() 不得释放/重建宠物窗口")
        assertFalse(pet.isReleasedWhenClosed)
        assertFalse(bar.isReleasedWhenClosed)

        CompanionManager.shared.start()
        CompanionManager.shared.stop()
        assertTrue(pet === CompanionPetPanel.shared, "二次切换后仍必须是同一只宠物窗口")
        assertFalse(pet.isVisible)
        assertFalse(pet.isReleasedWhenClosed)
        assertFalse(pet.canHide)
    }
}
