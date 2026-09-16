//
//  LLMService.swift
//  HuaciGongju
//

import Foundation

public struct ChatMessage: Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

// MARK: - 对话日志
// 记录每次请求的输入与模型输出，供回溯与排查使用。
// 默认关闭明文记录以保护隐私，日志保存在用户个人目录 ~/Library/Logs/HuaciGongju/ 下。
public enum ChatLog {
    public static var logDirectoryURL: URL {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/HuaciGongju", isDirectory: true)
        if !FileManager.default.fileExists(atPath: logsDir.path) {
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } else {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: logsDir.path)
        }
        return logsDir
    }

    public static var path: String {
        return logDirectoryURL.appendingPathComponent("huacigongju-chat.log").path
    }

    private static let maxBytes = 2 * 1024 * 1024
    private static let maxFieldChars = 4000
    private static let queue = DispatchQueue(label: "com.jackdu.huacigongju.chatlog")

    static func now() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static func clip(_ text: String) -> String {
        guard text.count > maxFieldChars else { return text }
        return String(text.prefix(maxFieldChars)) + "\n…（此处截断，原文共 \(text.count) 字）"
    }

    static func append(_ text: String) {
        let block = text.hasSuffix("\n") ? text : text + "\n"
        queue.async {
            guard let data = block.data(using: .utf8) else { return }
            let filePath = path
            let url = URL(fileURLWithPath: filePath)
            let fm = FileManager.default

            if !fm.fileExists(atPath: filePath) {
                fm.createFile(atPath: filePath, contents: data, attributes: [.posixPermissions: 0o600])
                return
            }

            // 超过上限时轮转重开，避免无限增长
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int,
               size > maxBytes {
                try? fm.removeItem(atPath: filePath)
                let header = "[日志超过 2MB，已轮转重开]\n"
                fm.createFile(atPath: filePath, contents: header.data(using: .utf8), attributes: [.posixPermissions: 0o600])
            }

            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        }
    }

    static func recordRequest(
        profileName: String,
        modelName: String,
        endpoint: String,
        systemPrompt: String,
        history: [ChatMessage],
        userContent: String
    ) {
        let allowPlaintext = ConfigManager.shared.enablePlaintextLogging
        var text = "\n======== \(now()) ========\n"
        text += "[模型] \(profileName) · \(modelName)\n"
        text += "[端点] \(endpoint)\n"
        if !history.isEmpty {
            text += "[上下文] \(history.count) 条历史消息\n"
        }
        if allowPlaintext {
            text += "[系统提示] \(clip(systemPrompt))\n"
            text += "[用户输入] \(clip(userContent))\n"
        } else {
            text += "[系统提示] (明文日志已关闭)\n"
            text += "[用户输入] (共 \(userContent.count) 字，明文日志已关闭)\n"
        }
        append(text)
    }

    static func recordResponse(
        reasoning: String,
        reasoningChunks: Int,
        answer: String,
        contentChunks: Int,
        elapsed: TimeInterval
    ) {
        let allowPlaintext = ConfigManager.shared.enablePlaintextLogging
        var text = "[思考过程] \(reasoningChunks) 段 / \(reasoning.count) 字\n"
        if allowPlaintext {
            text += reasoning.isEmpty ? "（无）\n" : "\(clip(reasoning))\n"
        } else {
            text += reasoning.isEmpty ? "（无）\n" : "（明文日志已关闭）\n"
        }
        text += "\n[最终答案] \(contentChunks) 段 / \(answer.count) 字\n"
        if allowPlaintext {
            text += answer.isEmpty ? "（空）\n" : "\(clip(answer))\n"
        } else {
            text += answer.isEmpty ? "（空）\n" : "（明文日志已关闭）\n"
        }
        text += "\n[统计] 耗时 \(String(format: "%.2f", elapsed))s\n"
        append(text)
    }
}

public class LLMService {
    public static let shared = LLMService()

    private var currentTask: URLSessionDataTask?
    private var currentSession: URLSession?

    /// 网络回调队列：必须是串行且**不能是主线程**。
    /// SSE 解析、JSON 解码、字符串累积全在这条队列上完成，主线程只负责接收已经合并好的片段。
    private static let streamDelegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.jackdu.huacigongju.llm.stream"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// 用于创建流式网络会话的配置，使用 `.ephemeral` 彻底杜绝 SQLite `Cache.db` 磁盘与内存缓存。
    public static var sessionConfiguration: URLSessionConfiguration {
        .ephemeral
    }

