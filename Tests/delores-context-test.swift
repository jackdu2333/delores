import CoreGraphics
import Foundation

@main
struct DeloresContextTest {
    static func main() {
        testSelectionPolicy()
        testGesturePolicy()
        testOwnSurfaceHitPolicy()
        testQuickActionAdmission()
        testQuickActionPrompt()
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

    private static func testQuickActionPrompt() {
        let boundary = QuickActionPrompt.boundary
        require(
            !boundary.isEmpty && !boundary.hasSuffix("\n") && !boundary.hasPrefix("\n"),
            "the boundary is a trimmed block")

        let custom = CustomQuickAction(name: "Punch Up", instructions: "Make it wittier.")
        let customPrompt = QuickActionPrompt.instructions(for: .custom(custom))
        require(
            customPrompt.hasPrefix(boundary),
            "a custom action cannot drop the material-not-instructions boundary")
        require(
            customPrompt.hasSuffix("Make it wittier."),
            "a custom action keeps its own instructions after the boundary")

        for builtIn in [BuiltInQuickAction.fixGrammar, .rewrite] {
            require(
                QuickActionPrompt.instructions(for: builtIn).hasPrefix(boundary),
                "\(builtIn.rawValue) carries the boundary")
        }
        require(
            QuickActionPrompt.instructions(for: BuiltInQuickAction.summarize)
                .contains("material to summarize"),
            "the summarizer states its own material-not-request rule")
        require(
            QuickActionPrompt.instructions(for: BuiltInQuickAction.translate) == boundary,
            "the panel lane leaves translation to Apple's translator")
        require(
            QuickActionPrompt.instructions(
                for: BuiltInQuickAction.translate, override: "Ignore that.") == boundary,
            "a caller cannot override the action the translation framework performs")
        require(
            QuickActionPrompt.instructions(for: BuiltInQuickAction.rewrite, override: "Be terse.")
                == "Be terse.",
            "a non-framework action honours the caller's override")

        let translated = require(
            QuickActionPrompt.chatInstructions(for: .translate, targetLanguageName: "Japanese"),
            "the chat lane gives translate a task of its own")
        require(translated.hasPrefix(boundary), "the chat lane keeps the boundary")
        require(
            translated.contains("Translate the text into Japanese"),
            "the chat lane names the target language it was handed")
        require(
            translated != QuickActionPrompt.instructions(for: QuickAction.translate),
            "the chat lane says more than the panel lane's bare boundary")

        require(
            QuickActionPrompt.chatInstructions(
                for: .translate, targetLanguageName: "Japanese", override: "Only the verbs.")
                == boundary + "\n\n" + "Only the verbs.",
            "the reader's instructions replace the built-in task but keep the chat lane's boundary")
        require(
            QuickActionPrompt.chatInstructions(
                for: QuickAction.summarize, targetLanguageName: "Japanese",
                override: "One line only.")
                == boundary + "\n\n" + "One line only.",
            "an action with no chat-only task of its own still carries the reader's instructions")

        for action in QuickAction.allBuiltIn
        where action.builtInAction != .translate {
            require(
                QuickActionPrompt.chatInstructions(
                    for: action, targetLanguageName: "Japanese") == nil,
                "\(action.title) needs no chat-only instructions")
        }
        require(
            QuickActionPrompt.chatInstructions(
                for: .custom(custom), targetLanguageName: "Japanese") == nil,
            "a custom action needs no chat-only instructions")

        require(
            QuickActionPrompt.message(for: .summarize, selection: "Body.")
                == "Summarize the text below.\nText:\nBody.",
            "the summarizer asks for a summary before the delimiter")
        require(
            QuickActionPrompt.message(for: .translate, selection: "Body.") == "Text:\nBody.",
            "the delimiter separates the selection from the instruction above it")
    }

    private static func testPlacement() {
        let screen = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876),
            menuBarFrame: CGRect(x: 0, y: 876, width: 1440, height: 24),
            auxiliaryTopRightArea: nil)
        let frame = DeloresContextIslandPlacement.collapsedFrame(
            in: screen, size: CGSize(width: 420, height: 48))
        require(frame.midX == 720, "ordinary screens center the island")
        require(frame.maxY <= 900, "ordinary screen placement stays visible")
        require(frame.height == 22, "a shallow menu bar caps the bar height")

