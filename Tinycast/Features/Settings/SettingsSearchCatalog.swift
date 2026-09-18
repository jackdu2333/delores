import Foundation

/// One searchable place in Settings: a pane, or a row inside one of its `Form` sections.
struct SettingsSearchEntry: Identifiable, Hashable, Sendable {
    let tab: SettingsTab
    /// Where picking this result lands; nil for the pane itself, which is its own result.
    let target: SettingsTarget?
    let title: String
    /// Words a user might type that the visible title doesn't contain.
    let keywords: [String]

    /// Taking the pane from the target is what makes a row filed under the wrong pane unwritable.
    private init(_ target: SettingsTarget, _ title: String, _ keywords: [String]) {
        self.tab = target.tab
        self.target = target
        self.title = title
        self.keywords = keywords
    }

    /// One setting, which its pane marks with a matching `SettingsRowTitle`.
    init(_ anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        let localized = L10n.text(title)
        self.init(.row(anchor, localized), localized, keywords)
    }

    /// A whole group, for a result no single row answers — a list, or a section's master switch.
    init(group anchor: SettingsAnchor, _ title: String, keywords: [String] = []) {
        self.init(.section(anchor), L10n.text(title), keywords)
    }

    init(pane: SettingsTab, keywords: [String] = []) {
        self.tab = pane
        self.target = nil
        self.title = pane.title
        self.keywords = keywords
    }

    var anchor: SettingsAnchor? { target?.anchor }

    var id: String { "\(tab.title)/\(anchor?.title ?? "")/\(title)" }

    /// The result row's second line — "General", or "General › Hyper Key".
    var breadcrumb: String {
        guard let anchor else { return tab.title }
        let section = L10n.text(anchor.title)
        guard section != tab.title else { return tab.title }
        return "\(tab.title) › \(section)"
    }
}

/// What Settings offers to search. Hand-written: a `Form` can't be asked what rows it holds, so a
/// new row is searchable only once it is listed here.
enum SettingsSearchCatalog {
    struct Query: Sendable {
        let terms: [FuzzyMatch.Query]

        init(_ raw: String) {
            terms = raw.split(whereSeparator: \Character.isWhitespace).map {
                FuzzyMatch.Query(String($0))
            }
        }

        var isEmpty: Bool { terms.isEmpty }
    }

    static func results(for raw: String, limit: Int = 50) -> [SettingsSearchEntry] {
        let query = Query(raw)
        guard !query.isEmpty else { return [] }
        // Catalog order is the tie-break, so results don't reshuffle between equal-scoring rows.
        return
            entries
            .enumerated()
            .compactMap { item -> (entry: SettingsSearchEntry, score: Int, rank: Int)? in
                guard let score = score(query, item.element) else { return nil }
                return (item.element, score, item.offset)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.rank < $1.rank }
            .prefix(limit)
            .map(\.entry)
    }

    /// Every term must land somewhere; a term matched in the title outranks one found off it.
    private static func score(_ query: Query, _ entry: SettingsSearchEntry) -> Int? {
        var titleScore = 0
        var titleMatches = 0
        for term in query.terms {
            if let match = FuzzyMatch.match(term, candidate: entry.title) {
                titleMatches += 1
                titleScore += match.score
                continue
            }
            guard
                entry.keywords.contains(where: { FuzzyMatch.match(term, candidate: $0) != nil })
                    || FuzzyMatch.match(term, candidate: entry.breadcrumb) != nil
            else { return nil }
        }

        let band: Int
        if titleMatches == query.terms.count {
            band = 2_000_000
        } else if titleMatches > 0 {
            band = 1_000_000
        } else {
            band = 0
        }
        // A pane outranks its own rows, so a bare "clipboard" lands on the pane rather than a row.
        return band + titleScore + (entry.anchor == nil ? 500_000 : 0)
    }

    // MARK: - The index
    // Pane order, then section order within a pane, so this reads as a table of contents.

    static let entries: [SettingsSearchEntry] =
        general + applications + systemSettings
        + systemActions + commands + quicklinks + appleShortcuts + fallbacks + ai + quickActions + fileSearch
        + navigation + windowManagement + delores + clipboard
        + permissions + backup + about

