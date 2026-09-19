import Foundation

@main
@MainActor
struct ClipboardSearchTests {
    static var checks = 0
    static let queries = [
        "", " ", "a", "al", "common", "invoice", "rare", "absent-value",
        "COMMON", "café", "日本語", "say \"yes\"", "  common  ", "pdf"
    ]

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipboard-search-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        store.maxAge = ClipboardRetention.forever.maxAge
        let now = Date()
        let entries = (0..<2500).map { index in
            let kind: ClipboardItem.Kind = index % 3 == 0 ? .text : index % 3 == 1 ? .file : .image
            let suffix = " \(index) café 日本語 say \"yes\"" + (index % 401 == 0 ? " rare" : "")
            return ClipboardItem(
                id: UUID(), kind: kind,
                text: kind == .text
                    ? "Common alphabet" + suffix
                    : kind == .file ? "/fixture/common\(index).pdf" : nil,
                imagePath: kind == .image ? "/fixture/\(index).png" : nil,
                createdAt: now.addingTimeInterval(Double(-index)), sourceBundleID: nil,
                pinnedAt: index < 220 ? now.addingTimeInterval(Double(-index)) : nil)
        }
        precondition(
            ClipboardStore.importStoredItems(inDatabaseAt: store.dbURL, entries) == entries.count)
        store.load()
        try compare(store, phase: "mixed history")
        store.promote(entries[400])
        store.togglePinned(entries[401])
        try compare(store, phase: "promotion and pinning")
        store.remove(entries[400])
        try compare(store, phase: "deleted row")
        store.clearAll()
        try compare(store, phase: "cleared")
        store.close()
        store.open()
        store.load()
        for query in queries { precondition(store.search(query, filter: .all).isEmpty) }
        print("\(checks) search comparisons passed")
    }

    static func sameResults(_ actual: [ClipboardItem], _ expected: [ClipboardItem]) -> Bool {
        actual.map(\.id) == expected.map(\.id) && actual.map(\.isPinned) == expected.map(\.isPinned)
    }

    static func compare(_ store: ClipboardStore, phase: String) throws {
        var stored: [ClipboardItem] = []
        ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { stored.append($0) }
        let all = Array(stored.reversed())
        let pins = store.items.filter(\.isPinned).sorted { $0.pinnedAt! < $1.pinnedAt! }
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            let candidates = trimmed.count < 3 ? store.items : all
            let normal =
                trimmed.isEmpty
                ? store.items.filter { !$0.isPinned }
                : Array(
                    candidates.filter { $0.matches(trimmed) }
                        .prefix(trimmed.count < 3 ? Int.max : 200)
                ).filter { !$0.isPinned }
            let normalPins = trimmed.isEmpty ? pins : pins.filter { $0.matches(trimmed) }
            for filter in ClipboardFilter.allCases {
                let expected = filter.apply(to: normalPins + normal)
                let actual = store.search(query, filter: filter)
                precondition(
                    sameResults(actual, expected), "\(phase): \(query) / \(filter)")
                precondition(
                    sameResults(store.search(query, filter: filter), expected), "memo differs")
                precondition(Set(actual.map(\.id)).count == actual.count, "duplicate result")
                checks += 1
            }
        }
    }
}
