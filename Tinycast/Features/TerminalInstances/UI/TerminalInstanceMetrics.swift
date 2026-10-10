import AppKit

/// The instance's own geometry: the palette's compact bar on top, `TerminalLogView`'s face below.
@MainActor
struct TerminalInstanceMetrics {
    let metrics: InterfaceMetrics

    /// The four grid faces and the cell they measure, resolved once per Monospaced font setting.
    struct Faces {
        let family: String?
        let regular: NSFont
        let bold: NSFont
        let italic: NSFont
        let boldItalic: NSFont
        let rowHeight: CGFloat
        let characterWidth: CGFloat

        init(family: String?) {
            self.family = family
            let typography = ForkTypography.shared
            func face(_ weight: NSFont.Weight, italic: Bool) -> NSFont {
                var base = NSFont.monospacedSystemFont(ofSize: 12, weight: weight)
                if italic { base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) }
                return typography.monoFace(base)
            }
            regular = face(.regular, italic: false)
            bold = face(.bold, italic: false)
            italic = face(.regular, italic: true)
            boldItalic = face(.bold, italic: true)
            rowHeight = ceil(NSLayoutManager().defaultLineHeight(for: regular))
            characterWidth = ("M" as NSString).size(withAttributes: [.font: regular]).width
        }
    }

    private static var cachedFaces = Faces(family: ForkTypography.shared.monoFamily)

    /// Follows Settings → Monospaced font; remeasured only when the family changes.
    static var faces: Faces {
        let family = ForkTypography.shared.monoFamily
        if cachedFaces.family != family { cachedFaces = Faces(family: family) }
        return cachedFaces
    }

    static var logFont: NSFont { faces.regular }
    static let logInset = CGSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xs)
    static var rowHeight: CGFloat { faces.rowHeight }
    static var characterWidth: CGFloat { faces.characterWidth }
    static let restackDuration: TimeInterval = 0.18

    var width: CGFloat { metrics.size.panelWidth }
    var barHeight: CGFloat { metrics.size.compactHeight }
    var gap: CGFloat { metrics.spacing.md }
    var maxOutput: CGFloat { metrics.scaled(340) }
    var columns: Int { max(20, Int((width - Self.logInset.width * 2) / Self.characterWidth)) }
    /// Viewport rows of the ghostty grid: whole rows that fit under `maxOutput` with the log's inset.
    var gridRows: Int { Int((maxOutput - Self.logInset.height * 2) / Self.rowHeight) }
    var rowCap: Int { Int((maxOutput / Self.rowHeight).rounded(.up)) + 1 }
}
