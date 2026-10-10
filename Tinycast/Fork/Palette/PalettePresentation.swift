import CoreGraphics

/// How the expanded palette window presents one screen; a screen declares it, the shell obeys.
struct PalettePresentation: Equatable, Sendable {
    enum Height: Equatable, Sendable {
        /// The full window at its normal height.
        case standard
        /// The bar plus exactly `rows` result rows, capped at the standard height.
        case fitted(rows: Int)
    }

    enum Footer: Equatable, Sendable {
        case shown
        /// Gone from the window; ↵ still performs the primary action.
        case hidden
    }

    var height: Height = .standard
    var footer: Footer = .shown

    static let standard = PalettePresentation()

    static func fitted(rows: Int, footer: Footer = .shown) -> PalettePresentation {
        PalettePresentation(height: .fitted(rows: rows), footer: footer)
    }

    var showsFooter: Bool { footer == .shown }

    /// The expanded window's height. Compact keeps its own bar height and never asks.
    func windowHeight(metrics: InterfaceMetrics) -> CGFloat {
        let size = metrics.size
        switch height {
        case .standard:
            return size.panelHeight
        case .fitted(let rows):
            let rowsHeight = CGFloat(max(rows, 1)) * Self.rowHeight(metrics: metrics)
            let content = size.compactHeight + metrics.spacing.xs * 2 + rowsHeight
            return min(content + (showsFooter ? size.bottomBarHeight : 0), size.panelHeight)
        }
    }

    /// One result row of a fitted screen, so the window maths and the row view share a number.
    static func rowHeight(metrics: InterfaceMetrics) -> CGFloat {
        metrics.size.resultRowIcon + metrics.spacing.sm * 2
    }
}
