import SwiftUI

/// Variant A, "Grow": one glass card whose bar is the compact palette and whose log grows below.
struct TerminalInstanceView: View {
    @Bindable var instance: TerminalInstance
    @Environment(TerminalInstancesCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @FocusState private var fieldFocused: Bool

    private var session: TerminalSession { instance.session }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous)
        VStack(spacing: 0) {
            bar
            if instance.showsOutput, let run = session.run {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: TerminalInstanceStack.dividerHeight)
                if session.grid != nil {
                    GhosttyGridView(session: session)  // FORK: libghostty prototype
                } else {
                    TerminalLogView(run: run)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(shape)
        .overlay { shape.strokeBorder(borderColor, lineWidth: 1) }
        .onAppear { fieldFocused = true }
        .onChange(of: session.phase) { _, phase in
            if case .idle = phase { fieldFocused = true }
        }
    }

    private var bar: some View {
        HStack(spacing: metrics.spacing.lg) {
            statusGlyph
                .frame(width: metrics.size.headerIconSlot)
            commandArea
                .frame(maxWidth: .infinity, alignment: .leading)
            if session.isFullScreen {
                Text("Full-screen program · ⌘O opens kitty")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(1)
            }
            Text((session.directory as NSString).abbreviatingWithTildeInPath)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
            barButton(
                instance.isPinned ? "pin.fill" : "pin.slash",
                help: instance.isPinned ? "Unpin  ⌘P" : "Pin on Top  ⌘P"
            ) { coordinator.togglePinned(instance) }
            barButton("arrow.up.forward.app", help: "Open in kitty  ⌘O") { coordinator.openInKitty(instance) }
            barButton("xmark", help: "Close  ⌘W") { coordinator.close(instance) }
        }
        .padding(.horizontal, metrics.spacing.md * 2)
        .frame(height: metrics.size.compactHeight)
    }

    @ViewBuilder
    private var commandArea: some View {
        switch session.phase {
        case .starting where session.startupNotice != nil:
            Text(session.startupNotice ?? "")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .starting, .running:
            Text(instance.lastCommand)
                .font(metrics.typography.searchField.monospaced())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .ended:
            Text("Shell ended · ⌘W closes")
                .font(metrics.typography.searchField)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .idle:
            TextField("Next command", text: $instance.input)
                .textFieldStyle(.plain)
                .font(metrics.typography.searchField.monospaced())
                .focused($fieldFocused)
                .onSubmit { coordinator.submit(instance) }
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch session.phase {
        case .starting, .running:
            ProgressView().controlSize(.small)
        case .idle(let status?) where status != 0:
            Text(String(status))
                .font(metrics.typography.keyCap.monospacedDigit())
                .foregroundStyle(Theme.Colors.destructive)
        case .ended:
            Image(systemName: "powersleep")
                .font(metrics.typography.headerIcon)
                .foregroundStyle(Theme.Colors.textTertiary)
        case .idle:
            Image(systemName: "dollarsign")
                .font(metrics.typography.headerIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var borderColor: Color {
        switch session.phase {
        case .starting, .running: Color.accentColor.opacity(0.7)
        case .idle(let status?) where status != 0: Theme.Colors.destructive.opacity(0.6)
        case .idle, .ended: Theme.Colors.border
        }
    }

    private func barButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(metrics.typography.barSymbol)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
        .accessibilityLabel(help)
    }
}
