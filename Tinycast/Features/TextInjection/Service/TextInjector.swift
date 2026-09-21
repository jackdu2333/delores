import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

/// Its own shape, not a caller's result type, so the injector stays owned by no one feature.
struct InjectedText: Equatable, Sendable {
    let text: String
    /// Leaves the caret this many characters back from the end; nil leaves it after the text.
    let cursorOffsetFromEnd: Int?

    init(_ text: String, cursorOffsetFromEnd: Int? = nil) {
        self.text = text
        self.cursorOffsetFromEnd = cursorOffsetFromEnd
    }

    /// UTF-16 distance from the start of the inserted text to where the caret should land.
    var caretPrefixLength: Int {
        let offset = min(max(cursorOffsetFromEnd ?? 0, 0), text.count)
        return text[..<text.index(text.endIndex, offsetBy: -offset)].utf16.count
    }
}

enum AccessibilityReplacement: Equatable {
    case delivered
    case unavailable
    case rejected

    /// `.rejected` means the document is not the one we measured, so events would edit the wrong text.
    var fallsBackToEvents: Bool { self == .unavailable }
}

/// The two judgements a replacement makes, kept pure so the harness can drive both tiers.
@MainActor
final class DeliveryCompletion {
    private let onDelivered: @MainActor () -> Void
    private let onFailed: @MainActor () -> Void
    private(set) var isConfirmed = false
    private var isSettled = false

    init(
        onDelivered: @escaping @MainActor () -> Void = {},
        onFailed: @escaping @MainActor () -> Void = {}
    ) {
        self.onDelivered = onDelivered
        self.onFailed = onFailed
    }

    func confirm() {
        guard !isSettled else { return }
        isSettled = true
        isConfirmed = true
        onDelivered()
    }

    /// Driven from a `defer`, so a delivery that returned early still says so instead of vanishing.
    func settle() {
        guard !isSettled else { return }
        isSettled = true
        onFailed()
    }
}

@MainActor
final class TextInjector {
    private let clipboardManager: ClipboardManager
    private let deliveryQueue = DeliveryQueue()
    private var activePasteboardLease: TemporaryPasteboardLease?

    init(clipboardManager: ClipboardManager) {
        self.clipboardManager = clipboardManager
    }

    /// A paste is still in flight, or we still hold the pasteboard it borrowed.
    var isDelivering: Bool { !deliveryQueue.isIdle || activePasteboardLease != nil }

    func prepareInteractiveExpansion(target: InjectionTarget?) -> Bool {
        if let editor = target?.ownEditor { return editor.isEditable }
        guard targetAcceptsInjection(target?.externalApp), Permissions.ensureAccessibility() else {
            target?.restoreFocus()
            return false
        }
        return true
    }

    func prepareForTermination() {
        deliveryQueue.cancelAll()
        finishPendingPasteboardOwnership()
    }

    /// A hotkey's target comes from `frontmostApplication`, which can be Tinycast itself.
    private func targetAcceptsInjection(_ targetApp: NSRunningApplication?) -> Bool {
        guard let targetApp,
            !targetApp.isTerminated,
            targetApp.bundleIdentifier != Bundle.main.bundleIdentifier,
            !IsSecureEventInputEnabled()
        else { return false }
        return true
    }

    func captureExpansionContext(
        target: InjectionTarget?,
        clipboardHistory: [String]
    ) -> QuicklinkTemplateEngine.ExpansionContext {
        QuicklinkTemplateEngine.ExpansionContext(
            clipboardHistory: clipboardHistory,
            selection: selection(in: target),
            now: Date(),
            calendar: Calendar.current,
            locale: Locale.current,
            timeZone: .current)
    }

    /// The caller must know there *is* a selection: a zero-length one inserts at the caret instead.
    func replaceSelection(
        with text: String,
        in targetApp: NSRunningApplication?,
        onDelivered: @escaping @MainActor () -> Void = {},
        onFailed: @escaping @MainActor () -> Void = {}
    ) {
        deliver(
            InjectedText(text), target: targetApp.map(InjectionTarget.external),
            onDelivered: onDelivered, onFailed: onFailed)
    }

