import SwiftUI

/// The palette's outline, following the window animator's radius so corners morph with the frame.
struct PaletteFrameClip: ViewModifier {
    let radius: CGFloat
    var outset: CGFloat = 0
    @Environment(PaletteFrameAnimator.self) private var animator

    func body(content: Content) -> some View {
        let theme = ForkTheme.current
        let shape = RoundedRectangle(cornerRadius: animator.cornerRadius ?? radius, style: .continuous)
            .inset(by: -outset)
        content
            .clipShape(shape)
            .overlay {
                if theme.flag(.paletteBorder) {
                    shape
                        .strokeBorder(
                            theme.color(.paletteBorderColor) ?? Theme.Colors.border,
                            lineWidth: theme.points(.paletteBorderWidth, .standard)
                        )
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// `radius` is the resting value; the animator's own wins while it has one.
    func paletteFrameClip(radius: CGFloat, outset: CGFloat = 0) -> some View {
        modifier(PaletteFrameClip(radius: radius, outset: outset))
    }
}
