// Standalone test for the subprocess runner: draining, exit statuses, and the two waits that must end.
import Foundation

@main
@MainActor
struct ToolRunnerTest {
    private static var failures = 0

    static func check(_ condition: @autoclosure () -> Bool, _ description: String) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    /// Every case spawns the real thing. This is a subprocess runner, and a stub would only test the
    /// stub, so `/bin/sh` is the tool here and what it writes is what a tool writes.
    static func spawn(
        _ executable: String, _ arguments: [String], timeout: TimeInterval?
    ) async -> ToolRunner.Result? {
        do {
            return try await ToolRunner.run(
                URL(fileURLWithPath: executable), arguments, timeout: timeout)
        } catch {
            print("FAIL  spawn threw: \(error.localizedDescription)")
            failures += 1
            return nil
        }
    }

    static func shell(
        _ script: String, timeout: TimeInterval? = 10
    ) async -> ToolRunner.Result? {
        await spawn("/bin/sh", ["-c", script], timeout: timeout)
    }

    static func seconds(_ since: Date) -> String {
        String(format: "%.2fs", Date().timeIntervalSince(since))
    }

    static func main() async {
        // 1. The ordinary path.
        if let result = await shell("printf 'hello\n'") {
            check(result.status == 0, "a tool that succeeds reports status 0")
            check(result.output == "hello\n", "its output arrives whole")
            check(result.succeeded, "and it counts as a success")
            check(!result.timedOut, "a run that ended on its own is not a timeout")
        }

        // 2. Standard error lands in the same buffer, because that is where a tool puts its reason.
        if let result = await shell("printf out; printf err >&2") {
            check(result.output == "outerr", "stderr is merged, in the order the tool wrote it")
            check(result.status == 0, "writing to stderr does not make a run fail")
        }

        // 3. A failing tool, and the tail that carries its reason.
        if let result = await shell("printf 'the reason\n' >&2; exit 3") {
            check(result.status == 3, "the exit status survives")
            check(!result.succeeded, "a non-zero status is not a success")
            check(result.tail == "the reason", "the tail is the last words the tool said")
        }

        // A long transcript buries the reason, so the tail is the last eight lines.
        let numbered = (1...10).map { "printf 'line \($0)\\n'" }.joined(separator: "; ")
        if let result = await shell(numbered + "; exit 1") {
            let lines = result.tail.split(separator: "\n")
            check(lines.count == 8, "the tail keeps eight lines and no more")
            check(lines.first == "line 3", "and they are the last eight, not the first")
        }

        // A tool that says nothing still has to answer for itself.
        if let result = await shell("exit 1") {
            check(result.output.isEmpty, "silence is empty output")
            check(result.tail == "no output", "and the tail says so rather than showing nothing")
        }

        // 4. More output than the pipe buffer holds. A runner that only reads after the tool exits
        //    deadlocks here, which is why the drain exists at all.
        if let result = await shell("yes abcd | head -n 50000") {
            let expected = 50000 * 5
            check(result.status == 0, "a tool outwriting the pipe still exits cleanly")
            check(result.output.utf8.count == expected, "all \(expected) bytes arrive, none dropped")
            check(result.output.hasPrefix("abcd\nabcd\n"), "in order, from the start")
            check(result.output.hasSuffix("abcd\n"), "and through to the end")
        }

        // 5. A tool that is not there. The drain would block forever on a pipe no writer ever closes,
        //    so this is also the case that proves the spawn failure ends it.
        let missing = Date()
        do {
            _ = try await ToolRunner.run(URL(fileURLWithPath: "/nonexistent/tool-runner"), [])
            check(false, "spawning a missing executable throws")
        } catch {
            check(true, "spawning a missing executable throws")
            check(Date().timeIntervalSince(missing) < 2, "and throws promptly")
        }

        // 6. The budget, first stage: a tool that honours SIGTERM stops at the deadline.
        let cooperative = Date()
        if let result = await spawn("/bin/sleep", ["30"], timeout: 1) {
            check(result.timedOut, "a run cut short says so")
            check(!result.succeeded, "and is not a success")
            check(Date().timeIntervalSince(cooperative) < 5, "the wait ended with the tool")
        }

        // Second stage: a tool that ignores SIGTERM, and leaves a child holding the pipe open behind
        // it. Nothing is coming then — no status, and no end of file — so this is the case only the
        // deadline itself can end.
        let stubborn = Date()
        if let result = await shell("trap '' TERM; sleep 5", timeout: 1) {
            check(result.timedOut, "a tool that refused to stop is still reported as cut short")
            check(!result.succeeded, "and is not a success")
            check(
                Date().timeIntervalSince(stubborn) < 8,
                "the wait ended anyway, after \(seconds(stubborn))")
        }

        // Third stage: the tool is gone and its own child is not, so the status is in and end of file
        // is not. Nothing the tool does can end this one either — only the deadline can, and the
        // answer then carries a successful status *and* says the budget ended the wait, because both
        // of those are true.
        let descendant = Date()
        if let result = await shell("sleep 5 & echo done", timeout: 1) {
            check(result.output == "done\n", "output written before the tool exited still arrives")
            check(result.succeeded, "a tool that exited 0 is a success even so")
            check(result.timedOut, "and the run still says the budget is what ended it")
            check(
                Date().timeIntervalSince(descendant) < 8,
                "the wait ended anyway, after \(seconds(descendant))")
        }

        // A tool that was never given a budget is never killed: it may be waiting on a person.
        if let result = await shell("sleep 1; printf 'waited\n'", timeout: nil) {
            check(result.output == "waited\n", "a run with no timeout is allowed to take its time")
            check(!result.timedOut, "and is never reported as cut short")
        }

        // 7. Many small writes, reassembled. Chunk boundaries land wherever the pipe decides, so this
        //    fails if two reads on one descriptor can ever interleave.
        let counted = (1...200).map { String(format: "%04d,", $0) }.joined()
        if let result = await shell("i=1; while [ $i -le 200 ]; do printf '%04d,' $i; i=$((i+1)); done") {
            check(result.output == counted, "200 separate writes arrive whole and in order")
        }

        // 8. A character split across reads. The collector buffers bytes rather than decoding each
        //    chunk, so the three bytes of one character may arrive in three writes and still land.
        if let result = await shell("printf '\\344'; printf '\\270'; printf '\\255'") {
            check(result.output == "中", "a character split across reads still decodes")
        }

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) failed")
        if failures > 0 { exit(1) }
    }
}
