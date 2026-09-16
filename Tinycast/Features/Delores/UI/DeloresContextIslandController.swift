import AppKit
import SwiftUI

private final class DeloresFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class DeloresContextIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the Context Surface window; feature policy stays in `DeloresContextCoordinator`.
@MainActor
final class DeloresContextIslandController: NSObject, NSWindowDelegate {
    private var panel: DeloresContextIslandPanel?
    private var onDismiss: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func contains(_ point: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -4, dy: -4).contains(point)
    }

    func present(
        context: SelectionInvocation,
        actions: [DeloresContextAction],
        metrics: InterfaceMetrics,
        onAction: @escaping (DeloresContextAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        dismiss(notifying: false)

        let size = DeloresContextIslandView.preferredSize(for: metrics)
        let root = DeloresContextIslandView(
            actions: actions,
            onAction: { [weak self] action in
                self?.dismiss(notifying: false)
                onAction(action)
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosted = root.environment(\.metrics, metrics)
        let hosting = DeloresFirstMouseHostingView(rootView: hosted)
        hosting.sizingOptions = []
        hosting.setFrameSize(size)

        let panel = DeloresContextIslandPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.delegate = self
        panel.contentView = hosting

        let frame = DeloresContextIslandPlacement.frame(in: context.screen, size: size)
        panel.setFrame(NSRect(origin: frame.origin, size: frame.size), display: false)
        self.panel = panel
        self.onDismiss = onDismiss

        panel.fadeIn(duration: Theme.Duration.enter) {
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    func dismiss(notifying: Bool = true) {
        guard let closing = panel else {
            if notifying { onDismiss?() }
            return
        }
        panel = nil
        let callback = onDismiss
        onDismiss = nil
        closing.delegate = nil
        if notifying { callback?() }
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        dismiss()
    }
}
