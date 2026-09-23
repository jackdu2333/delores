import AppKit

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case systemSettings
        case command
        case quickAction
        case systemAction
        case quicklink
        case appleShortcut

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canHideFromSearch: true,
                    canRevealInFinder: true, isSymbolIcon: false, rankPriority: 4)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canHideFromSearch: true,
                    canRevealInFinder: true, isSymbolIcon: false, rankPriority: 1)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, isSymbolIcon: true, rankPriority: 3)
            case .quickAction:
                return KindDescriptor(
                    label: "Quick Action", sectionTitle: "Quick Actions",
                    openVerb: "Run Quick Action", canHideFromSearch: true,
                    canRevealInFinder: false, isSymbolIcon: true, rankPriority: 3)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canHideFromSearch: true,
                    canRevealInFinder: false, isSymbolIcon: true, rankPriority: 3)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks",
                    openVerb: "Open Quicklink", canHideFromSearch: false,
                    canRevealInFinder: false, isSymbolIcon: true, rankPriority: 2)
            case .appleShortcut:
                // File-backed so every row draws the Shortcuts app's own icon.
                return KindDescriptor(
                    label: "Apple Shortcut", sectionTitle: "Apple Shortcuts",
                    openVerb: "Run Shortcut", canHideFromSearch: true,
                    canRevealInFinder: false, isSymbolIcon: false, rankPriority: 3)
            }
        }
    }

    /// Everything fixed per kind. A new `Kind` case fails to name each field before it ships.
    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        /// Only where Settings lists a per-item checkbox to put it back: a hide is never one-way.
        let canHideFromSearch: Bool
        let canRevealInFinder: Bool
        let isSymbolIcon: Bool
        /// A stable tie-break in usage-ordered results; it never outranks a search match.
        let rankPriority: Int
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// Set when a feature pane, not this entry's category pane, lists its controls and gates it.
    var settingsOwner: SettingsTab?
    /// Secondary label beside the name, for an entry whose name alone can't say what it acts on.
    var subtitle: String?
    /// Other names as strong as the display name, such as a localized application name.
    var matchAliases: [String] = []
    /// Per-item symbol, for the one kind whose glyph is the user's choice. Nil elsewhere.
    var symbolName: String?
    /// Other ways to say this entry's name: Spotlight alternates, localizations, romanizations.
    var alternateNames: [String] = []
    /// `CFBundleExecutable`, matched literally as a last resort. Applications only.
    var executableName: String?
    /// Moves when the bundle's icon changes on disk, retiring the cached bitmap. Applications only.
    var iconStamp: Int = 0
    /// When the app was added to its parent folder, for first-open suggestions.
    var installedAt: Date?
    /// Set by the feature that produced the entry when its glyph isn't derivable from `kind`.
    var iconOverride: EntryIcon?
    /// The searchable form of every field above, built at publish by `buildAliases`.
    var aliases: [SearchAlias] = []

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    /// What this entry is called, in the shape `EntryNaming` reads.
    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.strongNames = matchAliases
        sources.translations = alternateNames
        sources.bundleID = bundleID
        sources.executableName = executableName
        return sources
    }

    /// Built once per index change, never per keystroke; only `AppIndex.named` calls it.
    mutating func buildAliases() { aliases = EntryNaming.aliases(for: naming) }

    /// Only a name the entry lacks adds anything; a bundle usually spells itself the same twice.
    mutating func addStrongName(_ candidate: String) {
        let existing = [name] + matchAliases
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        matchAliases.append(candidate)
    }

    var kindLabel: String { kind.descriptor.label }

    /// The hotkey action for this entry, or nil when the entry has no addressable action.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .quickAction:
            if let command = CommandCatalog.command(for: self) { return command.hotKeyAction }
            return CustomQuickAction.id(fromEntryID: id).map { .quickAction(id: $0) }
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .quicklink:
            return Quicklink.id(fromEntryID: id).map { .quicklink(id: $0) }
        case .appleShortcut:
            return AppleShortcut.id(fromEntryID: id).map { .appleShortcut(id: $0) }
        default:
            return nil
        }
    }

    /// Synthetic entries have no file to reveal; a destination is its record's own action.
    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    var canHideFromSearch: Bool { kind.descriptor.canHideFromSearch }

    /// What this row draws, and the only thing any icon path needs to ask.
    var iconSource: EntryIcon { iconOverride ?? defaultIcon }

    /// Derived from the kind alone: synthetic entries get a symbol tile, everything else its file.
    private var defaultIcon: EntryIcon {
        guard kind.descriptor.isSymbolIcon else { return .file(stamp: iconStamp) }
        return .symbol(symbolName ?? kindSymbol)
    }

    private var kindSymbol: String {
        switch kind {
        case .quicklink: return Quicklink.sfSymbol
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .quickAction:
            return CommandCatalog.command(for: self)?.sfSymbol ?? CustomQuickAction.sfSymbol
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .application, .systemSettings, .appleShortcut: return "questionmark"
        }
    }

    /// Main-actor because it subscribes the calling view; every caller is a `body`.
    @MainActor var icon: NSImage {
        IconCache.observeStyle()
        return IconCache.icon(for: iconSource, fileURL: url)
    }

    /// Icon identity for a row's async load: re-skinning changes the glyph while `id` stays put.
    var iconKey: String { "\(id)|\(iconSource)" }
}

