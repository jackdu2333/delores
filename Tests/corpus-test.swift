import Foundation

/// Exercises Delores' real alias roles against a synthetic, collision-heavy search corpus.
@main
struct CorpusTest {
    struct Entry: Codable {
        let key: String
        let kind: String
        let name: String
        let strongNames: [String]
        let translations: [String]
        var ownerName: String?
        var bundleID: String?
        var executableName: String?

        var fields: SearchFields {
            var sources = EntryNaming.Sources(name: name)
            sources.strongNames = strongNames
            sources.translations = translations
            sources.ownerName = ownerName
            sources.bundleID = bundleID
            sources.executableName = executableName
            return SearchFields(EntryNaming.aliases(for: sources))
        }

        var priority: Int {
            switch kind {
            case "application": 4
            case "systemSettings": 1
            case "quicklink": 2
            default: 3
            }
        }
    }

    struct Case: Codable {
        let query: String
        let expect: String
        let criterion: String
        var protected: Bool?
        var note: String?
    }

    struct Corpus: Codable {
        let entries: [Entry]
        let cases: [Case]
    }

    nonisolated(unsafe) static var failures = 0

    static func check(_ description: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
        if condition {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)  \(detail())")
            failures += 1
        }
    }

    static func main() {
        let url = URL(fileURLWithPath: "Tests/launcher-corpus/corpus.json")
        guard let data = try? Data(contentsOf: url),
            let corpus = try? JSONDecoder().decode(Corpus.self, from: data)
        else {
            print("FAIL  corpus.json is unreadable — run from the repo root")
            exit(1)
        }
        print("# corpus: \(corpus.entries.count) entries, \(corpus.cases.count) cases")
        coldAccuracy(corpus)
        queryLearning(corpus)
        protectedNames(corpus)
        exit(failures == 0 ? 0 : 1)
    }

    static func rank(
        _ query: String, _ entries: [Entry], usage: [String: Double] = [:], limit: Int = 200
    ) -> [Entry] {
        let term = LauncherRankingStore.normalize(query)
        return LauncherOrder.ranked(
            entries, query: FuzzyMatch.Query(query), sensitivity: .low, limit: limit,
            fields: \.fields,
            signals: { entry in
                let fields = entry.fields
                let value = usage[entry.key] ?? 1
                return LauncherOrder.Signals(
                    userAlias: fields.aliases.first { $0.role == .userAlias }?.text,
                    usage: LauncherUsage(
                        frecency: value, searchTerms: value > 1 ? [term] : []),
                    priority: entry.priority, title: entry.name)
            })
    }

    static func coldAccuracy(_ corpus: Corpus) {
        print("\n# cold root search")
        var matched = 0
        var top1 = 0
        var top5 = 0
        var misses: [String] = []
        for test in corpus.cases {
            let ranked = rank(test.query, corpus.entries, limit: corpus.entries.count)
            let position = ranked.firstIndex { $0.key == test.expect }
            if position != nil { matched += 1 }
            if position == 0 { top1 += 1 } else { misses.append("'\(test.query)' (\(test.criterion))") }
            if let position, position < 5 { top5 += 1 }
        }
        check("chosen entry remains matchable (\(matched)/\(corpus.cases.count))", matched >= 51)
        check("cold top-1 (\(top1)/\(corpus.cases.count))", top1 >= 38, "missed \(misses.prefix(8))")
        check("cold top-5 (\(top5)/\(corpus.cases.count))", top5 >= 50)
    }

    static func queryLearning(_ corpus: Corpus) {
        print("\n# query-specific learning")
        var learnedFirst = 0
        var protected = 0
        var stuck: [String] = []
        for test in corpus.cases {
            let learned = rank(test.query, corpus.entries, usage: [test.expect: 101])
            if learned.first?.key == test.expect {
                learnedFirst += 1
            } else {
                stuck.append("'\(test.query)' → \(test.expect)")
            }
            if test.protected == true { protected += 1 }
        }
        check("query intent wins in the unprotected cases (\(learnedFirst)/\(corpus.cases.count))",
            learnedFirst >= 50, "still behind: \(stuck)")
        check("every protected collision documents its escape", protected == 1
            && corpus.cases.filter { $0.protected == true }.allSatisfy { $0.note != nil })
    }

    static func protectedNames(_ corpus: Corpus) {
        print("\n# exact-name protection")
        var checked = 0
        var violations = 0
        for entry in corpus.entries where entry.name.count >= 3 {
            let rivals = corpus.entries.filter { $0.key != entry.key }
            let usage = Dictionary(uniqueKeysWithValues: rivals.map { ($0.key, 1_000_000.0) })
            guard let first = rank(entry.name, corpus.entries, usage: usage, limit: 1).first else {
                continue
            }
            checked += 1
            if first.key != entry.key,
                FuzzyMatch.normalized(first.name) != FuzzyMatch.normalized(entry.name)
            {
                violations += 1
            }
        }
        check("exact display names survive stronger rival frecency (\(checked) names)",
            violations == 0, "\(violations) violations")
    }
}
