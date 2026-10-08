import AppKit
import SwiftUI

/// Never key: a click on a chip must leave the palette's search field focused.
final class PaletteChipsPanel: NSPanel {
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .palette
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        // The glass draws its own edge; a window shadow would outline the transparent gaps.
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        let hosting = HostingView(rootView: rootView)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private final class HostingView<Content: View>: NSHostingView<Content> {
        override var acceptsFirstResponder: Bool { false }
        override var needsPanelToBecomeKey: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