    /// A `changeCount` that never moves means nothing was selected, not that the old clipboard won.
    func copySelection(from targetApp: NSRunningApplication?) async -> String? {
        await deliveryQueue.drain()
        guard finishPendingPasteboardOwnership(),
            await activateAndWaitForTarget(targetApp),
            deliveryIsAllowed(targetApp: targetApp, promptForInteractiveAccessibility: true)
        else { return nil }
        return await copySelection(from: targetApp, pasteboard: NSPasteboard.general)
    }

    /// Automatic capture may only copy when the target already holds the keyboard.
    func copySelectionIfFrontmost(from targetApp: NSRunningApplication?) async -> String? {
        await deliveryQueue.drain()
        guard finishPendingPasteboardOwnership(),
            deliveryIsAllowed(targetApp: targetApp, promptForInteractiveAccessibility: false)
        else { return nil }
        return await copySelection(from: targetApp, pasteboard: NSPasteboard.general)
    }

    /// Split for the harness, which drives a stub pasteboard rather than another app.
    func copySelection(
        from targetApp: NSRunningApplication?, pasteboard: any PasteboardAccess
    ) async -> String? {
        clipboardManager.prepareForTinycastPasteboardMutation()
        // Refused rather than forced when the board is holding something heavy: the fallback is worth
        // less than whatever the reader copied before selecting this text, and it is the only step
        // here that would otherwise not happen without their asking. Returning here leaves the board
        // untouched — nothing has been cleared yet.
        guard let original = PasteboardSnapshot(pasteboard: pasteboard, extent: .budgeted)
        else { return nil }
        defer { restore(original, to: pasteboard) }

        Paster.postCommandC(toPid: targetApp?.processIdentifier)
        for _ in 0..<Self.copyPollAttempts {
            guard await wait(for: Self.copyPollInterval) else { return nil }
            guard pasteboard.changeCount != original.changeCount else { continue }
            guard let copied = PasteboardSnapshot(pasteboard: pasteboard, extent: .budgeted),
                let data = copied.firstStringData
            else { return nil }
            return String(bytes: data, encoding: .utf8)
        }
        return nil
    }

    private func restore(_ snapshot: PasteboardSnapshot, to pasteboard: any PasteboardAccess) {
        guard let items = snapshot.pasteboardItems() else { return }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else { return }
        clipboardManager.synchronizeAfterTinycastPasteboardMutation(
            changeCount: pasteboard.changeCount)
    }

    /// A copy lands well inside a second; past that the app was never going to answer.
    private static let copyPollAttempts = 40
    private static let copyPollInterval = Duration.milliseconds(25)

    func deliver(
        _ injected: InjectedText,
        target: InjectionTarget?,
        onDelivered: @escaping @MainActor () -> Void = {},
        onFailed: @escaping @MainActor () -> Void = {}
    ) {
        let targetApp = target?.externalApp
        activate(targetApp)
        guard prepareInteractiveExpansion(target: target) else {
            onFailed()
            return
        }

        deliveryQueue.enqueue { [weak self] in
            guard let self else { return }
            let completion = DeliveryCompletion(onDelivered: onDelivered, onFailed: onFailed)
            if let editor = target?.ownEditor {
                self.deliverInProcess(injected, into: editor, completion: completion)
                return
            }
            await self.performDelivery(injected, targetApp: targetApp, completion: completion)
        }
    }

    private func deliverInProcess(
        _ injected: InjectedText,
        into editor: any InjectableTextView,
        completion: DeliveryCompletion
    ) {
        guard editor.isEditable else {
            completion.settle()
            return
        }
        editor.inject(injected, over: editor.selectedRange())
        completion.confirm()
    }

