import AppKit

/// The instance's own geometry: the palette's compact bar on top, `TerminalLogView`'s face below.
@MainActor
struct TerminalInstanceMetrics {
    let metrics: InterfaceMetrics

    /// `TerminalLogView` draws at this fixed face and inset; both are private there, so restated.
    static let logFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let logInset = CGSize(width: Theme.Spacing.xxl, height: Theme.Spacing.xs)
    static let rowHeight = ceil(NSLayoutManager().defaultLineHeight(for: logFont))
    static let characterWidth = ("M" as NSString).size(withAttributes: [.font: logFont]).width
    static let restackDuration: TimeInterval = 0.18

    var width: CGFloat { metrics.size.panelWidth }
    var barHeight: CGFloat { metrics.size.compactHeight }
    var gap: CGFloat { metrics.spacing.md }
    var maxOutput: CGFloat { metrics.scaled(340) }
    var columns: Int { max(20, Int((width - Self.logInset.width * 2) / Self.characterWidth)) }
    var rowCap: Int { Int((maxOutput / Self.rowHeight).rounded(.up)) + 1 }
}
