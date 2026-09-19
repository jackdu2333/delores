import Foundation

/// The per-channel storage roots. Keyed by bundle id so a Dev build never shares a stable's dirs.
enum AppPaths {
    static func caches(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
    ) -> URL {
        root(.cachesDirectory, bundleID: bundleID)
    }

    static func applicationSupport(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
    ) -> URL {
        root(.applicationSupportDirectory, bundleID: bundleID)
    }

    /// Where Notes lives until a folder of the person's own is chosen. The default stays inside the
    /// per-channel support root, so it is still a Dev build's own folder and not a stable's.
    static func defaultNotesDirectory(
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.tinycast.app"
    ) -> URL {
        applicationSupport(bundleID: bundleID).appendingPathComponent("Notes", isDirectory: true)
    }

    /// Where Notes lives: the folder the setting names, or the per-channel default when it names none.
    static func notesDirectory(chosenPath: String) -> URL {
        chosenPath.isEmpty
            ? defaultNotesDirectory() : URL(fileURLWithPath: chosenPath, isDirectory: true)
    }

    private static func root(
        _ directory: FileManager.SearchPathDirectory, bundleID: String
    ) -> URL {
        let url = FileManager.default
            .urls(for: directory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
