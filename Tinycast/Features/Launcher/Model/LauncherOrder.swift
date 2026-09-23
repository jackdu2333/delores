import Foundation

/// How loosely root search accepts a fuzzy subsequence.
enum SearchSensitivity: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        return switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    func accepts(_ match: FuzzyMatch.Match) -> Bool {
        guard match.tier == .subsequence else { return true }
        let best = Double(FuzzyMatch.referenceSpread(match.queryLength))
        let fraction = Double(match.spread) / best
        return switch self {
        case .low: true
        case .medium: fraction >= 0.35
        case .high: fraction >= 0.55
        }
    }
}

/// Root-search ordering and the empty-query order, kept pure for the launcher harnesses.
enum LauncherOrder {
    struct Signals: Sendable {
        var userAlias: String?
        var usage: LauncherUsage
        var priority: Int
        var title: String
        var boostedTerms: Set<String> = []
    }

    static func ranked<Item>(
        _ items: [Item], query: FuzzyMatch.Query, sensitivity: SearchSensitivity, limit: Int,
        fields: (Item) -> SearchFields, signals: (Item) -> Signals
    ) -> [Item] {
        guard !query.isEmpty else { return [] }
        let term = LauncherRankingStore.normalize(query.value)
        let scored = items.enumerated().compactMap { position, item -> (Item, Candidate)? in
            let signal = signals(item)
            let hits = SearchRelevance.hits(query, fields: fields(item)).filter {
                sensitivity.accepts($0.match)
            }
            guard let relevance = hits.map(\.quality).max() else { return nil }
            let titleHits = hits.filter {
                $0.alias.role == .name || $0.alias.role == .translation
            }
            let titleExact = titleHits.contains { $0.match.tier == .exact }
            let titleQuality = titleHits.map(\.quality).max() ?? 0
            let protectedName = hits.contains {
                $0.alias.role == .name && $0.match.tier == .exact
                    && FuzzyMatch.normalized($0.alias.text) == FuzzyMatch.normalized(signal.title)
            }
            let alias = signal.userAlias.map { aliasHit($0, query.value) } ?? .none
            let exactAlias = hits.contains {
                $0.alias.role == .userAlias && $0.match.tier == .exact
            }
            let isProtected = protectedName || exactAlias || alias == .exact
            let facts = Facts(
                alias: alias,
                isProtected: isProtected,
                isBoosted: signal.boostedTerms.contains(term),
                titleExact: titleExact,
                titleQuality: titleQuality,
                relevance: relevance,
                term: termHit(signal.usage.searchTerms, term))
            return (item, Candidate(facts: facts, signals: signal, position: position))
        }
        let length = term.utf16.count
        return scored.sorted {
            precedes($0.1, $1.1, queryLength: length)
        }.prefix(limit).map(\.0)
    }

    /// Empty-query order: global frecency, then aliases, kind priority and title.
    static func byUsage<Item>(_ items: [Item], signals: (Item) -> Signals) -> [Item] {
        items.enumerated()
            .map { ($0.element, Candidate(facts: nil, signals: signals($0.element), position: $0.offset)) }
            .sorted {
                let order = tiebreak($0.1, $1.1)
                return order != 0 ? order < 0 : $0.1.position < $1.1.position
            }
            .map(\.0)
    }

    private struct Candidate {
        let facts: Facts?
        let signals: Signals
        let position: Int
    }

    private struct Facts {
        let alias: AliasHit
        let isProtected: Bool
        let isBoosted: Bool
        let titleExact: Bool
        let titleQuality: Int
        let relevance: Int
        let term: TermHit
    }

    private enum AliasHit: Equatable {
        case none
        case prefix
        case exact
    }

    private enum TermHit: Equatable {
        case none
        case exact(length: Int)
        case prefix(length: Int)
        case overbounds(length: Int)

        var strength: Int {
            switch self {
            case .none: 0
            case .overbounds: 1
            case .prefix: 2
            case .exact: 3
            }
        }

        var isExact: Bool { if case .exact = self { true } else { false } }
        var isPrefix: Bool { if case .prefix = self { true } else { false } }

        var isLongOverbounds: Bool {
            return switch self {
            case .overbounds(let length): length >= LauncherOrder.overboundsFloor
            default: false
            }
        }
    }

    private static let overboundsReach = 3
    private static let overboundsFloor = 3

    private static func precedes(_ lhs: Candidate, _ rhs: Candidate, queryLength: Int) -> Bool {
        let order = compare(lhs, rhs, queryLength: queryLength)
        return order != 0 ? order < 0 : lhs.position < rhs.position
    }