    private func performDelivery(
        _ injected: InjectedText,
        targetApp: NSRunningApplication?,
        completion: DeliveryCompletion
    ) async {
        defer { completion.settle() }
        guard finishPendingPasteboardOwnership(),
            await activateAndWaitForTarget(targetApp),
            deliveryIsAllowed(targetApp: targetApp, promptForInteractiveAccessibility: true)
        else { return }

        let accessibilityReplacement = replaceUsingAccessibility(injected, targetApp: targetApp)
        if accessibilityReplacement == .delivered {
            completion.confirm()
            return
        }
        guard accessibilityReplacement.fallsBackToEvents else { return }

        guard
            await deliverUsingEvents(
                injected.text,
                targetApp: targetApp)
        else { return }

        guard let offset = injected.cursorOffsetFromEnd, offset > 0 else {
            completion.confirm()
            return
        }
        for index in 0..<offset {
            guard
                deliveryIsAllowed(
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false),
                postKey(code: CGKeyCode(kVK_LeftArrow), targetApp: targetApp)
            else { return }
            if index < offset - 1,
                !(await wait(for: .milliseconds(8)))
            {
                return
            }
        }
        completion.confirm()
    }

    private func deliverUsingEvents(
        _ text: String,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        let isShortSingleLine =
            text.count <= 100
            && !text.contains("\n")
            && !text.contains("\r")
        if isShortSingleLine {
            return await deliverUsingUnicodeEvents(
                text,
                targetApp: targetApp)
        }

        guard let lease = beginTemporaryPasteboardLease(text) else {
            return await deliverUsingUnicodeEvents(
                text,
                targetApp: targetApp)
        }
        activePasteboardLease = lease
        defer { finish(lease) }

        guard await wait(for: .milliseconds(80)),
            lease.isOwned,
            deliveryIsAllowed(
                targetApp: targetApp,
                promptForInteractiveAccessibility: false)
        else { return false }

        let stateBeforePaste = accessibilityTextState(in: targetApp)
        Paster.postCommandV(toPid: targetApp?.processIdentifier)
        return await waitForPasteConfirmation(
            previousState: stateBeforePaste,
            pasteboardLease: lease,
            targetApp: targetApp)
    }

    private func deliverUsingUnicodeEvents(
        _ text: String,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        guard let insertionEvents = makeUnicodeEvents(text),
            deliveryIsAllowed(
                targetApp: targetApp,
                promptForInteractiveAccessibility: false),
            await postEventGroups(insertionEvents, targetApp: targetApp)
        else { return false }

        return await wait(for: .milliseconds(100))
    }

    /// Each group is one keystroke, spaced so a target that stops accepting them halts the rest.
    private func postEventGroups(
        _ events: [[CGEvent]],
        targetApp: NSRunningApplication?
    ) async -> Bool {
        for index in events.indices {
            guard
                deliveryIsAllowed(
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false)
            else { return false }
            post(events[index], targetApp: targetApp)
            if index < events.count - 1,
                !(await wait(for: .milliseconds(8)))
            {
                return false
            }
        }
        return true
    }

    private func beginTemporaryPasteboardLease(_ text: String) -> TemporaryPasteboardLease? {
        clipboardManager.prepareForTinycastPasteboardMutation()
        return TemporaryPasteboardLease.begin(
            text: text,
            pasteboard: NSPasteboard.general
        ) { [clipboardManager] changeCount in
            clipboardManager.synchronizeAfterTinycastPasteboardMutation(
                changeCount: changeCount)
        }
    }

    @discardableResult
    private func finishPendingPasteboardOwnership() -> Bool {
        guard let lease = activePasteboardLease else { return true }
        for _ in 0..<3 where lease.isOwned { finish(lease) }
        return !lease.isOwned
    }

    private func finish(_ lease: TemporaryPasteboardLease) {
        switch lease.restoreIfOwned() {
        case .restored(let changeCount):
            // Keeps the poller from recording the restored original as a second copy.
            clipboardManager.synchronizeAfterTinycastPasteboardMutation(changeCount: changeCount)
        case .superseded:
            break
        case .failed:
            // Still ours, so leave `activePasteboardLease` in place for the retry below.
            if lease.isOwned { return }
        }
        if activePasteboardLease === lease { activePasteboardLease = nil }
    }

