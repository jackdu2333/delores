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
    /// Which action answered, so the bar can light the row the answer came from rather than leaving
    /// the reader to match a title by eye.
    let actionID: String
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
    /// does, and a spinner beside Retry would be asking them to wait for something that has stopped.
    var isRunning: Bool { text == nil && failure == nil && !isStopped }

    /// Whether asking again would get another answer. Anything that ended without one can be tried
    /// once more, and so can a reply the reader cut short — but not a reply that finished, which has
    /// nothing left to say for itself.
    var canRetry: Bool { failure != nil || isStopped }
}

enum DeloresContextIslandMode: Equatable {
    case actions
    /// The selected action is still running; the strip stays put until there is content to open.
    case inlineWorking(DeloresContextIslandAnswer)
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
        switch self {
        case .inlineWorking(let answer), .result(let answer): answer
        default: nil
        }
    }

    var isInlineWorking: Bool {
        guard case .inlineWorking(let answer) = self else { return false }
        return answer.isRunning
    }

    /// True while an answer is being generated and no content has arrived yet.
    var isWorking: Bool {
        if isInlineWorking { return true }
        if let answer, answer.isRunning { return true }
        if handoffTitle != nil { return true }
        return false
    }

    /// Whether the panel needs the card frame at all.
    var opensCard: Bool {
        switch self {
        case .handoff, .result: true
        case .actions, .inlineWorking: false
        }
    }

    var needsExitControls: Bool { opensCard || isInlineWorking }
}

/// The press feel for the island's controls.
///
/// A `.plain` style gives no press at all, which is most of why this bar read as a row of labels
/// rather than a row of controls. Taken from the toolbar this island came from: a spring on the
/// press and a small lift under the pointer, both deliberately shallow — the bar is 28pt tall on a
/// 30pt menu bar, and a larger factor turns a click into a bounce.
private struct DeloresIslandPressStyle: ButtonStyle {
    var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : (isHovered ? 1.03 : 1.0))
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
            .animation(.easeInOut(duration: Theme.Duration.tooltip), value: isHovered)
    }
}

/// The two surfaces that live *inside* the glass vessel, and the rim they share.
///
/// They are filled from the system's own surfaces rather than from the glass, because a surface
/// inside glass has to read as one step away from it: tinting the glass again would make the card
/// look like a second window.
private enum DeloresIslandSurface {
    /// The reading canvas. Near-white in light, a light wash in dark, so a page of text sits on the
    /// opposite side of the glass from the bar above it either way.
    static func card(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .textBackgroundColor).opacity(scheme == .dark ? 0.18 : 0.32)
    }

    /// The follow-up field, tighter than the card because it is a control rather than a page.
    static func pill(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor).opacity(scheme == .dark ? 0.30 : 0.45)
    }

    /// A directional rim: a bright top edge lifts the surface off a ground darker than it, and a dark
    /// bottom edge cuts it off a ground lighter than it. Covering both ends means the surface stays
    /// legible whichever way the background behind the glass happens to drift — a single flat stroke
    /// would only work on one of them.
    static func rim(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(scheme == .dark ? 0.36 : 0.42), location: 0.0),
                .init(color: Color.white.opacity(scheme == .dark ? 0.18 : 0.20), location: 0.16),
                .init(color: Color.white.opacity(scheme == .dark ? 0.06 : 0.08), location: 0.72),
                .init(color: Color.black.opacity(scheme == .dark ? 0.20 : 0.10), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
    }
}

struct DeloresContextIslandView: View {
    @Environment(\.metrics) private var metrics
    /// The sheen is white, not a theme hover: a tinted fill reads as a selection rather than as light.
    /// It is weighted per appearance because the same white does opposite things on the two grounds —
    /// on glass over a light desktop a faint white is invisible, over a dark one it is already a
    /// highlight.
    @Environment(\.colorScheme) private var colorScheme

