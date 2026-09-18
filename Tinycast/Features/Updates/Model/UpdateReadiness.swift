import Foundation

/// What the app is in the middle of. Every flag is injected, so the decision stays pure.
struct UpdateActivity: Sendable {
    var isUninstalling = false
    var isRecordingHotKey = false
    var isPromptingForArguments = false
    var isShowingDialog = false
    var isPaletteVisible = false
}

/// Whether it is safe to interrupt the user and swap the app out from under them.
enum UpdateReadiness {
    enum Blocker: Equatable, Sendable {
        case uninstalling
        case recordingHotKey
        case promptingForArguments
        case dialogOpen
        case paletteOpen

        var message: String {
            switch self {
            case .uninstalling: return "Waiting for the uninstaller to finish."
            case .recordingHotKey: return "Finish recording the shortcut first."
            case .promptingForArguments: return "Finish the open command prompt first."
            case .dialogOpen: return "Close the open dialog first."
            case .paletteOpen: return "Close Tinycast's window first."
            }
        }
    }

    /// Ordered by consequence: an interrupted install loses work, an open panel does not.
    static func evaluate(_ activity: UpdateActivity) -> Blocker? {
        if activity.isUninstalling { return .uninstalling }
        if activity.isRecordingHotKey { return .recordingHotKey }
        if activity.isPromptingForArguments { return .promptingForArguments }
        if activity.isShowingDialog { return .dialogOpen }
        if activity.isPaletteVisible { return .paletteOpen }
        return nil
    }
}
