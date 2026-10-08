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
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}
