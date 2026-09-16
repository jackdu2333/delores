import CoreGraphics
import Foundation

enum InvocationSource: String, Sendable {
    case command
    case selection
    case windowDrag
    case menuBar
}

struct InvocationApplication: Equatable, Hashable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    let displayName: String?
}

struct InvocationWindow: Equatable, Hashable, Sendable {
    let processIdentifier: Int32
    let title: String?
}

struct InvocationScreen: Equatable, Sendable {
    let frame: CGRect
    let visibleFrame: CGRect
    let menuBarFrame: CGRect
    let auxiliaryTopRightArea: CGRect?
}

struct CommandInvocation: Equatable, Sendable {
    let targetApplication: InvocationApplication?
    let timestamp: Date
}

struct SelectionInvocation: Equatable, Sendable {
    let text: String
    let targetApplication: InvocationApplication
    let screenPoint: CGPoint
    let screen: InvocationScreen
    let timestamp: Date
}

struct WindowInvocation: Equatable, Sendable {
    let targetWindow: InvocationWindow
    let screenPoint: CGPoint
    let timestamp: Date
}

struct MenuBarInvocation: Equatable, Sendable {
    let timestamp: Date
}

enum InvocationContext: Equatable, Sendable {
    case command(CommandInvocation)
    case selection(SelectionInvocation)
    case windowDrag(WindowInvocation)
    case menuBar(MenuBarInvocation)

    var source: InvocationSource {
        switch self {
        case .command: return .command
        case .selection: return .selection
        case .windowDrag: return .windowDrag
        case .menuBar: return .menuBar
        }
    }
}
