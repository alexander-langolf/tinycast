import AppKit
import SwiftUI

// MenuPanel must become key for navigation; agent cards must never take the palette's key status.
final class AgentRunsPanel: NSPanel {
    weak var paletteState: PaletteState?

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
        level = .palette
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        let hosting = HostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .mouseMoved {
            paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        }
        super.sendEvent(event)
    }

    private final class HostingView<Content: View>: NSHostingView<Content> {
        override var acceptsFirstResponder: Bool { false }
        override var needsPanelToBecomeKey: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
