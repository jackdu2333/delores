import CoreGraphics
import Foundation

@main
struct DeloresContextTest {
    static func main() {
        testSelectionPolicy()
        testGesturePolicy()
        testPlacement()
        testInvocationContext()
        print("Delores context tests passed")
    }

    private static func testSelectionPolicy() {
        let prepared = require(
            DeloresSelectionContextPolicy.prepare("  hello  "),
            "selection is prepared")
        require(prepared.text == "hello", "selection trims surrounding whitespace")
        require(
            DeloresSelectionContextPolicy.isDuplicate(
                prepared.fingerprint,
                previous: prepared.fingerprint,
                elapsed: 0.2),
            "recent identical selection is deduplicated")
        require(
            !DeloresSelectionContextPolicy.isDuplicate(
                prepared.fingerprint,
                previous: prepared.fingerprint,
                elapsed: 0.5),
            "duplicate window is bounded")
        require(
            DeloresSelectionContextPolicy.prepare(" \n\t") == nil,
            "blank selection is ignored")

        let longText = String(repeating: "界", count: 20_000)
        let clipped = require(
            DeloresSelectionContextPolicy.prepare(longText),
            "long selection is clipped")
        require(clipped.text.utf8.count <= DeloresSelectionContextPolicy.maxInputBytes,
                "clipped selection stays within byte budget")
        require(clipped.text.last == "界", "clipping does not split a character")
        require(clipped.fingerprint.length == longText.count,
                "fingerprint keeps original length")
    }

    private static func testPlacement() {
        let screen = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876),
            menuBarFrame: CGRect(x: 0, y: 876, width: 1440, height: 24),
            auxiliaryTopRightArea: nil)
        let frame = DeloresContextIslandPlacement.frame(
            in: screen, size: CGSize(width: 420, height: 48))
        require(frame.midX == 720, "ordinary screens center the island")
        require(frame.maxY <= 900, "ordinary screen placement stays visible")

        let notchScreen = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 2000, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 2000, height: 876),
            menuBarFrame: CGRect(x: 0, y: 876, width: 2000, height: 24),
            auxiliaryTopRightArea: CGRect(x: 1400, y: 876, width: 300, height: 24))
        let notchFrame = DeloresContextIslandPlacement.frame(
            in: notchScreen, size: CGSize(width: 420, height: 48))
        require(notchFrame.minX == 1410, "notch screens anchor beside the right safe area")
    }

    private static func testGesturePolicy() {
        require(
            DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 8,
                previousReleaseDistance: nil,
                elapsedSincePreviousRelease: nil),
            "drag selection reaches its threshold")
        require(
            !DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 7.9,
                previousReleaseDistance: nil,
                elapsedSincePreviousRelease: nil),
            "ordinary click is ignored")
        require(
            DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 0,
                previousReleaseDistance: 4,
                elapsedSincePreviousRelease: 0.34),
            "double click selection is accepted")
        require(
            !DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 0,
                previousReleaseDistance: 4,
                elapsedSincePreviousRelease: 0.35),
            "late second click is ignored")
    }

    private static func testInvocationContext() {
        let target = InvocationApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.reader",
            displayName: "Reader")
        let screen = InvocationScreen(
            frame: .zero,
            visibleFrame: .zero,
            menuBarFrame: .zero,
            auxiliaryTopRightArea: nil)
        let context = InvocationContext.selection(
            SelectionInvocation(
                text: "source",
                targetApplication: target,
                screenPoint: CGPoint(x: 12, y: 24),
                screen: screen,
                timestamp: Date(timeIntervalSince1970: 1)))
        require(context.source == .selection, "selection context identifies its source")
        if case .selection(let selection) = context {
            require(selection.targetApplication == target, "selection keeps its target app")
        } else {
            fatalError("selection context changed case")
        }
    }

    private static func require<T>(_ value: T?, _ message: String) -> T {
        guard let value else { fatalError("FAIL: \(message)") }
        return value
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: \(message)") }
    }
}
