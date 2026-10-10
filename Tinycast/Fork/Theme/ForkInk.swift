import SwiftUI

/// Which colours a fork-owned surface draws: the live theme, or one Settings is previewing.
enum ForkColorPreview: Equatable, Sendable {
    case live
    /// Nil previews Tinycast's own look, whatever theme is applied.
    case showing(ForkColorPalette?, isDark: Bool)
}

extension EnvironmentValues {
    @Entry var forkColorPreview = ForkColorPreview.live
}

/// The inks of the agent and terminal cards, so Settings can draw them in a theme not yet applied.
struct ForkInk {
    private let palette: ForkColorPalette?
    private let theme: ForkTheme
    /// Set only when previewing Tinycast's look while a theme is live, which `Theme` can't show.
    private let tinycastIsDark: Bool?

    init(_ preview: ForkColorPreview, theme: ForkTheme = .current) {
        self.theme = theme
        switch preview {
        case .live:
            palette = theme.palette
            tinycastIsDark = nil
        case .showing(let palette, let isDark):
            self.palette = palette
            tinycastIsDark = palette == nil && theme.palette != nil ? isDark : nil
        }
    }

    var themePalette: ForkColorPalette? { palette }

    var textPrimary: Color { ink(.text, ramp: (1.0, 1.0), Theme.Colors.textPrimary) }
    var textSecondary: Color { ink(.secondaryText, ramp: (0.60, 0.60), Theme.Colors.textSecondary) }
    var textTertiary: Color { ink(.secondaryText, alpha: 0.75, ramp: (0.40, 0.42), Theme.Colors.textTertiary) }
    var selection: Color { ink(.accent, alpha: 0.28, ramp: (0.10, 0.09), Theme.Colors.selection) }
    var iconPlaceholder: Color { ink(.text, alpha: 0.06, ramp: (0.06, 0.06), Theme.Colors.iconPlaceholder) }
    var rowHover: Color { ink(.accent, alpha: 0.12, ramp: (0.05, 0.045), Theme.Colors.rowHover) }
    var separator: Color { ink(.border, alpha: 0.7, ramp: (0.10, 0.12), Theme.Colors.separator) }
    var border: Color { ink(.border, ramp: (0.20, 0.18), Theme.Colors.border) }
    var accent: Color { palette.map { Color(nsColor: $0.nsColor(.accent)) } ?? .accentColor }
    /// The palette's surface, as the terminal card and the palette edge draw it.
    var paletteScrim: AnyShapeStyle { scrim(.background) { theme.paletteScrim } }
    var terminalScrim: AnyShapeStyle { scrim(.terminal) { theme.terminalScrim } }

    var warning: Color { status(.warning, Theme.Colors.warning) }
    var error: Color { status(.error, Theme.Colors.destructive) }

    private func ink(
        _ slot: ForkColorTheme.Slot, alpha: Double = 1, ramp: (dark: Double, light: Double), _ upstream: Color
    ) -> Color {
        if let palette { return Color(nsColor: palette.nsColor(slot, alpha: alpha)) }
        guard let tinycastIsDark else { return upstream }
        // Restates `Theme.Colors.ramp`, which a live theme intercepts.
        return Color(nsColor: .srgbInk(tinycastIsDark ? 1 : 0, alpha: tinycastIsDark ? ramp.dark : ramp.light))
    }

    private func scrim(_ slot: ForkColorTheme.Slot, live: () -> AnyShapeStyle) -> AnyShapeStyle {
        if let palette { return theme.scrim(palette, slot) }
        guard let tinycastIsDark else { return live() }
        let ink = NSColor.srgbInk(tinycastIsDark ? 0 : 1, alpha: tinycastIsDark ? 0.40 : 0.55)
        return AnyShapeStyle(Color(nsColor: ink))
    }

    private func status(_ slot: ForkColorTheme.Slot, _ upstream: Color) -> Color {
        palette.map { Color(nsColor: $0.nsColor(slot)) } ?? upstream
    }
}
