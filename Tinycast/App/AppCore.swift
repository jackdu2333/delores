import AppKit

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
@Observable
final class AppCore {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let quicklinks = QuicklinkStore()
    let windowLayouts = WindowLayoutStore()
    let clipboardStore = ClipboardStore()
    let clipboardManager: ClipboardManager
    let textInjector: TextInjector
    let hotKeys = HotKeyManager()
    let hyperKeyTap = HyperKeyTap()
    let windowMover = WindowMover()
    let spaceSwitcher = SpaceSwitcher()
    let inputSourceSwitcher = InputSourceSwitcher()
    let settings: AppSettings
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private let iconStyle = IconStyleMonitor()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let aliases = AliasStore()
    let fallbacks = FallbackStore()
    let calcHistory = CalculatorHistoryStore()
    let currencyRates = CurrencyRateStore()
    let runningApps = RunningAppsMonitor()
    let palette = PaletteState()
    let fileSearch = FileSearchSession()
    let menuSearch = MenuSearchSession()
    let windowSwitch = WindowSwitchSession()
    let activationPolicy = ActivationPolicy()
    let uninstall = UninstallSession()
    let notesStore: NotesStore
    let chatHistory: ChatHistoryStore
    let aiChat: AIChatState
    let aiSettings = AISettingsStore(
        isAppleIntelligenceAvailable: { AppleIntelligenceProvider.status().isAvailable })
    let mcpSettings = MCPSettingsStore()
    let mcp = MCPServerManager()
    let quickActionSettings = QuickActionSettingsStore()
    let customQuickActions = CustomQuickActionStore()
    let chatGPTSubscription = ChatGPTSubscriptionManager()
    let installedAI = InstalledAIManager()

    /// Set when a quicklink editor should open with Settings; the pane consumes it.
    var pendingQuicklinkEdit: QuicklinkEditRequest?
    /// Set when a layout editor should open with Settings; the pane consumes it.
    var pendingWindowLayoutEdit: WindowLayoutEditRequest?

    @ObservationIgnored private(set) lazy var quicklinkCoordinator = QuicklinkCoordinator(
        store: quicklinks, settings: settings,
        appIndex: appIndex, injector: textInjector, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        clipboardStore: clipboardStore,
        windowController: windowController,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)

