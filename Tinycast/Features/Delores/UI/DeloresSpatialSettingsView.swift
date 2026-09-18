import Combine
import SwiftUI

/// Everything Delores itself owns: the Context Bar's rows, the Companion, and the two window
/// capabilities. The file is named for the third because that is what it held first.
struct DeloresSpatialSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(QuickActionSettingsStore.self) private var quickActions

    /// Polled like the Permissions pane: the grant lands in System Settings, which sends nothing.
    @State private var isTrusted = Permissions.isAccessibilityTrusted()
    @State private var editingAction: DeloresContextAction?
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            contextBarSection
            companionSection
            windowSection
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.delores)
        .onReceive(refreshTimer) { _ in isTrusted = Permissions.isAccessibilityTrusted() }
        .sheet(item: $editingAction) { action in
            ContextActionModelSheet(action: action)
                .environment(quickActions)
        }
    }

    /// The rows the bar offers, each with the model that answers it.
    ///
    /// This section exists because the bar's catalogue is not the same as Quick Actions': 解释 and 搜索
    /// have no Quick Action behind them, so they had no row anywhere to be configured from, and the
    /// two that do overlap could only be reached by finding them in the other pane.
    @ViewBuilder private var contextBarSection: some View {
        Section {
            if !settings.quickActionsEnabled {
                SettingsRow(
                    title: "The Context Bar is off",
                    subtitle: "Turn on Enable Quick Actions to show it when you select text."
                ) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Size.settingsRowIcon)
                }
            }
            ForEach(DeloresContextAction.catalog) { action in
                SettingsRow(title: action.title, subtitle: answerRoute(action)) {
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
                        .help("Choose the model for \(action.title)")
                        .accessibilityLabel("Choose the model for \(action.title)")
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.deloresContextBar)
        } footer: {
            Text(
                "These are the buttons on the bar that appears when you select text. A row without "
                    + "its own model follows the one chosen in the Quick Actions pane. 翻译 keeps "
                    + "Apple's translator until you bind a model to it, and falls back to that "
                    "shared model for a language Apple's translator does not have."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
        return action.definition.backend == .languageModel ? "Same as Quick Actions" : "Apple's translator"
    }

    @ViewBuilder private var companionSection: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.deloresCompanionEnabled) {
                SettingsRowTitle(.deloresCompanion, "Enable desktop companion")
                Text(
                    "The companion that is simply there: it wanders the edge of the display, and "
                        + "reopens your last selection when you double-click it. "
                )
            }
            Picker(selection: $settings.deloresCompanionSize) {
                Text("Regular").tag(DeloresCompanionShell.Size.regular)
                Text("Large").tag(DeloresCompanionShell.Size.large)
            } label: {
                SettingsRowTitle(.deloresCompanion, "Size")
                // Why there are two and no slider: the sprite is authored at a fixed size and drawn
                // at a whole number of its own pixels. Anything between the two would put a
                // fractional number of screen pixels under one drawn pixel, which is what shimmers.
                Text("Two sizes only, because it is drawn at a whole number of its own pixels.")
            }
            .settingsEnabled(settings.deloresCompanionEnabled)
        } header: {
            SettingsSectionHeader(.deloresCompanion)
        } footer: {
            Text(
                "The companion is a Surface, not a second chat client: it has no actions, "
                    + "history or model of its own. It hands you to the Context or Command "
                    + "Surface, which own those."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var windowSection: some View {
        @Bindable var settings = settings
        Section {
            if needsAccessibility {
                SettingsRow(
                    title: "Accessibility permission required",
                    subtitle: needsAccessibilitySubtitle
                ) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.destructive)
                        .frame(width: Theme.Size.settingsRowIcon)
                } trailing: {
                    Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                }
            }
            Toggle(isOn: snappingBinding) {
                SettingsRowTitle(.deloresSpatial, "Enable window snapping")
                Text(
                    "Drag a window up to the island at the top of the display, and drop it on "
                        + "the layout you want."
                )
            }
            Toggle(isOn: dividerBinding) {
                SettingsRowTitle(.deloresSpatial, "Enable split divider")
                Text(
                    "Move the pointer onto the seam between two tiled windows to resize them "
                        + "together."
                )
            }
        } header: {
            SettingsSectionHeader(.deloresSpatial)
        } footer: {
            Text(
                "Both read and move other apps' windows through the same Accessibility "
                    + "permission Tinycast uses to paste. Neither is enabled by default, and "
                    + "neither is restored from a settings backup."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// The window capabilities write window frames, so the grant is asked for where the reader turns
    /// them on — an explicit gesture — rather than at launch.
    private var snappingBinding: Binding<Bool> {
        Binding(
            get: { settings.deloresWindowSnappingEnabled },
            set: { enabled in
                guard enabled else {
                    settings.deloresWindowSnappingEnabled = false
                    return
                }
                guard Permissions.ensureAccessibility() else { return }
                settings.deloresWindowSnappingEnabled = true
            })
    }

    private var dividerBinding: Binding<Bool> {
        Binding(
            get: { settings.deloresSplitDividerEnabled },
            set: { enabled in
                guard enabled else {
                    settings.deloresSplitDividerEnabled = false
                    return
                }
                guard Permissions.ensureAccessibility() else { return }
                settings.deloresSplitDividerEnabled = true
            })
    }

    private var needsAccessibility: Bool {
        !isTrusted && (settings.deloresWindowSnappingEnabled || settings.deloresSplitDividerEnabled)
    }

    private var needsAccessibilitySubtitle: String {
        isTrusted
            ? ""
            : "Tinycast can't read or move other apps' windows until it is granted."
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
            Text("Model for \(action.title)")
                .font(.title2.weight(.bold))
            Text("Used every time \(action.title) runs from the bar on the text you have selected.")
                .foregroundStyle(.secondary)

            QuickActionModelPicker(
                selection: $selection,
                inheritedTitle: keepsAppleTranslator ? "Apple's translator" : "Same as Quick Actions",
                inheritedHelp: keepsAppleTranslator
                    ? "With nothing bound this row keeps Apple's translator; a pair it does not have "
                        + "falls back to the shared model."
                    : "Same as Quick Actions follows the Model section of the Quick Actions pane.")

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
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
