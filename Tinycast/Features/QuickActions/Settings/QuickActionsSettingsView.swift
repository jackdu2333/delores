import Combine
import SwiftUI

/// The model that answers action rows, and the language it translates to; composed into the Core
/// capabilities pane that owns shared routing.
///
/// It no longer lists the built-in Quick Actions, and no longer carries the switch: the toolbar's
/// own rows are the one list of what a selection can do, and the switch belongs to the pane, which
/// writes it through `QuickActionCoordinator.setEnabled`.
struct QuickActionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var appSettings
    @Environment(QuickActionSettingsStore.self) private var store
    @Environment(AISettingsStore.self) private var aiSettings

    var body: some View {
        // A `Group`, not a `Form`: the Core capabilities pane owns the one `Form` these compose into.
        Group {
            modelSection
            languageSection
        }
        .settingsEnabled(appSettings.quickActionsEnabled)
        .onAppear {
            core.quickActionCoordinator.loadLanguages()
            store.repairModel(against: aiSettings.connections, fallback: aiSettings.defaultModel)
            store.resolveModel(
                appleIntelligenceAvailable: aiSettings.isAppleIntelligenceAvailable(),
                fallback: aiSettings.defaultModel)
            core.applyInstalledAILifecycle()
        }
        .onChange(of: appSettings.aiEnabled) { repairInstalledModel() }
        .onChange(of: aiSettings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            repairInstalledModel()
        }
        .onChange(of: core.chatGPTSubscription.models) { repairInstalledModel() }
        .onChange(of: core.chatGPTSubscription.phase) { repairInstalledModel() }
        .onChange(of: core.installedAI.statuses) { repairInstalledModel() }
    }

    private var modelSection: some View {
        Section {
            AIModelSelectionRows(
                selection: store.model,
                select: store.select,
                modelLabel: {
                    SettingsRowTitle(.quickActionsModel, "Model")
                    Text(
                    L10n.format(
                        "Used by every action without a model of its own, %@ included for a pair Apple's translator cannot do.",
                        DeloresContextAction.translateTitle))
                },
                effortLabel: {
                    SettingsRowTitle(.quickActionsModel, "Reasoning effort")
                    Text(L10n.string("Applied when the selected model supports reasoning effort."))
                }
            )
        } header: {
            SettingsSectionHeader(.quickActionsModel)
        } footer: {
            Text(
                    L10n.format(
                        "Separate from chat's model on purpose: a shortcut you press all day should not bill an API every time. Apple Intelligence runs on this Mac for nothing. It answers the selection toolbar's rows too, except the ones given a model of their own — those are set beside their rows, under Selection Toolbar below. %@ keeps Apple's translator unless it is given one, or unless the pair is one Apple cannot do.",
                        DeloresContextAction.translateTitle))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: languageBinding) {
                Text(L10n.string("Same as this Mac")).tag("")
                ForEach(core.quickActionCoordinator.offeredLanguages, id: \.minimalIdentifier) {
                    Text(TextTranslator.displayName(of: $0)).tag($0.minimalIdentifier)
                }
            } label: {
                SettingsRowTitle(.quickActionsTranslate, "Translate to")
                Text(L10n.string("The panel can still translate into another language once it is open."))
            }
        } header: {
            SettingsSectionHeader(.quickActionsTranslate)
        } footer: {
            Text(
                    L10n.format(
                        "Apple's own translator runs on this Mac, so it costs nothing and reaches no provider; a language downloads the first time you use it. Binding a model to %@ replaces the translator, and that route bills like any other.",
                        DeloresContextAction.translateTitle))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { store.settings.targetLanguage },
            set: { store.settings.targetLanguage = $0 })
    }

    private var modelChoices: [AIModelOption] {
        AIModelOption.availableGroups(
            settings: aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI
        )
        .flatMap(\.options)
    }

    private func repairInstalledModel() {
        // Catalog rows name a route without an effort; a repaired selection must carry the default.
        let options = modelChoices.map {
            AIModelOption.withDefaultEffort(
                $0.selection, settings: aiSettings, subscription: core.chatGPTSubscription,
                installedAI: core.installedAI)
        }
        var unavailable = Set<AIModelSource>()
        if !aiSettings.enabledInstalledProviders.contains(.codex)
            || core.chatGPTSubscription.phase == .signedOut
            || core.chatGPTSubscription.phase.isUnavailable
        {
            unavailable.insert(.codex)
        }
        for kind in [InstalledAIKind.claude, .openCode] {
            let phase = core.installedAI.status(for: kind).phase
            guard
                !aiSettings.enabledInstalledProviders.contains(kind)
                    || phase == .signInRequired || phase == .notInstalled
            else { continue }
            unavailable.insert(kind.source)
        }
        store.repairInstalledModel(
            available: options, unavailableSources: unavailable,
            fallback: aiSettings.defaultModel)
    }
}
