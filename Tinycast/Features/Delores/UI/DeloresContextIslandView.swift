import SwiftUI

enum DeloresContextIslandMode: Equatable {
    case actions
    case busy
    /// The bar has opened for an answer that arrives on the chat surface instead of in here.
    case handoff(progressTitle: String)

    /// What the opened card says while it waits; nil leaves the bar closed.
    var handoffTitle: String? {
        guard case .handoff(let progressTitle) = self else { return nil }
        return progressTitle
    }
}

struct DeloresContextIslandView: View {
    @Environment(\.metrics) private var metrics

    let actions: [DeloresContextAction]
    let mode: DeloresContextIslandMode
    /// The row keeps the height it was measured at, so opening the card never shifts it.
    let barHeight: CGFloat
    let onAction: (DeloresContextAction) -> Void
    /// Reports the state it switched to, so the controller's copy can never drift from this one.
    let onTogglePin: (Bool) -> Void
    let onDismiss: () -> Void

    /// The toggle draws from here; the controller reads the value this reports back.
    @State private var isPinned: Bool

    init(
        actions: [DeloresContextAction],
        mode: DeloresContextIslandMode,
        isPinned: Bool = false,
        barHeight: CGFloat,
        onAction: @escaping (DeloresContextAction) -> Void,
        onTogglePin: @escaping (Bool) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.actions = actions
        self.mode = mode
        self.barHeight = barHeight
        self.onAction = onAction
        self.onTogglePin = onTogglePin
        self.onDismiss = onDismiss
        _isPinned = State(initialValue: isPinned)
    }

    /// The bar's wish, before the menu bar gets a say.
    static func preferredSize(for metrics: InterfaceMetrics) -> CGSize {
        CGSize(
            width: metrics.scaled(DeloresContextIslandPlacement.preferredWidth),
            height: metrics.scaled(DeloresContextIslandPlacement.preferredBarHeight))
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if let title = mode.handoffTitle {
                Label(title, systemImage: "ellipsis.bubble")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One shape for both states: the corner is wider than half a closed bar's height, so the bar
        // clamps it down to the pill it always was and the card simply grows into the wider corner.
        .frosted(
            in: RoundedRectangle(
                cornerRadius: metrics.scaled(DeloresContextIslandPlacement.openCornerRadius),
                style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var bar: some View {
        HStack(spacing: metrics.spacing.xs) {
            switch mode {
            case .actions, .handoff:
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
            case .busy:
                Label("上一项任务处理中", systemImage: "hourglass")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }

            // Present in every state: a pinned bar that lost its toggle would be a trap, since a
            // pinned surface stops answering outside clicks and new selections alike.
            Button {
                isPinned.toggle()
                onTogglePin(isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: metrics.scaled(11), weight: .semibold))
                    .frame(width: metrics.scaled(24), height: metrics.scaled(30))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isPinned ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            .accessibilityLabel(isPinned ? "Unpin Context Island" : "Pin Context Island")

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
        .frame(height: barHeight)
    }
}