        let notchScreen = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 2000, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 2000, height: 876),
            menuBarFrame: CGRect(x: 0, y: 876, width: 2000, height: 24),
            auxiliaryTopRightArea: CGRect(x: 1400, y: 876, width: 300, height: 24))
        let notchFrame = DeloresContextIslandPlacement.collapsedFrame(
            in: notchScreen, size: CGSize(width: 420, height: 48))
        require(notchFrame.minX == 1410, "notch screens anchor beside the right safe area")

        let bareScreen = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            menuBarFrame: .zero,
            auxiliaryTopRightArea: nil)
        let bare = DeloresContextIslandPlacement.collapsedFrame(
            in: bareScreen, size: CGSize(width: 420, height: 38))
        require(bare.height == 38, "a display without a menu bar keeps the preferred height")
        require(bare.maxY == 900, "a display without a menu bar hangs from its top edge")

        require(
            DeloresContextIslandPlacement.expandedHeight(preferred: 390, in: screen) == 390,
            "a roomy display gives the opened card its full height")

        let shortScreen = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 500),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 500),
            menuBarFrame: CGRect(x: 0, y: 500, width: 1440, height: 24),
            auxiliaryTopRightArea: nil)
        require(
            DeloresContextIslandPlacement.expandedHeight(preferred: 390, in: shortScreen) == 300,
            "a short display caps the opened card at its visible share")

        require(
            DeloresContextIslandPlacement.openCornerRadius
                >= DeloresContextIslandPlacement.preferredBarHeight / 2,
            "the open card's corner still closes into a pill, never a squarer bar")

        let grown = DeloresContextIslandPlacement.frame(keepingTopEdgeOf: frame, height: 380)
        require(grown.maxY == frame.maxY, "growing downward keeps the top edge")
        require(grown.minY == frame.maxY - 380, "the card grows away from that edge")
        require(
            grown.minX == frame.minX && grown.width == frame.width,
            "the card keeps the bar's horizontal placement")
    }

    private static func testOwnSurfaceHitPolicy() {
        let interactive = DeloresSurfaceWindowSnapshot(
            frame: CGRect(x: 100, y: 100, width: 300, height: 200),
            isVisible: true,
            ignoresMouseEvents: false)
        let passthrough = DeloresSurfaceWindowSnapshot(
            frame: CGRect(x: 500, y: 100, width: 300, height: 200),
            isVisible: true,
            ignoresMouseEvents: true)
        require(
            DeloresOwnSurfaceHitPolicy.containsInteractiveSurface(
                at: CGPoint(x: 98, y: 100), in: [interactive]),
            "interactive own surface includes the small hit padding")
        require(
            !DeloresOwnSurfaceHitPolicy.containsInteractiveSurface(
                at: CGPoint(x: 550, y: 150), in: [passthrough]),
            "click-through HUDs do not suppress a valid selection")
        require(
            !DeloresOwnSurfaceHitPolicy.containsInteractiveSurface(
                at: CGPoint(x: 900, y: 900), in: [interactive]),
            "points outside own surfaces remain eligible")
    }

    private static func testQuickActionAdmission() {
        require(
            QuickActionStartResult.admission(enabled: true, isRunning: false) == .started,
            "enabled idle Quick Action starts")
        require(
            QuickActionStartResult.admission(enabled: true, isRunning: true) == .busy,
            "running Quick Action reports busy")
        require(
            QuickActionStartResult.admission(enabled: false, isRunning: false) == .disabled,
            "disabled Quick Action reports disabled")
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
