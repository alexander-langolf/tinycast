import AppKit
import SwiftUI

/// Takes key without activating Tinycast, as the palette does, so typing works over any app.
final class TerminalInstancePanel: NSPanel {
    let instanceID: UUID
    /// The card's chords, checked before the field editor sees the key.
    var onKey: ((NSEvent) -> Bool)?

    init<Content: View>(instanceID: UUID, rootView: Content) {
        self.instanceID = instanceID
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { !isPinned }

    private(set) var isPinned = true

    /// Pinned: a floating, non-activating panel that works over any app. Unpinned: an ordinary
    /// managed window. Mission Control and the Dock only bring forward a window that can become main
    /// in an app that can activate; a non-activating panel at `.normal` is put back behind them.
    func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            styleMask.insert(.nonactivatingPanel)
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            level = .floating
        } else {
            styleMask.remove(.nonactivatingPanel)
            collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
            level = .normal
            if isVisible { orderFrontRegardless() }
        }
    }

    /// Backstop for a press while unpinned: raise just this panel and make it key.
    private func raiseAsOrdinaryWindow() {
        orderFrontRegardless()
        if !isKeyWindow { makeKey() }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        if event.type == .leftMouseDown || event.type == .rightMouseDown, level == .normal {
            raiseAsOrdinaryWindow()
        }
        super.sendEvent(event)
    }
}
