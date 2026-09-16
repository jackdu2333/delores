import SwiftUI

/// The answer an action produced, as the card below the bar shows it.
///
/// A value, so the controller can hand the view a new one on each state change without the view
/// holding any of it. `text` is nil while the answer is still on its way, which is the same thing as
/// saying the card is waiting — a separate flag could disagree with the text it describes.
struct DeloresContextIslandAnswer: Equatable {
    /// What was asked. The card says this rather than a bare result, because the bar above it can run
    /// other things and the reader needs to know which one answered.
    let actionTitle: String
    let symbol: String
    /// Whether the answer is a rewrite of the selection, which is what decides if it can go back to
    /// the document the selection came from.
    let rewritesSelection: Bool
    var text: String?
    var failure: String?
    /// Nothing more will arrive because the reader stopped it, not because the reply ended. What the
    /// model had already produced stays: a translation half-finished is still the translation up to
    /// there, and it is theirs to keep.
    var isStopped: Bool = false
    /// Something that happened *around* the answer rather than instead of it — a write-back that
    /// failed, a reply that came back empty. Kept apart from `failure` so a note never costs the
    /// reader the text they were about to copy.
    var note: String?

    /// Stopped is not running: a reply the reader cut short waits for them the way a finished one
    /// does, and a spinner beside 重试 would be asking them to wait for something that has stopped.
    var isRunning: Bool { text == nil && failure == nil && !isStopped }

    /// Whether asking again would get another answer. Anything that ended without one can be tried
    /// once more, and so can a reply the reader cut short — but not a reply that finished, which has
    /// nothing left to say for itself.
    var canRetry: Bool { failure != nil || isStopped }
}

enum DeloresContextIslandMode: Equatable {
    case actions
    /// The bar has opened for an answer that arrives on the chat surface instead of in here.
    case handoff(progressTitle: String)
    /// The answer, in the card below the bar. The bar above it stays live: the reader who wanted a
    /// translation often wants a summary of the same selection next.
    case result(DeloresContextIslandAnswer)

    /// What the opened card says while it waits; nil leaves the bar closed.
    var handoffTitle: String? {
        guard case .handoff(let progressTitle) = self else { return nil }
        return progressTitle
    }

    var answer: DeloresContextIslandAnswer? {
        guard case .result(let answer) = self else { return nil }
        return answer
    }

    /// Whether the panel needs the tall frame at all.
    var opensCard: Bool { answer != nil || handoffTitle != nil }
}

/// The press feel for the island's controls.
///
/// A `.plain` style gives no press at all, which is most of why this bar read as a row of labels
/// rather than a row of controls. The scale is deliberately small: the bar is 28pt tall on a 30pt
/// menu bar, and a larger factor turns a click into a bounce.
private struct DeloresIslandPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: Theme.Duration.hover), value: configuration.isPressed)
    }
}

struct DeloresContextIslandView: View {
    @Environment(\.metrics) private var metrics

    let actions: [DeloresContextAction]
    let mode: DeloresContextIslandMode
    /// The height the bar is actually given, after the menu bar has had its say — deliberately not
    /// the wish. Laying out to the wish is what clipped the pills: the panel is capped to the menu
    /// bar strip (28pt on a 30pt bar), so content designed against 38pt lost its bottom edge.
    let barHeight: CGFloat
    let onAction: (DeloresContextAction) -> Void
    let onCopy: () -> Void
    /// Copies the answer in the card, which is a different text from the selection the bar copies.
    let onCopyAnswer: () -> Void
    /// Writes the answer back over the selection it came from.
    let onReplaceAnswer: () -> Void
    /// Reports the state it switched to, so the controller's copy can never drift from this one.
    let onTogglePin: (Bool) -> Void
    /// Puts the card away without putting the selection away.
    let onCollapseAnswer: () -> Void
    /// Stops a reply that is still arriving, keeping what it got so far.
    let onStopAnswer: () -> Void
    /// Asks the same action about the same text again.
    let onRetryAnswer: () -> Void
    /// Asks a further question about this answer, carrying the turn already answered.
    let onFollowUp: (String) -> Void
    let onDismiss: () -> Void
    /// The question being typed, held above the view rather than in it: the card is rebuilt for every
    /// token of the reply above it, and `@State` here would be emptied each time — mid-sentence.
    @Binding var followUpInput: String