    private func deliveryIsAllowed(
        targetApp: NSRunningApplication?,
        promptForInteractiveAccessibility: Bool
    ) -> Bool {
        // Re-checked before every post, so a target that went away or went secure stops delivery.
        guard targetAcceptsInjection(targetApp), let targetApp,
            targetApp.isActive,
            NSWorkspace.shared.frontmostApplication?.processIdentifier
                == targetApp.processIdentifier
        else { return false }
        return promptForInteractiveAccessibility
            ? Permissions.ensureAccessibility()
            : Permissions.isAccessibilityTrusted()
    }

    private struct AccessibilityTextState: Equatable {
        let value: String
        let selectedRange: NSRange
    }

    private func activateAndWaitForTarget(
        _ targetApp: NSRunningApplication?
    ) async -> Bool {
        guard let targetApp else {
            return false
        }
        activate(targetApp)
        for _ in 0..<50 {
            if targetApp.isActive,
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == targetApp.processIdentifier
            {
                return true
            }
            guard await wait(for: .milliseconds(20)) else { return false }
        }
        return false
    }

    private struct AccessibilityTarget {
        let element: AXUIElement
        let value: String
        let originalRange: NSRange
        let replacementRange: NSRange
    }

    private enum AccessibilityTargetState {
        case ready(AccessibilityTarget)
        case unavailable
        case rejected
    }

    private func replaceUsingAccessibility(
        _ injected: InjectedText,
        targetApp: NSRunningApplication?
    ) -> AccessibilityReplacement {
        guard let targetApp else { return .unavailable }
        let state = accessibilityTarget(in: targetApp)
        guard case .ready(let target) = state else {
            if case .rejected = state { return .rejected }
            return .unavailable
        }

        guard setSelectedRange(target.replacementRange, in: target.element) else {
            return .unavailable
        }
        guard
            AXUIElementSetAttributeValue(
                target.element,
                kAXSelectedTextAttribute as CFString,
                injected.text as CFString) == .success
        else {
            _ = setSelectedRange(target.originalRange, in: target.element)
            return .unavailable
        }

        let observed = stringValue(in: target.element)
        guard let observed,
            let stringRange = Range(target.replacementRange, in: target.value)
        else {
            _ = setSelectedRange(target.originalRange, in: target.element)
            return .unavailable
        }
        var expected = target.value
        expected.replaceSubrange(stringRange, with: injected.text)
        guard observed == expected else {
            _ = setSelectedRange(target.originalRange, in: target.element)
            return observed == target.value ? .unavailable : .rejected
        }

        _ = setSelectedRange(
            NSRange(
                location: target.replacementRange.location + injected.caretPrefixLength, length: 0),
            in: target.element)
        return .delivered
    }

    private func accessibilityTarget(
        in targetApp: NSRunningApplication
    ) -> AccessibilityTargetState {
        inspectAccessibilityTarget(in: targetApp)
    }

    private func inspectAccessibilityTarget(
        in targetApp: NSRunningApplication
    ) -> AccessibilityTargetState {
        guard let element = AccessibilityText.focusedElement(in: targetApp),
            !usesTextMarkerSelection(element),
            isAttributeSettable(kAXSelectedTextRangeAttribute, in: element),
            isAttributeSettable(kAXSelectedTextAttribute, in: element),
            let value = stringValue(in: element),
            let originalRange = selectedRange(in: element)
        else { return .unavailable }

        // Offsets its own value cannot address are a broken tier, not proof the document moved.
        guard Range(originalRange, in: value) != nil else { return .unavailable }
        return .ready(
            AccessibilityTarget(
                element: element, value: value, originalRange: originalRange,
                replacementRange: originalRange))
    }