extension AppEntry {
    /// The one row a custom Quick Action draws, wherever it is offered from.
    init(_ action: CustomQuickAction) {
        self.init(
            id: action.entryID, name: action.name,
            url: URL(string: "tinycast://quick-action/" + action.id.uuidString)!,
            bundleID: nil, kind: .quickAction, symbolName: action.iconSymbol)
    }

    /// The one row a quicklink draws, wherever it is offered from.
    init(_ quicklink: Quicklink) {
        self.init(
            id: quicklink.entryID, name: quicklink.name,
            url: URL(string: "tinycast://quicklink/" + quicklink.id.uuidString)!,
            bundleID: nil, kind: .quicklink,
            symbolName: quicklink.iconSymbol
                ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol)
    }

    /// No bundle id: that would key every shortcut's alias and ranking to the Shortcuts app.
    init(_ shortcut: AppleShortcut, applicationURL: URL) {
        self.init(
            id: shortcut.entryID, name: shortcut.name, url: applicationURL, bundleID: nil,
            kind: .appleShortcut)
    }
}

extension AppEntry.Kind {
    /// The descriptors' own words, lowercased once, so a keystroke costs a lookup and not a scan.
    private static let byCategoryName: [String: AppEntry.Kind] = allCases.reduce(into: [:]) {
        $0[$1.descriptor.sectionTitle.lowercased()] = $1
        $0[$1.descriptor.label.lowercased()] = $1
    }

    /// The category a query names outright. Exact only — a prefix would take a word from an entry.
    static func named(by query: String) -> AppEntry.Kind? {
        byCategoryName[query.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}

@MainActor
@Observable
final class AppIndex {
    private(set) var apps: [AppEntry] = []
    private static let sectionOrder: [AppEntry.Kind] = [
        .application, .systemSettings, .quicklink, .appleShortcut, .systemAction, .quickAction,
        .command
    ]

    private struct MatchKey: Equatable {
        let query: String
        let limit: Int
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let sensitivity: SearchSensitivity
        let minute: Int
    }

    private struct ResultsKey: Equatable {
        let match: MatchKey
        let visibilityRevision: Int
        let favoritesRevision: Int
        let hotKeysRevision: Int
        let showsSuggestions: Bool
    }

    struct Results: Equatable {
        var entries: [AppEntry] = []
        var favoriteCount = 0
        var suggestionCount = 0
    }

    /// Repeated renders for the same query reuse the ranking instead of re-matching every frame.
    @ObservationIgnored private var matchMemo = Memo<MatchKey, [AppEntry]>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, Results>()
    /// Bumped whenever `apps` changes, so both memos above name the entry set they were built from.
    private var entriesRevision = 0

    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "tinycast://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    private var discoveredEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    private var appleShortcutEntries: [AppEntry] = []
    private var customQuickActionEntries: [AppEntry] = []
    /// The catalog's commands a disabled feature hides; the Commands slice is recomputed from it.
    private var hiddenCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var isRefreshing = false
    /// Set when a refresh lands mid-scan, so a scope edit is never silently dropped.
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?
    /// Fires after every scan, including unchanged ones, to reconcile app-owned hotkeys.
    @ObservationIgnored var onScan: (() -> Void)?

    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    /// The always-relevant built-ins, plus whatever a disabled feature has not hidden.
    private var commandEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .command }
    }

