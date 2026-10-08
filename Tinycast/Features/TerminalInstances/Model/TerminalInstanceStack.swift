import CoreGraphics
import Foundation

/// Where instance panels go: newest at the anchor, each one gap below the last.
enum TerminalInstanceStack {
    struct Slot: Equatable, Sendable {
        let id: UUID
        let height: CGFloat
        /// A dragged panel leaves the stack and grows down from its own top-left corner.
        let detachedTopLeft: CGPoint?
    }

    static let dividerHeight: CGFloat = 1

    /// AppKit coordinates (y up); `anchor` is the stack's top-left.
    static func frames(
        for slots: [Slot], anchor: CGPoint, width: CGFloat, gap: CGFloat, floorY: CGFloat
    ) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var top = anchor.y
        for slot in slots {
            if let corner = slot.detachedTopLeft {
                frames[slot.id] = CGRect(
                    x: corner.x, y: corner.y - slot.height, width: width, height: slot.height)
                continue
            }
            let y = max(top - slot.height, floorY)
            frames[slot.id] = CGRect(x: anchor.x, y: y, width: width, height: slot.height)
            top = y - gap
        }
        return frames
    }

    /// The bar alone, or the bar, a divider and the log up to `maxOutput`.
    static func cardHeight(
        barHeight: CGFloat, rows: Int, rowHeight: CGFloat, verticalInset: CGFloat, maxOutput: CGFloat
    ) -> CGFloat {
        guard rows > 0 else { return barHeight }
        return barHeight + dividerHeight + min(CGFloat(rows) * rowHeight + verticalInset * 2, maxOutput)
    }
}
