import AppKit
import SwiftUI

/// The one editor panel: placed on the screen under the cursor, remembering the size it was left at.
@MainActor
final class MonacoEditorPresenter {
    private unowned let core: AppCore
    private var panel: MonacoEditorPanel?
    private var lastSize = NSSize(width: 920, height: 640)

    init(core: AppCore) {
        self.core = core
    }

    func present(_ session: MonacoEditorSession) {
        dismiss()
        let root = MonacoEditorView(session: session)
            .environment(core.monacoEditor)
            .paletteEnvironment(core)
        let panel = MonacoEditorPanel(rootView: root)
        panel.onKey = { [weak self] event in self?.core.monacoEditor.handleKey(event) ?? false }
        let visible = (NSScreen.underCursor ?? NSScreen.primary)?.visibleFrame ?? .zero
        let size = NSSize(
            width: min(lastSize.width, visible.width), height: min(lastSize.height, visible.height))
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.04,
                width: size.width, height: size.height),
            display: true)
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        guard let panel else { return }
        lastSize = panel.frame.size
        self.panel = nil
        panel.onKey = nil
        panel.orderOut(nil)
    }

    /// Raises the open panel and gives it key focus; the page takes focus back through the web view.
    func focus() {
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }
}
