import CoreGraphics
import Foundation

@main
struct DeloresContextTest {
    static func main() {
        testSelectionPolicy()
        testAnswerAccumulator()
        testActionSession()
        testActionConversation()
        testActionDefinition()
        MainActor.assumeIsolated { testActionSessionRunner() }
        testGesturePolicy()
        testOwnSurfaceHitPolicy()
        MainActor.assumeIsolated { testSurfaceInteractionGate() }
        testCompanionLoop()
        testCompanionWander()
        testQuickActionAdmission()
        testContextActions()
        testCustomRowsOnTheBar()
        testContextActionPrompts()
        testSearchURL()
        testQuickActionPrompt()
        testPlacement()
        testCompanionShell()
        testCompanionAnimation()
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
            QuickActionPrompt.instructions(for: QuickAction.translate, translatingInto: "Japanese")
                == translated,
            "a model standing in for the framework is asked for the translation the chat lane asks")
        require(
            QuickActionPrompt.instructions(
                for: BuiltInQuickAction.translate, override: "Ignore that.", translatingInto: "Japanese")
                == translated,
            "a reader's wording cannot drop the language translate's model was asked for")
        require(
            QuickActionPrompt.instructions(for: QuickAction.summarize, translatingInto: "Japanese")
                == QuickActionPrompt.instructions(for: QuickAction.summarize),
            "a target language is read for translate and nothing else")

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
        require(!gate.claim(.companion), "the companion cannot take a gesture already owned")

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
        require(gate.claim(.companion), "the companion claims an idle gate")
        require(!gate.claim(.snapping), "a pet drag is not also a window snap")
        gate.release(.companion)
        require(gate.blocksSelection, "releasing the companion still covers the gesture that ended")
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