    /// Web content and Monaco expose selection only as markers; their `AXValue` trails or is empty.
    private func usesTextMarkerSelection(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextMarkerRangeAttribute as CFString,
                &value) == .success,
            let value
        else { return false }
        return CFGetTypeID(value) == AXTextMarkerRangeGetTypeID()
    }

    private func waitForPasteConfirmation(
        previousState: AccessibilityTextState?,
        pasteboardLease: TemporaryPasteboardLease,
        targetApp: NSRunningApplication?
    ) async -> Bool {
        var readStateAfterPaste = false
        for attempt in 0..<80 {
            guard pasteboardLease.isOwned,
                deliveryIsAllowed(
                    targetApp: targetApp,
                    promptForInteractiveAccessibility: false)
            else { return false }

            if let previousState,
                let currentState = accessibilityTextState(in: targetApp)
            {
                readStateAfterPaste = true
                if currentState != previousState { return true }
            }
            if PasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: attempt,
                hadPreviousState: previousState != nil,
                readStateAfterPaste: readStateAfterPaste)
            {
                return true
            }
            guard await wait(for: .milliseconds(25)) else { return false }
        }
        return false
    }

    private func accessibilityTextState(
        in targetApp: NSRunningApplication?
    ) -> AccessibilityTextState? {
        guard let targetApp,
            let element = AccessibilityText.focusedElement(in: targetApp),
            !usesTextMarkerSelection(element),
            let value = stringValue(in: element),
            let selectedRange = selectedRange(in: element)
        else { return nil }
        return AccessibilityTextState(value: value, selectedRange: selectedRange)
    }

    private func stringValue(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXValueAttribute as CFString,
                &value) == .success
        else { return nil }
        return value as? String
    }

    private func selectedRange(in element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func setSelectedRange(_ range: NSRange, in element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value) == .success
    }

    private func isAttributeSettable(_ attribute: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard
            AXUIElementIsAttributeSettable(
                element,
                attribute as CFString,
                &settable) == .success
        else { return false }
        return settable.boolValue
    }

    private func activate(_ targetApp: NSRunningApplication?) {
        guard targetApp?.isTerminated == false else { return }
        targetApp?.activate()
    }

    private func selection(in target: InjectionTarget?) -> String {
        switch target {
        case .ownEditor(let editor): return editor.injectableSelection
        case .external(let app): return selectedText(in: app) ?? ""
        case nil: return ""
        }
    }

    private func selectedText(in targetApp: NSRunningApplication?) -> String? {
        guard Permissions.isAccessibilityTrusted(), let targetApp else { return nil }
        return AccessibilityText.selection(in: targetApp)
    }

    private func makeUnicodeEvents(_ text: String) -> [[CGEvent]]? {
        guard !text.isEmpty else { return [] }
        var groups: [[CGEvent]] = []
        for chunk in UnicodeTypingChunk.split(text) {
            guard let pair = makeUnicodeEvent(chunk) else { return nil }
            groups.append(pair)
        }
        return groups
    }

    private func makeUnicodeEvent(_ chunk: [UniChar]) -> [CGEvent]? {
        let source = CGEventSource(stateID: .combinedSessionState)
        var characters = chunk
        guard
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false)
        else { return nil }

        tag(down)
        tag(up)
        down.keyboardSetUnicodeString(
            stringLength: characters.count,
            unicodeString: &characters)
        up.keyboardSetUnicodeString(
            stringLength: characters.count,
            unicodeString: &characters)
        return [down, up]
    }

    private func makeKeyEvents(
        code: CGKeyCode,
        flags: CGEventFlags = []
    ) -> [CGEvent]? {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source,
                virtualKey: code,
                keyDown: false)
        else { return nil }
        down.flags = flags
        up.flags = flags
        tag(down)
        tag(up)
        return [down, up]
    }

    private func postKey(code: CGKeyCode, targetApp: NSRunningApplication?) -> Bool {
        guard let events = makeKeyEvents(code: code) else { return false }
        post(events, targetApp: targetApp)
        return true
    }

    private func tag(_ event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: Paster.tinycastEventTag)
    }

    private func post(_ events: [CGEvent], targetApp: NSRunningApplication?) {
        for event in events { post(event, targetApp: targetApp) }
    }

    private func post(_ event: CGEvent, targetApp: NSRunningApplication?) {
        if let pid = targetApp?.processIdentifier {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func wait(for duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return !Task.isCancelled
        } catch {
            return false
        }
    }
}

