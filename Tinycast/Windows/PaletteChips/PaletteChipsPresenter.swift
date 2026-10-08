import AppKit
import SwiftUI

/// The chips' child panel: beside the pill inside the bar's width, or beside an expanded palette.
@MainActor
final class PaletteChipsPresenter {
    private unowned let core: AppCore
    private var panel: PaletteChipsPanel?
    private weak var parent: NSWindow?
    private var resizeObserver: NotificationToken?

    init(core: AppCore) {
        self.core = core
    }

    func update() {
        guard core.paletteChips.isActive, let parent = core.paletteCoordinator.anchorView?.window,
            parent.isVisible, let screen = parent.screen
        else { return hide() }
        follow(parent)
        let metrics = core.settings.interfaceSize.metrics
        let frame = core.paletteChips.layout(metrics).chipsFrame(
            beside: parent.frame, pill: core.paletteCoordinator.paletteIsCollapsed,
            visibleFrame: screen.visibleFrame)
        let child = panel ?? makePanel()
        child.setFrame(frame, display: true)
        if child.parent !== parent { parent.addChildWindow(child, ordered: .above) }
        child.orderFront(nil)
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Typing widens the pill back to the bar; a resize moves the chips beside it.
    private func follow(_ window: NSWindow) {
        guard parent !== window else { return }
        parent = window
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        resizeObserver = NotificationToken(token, center: center)
    }

    private func makePanel() -> PaletteChipsPanel {
        let root = PaletteChipsBar()
            .environment(core.paletteChips)
            .paletteEnvironment(core)
        let panel = PaletteChipsPanel(rootView: root)
        self.panel = panel
        return panel
    }
}