    private static func compare(_ lhs: Candidate, _ rhs: Candidate, queryLength: Int) -> Int {
        guard let left = lhs.facts, let right = rhs.facts else {
            return tiebreak(lhs, rhs)
        }
        if left.isProtected != right.isProtected { return left.isProtected ? -1 : 1 }
        if left.isProtected, left.relevance != right.relevance {
            return descending(left.relevance, right.relevance)
        }
        if left.alias == .exact || right.alias == .exact {
            if left.alias != right.alias { return left.alias == .exact ? -1 : 1 }
        }
        if left.isBoosted != right.isBoosted {
            let (boosted, other) = left.isBoosted ? (lhs, rhs) : (rhs, lhs)
            if !(other.signals.usage.frecency > 1
                && other.signals.usage.frecency > boosted.signals.usage.frecency)
            {
                return left.isBoosted ? -1 : 1
            }
        }
        if queryLength > 3, left.titleExact || right.titleExact {
            guard left.titleExact, right.titleExact else { return left.titleExact ? -1 : 1 }
            return first(termStrength(left.term, right.term), frecency(lhs, rhs))
                ?? tiebreak(lhs, rhs)
        }
        if left.term.isExact || right.term.isExact {
            guard left.term.isExact, right.term.isExact else { return left.term.isExact ? -1 : 1 }
            return first(frecency(lhs, rhs)) ?? tiebreak(lhs, rhs)
        }
        if left.alias == .prefix || right.alias == .prefix {
            if left.alias != right.alias { return left.alias == .prefix ? -1 : 1 }
        }
        if left.term.isPrefix || right.term.isPrefix {
            if left.term.isPrefix != right.term.isPrefix { return left.term.isPrefix ? -1 : 1 }
        }
        if case .overbounds(let a) = left.term, case .overbounds(let b) = right.term,
            a != b, a >= overboundsFloor || b >= overboundsFloor
        {
            return descending(a, b)
        }
        if left.term.isLongOverbounds != right.term.isLongOverbounds {
            return left.term.isLongOverbounds ? -1 : 1
        }
        if left.term.isLongOverbounds, right.term == .none { return -1 }
        if right.term.isLongOverbounds, left.term == .none { return 1 }
        return first(
            descending(max(left.titleQuality, left.relevance), max(right.titleQuality, right.relevance)),
            frecency(lhs, rhs),
            descending(left.titleQuality, right.titleQuality),
            descending(lhs.signals.priority, rhs.signals.priority)) ?? collate(lhs, rhs)
    }

    private static func tiebreak(_ lhs: Candidate, _ rhs: Candidate) -> Int {
        let alias = descending(lhs.signals.userAlias == nil ? 0 : 1, rhs.signals.userAlias == nil ? 0 : 1)
        return first(
            frecency(lhs, rhs), alias,
            descending(lhs.signals.priority, rhs.signals.priority)) ?? collate(lhs, rhs)
    }

    private static func aliasHit(_ alias: String, _ query: String) -> AliasHit {
        let candidate = FuzzyMatch.normalized(alias)
        if candidate == query { return .exact }
        return candidate.hasPrefix(query) ? .prefix : .none
    }

    private static func termHit(_ terms: [String], _ query: String) -> TermHit {
        let typed = Array(query.utf16)
        var best = TermHit.none
        for term in terms.reversed() {
            let stored = Array(term.utf16)
            guard !stored.isEmpty else { continue }
            if stored.count > typed.count {
                guard stored.starts(with: typed) else { continue }
                if !best.isPrefix { best = .prefix(length: stored.count) }
            } else if stored.count == typed.count {
                if stored == typed { return .exact(length: stored.count) }
            } else if typed.starts(with: stored) {
                let extra = typed.count - stored.count
                guard extra <= overboundsReach else { continue }
                if case .overbounds(let length) = best, length >= stored.count { continue }
                if !best.isPrefix { best = .overbounds(length: stored.count) }
            }
        }
        return best
    }

    private static func termStrength(_ lhs: TermHit, _ rhs: TermHit) -> Int {
        if lhs.strength != rhs.strength { return descending(lhs.strength, rhs.strength) }
        if case .overbounds(let left) = lhs, case .overbounds(let right) = rhs {
            return descending(left, right)
        }
        return 0
    }

    private static func frecency(_ lhs: Candidate, _ rhs: Candidate) -> Int {
        descending(lhs.signals.usage.frecency, rhs.signals.usage.frecency)
    }

    private static func collate(_ lhs: Candidate, _ rhs: Candidate) -> Int {
        switch lhs.signals.title.localizedStandardCompare(rhs.signals.title) {
        case .orderedAscending: -1
        case .orderedDescending: 1
        case .orderedSame: 0
        }
    }

    private static func descending<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> Int {
        lhs == rhs ? 0 : (lhs > rhs ? -1 : 1)
    }

    private static func first(_ orders: Int...) -> Int? { orders.first { $0 != 0 } }
}
