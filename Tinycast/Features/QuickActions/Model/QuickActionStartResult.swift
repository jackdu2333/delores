enum QuickActionStartResult: Equatable, Sendable {
    case started
    case busy
    case disabled

    static func admission(enabled: Bool, isRunning: Bool) -> Self {
        guard enabled else { return .disabled }
        return isRunning ? .busy : .started
    }
}
