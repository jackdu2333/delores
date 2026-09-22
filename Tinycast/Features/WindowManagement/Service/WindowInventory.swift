import AppKit

/// Lists external applications with user-facing windows for the window switcher.
@MainActor
enum WindowInventory {
    /// About flips the app to `.regular`, so exclude only this process itself.
    static func candidates() -> [NSRunningApplication] {
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated
                && $0.processIdentifier != ownPID
        }
    }
}