    /// The toggle draws from here; the controller reads the value this reports back.
    @State private var isPinned: Bool
    /// The pointer's answer to "which one is this". The bar is nothing but controls, so without a
    /// hover layer the reader has to guess where the cursor has landed.
    @State private var hoveredActionID: String?
    @State private var hoveredControl: Control?
    /// The copy confirmation lives on the button that was pressed, not in a HUD elsewhere: the
    /// reader is already looking here, and a bar that vanishes gives a HUD nothing to point at.
    @State private var didCopy = false
    @State private var didCopyAnswer = false

    private enum Control: Hashable { case copy, pin, collapse, close, copyAnswer, replace }

    init(
        actions: [DeloresContextAction],
        mode: DeloresContextIslandMode,
        isPinned: Bool = false,
        barHeight: CGFloat,
        onAction: @escaping (DeloresContextAction) -> Void,
        onCopy: @escaping () -> Void = {},
        onCopyAnswer: @escaping () -> Void = {},
        onReplaceAnswer: @escaping () -> Void = {},
        onTogglePin: @escaping (Bool) -> Void = { _ in },
        onCollapseAnswer: @escaping () -> Void = {},
        onStopAnswer: @escaping () -> Void = {},
        onRetryAnswer: @escaping () -> Void = {},
        onFollowUp: @escaping (String) -> Void = { _ in },
        followUpInput: Binding<String> = .constant(""),
        onDismiss: @escaping () -> Void
    ) {
        self.actions = actions
        self.mode = mode
        self.barHeight = barHeight
        self.onAction = onAction
        self.onCopy = onCopy
        self.onCopyAnswer = onCopyAnswer
        self.onReplaceAnswer = onReplaceAnswer
        self.onTogglePin = onTogglePin
        self.onCollapseAnswer = onCollapseAnswer
        self.onStopAnswer = onStopAnswer
        self.onRetryAnswer = onRetryAnswer
        self.onFollowUp = onFollowUp
        self.onDismiss = onDismiss
        _followUpInput = followUpInput
        _isPinned = State(initialValue: isPinned)
    }

    /// The bar's wish, before the menu bar caps it and before the controls are measured for width.
    static func preferredSize(for metrics: InterfaceMetrics) -> CGSize {
        CGSize(
            width: metrics.scaled(DeloresContextIslandPlacement.preferredWidth),
            height: metrics.scaled(DeloresContextIslandPlacement.preferredBarHeight))
    }

