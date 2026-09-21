import Foundation

enum DeloresAutomaticSelectionCompatibility {
    static let weChatBundleIdentifier = "com.tencent.xinWeChat"
    static let weComCustomizedBundleIdentifier = "com.tencent.WxWorkMacEntCustomized"

    private static let clipboardFallbackBundleIdentifiers: Set<String> = [
        weChatBundleIdentifier,
        weComCustomizedBundleIdentifier,
    ]

    // WeChat/WeCom chat bubbles expose no AX selection; only a drag may borrow one ⌘C.
    static func allowsClipboardFallback(
        bundleIdentifier: String?,
        gesture: DeloresSelectionGesturePolicy.Kind
    ) -> Bool {
        gesture == .drag
            && bundleIdentifier.map(clipboardFallbackBundleIdentifiers.contains) == true
    }
}
