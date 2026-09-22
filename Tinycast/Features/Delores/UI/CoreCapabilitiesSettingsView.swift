import SwiftUI

/// The shared capability pane: AI, action routing and chat settings are configured once for all
/// Surfaces, while each Surface pane keeps only its own entry and presentation choices.
struct CoreCapabilitiesSettingsView: View {
    var body: some View {
        Form {
            AISettingsView()
            QuickActionsSettingsView()
            AIChatSettingsView()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.aiAndActions)
    }
}
