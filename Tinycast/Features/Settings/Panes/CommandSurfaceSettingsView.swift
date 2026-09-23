import SwiftUI

/// The Command Surface: everything the palette itself reads — how it is summoned, how it ranks, the
/// keys it takes and how it is drawn.
///
/// These rows used to sit in a pane called "General" beside the app's own start-up switch, so the
/// first thing a reader met in Settings was the launcher's shortcut and the product read as a
/// launcher. The app-level rows stayed behind in `GeneralSettingsView`.
struct CommandSurfaceSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    private var hyperTap: HyperKeyTap { core.hyperKeyTap }
    private var launcherRanking: LauncherRankingStore { core.launcherRanking }
    @State private var confirmingRankingReset = false
    @State private var inputSources: [InputSourceSwitcher.Option] = []

    /// The Hyper modifier chord as prose glyphs, tracking the Include Shift toggle.
    private var hyperGlyphs: String { settings.hyperKeyIncludesShift ? "⌃⌥⇧⌘" : "⌃⌥⌘" }

    /// The missing-permission half is its own row, so it can carry the button that fixes it.
    private var hyperSubtitle: String {
        guard settings.hyperKey != .none else {
            return
                L10n.format(
                    "Select a physical key to remap to the %@ modifier keys simultaneously.",
                    hyperGlyphs)
        }
        return
            L10n.format(
                "Pressing %@ will trigger the left %@ modifier keys.",
                L10n.text(settings.hyperKey.title), hyperGlyphs)
            + " "
            + L10n.string("Hyper Key shortcuts are shown in Delores with ✦.")
    }

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                SettingsRow(title: "App Launcher", anchor: .commandSurfaceGlobalShortcuts) {
                    ShortcutRecorder(action: .togglePalette)
                }
            } header: {
                SettingsSectionHeader(.commandSurfaceGlobalShortcuts)
            } footer: {
                Text(L10n.string("Summon the fuzzy app launcher."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.launcherShowsSuggestions) {
                    SettingsRowTitle(.commandSurfaceSearch, "Show suggestions")
                    Text(L10n.string("Show useful entries while the search field is empty."))
                }

                Picker(selection: $settings.rootSearchSensitivity) {
                    ForEach(SearchSensitivity.allCases) { sensitivity in
                        Text(L10n.text(sensitivity.title)).tag(sensitivity)
                    }
                } label: {
                    SettingsRowTitle(.commandSurfaceSearch, "Search sensitivity")
                    Text(L10n.string("Control how loosely fuzzy matches are accepted."))
                }

                LabeledContent {
                    Button(L10n.string("Reset…"), role: .destructive) {
                        confirmingRankingReset = true
                    }
                    .disabled(launcherRanking.isEmpty)
                } label: {
                    SettingsRowTitle(.commandSurfaceSearch, "Learned ranking")
                }
            } header: {
                SettingsSectionHeader(.commandSurfaceSearch)
            } footer: {
                Text(
                    L10n.string(
                        "Delores privately learns which results you choose for each query. Reset all learned choices to restore the default order."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: $settings.hyperKey) {
                    ForEach(HyperKeyPhysicalKey.allCases) { key in
                        Text(L10n.text(key.title)).tag(key)
                    }
                } label: {
                    SettingsRowTitle(.commandSurfaceHyperKey, "Hyper Key")
                    Text(hyperSubtitle)
                }
                .onChange(of: settings.hyperKey) { _, newKey in
                    // A Quick Press choice is meaningless for a different key.
                    settings.hyperKeyQuickPress = .none
                    if newKey != .none { Permissions.ensureAccessibility() }
                }

                if hyperTap.status == .needsAccessibility {
                    LabeledContent {
                        Button(L10n.string("Grant Access…")) {
                            Permissions.openAccessibilitySettings()
                        }
                    } label: {
                        Label(
                            L10n.string("Delores needs Accessibility access to remap keys."),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                if settings.hyperKey.hasOriginalFunction {
                    Picker(selection: $settings.hyperKeyQuickPress) {
                        Text(L10n.string("Does Nothing")).tag(HyperKeyQuickPress.none)
                        if let original = settings.hyperKey.quickPressOriginalTitle {
                            Text(L10n.text(original)).tag(HyperKeyQuickPress.originalKey)
                        }
                        Text(L10n.string("Trigger Escape")).tag(HyperKeyQuickPress.escape)
                    } label: {
                        SettingsRowTitle(.commandSurfaceHyperKey, "Quick Press")
                        Text(
                            L10n.format(
                                "Select an action to perform when %@ is pressed without any other keys.",
                                L10n.text(settings.hyperKey.title))
                        )
                    }
                }

                Toggle(isOn: $settings.hyperKeyIncludesShift) {
                    SettingsRowTitle(.commandSurfaceHyperKey, "Include Shift (⇧)")
                    Text(L10n.format("Hyper Key will remap to the %@ modifier keys.", hyperGlyphs))
                }
                // Flipping it re-points recorded chords, so it needs a chord to mean.
                .settingsEnabled(settings.hyperKey != .none)
            } header: {
                SettingsSectionHeader(.commandSurfaceHyperKey)
            }

            Section {
                Picker(selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(L10n.text(appearance.title)).tag(appearance)
                    }
                } label: {
                    SettingsRowTitle(.commandSurfaceAppearance, "Theme")
                    Text(L10n.string("Match macOS, or pin Delores to Light or Dark."))
                }
                InterfaceSizeRow()
                PaletteTransparencyRow()
                Toggle(isOn: $settings.compactMode) {
                    SettingsRowTitle(.commandSurfaceAppearance, "Compact mode")
                    Text(
                        L10n.string(
                            "Open the launcher as a slim search bar that expands into the full list as you type."
                        )
                    )
                }
                Toggle(isOn: $settings.showFavoritesInCompactMode) {
                    SettingsRowTitle(.commandSurfaceAppearance, "Show favorites in compact mode")
                    Text(
                        L10n.string(
                            "Pin favorite app icons to the right of the compact bar (⌘1–⌘5 to launch)."
                        )
                    )
                }
                .disabled(!settings.compactMode)
                Toggle(isOn: $settings.openOnCursorScreen) {
                    SettingsRowTitle(.commandSurfaceAppearance, "Follow the cursor across displays")
                    Text(
                        L10n.string(
                            "Open the launcher on whichever display the pointer is on, rather than the one with the menu bar."
                        )
                    )
                }
                Toggle(isOn: $settings.paletteDraggable) {
                    SettingsRowTitle(.commandSurfaceAppearance, "Drag to reposition")
                    Text(
                        L10n.string(
                            "Grab the thin strip just above the search field to move the launcher out of the way."
                        )
                    )
                }
            } header: {
                SettingsSectionHeader(.commandSurfaceAppearance)
            }

            Section {
                Picker(selection: $settings.popToRootTimeout) {
                    ForEach(PopToRootTimeout.allCases) { timeout in
                        Text(L10n.text(timeout.title)).tag(timeout)
                    }
                } label: {
                    SettingsRowTitle(.commandSurfaceBehaviour, "Pop to Root Search")
                    Text(L10n.string("Reset to the launcher this long after the window closes."))
                }
                Picker(selection: $settings.escapeKeyBehavior) {
                    ForEach(EscapeKeyBehavior.allCases) { behavior in
                        Text(L10n.text(behavior.title)).tag(behavior)
                    }
                } label: {
                    SettingsRowTitle(.commandSurfaceBehaviour, "Escape Key Behavior")
                    Text(L10n.string("What Escape does once the search field is already empty."))
                }
                // Empty only when TIS fails; one layout still lists, so the row stays put.
                if !inputSources.isEmpty {
                    Picker(selection: $settings.autoSwitchInputSourceID) {
                        Text(L10n.string("None")).tag(nil as String?)
                        ForEach(inputSources) { source in
                            Text(source.title).tag(Optional(source.id))
                        }
                    } label: {
                        SettingsRowTitle(.commandSurfaceBehaviour, "Auto-switch input source")
                        Text(
                            L10n.string(
                                "Switch the keyboard to this source while the launcher is open."))
                    }
                }
            } header: {
                SettingsSectionHeader(.commandSurfaceBehaviour)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.commandSurface)
        .confirmationDialog(
            L10n.string("Reset learned launcher ranking?"),
            isPresented: $confirmingRankingReset,
            titleVisibility: .visible
        ) {
            Button(L10n.string("Reset Ranking"), role: .destructive) {
                launcherRanking.resetAll()
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("Delores will relearn your preferred results as you use the launcher."))
        }
        .onAppear(perform: refreshInputSources)
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: InputSourceSwitcher.sourcesDidChange)
        ) { _ in
            refreshInputSources()
        }
    }

    private func refreshInputSources() {
        inputSources = core.inputSourceSwitcher.options(selecting: settings.autoSwitchInputSourceID)
    }
}

