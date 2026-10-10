import AppKit
import SwiftUI

/// The design tokens in effect: an override for each changed token, today's value for the rest.
struct ForkTheme: Equatable, Sendable {
    var overrides: [ForkThemeToken: ForkThemeValue] = [:]

    /// The live tokens; a read inside a view body or an observation re-runs it when they change.
    static var current: ForkTheme { ForkThemeState.shared.theme }

    /// The override alone, for a seam whose fallback must stay upstream's own expression.
    static func override(_ token: ForkThemeToken) -> CGFloat? {
        current.overrides[token]?.number.map { CGFloat($0) }
    }

    func isOverridden(_ token: ForkThemeToken) -> Bool { overrides[token] != nil }

    func number(_ token: ForkThemeToken) -> Double {
        overrides[token]?.number ?? token.defaultNumber(in: self)
    }

    func flag(_ token: ForkThemeToken) -> Bool {
        overrides[token]?.flag ?? token.defaultFlag
    }

    /// Nil while unset: the surface keeps its own adaptive ink.
    func color(_ token: ForkThemeToken) -> Color? {
        overrides[token]?.color.map {
            Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha)
        }
    }

    /// The token at the user's Interface Size, for the kinds that scale with it.
    func points(_ token: ForkThemeToken, _ metrics: InterfaceMetrics) -> CGFloat {
        let value = CGFloat(number(token))
        switch token.kind {
        case .length(_, _, let scales), .fontSize(_, let scales):
            return scales ? metrics.scaled(value) : value
        case .opacity, .flag, .color: return value
        }
    }

    /// A text style at the token's size, in the interface font; nil while unset keeps the style itself.
    func font(_ token: ForkThemeToken, style: NSFont.TextStyle, _ metrics: InterfaceMetrics) -> Font? {
        guard isOverridden(token) else { return nil }
        return Font(nsFont(token, style: style, metrics))
    }

    func nsFont(_ token: ForkThemeToken, style: NSFont.TextStyle, _ metrics: InterfaceMetrics) -> NSFont {
        let base = NSFont.preferredFont(forTextStyle: style)
        let sized = NSFont(descriptor: base.fontDescriptor, size: points(token, metrics)) ?? base
        return ForkTypography.resolve(sized)
    }

    /// The panel ink at the given alphas: black over Dark's surface, white over Light's.
    static func scrim(dark: Double, light: Double) -> Color {
        Theme.Colors.adaptive(dark: .srgbInk(0, alpha: dark), light: .srgbInk(1, alpha: light))
    }

    var paletteScrim: Color {
        guard isOverridden(.paletteScrimDark) || isOverridden(.paletteScrimLight) else {
            return Theme.Colors.panelScrim
        }
        return Self.scrim(dark: number(.paletteScrimDark), light: number(.paletteScrimLight))
    }

    func hasOverrides(in component: ForkThemeToken.Component) -> Bool {
        overrides.keys.contains { $0.component == component }
    }
}

extension ForkThemeToken {
    /// Today's value, restated from the token it always read, so an unset token changes nothing.
    func defaultNumber(in theme: ForkTheme) -> Double {
        switch self {
        case .agentCardHorizontalPadding: Double(Theme.Spacing.xl)
        case .agentCardVerticalPadding: Double(Theme.Spacing.sm)
        case .agentCardGap: Double(Theme.Spacing.md)
        case .agentCardMargin: Double(Theme.Spacing.xl)
        case .agentCardCornerRadius, .terminalCornerRadius: theme.number(.paletteCornerRadius)
        case .agentCardScrimOpacity: 0
        case .agentCardBorderWidth, .terminalDividerWidth, .paletteBorderWidth: Double(Theme.Size.hairline)
        case .agentCardTitleSize: Double(NSFont.preferredFont(forTextStyle: .body).pointSize)
        case .agentCardDetailSize: Double(NSFont.preferredFont(forTextStyle: .caption1).pointSize)
        case .agentCardTrailingSize: Double(NSFont.preferredFont(forTextStyle: .callout).pointSize)
        case .agentCardDotSize: 6
        case .terminalBarHeight:
            Double(Theme.Size.headerHeight) + theme.number(.paletteHeaderPadding) * 2
        case .terminalGutter: Double(Theme.Spacing.md * 2)
        case .terminalGridFontSize: 12
        case .terminalOutputInsetHorizontal: Double(Theme.Spacing.xxl)
        case .terminalOutputInsetVertical: Double(Theme.Spacing.xs)
        case .paletteCornerRadius: Double(Theme.Radius.panel)
        case .paletteRowPadding: Double(Theme.Spacing.sm)
        case .paletteRowCornerRadius: Double(Theme.Radius.row)
        case .paletteSearchFieldSize: Double(Theme.Typography.searchFieldSize)
        case .paletteHeaderPadding: Double(Theme.Size.headerPadding)
        // `panelScrim`'s two literals, restated.
        case .paletteScrimDark: 0.40
        case .paletteScrimLight: 0.55
        case .agentCardBorder, .terminalDivider, .paletteBorder, .agentCardBorderColor,
            .agentCardModelColor, .paletteBorderColor:
            0
        }
    }

    var defaultFlag: Bool { self == .terminalDivider }

    /// Nil for a colour: unset is the surface's own adaptive ink, which no single value states.
    func defaultValue(in theme: ForkTheme) -> ForkThemeValue? {
        switch kind {
        case .flag: .flag(defaultFlag)
        case .color: nil
        case .length, .fontSize, .opacity: .number(defaultNumber(in: theme))
        }
    }
}