    private static func testActionSession() {
        var session = DeloresActionSession()
        require(session.ingest("你好") == .streaming("你好"), "deltas accumulate")
        require(session.complete() == .finished("你好"), "finished is trimmed")
        var empty = DeloresActionSession(); require(empty.complete() == .failed(DeloresActionSession.emptyResult), "empty fails")
        var stopped = DeloresActionSession(); require(stopped.stop() == .stopped(nil), "stop before token")
        var cap = DeloresActionSession(); let limit = DeloresAnswerAccumulator.maxCharacters
        _ = cap.ingest(String(repeating: "甲", count: limit - 1))
        require(cap.ingest("乙丙") == .capped, "cap stops transport")
        guard case .finished(let text) = cap.complete() else { fatalError("FAIL capped") }
        require(text.hasSuffix(DeloresAnswerAccumulator.truncationNotice), "capped notice")
    }
    private static func testActionConversation() {
        var c = DeloresActionConversation()
        c.begin(question: "q")
        c.noteAnswer("a")
        c.commitForFollowUp()
        require(c.settled.count == 2, "exchange kept")
        c.restart()
        require(c.settled.isEmpty, "retry clears")

        let long = String(repeating: "x", count: DeloresActionConversation.maxTurnCharacters + 8)
        let clipped = DeloresActionConversation.kept([
            .init(role: .user, text: long),
            .init(role: .assistant, text: "ok"),
        ])
        require(clipped[0].text.count == DeloresActionConversation.maxTurnCharacters, "turn clipped")

        var overflow: [DeloresActionConversation.Turn] = []
        for i in 0..<12 {
            overflow.append(.init(role: .user, text: "u\(i)"))
            overflow.append(.init(role: .assistant, text: "a\(i)"))
        }
        let even = DeloresActionConversation.kept(overflow)
        require(even.count == DeloresActionConversation.maxTurnMessages, "keeps twenty")
        require(even.first?.text == "u2", "oldest pair dropped")

        overflow.append(.init(role: .user, text: "orphan"))
        let odd = DeloresActionConversation.kept(overflow)
        require(odd.count == 19, "odd excess drops one extra to keep pairs")
        require(odd.first?.role == .user, "kept sequence still starts on a question")
    }
    private static func testActionDefinition() {
        let summarize = require(DeloresContextAction.catalog.first { $0.id == "summarize" }, "summarize")
        require(DeloresActionDefinition.outputCap(for: "summarize") == .compact(max: 512), "the shared policy caps a digest")
        require(DeloresActionDefinition.outputCap(for: "explain") == .scaled(max: 2_048), "and lets an answer take its room")
        require(DeloresActionDefinition.outputCap(for: "custom-row") == .scaled(max: 2_048), "an id it does not know")
        require(summarize.maxOutputTokens(selection: "x") == 64, "compact floor")
        require(summarize.maxOutputTokens(selection: String(repeating: "a", count: 9_000)) == 512, "512 ceiling")
        let translate = require(DeloresContextAction.catalog.first { $0.id == "translate" }, "translate")
        require(translate.maxOutputTokens(selection: "short") == 128, "scaled")
        require(summarize.definition.id == "summarize", "summarize identity")
        require(
            summarize.definition.outputCap == .compact(max: 512)
                && summarize.maxOutputTokens(selection: String(repeating: "a", count: 9_000))
                == DeloresActionDefinition.OutputCap.compact(max: 512)
                    .tokens(selection: String(repeating: "a", count: 9_000)),
            "Context summarize and Quick Action summarize share the compact 512 cap")
        require(
            translate.definition.backend == .translationFramework,
            "the bar's 翻译 says Apple's translator is what answers it with no model bound")
        require(
            DeloresActionDefinition.defaultBackend(for: "translate") == .translationFramework
                && DeloresActionDefinition.defaultBackend(for: "explain") == .languageModel
                && DeloresActionDefinition.defaultBackend(for: "custom-row") == .languageModel,
            "translate is the one id Apple's translator owns by default")
        // `translationRoute` picks between Apple's translator and a model; its labels say which.
        let route = DeloresActionDefinition.translationRoute
        require(
            route(true, .installed) == .languageModel && route(true, .undetectable) == .languageModel,
            "a model bound to the id answers it, whatever this Mac can do on its own")
        require(
            route(false, .installed) == .translationFramework
                && route(false, .supported) == .translationFramework,
            "an unbound translate keeps the translator, including a pair only waiting to download")
        require(
            route(false, .unsupported) == .languageModel && route(false, .undetectable) == .languageModel,
            "a pair Apple cannot do, or a text whose language it cannot tell, falls to a model")
    }
    private static func testActionSessionRunner() {
        require(runSession { $0.yield(.text("你好")); $0.yield(.text("世界")); $0.finish() } == .finished("你好世界"), "runner short stream")
        require(runSession { $0.finish() } == .failed(DeloresActionSession.emptyResult), "empty stream")
        require(runSession(isCurrent: { false }) { $0.yield(.text("ghost")); $0.finish() } == nil, "stale generation")
        require(
            runSession { continuation in
                continuation.yield(.text("一半"))
                continuation.finish(throwing: CancellationError())
            } == .stopped("一半"),
            "cancelled stream keeps the partial result")
    }
    private static func runSession(isCurrent: @escaping () -> Bool = { true }, _ build: @escaping (AsyncThrowingStream<AIStreamEvent, Error>.Continuation) -> Void) -> DeloresActionSession.Outcome? {
        var outcome: DeloresActionSession.Outcome?
        Task { @MainActor in
            let stream: AIProviderStream = AsyncThrowingStream { build($0) }
            outcome = await DeloresActionSessionRunner.run(stream: stream, isCurrent: isCurrent, onStreaming: { _ in })
            CFRunLoopStop(CFRunLoopGetMain())
        }
        CFRunLoopRun(); return outcome
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

    private static func testCompanionShell() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 876)
        let r = DeloresCompanionShell.Size.regular.radius
        let gap = DeloresCompanionShell.shellGap
        let bar = CGSize(width: 420, height: 38)

