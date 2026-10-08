import AppKit
import Observation
import SwiftUI

@MainActor
final class AgentRunsPanelPresenter {
    private unowned let core: AppCore
    private weak var panel: NSPanel?
    private var agentRunsPanel: AgentRunsPanel?

    init(core: AppCore) {
        self.core = core
    }

    func observe(_ panel: NSPanel) {
        self.panel = panel
        trackAgentRuns()
    }

    private func trackAgentRuns() {
        withObservationTracking {
            _ = core.agentRunsCoordinator.runs.count
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.trackAgentRuns()
                self.update(self.panel, metrics: self.core.settings.interfaceSize.metrics)
            }
        }
    }

    func hide() {
        guard let agentRunsPanel else { return }
        panel?.removeChildWindow(agentRunsPanel)
        agentRunsPanel.orderOut(nil)
    }

    func update(_ panel: NSPanel?, metrics: InterfaceMetrics) {
        let count = core.agentRunsCoordinator.runs.count
        guard let panel, panel.isVisible, count > 0, let screen = panel.screen else {
            hide()
            return
        }
        let child: AgentRunsPanel
        if let agentRunsPanel {
            child = agentRunsPanel
        } else {
            child = AgentRunsPanel(rootView: AgentRunsStack().paletteEnvironment(core))
            child.paletteState = core.palette
            agentRunsPanel = child
        }
        let cards = min(count, AgentRunsStack.cardLimit)
        let rowHeight = metrics.size.rowIcon + metrics.spacing.sm * 2
        var height = CGFloat(cards) * rowHeight + CGFloat(cards - 1) * metrics.spacing.md
        if count > cards { height += metrics.spacing.md + metrics.size.barButtonHeight }
        let gap = metrics.spacing.xl
        let below = NSRect(
            x: panel.frame.minX, y: panel.frame.minY - gap - height,
            width: panel.frame.width, height: height)
        let frame: NSRect
        if screen.visibleFrame.contains(below) {
            frame = below
        } else {
            let width = AgentRunsMetrics(metrics: metrics).sideWidth
            let right = NSRect(
                x: panel.frame.maxX + gap, y: panel.frame.maxY - height,
                width: width, height: height)
            frame =
                screen.visibleFrame.contains(right)
                ? right
                : NSRect(
                    x: panel.frame.minX - gap - width, y: panel.frame.maxY - height,
                    width: width, height: height)
        }
        // Neither side fits: keep the stack on screen rather than half off it.
        let visible = screen.visibleFrame
        let clamped = NSRect(
            x: min(max(frame.minX, visible.minX), visible.maxX - frame.width),
            y: min(max(frame.minY, visible.minY), visible.maxY - frame.height),
            width: frame.width, height: frame.height)
        child.setFrame(clamped, display: true)
        child.contentView?.layoutSubtreeIfNeeded()
        child.invalidateShadow()
        if child.parent !== panel { panel.addChildWindow(child, ordered: .above) }
        child.orderFront(nil)
    }
}
