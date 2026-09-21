import Foundation

enum DeloresAutomaticSelectionCompatibility {
    static let weChatBundleIdentifier = "com.tencent.xinWeChat"

    // WeChat chat bubbles expose no AX selection; only a drag may borrow one ⌘C.
    static func allowsClipboardFallback(
        bundleIdentifier: String?,
        gesture: DeloresSelectionGesturePolicy.Kind
    ) -> Bool {
        gesture == .drag && bundleIdentifier == weChatBundleIdentifier
    }
}
