import AppKit
import Observation

/// The single funnel for every Quick Action, however it was started.
@MainActor
@Observable
final class QuickActionCoordinator {
    private let settings: AppSettings
    private let store: QuickActionSettingsStore
    private let customActions: CustomQuickActionStore
    private let injector: TextInjector
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private let panels = QuickActionPanelController()
    private unowned let core: AppCore

    private static let launcherCommands = Set(BuiltInQuickAction.allCases.map(CommandID.init))

    /// One at a time: two runs race for one selection, and the second overwrites the first's work.
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        settings: AppSettings, store: QuickActionSettingsStore,
        customActions: CustomQuickActionStore, injector: TextInjector,
        appIndex: AppIndex, hotKeys: HotKeyManager, favorites: FavoritesStore,
        visibility: VisibilityStore, ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.customActions = customActions
        self.injector = injector
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// Launcher rows come and go with the switch; the Carbon bindings stay registered.
    func applyEnabled() {
        appIndex.setCommandsVisible(Self.launcherCommands, settings.quickActionsEnabled)
        applyCustomQuickActionsPresence()
        guard settings.quickActionsEnabled else {
            cancel()
            core.applyInstalledAILifecycle()
            return
        }
        core.applyInstalledAILifecycle()
        store.resolveModel(
            appleIntelligenceAvailable: core.aiSettings.isAppleIntelligenceAvailable(),
            fallback: core.aiSettings.defaultModel)
        loadLanguages()
    }

