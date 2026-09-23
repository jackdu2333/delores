import Foundation

@main
struct RankingTest {
    @MainActor
    static func main() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ranking-\(UUID().uuidString).json")
        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let store = LauncherRankingStore(fileURL: fileURL) { clock }
        let app = "net.whatsapp.WhatsApp"
        let other = "com.example.other"
        var failures = 0

        func check(_ label: String, _ condition: Bool) {
            if condition {
                print("PASS  \(label)")
            } else {
                print("FAIL  \(label)")
                failures += 1
            }
        }

        check("empty store starts with no learned visits", store.isEmpty)
        check("Chinese and pinyin searches share a learned term",
            LauncherRankingStore.normalize("微信") == LauncherRankingStore.normalize("wei xin"))

        let revision = store.revision
        store.visit(itemKey: app, query: "Wha")
        let first = store.snapshot().usage(for: app)
        check("one launch adds 100 to the frecency baseline", abs(first.frecency - 101) < 0.001)
        check("a search launch remembers its normalized term", first.searchTerms == ["wha"])
        check("a visit invalidates ranking memos", store.revision > revision)

        store.visit(itemKey: app, query: "Wha")
        check("repeating a term does not duplicate it",
            store.snapshot().usage(for: app).searchTerms == ["wha"])
        for query in ["one", "two", "three", "four"] {
            store.visit(itemKey: app, query: query)
        }
        check("only the three latest distinct terms remain",
            store.visits[app]?.searchTerms == ["two", "three", "four"])
        store.visit(itemKey: app, query: "three")
        check("a repeated older term moves to the newest position",
            store.visits[app]?.searchTerms == ["two", "four", "three"])

        store.visit(itemKey: app, query: nil)
        check("a direct launch keeps recent search intent",
            store.snapshot().usage(for: app).searchTerms == ["two", "four", "three"])
        let fresh = store.snapshot().usage(for: app).frecency
        clock.addTimeInterval(10 * 86_400)
        let decayed = store.snapshot().usage(for: app).frecency
        check("frecency halves over its ten-day half-life", abs(decayed - fresh / 2) < 0.001)
        clock.addTimeInterval(LauncherRankingStore.termWindow + 1)
        check("search intent expires after its shorter window",
            store.snapshot().usage(for: app).searchTerms.isEmpty)

        store.visit(itemKey: other, query: "other")
        check("snapshot gives unseen entries the baseline",
            store.snapshot().usage(for: "never-opened").frecency == 1)
        store.reset(itemKey: app)
        check("per-entry reset removes only that visit",
            !store.hasRanking(for: app) && store.hasRanking(for: other))

        let preserved = store.visits
        await store.flush()
        let reloaded = LauncherRankingStore(fileURL: fileURL) { clock }
        check("learned visits persist across store instances", reloaded.visits == preserved)
        reloaded.resetAll()
        check("global reset clears all learned visits", reloaded.isEmpty)

        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ranking-legacy-\(UUID().uuidString).json")
        let legacy = """
            [{"itemKey":"dev.zed.Zed","query":"zed","count":5,"lastUsed":695000000}]
            """
        try? Data(legacy.utf8).write(to: legacyURL)
        let resetLegacy = LauncherRankingStore(fileURL: legacyURL) { clock }
        check("the incompatible per-query table resets cleanly", resetLegacy.isEmpty)

        try? FileManager.default.removeItem(at: legacyURL)
        try? FileManager.default.removeItem(at: fileURL)
        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