    let actions: [DeloresContextAction]
    let mode: DeloresContextIslandMode
    /// The height the bar is actually given, after the menu bar has had its say — deliberately not
    /// the wish. Laying out to the wish is what clipped the pills: the panel is capped to the menu
    /// bar strip (28pt on a 30pt bar), so content designed against 38pt lost its bottom edge.
    ///
    /// For a vertical strip this carries the strip's *thickness* instead — the room the column
    /// takes across the display, measured where the bar's width is measured.
    let barHeight: CGFloat
    /// True when this is the vertical strip a body standing on a vertical edge grows: the catalog
    /// stacks into a column whose long axis follows the edge, and cards open inward across the
    /// strip's pet-side rim. The pills themselves never turn — a pill keeps its icon and label
    /// side by side, whatever direction the row that carries them runs in.
    let isVertical: Bool
    /// Which rim of the vessel the strip occupies when vertical — always the pet-side rim, so the
    /// card opens away from the edge into the display.
    let barAtLeadingEdge: Bool
    /// The width the bar had while it was the only thing in the panel, which the row keeps in every
    /// later state.
    ///
    /// This is what keeps the text still. A row that grew with its own controls would slide left as
    /// the panel widened, and the pill the reader just pressed would move out from under the pointer
    /// — first when the card's controls joined the row, then again as the card opened. Drawing the
    /// row at the bar's own width instead means the catalog never moves, and the controls a card adds
    /// spill to the right of it.
    ///
    /// Zero while measuring: a row told its own width cannot report what width it needs. A vertical
    /// strip keeps its length instead — see `pinnedBarLength` — and ignores this.
    let pinnedBarWidth: CGFloat
    /// The length the column had while it was the only thing in the panel, which the column keeps
    /// in every later state — the vertical strip's counterpart to `pinnedBarWidth`.
    let pinnedBarLength: CGFloat
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
    /// Escalates the completed result into the full Command conversation.
    let onContinueInCommand: () -> Void
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

    private enum Control: Hashable { case copy, pin, collapse, close, copyAnswer, replace, stop }

