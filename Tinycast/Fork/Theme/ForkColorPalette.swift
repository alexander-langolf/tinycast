import AppKit

/// A theme ready to draw: readable inks, its base appearance and its map onto `Theme.Colors`.
struct ForkColorPalette: Hashable, Sendable {
    typealias Slot = ForkColorTheme.Slot
    typealias Color = ForkThemeValue.Color

    /// Mid-grey's WCAG luminance: the background equally far, in contrast, from white and black.
    static let darkThreshold = 0.179
    static let minimumContrast = 4.5
    /// How solid a themed surface is over the glass, unless a scrim token says otherwise.
    static let surfaceOpacity = 0.85

    let theme: ForkColorTheme
    let slots: [Slot: Color]
    /// The slots moved toward white or black to reach `minimumContrast`, with the ratio they had.
    let adjusted: [Slot: Double]
    let isDark: Bool

    init(theme: ForkColorTheme) {
        self.theme = theme
        var slots = theme.baseSlots
        let background = slots[.background] ?? .black
        let isDark = background.luminance < Self.darkThreshold
        var adjusted: [Slot: Double] = [:]
        for slot in [Slot.text, .secondaryText] {
            guard let ink = slots[slot] else { continue }
            let ratio = ink.contrast(with: background)
            guard ratio < Self.minimumContrast else { continue }
            slots[slot] = Self.raised(ink, against: background, toward: isDark ? .white : .black)
            adjusted[slot] = ratio
        }
        self.slots = slots
        self.adjusted = adjusted
        self.isDark = isDark
    }

    /// Mixed toward `target` in small steps, so the hue survives as far as contrast allows.
    private static func raised(_ ink: Color, against background: Color, toward target: Color) -> Color {
        var amount = 0.0
        var result = ink
        while result.contrast(with: background) < minimumContrast, amount < 1 {
            amount += 0.05
            result = ink.mixed(with: target, amount: amount)
        }
        return result
    }

    subscript(slot: Slot) -> Color { slots[slot] ?? .black }

    func nsColor(_ slot: Slot, alpha: Double = 1) -> NSColor {
        let color = self[slot]
        return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: alpha * color.alpha)
    }

    var ansi: [Color]? { theme.ansiColors }

    var appearance: NSAppearance? { NSAppearance(named: isDark ? .darkAqua : .aqua) }

    /// The themed colour for an upstream `adaptive` pair, or nil to leave that pair upstream's.
    func color(forUpstream dark: NSColor, light: NSColor) -> NSColor? {
        guard let dark = dark.usingColorSpace(.sRGB), let light = light.usingColorSpace(.sRGB) else {
            return nil
        }
        let alphas = (dark: Self.rounded(dark.alphaComponent), light: Self.rounded(light.alphaComponent))
        if Self.isInk(dark, white: 0), Self.isInk(light, white: 1), alphas == (0.40, 0.55) {
            return nsColor(.background, alpha: Self.surfaceOpacity)
        }
        guard Self.isInk(dark, white: 1), Self.isInk(light, white: 0) else { return nil }
        switch alphas {
        case (1.0, 1.0): return nsColor(.text)
        case (0.60, 0.60): return nsColor(.secondaryText)
        case (0.40, 0.42): return nsColor(.secondaryText, alpha: 0.75)
        case (0.20, 0.18): return nsColor(.border)
        case (0.10, 0.12), (0.10, 0.10): return nsColor(.border, alpha: 0.7)
        case (0.10, 0.09): return nsColor(.accent, alpha: 0.28)
        case (0.05, 0.045): return nsColor(.accent, alpha: 0.12)
        default: return nsColor(.text, alpha: isDark ? alphas.dark : alphas.light)
        }
    }

    /// The ramp's white-over-Dark, black-over-Light inks: everything else is a named colour.
    private static func isInk(_ color: NSColor, white: CGFloat) -> Bool {
        abs(color.redComponent - white) < 0.01 && abs(color.greenComponent - white) < 0.01
            && abs(color.blueComponent - white) < 0.01
    }

    private static func rounded(_ value: CGFloat) -> Double { (Double(value) * 1000).rounded() / 1000 }
}
