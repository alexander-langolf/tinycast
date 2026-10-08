import SwiftUI

private struct ForkAppearanceScope: ViewModifier {
    func body(content: Content) -> some View {
        let fontFamily = ForkAppearance.current?.fontFamily
        let content = content.id(fontFamily ?? "system")
        if let accent = ForkAppearance.current?.colors.accent?.color {
            content.tint(accent).accentColor(accent)
        } else {
            content
        }
    }
}

extension View {
    func forkAppearance() -> some View { modifier(ForkAppearanceScope()) }
}