    private static let general: [SettingsSearchEntry] = [
        .init(pane: .general, keywords: ["preferences", "settings", "偏好", "设置", "通用"]),
        .init(
            .generalGlobalShortcuts, "App Launcher",
            keywords: ["hotkey", "shortcut", "summon", "palette", "热键", "快捷键", "召唤"]),
        .init(
            .generalSearch, "Learned ranking",
            keywords: ["reset", "history", "order", "privacy"]),
        .init(
            .generalHyperKey, "Hyper Key",
            keywords: ["modifier", "remap", "caps lock", "capslock"]),
        .init(
            .generalHyperKey, "Quick Press",
            keywords: ["tap", "escape", "single press"]),
        .init(
            .generalHyperKey, "Include Shift (⇧)",
            keywords: ["modifier", "chord"]),
        .init(
            .generalAppearance, "Theme",
            keywords: ["dark", "light", "mode", "appearance"]),
        .init(
            .generalAppearance, "Interface size",
            keywords: ["text size", "font size", "scale", "zoom", "bigger", "larger", "legible"]),
        .init(
            .generalAppearance, "Background transparency",
            keywords: ["glass", "opacity", "blur", "translucency", "reset"]),
        .init(
            .generalAppearance, "Compact mode",
            keywords: ["slim", "search bar", "small"]),
        .init(
            .generalAppearance, "Show favorites in compact mode",
            keywords: ["pinned", "apps", "compact"]),
        .init(
            .generalAppearance, "Follow the cursor across displays",
            keywords: ["monitor", "screen", "pointer", "multi display"]),
        .init(
            .generalAppearance, "Drag to reposition",
            keywords: ["move", "position", "window"]),
        .init(
            .generalGeneral, "Launch at login",
            keywords: ["startup", "login item", "start", "boot"]),
        .init(
            .generalGeneral, "Show in menu bar",
            keywords: ["menubar", "status item", "icon", "hide"]),
        .init(
            .generalGeneral, "Pop to Root Search",
            keywords: ["reset", "timeout", "back"]),
        .init(
            .generalGeneral, "Escape Key Behavior",
            keywords: ["escape", "esc", "back", "close", "navigate"]),
        .init(
            .generalGeneral, "Auto-switch input source",
            keywords: ["keyboard", "layout", "language", "abc"])
    ]

