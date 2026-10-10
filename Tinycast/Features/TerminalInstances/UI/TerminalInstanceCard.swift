import SwiftUI

/// What the card's buttons and return key do; previews pass the defaults.
struct TerminalInstanceActions {
    var submit: () -> Void = {}
    var togglePinned: () -> Void = {}
    var openInKitty: () -> Void = {}
    var close: () -> Void = {}
}

/// Variant A, "Grow": one glass card whose bar is the compact palette and whose log grows below.
/// Plain values in and a view builder for the output, so previews need no session, shell or libghostty.
struct TerminalInstanceCard<Output: View>: View {
    let phase: TerminalSessionPhase
    let command: String
    let directory: String
    let startupNotice: String?
    let isFullScreen: Bool
    let isPinned: Bool
    let showsOutput: Bool
    @Binding var input: String
    var actions = TerminalInstanceActions()
    @ViewBuilder let output: Output
    @Environment(\.metrics) private var metrics
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.panel, style: .continuous)
        VStack(spacing: 0) {
            bar
            if showsOutput {
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: TerminalInstanceStack.dividerHeight)
                output
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(shape)
        .overlay { shape.strokeBorder(borderColor, lineWidth: 1) }
        .onAppear { fieldFocused = true }
        .onChange(of: phase) { _, phase in
            if case .idle = phase { fieldFocused = true }
        }
    }

    private var bar: some View {
        HStack(spacing: metrics.spacing.lg) {
            statusGlyph
                .frame(width: metrics.size.headerIconSlot)
            commandArea
                .frame(maxWidth: .infinity, alignment: .leading)
            if isFullScreen {
                Text("Full-screen program · ⌘O opens kitty")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(1)
            }
            Text((directory as NSString).abbreviatingWithTildeInPath)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.head)
            barButton(
                isPinned ? "pin.fill" : "pin.slash",
                help: isPinned ? "Unpin  ⌘P" : "Pin on Top  ⌘P"
            ) { actions.togglePinned() }
            barButton("arrow.up.forward.app", help: "Open in kitty  ⌘O") { actions.openInKitty() }
            barButton("xmark", help: "Close  ⌘W") { actions.close() }
        }
        .padding(.horizontal, metrics.spacing.md * 2)
        .frame(height: metrics.size.compactHeight)
    }

    @ViewBuilder
    private var commandArea: some View {
        switch phase {
        case .starting where startupNotice != nil:
            Text(startupNotice ?? "")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .starting, .running:
            Text(command)
                .font(metrics.typography.searchField.monospaced())
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .ended:
            Text("Shell ended · ⌘W closes")
                .font(metrics.typography.searchField)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .idle:
            TextField("Next command", text: $input)
                .textFieldStyle(.plain)
                .font(metrics.typography.searchField.monospaced())
                .focused($fieldFocused)
                .onSubmit { actions.submit() }
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch phase {
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
        switch phase {
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