    /// What a pill may be tall inside the bar it was given. A shallow menu bar shortens the pills
    /// rather than clipping them; the floor keeps the label legible where there is almost no room.
    private var pillHeight: CGFloat {
        max(metrics.scaled(20), barHeight - metrics.scaled(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if let answer = mode.answer {
                Divider().foregroundStyle(Theme.Colors.separator)
                answerCard(answer)
            } else if let title = mode.handoffTitle {
                Divider().foregroundStyle(Theme.Colors.separator)
                Label(title, systemImage: "ellipsis.bubble")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Width hugs the controls; height still fills the vessel so an opened card looks like one
        // surface. Leaving width flexible is what lets the controller size the bar to its content.
        .frame(maxHeight: .infinity)
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
            // Every mode shows the catalog: an answer is one action's result, not the end of the bar,
            // and hiding the others behind a close press would make comparing two of them a
            // three-step job. `.handoff` passes an inert `onAction`, so this costs nothing there.
            ForEach(actions) { action in
                actionPill(action)
            }

            // The copy button is the bar's own action and is always there.
            copyButton
            // Pin and close appear exactly when the automatic exits are unavailable. A pinned
            // surface stops answering outside clicks and new selections alike, so it has to offer a
            // way out of itself; an open card is a state the reader chose and may want to leave
            // without leaving the selection. Collapsed and unpinned, the bar is the four actions and
            // the copy button — which is what was asked for, and what the toolbar this came from
            // showed in that state.
            if isPinned || mode.opensCard {
                controlButton(
                    .pin,
                    symbol: isPinned ? "pin.fill" : "pin",
                    isOn: isPinned,
                    iconSize: 11,
                    help: isPinned ? "松开这份选区" : "钉住这份选区"
                ) {
                    isPinned.toggle()
                    onTogglePin(isPinned)
                }
                // Only while there is a card to put away. Collapsing leaves the selection and the
                // bar exactly where they were, which is the difference between this and closing.
                if mode.opensCard {
                    controlButton(
                        .collapse, symbol: "chevron.up", iconSize: 10.5, weight: .semibold,
                        help: "收起结果"
                    ) {
                        onCollapseAnswer()
                    }
                }
                controlButton(
                    .close, symbol: "xmark", iconSize: 10, weight: .bold, help: "关闭（Esc）"
                ) {
                    onDismiss()
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: barHeight)
    }

    // MARK: - The answer

    /// The card. Deliberately a reader rather than an editor: the reply is meant to be read and then
    /// either copied or written back, and an editable field would invite edits the model never saw.
    private func answerCard(_ answer: DeloresContextIslandAnswer) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.xs) {
                Label(answer.actionTitle, systemImage: answer.symbol)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                // Stop and retry share one slot because they cannot both be true: a reply that has
                // finished cannot be stopped, and one still arriving has nothing to retry.
                if answer.isRunning {
                    answerButton("停止", symbol: "stop.circle") { onStopAnswer() }
                } else if answer.canRetry {
                    answerButton("重试", symbol: "arrow.clockwise") { onRetryAnswer() }
                }
                if answer.text != nil {
                    answerButton(
                        didCopyAnswer ? "已复制" : "复制",
                        symbol: didCopyAnswer ? "checkmark" : "doc.on.doc",
                        confirmed: didCopyAnswer
                    ) {
                        onCopyAnswer()
                        didCopyAnswer = true
                    }
                    // Writing back over somebody's document is the one irreversible thing this card
                    // can do, so it is a button the reader presses and never something that happens
                    // on its own the moment the answer lands — and never while it is still arriving.
                    if answer.rewritesSelection, !answer.isRunning {
                        answerButton("替换原文", symbol: "text.insert") { onReplaceAnswer() }
                    }
                }
            }
            answerBody(answer)
            // A follow-up is a question about an answer, so it waits for there to be one. Asking
            // while the reply is still arriving would read as interrupting it, which is what stop is.
            if answer.text != nil, !answer.isRunning {
                followUpField
            }
            if let note = answer.note {
                Text(note)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: didCopyAnswer) {
            guard didCopyAnswer else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            didCopyAnswer = false
        }
    }

    @ViewBuilder
    private func answerBody(_ answer: DeloresContextIslandAnswer) -> some View {
        if let failure = answer.failure {
            Text(failure)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let text = answer.text {
            ScrollView {
                // Selectable, because the first thing a reader does with a translation is take part
                // of it rather than all of it.
                Text(text)
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if answer.isStopped, answer.text == nil {
            // Stopped before the first token, so there is nothing to show but the fact of it.
            Text("已停止生成。")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: metrics.spacing.sm) {
                ProgressView().controlSize(.small)
                Text(answer.actionTitle + "中…")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Where a reader asks the next question. Plain rather than bordered: the toolbar this came from
    /// drew a container around it and read as a third surface inside the glass.
    private var followUpField: some View {
        let canSend = !followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: metrics.spacing.xs) {
            Image(systemName: "sparkle")
                .font(.system(size: metrics.scaled(11), weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField("接着问…", text: $followUpInput)
                .textFieldStyle(.plain)
                .font(metrics.typography.rowTrailing)
                .onSubmit(submitFollowUp)
            Button(action: submitFollowUp) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: metrics.scaled(15)))
                    .foregroundStyle(canSend ? Color.accentColor : Theme.Colors.textSecondary)
            }
            .buttonStyle(DeloresIslandPressStyle())
            .disabled(!canSend)
            .help("追问（Enter）")
            .accessibilityLabel("追问")
        }
        .padding(.horizontal, metrics.scaled(10))
        .padding(.vertical, metrics.scaled(6))
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .contentShape(Capsule())
    }

    private func submitFollowUp() {
        let question = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        onFollowUp(question)
        followUpInput = ""
    }

    private func answerButton(
        _ title: String, symbol: String, confirmed: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.scaled(3)) {
                Image(systemName: symbol)
                    .font(.system(size: metrics.scaled(10)))
                Text(title)
                    .font(.system(size: metrics.scaled(11), weight: .medium))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(confirmed ? Theme.Colors.success : Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.scaled(6))
            .padding(.vertical, metrics.scaled(3))
            // Filled, never stroked. A capsule outline redraws a second small container inside the
            // glass, which is where a layered look comes from — the toolbar this island came from
            // removed exactly this stroke for exactly this reason.
            .background(Capsule().fill(Color.white.opacity(0.04)))
            .contentShape(Capsule())
        }
        .buttonStyle(DeloresIslandPressStyle())
    }

    // MARK: - The bar's own controls

    private func actionPill(_ action: DeloresContextAction) -> some View {
        let isHovered = hoveredActionID == action.id
        return Button {
            onAction(action)
        } label: {
            // Spelled out rather than left to `Label`'s own spacing, and with the title pinned to
            // its natural width: the toolbar this island came from lays its actions out exactly this
            // way, and the pin is what keeps a width the bar has not measured yet from crushing a
            // title down to an ellipsis.
            HStack(spacing: metrics.scaled(4)) {
                Image(systemName: action.symbol)
                    .font(.system(size: metrics.scaled(12), weight: .medium))
                Text(action.title)
                    .font(.system(size: metrics.scaled(12), weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Theme.Colors.textPrimary.opacity(isHovered ? 0.95 : 0.72))
            .padding(.horizontal, metrics.scaled(8))
            .frame(height: pillHeight)
            // No resting capsule. A container drawn inside the glass reads as a second vessel,
            // which is exactly the layered look the toolbar this came from spent effort removing —
            // the pill is its label, and the pointer supplies the surface. The sheen is white, not a
            // theme hover: a tinted fill reads as a selection rather than as light.
            .background(Capsule().fill(isHovered ? Color.white.opacity(0.08) : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(DeloresIslandPressStyle())
        .onHover { inside in
            hoveredActionID = Self.resolvedHover(inside, current: hoveredActionID, id: action.id)
        }
        .accessibilityLabel(action.title)
    }

    private var copyButton: some View {
        controlButton(
            .copy,
            symbol: didCopy ? "checkmark" : "doc.on.doc",
            tint: didCopy ? Theme.Colors.success : nil,
            help: didCopy ? "已复制" : "复制选区"
        ) {
            onCopy()
            didCopy = true
        }
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            didCopy = false
        }
    }

    private func controlButton(
        _ control: Control,
        symbol: String,
        isOn: Bool = false,
        iconSize: CGFloat = 11,
        weight: Font.Weight = .medium,
        tint: Color? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredControl == control
        // The disc is a whisper at rest and only the pointer or a held state lights it. Painted at
        // this weight it reads as part of the glass; filled in with a theme surface it reads as
        // three grey counters sitting in it, which is not what the toolbar this came from looked
        // like. The padding, not a fixed square, is what sets the size, so the disc tracks the icon.
        let fill =
            isOn
            ? Theme.Colors.selection
            : Color.white.opacity(isHovered ? 0.10 : 0.04)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.scaled(iconSize), weight: weight))
                .foregroundStyle(tint ?? (isOn ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .padding(metrics.scaled(4))
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(DeloresIslandPressStyle())
        .onHover { inside in
            hoveredControl = Self.resolvedHover(inside, current: hoveredControl, id: control)
        }
        // The system tooltip, not Tinycast's own `tooltip`: the island sits inside the menu bar
        // strip, so a label drawn above it would land off the top of the display, and one drawn
        // below it would need a taller panel — which would then swallow the clicks of whatever
        // window is under that strip.
        .help(help)
        .accessibilityLabel(help)
    }

    /// Only clears when the pointer left the control that set it, so a hover that ends while the
    /// pointer is already inside a neighbour cannot blank the neighbour's own highlight.
    private static func resolvedHover<T: Equatable>(_ inside: Bool, current: T?, id: T) -> T? {
        inside ? id : (current == id ? nil : current)
    }
}
