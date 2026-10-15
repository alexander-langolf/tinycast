import Foundation

struct NotchBackdropColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

enum NotchBackdrop {
    /// Where a screen-space range lands in a wallpaper drawn to fill the screen, centred.
    static func imageRange(
        screen: ClosedRange<Double>, screenAspect: Double, imageAspect: Double, horizontal: Bool
    ) -> ClosedRange<Double> {
        guard screenAspect > 0, imageAspect > 0 else { return screen }
        let visible = horizontal ? min(1, screenAspect / imageAspect) : min(1, imageAspect / screenAspect)
        let offset = (1 - visible) / 2
        return (offset + screen.lowerBound * visible)...(offset + screen.upperBound * visible)
    }

    /// Mean colour of a normalised box (y down) of an RGBA8 buffer, or nil for an empty box.
    static func average(
        rgba: [UInt8], width: Int, height: Int, x: ClosedRange<Double>, y: ClosedRange<Double>
    ) -> NotchBackdropColor? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        let columns =
            max(
                0, Int((x.lowerBound * Double(width)).rounded(.down)))..<min(
                width, max(Int((x.upperBound * Double(width)).rounded(.up)), 1))
        let rows =
            max(
                0, Int((y.lowerBound * Double(height)).rounded(.down)))..<min(
                height, max(Int((y.upperBound * Double(height)).rounded(.up)), 1))
        guard !columns.isEmpty, !rows.isEmpty else { return nil }
        var sums = (red: 0.0, green: 0.0, blue: 0.0)
        for row in rows {
            for column in columns {
                let index = (row * width + column) * 4
                sums.red += Double(rgba[index])
                sums.green += Double(rgba[index + 1])
                sums.blue += Double(rgba[index + 2])
            }
        }
        let count = Double(columns.count * rows.count) * 255
        return NotchBackdropColor(red: sums.red / count, green: sums.green / count, blue: sums.blue / count)
    }
}
