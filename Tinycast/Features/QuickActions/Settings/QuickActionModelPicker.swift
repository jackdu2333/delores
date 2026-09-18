import SwiftUI

/// One action's own route, staged by the editor sheet that presents it until Save.
struct QuickActionModelPicker: View {
    @Binding var selection: AIModelSelection?
    /// What having no route of its own means for this row, said here because it is not one answer:
    /// a Quick Action follows the pane's model, while 翻译 keeps Apple's translator.
    var inheritedTitle = "Same as Quick Actions"
    var inheritedHelp = "Same as Quick Actions follows the Model section of the Quick Actions pane."

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Model")
                .font(.callout.weight(.medium))
            HStack(spacing: Theme.Spacing.lg) {
                AIModelSelectionRows(
                    selection: selection,
                    inheritedTitle: inheritedTitle,
                    select: { selection = $0 },
                    modelLabel: { Text("Model") },
                    effortLabel: { Text("Reasoning effort") })
            }
            .labelsHidden()
            Text(inheritedHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
