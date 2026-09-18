import Foundation

/// Both are other people's endpoints, so every field an install doesn't need is optional.
enum ExtensionStoreResponse {

    // MARK: - Raycast's store

    /// The endpoint the store's own website searches with. Unofficial, hence the GitHub fallback.
    static func searchURL(query: String, page: Int) -> URL? {
        var components = URLComponents(string: "https://www.raycast.com/frontend_api/extensions/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            // Case-sensitive: any other spelling returns only extensions listing no platforms.
            URLQueryItem(name: "platform", value: "macOS")
        ]
        return components?.url
    }

    private struct StorePayload: Decodable {
        let data: [StoreEntry]
    }

    private struct StoreEntry: Decodable {
        let id: String
        let name: String
        let title: String?
        let description: String?
        let author: Author?
        let icons: Icons?
        let commands: [Command]?
        let downloadCount: Int?
        let downloadURL: String?
        let commitSha: String?
        let relativePath: String?
        let status: String?

        struct Author: Decodable {
            let name: String?
            let handle: String?
        }
        struct Icons: Decodable {
            let light: String?
            let dark: String?
        }
        struct Command: Decodable {
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id, name, title, description, author, icons, commands, status
            case downloadCount = "download_count"
            case downloadURL = "download_url"
            case commitSha = "commit_sha"
            case relativePath = "relative_path"
        }
    }

    /// An entry without a usable download is dropped, not listed as uninstallable.
    static func parseStore(_ data: Data, registry: ExtensionRegistry) throws -> [ExtensionListing] {
        let payload = try JSONDecoder().decode(StorePayload.self, from: data)
        return payload.data.compactMap { entry -> ExtensionListing? in
            // A de-listed extension is still returned by search; it can't be downloaded any more.
            guard entry.status == nil || entry.status == "active" else { return nil }
            guard let raw = entry.downloadURL, let url = URL(string: raw) else { return nil }
            return ExtensionListing(
                id: entry.id,
                name: entry.name,
                title: entry.title ?? entry.name,
                summary: entry.description ?? "",
                author: entry.author?.name ?? entry.author?.handle ?? "",
                lightIconURL: entry.icons?.light.flatMap(URL.init(string:)),
                darkIconURL: entry.icons?.dark.flatMap(URL.init(string:)),
                commandCount: entry.commands?.count ?? 0,
                downloadCount: entry.downloadCount,
                registryID: registry.id,
                registryName: registry.name,
                source: .prebuiltZip(url))
        }
    }

    // MARK: - A GitHub registry

    static func treeURL(
        owner: String, repository: String, sha: String, recursive: Bool = false
    ) -> URL? {
        var components = URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repository)/git/trees/\(sha)")
        if recursive { components?.queryItems = [URLQueryItem(name: "recursive", value: "1")] }
        return components?.url
    }

    /// What a registry's ref named when the install started. A branch is a moving name, so reading
    /// the tree at one revision and the files at another is not an install anyone can reproduce.
    static func commitURL(owner: String, repository: String, ref: String) -> URL? {
        URLComponents(
            string: "https://api.github.com/repos/\(owner)/\(repository)/commits/\(escapedRef(ref))"
        )?.url
    }

    /// GitHub reads a slash in a ref as another path segment, so refs like feature/x arrive encoded.
    static func escapedRef(_ ref: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return ref.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ref
    }

    /// A ref resolved to the commit it names.
    struct GitCommit: Decodable, Sendable {
        let sha: String
    }

    /// The commit a ref resolves to, or a thrown message when GitHub answered with an error instead.
    static func parseCommit(_ data: Data) throws -> String {
        if let commit = try? JSONDecoder().decode(GitCommit.self, from: data), !commit.sha.isEmpty {
            return commit.sha
        }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.registryRejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }

    /// One file of a resolved commit: a tree says a path exists, this says what it holds.
    static func rawFileURL(owner: String, repository: String, commit: String, path: String) -> URL? {
        let escaped =
            "\(owner)/\(repository)/\(commit)/\(path)"
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let escaped else { return nil }
        return URL(string: "https://raw.githubusercontent.com/\(escaped)")
    }

    /// A Git tree: what a directory holds, by sha rather than by path.
    struct GitTree: Decodable, Sendable {
        let tree: [Entry]
        /// Set when GitHub gave up listing: what came back is a prefix, not the whole directory.
        let truncated: Bool?

        struct Entry: Decodable, Sendable {
            let path: String
            let type: String
            let sha: String
            let mode: String?

            var isDirectory: Bool { type == "tree" }
            var isFile: Bool { type == "blob" }
            var isExecutable: Bool { isFile && mode == "100755" }
        }

        func directorySHA(named name: String) -> String? {
            tree.first { $0.path == name && $0.isDirectory }?.sha
        }

        var directoryNames: [String] { tree.filter(\.isDirectory).map(\.path) }
    }

    /// A tree listing, or a thrown message when GitHub answered with an error instead.
    static func parseTree(_ data: Data) throws -> GitTree {
        if let tree = try? JSONDecoder().decode(GitTree.self, from: data) { return tree }
        struct Message: Decodable { let message: String }
        if let error = try? JSONDecoder().decode(Message.self, from: data) {
            throw ExtensionStoreError.registryRejected(error.message)
        }
        throw ExtensionStoreError.malformedResponse
    }

    /// The parts of `package.json` a listing shows, read from the repository.
    static func parseManifestSummary(
        _ data: Data, folder: String, registry: ExtensionRegistry
    ) -> ExtensionListing? {
        struct Manifest: Decodable {
            let name: String?
            let title: String?
            let description: String?
            let author: String?
            let icon: String?
            let commands: [Command]?
            struct Command: Decodable { let name: String? }
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            let name = manifest.name ?? manifest.title
        else { return nil }
        // One artwork per manifest, so both appearances resolve to it.
        let manifestIcon = manifest.icon.flatMap {
            URL(
                string:
                    "https://raw.githubusercontent.com/\(registry.owner)/\(registry.repository)"
                    + "/\(registry.ref)/\(registry.path)/\(folder)/assets/\($0)")
        }
        return ExtensionListing(
            id: "\(registry.id.uuidString)/\(folder)",
            name: name,
            title: manifest.title ?? name,
            summary: manifest.description ?? "",
            author: manifest.author ?? "",
            lightIconURL: manifestIcon,
            darkIconURL: manifestIcon,
            commandCount: manifest.commands?.count ?? 0,
            downloadCount: nil,
            registryID: registry.id,
            registryName: registry.name,
            source: .githubFolder(
                owner: registry.owner, repository: registry.repository,
                path: "\(registry.path)/\(folder)", ref: registry.ref))
    }
}

enum ExtensionStoreError: LocalizedError {
    case malformedResponse
    case registryRejected(String)
    case downloadFailed(String)
    case noPackageManager
    case noNode
    case buildFailed(String)
    case notAnExtension

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "The registry answered with something this version doesn't understand."
        case .registryRejected(let message):
            return message
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .noPackageManager:
            return
                "This extension is source that has to be built, and no package manager was found. "
                + "Install pnpm, npm, Yarn or Bun, or pick one in Advanced."
        case .noNode:
            return
                "This extension is source that has to be built, and Node wasn't found. Install "
                + "Node.js, or install this extension from the Raycast Store instead."
        case .buildFailed(let output):
            return "The extension didn't build: \(output)"
        case .notAnExtension:
            return "That download didn't contain a Raycast extension."
        }
    }
}
