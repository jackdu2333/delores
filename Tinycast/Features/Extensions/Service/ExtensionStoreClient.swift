import Foundation
import Synchronization

/// Merges every enabled registry; the store wins, because it is prebuilt.
struct ExtensionStoreClient: Sendable {
    /// Kept small: a GitHub registry reads one manifest per candidate.
    private static let githubCandidateLimit = 12

    /// Cacheless, never `URLSession.shared`, so a registry search leaves no second copy on disk.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private let session: URLSession
    /// Per client, so a second search reuses the tree the first one walked.
    private let folders = FolderCache()

    init(session: URLSession = ExtensionStoreClient.defaultSession) {
        self.session = session
    }

    // MARK: - Search

    /// The error rather than a throw, so one failing registry can't take the others' results.
    struct RegistryResult: Sendable {
        let registry: ExtensionRegistry
        let listings: [ExtensionListing]
        let failure: String?
    }

    func search(_ query: String, in registries: [ExtensionRegistry]) async -> [RegistryResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        return await withTaskGroup(of: RegistryResult.self) { group in
            for registry in registries where registry.isEnabled {
                group.addTask { await search(trimmed, in: registry) }
            }
            var results: [RegistryResult] = []
            for await result in group { results.append(result) }
            // Registry order, not completion order, so the list doesn't reshuffle between searches.
            return registries.compactMap { registry in
                results.first { $0.registry.id == registry.id }
            }
        }
    }

    private func search(_ query: String, in registry: ExtensionRegistry) async -> RegistryResult {
        do {
            let listings =
                switch registry.kind {
                case .raycastStore: try await searchStore(query, registry: registry)
                case .github: try await searchGitHub(query, registry: registry)
                }
            return RegistryResult(registry: registry, listings: listings, failure: nil)
        } catch {
            return RegistryResult(
                registry: registry, listings: [], failure: error.localizedDescription)
        }
    }

    private func searchStore(
        _ query: String, registry: ExtensionRegistry
    ) async throws
        -> [ExtensionListing]
    {
        guard let url = ExtensionStoreResponse.searchURL(query: query, page: 1) else {
            throw ExtensionStoreError.malformedResponse
        }
        let data = try await get(url)
        return try ExtensionStoreResponse.parseStore(data, registry: registry)
    }