    @ObservationIgnored private(set) lazy var paletteCoordinator = PaletteCoordinator(
        palette: palette, settings: settings, appIndex: appIndex,
        fileSearch: fileSearch, menuSearch: menuSearch, windowSwitch: windowSwitch,
        windowController: windowController)
    /// Its own window and lifecycle: neither coordinator shows or closes the other's surface.
    @ObservationIgnored private(set) lazy var settingsCoordinator = SettingsCoordinator(core: self)
    @ObservationIgnored private(set) lazy var onboardingCoordinator = OnboardingCoordinator(
        core: self)
    @ObservationIgnored private(set) lazy var systemActionCoordinator = SystemActionCoordinator(
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var uninstallCoordinator = UninstallCoordinator(
        session: uninstall, palette: palette, paletteCoordinator: paletteCoordinator,
        appIndex: appIndex, runningApps: runningApps, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases, core: self)
    @ObservationIgnored private(set) lazy var windowCommandCoordinator = WindowCommandCoordinator(
        settings: settings, paletteCoordinator: paletteCoordinator, windowMover: windowMover,
        spaceSwitcher: spaceSwitcher)
    @ObservationIgnored private(set) lazy var windowLayoutCoordinator = WindowLayoutCoordinator(
        store: windowLayouts, settings: settings, appIndex: appIndex, hotKeys: hotKeys,
        favorites: favorites, visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var appleShortcutCoordinator = AppleShortcutCoordinator(
        settings: settings, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, core: self)
    /// Window state, not a preference: it rides `UserDefaults` like the active note's filename.
    private nonisolated static let noteFormattingBarKey = "notesFormattingBarExpanded"
    @ObservationIgnored private(set) lazy var notesCoordinator = NotesCoordinator(
        store: notesStore,
        settings: settings,
        appIndex: appIndex,
        core: self,
        isFormattingBarExpanded: UserDefaults.standard.bool(forKey: Self.noteFormattingBarKey),
        saveFormattingBarExpanded: {
            UserDefaults.standard.set($0, forKey: Self.noteFormattingBarKey)
        })

    @ObservationIgnored private(set) lazy var launcherCoordinator = LauncherCoordinator(
        ranking: launcherRanking, windowController: windowController,
        paletteCoordinator: paletteCoordinator,
        settingsCoordinator: settingsCoordinator,
        systemActionCoordinator: systemActionCoordinator,
        quicklinkCoordinator: quicklinkCoordinator,
        windowCommandCoordinator: windowCommandCoordinator,
        windowLayoutCoordinator: windowLayoutCoordinator,
        fileSearchCoordinator: fileSearchCoordinator,
        menuSearchCoordinator: menuSearchCoordinator,
        windowSwitchCoordinator: windowSwitchCoordinator,
        notesCoordinator: notesCoordinator,
        core: self)
    @ObservationIgnored private(set) lazy var fallbackCoordinator = FallbackCoordinator(
        store: fallbacks, quicklinks: quicklinks, settings: settings, core: self)
    @ObservationIgnored private(set) lazy var clipboardCoordinator = ClipboardCoordinator(
        clipboardStore: clipboardStore, clipboardManager: clipboardManager, settings: settings,
        appIndex: appIndex, palette: palette, windowController: windowController,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var calculatorCoordinator = CalculatorCoordinator(
        calcHistory: calcHistory, paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var fileSearchCoordinator = FileSearchCoordinator(
        settings: settings, appIndex: appIndex, session: fileSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, windowController: windowController, core: self)
    @ObservationIgnored private(set) lazy var menuSearchCoordinator = MenuSearchCoordinator(
        settings: settings, appIndex: appIndex, session: menuSearch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var windowSwitchCoordinator = WindowSwitchCoordinator(
        settings: settings, appIndex: appIndex, session: windowSwitch, palette: palette,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var quickActionCoordinator = QuickActionCoordinator(
        settings: settings, store: quickActionSettings, customActions: customQuickActions,
        injector: textInjector, appIndex: appIndex, hotKeys: hotKeys, favorites: favorites,
        visibility: visibility, ranking: launcherRanking, aliases: aliases,
        paletteCoordinator: paletteCoordinator, core: self)
    @ObservationIgnored private(set) lazy var deloresCoordinator = DeloresCoordinator(
        settings: settings, quickActions: quickActionCoordinator, injector: textInjector,
        aiChat: aiChatCoordinator)
    @ObservationIgnored private(set) lazy var mcpCoordinator = MCPCoordinator(
        settings: settings, store: mcpSettings, manager: mcp, core: self)
    @ObservationIgnored private(set) lazy var aiChatCoordinator = AIChatCoordinator(
        chat: aiChat, settings: settings, appIndex: appIndex, palette: palette,
        paletteCoordinator: paletteCoordinator, settingsCoordinator: settingsCoordinator,
        core: self)

    @ObservationIgnored private lazy var windowController = PaletteWindowController(core: self)
    @ObservationIgnored private lazy var messageHUD = MessageHUDController(settings: settings)
    /// Every confirmation, report and prompt; it also stops a held hotkey stacking them.
    @ObservationIgnored private lazy var dialogs = DialogController(settings: settings)
    private let healthTicker = HealthTicker()

    private init() {
        let launcherRanking = LauncherRankingStore()
        let settings = AppSettings()
        let chatHistory = ChatHistoryStore(directory: AppPaths.applicationSupport())
        self.launcherRanking = launcherRanking
        self.settings = settings
        self.chatHistory = chatHistory
        aiChat = AIChatState(history: chatHistory)
        appIndex = AppIndex(ranking: launcherRanking, aliases: aliases)
        let clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        self.clipboardManager = clipboardManager
        textInjector = TextInjector(clipboardManager: clipboardManager)
        let noteSelectionKey = "notesActiveFileName"
        notesStore = NotesStore(
            repository: NotesRepository(
                applicationSupportDirectory: AppPaths.applicationSupport()),
            loadSelection: {
                UserDefaults.standard.string(forKey: noteSelectionKey).map(NoteID.init(rawValue:))
            },
            saveSelection: { UserDefaults.standard.set($0?.rawValue, forKey: noteSelectionKey) })
    }

    func start() {
        Signposts.interval("AppCore.start") {
            // Shorten AppKit's ~2–3s tooltip delay; registration domain, so a user default wins.
            UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
            NSApp.setActivationPolicy(.accessory)
            applyAppearance()
            observeEffectiveAppearance()

            appIndex.start(settings: settings)
            clipboardCoordinator.applyEnabled()
            fileSearchCoordinator.applyEnabled()
            windowSwitchCoordinator.applyEnabled()
            menuSearchCoordinator.applyEnabled()
            fileSearchCoordinator.applyPolicy()
            notesCoordinator.applyEnabled()
            aiChatCoordinator.applyEnabled()
            mcpCoordinator.applyEnabled()
            customQuickActions.onChange = { [weak self] _ in
                self?.quickActionCoordinator.applyCustomQuickActionsPresence()
            }
            // Before `hotKeys.start` even when off: the prune reads it.
            customQuickActions.load()
            quickActionCoordinator.applyEnabled()
            deloresCoordinator.applyEnabled()
            applyWindowCommandsPresence()
            windowLayouts.onChange = { [weak self] _ in
                self?.windowLayoutCoordinator.applyWindowLayoutsPresence()
            }
            windowLayoutCoordinator.applyWindowLayoutsPresence()
            quicklinks.onChange = { [weak self] _ in
                self?.quicklinkCoordinator.applyQuicklinksPresence()
            }
            // Before `hotKeys.start` even when off: the prune reads it. docs/features/quicklinks.md
            quicklinks.load()
            quicklinkCoordinator.applyQuicklinksPresence()
            appleShortcutCoordinator.applyPresence()
            paletteCoordinator.onLauncherShown = { [weak self] in
                self?.appleShortcutCoordinator.refresh()
            }
            Task { await appIndex.refresh() }
            currencyRates.start()

            hyperKeyTap.healthTicker = healthTicker
            hotKeys.doubleTapMonitor.healthTicker = healthTicker

            hotKeys.onTogglePalette = { [weak self] in self?.paletteCoordinator.togglePalette() }
            hotKeys.onRunCommand = { [weak self] id in self?.launcherCoordinator.runCommand(id) }
            hotKeys.onRunSystemAction = { [weak self] id in
                self?.systemActionCoordinator.runSystemAction(id: id)
            }
            hotKeys.onRunWindowCommand = { [weak self] id in
                self?.windowCommandCoordinator.runWindowCommand(id: id)
            }
            hotKeys.onRunWindowLayout = { [weak self] id in
                self?.windowLayoutCoordinator.runWindowLayout(id: id)
            }
            hotKeys.onOpenQuicklink = { [weak self] id in
                self?.quicklinkCoordinator.openQuicklink(id: id)
            }
            hotKeys.onRunQuickAction = { [weak self] id in
                self?.quickActionCoordinator.run(id: id)
            }
            hotKeys.onRunAppleShortcut = { [weak self] id in
                self?.appleShortcutCoordinator.run(id: id)
            }
            hotKeys.displayName = { [weak self] action in self?.hotKeyDisplayName(for: action) }
            hotKeys.allowsAction = { [weak self] action in
                guard let self, visibility.allowsHotKey(action) else { return false }
                // A disabled feature drops its commands from the launcher; their shortcuts go too.
                guard case .command(let id) = action else { return true }
                return appIndex.isCommandEnabled(id)
            }
            KeyShortcut.displayedHyperChord = { [settings] in
                guard settings.hyperKey != .none else { return nil }
                return KeyShortcut.hyperChord(includesShift: settings.hyperKeyIncludesShift)
            }
            SystemActionRunner.onAsyncFailure = { [weak self] id, failure in
                self?.systemActionCoordinator.presentSystemActionFailure(id: id, failure: failure)
            }
            hotKeys.start(
                quicklinkIDs: Set(quicklinks.quicklinks.map(\.id)),
                windowLayoutIDs: Set(windowLayouts.layouts.map(\.id)),
                quickActionIDs: Set(customQuickActions.actions.map(\.id)))
            // Keeps running while Carbon pauses: the recorder needs its rewritten flags.
            hyperKeyTap.start(settings: settings)

            observeFeatureSwitches()

            // First launch binds no hotkey, so guide once; the marker is written at show-time.
            if !OnboardingState.hasOnboarded {
                OnboardingState.markShown()
                onboardingCoordinator.showOnboarding()
            }
        }
    }

    /// Clicking the Dock icon: raise whichever window is already open, else summon the launcher.
    func handleReopen() {
        if settingsCoordinator.focusExisting() { return }
        if onboardingCoordinator.focusExisting() { return }
        paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
    }

    func handleOpenURL(_ url: URL) {
        _ = url
    }

    /// The store-backed half of the conflict message; `HotKeyManager` names the catalogs itself.
    private func hotKeyDisplayName(for action: HotKeyAction) -> String? {
        switch action {
        case .app(let bundleID):
            return appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
        case .settingsPane(let bundleID):
            return appIndex.apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?
                .name
        case .quicklink(let id):
            return quicklinks.quicklink(id: id)?.name
        case .quickAction(let id):
            return customQuickActions.action(id: id)?.name
        case .windowLayout(let id):
            return windowLayouts.layout(id: id)?.name
        case .appleShortcut(let id):
            return appleShortcutCoordinator.name(of: id)
        case .togglePalette, .command, .systemAction, .windowCommand:
            return nil
        }
    }

    func prepareForTermination() {
        deloresCoordinator.prepareForTermination()
        // Caps Lock first: its remap is the one teardown that outlives the process.
        hyperKeyTap.prepareForTermination()
        windowLayoutCoordinator.prepareForTermination()
        inputSourceSwitcher.endSession()
        textInjector.prepareForTermination()
        aiChat.cancel()
        chatGPTSubscription.stop()
        mcp.stop()
        installedAI.stop()
    }

    func flushNotesForTermination() async {
        await notesCoordinator.prepareForTermination()
    }

    @discardableResult
    func applyInstalledAILifecycle() -> Task<Void, Never> {
        let enabledKinds =
            settings.aiEnabled || settings.quickActionsEnabled
            ? aiSettings.enabledInstalledProviders : []
        var tasks: [Task<Void, Never>] = []
        if enabledKinds.contains(.codex) {
            tasks.append(
                chatGPTSubscription.phase == .idle
                    ? chatGPTSubscription.refresh()
                    : chatGPTSubscription.currentRefreshTask())
        } else {
            chatGPTSubscription.stop()
        }
        tasks.append(installedAI.ensure(enabledKinds: enabledKinds))
        return Task { for task in tasks { await task.value } }
    }

    func aiProvider() throws -> any AIProvider {
        try AIProviderFactory.make(
            settings: aiSettings, subscription: chatGPTSubscription, installedAI: installedAI)
    }

    /// Permissive guardrails: the text transformed is the reader's own, which `.default` refuses.
    func quickActionProvider(for action: QuickAction) throws -> any AIProvider {
        try quickActionProvider(forActionID: action.id)
    }

    /// The same route, resolved by an id rather than by a `QuickAction`.
    ///
    /// The Context Surface runs a catalog of its own, and two of its five actions have no Quick Action
    /// behind them at all — so a caller there holds a stable id and nothing to pass the overload
    /// above. Sharing this resolution is the whole point: a surface that reached for `aiProvider()`
    /// instead would quietly run the reader's own text on the chat's model and under the chat's
    /// guardrails, and neither substitution would announce itself.
    func quickActionProvider(forActionID id: String) throws -> any AIProvider {
        quickActionSettings.repairModel(
            against: aiSettings.connections, fallback: aiSettings.defaultModel)
        guard let selection = quickActionSettings.model(forActionID: id) ?? aiSettings.defaultModel
        else {
            throw AIProviderError.unavailable("Choose a model in Settings \u{2192} Quick Actions.")
        }
        return try AIProviderFactory.make(
            selection: selection, settings: aiSettings, subscription: chatGPTSubscription,
            installedAI: installedAI,
            guardrails: .permissiveContentTransformations)
    }

    // MARK: - Feature switches

    private func observeFeatureSwitches() {
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowManagementShowInLauncher
            }, reproject: { $0.applyWindowCommandsPresence() })
        track(
            {
                _ = $0.windowManagementEnabled
                _ = $0.windowLayoutsShowInLauncher
            }, reproject: { $0.windowLayoutCoordinator.applyWindowLayoutsPresence() })
        track(
            {
                _ = $0.quicklinksEnabled
                _ = $0.quicklinksShowInLauncher
            }, reproject: { $0.quicklinkCoordinator.applyQuicklinksPresence() })
        track(
            { _ = $0.appleShortcutsEnabled },
            reproject: { $0.appleShortcutCoordinator.applyPresence() })
        track(
            { _ = $0.clipboardEnabled }, reproject: { $0.clipboardCoordinator.applyEnabled() })
        track({ _ = $0.fileSearchEnabled }, reproject: { $0.fileSearchCoordinator.applyEnabled() })
        // Two features, one switch: each coordinator gates only its own command and mode.
        track(
            { _ = $0.navigationEnabled },
            reproject: {
                $0.windowSwitchCoordinator.applyEnabled()
                $0.menuSearchCoordinator.applyEnabled()
            })
        track({ _ = $0.notesEnabled }, reproject: { $0.notesCoordinator.applyEnabled() })
        track({ _ = $0.aiEnabled }, reproject: { $0.aiChatCoordinator.applyEnabled() })
        track(
            {
                _ = $0.aiEnabled
                _ = $0.mcpEnabled
            }, reproject: { $0.mcpCoordinator.applyEnabled() })
        track(
            {
                _ = $0.quickActionsEnabled
                _ = $0.deloresCompanionEnabled
                _ = $0.deloresWindowSnappingEnabled
                _ = $0.deloresSplitDividerEnabled
            },
            reproject: {
                $0.quickActionCoordinator.applyEnabled()
                $0.deloresCoordinator.applyEnabled()
            })
        // How large the body is drawn is not a capability being switched on: the Companion stays up,
        // it only stands further in from the edge than it did.
        track(
            { _ = $0.deloresCompanionSize },
            reproject: { $0.deloresCoordinator.applyCompanionSize() })
        track(
            { _ = $0.deloresCompanionKind },
            reproject: { $0.deloresCoordinator.applyCompanionKind() })
        track(
            {
                _ = $0.fileSearchScopes
                _ = $0.fileSearchIgnorePatterns
            }, reproject: { $0.fileSearchCoordinator.applyPolicy() })
        // Not a feature switch, but the same re-projection: a combo has the chord's ⇧ bit baked in.
        track({ _ = $0.hyperKeyIncludesShift }, reproject: { $0.applyHyperChord() })
        track({ _ = $0.appearance }, reproject: { $0.applyAppearance() })
        track({ _ = $0.interfaceSize }, reproject: { $0.windowController.applyInterfaceSize() })
    }

    /// `.system` resolves to `nil`, so AppKit follows macOS with nothing polling.
    private func applyAppearance() {
        NSApp.appearance = settings.appearance.nsAppearance
    }

    /// IconCache is told here, not from `applyAppearance()`, which never fires under `.system`.
    private func observeEffectiveAppearance() {
        // Synchronous on main, so no row can cache a tile under the outgoing appearance's key.
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial]) { app, _ in
            MainActor.assumeIsolated { IconCache.setDarkSurface(app.effectiveAppearance.isDark) }
        }
    }

    /// Fires synchronously on main before the write lands, so the task re-arms and re-reads.
    private func track(
        _ reads: @escaping @Sendable @MainActor (AppSettings) -> Void,
        reproject: @escaping @Sendable @MainActor (AppCore) -> Void
    ) {
        withObservationTracking {
            reads(settings)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track(reads, reproject: reproject)
                reproject(self)
            }
        }
    }

    /// Without a Hyper key the chord means nothing, so a literal ⌃⌥⌘ combo is left as recorded.
    private func applyHyperChord() {
        guard settings.hyperKey != .none else { return }
        hotKeys.retargetHyperBindings(includesShift: settings.hyperKeyIncludesShift)
    }

    private func applyWindowCommandsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowManagementShowInLauncher
        appIndex.setWindowCommandsVisible(visible)
    }