    private init() {}

    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        currentSession?.invalidateAndCancel()
        currentSession = nil
    }

    /// 判断 Base URL 是否指向本机回环地址。
    /// 使用 URL.host 精确匹配，避免 contains 造成的误判
    /// （例如 `https://my-localhost-proxy.example.com` 会被 contains 误认为本机）。
    private static func isLoopbackHost(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    public func streamChat(
        systemPrompt: String,
        userContent: String,
        profile: LLMProfile? = nil,
        history: [ChatMessage] = [],
        onReasoning: ((String) -> Void)? = nil,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        cancel()

        let currentProfile = profile ?? ConfigManager.shared.activeProfile
        var baseUrlString = currentProfile.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let isLocalHost = LLMService.isLoopbackHost(baseUrlString)

        let key = currentProfile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isLocalHost && key.isEmpty {
            onError(NSError(domain: "HuaciGongju", code: -1, userInfo: [NSLocalizedDescriptionKey: "请在设置中为「\(currentProfile.name)」配置 API Key"]))
            return
        }

        if baseUrlString.hasSuffix("/") {
            baseUrlString.removeLast()
        }
        let endpoint = baseUrlString.hasSuffix("/chat/completions") ? baseUrlString : "\(baseUrlString)/chat/completions"

        guard let url = URL(string: endpoint) else {
            onError(NSError(domain: "HuaciGongju", code: -2, userInfo: [NSLocalizedDescriptionKey: "接口 Base URL 格式无效: \(endpoint)"]))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let authKey = key.isEmpty ? "local" : key
        request.setValue("Bearer \(authKey)", forHTTPHeaderField: "Authorization")

        // Crucial for OpenCode / specialized providers that require session headers
        request.setValue("huacigongju-\(UUID().uuidString.prefix(8))", forHTTPHeaderField: "x-opencode-session")

        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in history {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": userContent])

        let payload: [String: Any] = [
            "model": currentProfile.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": messages,
            "stream": true,
            "temperature": 0.5
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            onError(NSError(domain: "HuaciGongju", code: -3, userInfo: [NSLocalizedDescriptionKey: "构造请求数据失败"]))
            return
        }
        request.httpBody = httpBody

        ChatLog.recordRequest(
            profileName: currentProfile.name,
            modelName: currentProfile.modelName,
            endpoint: endpoint,
            systemPrompt: systemPrompt,
            history: history,
            userContent: userContent
        )

        let delegate = StreamDelegate(
            onReasoning: onReasoning,
            onToken: onToken,
            onComplete: onComplete,
            onError: onError
        )
        let session = URLSession(configuration: Self.sessionConfiguration, delegate: delegate, delegateQueue: LLMService.streamDelegateQueue)
        self.currentSession = session
        let task = session.dataTask(with: request)
        self.currentTask = task
        task.resume()
    }
}

/// SSE 流式响应解析器。
///
/// ## 线程模型（性能关键）
/// 旧实现把 URLSession 的 delegateQueue 设成 `.main`，于是 SSE 切行、JSON 解码、字符串累积
/// 和 `@Published` 赋值全部堆在主线程：一次快速模型的回答会产生几千次 UI 失效。
///
/// 现在拆成两条队列：
/// - `stateQueue`（后台串行）：所有可变状态的唯一归属者。解析、解码、累积全在这里。
///   不假设 URLSession 用哪条线程回调我们，每个入口都显式 hop 进来，因此测试里直接同步调用也安全。
/// - `flushQueue`（默认主线程）：只负责把**已经合并好的**片段交给上层。
///
/// 中间加一道 40ms 节流：40ms ≈ 每秒 25 次刷新，肉眼仍然是「实时输出」，
/// 但 UI 更新次数从「几千次」降到「几十次」。
internal class StreamDelegate: NSObject, URLSessionDataDelegate {
    private let onReasoning: ((String) -> Void)?
    private let onToken: (String) -> Void
    private let onComplete: (String) -> Void
    private let onError: (Error) -> Void

    /// 回调派发队列。生产环境固定主线程——SwiftUI 的 @Published 只能在主线程改。
    private let flushQueue: DispatchQueue

    /// 所有可变状态的唯一归属队列。
    private let stateQueue = DispatchQueue(label: "com.jackdu.huacigongju.llm.stream.state")

    private enum Throttle {
        /// 批量刷新间隔：40ms ≈ 25 次/秒。
        static let interval: TimeInterval = 0.04
        /// 攒到这个字节数就不再等下一拍，立刻发出去，避免节流反而引入可见延迟。
        static let maxPendingBytes = 2048
    }

    /// 输入侧字节预算：服务端异常时不能让它把我们撑爆。
    private enum Limits {
        /// 单行 SSE 上限。正常 SSE 一行几百字节；服务端若一直不发换行，
        /// dataBuffer 会无限增长，超过预算就整段丢弃重来（本来也解析不出内容）。
        static let maxLineBufferBytes = 256 * 1024
        /// 错误响应体上限，够放完所有常见的报错 JSON。
        static let maxErrorBodyBytes = 64 * 1024
        /// 正文硬边界，与 ViewModel 显示上限对齐。触顶后当成功结束，绝不 cancel-as-error。
        static let maxContentChars = UnifiedCommandBarViewModel.Capacity.maxOutputChars
        /// 思考硬边界。触顶只停思考累积，正文通道继续。
        static let maxReasoningChars = UnifiedCommandBarViewModel.Capacity.maxReasoningChars
    }

    // MARK: - 以下字段只能在 stateQueue 上访问

    private var fullText = ""            // 最终答案，仅来自 content 通道
    private var reasoningText = ""       // 思考过程，仅来自 reasoning_content 通道
    private var reasoningChunks = 0
    private var contentChunks = 0
    private var dataBuffer = Data()
    private var httpStatusCode: Int = 200
    private var errorBodyData = Data()
    private var pendingContent = ""      // 待批量发布的正片段
    private var pendingReasoning = ""    // 待批量发布的思考片段
    private var flushScheduled = false
    private var isFinished = false
    private var contentCapped = false
    private var reasoningCapped = false

    // MARK: - 常量

    private let startedAt = Date()

    init(
        onReasoning: ((String) -> Void)?,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void,
        flushQueue: DispatchQueue = .main
    ) {
        self.onReasoning = onReasoning
        self.onToken = onToken
        self.onComplete = onComplete
        self.onError = onError
        self.flushQueue = flushQueue
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        stateQueue.async {
            if let httpResponse = response as? HTTPURLResponse {
                self.httpStatusCode = httpResponse.statusCode
            }
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateQueue.async {
            guard !self.isFinished else { return }
            if !(200...299).contains(self.httpStatusCode) {
                if self.errorBodyData.count < Limits.maxErrorBodyBytes {
                    self.errorBodyData.append(data)
                }
                return
            }

            self.dataBuffer.append(data)
            if self.dataBuffer.count > Limits.maxLineBufferBytes {
                // 服务端一直不发换行：这不是合法的 SSE 行，留着只会无限增长
                self.dataBuffer.removeAll(keepingCapacity: true)
                return
            }
            self.processDataBuffer()
            if self.contentCapped && !self.isFinished {
                self.finishLocked(error: nil)
                dataTask.cancel()
            }
        }
    }

    // MARK: - 解析（仅 stateQueue）

    private func processDataBuffer() {
        while !isFinished, let newlineIndex = dataBuffer.firstIndex(of: 0x0A) {
            let lineData = dataBuffer.subdata(in: dataBuffer.startIndex..<newlineIndex)
            dataBuffer.removeSubrange(dataBuffer.startIndex...newlineIndex)

            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            parseSSELine(line)
        }
    }

    private func parseSSELine(_ line: String) {
        guard !isFinished else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return
        }
        guard let jsonData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let delta = firstChoice["delta"] as? [String: Any] else {
            return
        }

        // 思考通道与答案通道严格分离：绝不把 reasoning_content 混进正文
        var accumulated = false

        if !reasoningCapped, let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
            let room = Limits.maxReasoningChars - reasoningText.count
            if room <= 0 {
                reasoningCapped = true
            } else if reasoning.count > room {
                let clipped = String(reasoning.prefix(room))
                reasoningText += clipped
                reasoningChunks += 1
                pendingReasoning += clipped
                reasoningCapped = true
                accumulated = true
            } else {
                reasoningText += reasoning
                reasoningChunks += 1
                pendingReasoning += reasoning
                accumulated = true
            }
        }

        if !contentCapped, let content = delta["content"] as? String, !content.isEmpty {
            let room = Limits.maxContentChars - fullText.count
            if room <= 0 {
                contentCapped = true
            } else if content.count > room {
                let clipped = String(content.prefix(room))
                fullText += clipped
                contentChunks += 1
                pendingContent += clipped
                contentCapped = true
                accumulated = true
            } else {
                fullText += content
                contentChunks += 1
                pendingContent += content
                accumulated = true
            }
        }

        if accumulated {
            scheduleFlushLocked()
        }
    }

    // MARK: - 批量发布（仅 stateQueue）

    private func scheduleFlushLocked() {
        let pendingBytes = pendingContent.utf8.count + pendingReasoning.utf8.count
        if pendingBytes >= Throttle.maxPendingBytes {
            deliverPendingLocked()
            return
        }

        guard !flushScheduled else { return }
        flushScheduled = true
        stateQueue.asyncAfter(deadline: .now() + Throttle.interval) { [weak self] in
            guard let self = self else { return }
            self.flushScheduled = false
            self.deliverPendingLocked()
        }
    }

    /// 把攒下的片段一次性交给 flushQueue。顺序靠「stateQueue 串行 + flushQueue FIFO」保证。
    private func deliverPendingLocked() {
        let content = pendingContent
        let reasoning = pendingReasoning
        pendingContent = ""
        pendingReasoning = ""
        if content.isEmpty && reasoning.isEmpty { return }

        flushQueue.async {
            if !reasoning.isEmpty { self.onReasoning?(reasoning) }
            if !content.isEmpty { self.onToken(content) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()

        stateQueue.async {
            self.finishLocked(error: error)
        }
    }

    private func finishLocked(error: Error?) {
        guard !isFinished else { return }
        isFinished = true

        // 处理末尾未以换行结束的残余数据
        if !dataBuffer.isEmpty {
            if let line = String(data: dataBuffer, encoding: .utf8) {
                parseSSELine(line)
            }
            dataBuffer.removeAll()
        }

        // 收尾前先把残余片段推完，保证 onComplete 时上层已经拿到全部文本
        deliverPendingLocked()

        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                flushQueue.async { self.onError(error) }
            }
            return
        }

        if !(200...299).contains(httpStatusCode) {
            var detail = "HTTP \(httpStatusCode) 错误"
            if let json = try? JSONSerialization.jsonObject(with: errorBodyData) as? [String: Any] {
                if let errObj = json["error"] as? [String: Any], let msg = errObj["message"] as? String {
                    detail = msg
                } else if let msg = json["message"] as? String {
                    detail = msg
                }
            } else if let raw = String(data: errorBodyData, encoding: .utf8), !raw.isEmpty {
                detail = raw
            }
            ChatLog.append("[失败] HTTP \(httpStatusCode)：\(detail)")
            let code = httpStatusCode
            flushQueue.async {
                self.onError(NSError(domain: "HuaciGongju", code: code, userInfo: [NSLocalizedDescriptionKey: detail]))
            }
            return
        }

        ChatLog.recordResponse(
            reasoning: reasoningText,
            reasoningChunks: reasoningChunks,
            answer: fullText,
            contentChunks: contentChunks,
            elapsed: Date().timeIntervalSince(startedAt)
        )

        let finalText = fullText
        flushQueue.async { self.onComplete(finalText) }
    }

    // MARK: - 测试支持

    /// 同步排空：先把 stateQueue 上尚未发出的片段立刻派发，再等 flushQueue 执行完。
    ///
    /// 仅供单元测试做确定性断言；生产路径由 40ms 节流定时器驱动，不调用这里。
    /// 调用方**必须**传一条非主线程的 flushQueue —— 主线程无法 `sync` 等待自己。
    internal func drainPendingForTesting() {
        stateQueue.sync { self.deliverPendingLocked() }
        flushQueue.sync {}
    }
}
