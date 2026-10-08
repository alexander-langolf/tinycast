import CoreGraphics
import Foundation

/// The pill leaves the compact bar's right end to the chips, so the pair spans the bar's width.
struct PaletteChipsLayout: Equatable, Sendable {
    let panelWidth: CGFloat
    let chipSide: CGFloat
    let gap: CGFloat

    var barWidth: CGFloat {
        let count = CGFloat(PaletteChip.allCases.count)
        return count * chipSide + (count - 1) * gap
    }

    var pillWidth: CGFloat { panelWidth - barWidth - gap }

    /// Beside the pill inside the bar's old width; beside an expanded palette, right else left.
    func chipsFrame(beside palette: CGRect, pill: Bool, visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: barWidth, height: chipSide)
        var x = palette.maxX + gap
        if !pill, x + size.width > visibleFrame.maxX { x = palette.minX - gap - size.width }
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)
        let y = min(max(palette.maxY - size.height, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
