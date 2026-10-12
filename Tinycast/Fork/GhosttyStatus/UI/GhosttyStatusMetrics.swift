import SwiftUI

struct GhosttyStatusMetrics {
    let metrics: InterfaceMetrics
    var cards: AgentRunsMetrics { AgentRunsMetrics(metrics: metrics) }
    var inset: CGFloat { metrics.spacing.xxs }
    var gap: CGFloat { metrics.spacing.xs }
    var icon: CGFloat { metrics.size.menuIcon }
    var padding: CGFloat { min(cards.horizontalPadding, metrics.spacing.sm) }
    var launcherWidth: CGFloat { icon + metrics.spacing.sm * 2 }
    var overflowWidth: CGFloat { metrics.size.keyCap + metrics.spacing.sm * 2 }
    var cardWidth: CGFloat { cards.sideWidth / 3 }
    var rowHeight: CGFloat { max(icon, titleHeight) + metrics.spacing.sm * 2 }
    var overflowMaxHeight: CGFloat { metrics.size.menuRowsMaxHeight }
    var restingHeight: CGFloat { max(metrics.size.compactHeight / 2, titleHeight + inset * 4) }

    private var titleHeight: CGFloat {
        let font = cards.theme.nsFont(.agentCardTitleSize, style: .body, metrics)
        return ceil(font.ascender - font.descender + font.leading)
    }

    func fit(count: Int, width: CGFloat) -> GhosttyStatusLayout {
        GhosttyStatusLayout.fit(
            tabCount: count, width: max(0, width - inset * 2 - gap),
            launcherWidth: launcherWidth, cardWidth: cardWidth, overflowWidth: overflowWidth, gap: gap)
    }
}
