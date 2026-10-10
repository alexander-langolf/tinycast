import AppKit
import SwiftUI

/// One panel per instance: its level, its frame in the stack, and whether a drag took it out.
@MainActor
final class TerminalInstancesPresenter: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panels: [UUID: TerminalInstancePanel] = [:]
    /// Dragged panels leave the stack and keep growing down from where they were dropped.
    private var detached: Set<UUID> = []
    private var anchor: CGPoint?
    private var isTracking = false

    init(core: AppCore) {
        self.core = core
    }

    private var layout: TerminalInstanceMetrics {
        TerminalInstanceMetrics(metrics: core.settings.interfaceSize.metrics)
    }

    /// The newest instance goes on top at the palette's corner; the rest re-stack beneath it.
    func present(_ instance: TerminalInstance, anchor: CGPoint?) {
        self.anchor = anchor ?? self.anchor ?? defaultAnchor()
        let root = TerminalInstanceView(instance: instance)
            .environment(core.terminalInstances)
            .paletteEnvironment(core)
        let panel = TerminalInstancePanel(instanceID: instance.id, rootView: root)
        panel.delegate = self
        panel.onKey = { [weak self, weak instance] event in
            guard let self, let instance else { return false }
            return self.core.terminalInstances.handleKey(event, for: instance)
        }
        panels[instance.id] = panel
        applyPin(instance)
        place(animated: false)
        panel.makeKeyAndOrderFront(nil)
        if !isTracking {
            isTracking = true
            track()
        }
    }

    func dismiss(_ id: UUID) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        detached.remove(id)
        panel.delegate = nil
        panel.orderOut(nil)
        place(animated: true)
    }

    func applyPin(_ instance: TerminalInstance) {
        panels[instance.id]?.setPinned(instance.isPinned)
    }

    /// Heights follow the output; any change re-stacks, animated.
    private func track() {
        withObservationTracking {
            let layout = layout
            for instance in core.terminalInstances.instances { _ = instance.height(layout) }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.track()
                self.place(animated: true)
            }
        }
    }

    private func place(animated: Bool) {
        guard let anchor else { return }
        let layout = layout
        let slots = core.terminalInstances.instances.compactMap { instance -> TerminalInstanceStack.Slot? in
            guard let panel = panels[instance.id] else { return nil }
            let corner =
                detached.contains(instance.id) ? CGPoint(x: panel.frame.minX, y: panel.frame.maxY) : nil
            return TerminalInstanceStack.Slot(
                id: instance.id, height: instance.height(layout), detachedTopLeft: corner)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.primary
        let frames = TerminalInstanceStack.frames(
            for: slots, anchor: anchor, width: layout.width, gap: layout.gap,
            floorY: screen?.visibleFrame.minY ?? 0)
        for (id, frame) in frames {
            guard let panel = panels[id], panel.frame != frame else { continue }
            if animated, panel.isVisible {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = TerminalInstanceMetrics.restackDuration
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
        }
    }

    /// The palette's own default corner, for an instance opened while the palette was hidden.
    private func defaultAnchor() -> CGPoint {
        guard let screen = NSScreen.underCursor ?? NSScreen.primary else { return .zero }
        return PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: layout.width,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
    }

    // MARK: - NSWindowDelegate

    /// Only a press-and-drag detaches; the stack's own animated moves never do.
    func windowWillMove(_ notification: Notification) {
        guard let panel = notification.object as? TerminalInstancePanel,
            NSEvent.pressedMouseButtons & 1 == 1
        else { return }
        detached.insert(panel.instanceID)
    }
}