    /// A registry has no search, so the listing is ranked here and only the best few are read.
    private func searchGitHub(
        _ query: String, registry: ExtensionRegistry
    ) async throws
        -> [ExtensionListing]
    {
        let folders = try await folderNames(in: registry)
        let folded = FuzzyMatch.Query(query)
        let ranked =
            folders
            .compactMap { folder -> (String, Int)? in
                guard let score = FuzzyMatch.score(folded, candidate: folder) else {
                    return nil
                }
                return (folder, score)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(Self.githubCandidateLimit)
            .map(\.0)

        return await withTaskGroup(of: ExtensionListing?.self) { group in
            for folder in ranked {
                group.addTask { await manifestListing(folder: folder, registry: registry) }
            }
            var listings: [ExtensionListing] = []
            for await listing in group {
                if let listing { listings.append(listing) }
            }
            // Back into rank order: the group finishes in whatever order the requests do.
            return ranked.compactMap { folder in
                listings.first { listing in
                    if case .githubFolder(_, _, let path, _) = listing.source {
                        return path.hasSuffix("/" + folder)
                    }
                    return false
                }
            }
        }
    }

    private func manifestListing(
        folder: String, registry: ExtensionRegistry
    ) async
        -> ExtensionListing?
    {
        let raw =
            "https://raw.githubusercontent.com/\(registry.owner)/\(registry.repository)"
            + "/\(registry.ref)/\(registry.path)/\(folder)/package.json"
        guard let url = URL(string: raw), let data = try? await get(url) else { return nil }
        return ExtensionStoreResponse.parseManifestSummary(
            data, folder: folder, registry: registry)
    }

    /// Trees, not contents: contents caps a directory at 1000 silently.
    private func folderNames(in registry: ExtensionRegistry) async throws -> [String] {
        if let cached = folders.names(for: registry.id) { return cached }

        let sha = try await treeSHA(
            owner: registry.owner, repository: registry.repository, path: registry.path,
            ref: registry.ref)
        guard
            let url = ExtensionStoreResponse.treeURL(
                owner: registry.owner, repository: registry.repository, sha: sha)
        else { throw ExtensionStoreError.malformedResponse }
        let names = try ExtensionStoreResponse.parseTree(try await get(url)).directoryNames
        folders.store(names, for: registry.id)
        return names
    }

    // MARK: - Fetching

    /// Never needed to build, and the heaviest thing in some extension folders.
    private static let skippedDirectories: Set<String> = ["node_modules", "metadata"]

    /// One recursive tree, then raw blobs: `contents` costs an API call per directory, and the
    /// anonymous budget is 60 an hour — an extension with 17 of them used to spend a third of it.
    func downloadFolder(
        owner: String, repository: String, path: String, ref: String, to destination: URL
    ) async throws -> String {
        // One commit for the whole download: a branch can move between two requests, and a tree from
        // one revision whose files come from another is not an install anyone can reproduce.
        let commit = try await commitSHA(owner: owner, repository: repository, ref: ref)
        let root = try await treeSHA(owner: owner, repository: repository, path: path, ref: commit)
        guard
            let url = ExtensionStoreResponse.treeURL(
                owner: owner, repository: repository, sha: root, recursive: true)
        else { throw ExtensionStoreError.malformedResponse }
        let tree = try ExtensionStoreResponse.parseTree(try await get(url))
        guard tree.truncated != true else {
            throw ExtensionStoreError.downloadFailed("\(path) is too large to download in one listing.")
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for entry in tree.tree where entry.isFile {
            let components = entry.path.split(separator: "/").map(String.init)
            guard !components.contains(where: Self.skippedDirectories.contains) else { continue }
            guard
                let raw = ExtensionStoreResponse.rawFileURL(
                    owner: owner, repository: repository, commit: commit,
                    path: "\(path)/\(entry.path)")
            else { continue }
            let target = components.reduce(destination) { $0.appendingPathComponent($1) }
            try fileManager.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await get(raw).write(to: target, options: .atomic)
            if entry.isExecutable {
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            }
        }
        return commit
    }

    /// Walks a path to the tree it names: the trees API takes a sha, and a ref only for the root.
    private func treeSHA(
        owner: String, repository: String, path: String, ref: String
    ) async throws -> String {
        var sha = ref
        for segment in path.split(separator: "/").map(String.init) {
            guard
                let url = ExtensionStoreResponse.treeURL(
                    owner: owner, repository: repository, sha: sha)
            else { throw ExtensionStoreError.malformedResponse }
            guard
                let next = try ExtensionStoreResponse.parseTree(try await get(url))
                    .directorySHA(named: segment)
            else {
                throw ExtensionStoreError.registryRejected(
                    "\(owner)/\(repository) has no \(path) directory on \(ref).")
            }
            sha = next
        }
        return sha
    }

    /// A branch or tag is a name that can move; an install is pinned to what it named just now.
    private func commitSHA(owner: String, repository: String, ref: String) async throws -> String {
        guard
            let url = ExtensionStoreResponse.commitURL(owner: owner, repository: repository, ref: ref)
        else { throw ExtensionStoreError.malformedResponse }
        return try ExtensionStoreResponse.parseCommit(try await get(url))
    }

    func download(_ url: URL) async throws -> Data {
        try await get(url)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        // GitHub serves the old media type without it, and rejects a request with no user agent.
        request.setValue("Tinycast", forHTTPHeaderField: "User-Agent")
        if url.host?.hasSuffix("api.github.com") == true {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            // GitHub explains a rate limit in the body; surfacing that beats a bare "403".
            struct Message: Decodable { let message: String }
            if let error = try? JSONDecoder().decode(Message.self, from: data) {
                throw ExtensionStoreError.registryRejected(error.message)
            }
            throw ExtensionStoreError.downloadFailed("HTTP \(http.statusCode)")
        }
        return data
    }
}

/// Re-fetching per keystroke spends GitHub's anonymous limit fast. One per client rather than one per
/// process: a lock suffices, because this is a memo and not a concurrency boundary.
private final class FolderCache: Sendable {
    private let cached = Mutex<[UUID: [String]]>([:])

    func names(for registry: UUID) -> [String]? { cached.withLock { $0[registry] } }
    func store(_ names: [String], for registry: UUID) { cached.withLock { $0[registry] = names } }
}
