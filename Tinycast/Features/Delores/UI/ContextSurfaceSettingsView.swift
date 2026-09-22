import Combine
import SwiftUI

/// The Context Surface: its switch and the action rows that appear for a selection.
///
/// Shared AI, model, action-routing and chat settings live in the Core capabilities pane. Keeping
/// them there prevents this Surface from becoming a second configuration surface for the core.
///
/// The built-in Quick Actions have no list of their own here: the toolbar's rows are the one place
/// a selection's actions are listed and given a model. The switch lives in this file because it
/// writes through `QuickActionCoordinator.setEnabled` — the consent and the Accessibility grant
/// are that call's, and a direct binding would skip both.
struct ContextSurfaceSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(QuickActionSettingsStore.self) private var quickActions
    @State private var editingAction: DeloresContextAction?
    @Environment(CustomQuickActionStore.self) private var customActions
    @State private var customEditing: CustomQuickActionEditRequest?
    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            switchSection
            contextBarSection
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.contextSurface)
        .onReceive(refreshTimer) { _ in isTrusted = Permissions.isAccessibilityTrusted() }
        .sheet(item: $editingAction) { action in
            ContextActionModelSheet(action: action)
                .environment(quickActions)
        }
        .sheet(item: $customEditing) { request in
            CustomQuickActionEditorSheet(
                request: request,
                model: request.action.flatMap { quickActions.modelOverride(for: .custom($0)) })
        }
    }

    /// The Surface's own switch, and the grant it cannot work without.
    ///
    /// It writes through `QuickActionCoordinator.setEnabled`, which asks for consent and for the
    /// Accessibility grant; binding `quickActionsEnabled` directly would skip both.
    private var switchSection: some View {
        Section {
            Toggle(isOn: enabledBinding) {
                SettingsRowTitle(.contextSurfaceEnable, "Enable the Context Surface")
                Text(
                    L10n.string(
                        "Act on the text you have selected in any app. Delores reads a selection only after a shortcut or a completed selection gesture, then shows the toolbar at the top of the screen."
                    ))
            }
            if settings.quickActionsEnabled, !isTrusted {
                // Every shortcut fails without it; better said here than found one press later.
                SettingsRow(
                    title: L10n.string("Accessibility permission required"),
                    subtitle: "Delores can't read your selection until it is granted."
                ) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.destructive)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    Button(L10n.string("Open System Settings")) {
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.contextSurfaceEnable)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.quickActionsEnabled },
            set: { core.quickActionCoordinator.setEnabled($0) })
    }

    /// The rows the bar offers, each with the model that answers it.
    ///
    /// The rows are listed here because the bar's catalogue is not the same as Quick Actions': 解释
    /// and 搜索 have no Quick Action behind them, so they had no row anywhere to be configured from,
    /// and the two that do overlap could otherwise only be reached by finding them in another pane.
    @ViewBuilder private var contextBarSection: some View {
        Section {
            Group {
                ForEach(DeloresContextAction.catalog) { action in
                    SettingsRow(title: action.displayTitle, subtitle: answerRoute(action)) {
                        SymbolImage(name: action.symbol, size: Theme.Size.settingsRowIcon)
                            .frame(width: Theme.Size.settingsRowIcon)
                    } trailing: {
                        if action.needsModel {
                            Button {
                                editingAction = action
                            } label: {
                                SymbolImage(name: "pencil", size: Theme.Size.quickActionHeaderIcon)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.format("Choose the model for %@", action.displayTitle))
                            .accessibilityLabel(
                                L10n.format("Choose the model for %@", action.displayTitle))
                        }
                    }
                }
                ForEach(customActions.actions, content: customRow)
                Button {
                    customEditing = CustomQuickActionEditRequest(action: nil)
                } label: {
                    SettingsRowTitle(.contextSurfaceContextBar, "Add action")
                }
            }
            .settingsEnabled(settings.quickActionsEnabled)
        } header: {
            SettingsSectionHeader(.contextSurfaceContextBar)
        } footer: {
            Text(
                L10n.format(
                    "These are the buttons on the island that appears when you select text. Your own actions join Translate, Explain, Summarize and Search. A row without its own model follows the one chosen under Actions above. %@ keeps Apple's translator until you bind a model to it, and falls back to that shared model for a language Apple's translator does not have.",
                    DeloresContextAction.translateTitle)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func customRow(_ custom: CustomQuickAction) -> some View {
        let action = DeloresContextAction(custom)
        return SettingsRow(title: custom.name, subtitle: answerRoute(action)) {
            SymbolImage(name: custom.symbol, size: Theme.Size.settingsRowIcon)
                .frame(width: Theme.Size.settingsRowIcon)
        } trailing: {
            Button {
                customEditing = CustomQuickActionEditRequest(action: custom)
            } label: {
                SymbolImage(name: "pencil", size: Theme.Size.quickActionHeaderIcon)
            }
            .buttonStyle(.plain)
            .help(L10n.format("Edit %@", custom.name))
            .accessibilityLabel(L10n.format("Edit %@", custom.name))
        }
    }

    /// Which model answers this row, said in the row so the answer does not require opening anything.
    private func answerRoute(_ action: DeloresContextAction) -> String {
        if action.kind == .search {
            return action.searchTemplate
        }
        if let bound = quickActions.modelOverride(forActionID: action.id) {
            guard let effort = bound.effort else { return bound.model }
            return "\(bound.model) · \(effort)"
        }
        // The row says what will answer it, and for 翻译 that is not the pane's model.
        return action.definition.backend == .languageModel
            ? L10n.string("Same as Quick Actions") : L10n.string("Apple's translator")
    }
}

/// The model behind one bar row. Its own sheet rather than a control in the row, matching how a
/// Quick Action's model is edited — and so the row can say which model it is on without a picker
/// taking the width it needs to say it in.
private struct ContextActionModelSheet: View {
    let action: DeloresContextAction
    @Environment(QuickActionSettingsStore.self) private var quickActions
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AIModelSelection?

    init(action: DeloresContextAction) {
        self.action = action
        _selection = State(initialValue: nil)
    }

    /// 翻译 has a backend of its own, so "no route" does not mean the Quick Actions model for it.
    private var keepsAppleTranslator: Bool { action.definition.backend == .translationFramework }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(L10n.format("Model for %@", action.displayTitle))
                .font(.title2.weight(.bold))
            Text(
                L10n.format(
                    "Used every time %@ runs from the bar on the text you have selected.",
                    action.displayTitle)
            )
            .foregroundStyle(.secondary)

            QuickActionModelPicker(
                selection: $selection,
                inheritedTitle: keepsAppleTranslator
                    ? L10n.string("Apple's translator") : L10n.string("Same as Quick Actions"),
                inheritedHelp: keepsAppleTranslator
                    ? L10n.string(
                        "With nothing bound this row keeps Apple's translator; a pair it does not have falls back to the shared model."
                    )
                    : L10n.string(
                        "Same as Quick Actions follows the Model section above."))

            HStack {
                Spacer()
                Button(L10n.string("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.string("Save")) {
                    quickActions.setModelOverride(selection, forActionID: action.id)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.editorSheetWidth)
        .onAppear { selection = quickActions.modelOverride(forActionID: action.id) }
    }
}
