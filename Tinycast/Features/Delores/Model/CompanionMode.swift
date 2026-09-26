/// Which desktop pet provides Delores' visual anchor.
///
/// The mode is deliberately one value rather than two switches: a future surface cannot start both
/// the native Delores pet and the Codex pet bridge by accident.
enum DeloresCompanionMode: String, CaseIterable, Identifiable, Sendable {
    case off
    case automatic
    case delores
    case codex

    var id: String { rawValue }

    var usesDeloresPet: Bool { self == .delores }

    func resolved(codexPetEnabled: Bool) -> Self {
        guard self == .automatic else { return self }
        return codexPetEnabled ? .codex : .delores
    }
}