    /// Enabling is consent: reading a selection and typing over it both need Accessibility.
    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.quickActionsEnabled else { return }
        guard enabled else {
            settings.quickActionsEnabled = false
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable Quick Actions?",
                    message:
                        "Delores needs the Accessibility permission to read the text you have "
                        + "selected in other apps and replace it. Nothing is read until you press "
                        + "a shortcut or complete a selection gesture.",
                    symbol: "wand.and.sparkles", confirmTitle: "Continue", tone: .neutral,
                    confirmRole: .standard)
            else { return }
            settings.quickActionsEnabled = true
            // The one prompt for this feature, raised from the gesture that asked for it.
            Permissions.ensureAccessibility()
        }
    }

    func applyCustomQuickActionsPresence() {
        appIndex.setCustomQuickActions(
            settings.quickActionsEnabled ? customActions.actions : [])
    }

    // MARK: - The reader's own actions

    /// The route is stored only once the record is on disk, so a refused save leaves neither behind.
    func addCustomQuickAction(
        _ draft: CustomQuickAction, model: AIModelSelection?
    ) throws(CustomQuickActionError) {
        let action = try customActions.add(draft)
        store.setModelOverride(model, for: .custom(action))
    }

    func updateCustomQuickAction(
        _ draft: CustomQuickAction, model: AIModelSelection?
    ) throws(CustomQuickActionError) {
        try customActions.update(draft)
        store.setModelOverride(model, for: .custom(draft))
    }

    func setPreviewsResult(_ previews: Bool, id: UUID) {
        do {
            try customActions.setPreviewsResult(previews, id: id)
        } catch {
            report(error)
        }
    }

    func deleteCustomQuickAction(id: UUID) async {
        guard let action = customActions.action(id: id) else { return }
        guard
            await core.confirm(
                title: "Delete “\(action.name)”?",
                message: "Its instructions, shortcut and learned ranking go with it.",
                symbol: action.symbol, confirmTitle: "Delete")
        else { return }
        // Unwound only once the row is gone, so a kept record never loses its shortcut.
        do {
            guard let removed = try customActions.remove(id: id) else { return }
            removeCustomQuickActionReferences(removed)
        } catch {
            report(error)
        }
    }

    private func report(_ error: CustomQuickActionError) {
        Task {
            await core.showNotice(
                title: "Couldn’t Save the Change", message: error.localizedDescription,
                symbol: CustomQuickAction.sfSymbol, tone: .danger)
        }
    }

    private func removeCustomQuickActionReferences(_ action: CustomQuickAction) {
        let hotKeyAction = HotKeyAction.quickAction(id: action.id)
        if hotKeys.recordingAction == hotKeyAction { hotKeys.recordingAction = nil }
        hotKeys.setBinding(nil, for: hotKeyAction)
        store.setModelOverride(nil, for: .custom(action))
        favorites.remove(keys: [action.entryID])
        visibility.removeItemKeys([action.entryID])
        aliases.removeKeys([action.entryID])
        ranking.reset(itemKey: action.entryID)
    }

    func run(id: UUID) {
        guard let action = customActions.action(id: id) else { return }
        run(.custom(action))
    }

    @discardableResult
    func run(_ action: QuickAction) -> QuickActionStartResult {
        let admission = QuickActionStartResult.admission(
            enabled: settings.quickActionsEnabled, isRunning: running != nil)
        guard admission == .started else { return admission }
        let target = paletteCoordinator.targetApp
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        start { [weak self] in await self?.begin(action, target: target) }
        return .started
    }

    func cancel() {
        generation += 1
        running?.cancel()
        running = nil
        panels.dismiss()
    }

    /// The generation stops a superseded task from clearing the newer handle as it finishes.
    private func start(_ work: @escaping @MainActor () async -> Void) {
        generation += 1
        let mine = generation
        running?.cancel()
        running = Task { [weak self] in
            await work()
            guard let self, mine == self.generation else { return }
            self.running = nil
        }
    }

    private func begin(_ action: QuickAction, target: NSRunningApplication?) async {
        let selection: String
        do {
            selection = try await QuickActionRunner.selection(in: target, using: injector)
        } catch let failure as QuickActionFailure {
            reportRefusal(failure)
            return
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        let state = QuickActionPanelState(
            action: action, original: selection, targetLanguage: targetLanguage)
        let previews = store.settings.previewsResult(action)
        if previews { present(state, target: target) }
        await perform(state, target: target, previewing: previews)
    }

    /// A missing permission cannot be fixed from a pill that fades, so it earns a dialog instead.
    private func reportRefusal(_ failure: QuickActionFailure) {
        guard failure.opensAccessibilitySettings else {
            core.showMessage(failure.localizedDescription, tone: .danger)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.reportFailure(
                    title: "Quick Actions can't read your selection",
                    message:
                        "Delores needs the Accessibility permission to read the text you have "
                        + "selected and replace it. If Delores is already listed, switch it off "
                        + "and on again — a rebuilt app keeps a stale entry.",
                    symbol: "wand.and.sparkles", recovery: "Open System Settings")
            else { return }
            Permissions.openAccessibilitySettings()
        }
    }

    private func perform(
        _ state: QuickActionPanelState, target: NSRunningApplication?, previewing: Bool
    ) async {
        do {
            let text = try await produce(state, previewing: previewing)
            guard !Task.isCancelled else { return }
            state.finish(text)
            if previewing { return }
            deliver(text, to: target, action: state.action)
        } catch is CancellationError {
            return
        } catch let error as TextTranslator.Failure where error.needsDownload {
            // A HUD cannot say where the download lives, so this has to become a panel.
            if !previewing { present(state, target: target) }
            state.requireLanguageDownload()
        } catch {
            report(error, state: state, previewing: previewing)
        }
    }

    /// Without a panel there is nothing on screen saying the model is working, so the pill says it.
    private func produce(
        _ state: QuickActionPanelState, previewing: Bool
    ) async throws -> String {
        guard !previewing else { return try await generate(state, streaming: true) }
        core.showProgress(state.action.progressTitle)
        defer { core.hideProgress() }
        return try await generate(state, streaming: false)
    }

    private func generate(
        _ state: QuickActionPanelState, streaming: Bool
    ) async throws -> String {
        if state.action.usesTranslationFramework,
            await translateRoute(for: state.original, to: state.targetLanguage) == .translationFramework
        {
            return try await TextTranslator.translate(state.original, to: state.targetLanguage)
        }
        let provider = try core.quickActionProvider(for: state.action)
        return try await QuickActionRunner.run(
            state.action, selection: state.original, using: provider,
            translatingInto: TextTranslator.displayName(of: state.targetLanguage),
            instructionOverride: store.settings.instructionOverride(for: state.action),
            onDelta: { delta in
                guard streaming else { return }
                state.append(delta)
            })
    }

    /// A replacement that never lands would otherwise lose the reply, so the clipboard keeps it.
    private func deliver(_ text: String, to target: NSRunningApplication?, action: QuickAction) {
        injector.replaceSelection(
            with: text, in: target,
            onDelivered: { [weak self] in self?.core.showMessage("\(action.title) applied") },
            onFailed: { [weak self] in
                Paster.copyPlainText(text)
                self?.core.showMessage(
                    "\(action.title) couldn't replace the selection — copied instead",
                    tone: .danger)
            })
    }

    /// A failure the reader cannot see is a hotkey that silently did nothing.
    private func report(_ error: Error, state: QuickActionPanelState, previewing: Bool) {
        guard previewing else {
            core.showMessage(error.localizedDescription, tone: .danger)
            return
        }
        state.fail(error.localizedDescription)
    }

    private func present(_ state: QuickActionPanelState, target: NSRunningApplication?) {
        panels.present(
            state,
            metrics: settings.interfaceSize.metrics,
            languages: offeredLanguages,
            onRetranslate: { [weak self] language in
                state.targetLanguage = language
                self?.rerun(state, target: target)
            },
            onReplace: { [weak self] text in
                self?.deliver(text, to: target, action: state.action)
            })
    }

    private func rerun(_ state: QuickActionPanelState, target: NSRunningApplication?) {
        state.restart()
        start { [weak self] in await self?.perform(state, target: target, previewing: true) }
    }

    /// Shared with a surface that hands its action to the chat, so both translate into one language.
    var targetLanguage: Locale.Language {
        let stored = store.settings.targetLanguage
        guard !stored.isEmpty else { return Locale.current.language }
        return Locale.Language(identifier: stored)
    }

    /// Which backend answers the one id both catalogues call `translate`, asked before anything runs.
    ///
    /// One decision for both surfaces, because they share the id: the reader's own binding if they made
    /// one, and Apple's translator otherwise whenever it has the pair. A pair it merely supports still
    /// counts, so a language nobody downloaded waits to be downloaded rather than becoming an AI bill.
    ///
    /// The target is an argument rather than `targetLanguage`, because a panel the reader already has
    /// open can be retranslated into a language the setting does not name, and the backend has to be
    /// the one that can serve the language actually asked for.
    func translateRoute(
        for selection: String, to target: Locale.Language
    ) async -> DeloresTranslationRoute {
        // The same repair the provider resolver runs, because the binding that decides this route has
        // to be the one that will actually answer: a connection deleted in AI Settings must not read as
        // a binding here and then be discarded one call later, or the press goes to a provider the
        // reader had already let go of instead of to Apple's translator.
        store.repairModel(
            against: core.aiSettings.connections, fallback: core.aiSettings.defaultModel)
        // A bound model answers without asking Apple anything: the reader's choice settles it, and
        // neither the recognizer nor the framework round trip has anything to add to that.
        guard store.modelOverride(forActionID: BuiltInQuickAction.translate.id) == nil else {
            return .languageModel
        }
        return DeloresActionDefinition.translationRoute(
            hasModelBinding: false,
            availability: await TextTranslator.availability(of: selection, to: target))
    }

    /// The provider this action runs on: the model the reader bound to it, and the permissive
    /// guardrails a transformation of the reader's own text needs. Shared for the same reason
    /// `targetLanguage` is — a surface that hands the action to the chat must not let the chat
    /// answer as the chat, or the binding and the guardrails are both silently lost.
    func provider(for action: QuickAction) throws -> any AIProvider {
        try core.quickActionProvider(for: action)
    }

    /// The same route for an action this catalog does not own: the Context Surface carries its own
    /// five, and reaches its provider through here rather than pretending to be a Quick Action. The
    /// binding and the guardrails are the reason it must come through here at all.
    func provider(forActionID id: String) throws -> any AIProvider {
        try core.quickActionProvider(forActionID: id)
    }

    /// The instructions the reader replaced the built-in prompt with, if they did. Nil means the
    /// built-in prompt stands, which is also why a custom action never reports one.
    func instructionOverride(for action: QuickAction) -> String? {
        store.settings.instructionOverride(for: action)
    }

    /// The reader's wording for an action the Context Surface keeps under an id of its own. The bar
    /// and this catalogue overlap without agreeing on every row, so only an id can ask.
    func instructionOverride(forActionID id: String) -> String? {
        store.settings.instructionOverride(forActionID: id)
    }

    /// The rows the reader wrote in Settings, in the order Settings keeps them.
    ///
    /// The Context Surface reads this list and nothing else: it copies the rows out rather than
    /// taking the store, so neither catalogue can be rewritten by the surface that borrowed it.
    var customQuickActionRows: [CustomQuickAction] { customActions.actions }

    /// Observed, not ignored: it arrives after the pane has painted, and the picker has to notice.
    private(set) var offeredLanguages: [Locale.Language] = []
    @ObservationIgnored private var languageLoad: Task<Void, Never>?

    func loadLanguages() {
        guard offeredLanguages.isEmpty, languageLoad == nil else { return }
        languageLoad = Task { [weak self] in
            let languages = await TextTranslator.supportedLanguages()
            self?.offeredLanguages = languages
        }
    }
}

extension TextTranslator.Failure {
    var needsDownload: Bool {
        if case .notInstalled = self { return true }
        return false
    }
}
