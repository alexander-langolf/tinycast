import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class ForkAutocompleteGhostController {
    struct FallbackAnchor: Equatable {
        let rect: CGRect
        let isWindow: Bool
    }

    private var panel: ForkLyraPassivePanel?

    func show(_ suffix: String, at anchor: CGRect, rejected: (ForkEvent.Reason) -> Void) -> Bool {
        dismiss()
        guard !suffix.isEmpty else { rejected(.noCandidate); return false }
        guard anchor.height.isFinite, anchor.height > 0,
              anchor.origin.x.isFinite, anchor.origin.y.isFinite else { rejected(.noCaret); return false }
        let caret = ForkLyraSuggestionController.cocoaAnchor(
            anchor, mainHeight: NSScreen.screens.first?.frame.height ?? 0)
        let font = NSFont.systemFont(ofSize: min(22, max(9, anchor.height * 0.74)))
        let text = NSAttributedString(string: suffix, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        let width = ceil(text.size().width)
        let frame = CGRect(x: caret.minX, y: caret.minY, width: width, height: anchor.height)
        guard NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }) else {
            rejected(.offscreen)
            return false
        }
        let created = ForkLyraPassivePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        created.level = .floating
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.ignoresMouseEvents = true
        created.appearance = NSAppearance(named: ForkLyraSuggestionController.appearanceName(
            interfaceStyle: UserDefaults.standard.string(forKey: "AppleInterfaceStyle")))
        let view = GhostTextView(frame: CGRect(origin: .zero, size: frame.size))
        view.text = text
        view.setAccessibilityElement(false)
        created.contentView = view
        panel = created
        created.orderFrontRegardless()
        return true
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    static func fallbackAnchor(for snapshot: ForkLyraTextSnapshot) -> FallbackAnchor? {
        if let rect = frame(of: snapshot.element) { return FallbackAnchor(rect: rect, isWindow: false) }
        let window = ForkLyraFocusObserver.attribute(snapshot.element, kAXWindowAttribute)
            ?? ForkLyraFocusObserver.attribute(AXUIElementCreateApplication(snapshot.pid), kAXFocusedWindowAttribute)
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
              let rect = frame(of: window as! AXUIElement) else { return nil }
        return FallbackAnchor(rect: rect, isWindow: true)
    }

    func showFallback(prefix: String, suffix: String, at anchor: FallbackAnchor,
                      rejected: (ForkEvent.Reason) -> Void) -> Bool {
        dismiss()
        guard !suffix.isEmpty else { rejected(.noCandidate); return false }
        let bounds = ForkLyraSuggestionController.cocoaAnchor(
            anchor.rect, mainHeight: NSScreen.screens.first?.frame.height ?? 0)
        guard let screen = NSScreen.screens.filter({ $0.visibleFrame.intersects(bounds) }).max(by: {
            let left = $0.visibleFrame.intersection(bounds)
            let right = $1.visibleFrame.intersection(bounds)
            return left.width * left.height < right.width * right.height
        }) else { rejected(.offscreen); return false }
        let view = NSHostingView(rootView: FallbackChip(prefix: prefix, suffix: suffix))
        let size = view.fittingSize
        let visible = screen.visibleFrame.insetBy(dx: Theme.Spacing.xs, dy: Theme.Spacing.xs)
        guard size.width > 0, size.height > 0, size.width <= visible.width, size.height <= visible.height else {
            rejected(.offscreen)
            return false
        }
        let x = min(max(bounds.minX, visible.minX), visible.maxX - size.width)
        var y = bounds.minY - size.height - Theme.Spacing.xs
        if anchor.isWindow {
            y = max(bounds.minY, visible.minY) + Theme.Spacing.xs
        } else if y < visible.minY {
            y = bounds.maxY + Theme.Spacing.xs
        }
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        guard visible.contains(frame), anchor.isWindow ? bounds.contains(frame) : !frame.intersects(bounds) else {
            rejected(.offscreen)
            return false
        }
        let created = ForkLyraPassivePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        created.level = .floating
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.ignoresMouseEvents = true
        created.contentView = view
        panel = created
        created.orderFrontRegardless()
        return true
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = ForkLyraFocusObserver.attribute(element, kAXPositionAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              let dimensions = ForkLyraFocusObserver.attribute(element, kAXSizeAttribute),
              CFGetTypeID(dimensions) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(dimensions as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }

    private struct FallbackChip: View {
        let prefix: String
        let suffix: String

        var body: some View {
            HStack(spacing: 0) {
                Text(verbatim: prefix).foregroundStyle(Theme.Colors.textTertiary)
                Text(verbatim: suffix).foregroundStyle(Theme.Colors.textPrimary)
            }
            .font(Theme.Typography.chip)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .glassEffect(.regular, in: Capsule())
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private final class GhostTextView: NSView {
        var text = NSAttributedString(string: "")

        override func draw(_ dirtyRect: NSRect) { text.draw(at: .zero) }
    }
}
