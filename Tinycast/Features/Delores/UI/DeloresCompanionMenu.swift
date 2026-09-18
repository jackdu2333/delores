import AppKit
import SwiftUI

/// The Companion's own menu, in a window of its own: the body is too small to hold one, and a menu
/// AppKit has to run a tracking loop for is the one thing never to hang off a body that walks the
/// menu bar.
final class DeloresCompanionMenuPanel: NSPanel {
    /// `PopoverMenu` arms its hover highlight off a `PaletteState`; the Companion owns no palette,
    /// so this menu brings its own: opening it must not re-key the palette's own menu.
    weak var menuState: PaletteState?

    init() {
        super.init(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: false)
        isFloatingPanel = true
        // Key only if something in here asks for it, which nothing does: a menu the reader
        // right-clicked open has no business taking the keyboard from the app they were using.
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        // `.popUpMenu`, where the snap island sits too: the body rides at `.statusBar`, and a menu
        // it could draw over would be one half-buried in its own anchor.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    /// Rows light on real pointer movement, exactly as the palette's own menus do.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: menuState?.notePointerMoved(to: NSEvent.mouseLocation)
        case .scrollWheel: menuState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        default: break
        }
        super.sendEvent(event)
    }
}

/// The menu's rows. Selection belongs to the pointer here: the menu takes no key, so nothing else
/// can move it.
private struct DeloresCompanionMenuView: View {
    let items: [PopoverMenuItem]
    let width: CGFloat

    /// Nothing is lit until the pointer moves of its own accord: the press that asked for the menu
    /// chose no row of it.
    @State private var selection = -1

    var body: some View {
        PopoverMenu(
            header: nil, items: items, selection: $selection, width: width,
            onActivate: { items[$0].action() })
    }
}

/// Opens and closes the Companion's menu, and owns the window it lives in.
///
/// Placement is `DeloresCompanionShell.placeShell`, the geometry that grows the Context bar and the
/// snap island out of the body, so a menu that does not fit where the body is standing resolves the
/// way every other shell does: the body slides along its own edge to make room.
@MainActor
final class DeloresCompanionMenuController {
    /// Where the menu hangs, and what it must stay clear of: the body that opened it, and the
    /// display it may land on.
    struct Anchor {
        let petCenter: CGPoint
        let petFrame: CGRect
        let edge: DeloresCompanionEdge
        let bodyRadius: CGFloat
        let visibleFrame: CGRect
    }

    /// Called when the menu closed for a reason other than a row of it being pressed. The body's
    /// owner is the only thing that can let go of the body.
    var onClose: (() -> Void)?

    var isOpen: Bool { panel?.isVisible ?? false }

    /// Wide enough for the longest creature name beside its `当前` mark, and stated rather than
    /// intrinsic so a longer name can only ever truncate itself rather than move the menu.
    private static let width: CGFloat = 220

    private let menuState = PaletteState()
    private var panel: DeloresCompanionMenuPanel?
    private var outsideClickMonitors: [Any] = []

    /// Shows `items` beside the body, and answers where the body ended up.
    @discardableResult
    func show(
        _ items: [PopoverMenuItem], anchoredTo anchor: Anchor, metrics: InterfaceMetrics
    ) -> CGPoint {
        hide()
        let panel = panel ?? makePanel()
        self.panel = panel
        let view = DeloresCompanionMenuView(
            items: items.map { $0.closing { [weak self] in self?.hide() } },
            width: metrics.scaled(Self.width))
            .environment(menuState)
            .environment(\.metrics, metrics)
        let hosting = DeloresFirstMouseHostingView(rootView: AnyView(view))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.wantsLayer = true
        panel.contentView = hosting
        panel.displayIfNeeded()
        let placement = DeloresCompanionShell.placeShell(
            petCenter: anchor.petCenter, edge: anchor.edge, shellSize: hosting.intrinsicContentSize,
            visibleFrame: anchor.visibleFrame, bodyRadius: anchor.bodyRadius)
        // Imposed on the content as well as the panel: an `NSHostingView` in a window sizes that
        // window too, and the two numbers have to be the same one.
        panel.setFrame(placement.frame, display: false)
        hosting.frame = CGRect(origin: .zero, size: placement.frame.size)
        panel.invalidateShadow()
        installDismissalWatchers(avoiding: anchor.petFrame)
        panel.orderFrontRegardless()
        return placement.petCenter
    }

    /// Ordered out rather than torn down: a row's own press is still being dispatched through it.
    func hide() {
        teardownDismissalWatchers()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        onClose?()
    }

    private func makePanel() -> DeloresCompanionMenuPanel {
        let panel = DeloresCompanionMenuPanel()
        panel.menuState = menuState
        return panel
    }

    /// A menu that holds no key has no key to lose, so the click away is watched directly. A click
    /// on the body that opened it is not a leave: the menu is hung off that body.
    private func installDismissalWatchers(avoiding bodyFrame: CGRect) {
        teardownDismissalWatchers()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideClickMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                MainActor.assumeIsolated { self?.dismissIfReaderClickedAway(from: bodyFrame) }
            },
            NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.dismissIfReaderClickedAway(from: bodyFrame) }
                return event
            },
        ].compactMap { $0 }
    }

    private func teardownDismissalWatchers() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors = []
    }

    private func dismissIfReaderClickedAway(from bodyFrame: CGRect) {
        guard let panel, panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        // A press inside either frame is already on its way to whatever control sits under it.
        guard !panel.frame.contains(point), !bodyFrame.contains(point) else { return }
        hide()
    }
}

private extension PopoverMenuItem {
    /// Every row takes the menu away with it: left open over the body it grew from, it would cover
    /// the thing the reader was looking at.
    func closing(_ close: @escaping () -> Void) -> PopoverMenuItem {
        PopoverMenuItem(
            title: title, icon: icon, isLoading: isLoading, isEnabled: isEnabled,
            sectionTitle: sectionTitle, startsSection: startsSection, shortcut: shortcut,
            detail: detail, isDestructive: isDestructive,
            action: {
                close()
                action()
            })
    }
}
