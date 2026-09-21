import SwiftUI

/// The pane that answers 分屏.
///
/// It used to be one section at the bottom of upstream's Window Management pane, under a switch that
/// gated nothing this section touched — which is why turning the pane's own switch off left snapping
/// running. Upstream's window management is no longer offered, so the two ways a drag splits a
/// screen own a pane of their own and every switch in it is one the reader can see the effect of.
struct SplitScreenSettingsView: View {
    var body: some View {
        Form {
            WindowSnappingSection()
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.splitScreen)
    }
}