        // The whole point: the shell grows inward, and the body it grew from stays outside it.
        func assertOutside(_ placement: DeloresCompanionShell.Placement, _ what: String) {
            let pet = DeloresCompanionShell.circleFrame(center: placement.petCenter, bodyRadius: r)
            require(
                !placement.frame.intersects(pet),
                "a shell grown \(what) does not cover the body it grew from")
            require(
                placement.frame.minX >= visible.minX && placement.frame.maxX <= visible.maxX
                    && placement.frame.minY >= visible.minY && placement.frame.maxY <= visible.maxY,
                "a shell grown \(what) stays inside the visible area")
        }

        let right = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 400),
            edge: .right, shellSize: bar, visibleFrame: visible, bodyRadius: r)
        let rightPet = DeloresCompanionShell.circleFrame(center: right.petCenter, bodyRadius: r)
        require(
            right.frame.maxX == rightPet.minX - gap,
            "a shell on the right edge grows leftward with the gap between")
        require(right.frame.midY == rightPet.midY, "a closed shell is level with the body")
        assertOutside(right, "on the right edge")

        let left = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: visible.minX + r, y: 400),
            edge: .left, shellSize: bar, visibleFrame: visible, bodyRadius: r)
        let leftPet = DeloresCompanionShell.circleFrame(center: left.petCenter, bodyRadius: r)
        require(
            left.frame.minX == leftPet.maxX + gap,
            "a shell on the left edge grows rightward with the gap between")
        assertOutside(left, "on the left edge")

        let top = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: 400, y: visible.maxY - r),
            edge: .top, shellSize: bar, visibleFrame: visible, bodyRadius: r)
        let topPet = DeloresCompanionShell.circleFrame(center: top.petCenter, bodyRadius: r)
        require(
            top.frame.maxY == topPet.minY - gap,
            "a shell on the top edge hangs below the body")
        require(top.frame.midX == topPet.midX, "a shell on a horizontal edge is centred on the body")
        assertOutside(top, "on the top edge")

        // The bottom edge is the one the reader is not looking past: a shell grown "inward" from
        // there would lie across the middle of the display. The body slides to a vertical edge.
        let bottom = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: 200, y: visible.minY + r),
            edge: .bottom, shellSize: bar, visibleFrame: visible, bodyRadius: r)
        require(bottom.edge == .left, "a body on the bottom edge slides to the nearer vertical edge")
        assertOutside(bottom, "from the bottom edge")
        let farBottom = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: visible.maxX - 200, y: visible.minY + r),
            edge: .bottom, shellSize: bar, visibleFrame: visible, bodyRadius: r)
        require(
            farBottom.edge == .right,
            "a body on the bottom edge takes the nearer vertical edge, whichever that is")

        // An opened card hangs from the closed bar's top edge, so the growth is one downward
        // gesture and the bar itself does not move.
        let opened = DeloresCompanionShell.planExpandedBarOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 400),
            edge: .right, collapsedSize: bar,
            expandedSize: CGSize(width: 420, height: 390), visibleFrame: visible, bodyRadius: r)
        require(
            opened.frame.maxY == right.frame.maxY,
            "an opened card hangs from the closed bar's top edge")
        require(
            opened.frame.minX == right.frame.minX,
            "an opened card keeps the bar's horizontal placement")
        assertOutside(opened, "open, on the right edge")

        // Too close to the bottom, and the body rides up with it rather than being clipped.
        let low = DeloresCompanionShell.planExpandedBarOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 100),
            edge: .right, collapsedSize: bar,
            expandedSize: CGSize(width: 420, height: 390), visibleFrame: visible, bodyRadius: r)
        require(low.petCenter.y > 100, "a card that would run off the bottom lifts the body with it")
        require(low.frame.minY == visible.minY, "the lifted card sits on the bottom edge")
        assertOutside(low, "open, after lifting the body")
        require(
            low.frame.maxY <= visible.maxY,
            "a lifted card does not push the body off the top instead")

        // A display too narrow for the shell shrinks it rather than hanging it off both ends.
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 876)
        let squeezed = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: 300 - r, y: 400),
            edge: .right, shellSize: bar, visibleFrame: narrow, bodyRadius: r)
        require(
            squeezed.frame.width <= narrow.width && squeezed.frame.minX >= narrow.minX,
            "a shell wider than its display is shrunk to it")

        // A vertical edge grows a vertical strip: the same placement, asked for a column's size,
        // stands the column level with the body — and an opened card shares the strip's pet-side
        // rim, the strip riding the card's rim like a spine, so the growth is one inward gesture.
        let strip = CGSize(width: 44, height: 340)
        let rightStrip = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 400),
            edge: .right, shellSize: strip, visibleFrame: visible, bodyRadius: r)
        require(
            rightStrip.frame.maxX == rightPet.minX - gap,
            "a strip on the right edge grows leftward with the gap between")
        require(rightStrip.frame.midY == rightPet.midY, "a strip is level with the body")
        assertOutside(rightStrip, "as a strip, on the right edge")
        let leftStrip = DeloresCompanionShell.planBarOpening(
            petCenter: CGPoint(x: visible.minX + r, y: 400),
            edge: .left, shellSize: strip, visibleFrame: visible, bodyRadius: r)
        require(
            leftStrip.frame.minX == leftPet.maxX + gap,
            "a strip on the left edge grows rightward with the gap between")

        let spine = DeloresCompanionShell.planExpandedBarOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 400),
            edge: .right, collapsedSize: strip,
            expandedSize: CGSize(width: 420, height: 390), visibleFrame: visible, bodyRadius: r)
        require(
            spine.frame.maxX == rightStrip.frame.maxX,
            "an opened card keeps the strip's pet-side rim — the strip is the card's spine")
        require(
            spine.frame.maxY == rightStrip.frame.maxY,
            "an opened card starts where the strip starts along its long axis")
        assertOutside(spine, "open beside a strip")

        // A snap island opens out of the body on whichever edge it stands: horizontal above or
        // below it, vertical beside it, its long axis always along the edge. Unlike a bar it may
        // open on the bottom edge — it is a preview for the length of a drag, not a reading
        // surface, and the bottom of the display is not the middle of it.
        // The reference's own numbers: a row of four panes in a capsule, and the same four standing
        // in a column with no capsule around them — a column is only as wide and as tall as its
        // panes, because a capsule 300-odd tall would cut the end ones to slivers.
        let wide = CGSize(width: 620, height: 88)
        let tall = CGSize(width: 140, height: 324)
        let topIsland = DeloresCompanionShell.planIslandOpening(
            petCenter: CGPoint(x: 400, y: visible.maxY - r),
            edge: .top, islandSize: wide, visibleFrame: visible, bodyRadius: r)
        let topIslandPet = DeloresCompanionShell.circleFrame(center: topIsland.petCenter, bodyRadius: r)
        require(
            topIsland.frame.maxY == topIslandPet.minY - gap,
            "an island on the top edge hangs below the body")
        require(topIsland.frame.midX == topIslandPet.midX, "an island on a horizontal edge is centred")
        assertOutside(topIsland, "as an island, on the top edge")

        let bottomIsland = DeloresCompanionShell.planIslandOpening(
            petCenter: CGPoint(x: 400, y: visible.minY + r),
            edge: .bottom, islandSize: wide, visibleFrame: visible, bodyRadius: r)
        let bottomIslandPet = DeloresCompanionShell.circleFrame(center: bottomIsland.petCenter, bodyRadius: r)
        require(
            bottomIsland.frame.minY == bottomIslandPet.maxY + gap,
            "an island on the bottom edge rides above the body, where a bar would have slid away")
        assertOutside(bottomIsland, "as an island, on the bottom edge")

        let rightIsland = DeloresCompanionShell.planIslandOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 400),
            edge: .right, islandSize: tall, visibleFrame: visible, bodyRadius: r)
        require(
            rightIsland.frame.maxX == rightPet.minX - gap,
            "an island on the right edge grows leftward with the gap between")
        require(rightIsland.frame.midY == rightPet.midY, "a vertical island is level with the body")
        assertOutside(rightIsland, "as an island, on the right edge")

        // Too low for a vertical island, and the body rides up with it rather than being clipped.
        let lowIsland = DeloresCompanionShell.planIslandOpening(
            petCenter: CGPoint(x: visible.maxX - r, y: 60),
            edge: .right, islandSize: tall, visibleFrame: visible, bodyRadius: r)
        require(lowIsland.petCenter.y > 60, "an island that would run off the bottom lifts the body")

        // What counts as "brought to the body" during a drag is generous, by design.
        let hit = DeloresCompanionShell.dragHitFrame(center: CGPoint(x: 700, y: 400))
        require(hit.width == 60 && hit.height == 60, "the drag hit frame is 60pt square")
        require(
            hit.contains(CGPoint(x: 675, y: 400)) && hit.contains(CGPoint(x: 725, y: 400)),
            "the drag hit frame is centred on the body")
    }

    private static func testCompanionAnimation() {
        // Ruling 3, and its corollary: anything that is not a trip is idle. That is also what covers
        // holding a shell, being captured and being dragged — none of them has a wander state to read.
        require(
            DeloresCompanionAnimation.row(isStrolling: false, isHeld: false, facing: .right) == .idle,
            "a resting body is idle")
        require(
            DeloresCompanionAnimation.row(isStrolling: true, isHeld: true, facing: .left) == .idle,
            "a body holding a shell is idle even mid-trip")
        require(
            DeloresCompanionAnimation.row(isStrolling: true, isHeld: false, facing: .left) == .walkLeft,
            "a trip reads its row off the facing")
        require(
            DeloresCompanionAnimation.row(isStrolling: true, isHeld: false, facing: .right) == .walkRight,
            "and the other direction off the same one")

        // The wander walks a perimeter, so a step along a vertical edge has no horizontal component.
        // A body there must not flip sides every frame: it keeps what it already had.
        require(
            DeloresCompanionAnimation.facing(
                from: CGPoint(x: 400, y: 300), to: CGPoint(x: 400, y: 340), fallback: .left) == .left,
            "a purely vertical step keeps the facing it already had")
        require(
            DeloresCompanionAnimation.facing(
                from: CGPoint(x: 400, y: 340), to: CGPoint(x: 400, y: 300), fallback: .right) == .right,
            "and so does one going back down the same edge")
        require(
            DeloresCompanionAnimation.facing(
                from: CGPoint(x: 100, y: 20), to: CGPoint(x: 130, y: 20), fallback: .left) == .right,
            "a step to the right turns the body right")
        require(
            DeloresCompanionAnimation.facing(
                from: CGPoint(x: 130, y: 20), to: CGPoint(x: 100, y: 20), fallback: .right) == .left,
            "a step to the left turns it back")

        // Core Animation counts y from the bottom and the sheet is authored from the top, so the row
        // is flipped once — and the first row is therefore the one at the top of the image.
        let top = DeloresCompanionAnimation.contentsRect(row: .idle, frame: 0)
        require(top.minX == 0, "the first frame of the first row is the sheet's left edge")
        require(top.maxY == 1, "and its top edge — the flip is what puts the first row up there")
        require(top.width == 0.2, "a frame is one column of five")
        require(abs(top.height - (1.0 / 6.0)) < 0.0001, "and one row of six")
        let last = DeloresCompanionAnimation.contentsRect(row: .acrobatics, frame: 2)
        require(last.minY == 0, "the last row sits on the sheet's bottom edge")
        require(last.minX == 0.4, "the frame index is the column")

        // Ruling 2: one timer drives the step and the frame together, so this is a trade, not a saving.
        require(DeloresCompanionAnimation.walkFrame == 1.0 / 8.0, "walking is pinned at an ambling 8 fps")
        require(DeloresCompanionAnimation.breathDuration == 2.0, "a breath is two seconds across two frames")
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

    /// The loop: what the body may walk, and where it turns back.
    private static func testCompanionLoop() {
        let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let radius: CGFloat = 24
        let r = display.insetBy(dx: radius, dy: radius)

        // Nothing in the way: one run around the display, and it closes.
        let plain = DeloresCompanionLoop.around(display, bodyRadius: radius)
        require(plain.runs.count == 1, "an unobstructed display is one run")
        require(plain.runs[0].isClosed, "and it closes")
        let perimeter = 2 * (r.width + r.height)
        require(
            abs(plain.runs[0].length - perimeter) < 0.01,
            "and its length is the display's perimeter")
        for tick in stride(from: 0, through: perimeter, by: 1) {
            let point = DeloresCompanionLoop.position(at: tick, in: plain.runs[0])
            require(
                r.insetBy(dx: -0.01, dy: -0.01).contains(point),
                "every point of the loop is on the display")
        }

        // A Dock standing on the bottom edge is walked around rather than crossed.
        let dock = CGRect(x: 600, y: 0, width: 400, height: 90)
        let withDock = DeloresCompanionLoop.around(display, bodyRadius: radius, walkingAround: dock)
        require(withDock.runs.count == 1, "walking around something still leaves one run")
        let dockRun = withDock.runs[0]
        require(dockRun.isClosed, "and that run still closes")
        require(
            abs(dockRun.length - (perimeter + 2 * (dock.maxY - r.minY))) < 0.01,
            "going around costs the Dock's height twice, once each way")
        let walked = stride(from: 0, through: dockRun.length, by: 1).map {
            DeloresCompanionLoop.position(at: $0, in: dockRun)
        }
        require(
            walked.contains { abs($0.y - dock.maxY) < 0.01 && $0.x > dock.minX && $0.x < dock.maxX },
            "the loop crosses the Dock's top")
        require(
            !walked.contains { dock.insetBy(dx: 1, dy: 0).contains($0) && $0.y < dock.maxY - 0.01 },
            "and never enters the Dock")

        // The menu bar's ends are forbidden, so each allowed stretch is a run of its own and the long
        // way round stops where the first of them begins.
        let withEnds = DeloresCompanionLoop.around(
            display, bodyRadius: radius, topRuns: [200...500, 900...1200])
        require(withEnds.runs.count == 3, "two allowed stretches plus the long way round")
        require(withEnds.runs[1].length == 300, "a stretch is as long as it is")
        require(withEnds.runs[2].length == 300, "and so is the other one")
        require(!withEnds.runs[1].isClosed, "a stretch that stops short is walked back and forth")
        require(!withEnds.runs[2].isClosed, "both of them")
        for index in 1...2 {
            for end in [withEnds.runs[index].points.first!, withEnds.runs[index].points.last!] {
                require(abs(end.y - r.maxY) < 0.01, "both ends of a stretch are on the menu bar")
            }
        }
        let longWay = require(withEnds.runs[0].points.last, "the long run ends somewhere")
        require(abs(longWay.x - 1200) < 0.01, "the long run stops at the first forbidden stretch")
        require(
            abs(withEnds.runs[0].points.first!.x - r.minX) < 0.01,
            "and it starts at the other corner")

        // An open run turns back at its ends; a closed one carries on round.
        require(
            DeloresCompanionLoop.travel(150, from: 250, in: withEnds.runs[1]) == 200,
            "an open run turns back at its far end")
        require(
            DeloresCompanionLoop.travel(-400, from: 100, in: withEnds.runs[1]) == 300,
            "and at its near end")
        require(
            abs(DeloresCompanionLoop.travel(plain.runs[0].length + 10, from: 0, in: plain.runs[0]) - 10)
                < 0.01,
            "a closed run carries on round instead of turning")

        // A display too small to hold the body at all is empty rather than crashing.
        require(
            DeloresCompanionLoop.around(
                CGRect(x: 0, y: 0, width: 40, height: 40), bodyRadius: 24
            ).isEmpty,
            "a display smaller than the body has nowhere to walk")
    }

    /// The Companion's wander: it rides its loop without ever cutting across, never ends a trip where
    /// the last one did, never rests long enough to look dead, and asks for no frame at all while it
    /// rests. Replayed from a fixed seed, so the randomness is real and the sequence is not.
    private static func testCompanionWander() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let loop = DeloresCompanionLoop.around(bounds, bodyRadius: 0)
        let run = loop.runs[0]
        let total = run.length
        let least = DeloresCompanionWander.shortTripRange.lowerBound
        var rng = SeededRandom(seed: 0x5EED_1234)

        let settled = DeloresCompanionWander.settled(
            at: CGPoint(x: 700, y: 400), in: loop, at: 0, using: &rng)
        require(isOnEdge(settled.center, in: bounds), "a settle lands on the edge it will ride")
        let firstRest = require(restEnd(settled), "a settle stands still before it walks")
        require(firstRest >= DeloresCompanionWander.shortRestRange.lowerBound, "a rest is not instant")
        require(firstRest <= DeloresCompanionWander.maximumRest, "a rest stays inside its bound")
        require(
            DeloresCompanionWander.nextWake(after: settled) == firstRest,
            "a rest states when it ends")
        require(
            DeloresCompanionWander.advance(settled, elapsed: 0.1, now: 1, in: loop, using: &rng) == settled,
            "a rest under its due time changes nothing, and owes no frame")

        let walking = DeloresCompanionWander.advance(
            settled, elapsed: 0.1, now: firstRest + 0.1, in: loop, using: &rng)
        guard case .strolling(_, let destination, let speed) = walking.phase else {
            fatalError("FAIL: a rest that has come due sets off")
        }
        require(DeloresCompanionWander.speedRange.contains(speed), "a trip holds a speed in range")
        let leftBehind = DeloresCompanionLoop.distance(of: settled.center, in: run)
        require(
            gap(destination, leftBehind, around: total) >= least - 0.01,
            "a destination is far enough away not to repeat the spot it left")
        require(DeloresCompanionWander.nextWake(after: walking) == nil, "a trip runs on frames")

        let late = DeloresCompanionWander.advance(
            walking, elapsed: 600, now: firstRest + 61, in: loop, using: &rng)
        require(late.phase.isWalking, "a capped frame does not finish a trip")
        let ceiling = CGFloat(DeloresCompanionWander.maximumStep) * DeloresCompanionWander.speedRange.upperBound
        require(
            distance(late.center, walking.center) <= ceiling + 0.01,
            "a frame that arrives late is capped instead of teleporting the body")

        // Both draws have a short body and a long tail. The tail is the whole reason the thing reads
        // as occupied rather than scheduled.
        let restDraws = (0..<400).map { _ in DeloresCompanionWander.restDuration(using: &rng) }
        require(
            restDraws.allSatisfy { $0 <= DeloresCompanionWander.maximumRest },
            "no rest outlasts the bound")
        require(
            restDraws.allSatisfy { $0 >= DeloresCompanionWander.shortRestRange.lowerBound },
            "no rest is instant")
        require(
            restDraws.contains { $0 > DeloresCompanionWander.shortRestRange.upperBound },
            "the tail of the rest distribution is a long rest")
        require(
            restDraws.contains { $0 <= DeloresCompanionWander.shortRestRange.upperBound },
            "most rests are pauses")
        require(Set(restDraws).count > 10, "rests are drawn, not fixed")

        let tripDraws = (0..<400).map { _ in DeloresCompanionWander.tripDistance(in: total, using: &rng) }
        require(
            tripDraws.allSatisfy { $0 >= DeloresCompanionWander.shortTripRange.lowerBound },
            "a trip always goes somewhere")
        require(
            tripDraws.contains { $0 > DeloresCompanionWander.shortTripRange.upperBound },
            "the tail of the trip distribution is the long way")
        require(
            tripDraws.contains { $0 <= DeloresCompanionWander.shortTripRange.upperBound },
            "most trips are a few steps")
        require(Set(tripDraws).count > 10, "trips are drawn, not fixed")

        var state = settled
        var clock = 0.0
        var edges = Set<String>()
        var tripCount = 0
        var restingFrames = 0
        var rests: [TimeInterval] = []
        var destinations: [CGFloat] = []
        var speeds: [CGFloat] = []
        // The lazy pacing loiters far more than it walks, so the replay needs a longer window to
        // see the same amount of world: at five minutes the body can honestly still be on its
        // first edge. Fifteen minutes is the new calibration, not a loosened assertion.
        while clock < 900 {
            let elapsed = 1.0 / 20.0
            clock += elapsed
            let wasWalking = state.phase.isWalking
            let next = DeloresCompanionWander.advance(
                state, elapsed: elapsed, now: clock, in: loop, using: &rng)
            require(isOnEdge(next.center, in: bounds), "the body rides an edge and never cuts across")
            require(
                bounds.insetBy(dx: -0.01, dy: -0.01).contains(next.center),
                "the body stays on the display")
            edges.insert(String(describing: DeloresCompanionWander.edge(for: next.center, in: bounds)))
            if wasWalking {
                require(
                    !next.phase.isWalking || next.phase == state.phase,
                    "a trip holds its speed and destination until it arrives")
            }
            switch next.phase {
            case .resting(let until):
                restingFrames += 1
                if wasWalking { rests.append(until - clock) }
            case .strolling(_, let destination, let speed):
                if !wasWalking {
                    tripCount += 1
                    destinations.append(destination)
                    speeds.append(speed)
                }
            }
            state = next
        }

        require(tripCount >= 3 && restingFrames > 0, "fifteen minutes hold both walking and resting")
        require(edges.count >= 2, "a wander is not one fixed edge")
        require(Set(speeds).count > 1, "trips do not all run at one speed")
        require(
            tripCount - 1 <= rests.count && rests.count <= tripCount,
            "every trip that ended left a rest behind it")
        for rest in rests {
            require(rest >= DeloresCompanionWander.shortRestRange.lowerBound, "no rest in the run is instant")
            require(rest <= DeloresCompanionWander.maximumRest, "no rest in the run outlasts the bound")
        }
        for index in 1..<destinations.count {
            require(
                gap(destinations[index], destinations[index - 1], around: total) >= least - 0.01,
                "consecutive destinations never repeat a spot")
        }

        // A display too small to hold a minimum trip still wanders, and still stays on its edge.
        let tight = CGRect(x: 0, y: 0, width: 90, height: 60)
        let tightLoop = DeloresCompanionLoop.around(tight, bodyRadius: 0)
        var tightState = DeloresCompanionWander.settled(
            at: CGPoint(x: tight.midX, y: tight.midY), in: tightLoop, at: 0, using: &rng)
        for tick in stride(from: 0.05, through: 30, by: 0.05) {
            tightState = DeloresCompanionWander.advance(
                tightState, elapsed: 0.05, now: tick, in: tightLoop, using: &rng)
            require(
                isOnEdge(tightState.center, in: tight),
                "a tiny display still keeps the body on its edge")
        }
    }

    private static func isOnEdge(_ point: CGPoint, in bounds: CGRect, tolerance: CGFloat = 0.001) -> Bool {
        let onVertical = abs(point.x - bounds.minX) <= tolerance || abs(point.x - bounds.maxX) <= tolerance
        let onHorizontal = abs(point.y - bounds.minY) <= tolerance || abs(point.y - bounds.maxY) <= tolerance
        return onVertical || onHorizontal
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// The short way round the perimeter between two distances measured along it.
    private static func gap(_ a: CGFloat, _ b: CGFloat, around total: CGFloat) -> CGFloat {
        let raw = abs(a - b)
        return min(raw, total - raw)
    }

    private static func restEnd(_ state: DeloresCompanionWander.State) -> TimeInterval? {
        guard case .resting(let until) = state.phase else { return nil }
        return until
    }

    private static func require<T>(_ value: T?, _ message: String) -> T {
        guard let value else { fatalError("FAIL: \(message)") }
        return value
    }

    private static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError("FAIL: \(message)") }
    }
}

/// SplitMix64. The wander's randomness stays real; replaying it is what makes it assertable.
private struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension DeloresCompanionWander.Phase {
    var isWalking: Bool {
        if case .strolling = self { return true }
        return false
    }
}
