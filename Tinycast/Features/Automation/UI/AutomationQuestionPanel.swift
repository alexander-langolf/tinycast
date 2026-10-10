import AppKit
import SwiftUI

/// Floats above other apps without taking key status, so an agent's question never steals typing.
final class AutomationQuestionPanel: NSPanel {
    private let hosting: HostingView<AnyView>

    init(rootView: AnyView) {
        hosting = HostingView(rootView: rootView)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = hosting
    }

    /// Height the cards need at this width: the text wraps, so height follows width.
    func fittingHeight(width: CGFloat) -> CGFloat {
        hosting.setFrameSize(NSSize(width: width, height: 10))
        return hosting.fittingSize.height
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private final class HostingView<Content: View>: NSHostingView<Content> {
        override var acceptsFirstResponder: Bool { false }
        override var needsPanelToBecomeKey: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
