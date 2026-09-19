import Darwin
import Foundation

/// Runs a command and hands back everything it printed, drained as it arrives so a tool outwriting
/// the pipe buffer cannot wedge. Every wait here has an end, which is the easy half to get wrong: a
/// reader that blocks on the pipe and a timeout that merely asks the tool to stop both leave a caller
/// waiting forever, and this is the one utility every other subprocess call is built on.
enum ToolRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String

        /// Set when the runner stopped waiting instead of hearing the tool out. `status` is then
        /// `stopped`, since nothing can read an exit status out of a process that is still alive.
        /// A run can be both this and successful — the tool may exit just as the budget runs out —
        /// which is why `succeeded` asks only about the status.
        let timedOut: Bool

        /// What `status` reports when the wait ended before the tool did.
        static let stopped: Int32 = -1

        var succeeded: Bool { status == 0 }

        /// The tail, which is where a tool puts the actual error.
        var tail: String {
            let lines = output.split(separator: "\n").suffix(8)
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "no output" : text
        }
    }

    /// How long a tool gets to honour SIGTERM before SIGKILL, and then how long the wait survives
    /// even that. `Process` cannot put the child in a session of its own the way `PseudoTerminal`
    /// does, so there is no `kill(-pid)` here to reach whatever the tool left running: the drain's
    /// end is what has to be bounded instead.
    private static let terminationGrace: TimeInterval = 1
    private static let lastResortGrace: TimeInterval = 2

    /// A nil `timeout` never kills: the tool may be waiting on a person rather than wedged.
    static func run(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval? = 120
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collector = OutputCollector()
        let reader = pipe.fileHandleForReading

        return try await withCheckedThrowingContinuation { continuation in
            let completion = Completion(collector: collector) { continuation.resume(returning: $0) }

            // The pipe has exactly one reader, and it is this loop. Reading in a readability handler
            // *and* again with `readToEnd` from the exit handler was two readers on one descriptor:
            // their chunks could be absorbed in either order, and the collector's lock only ever
            // guarded the buffer, never the read that filled it.
            //
            // It drains to end of file rather than to the tool's exit, which is not the same moment:
            // a tool that leaves a child behind leaves the write end open with it.
            DispatchQueue(label: "com.jackdu.delores.tool-runner").async {
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    collector.absorb(chunk)
                }
                completion.endOfFile()
            }

            // The exit supplies one of the two facts the answer needs, and the drain the other.
            process.terminationHandler = { finished in
                completion.exited(finished.terminationStatus)
            }

            do {
                try process.run()
            } catch {
                // No handler fires for a process that never started, and the drain would block on a
                // pipe whose write end nobody ever handed to a child, so both end here.
                process.terminationHandler = nil
                try? pipe.fileHandleForWriting.close()
                guard completion.claim() else { return }
                continuation.resume(throwing: error)
                return
            }

            guard let timeout else { return }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !completion.hasSettled else { return }
                // The budget is spent. Ask the tool to stop, then insist: SIGKILL cannot be caught
                // or ignored, so the exit handler is guaranteed to fire from here.
                completion.markTimedOut()
                if process.isRunning { process.terminate() }
                try? await Task.sleep(for: .seconds(terminationGrace))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                // Reaping the tool is still not enough, because the drain is waiting on end of file
                // and a descendant can hold the write end open indefinitely. So the wait ends here
                // regardless, with whatever arrived by then.
                try? await Task.sleep(for: .seconds(lastResortGrace))
                completion.giveUp()
            }
        }
    }
}

/// Both the drain and the waiter touch the bytes, on queues of their own, so the lock is load-bearing.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        // Latin-1 cannot fail, so other encodings still reach the user.
        return String(bytes: buffer, encoding: .utf8)
            ?? String(bytes: buffer, encoding: .isoLatin1) ?? ""
    }

    /// Buffers bytes, not text: a read landing mid-character would decode to a replacement.
    func absorb(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }
}

/// The exit and the drain arrive on different queues, and the answer needs both: the drain knows when
/// the bytes stop, and only the exit knows the status. Whoever completes the pair answers, once.
///
/// The clock is a third way in, because neither of the other two is guaranteed to arrive — a tool
/// that ignores SIGTERM never exits, and a descendant holding the pipe means end of file never comes.
private final class Completion: @unchecked Sendable {
    private let lock = NSLock()
    private let collector: OutputCollector
    private let resume: (ToolRunner.Result) -> Void
    private var status: Int32?
    private var drained = false
    private var settled = false
    private var timedOut = false

    init(collector: OutputCollector, resume: @escaping (ToolRunner.Result) -> Void) {
        self.collector = collector
        self.resume = resume
    }

    /// A settled run needs no watching, and can absorb nothing further.
    var hasSettled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return settled
    }

    func exited(_ status: Int32) {
        lock.lock()
        self.status = status
        lock.unlock()
        settle()
    }

    /// The drain has reached end of file, so nothing further can arrive.
    func endOfFile() {
        lock.lock()
        drained = true
        lock.unlock()
        settle()
    }

    /// Recorded before the tool is signalled, so that whichever path ends the wait can say the budget
    /// was what ended it rather than the tool.
    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    /// The last resort: end the wait even though the tool has not ended. Anything still unread is
    /// lost to a drain that is still blocked, which is the point of stopping here.
    func giveUp() {
        lock.lock()
        drained = true
        status = status ?? ToolRunner.Result.stopped
        lock.unlock()
        settle()
    }

    /// Ends the wait without an answer, for the caller that resumes with its own error instead.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !settled else { return false }
        settled = true
        return true
    }

    private func settle() {
        lock.lock()
        guard !settled, drained, let status else {
            lock.unlock()
            return
        }
        settled = true
        let flag = timedOut
        lock.unlock()
        // Read outside the lock: the collector holds one of its own, and the drain may still append.
        resume(ToolRunner.Result(status: status, output: collector.text, timedOut: flag))
    }
}
