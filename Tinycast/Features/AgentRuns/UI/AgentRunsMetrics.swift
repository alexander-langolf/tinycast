import SwiftUI

struct AgentRunsMetrics {
    let metrics: InterfaceMetrics

    var sideWidth: CGFloat { metrics.scaled(360) }
    var statusDot: CGFloat { metrics.scaled(6) }
    /// Air above and below the two text lines, which otherwise touch the card's edges.
    var cardVerticalPadding: CGFloat { metrics.spacing.sm }
    /// One launcher row plus the vertical padding; the stack and the panel's frame both size from it.
    var cardHeight: CGFloat { metrics.size.rowIcon + metrics.spacing.sm * 2 + cardVerticalPadding * 2 }
}
