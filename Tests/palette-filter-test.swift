import Foundation

/// ⌘P opens exactly one filter, and every other mode stays with the search field.
@main
@MainActor
struct PaletteFilterTests {
    static var failures = 0
    static var passes = 0

    static func expect(
        _ actual: PaletteFilterAction, _ expected: PaletteFilterAction, _ message: String
    ) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(actual), want \(expected)")
        }
    }

    static func resolve(collapsed: Bool = false, mode: PaletteMode) -> PaletteFilterAction {
        PaletteFilterAction.resolve(collapsed: collapsed, mode: mode)
    }

    static func main() {
        expect(
            resolve(mode: .clipboard), .clipboardFilter,
            "the clipboard's type filter is what ⌘P has always opened")
        expect(
            resolve(mode: .fileSearch), .fileSearchFilter,
            "file search has a header filter of its own")
        // Every other mode was untouched by ⌘P before and has to stay that way.
        for mode in [
            PaletteMode.launcher, .ai, .aiHistory, .calculatorHistory,
            .quicklinks, .menuSearch, .switchWindows, .uninstall
        ] {
            expect(
                resolve(mode: mode), .ignored,
                "\(mode.rawValue) has no header filter, so ⌘P stays with the field")
        }

        // Collapsed there is no header to hang a button off, so no filter may open.
        for mode in [PaletteMode.clipboard, .fileSearch, .launcher] {
            expect(
                resolve(collapsed: true, mode: mode), .ignored,
                "the compact bar draws no filter button, so ⌘P opens nothing on \(mode.rawValue)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