    // MARK: - Dialogs, routed here so `dialogs` stays the single owner

    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {
        await dialogs.notice(title: title, message: message, symbol: symbol, tone: tone)
    }

    /// True while a dialog is up, so a surface behind one can tell it apart from losing focus.
    var isShowingDialog: Bool { dialogs.isPresenting }

    /// The same question for the other surface that may be holding the keyboard on purpose.
    var isHoldingPinnedContext: Bool { deloresCoordinator.isHoldingPinnedContext }

    /// `tone` styles the glyph, `confirmRole` the button; separate on purpose.
    func confirm(
        title: String, message: String?, symbol: String?, confirmTitle: String,
        tone: DialogTone = .danger, confirmRole: DialogAction.Role = .destructive,
        dismissTitle: String = L10n.string("Cancel")
    ) async -> Bool {
        await dialogs.confirm(
            title: title, message: message, symbol: symbol, tone: tone, confirmTitle: confirmTitle,
            confirmRole: confirmRole, dismissTitle: dismissTitle)
    }

    /// A question with more than two answers; the returned index is into `options`.
    func choose(
        title: String, message: String?, symbol: String?, options: [DialogAction],
        defaultIndex: Int, tone: DialogTone = .neutral
    ) async -> Int {
        await dialogs.choose(
            title: title, message: message, symbol: symbol, tone: tone, options: options,
            defaultIndex: defaultIndex)
    }

    /// A failure with one usable second option; `true` when the user takes it.
    func reportFailure(
        title: String, message: String, symbol: String, recovery: String?
    ) async
        -> Bool
    {
        await dialogs.reportFailure(
            title: title, message: message, symbol: symbol, recovery: recovery)
    }

    /// The transient success/info pill, so `messageHUD` stays single-owned alongside `dialogs`.
    func showMessage(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: message, tone: tone)
    }

    /// The same pill for copy the catalog owns. The entry point above is the verbatim one, and it
    /// stays that: a feature reporting a file name, a model's own error or a wording the reader wrote
    /// hands it there, so nothing renames itself behind their back.
    func showChrome(_ message: String, tone: DialogTone = .success) {
        messageHUD.show(message: L10n.text(message), tone: tone)
    }

    /// The same pill with a spinner, for work the reader started and cannot otherwise see running.
    func showProgress(_ message: String) {
        messageHUD.showProgress(message: message)
    }

    func hideProgress() {
        messageHUD.dismiss()
    }

    /// The volume slider, so `dialogs` stays the single owner of every prompt in the app.
    func pickVolume(current: Float32) async -> Float32? {
        await dialogs.pickVolume(current: current)
    }

}
