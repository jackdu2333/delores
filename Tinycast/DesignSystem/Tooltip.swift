import SwiftUI

/// A hover label in Tinycast's own vocabulary, replacing a system `.help()` tooltip.
private struct TooltipModifier: ViewModifier {
    let text: String?
    /// Delores seam: upstream v0.11.3 rewrote this tile and gave it an alignment; Notes needs the
    /// alignment for a control against a window edge, and the rest of Delores keeps its own chrome.
    var alignment: HorizontalAlignment = .center
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content
            .onHover { hovered = text != nil && $0 }
            .overlay(alignment: Alignment(horizontal: alignment, vertical: .top)) {
                if let text, hovered {
                    Text(text)
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, metrics.spacing.sm)
                        .padding(.vertical, metrics.spacing.xxs)
                        .background(Capsule().fill(Theme.Colors.controlSurface))
                        .overlay(Capsule().strokeBorder(Theme.Colors.border, lineWidth: 1))
                        .fixedSize()
                        .offset(y: -metrics.spacing.xxl)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: Theme.Duration.tooltip), value: hovered)
    }
}

extension View {
    /// Hover label styled like the palette's keycap chips, for our own chrome.
    /// Align it leading or trailing when the control sits against a window edge.
    func tooltip(_ text: String?, alignment: HorizontalAlignment = .center) -> some View {
        modifier(TooltipModifier(text: text, alignment: alignment))
    }
}
