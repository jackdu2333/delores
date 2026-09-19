import Foundation

/// What `SettingsBackup.SettingsData` carries, written out so a new setting has to be considered.
enum SettingsBackupCoverage {
    /// Each `SettingsData` field paired with the `AppSettings` key it mirrors.
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardEnabled": .clipboardEnabled,
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDefaultAction": .clipboardDefaultAction,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "popToRootSeconds": .popToRootTimeout,
        "escapeKeyBehavior": .escapeKeyBehavior,
        "appearance": .appearance,
        "interfaceSize": .interfaceSize,
        "paletteTransparency": .paletteTransparency,
        "compactMode": .compactMode,
        "showFavoritesInCompactMode": .showFavoritesInCompactMode,
        "searchScopes": .searchScopes,
        "openOnCursorScreen": .openOnCursorScreen,
        "paletteDraggable": .paletteDraggable,
        "fileSearchEnabled": .fileSearchEnabled,
        "fileSearchScopes": .fileSearchScopes,
        "fileSearchIgnorePatterns": .fileSearchIgnorePatterns,
        "notesEnabled": .notesEnabled,
        "notesRendersMarkdown": .notesRendersMarkdown,
        "notesShowsFormattingBar": .notesShowsFormattingBar,
        "navigationEnabled": .navigationEnabled,
        "menuSearchDisabledApps": .menuSearchDisabledApps,
        "menuSearchShowsAppleMenu": .menuSearchShowsAppleMenu,
        "windowManagementEnabled": .windowManagementEnabled,
        "windowManagementShowInLauncher": .windowManagementShowInLauncher,
        "windowGap": .windowGap,
        "windowCycle": .windowCycle,
        "windowLayoutsShowInLauncher": .windowLayoutsShowInLauncher,
        "quicklinksEnabled": .quicklinksEnabled,
        "quicklinksShowInLauncher": .quicklinksShowInLauncher,
        "quicklinkOpensNewWindow": .quicklinkOpensNewWindow,
        "quicklinkSelectionFallback": .quicklinkSelectionFallback,
        "quicklinkConfirmsBeforeDelete": .quicklinkConfirmsBeforeDelete,
        "appleShortcutsEnabled": .appleShortcutsEnabled,
        "companionSize": .deloresCompanionSize,
        "companionKind": .deloresCompanionKind
    ]

    /// The `SettingsData` fields no `AppSettings` key stands behind, and what they read instead.
    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults.",
        "showInMenuBar": "SettingsKey.showInMenuBar — shared with MenuBarExtra, not owned here."
    ]

    /// Keys kept out of a backup on purpose, each with the reason it has to stay out.
    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.palettePosition.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.autoSwitchInputSource.rawValue:
            "Names a keyboard input source installed on this Mac; another Mac may not have it.",
        AppSettingsKey.aiEnabled.rawValue:
            "No other AI setting travels in a backup, so an import would arm a feature it cannot "
            + "configure.",
        AppSettingsKey.aiInstalledProviders.rawValue:
            "Installed commands and their accounts belong to this Mac; an import must not enable "
            + "their discovery on another one.",
        AppSettingsKey.aiConnections.rawValue:
            "AI connection metadata stays on the Mac with the Keychain credentials it describes.",
        AppSettingsKey.aiDefaultModel.rawValue:
            "The default model names an external AI destination; importing must not choose one.",
        AppSettingsKey.aiWebSearch.rawValue:
            "Whether prompts may reach a search engine is a choice each Mac makes for itself.",
        AppSettingsKey.aiSystemPrompt.rawValue:
            "Standing instructions to a model are the one AI setting that changes every answer; an "
            + "import must not carry them onto another Mac unseen.",
        AppSettingsKey.aiSystemPromptEnabled.rawValue:
            "Governs whether a turn carries standing instructions at all, so it changes every answer "
            + "the same way the prompt it gates does.",
        AppSettingsKey.aiRetention.rawValue:
            "How long conversations survive is a decision about the chats on this Mac, and an import "
            + "must never arrive carrying an instruction to delete them.",
        AppSettingsKey.aiOpensTo.rawValue:
            "Whether chat reopens on an existing conversation depends on the history this Mac holds, "
            + "which no other Mac has.",
        AppSettingsKey.aiNewChatAfter.rawValue:
            "Paces the same decision as the setting it accompanies, against conversations that stay "
            + "on the Mac that had them.",
        AppSettingsKey.mcpEnabled.rawValue:
            "Doubles as consent to run third-party MCP servers, one of which is a local process; a "
            + "flag that grants a capability is never carried by a backup.",
        AppSettingsKey.mcpServers.rawValue:
            "An MCP server is a source of executable code and a destination for chat context, and "
            + "it is meaningless without the machine-local Keychain secrets it describes.",
        AppSettingsKey.quickActionsEnabled.rawValue:
            "Grants keystroke delivery into other apps through the Accessibility permission, and a "
            + "flag that grants a capability is never carried by a backup.",
        AppSettingsKey.quickActionModel.rawValue:
            "Names an external AI destination for text taken from whatever app is frontmost; an "
            + "import must not choose one.",
        AppSettingsKey.quickActionModelOverrides.rawValue:
            "Sends one action's text to its own AI destination, some keyed by actions that exist only "
            + "on the Mac that made them.",
        AppSettingsKey.quickActionPreviews.rawValue:
            "Says which actions may rewrite a document without showing the result first, which is a "
            + "decision each Mac makes about its own text.",
        AppSettingsKey.quickActionInstructions.rawValue:
            "Custom model instructions change transformed results and must not move unseen.",
        AppSettingsKey.quickActionLanguage.rawValue:
            "Follows the language the person at this Mac reads, not the one who wrote the backup.",
        AppSettingsKey.deloresCompanionEnabled.rawValue:
            "Starts a pet that watches the pointer and every window move, so it is consent to a "
            + "resident monitor and never something an import may switch on.",
        AppSettingsKey.deloresWindowSnappingEnabled.rawValue:
            "Watches window drags across this Mac's displays; a flag that grants a capability is "
            + "never carried by a backup.",
        AppSettingsKey.deloresSplitDividerEnabled.rawValue:
            "Draws a snap guide over whatever else is on screen, which no backup should decide for "
            + "someone else's displays."
    ]
}
