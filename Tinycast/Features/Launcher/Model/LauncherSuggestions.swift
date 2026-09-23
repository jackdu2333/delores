import Foundation

/// Entries worth reaching for before the user types a query.
enum LauncherSuggestions {
    static let limit = 5
    static let recentInstallLimit = 2
    static let recentInstallWindow: TimeInterval = 5 * 60

    struct Traits: Sendable {
        var signals: LauncherOrder.Signals
        var installedAt: Date?
        var hasHotKey: Bool
        var priority: Int?
    }

    static func select<Item>(
        from items: [Item], now: Date, traits: (Item) -> Traits
    ) -> [Item] {
        let all = items.map(traits)
        let signals: (Int) -> LauncherOrder.Signals = { all[$0].signals }
        let fresh = LauncherOrder.byUsage(
            all.indices.filter { isFreshInstall(all[$0], now: now) }, signals: signals)
            .prefix(recentInstallLimit)
        var taken = Set(fresh)
        let used = LauncherOrder.byUsage(
            all.indices.filter {
                !taken.contains($0) && all[$0].signals.usage.frecency > 1 && !all[$0].hasHotKey
            }, signals: signals)
        var picked = Array(fresh) + used
        if picked.count < limit {
            taken.formUnion(used)
            let fill = all.indices
                .filter {
                    !taken.contains($0) && all[$0].signals.userAlias == nil && !all[$0].hasHotKey
                }
                .compactMap { index in all[index].priority.map { (index: index, priority: $0) } }
                .sorted {
                    $0.priority != $1.priority ? $0.priority > $1.priority : $0.index < $1.index
                }
            picked += fill.map(\.index)
        }
        return picked.prefix(limit).map { items[$0] }
    }

    private static func isFreshInstall(_ traits: Traits, now: Date) -> Bool {
        guard traits.signals.usage.frecency <= 1, let installedAt = traits.installedAt else {
            return false
        }
        let age = now.timeIntervalSince(installedAt)
        return age >= 0 && age < recentInstallWindow
    }
}
