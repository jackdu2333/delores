import SwiftUI

struct DeloresContextIslandView: View {
    @Environment(\.metrics) private var metrics

    let actions: [DeloresContextAction]
    let onAction: (DeloresContextAction) -> Void
    let onDismiss: () -> Void

    static func preferredSize(for metrics: InterfaceMetrics) -> CGSize {
        CGSize(width: metrics.scaled(420), height: metrics.scaled(48))
    }

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            ForEach(actions) { action in
                Button {
                    onAction(action)
                } label: {
                    Label(action.title, systemImage: action.symbol)
                        .font(metrics.typography.rowTrailing)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, metrics.spacing.sm)
                .frame(height: metrics.scaled(30))
                .background(Theme.Colors.controlSurface, in: Capsule())
                .accessibilityLabel(action.title)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: metrics.scaled(11), weight: .semibold))
                    .frame(width: metrics.scaled(24), height: metrics.scaled(30))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityLabel("Dismiss Context Island")
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(
            width: Self.preferredSize(for: metrics).width,
            height: Self.preferredSize(for: metrics).height)
        .frosted(in: Capsule())
        .accessibilityElement(children: .contain)
    }
}
