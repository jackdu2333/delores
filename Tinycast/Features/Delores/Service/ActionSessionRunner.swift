import Foundation
enum DeloresActionSessionRunner {
    @MainActor
    static func run(stream: AIProviderStream, isCurrent: () -> Bool, onStreaming: (String) -> Void) async -> DeloresActionSession.Outcome? {
        var session = DeloresActionSession()
        do {
            for try await event in stream {
                guard case .text(let delta) = event else { continue }
                let step = session.ingest(delta)
                guard isCurrent() else { return nil }
                switch step {
                case .capped: return session.complete()
                case .streaming(let text): onStreaming(text)
                case .none: break
                }
            }
        } catch is CancellationError {
            guard isCurrent() else { return nil }
            return session.stop()
        } catch {
            guard isCurrent() else { return nil }
            return session.fail(error.localizedDescription)
        }
        guard isCurrent() else { return nil }
        return session.complete()
    }
}
