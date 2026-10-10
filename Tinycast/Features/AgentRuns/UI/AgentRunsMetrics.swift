import SwiftUI

/// The cards' geometry and type: Settings → Appearance → Agent Card, at the user's Interface Size.
struct AgentRunsMetrics {
    let metrics: InterfaceMetrics
    var theme = ForkTheme.current

    var sideWidth: CGFloat { metrics.scaled(360) }
    var statusDot: CGFloat { theme.points(.agentCardDotSize, metrics) }
    var dotGap: CGFloat { theme.points(.agentCardDotGap, metrics) }
    var horizontalPadding: CGFloat { theme.points(.agentCardHorizontalPadding, metrics) }
    /// Air above and below the two text lines, which otherwise touch the card's edges.
    var cardVerticalPadding: CGFloat { theme.points(.agentCardVerticalPadding, metrics) }
    var gap: CGFloat { theme.points(.agentCardGap, metrics) }
    var paletteMargin: CGFloat { theme.points(.agentCardMargin, metrics) }
    var cornerRadius: CGFloat { theme.points(.agentCardCornerRadius, metrics) }
    var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    var titleFont: Font {
        theme.font(.agentCardTitleSize, style: .body, metrics) ?? metrics.typography.rowTitle
    }
    var detailFont: Font {
        theme.font(.agentCardDetailSize, style: .caption1, metrics) ?? metrics.typography.keyCap
    }
    var trailingFont: Font {
        theme.font(.agentCardTrailingSize, style: .callout, metrics) ?? metrics.typography.rowTrailing
    }

    /// A colour theme's surface, mostly solid unless the opacity token is set, or the glass alone.
    func scrim(_ ink: ForkInk) -> AnyShapeStyle {
        let opacity = theme.number(.agentCardScrimOpacity)
        if let palette = ink.themePalette {
            let solid = theme.isOverridden(.agentCardScrimOpacity) ? opacity : ForkColorPalette.surfaceOpacity
            return AnyShapeStyle(Color(nsColor: palette.nsColor(.surface, alpha: solid)))
        }
        return AnyShapeStyle(opacity > 0 ? ForkTheme.scrim(dark: opacity, light: opacity) : .clear)
    }

    /// One launcher row plus the vertical padding; the stack and the panel's frame both size from it.
    var cardHeight: CGFloat {
        let row = metrics.size.rowIcon + metrics.spacing.sm * 2
        return max(row, textHeight) + cardVerticalPadding * 2
    }

    /// Zero until a font size is set, so the default card keeps exactly the row's height.
    private var textHeight: CGFloat {
        let sizes: [ForkThemeToken] = [.agentCardTitleSize, .agentCardDetailSize, .agentCardTrailingSize]
        guard sizes.contains(where: theme.isOverridden) else { return 0 }
        func line(_ token: ForkThemeToken, _ style: NSFont.TextStyle) -> CGFloat {
            let font = theme.nsFont(token, style: style, metrics)
            return ceil(font.ascender - font.descender + font.leading)
        }
        let leading = line(.agentCardTitleSize, .body) + line(.agentCardDetailSize, .caption1)
        return max(leading, line(.agentCardTrailingSize, .callout) * 2)
    }
}
