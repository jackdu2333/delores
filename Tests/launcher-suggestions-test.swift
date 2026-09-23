import Foundation

@main
struct LauncherSuggestionsTest {
    struct Item {
        let id: String
        let title: String
        var fields: SearchFields
        var usage = LauncherUsage.unused
        var priority = 3
        var alias: String?
    }

    static func signals(_ item: Item) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            userAlias: item.alias, usage: item.usage, priority: item.priority, title: item.title)
    }

    static func main() {
        var failures = 0
        func check(_ label: String, _ condition: Bool) {
            if condition {
                print("PASS  \(label)")
            } else {
                print("FAIL  \(label)")
                failures += 1
            }
        }

        let exact = Item(id: "exact", title: "WhatsApp", fields: [.name("WhatsApp")])
        let rival = Item(
            id: "rival", title: "WhatsApp Clone", fields: [.name("WhatsApp Clone")],
            usage: LauncherUsage(frecency: 1_000_000, searchTerms: ["whatsapp"]))
        let protected = LauncherOrder.ranked(
            [rival, exact], query: FuzzyMatch.Query("WhatsApp"), sensitivity: .low,
            limit: 5, fields: \.fields, signals: signals)
        check("an exact display name stays above a heavily used weaker match",
            protected.first?.id == "exact")

        let learned = Item(
            id: "chatgpt", title: "ChatGPT",
            fields: [.name("ChatGPT"), .translation("Codex")],
            usage: LauncherUsage(frecency: 101, searchTerms: ["codex"]))
        let popular = Item(
            id: "codex", title: "Codex Viewer", fields: [.name("Codex Viewer")],
            usage: LauncherUsage(frecency: 10_000, searchTerms: []))
        let intent = LauncherOrder.ranked(
            [popular, learned], query: FuzzyMatch.Query("codex"), sensitivity: .low,
            limit: 5, fields: \.fields, signals: signals)
        check("a remembered exact search term steers an unprotected result", intent.first?.id == "chatgpt")

        let aliased = Item(
            id: "figma", title: "Figma", fields: [.name("Figma"), .userAlias("fg")], alias: "fg")
        let literalName = Item(id: "fg", title: "fg", fields: [.name("fg")])
        let aliasOrder = LauncherOrder.ranked(
            [literalName, aliased], query: FuzzyMatch.Query("fg"), sensitivity: .low,
            limit: 5, fields: \.fields, signals: signals)
        check("an exact user alias keeps its Delores priority", aliasOrder.first?.id == "figma")

        let chineseAlias = Item(
            id: "chinese-alias", title: "Chat Tool",
            fields: [.name("Chat Tool"), .userAlias("微信")], alias: "微信")
        let chineseName = Item(id: "chinese-name", title: "微信", fields: [.name("微信")])
        let chineseOrder = LauncherOrder.ranked(
            [chineseName, chineseAlias], query: FuzzyMatch.Query("微信"), sensitivity: .low,
            limit: 5, fields: \.fields, signals: signals)
        check("an exact Chinese user alias remains protected", chineseOrder.first?.id == "chinese-alias")

        let loose = Item(
            id: "loose", title: "aXbYcZd", fields: [.name("aXbYcZd")])
        let low = LauncherOrder.ranked(
            [loose], query: FuzzyMatch.Query("abcd"), sensitivity: .low,
            limit: 5, fields: \.fields, signals: signals)
        let high = LauncherOrder.ranked(
            [loose], query: FuzzyMatch.Query("abcd"), sensitivity: .high,
            limit: 5, fields: \.fields, signals: signals)
        check("low sensitivity retains loose subsequences", low.count == 1)
        check("high sensitivity filters loose subsequences", high.isEmpty)

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func candidate(
            _ id: String, used: Double = 1, installed: TimeInterval? = nil,
            hotKey: Bool = false, priority: Int? = nil, alias: String? = nil
        ) -> (Item, LauncherSuggestions.Traits) {
            let item = Item(
                id: id, title: id, fields: [.name(id)],
                usage: LauncherUsage(frecency: used, searchTerms: []), alias: alias)
            return (item, LauncherSuggestions.Traits(
                signals: signals(item), installedAt: installed.map { now.addingTimeInterval(-$0) },
                hasHotKey: hotKey, priority: priority))
        }
        let candidates = [
            candidate("fresh-c", installed: 10),
            candidate("fresh-b", installed: 10),
            candidate("fresh-a", installed: 10),
            candidate("used", used: 100),
            candidate("already-bound", used: 200, hotKey: true, priority: 99),
            candidate("command-high", priority: 90),
            candidate("command-low", priority: 80),
            candidate("aliased-command", priority: 100, alias: "mine")
        ]
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.0.id, $0) })
        let selected = LauncherSuggestions.select(from: candidates.map(\.0), now: now) { item in
            byID[item.id]!.1
        }.map(\.id)
        check("empty-query suggestions prefer two fresh installs, then use and eligible commands",
            selected == ["fresh-a", "fresh-b", "used", "command-high", "command-low"])
        check("a shortcut or alias keeps an item out of the built-in suggestion fill",
            !selected.contains("already-bound") && !selected.contains("aliased-command"))

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
