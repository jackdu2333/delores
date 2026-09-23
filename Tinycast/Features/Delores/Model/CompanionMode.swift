/// Which desktop pet provides Delores' visual anchor.
///
/// The mode is deliberately one value rather than two switches: a future surface cannot start both
/// the native Delores pet and the Codex pet bridge by accident.
enum DeloresCompanionMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case delores
    case codex

    var id: String { rawValue }

    var usesDeloresPet: Bool { self == .delores }

    func allowsTopCenterSnapFallback(codexPetVisible: Bool) -> Bool {
        self != .codex || !codexPetVisible
    }
}
