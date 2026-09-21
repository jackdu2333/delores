import AppKit
// `@preconcurrency` downgrades AX diagnostics: the attribute keys are constant C globals.
@preconcurrency import ApplicationServices

/// Always against a named process: the system-wide focus answers with ours.
enum AccessibilityText {
    /// Generous for a responsive app, short enough that a wedged one can't stall the main actor.
    private static let timeout: Float = 1
    /// Enough to climb out of a chat bubble, short enough not to walk a whole Electron tree.
    private static let ancestorLimit = 8

    /// The two have different fixes; collapsing them tells a reader to select what they selected.
    enum Selection: Equatable {
        case text(String)
        case noFocusedElement
        case empty
    }

    static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        let application = applicationElement(for: app)
        var focusedValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXFocusedUIElementAttribute as CFString,
                &focusedValue) == .success,
            let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func read(in app: NSRunningApplication) -> Selection {
        guard let element = focusedElement(in: app) else { return .noFocusedElement }
        return selection(from: element) ?? .empty
    }

    /// A narrower question, for callers that can act on the text but not on why there is none.
    static func selection(in app: NSRunningApplication) -> String? {
        guard case .text(let text) = read(in: app) else { return nil }
        return text
    }

    /// Automatic capture already knows where the gesture ended; some hosts keep focus on a container.
    @MainActor
    static func selection(in app: NSRunningApplication, at cocoaPoint: CGPoint) -> String? {
        if let text = selection(in: app) { return text }
        let application = applicationElement(for: app)
        guard let hit = element(at: cocoaPoint, in: application) else { return nil }
        var current: AXUIElement? = hit
        var seen = Set<ObjectIdentifier>()
        for _ in 0..<ancestorLimit {
            guard let element = current else { break }
            let identity = ObjectIdentifier(element)
            guard seen.insert(identity).inserted else { break }
            if case .text(let text) = selection(from: element) { return text }
            current = parent(of: element)
        }
        return nil
    }

    private static func applicationElement(for app: NSRunningApplication) -> AXUIElement {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Per element and never inherited, so each hop below needs its own against a hang.
        AXUIElementSetMessagingTimeout(application, timeout)
        activateManualAccessibility(of: application)
        return application
    }

    private static func selection(from element: AXUIElement) -> Selection? {
        if let text = selectedText(in: element) { return .text(text) }
        if let text = rangedSelection(in: element) { return .text(text) }
        if let text = webSelection(in: element) { return .text(text) }
        return nil
    }

    private static func selectedText(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                &value) == .success,
            let text = value as? String, !text.isEmpty
        else { return nil }
        return text
    }

    /// Some hosts expose a range into AXValue instead of a ready-made selected-text string.
    private static func rangedSelection(in element: AXUIElement) -> String? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                &rangeValue) == .success,
            let rangeValue
        else { return nil }

        var parameterized: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &parameterized) == .success,
            let text = parameterized as? String, !text.isEmpty
        {
            return text
        }

        guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        let axValue = rangeValue as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.length > 0 else { return nil }
        var whole: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &whole) == .success,
            let value = whole as? String
        else { return nil }
        let location = range.location
        let length = range.length
        guard location >= 0, length > 0, location + length <= value.utf16.count else { return nil }
        let start = String.Index(utf16Offset: location, in: value)
        let end = String.Index(utf16Offset: location + length, in: value)
        let slice = String(value[start..<end])
        return slice.isEmpty ? nil : slice
    }

    @MainActor
    private static func element(at cocoaPoint: CGPoint, in application: AXUIElement) -> AXUIElement? {
        let axPoint = AXGeometry(screens: NSScreen.screens).flip(cocoaPoint)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            application, Float(axPoint.x), Float(axPoint.y), &hit) == .success
        else { return nil }
        if let hit { AXUIElementSetMessagingTimeout(hit, timeout) }
        return hit
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
                == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let parent = value as! AXUIElement
        AXUIElementSetMessagingTimeout(parent, timeout)
        return parent
    }

    /// Chromium builds its tree only once asked, so Chrome and Electron answer nothing until this.
    private static func activateManualAccessibility(of application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Browsers have no `AXSelectedText`: web selection exists only as an opaque marker range.
    private static func webSelection(in element: AXUIElement) -> String? {
        var range: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element,
                kAXSelectedTextMarkerRangeAttribute as CFString,
                &range) == .success,
            let range,
            CFGetTypeID(range) == AXTextMarkerRangeGetTypeID()
        else { return nil }

        var value: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
                range,
                &value) == .success
        else { return nil }
        return value as? String
    }
}
