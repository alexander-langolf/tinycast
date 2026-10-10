import AppKit
import Observation
import SwiftUI

/// Shows the question cards at the top right of the active screen while any question is open.
@MainActor
final class AutomationQuestionPresenter {
    private unowned let core: AppCore
    private let store: AutomationQuestionStore
    private var panel: AutomationQuestionPanel?
    private var isTracking = false

    init(core: AppCore, store: AutomationQuestionStore) {
        self.core = core
        self.store = store
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true
        track()
        update()
    }

    func stop() {
        isTracking = false
        panel?.orderOut(nil)
        panel = nil
    }

    private func track() {
        guard isTracking else { return }
        withObservationTracking {
            _ = store.pending.count
            _ = core.settings.interfaceSize
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isTracking else { return }
                self.track()
                self.update()
            }
        }
    }

    private func update() {
        let count = min(store.pending.count, AutomationQuestionStack.cardLimit)
        guard count > 0, let screen = NSScreen.underCursor ?? NSScreen.primary else {
            panel?.orderOut(nil)
            return
        }
        let metrics = core.settings.interfaceSize.metrics
        let width = metrics.scaled(360)
        let panel =
            panel
            ?? AutomationQuestionPanel(
                rootView: AnyView(AutomationQuestionStack(store: store).paletteEnvironment(core)))
        self.panel = panel
        let height = panel.fittingHeight(width: width)
        let visible = screen.visibleFrame
        let margin = metrics.spacing.xl
        panel.setFrame(
            NSRect(
                x: visible.maxX - width - margin, y: visible.maxY - height - margin, width: width,
                height: height), display: true)
        panel.orderFrontRegardless()
    }
}