    private var quickActionEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .quickAction } + customQuickActionEntries
    }

    private var visibleCatalogEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command)
        }
    }

    /// Whether the feature behind a command is on, which is what its shortcut has to obey too.
    func isCommandEnabled(_ command: CommandID) -> Bool {
        !hiddenCommands.contains(command)
    }

    /// A feature's commands leave the Commands slice when it is off; `visible` restores them.
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    /// Replaces the custom Quick Action slice, which shares its section with the shipped four.
    func setCustomQuickActions(_ actions: [CustomQuickAction]) {
        let entries = actions.sorted(by: CustomQuickAction.precedes).map(AppEntry.init)
        guard entries != customQuickActionEntries else { return }
        customQuickActionEntries = entries
        publishEntries()
    }

    /// Replaces the quicklink slice; a toggle can't split its entries from their section.
    func setQuicklinks(_ quicklinks: [Quicklink]) {
        let entries =
            quicklinks
            .filter { $0.isEnabled && $0.showsInRootSearch }
            .sorted(by: Quicklink.precedes)
            .map(AppEntry.init)
        guard entries != quicklinkEntries else { return }
        quicklinkEntries = entries
        publishEntries()
    }

    /// Discovered from the Shortcuts app, so it arrives already built and sorted.
    func setAppleShortcuts(_ entries: [AppEntry]) {
        guard entries != appleShortcutEntries else { return }
        appleShortcutEntries = entries
        publishEntries()
    }

    /// Wires the scopes, re-indexing on edit rather than waiting for the next open.
    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    /// Fires synchronously on main before the write lands, so the task re-arms, then rescans.
    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    /// Re-scan on every open; reopens collapse, and an unchanged set does no UI work.
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let reusingPanes = paneCache
            let languages = BundleLocalization.indexedLanguages(Locale.preferredLanguages)
            let reusing = BundleNameCache(reusing: nameCache, languages: languages)
            let (found, cache, panes) = await Task.detached(priority: .utility) {
                AppIndex.scan(
                    scopes: scopes, languages: languages, cache: reusing, paneCache: reusingPanes)
            }.value
            nameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
        onScan?()
    }

    /// Missing from the index and LaunchServices, so excluding a scope is never treated as deletion.
    func isUninstalled(bundleID: String) -> Bool {
        !discoveredEntries.contains { $0.kind == .application && $0.bundleID == bundleID }
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
    }

    nonisolated private static func scan(
        scopes: [String], languages: [String], cache: BundleNameCache,
        paneCache: SettingsPaneScanner.Cache?
    ) -> ([AppEntry], BundleNameCache, SettingsPaneScanner.Cache?) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var indexByBundleID: [String: Int] = [:]
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let fileName = EntryNaming.strippingAppExtension(url.lastPathComponent)
                // Dedup by bundle id; the first scope wins, but a renamed copy lends its name.
                if let bundleID, let first = indexByBundleID[bundleID] {
                    result[first].addStrongName(fileName)
                    continue
                }

                // Finder's rule: LaunchServices ignores a display name the file name contradicts.
                let names = cache.names(
                    for: url, base: fileName, developmentRegion: bundle?.developmentLocalization)
                let name = names.localized.first ?? fileName
                let executable =
                    bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                var entry = AppEntry(
                    id: url.path, name: name, url: url, bundleID: bundleID,
                    kind: .application,
                    alternateNames: Array(names.localized.dropFirst()) + names.alternates,
                    executableName: executable, iconStamp: FileIconStamp.value(for: url),
                    installedAt: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
                        .addedToDirectoryDate)
                entry.addStrongName(fileName)
                // Still searchable, never the label: `code` must keep finding Visual Studio Code.
                if let declared = bundle?.installedAppName { entry.addStrongName(declared) }
                if let bundleID { indexByBundleID[bundleID] = result.count }
                result.append(entry)
            }
            // Slice order is section order, so the flat selection maps 1:1 onto rows.
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // Settings panes are `.appex` bundles, which carry no Spotlight alternate names.
            let (panes, panesCache) = SettingsPaneScanner.scan(languages: languages, cache: paneCache)
            // Named here, not at publish: romanizing a CJK index is ~50 ms of main-actor time.
            return (AppIndex.named(apps + panes), cache, panesCache)
        }
    }

    /// The searchable form of every name an entry carries. `scan` names the app slice itself.
    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildAliases()
            return entry
        }
    }

    private func publishEntries() {
        // Each slice arrives in its own display order; the slice order is the section order.
        let updated =
            discoveredEntries
            + Self.named(
                quicklinkEntries + appleShortcutEntries + Self.systemActionEntries
                    + quickActionEntries
                    + commandEntries)
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    /// Ranked matches, or a whole category when named; an empty query returns the unsorted index.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return matched(q, limit: limit, usage: ranking.snapshot())
    }

    private func matched(
        _ query: String, limit: Int, usage: LauncherRankingStore.Snapshot
    ) -> [AppEntry] {
        let key = matchKey(
            query, limit: limit, minute: Int(usage.now.timeIntervalSince1970 / 60))
        return matchMemo.value(for: key) {
            guard let kind = AppEntry.Kind.named(by: query) else {
                return rank(query, limit: limit, usage: usage)
            }
            return categoryListing(kind, query: query, usage: usage)
        }
    }

    /// Exact category matches remain visible and sort by usage within the named category.
    private func categoryListing(
        _ kind: AppEntry.Kind, query: String, usage: LauncherRankingStore.Snapshot
    ) -> [AppEntry] {
        let listed = apps.filter {
            $0.kind == kind || FuzzyMatch.normalized($0.name) == FuzzyMatch.normalized(query)
        }
        return orderedByKind(listed, usage: usage)
    }

    /// Keeps the flat selection in the same kind order the sectioned list draws.
    private func orderedByKind(
        _ entries: [AppEntry], usage: LauncherRankingStore.Snapshot
    ) -> [AppEntry] {
        var groups: [AppEntry.Kind: [AppEntry]] = [:]
        for entry in entries { groups[entry.kind, default: []].append(entry) }
        assert(groups.keys.allSatisfy(Self.sectionOrder.contains))
        return Self.sectionOrder.flatMap { kind in
            LauncherOrder.byUsage(groups[kind] ?? []) { self.signals(for: $0, usage: usage) }
        }
    }

    /// Ranked matches, or favorites, suggestions and usage-ordered entries when the query is empty.
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore, hotKeys: HotKeyManager
    ) -> Results {
        let q = query.trimmingCharacters(in: .whitespaces)
        let usage = ranking.snapshot()
        let showsSuggestions = settings?.launcherShowsSuggestions ?? true
        let key = ResultsKey(
            match: matchKey(
                q, limit: 200, minute: Int(usage.now.timeIntervalSince1970 / 60)),
            visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision, hotKeysRevision: hotKeys.revision,
            showsSuggestions: showsSuggestions)
        return resultsMemo.value(for: key) {
            let base = q.isEmpty ? apps : matched(q, limit: 200, usage: usage)
            let visible = base.filter(visibility.isVisible)
            guard q.isEmpty else { return Results(entries: visible) }
            let ordered = orderedByKind(visible, usage: usage)
            let split = favorites.ordered(ordered)
            let suggested = showsSuggestions
                ? self.suggestions(from: split.rest, usage: usage, hotKeys: hotKeys) : []
            let suggestedIDs = Set(suggested.map(\.id))
            let rest = orderedByKind(
                split.rest.filter { !suggestedIDs.contains($0.id) }, usage: usage)
            return Results(
                entries: split.favorites + suggested + rest,
                favoriteCount: split.favorites.count, suggestionCount: suggested.count)
        }
    }

    private var sensitivity: SearchSensitivity { settings?.rootSearchSensitivity ?? .high }

    private func matchKey(_ query: String, limit: Int, minute: Int) -> MatchKey {
        MatchKey(
            query: query, limit: limit, entriesRevision: entriesRevision,
            rankingRevision: ranking.revision, aliasRevision: aliases.revision,
            sensitivity: sensitivity, minute: minute)
    }

    private func rank(
        _ q: String, limit: Int, usage: LauncherRankingStore.Snapshot
    ) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            return LauncherOrder.ranked(
                apps, query: FuzzyMatch.Query(q), sensitivity: sensitivity, limit: limit,
                fields: { app in
                    guard let alias = self.aliases.alias(for: app.preferenceKey) else {
                        return SearchFields(app.aliases)
                    }
                    return SearchFields(app.aliases + [.userAlias(alias)])
                },
                signals: { self.signals(for: $0, usage: usage) })
        }
    }

    private func signals(
        for app: AppEntry, usage: LauncherRankingStore.Snapshot
    ) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            userAlias: aliases.alias(for: app.preferenceKey),
            usage: usage.usage(for: app.preferenceKey),
            priority: app.kind.descriptor.rankPriority,
            title: app.name,
            boostedTerms: CommandCatalog.command(for: app)?.boostedTerms ?? [])
    }

    private func suggestions(
        from entries: [AppEntry], usage: LauncherRankingStore.Snapshot, hotKeys: HotKeyManager
    ) -> [AppEntry] {
        let eligible = entries.filter { $0.bundleID != Bundle.main.bundleIdentifier }
        return LauncherSuggestions.select(from: eligible, now: usage.now) { entry in
            LauncherSuggestions.Traits(
                signals: self.signals(for: entry, usage: usage), installedAt: entry.installedAt,
                hasHotKey: entry.hotKeyAction.flatMap(hotKeys.binding(for:)) != nil,
                priority: CommandCatalog.command(for: entry)?.suggestionPriority)
        }
    }
}
