import Foundation

/// Where a GitHub install came from, pinned to the commit it was built from.
///
/// A registry's ref is usually a branch, so the name alone says nothing about what is installed a
/// week later. The commit is the part that answers what is actually running.
struct ExtensionInstallProvenance: Codable, Sendable, Hashable {
    let owner: String
    let repository: String
    let path: String
    /// What the registry asked for, kept so the resolved commit can be read as a change.
    let requestedRef: String
    let commit: String

    /// Dot-prefixed, so nothing that reads an extension's own files mistakes it for one of them.
    static let fileName = ".install-provenance.json"
}