    init(
        actions: [DeloresContextAction],
        mode: DeloresContextIslandMode,
        isPinned: Bool = false,
        barHeight: CGFloat,
        isVertical: Bool = false,
        barAtLeadingEdge: Bool = true,
        pinnedBarWidth: CGFloat = 0,
        pinnedBarLength: CGFloat = 0,
        onAction: @escaping (DeloresContextAction) -> Void,
        onCopy: @escaping () -> Void = {},
        onCopyAnswer: @escaping () -> Void = {},
        onReplaceAnswer: @escaping () -> Void = {},
        onTogglePin: @escaping (Bool) -> Void = { _ in },
        onCollapseAnswer: @escaping () -> Void = {},
        onStopAnswer: @escaping () -> Void = {},
        onRetryAnswer: @escaping () -> Void = {},
        onFollowUp: @escaping (String) -> Void = { _ in },
        onContinueInCommand: @escaping () -> Void = {},
        followUpInput: Binding<String> = .constant(""),
        onDismiss: @escaping () -> Void
    ) {
        self.actions = actions
        self.mode = mode
        self.barHeight = barHeight
        self.isVertical = isVertical
        self.barAtLeadingEdge = barAtLeadingEdge
        self.pinnedBarWidth = pinnedBarWidth
        self.pinnedBarLength = pinnedBarLength
        self.onAction = onAction
        self.onCopy = onCopy
        self.onCopyAnswer = onCopyAnswer
        self.onReplaceAnswer = onReplaceAnswer
        self.onTogglePin = onTogglePin
        self.onCollapseAnswer = onCollapseAnswer
        self.onStopAnswer = onStopAnswer
        self.onRetryAnswer = onRetryAnswer
        self.onFollowUp = onFollowUp
        self.onContinueInCommand = onContinueInCommand
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

    /// What one entry occupies along a vertical strip's long axis. A column is a stack of these, so
    /// this is what decides how long the strip grows — tight enough that the whole catalog still
    /// reads as a strip beside the body rather than a slab, and tall enough for an icon to keep its
    /// title under it.
    private var verticalStep: CGFloat { metrics.scaled(36) }

    /// What a pill may be tall inside the bar it was given. A shallow menu bar shortens the pills
    /// rather than clipping them; the floor keeps the label legible where there is almost no room.
    /// A column's entries take the strip's own step instead: its thickness is the width the entries
    /// need, not a depth anything is capping.
    private var pillHeight: CGFloat {
        guard isVertical else { return max(metrics.scaled(20), barHeight - metrics.scaled(8)) }
        return verticalStep
    }

    /// Where the vessel's two tenants sit: the bar along its top edge on the menu bar, the strip
    /// against the pet-side rim on a vertical edge. The card hangs the same way, off the far side of
    /// whichever rim the bar itself occupies.
    private var vesselAlignment: Alignment {
        guard isVertical else { return .top }
        return barAtLeadingEdge ? .topLeading : .topTrailing
    }

    private var vesselShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: metrics.scaled(DeloresContextIslandPlacement.openCornerRadius),
            style: .continuous)
    }

    var body: some View {
        // The bar holds the vessel's own top strip and the card hangs below it, as a ZStack rather
        // than a VStack.
        //
        // A VStack pushes the bar out of the glass whenever the content is taller than the vessel —
        // SwiftUI centres an oversized child, so while the window is still growing into its final
        // height the bar would slide up and out of the top. `Color.clear` is the receiver that keeps
        // the vessel's height honest: it accepts any proposal down to nothing, and the card hangs off
        // its `background`, which does not feed back into the vessel's size. So the card overflows
        // downward and is clipped, which is what "the panel opens downward" means, instead of
        // shoving the bar off the top of the screen. A vertical strip is the same arrangement turned
        // a quarter: the strip holds the pet-side rim and the card overflows inward across it.
        ZStack(alignment: vesselAlignment) {
            bar
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(alignment: vesselAlignment) {
                    if mode.opensCard {
                        expandedContent
                    }
                }
        }
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: isVertical ? vesselAlignment : .top)
        // One shape for both states: the corner is wider than half a closed bar's height, so the bar
        // clamps it down to the pill it always was and the card simply grows into the wider corner.
        .frosted(in: vesselShape)
        .clipShape(vesselShape)
        .accessibilityElement(children: .contain)
    }

    /// What hangs below the bar while a card is open: the reading surface, then the follow-up field
    /// as a surface of its own.
    ///
    /// The two are separate surfaces rather than one card with a divider through it. The toolbar this
    /// island came from draws no rule anywhere inside the vessel — a 1pt line inside glass reads as a
    /// second container, and the field is a control rather than a part of the answer.
    private var expandedContent: some View {
        VStack(spacing: metrics.spacing.md) {
            if let answer = mode.answer {
                if mode.isWorking {
                    workingCard(answer)
                } else {
                    answerCard(answer)
                    followUpPill(answer)
                }
            } else if let title = mode.handoffTitle {
                handoffCard(title)
            }
        }
        .padding(.top, isVertical ? 0 : barHeight)
        .padding(
            isVertical && barAtLeadingEdge ? .leading : .trailing,
            isVertical ? barHeight : 0)
        .padding(.horizontal, metrics.scaled(DeloresContextIslandPlacement.cardInset))
        .padding(.bottom, metrics.scaled(DeloresContextIslandPlacement.pillBottomInset))
    }

    /// The sleek, thin processing card shown while waiting for an answer to begin arriving.
    private func workingCard(_ answer: DeloresContextIslandAnswer) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(L10n.format("✦ %@ in progress…", answer.actionTitle))
                .font(.system(size: metrics.scaled(12), weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
            Button {
                onStopAnswer()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: metrics.scaled(10)))
                    .foregroundStyle(Theme.Colors.destructive)
                    .frame(width: metrics.scaled(26), height: metrics.scaled(26))
                    .background(
                        Circle().fill(
                            Theme.Colors.destructive.opacity(colorScheme == .dark ? 0.16 : 0.10)))
            }
            .buttonStyle(DeloresIslandPressStyle())
            .help(L10n.string("Stop generating"))
            .accessibilityLabel(L10n.string("Stop generating"))
        }
        .padding(.horizontal, metrics.scaled(12))
        .padding(.vertical, metrics.scaled(8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(
                cornerRadius: metrics.scaled(DeloresContextIslandPlacement.cardCornerRadius),
                style: .continuous
            )
            .fill(DeloresIslandSurface.card(colorScheme)))
        .overlay(
            RoundedRectangle(
                cornerRadius: metrics.scaled(DeloresContextIslandPlacement.cardCornerRadius),
                style: .continuous
            )
            .strokeBorder(DeloresIslandSurface.rim(colorScheme), lineWidth: 0.5))
    }

    /// The card shown while an action's answer is being handed to the chat surface. Its own buttons
    /// are inert: the press is the whole gesture.
    private func handoffCard(_ title: String) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            ProgressView().controlSize(.small)
            Text(title)
                .font(.system(size: metrics.scaled(12)))
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.scaled(10))
        .padding(.vertical, metrics.scaled(12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(
                cornerRadius: metrics.scaled(DeloresContextIslandPlacement.cardCornerRadius),
                style: .continuous
            )
            .fill(DeloresIslandSurface.card(colorScheme)))
    }

    /// The bar's arrangement: a row on the menu bar, a column on a vertical edge. The row runs
    /// along the edge the body rides either way; only the pills' carrier turns, never the pills.
    ///
    /// Either way the row is pinned to the length it was measured at — `pinnedBarWidth` one way,
    /// `pinnedBarLength` the other — so the controls a card adds spill past the row's end rather
    /// than pushing the catalog along, and `fixedSize` is what makes that spill deliberate: it
    /// stops the row from being squeezed to the space it is being drawn in, which is the other way
    /// this layout could eat the controls it just added.
    @ViewBuilder
    private var bar: some View {
        if isVertical {
            VStack(spacing: metrics.spacing.sm) { barContent }
                .padding(.vertical, metrics.spacing.md)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: pinnedBarLength > 0 ? pinnedBarLength : nil, alignment: .top)
                .frame(width: barHeight)
        } else {
            HStack(spacing: metrics.spacing.sm) { barContent }
                .padding(.horizontal, metrics.spacing.md)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: pinnedBarWidth > 0 ? pinnedBarWidth : nil, alignment: .leading)
                .frame(height: barHeight)
        }
    }

    @ViewBuilder
    private var barContent: some View {
        // Every mode shows the catalog: an answer is one action's result, not the end of the bar,
        // and hiding the others behind a close press would make comparing two of them a
        // three-step job. `.handoff` passes an inert `onAction`, so this costs nothing there.
        ForEach(actions) { action in
            actionPill(action)
        }

        // The trailing slot carries one group or the other, never both.
        //
        // Collapsed and unpinned, the bar is the catalog and the copy button — which is what was
        // asked for, and what the toolbar this came from showed in that state. Pin, collapse and
        // close belong to the states where the automatic exits are unavailable: a pinned surface
        // stops answering outside clicks and new selections alike, so it has to offer a way out
        // of itself, and an open card is a state the reader chose and may want to leave without
        // leaving the selection.
        //
        // Swapping rather than adding is the whole point. The selection's copy has a home in the
        // card while a card is open — the answer has its own copy button there — and carrying
        // both groups would grow the row by three controls instead of two, for a button already
        // on screen.
        if isPinned || mode.needsExitControls {
            controlButton(
                .pin,
                symbol: isPinned ? "pin.fill" : "pin",
                isOn: isPinned,
                iconSize: 11,
                help: L10n.text(isPinned ? "Release this selection" : "Pin this selection")
            ) {
                isPinned.toggle()
                onTogglePin(isPinned)
            }
            // Only while there is a card to put away. Collapsing leaves the selection and the
            // bar exactly where they were, which is the difference between this and closing.
            if mode.opensCard {
                controlButton(
                    .collapse, symbol: "chevron.up", iconSize: 10.5, weight: .semibold,
                    help: L10n.string("Collapse the answer")
                ) {
                    onCollapseAnswer()
                }
            }
            if mode.isInlineWorking {
                controlButton(
                    .stop, symbol: "stop.fill", iconSize: 10,
                    tint: Theme.Colors.destructive,
                    help: L10n.string("Stop generating"), action: onStopAnswer)
            }
            controlButton(
                .close, symbol: "xmark", iconSize: 10, weight: .bold,
                help: L10n.string("Close (Esc)")
            ) {
                onDismiss()
            }
        } else {
            copyButton
        }
    }

    // MARK: - The answer

    /// The card. Deliberately a reader rather than an editor: the reply is meant to be read and then
    /// either copied or written back, and an editable field would invite edits the model never saw.
    ///
    /// A surface of its own inside the vessel, not a region of the vessel: the toolbar this island
    /// came from paints the reading area one step away from the bar above it, with a directional rim
    /// rather than a rule. It also fills the height it is given, which is what makes the answer look
    /// like a page rather than a label that happens to be long.
    private func answerCard(_ answer: DeloresContextIslandAnswer) -> some View {
        VStack(spacing: 0) {
            answerHeader(answer)
            answerBody(answer)
            if let note = answer.note {
                Text(note)
                    .font(.system(size: metrics.scaled(11)))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, metrics.scaled(10))
                    .padding(.bottom, metrics.scaled(8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(
                cornerRadius: metrics.scaled(DeloresContextIslandPlacement.cardCornerRadius),
                style: .continuous
            )
            .fill(DeloresIslandSurface.card(colorScheme)))
        .overlay(
            RoundedRectangle(
                cornerRadius: metrics.scaled(DeloresContextIslandPlacement.cardCornerRadius),
                style: .continuous
            )
            .strokeBorder(DeloresIslandSurface.rim(colorScheme), lineWidth: 0.5))
        .task(id: didCopyAnswer) {
            guard didCopyAnswer else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            didCopyAnswer = false
        }
    }

    /// The strip above the answer: which action answered, and everything the reader can do with it.
    ///
    /// The action is a chip rather than a bare label, because the bar above already lights that row
    /// and the card is the second place the reader looks to confirm it.
    private func answerHeader(_ answer: DeloresContextIslandAnswer) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.xs) {
                Image(systemName: answer.symbol)
                    .font(.system(size: metrics.scaled(10), weight: .medium))
                Text(answer.actionTitle)
                    .font(.system(size: metrics.scaled(11), weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, metrics.scaled(6))
            .padding(.vertical, metrics.scaled(2.5))
            .background(
                Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04)))

            Spacer(minLength: metrics.spacing.sm)

            // Retry stays here; stop does not. A reply that has finished cannot be stopped and one
            // still arriving has nothing to retry, and stopping belongs with the field the reader is
            // watching fill rather than with the answer's own controls.
            if answer.canRetry {
                answerButton(L10n.string("Retry"), symbol: "arrow.clockwise") { onRetryAnswer() }
            }
            if answer.text != nil {
                answerButton(
                    L10n.text(didCopyAnswer ? "Copied" : "Copy"),
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
                    answerButton(
                        L10n.string("Replace the selection"), symbol: "text.insert"
                    ) { onReplaceAnswer() }
                }
                if !answer.isRunning, answer.failure == nil, let text = answer.text, !text.isEmpty {
                    answerButton(
                        L10n.string("Continue in Command"), symbol: "arrow.up.right"
                    ) { onContinueInCommand() }
                    .help(L10n.string("Continue asking"))
                    .accessibilityLabel(L10n.string("Continue asking"))
                }
            }
        }
        .padding(.horizontal, metrics.scaled(10))
        .padding(.top, metrics.scaled(7))
        .padding(.bottom, metrics.scaled(5))
    }

    @ViewBuilder
    private func answerBody(_ answer: DeloresContextIslandAnswer) -> some View {
        if let failure = answer.failure {
            answerParagraph {
                Text(failure)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        } else if let text = answer.text {
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                    DeloresMarkdownReaderView(markdown: text)
                        .padding(.horizontal, metrics.scaled(10))
                        .padding(.vertical, metrics.scaled(8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if answer.isStopped, answer.text == nil {
            // Stopped before the first token, so there is nothing to show but the fact of it.
            answerParagraph {
                Text(L10n.string("Generation stopped."))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } else {
            answerParagraph {
                HStack(spacing: metrics.spacing.md) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string("Generating…"))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    /// One paragraph of the reading canvas, set the way the toolbar this island came from set it:
    /// 13pt with the leading opened up to 4, inset from the card's own edge rather than the vessel's.
    ///
    /// The leading is the part worth copying. A block of translated prose is read rather than
    /// scanned, and at this size the default leading runs the lines together.
    private func answerParagraph<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .font(.system(size: metrics.scaled(13)))
            .lineSpacing(metrics.scaled(4))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.scaled(10))
            .padding(.vertical, metrics.scaled(8))
    }

    /// Where a reader asks the next question: a surface of its own, below the answer's card.
    ///
    /// Separate rather than a row inside the card, because it is a control and not part of the
    /// reading. It also carries the stop button — the field is what the reader is watching fill, so
    /// that is where stopping belongs, and the answer's own header keeps only what acts on a
    /// finished reply.
    private func followUpPill(_ answer: DeloresContextIslandAnswer) -> some View {
        let canSend = !followUpInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: metrics.spacing.md) {
            Image(systemName: "sparkle")
                .font(.system(size: metrics.scaled(11), weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
            TextField(L10n.string("Ask a follow-up about this…"), text: $followUpInput)
                .textFieldStyle(.plain)
                .font(.system(size: metrics.scaled(12)))
                .onSubmit(submitFollowUp)
            if answer.isRunning {
                Button {
                    onStopAnswer()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: metrics.scaled(15)))
                        .foregroundStyle(Theme.Colors.destructive.opacity(0.9))
                }
                .buttonStyle(DeloresIslandPressStyle())
                .help(L10n.string("Stop generating"))
                .accessibilityLabel(L10n.string("Stop generating"))
            } else {
                Button(action: submitFollowUp) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: metrics.scaled(15)))
                        .foregroundStyle(
                            canSend
                                ? Color.accentColor
                                : Theme.Colors.textSecondary.opacity(0.35))
                }
                .buttonStyle(DeloresIslandPressStyle())
                .disabled(!canSend)
                .help(L10n.string("Follow up (Return)"))
                .accessibilityLabel(L10n.string("Follow up"))
            }
        }
        .padding(.horizontal, metrics.scaled(12))
        .padding(.vertical, metrics.scaled(7))
        .background(Capsule().fill(DeloresIslandSurface.pill(colorScheme)))
        .overlay(Capsule().strokeBorder(DeloresIslandSurface.rim(colorScheme), lineWidth: 0.6))
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
        // The row the answer came from stays lit for as long as the card is open. The card names the
        // action too, but the bar is where the reader pressed, and a bar that looks identical before
        // and after a press leaves them to work out which of four rows answered.
        let isAnswering = mode.answer?.actionID == action.id
        let isWaiting = isAnswering && mode.answer?.isRunning == true
        let ink =
            isAnswering
            ? Color.accentColor
            : Theme.Colors.textPrimary.opacity(isHovered ? 0.95 : 0.72)
        let weight: Font.Weight = isAnswering ? .semibold : .medium
        return Button {
            onAction(action)
        } label: {
            // Spelled out rather than left to `Label`'s own spacing, and with the title pinned to
            // its natural width: the toolbar this island came from lays its actions out exactly this
            // way, and the pin is what keeps a width the bar has not measured yet from crushing a
            // title down to an ellipsis.
            //
            // A column turns the pair round instead. Its thickness is the shorter of its two sides,
            // and an entry that kept icon and title side by side would carry the row's whole width
            // down the column — the strip would be as wide as the bar it replaced and twice as tall.
            // Icon over a smaller title keeps the thickness at roughly the body's own scale, which
            // is the only reason a column can stand next to the pet and still read as a strip.
            Group {
                if isVertical {
                    VStack(spacing: metrics.scaled(1)) {
                        actionSymbol(action, isWaiting: isWaiting, size: 13, weight: weight)
                        Text(action.displayTitle)
                            .font(.system(size: metrics.scaled(10), weight: weight))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: metrics.spacing.xs) {
                        actionSymbol(action, isWaiting: isWaiting, size: 12, weight: weight)
                        Text(action.displayTitle)
                            .font(.system(size: metrics.scaled(12), weight: weight))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, isVertical ? metrics.spacing.sm : metrics.spacing.md)
            .frame(height: pillHeight)
            // No resting capsule. A container drawn inside the glass reads as a second vessel,
            // which is exactly the layered look the toolbar this came from spent effort removing —
            // the pill is its label, and the pointer supplies the surface. The answering row is the
            // exception, and even there it is a soft tint rather than a stroked outline: a rim would
            // redraw a small container inside the glass.
            .background(
                Group {
                    if isAnswering {
                        Capsule().fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                    Color.accentColor.opacity(colorScheme == .dark ? 0.05 : 0.03),
                                ],
                                startPoint: .top, endPoint: .bottom))
                    } else if isHovered {
                        Capsule().fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18))
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(DeloresIslandPressStyle(isHovered: isHovered))
        .onHover { inside in
            hoveredActionID = Self.resolvedHover(inside, current: hoveredActionID, id: action.id)
        }
        .accessibilityLabel(action.displayTitle)
        .accessibilityValue(isWaiting ? L10n.string("Generating…") : "")
    }

    @ViewBuilder
    private func actionSymbol(
        _ action: DeloresContextAction, isWaiting: Bool, size: CGFloat, weight: Font.Weight
    ) -> some View {
        if isWaiting {
            ProgressView()
                .controlSize(.mini)
                .tint(Color.accentColor)
                .frame(width: metrics.scaled(size), height: metrics.scaled(size))
        } else {
            Image(systemName: action.symbol)
                .font(.system(size: metrics.scaled(size), weight: weight))
        }
    }

    private var copyButton: some View {
        controlButton(
            .copy,
            symbol: didCopy ? "checkmark" : "doc.on.doc",
            tint: didCopy ? Theme.Colors.success : nil,
            help: L10n.text(didCopy ? "Copied" : "Copy selection")
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
        // Every one of these holds a square of the same size whatever it is drawing. `doc.on.doc`
        // and `checkmark` are not the same width, and neither are `pin` and `pin.fill` — an icon that
        // changed the footprint would resize the row it sits in, and a row resized under the pointer
        // is the same jolt as a row that moved.
        //
        // The disc is a whisper at rest and only the pointer or a held state lights it. Painted at
        // this weight it reads as part of the glass; filled in with a theme surface it reads as
        // three grey counters sitting in it, which is not what the toolbar this came from looked
        // like. The padding, not a fixed outer square, is what sets the target, so the disc tracks
        // the icon.
        let fill =
            isOn
            ? Color.accentColor.opacity(0.12)
            : Color.primary.opacity(
                isHovered ? (colorScheme == .dark ? 0.10 : 0.07) : 0.04)
        return Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: metrics.scaled(iconSize), weight: weight))
                .frame(width: metrics.scaled(12), height: metrics.scaled(12))
                .foregroundStyle(tint ?? (isOn ? Color.accentColor : Theme.Colors.textPrimary.opacity(0.65)))
                .padding(metrics.scaled(4))
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(DeloresIslandPressStyle(isHovered: isHovered))
        // A column's controls take the same step as its entries: a disc left at its own height
        // among them would read as a gap in the column rather than as another thing to press.
        .frame(minHeight: isVertical ? verticalStep : 0)
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


// MARK: - Delores Markdown Reader View

/// A compact, high-aesthetic Markdown reader for Delores Context Island Result Card.
/// Designed for small reading surfaces: no oversized headings, clean typography, beautiful code chips.
struct DeloresMarkdownReaderView: View {
    let markdown: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(DeloresMarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: DeloresMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.top, level <= 2 ? 4 : 2)

        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Theme.Colors.textPrimary)

        case .bulletItem(let indent, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
                    .frame(width: 10, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .padding(.leading, CGFloat(indent) * 12)

        case .numberedItem(let num, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(num + ".")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 16, alignment: .trailing)
                Text(inlineMarkdown(text))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

        case .codeBlock(let lang, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let lang, !lang.isEmpty {
                    Text(lang.lowercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.7))
                        .padding(.horizontal, 4)
                }
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }

        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: 12.5))
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(.vertical, 2)

        case .divider:
            Divider()
                .overlay(Color.primary.opacity(0.1))
                .padding(.vertical, 4)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return 15
        case 2: return 14
        default: return 13.5
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

private enum DeloresMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletItem(indent: Int, text: String)
    case numberedItem(number: String, text: String)
    case codeBlock(lang: String?, code: String)
    case quote(text: String)
    case divider

    static func parse(_ raw: String) -> [DeloresMarkdownBlock] {
        var blocks: [DeloresMarkdownBlock] = []
        let lines = raw.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(.codeBlock(lang: lang.isEmpty ? nil : lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Divider: --- or *** or ___
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Heading: # H1, ## H2, etc.
            if trimmed.hasPrefix("#") {
                var level = 0
                while level < trimmed.count && trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)] == "#" {
                    level += 1
                }
                if level <= 6 {
                    let afterHash = trimmed.dropFirst(level)
                    if afterHash.hasPrefix(" ") {
                        let text = String(afterHash).trimmingCharacters(in: .whitespaces)
                        blocks.append(.heading(level: level, text: text))
                        i += 1
                        continue
                    }
                }
            }

            // Blockquote: > text
            if trimmed.hasPrefix(">") {
                let quoteText = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text: quoteText))
                i += 1
                continue
            }

            // Bullet list item: - or *
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
                let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                blocks.append(.bulletItem(indent: indent, text: text))
                i += 1
                continue
            }

            // Numbered list item: 1. or 2.
            let numMatch = trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression)
            if let match = numMatch {
                let prefix = String(trimmed[match])
                let digits = prefix.trimmingCharacters(in: CharacterSet(charactersIn: ".) \t"))
                let text = String(trimmed[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                blocks.append(.numberedItem(number: digits, text: text))
                i += 1
                continue
            }

            // Standard paragraph
            blocks.append(.paragraph(text: line))
            i += 1
        }

        return blocks
    }
}
