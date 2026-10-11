import AppKit

/// The instance's own geometry: the palette's compact bar on top, `TerminalLogView`'s face below.
@MainActor
struct TerminalInstanceMetrics {
    let metrics: InterfaceMetrics
    var theme = ForkTheme.current
    var isEditor = false  // FORK: file-navigator

    /// The four grid faces and the cell they measure, resolved once per Monospaced font and size.
    struct Faces {
        let family: String?
        let size: CGFloat
        let regular: NSFont
        let bold: NSFont
        let italic: NSFont
        let boldItalic: NSFont
        let rowHeight: CGFloat
        let characterWidth: CGFloat

        init(family: String?, size: CGFloat) {
            self.family = family
            self.size = size
            let typography = ForkTypography.shared
            func face(_ weight: NSFont.Weight, italic: Bool) -> NSFont {
                var base = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
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

    private static var cachedFaces = Faces(
        family: ForkTypography.shared.monoFamily, size: gridFontSize(ForkTheme.current))

    private static func gridFontSize(_ theme: ForkTheme) -> CGFloat {
        theme.points(.terminalGridFontSize, .standard)
    }

    /// Follows Settings → Monospaced font and the output font size; remeasured only when either moves.
    static var faces: Faces {
        let family = ForkTypography.shared.monoFamily
        let size = gridFontSize(ForkTheme.current)
        if cachedFaces.family != family || cachedFaces.size != size {
            cachedFaces = Faces(family: family, size: size)
        }
        return cachedFaces
    }

    static var logFont: NSFont { faces.regular }
    /// Around the ghostty grid; `TerminalLogView` keeps its own private inset.
    static var logInset: CGSize {
        let theme = ForkTheme.current
        return CGSize(
            width: theme.points(.terminalOutputInsetHorizontal, .standard),
            height: theme.points(.terminalOutputInsetVertical, .standard))
    }
    static var rowHeight: CGFloat { faces.rowHeight }
    static var characterWidth: CGFloat { faces.characterWidth }
    static let restackDuration: TimeInterval = 0.18

    var width: CGFloat { metrics.size.panelWidth }
    /// The palette's compact bar until Settings → Appearance sets its own height.
    var barHeight: CGFloat {
        theme.isOverridden(.terminalBarHeight)
            ? theme.points(.terminalBarHeight, metrics) : metrics.size.compactHeight
    }
    var gutter: CGFloat { theme.points(.terminalGutter, metrics) }
    var cornerRadius: CGFloat { theme.points(.terminalCornerRadius, metrics) }
    var dividerHeight: CGFloat {
        theme.flag(.terminalDivider) ? theme.points(.terminalDividerWidth, metrics) : 0
    }
    var gap: CGFloat { metrics.spacing.md }
    // FORK: file-navigator
    var maxOutput: CGFloat {
        guard isEditor else { return metrics.scaled(340) }
        let available = NSScreen.main?.visibleFrame.height ?? metrics.scaled(680)
        return max(Self.rowHeight * 8, min(metrics.scaled(680), available - barHeight - gap * 2))
    }
    var columns: Int { max(20, Int((width - Self.logInset.width * 2) / Self.characterWidth)) }
    /// Viewport rows of the ghostty grid: whole rows that fit under `maxOutput` with the log's inset.
    var gridRows: Int { Int((maxOutput - Self.logInset.height * 2) / Self.rowHeight) }
    var rowCap: Int { Int((maxOutput / Self.rowHeight).rounded(.up)) + 1 }
}
