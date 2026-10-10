import SwiftUI

/// Lays the palette out at its destination height while the window moves, top edge pinned.
struct PaletteFrameLayout: ViewModifier {
    @Environment(PaletteFrameAnimator.self) private var animator

    func body(content: Content) -> some View {
        // An overlay may overflow its base, so the clipped window reveals content rather than squeezing it.
        Color.clear.overlay(alignment: .top) {
            content.frame(height: animator.layoutHeight, alignment: .top)
        }
    }
}

extension View {
    func paletteFrameLayout() -> some View {
        modifier(PaletteFrameLayout())
    }
}