/// Three glyph steps read as a legend; a true-to-scale "Aa" would look identical at 1.1.
private struct InterfaceSizeRow: View {
    @Environment(AppSettings.self) private var settings

    private static let glyph: [InterfaceSize: CGFloat] = [
        .standard: 11, .large: 14, .larger: 17
    ]

    var body: some View {
        SettingsRow(
            title: "Interface size",
            subtitle: "Scale the launcher and the windows that float with it. Settings stay put.",
            subtitleLineLimit: 2,
            anchor: .commandSurfaceAppearance
        ) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(InterfaceSize.allCases) { size in
                    segment(size)
                }
            }
        }
    }

    private func segment(_ size: InterfaceSize) -> some View {
        let selected = settings.interfaceSize == size
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        return Button {
            settings.interfaceSize = size
        } label: {
            Text("Aa")
                .font(.system(size: Self.glyph[size] ?? 13, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(width: Theme.Size.interfaceSizeSegment, height: Theme.Size.settingsSearchField)
                // Without this only the glyphs take the click, not the segment around them.
                .contentShape(shape)
                .background(shape.fill(selected ? Theme.Colors.controlSurface : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(size.title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(L10n.text(size.title))
    }
}

private struct PaletteTransparencyRow: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft: Double?
    @State private var isEditing = false

    private var value: Binding<Double> {
        Binding(
            get: { draft ?? Double(settings.paletteTransparency) },
            set: { value in
                if isEditing {
                    draft = value
                } else {
                    settings.paletteTransparency = Int(value)
                }
            })
    }

    var body: some View {
        SettingsRow(
            title: "Background transparency",
            subtitle: "The level of transparency of the glass background.",
            subtitleLineLimit: 2,
            anchor: .commandSurfaceAppearance
        ) {
            Slider(
                value: value, in: -100...100, step: 50, neutralValue: 0,
                label: { EmptyView() },
                minimumValueLabel: { Text(L10n.string("Less")) },
                maximumValueLabel: { Text(L10n.string("More")) },
                tick: { SliderTick($0) },
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing, let draft {
                        settings.paletteTransparency = Int(draft)
                        self.draft = nil
                    }
                }
            )
            .labelsHidden()
            .accessibilityLabel(L10n.string("Background transparency"))
            .frame(width: Theme.Size.paletteTransparencySlider)
            Button(L10n.string("Reset")) {
                draft = nil
                settings.paletteTransparency = 0
            }
            .help(L10n.string("Restore the default background in Light and Dark."))
        }
    }
}
