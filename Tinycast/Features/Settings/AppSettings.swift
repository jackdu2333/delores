import SwiftUI

/// Keys shared between `@AppStorage` sites, so app and Settings bind to the same one.
enum SettingsKey {
    /// The launcher icon's visibility — read by its `MenuBarExtra` and the General toggle.
    static let showInMenuBar = "showInMenuBar"
}

/// Delay before a closed palette pops to root; an unset key reads as `.immediately`.
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// What `AppIndex` scans, in scan order; editing it re-indexes, being observed.
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    /// Ships on, unlike every other feature switch: a launcher is expected to keep history.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardTextSearchEnabled: Bool {
        didSet { defaults.set(clipboardTextSearchEnabled, forKey: Key.clipboardTextSearchEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    /// Bundle IDs never recorded from; ordered, so the Settings list stays stable.
    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    /// What ↵ does on a clipboard entry; ⌘↵ always does the other one.
    var clipboardDefaultAction: ClipboardDefaultAction {
        didSet {
            defaults.set(
                clipboardDefaultAction.rawValue, forKey: Key.clipboardDefaultAction.rawValue)
        }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The physical key remapped to the Hyper chord; `HyperKeyTap` reacts via its observer.
    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey.rawValue) }
    }

    /// Whether Hyper is ⌃⌥⇧⌘ (on) or ⌃⌥⌘ (off).
    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet {
            defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress.rawValue)
        }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone.rawValue) }
    }

    /// Grid density used when the emoji picker opens; in-session zoom remains temporary.
    var emojiGridColumns: EmojiGridColumns {
        didSet { defaults.set(emojiGridColumns.rawValue, forKey: Key.emojiGridColumns.rawValue) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }

    /// Whether Escape walks back through the screens the palette opened, or just closes it.
    var escapeKeyBehavior: EscapeKeyBehavior {
        didSet { defaults.set(escapeKeyBehavior.rawValue, forKey: Key.escapeKeyBehavior.rawValue) }
    }

    /// Follow macOS, or pin Tinycast to one appearance. Applied by `AppCore.applyAppearance()`.
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    /// Scales the palette and its floating siblings only. Read through `InterfaceSize.metrics`.
    var interfaceSize: InterfaceSize {
        didSet { defaults.set(interfaceSize.rawValue, forKey: Key.interfaceSize.rawValue) }
    }

    var paletteTransparency: Int {
        didSet { defaults.set(paletteTransparency, forKey: Key.paletteTransparency.rawValue) }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    var showFavoritesInCompactMode: Bool {
        didSet {
            defaults.set(
                showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode.rawValue)
        }
    }

    /// Summon the palette on the display under the pointer instead of the one holding the menu bar.
    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    /// Lets the panel be dragged by its top edge; off by default, so most launches never grab it.
    var paletteDraggable: Bool {
        didSet { defaults.set(paletteDraggable, forKey: Key.paletteDraggable.rawValue) }
    }

    /// Where a drag left the panel's top-left, per display and relative to it.
    var palettePositions: [String: [Double]] {
        didSet { defaults.set(palettePositions, forKey: Key.palettePosition.rawValue) }
    }

    func palettePosition(on display: String) -> CGPoint? {
        palettePositions[display].flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    func setPalettePosition(_ offset: CGPoint?, on display: String) {
        guard let offset else {
            palettePositions.removeValue(forKey: display)
            return
        }
        palettePositions[display] = [offset.x, offset.y]
    }

    // Feature switches, off out of the box, and off means fully off.
    var fileSearchEnabled: Bool {
        didSet { defaults.set(fileSearchEnabled, forKey: Key.fileSearchEnabled.rawValue) }
    }

    /// Tilde-abbreviated, so a backup taken on one machine still points somewhere on another.
    var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Key.fileSearchScopes.rawValue) }
    }

    /// Only what the user added; the shipped rules are compiled into `FileSearchIgnoreList`.
    var fileSearchIgnorePatterns: [String] {
        didSet {
            defaults.set(fileSearchIgnorePatterns, forKey: Key.fileSearchIgnorePatterns.rawValue)
        }
    }

    var notesEnabled: Bool {
        didSet { defaults.set(notesEnabled, forKey: Key.notesEnabled.rawValue) }
    }

    /// Off by default: connecting a server is consent to run code Tinycast did not write.
    var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: Key.mcpEnabled.rawValue) }
    }
    var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled.rawValue) }
    }

    /// Off out of the box: on means Tinycast may read a selection anywhere and type over it.
    var quickActionsEnabled: Bool {
        didSet { defaults.set(quickActionsEnabled, forKey: Key.quickActionsEnabled.rawValue) }
    }

    var navigationEnabled: Bool {
        didSet { defaults.set(navigationEnabled, forKey: Key.navigationEnabled.rawValue) }
    }

    /// Bundle IDs whose menu bar Search Menu Bar Items refuses to read at all.
    var menuSearchDisabledApps: [String] {
        didSet { defaults.set(menuSearchDisabledApps, forKey: Key.menuSearchDisabledApps.rawValue) }
    }

    /// Off: the Apple menu is the same on every app, so it would only pad every snapshot.
    var menuSearchShowsAppleMenu: Bool {
        didSet {
            defaults.set(menuSearchShowsAppleMenu, forKey: Key.menuSearchShowsAppleMenu.rawValue)
        }
    }

    /// Off means fully off: no launcher entries, and a still-registered shortcut moves nothing.
    var windowManagementEnabled: Bool {
        didSet {
            defaults.set(windowManagementEnabled, forKey: Key.windowManagementEnabled.rawValue)
        }
    }

    var windowManagementShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowManagementShowInLauncher,
                forKey: Key.windowManagementShowInLauncher.rawValue)
        }
    }

    var deloresCompanionEnabled: Bool {
        didSet { defaults.set(deloresCompanionEnabled, forKey: Key.deloresCompanionEnabled.rawValue) }
    }

    /// How large the Companion is drawn. Two steps only — see `DeloresCompanionShell.Size`, which
    /// owns why anything between them would shimmer.
    var deloresCompanionSize: DeloresCompanionShell.Size {
        didSet { defaults.set(deloresCompanionSize.rawValue, forKey: Key.deloresCompanionSize.rawValue) }
    }

    var deloresCompanionKind: DeloresCompanionShell.Kind {
        didSet { defaults.set(deloresCompanionKind.rawValue, forKey: Key.deloresCompanionKind.rawValue) }
    }

    var deloresWindowSnappingEnabled: Bool {
        didSet { defaults.set(deloresWindowSnappingEnabled, forKey: Key.deloresWindowSnappingEnabled.rawValue) }
    }

    var deloresSplitDividerEnabled: Bool {
        didSet { defaults.set(deloresSplitDividerEnabled, forKey: Key.deloresSplitDividerEnabled.rawValue) }
    }

    /// Points between tiled windows and the screen edge; `WindowPlacementEngine` caps it.
    var windowGap: Int {
        didSet { defaults.set(windowGap, forKey: Key.windowGap.rawValue) }
    }

    /// Its own flag: hiding 34 command rows must not also hide the layouts you wrote.
    var windowLayoutsShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowLayoutsShowInLauncher, forKey: Key.windowLayoutsShowInLauncher.rawValue)
        }
    }

    /// What re-triggering a half does: nothing, step its size, or walk it across the displays.
    var windowCycle: WindowCycle {
        didSet { defaults.set(windowCycle.rawValue, forKey: Key.windowCycle.rawValue) }
    }

    /// Off means fully off, down to a still-registered shortcut opening nothing.
    var quicklinksEnabled: Bool {
        didSet { defaults.set(quicklinksEnabled, forKey: Key.quicklinksEnabled.rawValue) }
    }

    var quicklinksShowInLauncher: Bool {
        didSet {
            defaults.set(quicklinksShowInLauncher, forKey: Key.quicklinksShowInLauncher.rawValue)
        }
    }

    /// Off means the Shortcuts tool is never run, down to a bound shortcut running nothing.
    var appleShortcutsEnabled: Bool {
        didSet { defaults.set(appleShortcutsEnabled, forKey: Key.appleShortcutsEnabled.rawValue) }
    }

    /// Ask for a new window rather than a tab; off is the macOS default.
    var quicklinkOpensNewWindow: Bool {
        didSet {
            defaults.set(quicklinkOpensNewWindow, forKey: Key.quicklinkOpensNewWindow.rawValue)
        }
    }

    /// What `{selection}` does when there is no readable selection to pass.
    var quicklinkSelectionFallback: QuicklinkSelectionFallback {
        didSet {
            defaults.set(
                quicklinkSelectionFallback.rawValue,
                forKey: Key.quicklinkSelectionFallback.rawValue)
        }
    }

    var quicklinkConfirmsBeforeDelete: Bool {
        didSet {
            defaults.set(
                quicklinkConfirmsBeforeDelete, forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        }
    }

    /// Whether the support window may reopen itself; off means never ask again.
    var supportRemindersEnabled: Bool {
        didSet { defaults.set(supportRemindersEnabled, forKey: Key.supportReminders.rawValue) }
    }

    init() {
        // The only feature switch that defaults on, so absence has to outrank a stored `false`.
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        // `integer(forKey:)` returns 0 when unset, which no case matches.
        clipboardTextSearchEnabled = defaults.bool(forKey: Key.clipboardTextSearchEnabled.rawValue)
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        // Password managers ship excluded, until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardDefaultAction =
            defaults.string(forKey: Key.clipboardDefaultAction.rawValue)
            .flatMap(ClipboardDefaultAction.init) ?? .paste
        launchAtLogin = LaunchAtLogin.isEnabled
        hyperKey =
            defaults.string(forKey: Key.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init)
            ?? .none
        // Defaults to true, so absence must be distinguished from a stored `false`.
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress.rawValue)
            .flatMap(HyperKeyQuickPress.init)
            ?? .none
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        emojiGridColumns =
            EmojiGridColumns(rawValue: defaults.integer(forKey: Key.emojiGridColumns.rawValue))
            ?? .default
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        escapeKeyBehavior =
            defaults.string(forKey: Key.escapeKeyBehavior.rawValue).flatMap(EscapeKeyBehavior.init)
            ?? .navigateBackOrClose
        appearance =
            defaults.string(forKey: Key.appearance.rawValue).flatMap(AppAppearance.init) ?? .system
        interfaceSize =
            defaults.string(forKey: Key.interfaceSize.rawValue).flatMap(InterfaceSize.init)
            ?? .standard
        paletteTransparency = max(-100, min(100, defaults.integer(forKey: Key.paletteTransparency.rawValue)))
        compactMode = defaults.bool(forKey: Key.compactMode.rawValue)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode.rawValue) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode.rawValue)
        // Unset seeds the defaults; a stored empty array is a deliberately cleared list.
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen.rawValue)
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        paletteDraggable = defaults.bool(forKey: Key.paletteDraggable.rawValue)
        palettePositions =
            defaults.dictionary(forKey: Key.palettePosition.rawValue)
            as? [String: [Double]] ?? [:]
        fileSearchEnabled = defaults.bool(forKey: Key.fileSearchEnabled.rawValue)
        // Unset seeds home; a stored empty array is a cleared list that searches nothing.
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        notesEnabled = defaults.bool(forKey: Key.notesEnabled.rawValue)
        aiEnabled = defaults.bool(forKey: Key.aiEnabled.rawValue)
        mcpEnabled = defaults.bool(forKey: Key.mcpEnabled.rawValue)
        quickActionsEnabled = defaults.bool(forKey: Key.quickActionsEnabled.rawValue)
        navigationEnabled = defaults.bool(forKey: Key.navigationEnabled.rawValue)
        menuSearchDisabledApps =
            defaults.stringArray(forKey: Key.menuSearchDisabledApps.rawValue) ?? []
        menuSearchShowsAppleMenu = defaults.bool(forKey: Key.menuSearchShowsAppleMenu.rawValue)
        windowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled.rawValue)
        deloresCompanionEnabled = defaults.bool(forKey: Key.deloresCompanionEnabled.rawValue)
        deloresCompanionSize = DeloresCompanionShell.Size(
            rawValue: defaults.integer(forKey: Key.deloresCompanionSize.rawValue)) ?? .regular
        deloresCompanionKind = DeloresCompanionShell.Kind(
            rawValue: defaults.string(forKey: Key.deloresCompanionKind.rawValue) ?? "") ?? .duck
        deloresWindowSnappingEnabled = defaults.bool(
            forKey: Key.deloresWindowSnappingEnabled.rawValue)
        deloresSplitDividerEnabled = defaults.bool(
            forKey: Key.deloresSplitDividerEnabled.rawValue)
        windowManagementShowInLauncher =
            defaults.object(forKey: Key.windowManagementShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowManagementShowInLauncher.rawValue)
        // Unset reads as 0, which is the intended default anyway — no gap.
        windowGap = defaults.integer(forKey: Key.windowGap.rawValue)
        windowCycle =
            defaults.string(forKey: Key.windowCycle.rawValue).flatMap(WindowCycle.init) ?? .off
        windowLayoutsShowInLauncher =
            defaults.object(forKey: Key.windowLayoutsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowLayoutsShowInLauncher.rawValue)
        quicklinksEnabled = defaults.bool(forKey: Key.quicklinksEnabled.rawValue)
        quicklinksShowInLauncher =
            defaults.object(forKey: Key.quicklinksShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinksShowInLauncher.rawValue)
        appleShortcutsEnabled = defaults.bool(forKey: Key.appleShortcutsEnabled.rawValue)
        quicklinkOpensNewWindow = defaults.bool(forKey: Key.quicklinkOpensNewWindow.rawValue)
        quicklinkSelectionFallback =
            defaults.string(forKey: Key.quicklinkSelectionFallback.rawValue)
            .flatMap(QuicklinkSelectionFallback.init) ?? .ask
        quicklinkConfirmsBeforeDelete =
            defaults.object(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        supportRemindersEnabled =
            defaults.object(forKey: Key.supportReminders.rawValue) == nil
            || defaults.bool(forKey: Key.supportReminders.rawValue)
    }
}
