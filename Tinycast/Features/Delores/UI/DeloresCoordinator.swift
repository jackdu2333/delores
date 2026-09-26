import CoreGraphics

@MainActor
final class DeloresCoordinator {
    private let settings: AppSettings
    private let context: DeloresContextCoordinator
    private let companion: DeloresCompanionCoordinator
    private let companionMode: @MainActor () -> DeloresCompanionMode
    private let codexPet: DeloresCodexPetWindowProbe
    private let snapping: DeloresWindowSnapCoordinator
    private let divider: DeloresSplitDividerCoordinator
    private let interactionGate = DeloresSurfaceInteractionGate()
    /// Whether the launch call has already been made, so only that one waits.
    private var startupDelayScheduled = false
    private var startupDelayFinished = false
    private var appliedCompanionMode: DeloresCompanionMode?
    init(settings: AppSettings, quickActions: QuickActionCoordinator, injector: TextInjector, aiChat: AIChatCoordinator) {
        self.settings = settings
        let gate = interactionGate
        let codexPet = DeloresCodexPetWindowProbe()
        let companionMode: @MainActor () -> DeloresCompanionMode = { [weak codexPet] in
            settings.deloresCompanionMode.resolved(
                codexPetEnabled: codexPet?.isCodexPetEnabled ?? false)
        }
        let context = DeloresContextCoordinator(
            settings: settings, quickActions: quickActions, injector: injector, aiChat: aiChat,
            interactionGate: gate, companionMode: companionMode,
            additionalInteractiveSurfaceHitTest: { [weak codexPet] point in
                guard companionMode() == .codex else { return false }
                return codexPet?.containsPet(at: point) == true
            })
        let companion = DeloresCompanionCoordinator(
            settings: settings, interactionGate: gate, companionMode: companionMode,
            onOpenContext: { [weak context] in context?.showLastCapturedSelection() })
        let snapping = DeloresWindowSnapCoordinator(
            settings: settings, interactionGate: gate,
            additionalIgnoredPoint: { [weak codexPet] point in
                guard companionMode() == .codex else { return false }
                return codexPet?.containsPet(at: point) == true
            })
        let divider = DeloresSplitDividerCoordinator(settings: settings, interactionGate: gate)
        snapping.onWindowGeometryChanged = { [weak divider] point in
            divider?.windowGeometryDidChange(at: point)
        }
        snapping.onWindowSnapped = { [weak divider] window, slot, rect, screen in
            divider?.registerSnappedWindow(window, slot: slot, rect: rect, screen: screen)
        }
        self.context = context; self.companion = companion; self.codexPet = codexPet
        self.companionMode = companionMode
        self.snapping = snapping; self.divider = divider
        codexPet.onAutomaticPetEnabledChange = { [weak self] in
            guard let self, self.startupDelayFinished,
                self.settings.deloresCompanionMode == .automatic
            else { return }
            self.applyEnabled()
        }
        context.onSelectionPresented = { [weak companion] text in companion?.recordSelection(text) }
        // The Companion is the bar's other home: with it on, a bar grows out of the body's inward
        // side rather than down out of the menu bar.
        context.companionHosting = DeloresContextCompanionHosting(
            anchor: { [weak companion, weak codexPet] visibleFrame in
                if companionMode() == .codex {
                    guard let screen = DeloresWindowGeometry.screenContaining(
                        CGPoint(x: visibleFrame.midX, y: visibleFrame.midY))
                    else { return nil }
                    return codexPet?.anchor(on: screen)
                }
                return companion?.anchorForShell(in: visibleFrame)
            },
            avoidanceFrame: { [weak codexPet] visibleFrame in
                guard companionMode() == .codex,
                    let screen = DeloresWindowGeometry.screenContaining(
                        CGPoint(x: visibleFrame.midX, y: visibleFrame.midY))
                else { return nil }
                return codexPet?.activityFrame(on: screen)
            },
            relocate: { [weak companion] center, edge in companion?.relocate(to: center, edge: edge) },
            held: { [weak companion] isHeld in
                guard companionMode() == .delores else { return }
                if isHeld { companion?.holdForShell() } else { companion?.releaseShell() }
            },
            thinking: { [weak companion] isThinking in
                guard companionMode() == .delores else { return }
                companion?.setThinking(isThinking)
            },
            canRelocate: { companionMode() == .delores })
    }

    /// The body is drawn at another step, which changes where it may stand as well as how big it is.
    func applyCompanionSize() { companion.applyCompanionSize() }
    func applyCompanionKind() { companion.applyCompanionKind() }
    func applyEnabled() {
        let selectedMode = settings.deloresCompanionMode
        // The first call is launch, and the main actor is still digesting startup: every mouse
        // event these surfaces install lands on it, and a backlog at launch is paid in the apps
        // the reader clicks into. Give startup a beat before the surfaces go live; a settings
        // change after that still applies immediately.
        guard startupDelayFinished else {
            codexPet.applyEnabled(selectedMode == .automatic)
            guard !startupDelayScheduled else { return }
            startupDelayScheduled = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.startupDelayFinished = true
                self?.applyEnabled()
            }
            return
        }
        codexPet.applyEnabled(selectedMode == .codex || selectedMode == .automatic)
        let mode = companionMode()
        if let appliedCompanionMode, appliedCompanionMode != mode {
            context.stop()
        }
        appliedCompanionMode = mode
        context.applyEnabled(); companion.applyEnabled(); snapping.applyEnabled(); divider.applyEnabled()
    }
    var isHoldingPinnedContext: Bool { context.isHoldingPinnedContext }
    func prepareForTermination() {
        context.stop()
        companion.prepareForTermination()
        codexPet.stop()
        snapping.prepareForTermination()
        divider.prepareForTermination()
        interactionGate.reset()
    }
}
