import CoreGraphics
import Foundation

@main
struct DeloresContextTest {
    static func main() {
        testSelectionPolicy()
        testAnswerAccumulator()
        testGesturePolicy()
        testOwnSurfaceHitPolicy()
        MainActor.assumeIsolated { testSurfaceInteractionGate() }
        testQuickActionAdmission()
        testContextActions()
        testCustomRowsOnTheBar()
        testContextActionPrompts()
        testSearchURL()
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

    private static func testContextActions() {
        let actions = DeloresContextAction.catalog
        require(
            actions.map(\.id) == ["translate", "explain", "summarize", "search"],
            "the catalog is the four the reader asked for, in order")
        require(
            actions.allSatisfy { !$0.requiresChatHandoff },
            "no bar action escalates to chat on its own")
        require(
            actions.allSatisfy { !$0.title.isEmpty },
            "every action carries a title for its pill")

        require(actions.allSatisfy(\.isEnabled), "every default action is switched on")

        require(
            DeloresContextAction.available(aiEnabled: true).count == actions.count,
            "AI on exposes the whole catalog")
        require(
            DeloresContextAction.available(aiEnabled: false).map(\.id) == ["search"],
            "AI off leaves the one action that never needed a model")

        // Only the two that rewrite carry the flag. 解释 answering without being told to skip
        // commentary is the whole difference it exists for.
        require(
            actions.filter(\.rewritesSelection).map(\.id) == ["translate", "summarize"],
            "the rewriting actions are the two that can write back")

        // 问 AI left the catalog as a duplicate of 解释, but the hand-off it used is still the only
        // way the island reaches Chat, so the kind has to keep behaving for whatever row brings it
        // back.
        let handOff = DeloresContextAction(
            id: "ask", title: "问 AI", symbol: "sparkles", kind: .ask, prompt: "",
            rewritesSelection: false)
        require(handOff.requiresChatHandoff, "the chat hand-off kind still declares itself")
        require(handOff.needsModel, "a hand-off action still needs a model to answer it")
        require(
            handOff.progressTitle == "正在打开 AI 对话",
            "the hand-off card says what it is doing rather than naming the action")
    }

    private static func testCustomRowsOnTheBar() {
        let row = CustomQuickAction(name: "起标题", instructions: "为这段内容起五个标题")
        require(row.symbol == CustomQuickAction.sfSymbol, "a row without an icon takes the default")

        let withRow = DeloresContextAction.available(aiEnabled: true, customActions: [row])
        require(withRow.count == 5, "a row written in Settings joins the four Delores ships")
        require(withRow.last?.id == row.entryID, "the row keeps the id its model binding hangs from")
        require(withRow.last?.title == "起标题", "the row keeps its own title")
        require(
            withRow.last?.rewritesSelection == false,
            "a row the reader wrote does not take their document unasked")
        require(withRow.last?.maxOutputTokens(selection: "x") == 128,
                "a custom row answers at the same floor as any other model action")

        require(
            DeloresContextAction.available(aiEnabled: false, customActions: [row]).map(\.id)
                == ["search"],
            "AI off leaves search alone: a custom row is a prompt by definition")

        let explained = DeloresContextAction(id: "summarize", title: "总结", symbol: "s", kind: .ai,
                                            prompt: "ships with the app")
        require(
            explained.applying("按三点概括").prompt == "按三点概括",
            "a prompt replaced in Settings reaches the bar")
        require(
            explained.applying(nil).prompt == "ships with the app",
            "an untouched action keeps its shipped prompt")
        require(
            explained.applying("   ").prompt == "ships with the app",
            "a blank replacement is not a replacement")
        require(
            explained.applying("按三点概括").id == "summarize",
            "applying a prompt does not move the binding it is keyed by")
    }

    private static func testContextActionPrompts() {
        let translate = require(
            DeloresContextAction.catalog.first { $0.id == "translate" }, "translate is in the catalog")
        require(
            translate.instructions.hasPrefix(DeloresContextAction.materialRule),
            "an action is always sent the material-not-instructions rule")
        require(
            translate.instructions.contains(DeloresContextAction.bareOutputRule),
            "a rewriting action is sent the bare-output rule")
        require(
            translate.instructions.hasSuffix(translate.prompt) && !translate.prompt.isEmpty,
            "the reader's own prompt comes last and is not reworded")
        require(
            translate.prompt.contains("绝对严禁输出英文或复读原文"),
            "the toolbar's anti-repetition rule survives verbatim")
        require(
            translate.prompt.contains("LLMService"),
            "the toolbar's treatment of code identifiers survives verbatim")

        let explain = require(
            DeloresContextAction.catalog.first { $0.id == "explain" }, "explain is in the catalog")
        require(
            !explain.instructions.contains(DeloresContextAction.bareOutputRule),
            "an action that answers is not told to skip explaining")
        require(
            explain.instructions.contains(DeloresContextAction.materialRule),
            "an answering action still treats the selection as material")

        require(
            translate.message(selection: "Body.") == "Text:\nBody.",
            "the delimiter separates the selection from the instruction above it")

        let search = require(
            DeloresContextAction.catalog.first { $0.id == "search" }, "search is in the catalog")
        require(search.instructions == "", "a search action sends no instructions")

        require(
            translate.maxOutputTokens(selection: "short") == 128,
            "a tiny selection still gets room for a reply")
        require(
            translate.maxOutputTokens(selection: String(repeating: "a", count: 9_000)) == 2_048,
            "a long selection cannot lift the ceiling past the route's window")
    }

    private static func testSearchURL() {
        let search = require(
            DeloresContextAction.catalog.first { $0.id == "search" }, "search is in the catalog")
        require(
            search.searchURL(selection: "hello world")?.absoluteString
                == "https://www.bing.com/search?q=hello%20world",
            "a space is encoded rather than left to the engine")
        require(
            search.searchURL(selection: "a+b&c=d")?.absoluteString
                == "https://www.bing.com/search?q=a%2Bb%26c%3Dd",
            "a plus and an ampersand are encoded, so they stay part of what the reader selected")
        require(
            search.searchURL(selection: "中文")?.absoluteString
                == "https://www.bing.com/search?q=%E4%B8%AD%E6%96%87",
            "a non-ASCII selection is percent-encoded")

        let translate = require(
            DeloresContextAction.catalog.first { $0.id == "translate" },
            "translate is in the catalog")
        require(
            translate.searchURL(selection: "x") == nil,
            "an action that calls a model has no search address")
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

        testBarWidth(screen: screen)
        testCardPlacement(screen: screen)
        testPinnedBarRow(screen: screen)
    }

    /// The bar's row never moves. The panel is what widens, and the controls a card adds spill into
    /// the width it gained rather than pushing the catalog along.
    ///
    /// This is an invariant rather than a measurement: the row is drawn at the width the bar had
    /// while collapsed, and the panel is centred, so the row's left edge is a function of the bar
    /// alone. If a future state lets the row grow with its own controls, the pill under the reader's
    /// pointer moves the moment they press it — which is the bug this locks out.
    private static func testPinnedBarRow(screen: InvocationScreen) {
        let pinned: CGFloat = 300
        let collapsed = DeloresContextIslandPlacement.collapsedFrame(
            in: screen, size: CGSize(width: pinned, height: 48))
        let opened = DeloresContextIslandPlacement.expandedFrame(
            keepingTopEdgeOf: collapsed, size: CGSize(width: 420, height: 380), in: screen)

        let rowWhenBarred = DeloresContextIslandPlacement.pinnedRowFrame(
            in: collapsed, pinned: pinned)
        let rowWhenOpen = DeloresContextIslandPlacement.pinnedRowFrame(in: opened, pinned: pinned)
        require(
            rowWhenOpen.minX == rowWhenBarred.minX,
            "the pinned row keeps the bar's left edge once the panel widens")
        require(
            rowWhenBarred.minX == collapsed.minX,
            "a bar that fills its own panel starts at that panel's edge")
        require(rowWhenOpen.width == pinned, "the row keeps the bar's width, not the panel's")

        // The spill is the row's growth, and the room for it is twice that: half of every point the
        // panel gains lands on the empty side of the centred row.
        require(
            DeloresContextIslandPlacement.vesselWidth(row: pinned, pinned: pinned, in: screen)
                == pinned,
            "a row the bar's own width needs no room to spill into")
        require(
            DeloresContextIslandPlacement.vesselWidth(row: pinned + 40, pinned: pinned, in: screen)
                == pinned + 80,
            "a row that grew by forty needs eighty more panel")
        require(
            DeloresContextIslandPlacement.vesselWidth(row: pinned + 40, pinned: 0, in: screen)
                == pinned + 40,
            "an unmeasured bar is not asked for room it never claimed")
        require(
            DeloresContextIslandPlacement.vesselWidth(row: 4_000, pinned: pinned, in: screen)
                == screen.frame.width - DeloresContextIslandPlacement.margin * 2,
            "the display wins over a row too wide to hold")
    }

    /// A card is wider than the bar it grows out of, and a card that kept the bar's left edge would
    /// sit visibly off centre on a display the bar was centred on.
    private static func testCardPlacement(screen: InvocationScreen) {
        let bar = DeloresContextIslandPlacement.collapsedFrame(
            in: screen, size: CGSize(width: 420, height: 48))

        require(
            DeloresContextIslandPlacement.resultWidth(barWidth: 300, in: screen)
                == DeloresContextIslandPlacement.minimumReadingWidth,
            "a bar narrower than a readable column is widened to one")
        require(
            DeloresContextIslandPlacement.resultWidth(barWidth: 520, in: screen) == 520,
            "a bar already wider than the column keeps its own width")

        let sameWidth = DeloresContextIslandPlacement.expandedFrame(
            keepingTopEdgeOf: bar, size: CGSize(width: 420, height: 380), in: screen)
        require(sameWidth.maxY == bar.maxY, "the card grows away from the bar's top edge")
        require(sameWidth.minX == bar.minX, "a card the bar's own width keeps the bar's placement")

        let wider = DeloresContextIslandPlacement.expandedFrame(
            keepingTopEdgeOf: bar, size: CGSize(width: 520, height: 380), in: screen)
        require(wider.midX == bar.midX, "a wider card stays centred on the display the bar sits on")
        require(wider.height == 380, "a card is not capped to the menu bar the way the bar is")

        let narrow = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 300, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 876),
            menuBarFrame: CGRect(x: 0, y: 876, width: 300, height: 24),
            auxiliaryTopRightArea: nil)
        require(
            DeloresContextIslandPlacement.resultWidth(barWidth: 280, in: narrow) == 280,
            "a display too narrow for a reading column keeps the bar's own width")
    }

    /// The bar measures itself against a hosting view, and a hosting view that has not laid out
    /// reports zero — so the fallback is the ordinary path on the first frame, not an edge case.
    private static func testBarWidth(screen: InvocationScreen) {
        require(
            DeloresContextIslandPlacement.collapsedHeight(preferred: 38, in: screen) == 22,
            "the bar lays out against the height it is given, not the one it asked for")

        require(
            DeloresContextIslandPlacement.barWidth(hugging: 0, in: screen)
                == DeloresContextIslandPlacement.preferredWidth,
            "an unmeasured bar falls back to the preferred width instead of clipping")
        require(
            DeloresContextIslandPlacement.barWidth(hugging: .nan, in: screen)
                == DeloresContextIslandPlacement.preferredWidth,
            "a nonsense measurement falls back the same way")
        require(
            DeloresContextIslandPlacement.barWidth(hugging: .infinity, in: screen)
                == DeloresContextIslandPlacement.preferredWidth,
            "an unbounded measurement falls back the same way")
        require(
            DeloresContextIslandPlacement.barWidth(hugging: 300, in: screen) == 300,
            "a real measurement is used as it stands")
        require(
            DeloresContextIslandPlacement.barWidth(hugging: 1_200, in: screen) == 1_200,
            "a long catalog widens the bar past the preferred width rather than crushing it")

        let narrow = InvocationScreen(
            frame: CGRect(x: 0, y: 0, width: 300, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 876),
            menuBarFrame: CGRect(x: 0, y: 876, width: 300, height: 24),
            auxiliaryTopRightArea: nil)
        require(
            DeloresContextIslandPlacement.barWidth(hugging: 1_200, in: narrow) == 280,
            "a display too narrow for the catalog caps the bar at its own width less the margins")
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

    /// One mouse gesture belongs to one surface. These are the rules the Context Surface reads
    /// before it treats a mouse release as a completed selection.
    @MainActor
    private static func testSurfaceInteractionGate() {
        let gate = DeloresSurfaceInteractionGate()
        require(!gate.blocksSelection, "an idle gate leaves selection capture alone")

        require(gate.claim(.snapping), "a window drag claims the gate")
        require(gate.blocksSelection, "a claimed gesture blocks selection capture")
        require(!gate.claim(.divider), "a second surface cannot claim a gesture in flight")

        gate.release(.snapping)
        require(gate.owner == nil, "releasing clears the owner")
        // The Context Surface decides on the release that ended the drag, and it asks a beat later:
        // letting go has to keep covering the gesture rather than reopening it instantly.
        require(gate.blocksSelection, "a just-released gesture still covers the release that ended it")

        require(gate.claim(.divider), "the divider claims once the drag has been released")
        gate.release(.snapping)
        require(gate.owner == .divider, "a stale release cannot free another surface's gesture")

        gate.reset()
        require(gate.owner == nil, "reset drops the owner")
        require(!gate.blocksSelection, "reset also drops the release suppression")
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

    private static func testAnswerAccumulator() {
        var answer = DeloresAnswerAccumulator()
        answer.append("你好")
        answer.append("，世界")
        require(answer.text == "你好，世界", "answer accumulates deltas in arrival order")
        require(!answer.isCapped, "a short answer never reaches the ceiling")

        let limit = DeloresAnswerAccumulator.maxCharacters
        var capped = DeloresAnswerAccumulator()
        capped.append(String(repeating: "甲", count: limit - 2))
        require(!capped.isCapped, "room to spare leaves the answer open")

        // The delta that crosses the line is cut at the line rather than dropped, so the reader
        // keeps what there was room for and the notice is what marks it partial.
        capped.append("乙丙丁")
        require(capped.isCapped, "a delta past the ceiling caps the answer")
        require(
            capped.text.hasSuffix(DeloresAnswerAccumulator.truncationNotice),
            "a capped answer says it stopped")
        // Everything before the notice is kept body: the head plus as much of the crossing delta
        // as there was room for, which together come to exactly the ceiling.
        let body = capped.text.dropLast(DeloresAnswerAccumulator.truncationNotice.count)
        require(body.count == limit, "the kept body stops exactly at the ceiling")
        require(body.starts(with: "甲"), "the kept body starts with what arrived first")

        let settled = capped.text
        capped.append(String(repeating: "戊", count: 512))
        require(capped.text == settled, "a capped answer takes no further deltas")
    }

    private static func testGesturePolicy() {
        require(
            DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 8,
                previousReleaseDistance: nil,
                elapsedSincePreviousRelease: nil) == .drag,
            "drag selection reaches its threshold")
        require(
            DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 7.9,
                previousReleaseDistance: nil,
                elapsedSincePreviousRelease: nil) == nil,
            "ordinary click is ignored")
        require(
            DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 0,
                previousReleaseDistance: 4,
                elapsedSincePreviousRelease: 0.34) == .doubleClick,
            "double click selection is accepted")
        require(
            DeloresSelectionGesturePolicy.qualifies(
                dragDistance: 0,
                previousReleaseDistance: 4,
                elapsedSincePreviousRelease: 0.35) == nil,
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
