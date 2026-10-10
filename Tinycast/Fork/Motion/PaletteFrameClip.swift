import SwiftUI

/// The palette's outline, following the window animator's radius so corners morph with the frame.
struct PaletteFrameClip: ViewModifier {
    let radius: CGFloat
    @Environment(PaletteFrameAnimator.self) private var animator

    func body(content: Content) -> some View {
        content.clipShape(
            RoundedRectangle(cornerRadius: animator.cornerRadius ?? radius, style: .continuous))
    }
}

extension View {
    /// `radius` is the resting value; the animator's own wins while it has one.
    func paletteFrameClip(radius: CGFloat) -> some View {
        modifier(PaletteFrameClip(radius: radius))
    }
}
