import SwiftUI

private struct ForkAppearanceScope: ViewModifier {
    func body(content: Content) -> some View {
        let fontFamily = ForkAppearance.current?.fontFamily
        let monoFamily = ForkAppearance.current?.monoFontFamily
        let colors = ForkAppearance.current?.colors
        // A dynamic colour already drawn never asks again, so a new theme rebuilds the tree.
        let theme = colors?.theme.map { String($0.hashValue) } ?? "adaptive"
        let content = content.id("\(fontFamily ?? "system")|\(monoFamily ?? "system")|\(theme)")
        if let accent = colors?.effectiveAccent?.color {
            content.tint(accent).accentColor(accent)
        } else {
            content
        }
    }
}

extension View {
    func forkAppearance() -> some View { modifier(ForkAppearanceScope()) }
}