/// Blink keeps one key event's text in a fixed four-unit array, so Chromium drops everything past it.
enum UnicodeTypingChunk {
    static let maxUTF16Units = 4

    /// Split on scalar boundaries: a lone surrogate half is not text, and a scalar always fits four.
    static func split(_ text: String) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        current.reserveCapacity(maxUTF16Units)
        for scalar in text.unicodeScalars {
            if current.count + UTF16.width(scalar) > maxUTF16Units {
                chunks.append(current)
                current = []
            }
            UTF16.encode(scalar) { current.append($0) }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

enum PasteConfirmationPolicy {
    static func acceptsUnconfirmedDelivery(
        attempt: Int,
        hadPreviousState: Bool,
        readStateAfterPaste: Bool
    ) -> Bool {
        attempt >= 15 && (!hadPreviousState || !readStateAfterPaste)
    }
}

@MainActor
final class DeliveryQueue {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tail: (id: UUID, task: Task<Void, Never>)?

    var isIdle: Bool { tasks.isEmpty }

    func enqueue(
        operation: @escaping @MainActor () async -> Void
    ) {
        let id = UUID()
        let predecessor = tail?.task
        let task = Task { @MainActor [weak self] in
            await predecessor?.value
            guard let self else { return }
            defer { self.finish(id: id) }
            guard !Task.isCancelled else { return }
            await operation()
        }
        tasks[id] = task
        tail = (id, task)
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        tail = nil
    }

    func drain() async {
        await tail?.task.value
    }

    private func finish(id: UUID) {
        tasks.removeValue(forKey: id)
        if tail?.id == id { tail = nil }
    }
}

@MainActor
protocol PasteboardAccess: AnyObject {
    var changeCount: Int { get }
    var pasteboardItems: [NSPasteboardItem]? { get }
    @discardableResult func clearContents() -> Int
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: PasteboardAccess {}

@MainActor
final class TemporaryPasteboardLease {
    enum RestoreResult: Equatable {
        case restored(changeCount: Int)
        case superseded
        case failed
    }

    private let pasteboard: any PasteboardAccess
    private let ownedChangeCount: Int
    private let original: PasteboardSnapshot
    private var isFinished = false

    var isOwned: Bool {
        !isFinished && pasteboard.changeCount == ownedChangeCount
    }

    private init(
        pasteboard: any PasteboardAccess,
        ownedChangeCount: Int,
        original: PasteboardSnapshot
    ) {
        self.pasteboard = pasteboard
        self.ownedChangeCount = ownedChangeCount
        self.original = original
    }

    static func begin(
        text: String,
        pasteboard: any PasteboardAccess,
        onMutation: (Int) -> Void = { _ in }
    ) -> TemporaryPasteboardLease? {
        // Whole, and deliberately so: this lease is a promise to hand every type back. Snapshotting
        // part of an image-bearing board would drop everything the budget refused.
        guard let snapshot = PasteboardSnapshot(pasteboard: pasteboard, extent: .whole),
            let temporaryItem = PasteboardSnapshot.temporaryItem(carrying: text),
            let originalItems = snapshot.pasteboardItems(),
            pasteboard.changeCount == snapshot.changeCount
        else { return nil }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([temporaryItem]) else {
            if originalItems.isEmpty || pasteboard.writeObjects(originalItems) {
                onMutation(pasteboard.changeCount)
            }
            return nil
        }
        let ownedChangeCount = pasteboard.changeCount
        onMutation(ownedChangeCount)
        return TemporaryPasteboardLease(
            pasteboard: pasteboard,
            ownedChangeCount: ownedChangeCount,
            original: snapshot)
    }

    /// The lent board holds nothing of the original, so restoring rewrites the snapshot whole.
    func restoreIfOwned() -> RestoreResult {
        guard !isFinished else { return .superseded }
        guard pasteboard.changeCount == ownedChangeCount else {
            isFinished = true
            return .superseded
        }
        guard let items = original.pasteboardItems() else { return .failed }
        pasteboard.clearContents()
        isFinished = true
        guard items.isEmpty || pasteboard.writeObjects(items) else { return .failed }
        return .restored(changeCount: pasteboard.changeCount)
    }
}

@MainActor
struct PasteboardSnapshot {
    struct Item {
        let values: [(type: NSPasteboard.PasteboardType, data: Data)]
    }

    let items: [Item]
    let changeCount: Int

    var firstStringData: Data? {
        items.first?.values.first { $0.type == .string }?.data
    }

    /// How much of the board a snapshot is allowed to take. Every caller names one, because the two
    /// answers differ: borrowing the board is a promise to give all of it back, while reading it for
    /// a selection is a favour that can be refused.
    enum Extent {
        /// Everything, whatever it costs. For a caller about to clear the board and restore it, where
        /// taking half means losing the other half permanently.
        case whole
        /// Up to `SnapshotBudget`, with volumous types refused by name. For a caller that reads the
        /// board opportunistically and can simply do without the answer.
        case budgeted
    }

    init?(pasteboard: any PasteboardAccess, extent: Extent) {
        let changeCount = pasteboard.changeCount
        var items: [Item] = []
        var total = 0
        for pasteboardItem in pasteboard.pasteboardItems ?? [] {
            // Types first, sizes second: a volumous type is refused by its name, before any read.
            // Measuring a type's data is already the cost this budget exists to avoid.
            if extent == .budgeted,
               pasteboardItem.types.contains(where: { Self.isVoluminous($0) })
            {
                return nil
            }
            var values: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            for type in pasteboardItem.types {
                guard let data = pasteboardItem.data(forType: type) else { return nil }
                if extent == .budgeted {
                    guard data.count <= SnapshotBudget.maxSingleTypeBytes else { return nil }
                    total += data.count
                    guard total <= SnapshotBudget.maxTotalBytes else { return nil }
                }
                values.append((type: type, data: data))
            }
            items.append(Item(values: values))
        }
        guard pasteboard.changeCount == changeCount else { return nil }
        self.items = items
        self.changeCount = changeCount
    }

    /// What a snapshot may cost this process to take.
    ///
    /// Taking a selection by copy borrows the reader's whole pasteboard first, and that pasteboard
    /// may hold a screenshot, a movie or an archive — a well-behaved resident tool should not weigh
    /// 150MB because somebody selected two words next to what they copied earlier. Failing the
    /// selection is the right trade: a snapshot is only ever taken to clear the board and put it
    /// back, and losing all of it is far worse than losing this one read.
    private enum SnapshotBudget {
        /// Everything together, past which the fallback is abandoned whole.
        static let maxTotalBytes = 2 * 1024 * 1024
        /// One type on its own: "the total fits" is no cover for one enormous member.
        static let maxSingleTypeBytes = 1024 * 1024
    }

    /// Whether a type announces bulk without being read. A promised type is refused outright: its
    /// real size is whatever its provider says, and asking means starting that provider's process.
    private static func isVoluminous(_ type: NSPasteboard.PasteboardType) -> Bool {
        let raw = type.rawValue
        if raw.localizedCaseInsensitiveContains("promised") { return true }
        guard let declared = UTType(raw) else { return false }
        return declared.conforms(to: .image)
            || declared.conforms(to: .movie)
            || declared.conforms(to: .audio)
            || declared.conforms(to: .archive)
            || declared.conforms(to: .executable)
            || declared.conforms(to: .diskImage)
    }

    /// A kept `public.html` is the flavour a Chromium editor prefers, so we lend the text alone.
    static func temporaryItem(carrying text: String) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string),
            item.setData(Data(), forType: ClipboardManager.internalType)
        else { return nil }
        return item
    }

    func pasteboardItems() -> [NSPasteboardItem]? {
        var pasteboardItems: [NSPasteboardItem] = []
        pasteboardItems.reserveCapacity(items.count)
        for item in items {
            let pasteboardItem = NSPasteboardItem()
            for value in item.values {
                guard pasteboardItem.setData(value.data, forType: value.type) else { return nil }
            }
            pasteboardItems.append(pasteboardItem)
        }
        return pasteboardItems
    }
}
