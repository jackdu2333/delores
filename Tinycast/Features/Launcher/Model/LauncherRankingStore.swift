import Foundation

/// One entry's decaying use and the last three distinct searches that opened it.
struct LauncherVisit: Codable, Hashable, Sendable {
    var anchor: Date
    var openedAt: Date
    var searchTerms: [String]
}

struct LauncherUsage: Sendable, Equatable {
    let frecency: Double
    let searchTerms: [String]

    static let unused = LauncherUsage(frecency: 1, searchTerms: [])
}

/// Learns what the user opens, with one decaying usage score per entry.
@MainActor
@Observable
final class LauncherRankingStore {
    nonisolated static let halfLife: TimeInterval = 10 * 86_400
    nonisolated static let visitWeight = 100.0
    nonisolated static let termWindow: TimeInterval = 408 * 3_600
    nonisolated static let termLimit = 3
    private nonisolated static let exponentCeiling = 709.78
    private static let queryLimit = 64

    private let fileURL: URL
    private let now: () -> Date
    private(set) var visits: [String: LauncherVisit]
    /// Part of `AppIndex`'s cache key, invalidating results after a launch or reset.
    private(set) var revision = 0
    @ObservationIgnored private var writeTask: Task<Void, Never>?

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now
        let decoded =
            (try? Data(contentsOf: self.fileURL))
            .flatMap { try? JSONDecoder().decode([String: LauncherVisit].self, from: $0) } ?? [:]
        visits = Self.live(decoded, at: now())
    }

    var isEmpty: Bool { visits.isEmpty }

    func flush() async {
        await writeTask?.value
    }

    /// Nil means this launch was not chosen from a text search.
    func visit(itemKey: String, query: String?) {
        guard !itemKey.isEmpty else { return }
        let timestamp = now()
        let previous = visits[itemKey]
        let score = previous.map { Self.frecency(anchor: $0.anchor, at: timestamp) } ?? 1
        var terms = previous?.searchTerms ?? []
        if let term = query.map(Self.normalize), !term.isEmpty, term.count <= Self.queryLimit {
            terms.removeAll { $0 == term }
            terms.append(term)
            terms = Array(terms.suffix(Self.termLimit))
        }
        visits[itemKey] = LauncherVisit(
            anchor: Self.anchor(visitedWith: score, at: timestamp), openedAt: timestamp,
            searchTerms: terms)
        didMutate()
    }

    /// A single timestamp for every entry in one ordering pass.
    func snapshot() -> Snapshot { Snapshot(visits: visits, now: now()) }

    struct Snapshot: Sendable {
        let visits: [String: LauncherVisit]
        let now: Date

        func usage(for itemKey: String) -> LauncherUsage {
            LauncherRankingStore.usage(of: visits[itemKey], at: now)
        }
    }

    func hasRanking(for itemKey: String) -> Bool { visits[itemKey] != nil }

    func reset(itemKey: String) {
        guard visits.removeValue(forKey: itemKey) != nil else { return }
        didMutate()
    }

    func resetAll() {
        guard !visits.isEmpty else { return }
        visits = [:]
        didMutate()
    }

    /// Applies the same expiration rule to a table restored from a backup.
    func replace(_ imported: [String: LauncherVisit]) {
        visits = Self.live(imported, at: now())
        didMutate()
    }

    nonisolated static func normalize(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return ScriptRomanization.latin(trimmed) ?? FuzzyMatch.normalized(trimmed)
    }

    nonisolated static func frecency(anchor: Date, at timestamp: Date) -> Double {
        let exponent = decay * anchor.timeIntervalSince(timestamp)
        return max(1, exp(min(exponent, exponentCeiling)))
    }

    nonisolated static func anchor(visitedWith score: Double, at timestamp: Date) -> Date {
        timestamp.addingTimeInterval(log(score + visitWeight) / decay)
    }

    nonisolated static func usage(of visit: LauncherVisit?, at timestamp: Date) -> LauncherUsage {
        guard let visit else { return .unused }
        let frecency = frecency(anchor: visit.anchor, at: timestamp)
        let recent = frecency > 1 && timestamp.timeIntervalSince(visit.openedAt) < termWindow
        return LauncherUsage(frecency: frecency, searchTerms: recent ? visit.searchTerms : [])
    }

    private nonisolated static let decay = log(2) / halfLife

    private nonisolated static func live(
        _ table: [String: LauncherVisit], at timestamp: Date
    ) -> [String: LauncherVisit] {
        table.filter { !$0.key.isEmpty && $0.value.anchor > timestamp }
    }

    private func didMutate() {
        revision &+= 1
        let snapshot = visits
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultFileURL() -> URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jackdu.delores"
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("launcher-ranking.json")
    }
}
