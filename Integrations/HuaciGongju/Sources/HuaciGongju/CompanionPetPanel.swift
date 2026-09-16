//
//  CompanionPetPanel.swift
//  HuaciGongju
//
//  桌宠身体：看见 28pt 玻璃圆，窗口热区 44pt。懒实体化，出厂不创建。
//

import Cocoa
import SwiftUI

public enum CompanionExpression: Equatable {
    case idle
    case glance
    case chat
}

public class CompanionPetViewModel: ObservableObject {
    @Published public var expression: CompanionExpression = .idle
    @Published public var isExpressing: Bool = false
    /// v1 换图槽：代码留着，设置里不露。
    @Published public var customImage: NSImage? = nil

    public var symbolName: String {
        switch expression {
        case .idle: return "sparkles"
        case .glance: return "eye"
        case .chat: return "bubble.left"
        }
    }
}

public struct CompanionPetContentView: View {
    @ObservedObject public var viewModel: CompanionPetViewModel
    @Environment(\.colorScheme) var colorScheme

    public init(viewModel: CompanionPetViewModel) {
        self.viewModel = viewModel
    }

    private var surfaceScrimOpacity: Double {
        colorScheme == .dark ? 0.36 : 0.30
    }

    public var body: some View {
        ZStack {
            NativeLiquidGlassView(
                cornerRadius: CompanionGeometry.visibleRadius,
                style: .regular,
                effectIsInteractive: true
            )
            Color(nsColor: .windowBackgroundColor)
                .opacity(surfaceScrimOpacity)
            Group {
                if let image = viewModel.customImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: viewModel.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
        }
        .frame(width: CompanionGeometry.visibleSize, height: CompanionGeometry.visibleSize)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(
                    Color.white.opacity(viewModel.isExpressing ? 0.55 : 0.18),
                    lineWidth: viewModel.isExpressing ? 1.4 : 0.6
                )
        )
        .frame(width: CompanionGeometry.hitSize, height: CompanionGeometry.hitSize)
    }
}

public class CompanionPetPanel: NSPanel {
    private static let storage = CompanionPetPanel()
    private static var hasMaterialized = false

    public static var isMaterialized: Bool { hasMaterialized }

    public static var shared: CompanionPetPanel {
        hasMaterialized = true
        return storage
    }

    public static var safeShared: CompanionPetPanel? {
        isMaterialized ? storage : nil
    }

    public let viewModel = CompanionPetViewModel()

    public var onSingleClick: (() -> Void)?
    public var onDoubleClick: (() -> Void)?
    public var onLongPress: (() -> Void)?
    public var onDragMoved: ((NSPoint) -> Void)?
    public var onDragEnded: ((NSPoint) -> Void)?

    private var longPressTimer: Timer?
    private var dragStarted = false
    private var mouseDownLocation: NSPoint = .zero
    private var expressionToken: Int = 0

    private init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: CompanionGeometry.hitSize,
                height: CompanionGeometry.hitSize
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.isMovableByWindowBackground = false
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.ignoresMouseEvents = true
        self.alphaValue = 1.0
        // 进程级单例：关窗不得释放；NSApp.hide（设置窗归还焦点）也不得把圆收走。
        self.isReleasedWhenClosed = false
        self.canHide = false

        let hostingView = FirstMouseHostingView(rootView: CompanionPetContentView(viewModel: viewModel))
        self.contentView = hostingView
    }

    public var petCenter: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    public func move(to center: CGPoint, display: Bool = true) {
        setFrame(CompanionGeometry.panelFrame(center: center), display: display)
    }

    public func present(at center: CGPoint) {
        move(to: center, display: false)
        alphaValue = 1.0
        orderFrontRegardless()
    }

    public func hide() {
        orderOut(nil)
        cancelLongPress()
        dragStarted = false
    }

    public func setClickThrough(_ enabled: Bool) {
        ignoresMouseEvents = enabled
    }

    public func playExpression(_ expression: CompanionExpression, duration: TimeInterval = 0.8) {
        expressionToken += 1
        let token = expressionToken
        viewModel.expression = expression
        withAnimation(.easeInOut(duration: 0.12)) {
            viewModel.isExpressing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self.expressionToken == token else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                self.viewModel.isExpressing = false
                self.viewModel.expression = .idle
            }
        }
    }

    public override func mouseDown(with event: NSEvent) {
        dragStarted = false
        mouseDownLocation = NSEvent.mouseLocation
        cancelLongPress()
        longPressTimer = Timer.scheduledTimer(
            withTimeInterval: CompanionGeometry.longPressDuration,
            repeats: false
        ) { [weak self] _ in
            guard let self = self, !self.dragStarted else { return }
            self.onLongPress?()
        }
        if let timer = longPressTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        let loc = NSEvent.mouseLocation
        if hypot(loc.x - mouseDownLocation.x, loc.y - mouseDownLocation.y) >= 4 {
            dragStarted = true
            cancelLongPress()
            move(to: loc)
            onDragMoved?(loc)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        cancelLongPress()
        let loc = NSEvent.mouseLocation
        if dragStarted {
            onDragEnded?(loc)
            dragStarted = false
            return
        }
        if event.clickCount >= 2 {
            onDoubleClick?()
        } else {
            onSingleClick?()
        }
    }

    private func cancelLongPress() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }
}

public class CompanionChatBubblePanel: NSPanel {
    private static let storage = CompanionChatBubblePanel()
    private static var hasMaterialized = false

    public static var isMaterialized: Bool { hasMaterialized }

    public static var shared: CompanionChatBubblePanel {
        hasMaterialized = true
        return storage
    }

    public static var safeShared: CompanionChatBubblePanel? {
        isMaterialized ? storage : nil
    }

    public static let placeholderText = "对话即将到来"

    private init() {
        let size = CompanionGeometry.chatBubbleSize
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .popUpMenu
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = false
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false
        self.canHide = false

        let view = CompanionChatBubbleView()
        self.contentView = FirstMouseHostingView(rootView: view)
    }

    public func show(at frame: NSRect) {
        setFrame(frame, display: true)
        alphaValue = 1.0
        orderFrontRegardless()
    }

    public func hide() {
        orderOut(nil)
    }
}

private struct CompanionChatBubbleView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(CompanionChatBubblePanel.placeholderText)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .frame(
                width: CompanionGeometry.chatBubbleSize.width,
                height: CompanionGeometry.chatBubbleSize.height
            )
            .background(
                ZStack {
                    NativeLiquidGlassView(cornerRadius: 16, style: .regular)
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.36 : 0.30)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