    private static let applications: [SettingsSearchEntry] = [
        .init(pane: .applications, keywords: ["apps", "index", "launcher", "应用", "程序"]),
        .init(
            group: .applicationsSearchScopes, "Search Scopes",
            keywords: ["folders", "indexed", "locations", "add folder"]),
        .init(
            .applicationsApplications, "Enable Applications",
            keywords: ["hide apps", "visibility"]),
        .init(
            group: .applicationsApplications, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "per app", "hide"])
    ]

    private static let systemSettings: [SettingsSearchEntry] = [
        .init(
            pane: .systemSettings,
            keywords: ["panes", "preferences", "macos", "系统偏好"]),
        .init(
            .systemSettingsSystemSettings, "Enable System Settings",
            keywords: ["hide panes", "visibility"])
    ]

    private static let systemActions: [SettingsSearchEntry] = [
        .init(
            pane: .systemActions,
            keywords: ["sleep", "lock", "restart", "shut down", "empty trash", "睡眠", "锁屏", "重启", "关机"]),
        .init(
            .systemActionsSystemActions, "Enable System Actions",
            keywords: ["hide", "visibility"])
    ]

    private static let commands: [SettingsSearchEntry] = [
        .init(
            pane: .commands,
            keywords: ["built-in", "launcher", "terminal", "内置"]),
        .init(
            .commandsCommands, "Enable Commands",
            keywords: ["hide", "visibility"])
    ]

    private static let quicklinks: [SettingsSearchEntry] = [
        .init(pane: .quicklinks, keywords: ["url", "bookmark", "link", "书签", "链接"]),
        .init(
            .quicklinksQuicklinks, "Enable quicklinks",
            keywords: ["url", "bookmark"]),
        .init(
            .quicklinksQuicklinks, "Add Quicklink",
            keywords: ["new", "url", "bookmark", "alias"]),
        .init(
            group: .quicklinksCommands, "Quicklink commands",
            keywords: ["shortcut", "launcher", "search", "import", "export"]),
        .init(
            .quicklinksBehaviour, "Open in a new window",
            keywords: ["browser", "tab"]),
        .init(
            .quicklinksBehaviour, "When there's no selected text",
            keywords: ["selection", "fallback", "placeholder"]),
        .init(
            .quicklinksBehaviour, "Confirm before deleting",
            keywords: ["ask", "delete", "prompt"]),
        .init(
            .quicklinksImportExport, "Import quicklinks",
            keywords: ["json", "restore"]),
        .init(
            .quicklinksImportExport, "Export quicklinks",
            keywords: ["json", "backup"])
    ]

    private static let appleShortcuts: [SettingsSearchEntry] = [
        .init(pane: .appleShortcuts, keywords: ["shortcuts app", "automation", "workflow", "快捷指令", "自动化"]),
        .init(
            .appleShortcutsAppleShortcuts, "Enable Apple Shortcuts",
            keywords: ["shortcuts app", "automation", "workflow"]),
        .init(
            group: .appleShortcutsShortcuts, "Aliases and shortcuts",
            keywords: ["alias", "hotkey", "hide"])
    ]

    private static let fallbacks: [SettingsSearchEntry] = [
        .init(
            pane: .fallbacks,
            keywords: ["no results", "empty", "search web", "order", "无结果", "回退"])
    ]

    private static let ai: [SettingsSearchEntry] = [
        .init(pane: .ai, keywords: ["chat", "llm", "model", "openai", "anthropic", "聊天", "模型"]),
        .init(.aiAI, "Enable AI", keywords: ["chat", "llm"]),
        .init(
            .aiProviders, "Providers",
            keywords: [
                "sign in", "connect", "codex", "claude", "opencode", "api key", "connection",
                "base url", "openai", "anthropic", "ollama"
            ]),
        .init(.aiDefault, "Default model", keywords: ["llm", "gpt", "claude"]),
        .init(.aiDefault, "Reasoning effort", keywords: ["thinking", "effort", "deepseek"]),
        .init(.aiChat, "Web search", keywords: ["browse", "internet"]),
        .init(
            .aiConversations, "Opens to",
            keywords: ["new chat", "last", "summon"]),
        .init(
            .aiConversations, "Start a new conversation after",
            keywords: ["idle", "timeout", "fresh"]),
        .init(
            .aiConversations, "Keep conversations",
            keywords: ["retention", "delete", "history", "privacy"]),
        .init(
            .aiSystemPrompt, "Send a system prompt",
            keywords: ["instructions", "persona"]),
        .init(
            .aiMCPServers, "Enable MCP servers",
            keywords: ["tools", "model context protocol"]),
        .init(
            .aiMCPServers, "Add MCP Server",
            keywords: ["tools", "model context protocol", "stdio"]),
        .init(
            group: .aiCommands, "AI commands",
            keywords: ["shortcut", "launcher", "chat"])
    ]

    private static let quickActions: [SettingsSearchEntry] = [
        .init(
            pane: .quickActions,
            keywords: ["selected text", "rewrite", "translate", "summarize", "划词", "翻译", "总结"]),
        .init(
            .quickActionsQuickActions, "Enable Quick Actions",
            keywords: ["selected text", "accessibility"]),
        .init(
            group: .quickActionsActions, "Actions",
            keywords: ["shortcut", "replace", "preview", "customize"]),
        .init(
            .quickActionsActions, "Add Quick Action",
            keywords: ["new", "custom", "prompt", "instructions", "alias"]),
        .init(
            .quickActionsModel, "Model",
            keywords: ["llm", "ai", "default"]),
        .init(
            .quickActionsTranslate, "Translate to",
            keywords: ["language", "locale"])
    ]

    private static let fileSearch: [SettingsSearchEntry] = [
        .init(
            pane: .fileSearch,
            keywords: ["spotlight", "files", "folders", "find", "文件", "文件夹"]),
        .init(
            .fileSearchFileSearch, "Enable File Search",
            keywords: ["spotlight", "index"]),
        .init(
            group: .fileSearchCommands, "File search commands",
            keywords: ["shortcut", "launcher"]),
        .init(
            group: .fileSearchSearchScopes, "Search Scopes",
            keywords: ["folders", "locations", "home", "add folder"]),
        .init(
            group: .fileSearchIgnorePatterns, "Ignore Patterns",
            keywords: ["exclude", "glob", "node_modules", "skip"])
    ]

    private static let navigation: [SettingsSearchEntry] = [
        .init(
            pane: .navigation,
            keywords: ["window", "switch", "menu bar", "focus", "raise", "窗口", "菜单栏"]),
        .init(
            .navigationNavigation, "Enable navigation",
            keywords: ["window switcher", "menu bar", "accessibility"]),
        .init(
            group: .navigationCommands, "Navigation commands",
            keywords: ["shortcut", "hotkey", "alias", "launcher"]),
        .init(
            .navigationMenuSearch, "Show Apple menu items",
            keywords: ["apple menu", "about this mac", "recent items", "sleep", "logo"]),
        .init(
            .navigationMenuSearch, "Disabled Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy", "menu bar"])
    ]

    private static let delores: [SettingsSearchEntry] = [
        .init(pane: .delores, keywords: ["companion", "pet", "spatial", "snap", "split", "divider", "桌宠", "吸附", "分屏"]),
        .init(.deloresCompanion, "Enable desktop companion", keywords: ["pet", "presence", "companion"]),
        .init(.deloresSpatial, "Enable window snapping", keywords: ["snap", "drag", "window"]),
        .init(.deloresSpatial, "Enable split divider", keywords: ["seam", "resize", "tiled"])
    ]

    private static let windowManagement: [SettingsSearchEntry] = [
        .init(
            pane: .windowManagement,
            keywords: ["tile", "halves", "thirds", "maximize", "snap", "layouts", "arrangement", "平铺", "布局"]),
        .init(
            .windowManagementWindowManagement, "Enable window management",
            keywords: ["tile", "accessibility"]),
        .init(
            .windowManagementOptions, "Cycling",
            keywords: ["repeat", "thirds", "halves", "displays", "monitor", "screens"]),
        .init(
            .windowManagementOptions, "Gap between windows",
            keywords: ["padding", "spacing", "margin", "points"]),
        .init(
            group: .windowManagementOptions, "Window commands",
            keywords: ["shortcut", "left half", "maximize", "center"]),
        .init(
            group: .windowManagementLayoutCommands, "Layout commands",
            keywords: ["shortcut", "launcher", "create layout", "capture"]),
        .init(
            group: .windowManagementLayouts, "Window Layouts",
            keywords: [
                "layout", "arrangement", "workspace", "preset", "restore windows",
                "multi display", "monitor"
            ]),
        .init(
            .windowManagementLayouts, "Show layouts in launcher",
            keywords: ["hide", "visibility", "search"]),
        .init(
            .windowManagementLayouts, "New Layout",
            keywords: ["add", "create", "arrangement", "preset"]),
        .init(
            .windowManagementLayouts, "Create Layout from Current Windows",
            keywords: ["capture", "snapshot", "current", "save arrangement"])
    ]

    private static let clipboard: [SettingsSearchEntry] = [
        .init(
            pane: .clipboard,
            keywords: ["paste", "history", "copy", "pasteboard", "粘贴", "拷贝", "历史"]),
        .init(
            .clipboardClipboard, "Enable Clipboard History",
            keywords: ["disable", "turn off", "monitor", "record", "privacy"]),
        .init(
            group: .clipboardCommands, "Clipboard commands",
            keywords: ["shortcut", "hotkey", "launcher", "paste", "browser"]),
        .init(
            .clipboardHistory, "Keep history for",
            keywords: ["retention", "delete", "privacy", "expire"]),
        .init(
            .clipboardHistory, "Default action",
            keywords: ["enter", "return", "paste", "copy", "primary"]),
        .init(
            group: .clipboardDisabledApplications, "Disabled Applications",
            keywords: ["exclude", "password manager", "ignore", "privacy"]),
        .init(
            .clipboardDisabledApplications, "Clear history",
            keywords: ["delete", "erase", "wipe"])
    ]

    private static let permissions: [SettingsSearchEntry] = [
        .init(
            pane: .permissions,
            keywords: ["privacy", "tcc", "access", "grant", "隐私", "权限"]),
        .init(
            .permissionsAccessibility, "Accessibility",
            keywords: ["paste", "keystrokes", "privacy", "grant"])
    ]

    private static let backup: [SettingsSearchEntry] = [
        .init(
            pane: .backup,
            keywords: ["export", "import", "restore", "migrate", "raycast", "导出", "导入", "备份"]),
        .init(
            .backupExport, "Export Backup",
            keywords: ["save", "tinycast file", "archive"]),
        .init(
            .backupImport, "Backup File",
            keywords: ["restore", "choose", "tinycast file"]),
        .init(
            .backupImportFromRaycast, "Raycast Export",
            keywords: ["migrate", "rayconfig", "passphrase"])
    ]

    private static let about: [SettingsSearchEntry] = [
        .init(
            pane: .about,
            keywords: ["version", "licence", "license", "credits", "版本", "关于"]),
        .init(
            group: .aboutLinks, "Links",
            keywords: ["github", "source", "issues", "website"])
    ]
}
