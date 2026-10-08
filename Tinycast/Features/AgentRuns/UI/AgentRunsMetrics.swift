import SwiftUI

struct AgentRunsMetrics {
    let metrics: InterfaceMetrics

    var sideWidth: CGFloat { metrics.scaled(360) }
    var statusDot: CGFloat { metrics.scaled(6) }
}
