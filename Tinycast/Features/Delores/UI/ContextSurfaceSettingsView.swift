import Combine
import SwiftUI

/// The Context Surface: the rows the bar offers once something has been selected, and the model
/// behind each one.
///
/// The rows are listed here because the bar's catalogue is not the same as Quick Actions': 解释 and
/// 搜索 have no Quick Action behind them, so they had no row anywhere to be configured from, and
/// the two that do overlap could otherwise only be reached by finding them in the other pane.
struct ContextSurfaceSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(QuickActionSettingsStore.self) private var quickActions
    @State private var editingAction: DeloresContextAction?

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                // The same `quickActionsEnabled` the Quick Actions pane binds: one switch with two
                // entry points, not a second switch. The two features share an Accessibility grant,
                // so splitting the consent would ask for it twice.
                Toggle(isOn: $settings.quickActionsEnabled) {
                    SettingsRowTitle(.contextSurfaceContextBar, "Enable the Context Surface")
                    Text(
                        L10n.string(
                            "The bar appears at the top of the screen for the text you have already selected. It shares its switch, and its Accessibility grant, with Quick Actions."
                        ))
                }
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
                .settingsEnabled(settings.quickActionsEnabled)
            } header: {
                SettingsSectionHeader(.contextSurfaceContextBar)
            } footer: {
                Text(
                    L10n.format(
                        "These are the buttons on the bar that appears when you select text. A row without its own model follows the one chosen in the Quick Actions pane. %@ keeps Apple's translator until you bind a model to it, and falls back to that shared model for a language Apple's translator does not have.",
                        DeloresContextAction.translateTitle)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.contextSurface)
        .sheet(item: $editingAction) { action in
            ContextActionModelSheet(action: action)
                .environment(quickActions)
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
                        "Same as Quick Actions follows the Model section of the Quick Actions pane."))

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
