import AppKit
import SwiftUI

@MainActor
final class GhosttyStatusTooltipPresenter {
    private var task: Task<Void, Never>?
    private var panel: PersistentLauncherPanel?

    func hover(_ text: String?, anchor: CGRect, metrics: InterfaceMetrics) {
        hide()
        guard let text else { return }
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(Theme.Duration.tooltipDelay)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            let view = NSHostingView(rootView: Tile(text: text, metrics: metrics).forkAppearance())
            let size = view.fittingSize
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? anchor
            let window = PersistentLauncherPanel()
            window.ignoresMouseEvents = true
            window.contentView = view
            window.setFrame(
                CGRect(
                    x: min(max(anchor.midX - size.width / 2, screen.minX), screen.maxX - size.width),
                    y: max(screen.minY, anchor.minY - size.height - metrics.spacing.sm),
                    width: size.width, height: size.height), display: true)
            window.orderFrontRegardless()
            panel = window
        }
    }

    func hide() {
        task?.cancel()
        task = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    isolated deinit {
        task?.cancel()
        panel?.orderOut(nil)
    }

    private struct Tile: View {
        let text: String
        let metrics: InterfaceMetrics

        var body: some View {
            Text(text)
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.xs)
                .frame(minHeight: metrics.size.keyCap)
                .padding(metrics.spacing.xs)
                .background {
                    let shape = RoundedRectangle(cornerRadius: metrics.radius.tooltip)
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                    shape.fill(Theme.Colors.controlSurface)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: metrics.size.panelWidth / 2)
        }
    }
}

struct GhosttyStatusTooltip: ViewModifier {
    let text: String
    let hover: (String?, CGRect) -> Void
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                frame = $0
            }
            .onHover { hover($0 ? text : nil, frame) }
            .onDisappear { hover(nil, frame) }
    }
}
